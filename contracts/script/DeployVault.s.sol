// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {SenderoSalvajeVault} from "../SenderoSalvajeVault.sol";

/// @notice Testnet-only deployment helper. Never use for mainnet deployment.
contract DeployVault is Script {
    function run() external returns (SenderoSalvajeVault vault) {
        require(block.chainid == 84532, "Base Sepolia only");
        uint256 deployerKey = vm.envUint("BASE_SEPOLIA_PRIVATE_KEY");
        address initialOwner = vm.envAddress("VAULT_INITIAL_OWNER");
        require(initialOwner != address(0), "owner is zero");

        vm.startBroadcast(deployerKey);
        vault = new SenderoSalvajeVault(initialOwner);
        vm.stopBroadcast();
    }
}
