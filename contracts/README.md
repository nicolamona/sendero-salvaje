# Sendero Salvaje Vault — design draft

**Status: NOT AUDITED. DO NOT DEPLOY OR USE WITH REAL ETH.**

This draft is isolated on `feature/base-mainnet-investments`. It is not wired into the game UI and has not been deployed. It must not be treated as production-ready smart-contract code.

## Intended network

- Base Mainnet chain ID: `8453` (`0x2105`).
- Native asset: ETH.
- Explorer: https://basescan.org
- RPC reference: https://docs.base.org/base-chain/api-reference/ethereum-json-rpc-api/eth_chainId

The deployment script must explicitly assert `block.chainid == 8453` before broadcasting a mainnet deployment. Test deployments must use a separate deployment configuration and test-only funds. Never copy a mainnet private key into a test environment.

## Accounting buckets

The contract maintains these independent categories:

1. **Available user balance** — deposited ETH not currently committed to an investment.
2. **Expedition principal** — ETH committed by players to an expedition that has not settled.
3. **Staked principal** — ETH locked until the recorded maturity timestamp.
4. **Staking reward reserve** — ETH explicitly funded by the owner for staking rewards. Each stake snapshots its reward; the contract reserves the full reward before accepting the position.
5. **Expedition reward reserve** — separately funded ETH plus expedition losses recycled into the pool. Payouts above a player's principal cannot exceed this reserve.

`accountedLiabilities()` sums the user liabilities and earmarked reserves. The contract checks that its ETH balance is at least this amount after accounting-changing operations. ETH forced into the contract outside normal calls may make the actual balance larger than accounted liabilities.

## Deposits and withdrawals

- A player calls `deposit()` with native ETH. Only `msg.sender` is credited.
- Direct transfers through `receive()` are rejected to avoid untracked deposits; users must call `deposit()`.
- `withdraw(amount, recipient)` can only spend the caller's available balance. It uses checks-effects-interactions and `ReentrancyGuard`.
- A pause blocks new deposits, new investments, funding and normal expedition settlement. It intentionally does not block available-balance withdrawals or matured staking withdrawals. During a pause, players can call `emergencyRefundExpedition(expeditionId)` to recover principal from an unsettled expedition without relying on the settlement operator.
- Deposits are not ERC-20 transfers; this contract accepts native ETH on Base Mainnet.

## Expeditions

- Each player can create one position per `bytes32 expeditionId`; IDs cannot be reused for that player.
- Starting an expedition moves principal from available balance to the expedition-principal category.
- An authorized settlement operator submits a payout. A payout can be lower than principal (loss), equal to principal, or higher only when enough expedition reward reserve exists.
- Losses are recycled to the expedition reward reserve. The event log records the player, expedition ID, principal and payout.

**Critical trust limitation:** in this draft, the settlement operator determines the payout. A compromised or dishonest operator could cause a player to lose their committed stake. Do not use this settlement model with real funds until a separately reviewed result-verification system is implemented. Production governance should use a properly configured multisig and consider a timelock, challenge window, caps and an auditable oracle or proof-based result system. A single EOA must not control settlement for a real-money economy.

## Staking

- Players choose an amount and a duration from 7 to 365 days.
- The reward rate is snapshotted at stake creation. Changing the rate affects only new stakes.
- The rate starts at zero and is capped in this draft at 2,000 basis points annualized (20% ceiling, not a promise or recommendation).
- Before a stake is accepted, its full calculated reward must be available in the funded reward reserve and is earmarked for that stake.
- Principal and reward return to the player's available balance only after maturity. No early-exit path exists in this draft.
- Rewards are not guaranteed by an external yield source; they are funded from ETH explicitly added to the contract's reward reserve. The UI must show the exact rate, term, calculated reward, unlock date, and the fact that reward funding is finite before the user confirms.

## Backend / blockchain verification requirements

The backend must treat blockchain events as the source of truth, not a client-side success message or local storage.

For every observed deposit:

1. Check the chain ID is `8453` and the contract address matches the verified deployed address configured server-side.
2. Fetch the transaction receipt from a trusted Base RPC and verify successful receipt status.
3. Decode the `Deposited(player, amount, newAvailableBalance)` event emitted by the expected contract address.
4. Verify the event's `player` equals the connected wallet and the amount is positive.
5. Wait for the application's chosen confirmation/finality policy before showing the deposit as finalized.
6. Store a unique idempotency key: `chainId + transactionHash + logIndex`. Reprocessing the same log must never credit a second time.
7. Reconcile the event against on-chain `availableBalance(player)` and the contract's accounting view. Handle reorganizations and RPC disagreement safely.
8. Never accept a tx hash alone as proof of deposit; never trust an amount or address supplied by the browser.

The backend does not need the player's private key and must never ask for seed phrases. If the game displays an indexed balance, it must remain a view of the contract state, not a second independent spendable ledger.

## Mandatory launch gates

Do not deploy with real funds until all of these are complete:

- Compile against a pinned Solidity compiler and pinned OpenZeppelin Contracts 5.x release.
- Unit tests for deposit/withdraw, failed transfers, reentrancy, pauses, emergency expedition refunds, accounting invariants, stake maturity, reward-reserve exhaustion, expedition settlement and duplicate IDs.
- Fuzz/invariant tests proving contract ETH balance never falls below accounted liabilities.
- Test with multiple wallets and mobile wallet connection flows.
- Independent review of the expedition settlement trust model and reward economics.
- External smart-contract security audit; remediate findings and publish the report.
- Verify source code on BaseScan and independently verify deployed address and constructor parameters.
- Use multisig governance, secure signer procedures, monitoring and a tested incident-response plan.
- Legal review of the real-money investment/reward model and its availability in target jurisdictions.
- A small, capped pilot only after the preceding gates are passed.

## Security references

- Base chain ID reference: https://docs.base.org/base-chain/api-reference/ethereum-json-rpc-api/eth_chainId
- OpenZeppelin security utilities (ReentrancyGuard and Pausable): https://docs.openzeppelin.com/contracts/5.x/api/utils
- OpenZeppelin preparation for mainnet: https://docs.openzeppelin.com/contracts/5.x/learn/preparing-for-mainnet
