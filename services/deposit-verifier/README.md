# Deposit verifier

Draft only; not deployed or connected to the game.

The Worker checks direct native-ETH deposits on Base Mainnet (chain ID 8453), decodes the vault event, validates the sender and value, waits for confirmations, and stores a unique transaction/log record in D1.

The D1 table is an audit index only. The on-chain contract remains the balance source of truth. Configure the exact game origin, RPC URL, verified vault address and D1 database before testing. Do not use with real funds until the contract and verifier have been independently reviewed.