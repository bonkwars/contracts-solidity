// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/HydraOpenzeppelin.sol";
import "../src/security/SecurityManager.sol";
import "../src/MemeDexFactory.sol";
import "../src/MemeAssetRegistry.sol";
import "../src/MemeCoinFactory.sol";


contract DeployHydra is Script {
    function run() external {
        // Retrieve private key from environment
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy contracts
        HydraOpenZeppelin hydra = new HydraOpenZeppelin();
        SecurityManager security = new SecurityManager(msg.sender);
        MemeAssetRegistry assetRegistry = new MemeAssetRegistry();
        MemeCoinFactory memeCoinFactory = new MemeCoinFactory(address(security), address(assetRegistry));
        MemeDexFactory dexFactory = new MemeDexFactory();

        // Log deployment addresses
        console.log("HydraOpenZeppelin deployed to:", address(hydra));
        console.log("SecurityManager deployed to:", address(security));
        console.log("MemeAssetRegistry deployed to:", address(assetRegistry));
        console.log("MemeCoinFactory deployed to:", address(memeCoinFactory));
        console.log("MemeDexFactory deployed to:", address(dexFactory));

        // Write deployment addresses to file
        string memory addresses = string(abi.encodePacked(
            "HYDRA_ADDRESS=", vm.toString(address(hydra)), "\n",
            "SECURITY_MANAGER_ADDRESS=", vm.toString(address(security)), "\n",
            "MEME_ASSET_REGISTRY_ADDRESS=", vm.toString(address(assetRegistry)), "\n",
            "MEME_COIN_FACTORY_ADDRESS=", vm.toString(address(memeCoinFactory)), "\n",
            "MEME_DEX_FACTORY_ADDRESS=", vm.toString(address(dexFactory))
        ));
        vm.writeFile(".env", addresses);

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
