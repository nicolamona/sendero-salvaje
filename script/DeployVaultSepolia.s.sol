// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {SenderoSalvajeVault} from "../contracts/SenderoSalvajeVault.sol";

/// @notice Explicitly testnet-only deployment helper. Never run with a mainnet RPC/key.
contract DeployVaultSepolia is Script {
    function run() external returns (SenderoSalvajeVault vault) {
        require(block.chainid == 84532, "Base Sepolia only");
        uint256 deployerKey = vm.envUint("BASE_SEPOLIA_PRIVATE_KEY");
        address initialOwner = vm.envAddress("VAULT_INITIAL_OWNER");
        require(initialOwner != address(0), "Owner cannot be zero");

        vm.startBroadcast(deployerKey);
        vault = new SenderoSalvajeVault(initialOwner);
        vm.stopBroadcast();

        console2.log("Base Sepolia vault:", address(vault));
        console2.log("Initial owner:", initialOwner);
        console2.log("Settlement quorum:", vault.settlementQuorum());
    }
}
