// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/MemeCoinFactory.sol";
import "../src/MemeCoin.sol";
import "../src/security/AntiRugPull.sol";
import "../src/MemeAssetRegistry.sol";

contract MemeCoinFactoryTest is Test {
    // Constants 
    uint256 constant INITIAL_SUPPLY = 1000000 * 10**18;
    uint256 constant SALT = 123;

    struct TokenInfo {
        string name;
        string symbol;
        string imageUri;
        string description;
    }

    MemeCoinFactory public factory;
    AntiRugPull public antiRugPull;
    MemeAssetRegistry public assetRegistry;
    
    address public owner;
    address public user;

    TokenInfo testToken;

    event MemeCoinCreated(
        string name,
        string symbol,
        address indexed memeCoin,
        address indexed owner,
        uint256 totalSupply
    );

    function setUp() public {
        owner = address(this);
        user = makeAddr("user");

        // Setup test token info
        testToken = TokenInfo({
            name: "Test Meme",
            symbol: "TMEME",
            imageUri: "ipfs://QmTest...",
            description: "Test description"
        });

        // Deploy contracts with owner 
        vm.startPrank(owner);
        
        // Deploy AntiRugPull with owner
        antiRugPull = new AntiRugPull(owner);
        
        // Deploy asset registry
        assetRegistry = new MemeAssetRegistry();
        
        // Deploy factory
        factory = new MemeCoinFactory(
            address(antiRugPull), 
            address(assetRegistry)
        );

        // Enable security features on AntiRugPull for factory
        antiRugPull.enableSecurity(
            address(factory),
            500, // 5% max sell
            300, // 3% max wallet
            2000  // 20% max daily sells
        );

        vm.stopPrank();
    }

    function testCreateMemeCoin() public {
        vm.startPrank(owner);

        // Register asset
        bytes32 pendingHash = assetRegistry.registerAsset(
            address(0),
            testToken.name,
            testToken.symbol,
            testToken.imageUri, 
            testToken.description
        );

        // Create memecoin
        address expectedToken = factory.predictMemeCoinAddress(
            testToken.name,
            testToken.symbol,
            owner,
            SALT
        );

        // Expect event
        //vm.expectEmit(true, true, true, true);
        emit MemeCoinCreated(
            testToken.name,
            testToken.symbol,
            expectedToken,
            owner,
            INITIAL_SUPPLY
        );

        // Create token
        address memeCoin = factory.createMemeCoin(
            testToken.name,
            testToken.symbol,
            testToken.imageUri,
            testToken.description,
            owner,
            INITIAL_SUPPLY,
            SALT
        );

        // Verify state
        assertFalse(memeCoin == address(0), "Token deployment failed");
        assertEq(MemeCoin(memeCoin).name(), testToken.name);
        assertEq(MemeCoin(memeCoin).balanceOf(owner), INITIAL_SUPPLY);

        vm.stopPrank();
    }

    function testCannotCreateDuplicate() public {
        vm.startPrank(owner);

        // First creation
        bytes32 pendingHash = assetRegistry.registerAsset(
            address(0),
            testToken.name,
            testToken.symbol,
            testToken.imageUri,
            testToken.description
        );

        factory.createMemeCoin(
            testToken.name,
            testToken.symbol,
            testToken.imageUri,
            testToken.description,
            owner,
            INITIAL_SUPPLY,
            SALT
        );

        // Try duplicate with same salt
        vm.expectRevert("MemeCoin already exists");
        factory.createMemeCoin(
            testToken.name,
            testToken.symbol,
            testToken.imageUri,
            testToken.description,
            owner,
            INITIAL_SUPPLY,
            SALT
        );

        vm.stopPrank();
    }

    function testPredictAddress() public {
        vm.startPrank(owner);

        // Predict address
        address predicted = factory.predictMemeCoinAddress(
            testToken.name,
            testToken.symbol,
            owner,
            SALT
        );

        // Register asset
        bytes32 pendingHash = assetRegistry.registerAsset(
            address(0),
            testToken.name,
            testToken.symbol,
            testToken.imageUri,
            testToken.description
        );

        // Create token
        address actual = factory.createMemeCoin(
            testToken.name,
            testToken.symbol,
            testToken.imageUri,
            testToken.description,
            owner,
            INITIAL_SUPPLY,
            SALT
        );

        assertEq(actual, predicted, "Address prediction failed");
        vm.stopPrank();
    }

    function testAssetRegistryValidation() public {
        vm.startPrank(owner);

        // Create first token 
        bytes32 pendingHash = assetRegistry.registerAsset(
            address(0),
            testToken.name,
            testToken.symbol,
            testToken.imageUri,
            testToken.description
        );

        address memeCoin = factory.createMemeCoin(
            testToken.name,
            testToken.symbol,
            testToken.imageUri,
            testToken.description,
            owner,
            INITIAL_SUPPLY,
            SALT
        );

        // Try with same name
        vm.expectRevert();
        assetRegistry.registerAsset(
            address(0),
            testToken.name,
            "TEST2",
            "ipfs://different",
            "Different description"
        );

        // Try with same image
        vm.expectRevert(); 
        assetRegistry.registerAsset(
            address(0),
            "Different Name",
            "TEST2",
            testToken.imageUri,
            "Different description"
        );

        vm.stopPrank();
    }

    function testSecurityIntegration() public {
        vm.startPrank(owner);

        // Register and create token
        bytes32 pendingHash = assetRegistry.registerAsset(
            address(0),
            testToken.name,
            testToken.symbol,
            testToken.imageUri,
            testToken.description
        );

        address tokenAddr = factory.createMemeCoin(
            testToken.name,
            testToken.symbol,
            testToken.imageUri,
            testToken.description,
            owner,
            INITIAL_SUPPLY,
            SALT
        );

        // Get token
        MemeCoin token = MemeCoin(tokenAddr);
        
        // Verify AntiRugPull integration
        assertEq(address(token.antiRugPull()), address(antiRugPull));

        // Test max wallet restriction
        vm.expectRevert("Balance would exceed max");
        token.transfer(user, INITIAL_SUPPLY);

        vm.stopPrank();
    }

    function testFuzzCreateMemeCoin(uint256 supply, uint256 salt) public {
        // Bound supply to reasonable values
        supply = bound(supply, 1000, type(uint128).max);
        
        vm.startPrank(owner);

        // Register asset
        bytes32 pendingHash = assetRegistry.registerAsset(
            address(0),
            testToken.name,
            testToken.symbol,
            testToken.imageUri,
            testToken.description
        );

        // Create token
        address memeCoin = factory.createMemeCoin(
            testToken.name,
            testToken.symbol,
            testToken.imageUri,
            testToken.description,
            owner,
            supply,
            salt
        );

        // Verify basic state
        assertFalse(memeCoin == address(0), "Token deployment failed");
        assertEq(MemeCoin(memeCoin).balanceOf(owner), supply);

        vm.stopPrank();
    }
}