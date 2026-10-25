// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/*
 * Sendero Salvaje — DRAFT ONLY, NOT AUDITED, DO NOT DEPLOY WITH REAL FUNDS.
 *
 * Uses OpenZeppelin Contracts 5.x:
 *   @openzeppelin/contracts/access/Ownable2Step.sol
 *   @openzeppelin/contracts/utils/ReentrancyGuard.sol
 *   @openzeppelin/contracts/utils/Pausable.sol
 *
 * Design goals:
 * - Native ETH deposits credited to the sending wallet.
 * - Available balance, expedition principal, staking principal and reward
 *   reserves accounted separately.
 * - User withdrawals use checks-effects-interactions and reentrancy protection.
 * - Expedition settlement is explicit and auditable, but the settlement operator
 *   is trusted in this draft and can determine the payout. This is NOT production
 *   safe until the settlement/oracle governance model is independently reviewed.
 * - Staking rewards are not guaranteed: they can only be reserved if pre-funded.
 */
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract SenderoSalvajeVault is Ownable2Step, ReentrancyGuard, Pausable {
    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant YEAR = 365 days;
    uint256 public constant MIN_STAKING_DURATION = 7 days;
    uint256 public constant MAX_STAKING_DURATION = 365 days;
    uint16 public constant MAX_STAKING_REWARD_BPS = 2_000; // 20% APR ceiling, not a promise.

    enum ExpeditionOutcome { Loss, Refund, Win }

    struct ExpeditionPosition {
        uint128 principal;
        uint64 startedAt;
        bool exists;
        bool settled;
    }

    struct StakePosition {
        uint128 principal;
        uint128 reward;
        uint64 startedAt;
        uint64 unlockAt;
        bool withdrawn;
    }

    // User liabilities are tracked by category so the solvency invariant can be checked.
    mapping(address => uint256) public availableBalance;
    uint256 public totalAvailableLiability;
    uint256 public totalExpeditionPrincipal;
    uint256 public totalStakedPrincipal;

    // Reward reserves are contract liabilities earmarked for future player payouts.
    uint256 public stakingRewardReserve;
    uint256 public reservedStakingRewards;
    uint256 public expeditionRewardReserve;

    mapping(address => bool) public settlementSigners;
    uint8 public settlementQuorum;
    mapping(bytes32 => mapping(address => uint8)) public expeditionSignerVote;
    mapping(bytes32 => mapping(uint8 => uint8)) public expeditionOutcomeVotes;
    uint16 public stakingRewardBps; // New positions only. Defaults to zero.
    uint16 public expeditionWinRewardBps; // Fixed, pre-funded reward rate for winning expeditions.

    mapping(address => mapping(bytes32 => ExpeditionPosition)) public expeditionPositions;
    mapping(address => uint256) public nextStakeId;
    mapping(address => mapping(uint256 => StakePosition)) public stakePositions;

    event Deposited(address indexed player, uint256 amount, uint256 newAvailableBalance);
    event Withdrawn(address indexed player, address indexed recipient, uint256 amount);
    event ExpeditionFunded(address indexed funder, uint256 amount, uint256 newReserve);
    event ExpeditionStarted(address indexed player, bytes32 indexed expeditionId, uint256 stake);
    event ExpeditionSettled(address indexed player, bytes32 indexed expeditionId, uint256 stake, uint256 payout, address indexed operator);
    event ExpeditionLossRecycled(address indexed player, bytes32 indexed expeditionId, uint256 amount, uint256 newReserve);
    event ExpeditionEmergencyRefunded(address indexed player, bytes32 indexed expeditionId, uint256 principal);
    event StakingRewardsFunded(address indexed funder, uint256 amount, uint256 newReserve);
    event StakingRewardRateChanged(uint16 oldBps, uint16 newBps);
    event ExpeditionWinRewardRateChanged(uint16 oldBps, uint16 newBps);
    event StakingStarted(address indexed player, uint256 indexed stakeId, uint256 principal, uint256 reward, uint64 unlockAt);
    event StakingWithdrawn(address indexed player, uint256 indexed stakeId, uint256 principal, uint256 reward);
    event SettlementSignerChanged(address indexed signer, bool enabled);
    event SettlementQuorumChanged(uint8 oldQuorum, uint8 newQuorum);
    event ExpeditionOutcomeApproved(address indexed player, bytes32 indexed expeditionId, ExpeditionOutcome outcome, address indexed signer, uint8 approvals);
    event EmergencyPause(address indexed by);
    event EmergencyUnpause(address indexed by);

    error ZeroAmount();
    error InsufficientAvailableBalance();
    error InvalidRecipient();
    error InvalidExpedition();
    error PositionAlreadyExists();
    error PositionNotActive();
    error InvalidPayout();
    error UnauthorizedSettlementOperator();
    error DuplicateOrConflictingVote();
    error QuorumNotReached();
    error InvalidQuorum();
    error InvalidDuration();
    error StakeNotMatured();
    error StakeAlreadyWithdrawn();
    error InsufficientRewardReserve();
    error RewardRateTooHigh();
    error TransferFailed();
    error InsolventAccounting();

    constructor(address initialOwner) Ownable(initialOwner) {
        if (initialOwner == address(0)) revert InvalidRecipient();
        settlementSigners[initialOwner] = true;
        _settlementSignerList.push(initialOwner);
        settlementQuorum = 2;
    }

    /// @notice Deposit native ETH; credited only to msg.sender.
    function deposit() external payable nonReentrant whenNotPaused {
        if (msg.value == 0) revert ZeroAmount();
        availableBalance[msg.sender] += msg.value;
        totalAvailableLiability += msg.value;
        emit Deposited(msg.sender, msg.value, availableBalance[msg.sender]);
        _assertSolvent();
    }

    /// @notice Withdraw only the caller's uncommitted available balance.
    /// @dev Available-balance withdrawals remain enabled during an emergency pause.
    function withdraw(uint256 amount, address payable recipient) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        if (recipient == address(0)) revert InvalidRecipient();
        if (availableBalance[msg.sender] < amount) revert InsufficientAvailableBalance();

        availableBalance[msg.sender] -= amount;
        totalAvailableLiability -= amount;
        (bool ok,) = recipient.call{value: amount}("");
        if (!ok) revert TransferFailed();

        emit Withdrawn(msg.sender, recipient, amount);
        _assertSolvent();
    }

    /// @notice Fund the separate expedition reward pool. This does not credit a player balance.
    function fundExpeditionRewards() external payable onlyOwner whenNotPaused {
        if (msg.value == 0) revert ZeroAmount();
        expeditionRewardReserve += msg.value;
        emit ExpeditionFunded(msg.sender, msg.value, expeditionRewardReserve);
        _assertSolvent();
    }

    /// @notice Commit available balance to one unique expedition ID for this player.
    function startExpedition(bytes32 expeditionId, uint256 amount) external whenNotPaused {
        if (expeditionId == bytes32(0) || amount == 0) revert InvalidExpedition();
        if (amount > type(uint128).max) revert InvalidExpedition();
        if (expeditionPositions[msg.sender][expeditionId].exists) revert PositionAlreadyExists();
        if (availableBalance[msg.sender] < amount) revert InsufficientAvailableBalance();

        availableBalance[msg.sender] -= amount;
        totalAvailableLiability -= amount;
        totalExpeditionPrincipal += amount;
        expeditionPositions[msg.sender][expeditionId] = ExpeditionPosition({
            principal: uint128(amount),
            startedAt: uint64(block.timestamp),
            exists: true,
            settled: false
        });

        emit ExpeditionStarted(msg.sender, expeditionId, amount);
        _assertSolvent();
    }

    /// @notice Independent configured signers approve the same result before it can be settled.
    /// @dev This on-chain quorum reduces single-key risk, but signer governance still requires independent review.
    function approveExpeditionOutcome(address player, bytes32 expeditionId, ExpeditionOutcome outcome)
        external
        whenNotPaused
    {
        if (!settlementSigners[msg.sender]) revert UnauthorizedSettlementOperator();
        ExpeditionPosition storage position = expeditionPositions[player][expeditionId];
        if (!position.exists || position.settled) revert PositionNotActive();
        bytes32 key = keccak256(abi.encode(player, expeditionId));
        uint8 vote = uint8(outcome) + 1;
        if (expeditionSignerVote[key][msg.sender] != 0) revert DuplicateOrConflictingVote();
        expeditionSignerVote[key][msg.sender] = vote;
        uint8 approvals = ++expeditionOutcomeVotes[key][vote];
        emit ExpeditionOutcomeApproved(player, expeditionId, outcome, msg.sender, approvals);
    }

    /// @notice Settle only after the configured quorum approved the exact same outcome.
    function settleExpedition(address player, bytes32 expeditionId, ExpeditionOutcome outcome)
        external
        whenNotPaused
    {
        bytes32 key = keccak256(abi.encode(player, expeditionId));
        uint8 vote = uint8(outcome) + 1;
        if (expeditionOutcomeVotes[key][vote] < settlementQuorum) revert QuorumNotReached();
        ExpeditionPosition storage position = expeditionPositions[player][expeditionId];
        if (!position.exists || position.settled) revert PositionNotActive();

        uint256 principal = position.principal;
        uint256 payout;
        if (outcome == ExpeditionOutcome.Loss) {
            // A loss forfeits principal into the separate expedition reward reserve.
            expeditionRewardReserve += principal;
            emit ExpeditionLossRecycled(player, expeditionId, principal, expeditionRewardReserve);
        } else if (outcome == ExpeditionOutcome.Refund) {
            payout = principal;
        } else if (outcome == ExpeditionOutcome.Win) {
            uint256 reward = (principal * uint256(expeditionWinRewardBps)) / BPS_DENOMINATOR;
            if (reward > expeditionRewardReserve) revert InsufficientRewardReserve();
            expeditionRewardReserve -= reward;
            payout = principal + reward;
        } else {
            revert InvalidPayout();
        }

        position.settled = true;
        totalExpeditionPrincipal -= principal;
        totalAvailableLiability += payout;
        availableBalance[player] += payout;

        emit ExpeditionSettled(player, expeditionId, principal, payout, msg.sender);
        _assertSolvent();
    }

    /// @notice During an emergency pause, let a player cancel an unsettled expedition and recover principal.
    /// @dev This escape hatch does not depend on the settlement operator and pays no expedition reward.
    function emergencyRefundExpedition(bytes32 expeditionId) external whenPaused {
        ExpeditionPosition storage position = expeditionPositions[msg.sender][expeditionId];
        if (!position.exists || position.settled) revert PositionNotActive();

        uint256 principal = position.principal;
        position.settled = true;
        totalExpeditionPrincipal -= principal;
        totalAvailableLiability += principal;
        availableBalance[msg.sender] += principal;

        emit ExpeditionEmergencyRefunded(msg.sender, expeditionId, principal);
        _assertSolvent();
    }

    /// @notice Add ETH to the separate staking rewards reserve.
    function fundStakingRewards() external payable onlyOwner whenNotPaused {
        if (msg.value == 0) revert ZeroAmount();
        stakingRewardReserve += msg.value;
        emit StakingRewardsFunded(msg.sender, msg.value, stakingRewardReserve);
        _assertSolvent();
    }

    /// @notice Configure a fixed reward percentage for future winning expeditions.
    /// @dev This does not verify game outcomes; settlement authority still requires redesign before mainnet.
    function setExpeditionWinRewardBps(uint16 newBps) external onlyOwner whenNotPaused {
        if (newBps > MAX_STAKING_REWARD_BPS) revert RewardRateTooHigh();
        uint16 old = expeditionWinRewardBps;
        expeditionWinRewardBps = newBps;
        emit ExpeditionWinRewardRateChanged(old, newBps);
    }

    /// @notice Set rate for future stakes only; rate is snapshotted into each stake's reward.
    /// @dev 0 = no yield. Any nonzero rate must be backed by reserve at stake time.
    function setStakingRewardBps(uint16 newBps) external onlyOwner whenNotPaused {
        if (newBps > MAX_STAKING_REWARD_BPS) revert RewardRateTooHigh();
        uint16 old = stakingRewardBps;
        stakingRewardBps = newBps;
        emit StakingRewardRateChanged(old, newBps);
    }

    /// @notice Lock part of the player's available balance for a fixed term.
    /// @dev Rewards are calculated from a displayed, snapshotted simple annualized rate
    ///      and can only be reserved from ETH previously deposited into the reward pool.
    function stake(uint256 amount, uint64 duration) external whenNotPaused returns (uint256 stakeId) {
        if (amount == 0) revert ZeroAmount();
        if (amount > type(uint128).max) revert InvalidDuration();
        if (duration < MIN_STAKING_DURATION || duration > MAX_STAKING_DURATION) revert InvalidDuration();
        if (availableBalance[msg.sender] < amount) revert InsufficientAvailableBalance();

        uint256 reward = (amount * uint256(stakingRewardBps) * uint256(duration)) / (BPS_DENOMINATOR * YEAR);
        if (reward > stakingRewardReserve - reservedStakingRewards) revert InsufficientRewardReserve();
        if (reward > type(uint128).max) revert InvalidDuration();

        availableBalance[msg.sender] -= amount;
        totalAvailableLiability -= amount;
        totalStakedPrincipal += amount;
        reservedStakingRewards += reward;

        stakeId = nextStakeId[msg.sender]++;
        uint64 unlockAt = uint64(block.timestamp + duration);
        stakePositions[msg.sender][stakeId] = StakePosition({
            principal: uint128(amount),
            reward: uint128(reward),
            startedAt: uint64(block.timestamp),
            unlockAt: unlockAt,
            withdrawn: false
        });

        emit StakingStarted(msg.sender, stakeId, amount, reward, unlockAt);
        _assertSolvent();
    }

    /// @notice Return matured principal and its pre-reserved reward to the player's available balance.
    /// @dev Can be called while paused so a pause does not trap matured staking positions.
    function withdrawStake(uint256 stakeId) external nonReentrant {
        StakePosition storage position = stakePositions[msg.sender][stakeId];
        if (position.principal == 0 || position.withdrawn) revert StakeAlreadyWithdrawn();
        if (block.timestamp < position.unlockAt) revert StakeNotMatured();

        uint256 principal = position.principal;
        uint256 reward = position.reward;
        position.withdrawn = true;

        totalStakedPrincipal -= principal;
        stakingRewardReserve -= reward;
        reservedStakingRewards -= reward;
        uint256 payout = principal + reward;
        totalAvailableLiability += payout;
        availableBalance[msg.sender] += payout;

        emit StakingWithdrawn(msg.sender, stakeId, principal, reward);
        _assertSolvent();
    }

    /// @notice Configure a settlement signer. Quorum must remain achievable after changes.
    function setSettlementSigner(address signer, bool enabled) external onlyOwner {
        if (signer == address(0)) revert InvalidRecipient();
        if (!enabled && settlementSigners[signer] && settlementQuorum > 1) {
            // Count enabled signers to prevent silently configuring an impossible quorum.
            uint256 count = 0;
            // The owner-managed signer set is intentionally capped to keep this count bounded.
            for (uint256 i = 0; i < _settlementSignerList.length; i++) {
                if (settlementSigners[_settlementSignerList[i]] && _settlementSignerList[i] != signer) count++;
            }
            if (count < settlementQuorum) revert InvalidQuorum();
        }
        if (enabled && !settlementSigners[signer]) {
            if (_settlementSignerList.length >= 16) revert InvalidQuorum();
            _settlementSignerList.push(signer);
        }
        settlementSigners[signer] = enabled;
        emit SettlementSignerChanged(signer, enabled);
    }

    address[] private _settlementSignerList;

    function setSettlementQuorum(uint8 newQuorum) external onlyOwner {
        uint256 count = 0;
        for (uint256 i = 0; i < _settlementSignerList.length; i++) {
            if (settlementSigners[_settlementSignerList[i]]) count++;
        }
        if (newQuorum < 2 || newQuorum > count) revert InvalidQuorum();
        uint8 old = settlementQuorum;
        settlementQuorum = newQuorum;
        emit SettlementQuorumChanged(old, newQuorum);
    }

    /// @notice Emergency stop for deposits, new investments, funding and settlements.
    /// Available withdrawals and matured staking withdrawals remain available.
    function pause() external onlyOwner {
        _pause();
        emit EmergencyPause(msg.sender);
    }

    function unpause() external onlyOwner {
        _unpause();
        emit EmergencyUnpause(msg.sender);
    }

    /// @notice Current accounted liabilities across users and earmarked reward pools.
    function accountedLiabilities() public view returns (uint256) {
        return totalAvailableLiability
            + totalExpeditionPrincipal
            + totalStakedPrincipal
            + stakingRewardReserve
            + expeditionRewardReserve;
    }

    /// @notice Diagnostic solvency check; forced ETH may make balance greater than liabilities.
    function isSolvent() external view returns (bool) {
        return address(this).balance >= accountedLiabilities();
    }

    function _assertSolvent() internal view {
        if (address(this).balance < accountedLiabilities()) revert InsolventAccounting();
    }

    // Intentionally reject untracked direct transfers. Use deposit() for player deposits
    // or the explicit funding functions for reward reserves.
    receive() external payable {
        revert("Use deposit or reward funding");
    }

    fallback() external payable {
        revert("Unsupported call");
    }
}
