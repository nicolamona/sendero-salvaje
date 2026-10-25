// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SenderoSalvajeVault} from "../contracts/SenderoSalvajeVault.sol";

contract SenderoSalvajeVaultTest is Test {
    SenderoSalvajeVault internal vault;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        vault = new SenderoSalvajeVault(address(this));
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function testDepositAndWithdrawAvailableBalance() public {
        vm.startPrank(alice);
        vault.deposit{value: 2 ether}();
        assertEq(vault.availableBalance(alice), 2 ether);
        vault.withdraw(0.75 ether, payable(alice));
        vm.stopPrank();

        assertEq(vault.availableBalance(alice), 1.25 ether);
        assertEq(vault.totalAvailableLiability(), 1.25 ether);
        assertTrue(vault.isSolvent());
    }

    function testStakingRequiresPreFundedRewardReserve() public {
        vm.prank(alice);
        vault.deposit{value: 1 ether}();
        vault.setStakingRewardBps(1_000);

        vm.prank(alice);
        vm.expectRevert(SenderoSalvajeVault.InsufficientRewardReserve.selector);
        vault.stake(1 ether, 365 days);
    }

    function testStakingMaturesAndPaysOnlyReservedReward() public {
        vault.fundStakingRewards{value: 1 ether}();
        vault.setStakingRewardBps(1_000);

        vm.prank(alice);
        vault.deposit{value: 1 ether}();
        vm.prank(alice);
        uint256 stakeId = vault.stake(1 ether, 365 days);

        (uint128 principal, uint128 reward,, uint64 unlockAt, bool withdrawn) =
            vault.stakePositions(alice, stakeId);
        assertEq(principal, 1 ether);
        assertEq(reward, 0.1 ether);
        assertFalse(withdrawn);

        vm.warp(unlockAt);
        vm.prank(alice);
        vault.withdrawStake(stakeId);

        assertEq(vault.availableBalance(alice), 1.1 ether);
        assertEq(vault.stakingRewardReserve(), 0.9 ether);
        assertEq(vault.reservedStakingRewards(), 0);
        assertTrue(vault.isSolvent());
    }

    function testExpeditionLossMovesToRewardReserve() public {
        bytes32 id = keccak256("forest-expedition-1");
        vm.prank(alice);
        vault.deposit{value: 1 ether}();
        vm.prank(alice);
        vault.startExpedition(id, 1 ether);

        vault.settleExpedition(alice, id, 0.4 ether);

        assertEq(vault.availableBalance(alice), 0.4 ether);
        assertEq(vault.totalExpeditionPrincipal(), 0);
        assertEq(vault.expeditionRewardReserve(), 0.6 ether);
        assertTrue(vault.isSolvent());
    }

    function testExpeditionCannotPayMoreThanPrincipalPlusFundedReserve() public {
        bytes32 id = keccak256("forest-expedition-2");
        vm.prank(alice);
        vault.deposit{value: 1 ether}();
        vm.prank(alice);
        vault.startExpedition(id, 1 ether);

        vm.expectRevert(SenderoSalvajeVault.InsufficientRewardReserve.selector);
        vault.settleExpedition(alice, id, 1.01 ether);
    }

    function testPlayerCanEmergencyRefundExpeditionWhilePaused() public {
        bytes32 id = keccak256("forest-expedition-pause");
        vm.prank(alice);
        vault.deposit{value: 1 ether}();
        vm.prank(alice);
        vault.startExpedition(id, 1 ether);

        vault.pause();
        vm.prank(alice);
        vault.emergencyRefundExpedition(id);

        assertEq(vault.availableBalance(alice), 1 ether);
        assertEq(vault.totalExpeditionPrincipal(), 0);
        assertTrue(vault.isSolvent());
    }

    function testExpeditionIdCannotBeReusedBySamePlayer() public {
        bytes32 id = keccak256("unique-expedition");
        vm.prank(alice);
        vault.deposit{value: 1 ether}();
        vm.prank(alice);
        vault.startExpedition(id, 1 ether);
        vault.settleExpedition(alice, id, 1 ether);

        vm.prank(alice);
        vm.expectRevert(SenderoSalvajeVault.PositionAlreadyExists.selector);
        vault.startExpedition(id, 1 ether);
    }

    function testFuzzAccountingNeverExceedsContractBalance(uint96 depositAmount) public {
        vm.assume(depositAmount > 0);
        vm.deal(alice, uint256(depositAmount));
        vm.prank(alice);
        vault.deposit{value: uint256(depositAmount)}();
        assertTrue(vault.isSolvent());
        assertGe(address(vault).balance, vault.accountedLiabilities());
    }
}
