# Base Sepolia end-to-end runbook

This is a **testnet-only** procedure. Do not use mainnet keys or real ETH.

## Preconditions
- Install Foundry locally.
- Obtain Base Sepolia test ETH from a reputable faucet.
- Use a fresh test wallet; never paste seed phrases/private keys into GitHub, chat, or source files.
- Have two independently controlled test signer addresses available. The draft starts with the deployer as signer and quorum 2.

## Deploy the vault
From the repository root, configure environment variables locally:
- `BASE_SEPOLIA_PRIVATE_KEY`: test-only deployer private key.
- `VAULT_INITIAL_OWNER`: address that will own/configure the vault.

Then run:

```sh
forge install OpenZeppelin/openzeppelin-contracts@v5.4.0 --no-commit
forge install foundry-rs/forge-std@v1.9.7 --no-commit
forge test -vvv
forge script script/DeployVaultSepolia.s.sol:DeployVaultSepolia --rpc-url "$BASE_SEPOLIA_RPC_URL" --broadcast
```

The script explicitly reverts unless chain ID is 84532 (Base Sepolia). Keep the key in a local environment or secret manager; never commit an `.env` file.

## Required end-to-end checks
1. Verify the deployment transaction and contract bytecode on Base Sepolia explorer.
2. Configure a second independent settlement signer and confirm quorum is 2.
3. Deposit test ETH from wallet A; verify the `Deposited` event and credited balance.
4. Submit the deposit transaction hash to the verifier; verify receipt, destination, selector, wallet, amount, event, confirmations and canonical block hash.
5. Submit the same transaction/log twice; the second request must be idempotent and must not credit twice.
6. Test wrong chain, failed receipt, wrong destination, wrong wallet, mismatched amount, insufficient confirmations and a simulated/reorged block.
7. Approve one expedition outcome from signer A only and confirm settlement fails; approve the same outcome from signer B and confirm settlement succeeds.
8. Confirm a conflicting outcome cannot be approved by a signer who already voted.
9. Fund the expedition and staking reward reserves independently; verify one pool cannot subsidize the other.
10. Withdraw a deposit, complete a matured stake, pause the contract and verify recovery paths.
11. Record deployed address, deployment transaction, bytecode verification, Worker version, D1 migration/version, test results and monitoring alerts.

## Not automated / still blocked
This repository branch does not itself provide an RPC secret, funded signer, deployed Worker, production D1 database or deployment credentials. The script does not deploy itself. Do not switch to Base Mainnet until the full runbook passes and independent security review approves the signer governance, game-result integrity, accounting and recovery paths.
