# Sendero Salvaje — Base Mainnet readiness gate

**Status: BLOCKED — do not deploy with real funds.** This document is a checklist, not evidence of deployment or audit.

## Current verified state

- Target chain: Base Mainnet, chain ID `8453`.
- The vault and deposit verifier are drafts.
- The deposit verifier's automated suite has 8 mocked-RPC tests and TypeScript typechecking; these are not a live-chain test.
- No verified mainnet vault address, live deposit, live withdrawal, or production Cloudflare Worker is recorded here.
- The vault's expedition settlement operator can choose a player's payout. This trust assumption is unacceptable for production funds without a reviewed, constrained settlement mechanism.

## Required gates before mainnet

1. **Redesign expedition settlement.** Use a verifiable game result, constrained payout rules, or a reviewed dispute/multisig design. Do not let one hot operator freely choose payout amounts.
2. **Independent security review.** Review accounting invariants, reward reserve solvency, pause/recovery paths, access control, reentrancy, rounding, griefing, and all state transitions. Unit tests alone are not an audit.
3. **Testnet end-to-end.** Deploy a fresh vault to Base Sepolia; verify source and constructor arguments; exercise deposits, partial/full withdrawals, expedition wins/losses/refunds, staking lock maturity, reward exhaustion, pause/unpause, duplicate verifier requests, failed transactions, and reorg reconciliation.
4. **Reorg-safe verifier.** Add scheduled reconciliation and monitoring. Keep the indexer as an audit/index only; the contract remains the source of truth.
5. **Production infrastructure.** Create a dedicated production D1 database and Worker, restrict CORS to the real game origin, configure a reliable Base RPC, rate limits, alerts, and backups. Never reuse testnet resources.
6. **Key security.** Use a dedicated deployer and a hardware wallet or multisig for ownership; keep private keys only in a secure local secret manager or an explicitly configured CI secret. Never paste keys or seed phrases into chat or commit them to Git.
7. **Mainnet deployment and verification.** Only after all prior gates pass: deploy to chain ID 8453, record transaction hash and address, verify source/constructor args on a block explorer, transfer ownership to the reviewed multisig, and confirm pause/withdrawal procedures.
8. **Limited launch.** Start with deposits disabled in the game UI; test with a small, explicitly approved amount, reconcile the event against the indexer, verify withdrawal, then enable broader access only after checks pass.

## Safe deployment policy

- Never deploy this draft to mainnet simply by changing `CHAIN_ID`.
- Never expose a deposit button until the configured vault address has verified bytecode on the intended chain and the verifier's chain ID/address/origin are pinned.
- Never report a deployment as complete without an on-chain transaction hash and verified contract address.
- Never promise staking returns. Rewards must be fully pre-funded and clearly disclosed.
- Never use player principal to pay staking rewards or expedition rewards.

## Current decision

**Mainnet deployment is not authorized by technical readiness.** Proceed with code review and testnet validation; do not accept real ETH until the blockers above are resolved.
