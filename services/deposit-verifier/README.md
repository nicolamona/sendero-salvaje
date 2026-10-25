# Sendero Salvaje — deposit verifier (Base Sepolia test draft)

**Not deployed or connected to the game. Do not use with real funds.**

The Worker can be configured for Base Mainnet (8453) or Base Sepolia (84532); this repository's Wrangler template is explicitly configured for **Base Sepolia only** with a five-confirmation test threshold. The server must have an exact vault address, RPC URL, game origin and D1 binding before it will verify anything.

## Checks

- Check the configured chain ID and that the configured vault has bytecode.
- Require a successful receipt for a direct call to the configured vault's `deposit()` method.
- Decode exactly one `Deposited(player, amount, newAvailableBalance)` event emitted by that vault; match `player` to the submitted wallet and require a positive amount.
- Verify transaction value equals the event amount, check the receipt block hash against the canonical block and wait for the configured confirmation threshold.
- Store `chain_id + tx_hash + log_index` as a unique key so retries cannot create duplicate records.
- Derive the amount from the decoded event, never from browser-supplied data.

## Testnet setup (not performed here)

1. Install Foundry and dependencies in the repository.
2. Fund a dedicated test wallet with Base Sepolia test ETH. Never use a mainnet key or real funds.
3. Set `BASE_SEPOLIA_PRIVATE_KEY` and `VAULT_INITIAL_OWNER` locally as environment variables; do not commit either value.
4. Deploy from the repository root with `forge script contracts/script/DeployVault.s.sol:DeployVault --rpc-url "$BASE_SEPOLIA_RPC_URL" --broadcast`. The script refuses to deploy unless chain ID is 84532.
5. Verify the testnet contract address, then configure `VAULT_ADDRESS`, `BASE_RPC_URL`, `GAME_ORIGIN`, `CHAIN_ID=84532` and a dedicated D1 database.
6. Apply the D1 migration and run `npm test` and `npm run typecheck`.
7. Test a real testnet deposit, wrong wallet, failed transaction, duplicate verification and a reorg scenario before any UI integration.

## Architecture boundary

The D1 table is an audit/index only, never a spendable balance ledger. The on-chain contract remains the balance source of truth. The verifier must not trigger payouts or trust client success messages.

## Remaining gates

- Deploying the test contract and configuring Cloudflare require account access and a funded test wallet; these steps have not been performed by this change.
- Add scheduled reorg reconciliation, request rate limiting, monitoring and alerting.
- Independently review/audit the contract and redesign the expedition settlement trust model before considering Base Mainnet.
