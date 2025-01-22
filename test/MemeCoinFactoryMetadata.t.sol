// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/MemeCoinFactory.sol";
import "../src/MemeCoin.sol";
import "../src/security/AntiRugPull.sol";
import "../src/MemeAssetRegistry.sol";

contract MemeCoinFactoryMetadataTest is Test {
    MemeCoinFactory public factory;
    AntiRugPull public antiRugPull;
    MemeAssetRegistry public assetRegistry;
    address public owner;
    
    function setUp() public {
        owner = address(this);
        antiRugPull = new AntiRugPull(owner);
        assetRegistry = new MemeAssetRegistry();
        factory = new MemeCoinFactory(address(antiRugPull), address(assetRegistry));
    }
    
    function testMetadataValidation() public {
        string memory name = "Test Meme";
        string memory symbol = "TMEME";
        string memory imageUri = "https://example.com/image.png";
        string memory description = "Test Meme Coin Description";
        uint256 initialSupply = 1000000 * 10**18;
        uint256 salt = 123;

        // Test valid metadata
        address memeCoin = factory.createMemeCoin(
            name,
            symbol,
            imageUri,
            description,
            owner,
            initialSupply,
            salt
        );
        
        // Verify metadata in registry
        (
            string memory storedName,
            string memory storedSymbol,
            string memory storedImageUri,
            string memory storedDescription
        ) = (
            assetRegistry.getAsset(memeCoin).name,
            assetRegistry.getAsset(memeCoin).symbol,
            assetRegistry.getAsset(memeCoin).imageUri,
            assetRegistry.getAsset(memeCoin).description
        );
        
        assertEq(storedName, name, "Name mismatch");
        assertEq(storedSymbol, symbol, "Symbol mismatch");
        assertEq(storedImageUri, imageUri, "Image URI mismatch");
        assertEq(storedDescription, description, "Description mismatch");
    }
    
    function testInvalidImageUri() public {
        string memory name = "Test Meme";
        string memory symbol = "TMEME";
        string memory invalidImageUri = "";
        string memory description = "Test Meme Coin";
        uint256 initialSupply = 1000000 * 10**18;
        uint256 salt = 123;

        vm.expectRevert("Image URI cannot be empty");
        factory.createMemeCoin(
            name,
            symbol,
            invalidImageUri,
            description,
            owner,
            initialSupply,
            salt
        );
    }
    
    function testInvalidDescription() public {
        string memory name = "Test Meme";
        string memory symbol = "TMEME";
        string memory imageUri = "https://example.com/image.png";
        string memory invalidDescription = "";
        uint256 initialSupply = 1000000 * 10**18;
        uint256 salt = 123;

        vm.expectRevert("Description cannot be empty");
        factory.createMemeCoin(
            name,
            symbol,
            imageUri,
            invalidDescription,
            owner,
            initialSupply,
            salt
        );
    }
    
    function testDuplicateMetadata() public {
        string memory name = "Test Meme";
        string memory symbol = "TMEME";
        string memory imageUri = "https://example.com/image.png";
        string memory description = "Test Meme Coin";
        uint256 initialSupply = 1000000 * 10**18;
        
        // Create first memecoin
        factory.createMemeCoin(
            name,
            symbol,
            imageUri,
            description,
            owner,
            initialSupply,
            123
        );
        
        // Attempt to create second memecoin with same metadata but different salt
        vm.expectRevert("Image already exists");
        factory.createMemeCoin(
            name,
            symbol,
            imageUri,
            description,
            owner,
            initialSupply,
            456
        );
    }
    
    function testUpdateMetadata() public {
        string memory name = "Test Meme";
        string memory symbol = "TMEME";
        string memory imageUri = "https://example.com/image.png";
        string memory description = "Test Meme Coin";
        uint256 initialSupply = 1000000 * 10**18;
        uint256 salt = 123;

        address memeCoin = factory.createMemeCoin(
            name,
            symbol,
            imageUri,
            description,
            owner,
            initialSupply,
            salt
        );
        
        // Note: Asset metadata cannot be updated after creation
        // This test now verifies that metadata remains unchanged
        
        // Get metadata
        (
            string memory storedName,
            string memory storedSymbol,
            string memory storedImageUri,
            string memory storedDescription
        ) = (
            assetRegistry.getAsset(memeCoin).name,
            assetRegistry.getAsset(memeCoin).symbol,
            assetRegistry.getAsset(memeCoin).imageUri,
            assetRegistry.getAsset(memeCoin).description
        );
        
        assertEq(storedName, name, "Name should not change");
        assertEq(storedSymbol, symbol, "Symbol should not change");
        assertEq(storedImageUri, imageUri, "Image URI should not change");
        assertEq(storedDescription, description, "Description should not change");
    }
}