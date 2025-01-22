// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/security/SecurityManager.sol";
import "../lib/solmate/src/tokens/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK", 18) {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract MockAuthority is Authority {
    mapping(address => mapping(address => mapping(bytes4 => bool))) public authorizedCalls;

    constructor(address owner) {
        // Set up permissions for key functions
        authorizedCalls[owner][address(0)][SecurityManager.blacklistAddress.selector] = true;
        authorizedCalls[owner][address(0)][SecurityManager.setEmergencyMode.selector] = true;
        authorizedCalls[owner][address(0)][SecurityManager.clearTradingHistory.selector] = true;
    }

    function canCall(
        address user,
        address target,
        bytes4 functionSig
    ) public view override returns (bool) {
        return authorizedCalls[user][target][functionSig];
    }
}

contract SecurityManagerTest is Test {
    SecurityManager public securityManager;
    MockToken public token;
    address public owner;
    address public trader;
    address public authority;
    MockAuthority public mockAuthority;

   function setUp() public {
    owner = address(this);
    trader = address(0x1);
    
    // Deploy mock authority first
    mockAuthority = new MockAuthority(owner);
    
    // Deploy contracts using mock authority
    securityManager = new SecurityManager(address(mockAuthority));
    token = new MockToken();
    
    // Setup test accounts
    vm.deal(trader, 100 ether);
    token.transfer(trader, 10000 * 10**18);
}

    function testValidateTradeSuccess() public {
        uint256 amount = 1000 * 10**18;  // 1000 tokens
        uint256 price = amount;          // Setting price equal to amount for test
        
        bool isValid = securityManager.validateTrade(
            trader,
            address(token),
            amount,
            price
        );
        
        assertTrue(isValid);
    }

    function testTradeFrequencyLimit() public {
        uint256 amount = 1000 * 10**18;
        uint256 price = amount;
        
        // First trade should succeed
        securityManager.validateTrade(
            trader,
            address(token),
            amount,
            price
        );
        
        // Immediate second trade should fail
        vm.expectRevert("Trading too frequently");
        securityManager.validateTrade(
            trader,
            address(token),
            amount,
            price
        );
        
        // After MIN_TIME_BETWEEN_TRADES blocks, trade should succeed
        vm.warp(block.timestamp + 2); // Use warp instead of roll
        bool isValid = securityManager.validateTrade(
            trader,
            address(token),
            amount,
            price
        );
        assertTrue(isValid);
    }

    function testGetTraderStats() public {
        uint256 amount = 1000 * 10**18;
        uint256 price = amount;
        
        securityManager.validateTrade(
            trader,
            address(token),
            amount,
            price
        );
        
        (uint256 lastTrade, uint256 volume, bool isBlacklisted) = 
            securityManager.getTraderStats(trader);
            
        assertEq(lastTrade, block.timestamp);
        assertEq(volume, amount);
        assertFalse(isBlacklisted);
    }

    function testClearTradingHistory() public {
        uint256 amount = 1000 * 10**18;
        uint256 price = amount;
        
        securityManager.validateTrade(
            trader,
            address(token),
            amount,
            price
        );
        
        vm.prank(owner);
        securityManager.clearTradingHistory(trader);
        
        (uint256 lastTrade, uint256 volume, ) = securityManager.getTraderStats(trader);
        assertEq(lastTrade, 0);
        assertEq(volume, 0);
    }

     function testPriceImpact() public {
        uint256 amount = 1000 * 10**18;
        uint256 basePrice = amount;
        
        // Advance block to avoid frequency limit
        vm.warp(block.timestamp + 2);
        
        // Should succeed - no price impact
        bool isValid = securityManager.validateTrade(
            trader,
            address(token),
            amount,
            basePrice
        );
        assertTrue(isValid);
        
        // Advance block again for next trade
        vm.warp(block.timestamp + 2);
        
        // Should fail - price impact too high (11% difference)
        uint256 highImpactPrice = basePrice * 89 / 100;  // 11% lower
        vm.expectRevert("Price impact too high");
        securityManager.validateTrade(
            trader,
            address(token),
            amount,
            highImpactPrice
        );
    }

    function testValidateTradeSizeLimitExceeded() public {
        uint256 amount = 600000 * 10**18; // 60% of total supply
        uint256 expectedPrice = 1 ether;
        
        vm.expectRevert("Trade size too large");
        securityManager.validateTrade(
            trader,
            address(token),
            amount,
            expectedPrice
        );
    }

  

    function testEmergencyMode() public {
        // Set emergency mode
        vm.prank(owner);
        securityManager.setEmergencyMode(true);
        
        uint256 amount = 1000 * 10**18;
        uint256 expectedPrice = 1 ether;
        
        vm.expectRevert("Trading suspended");
        securityManager.validateTrade(
            trader,
            address(token),
            amount,
            expectedPrice
        );
    }

    function testBlacklist() public {
        vm.prank(owner);
        securityManager.blacklistAddress(trader);
        
        uint256 amount = 1000 * 10**18;
        uint256 expectedPrice = 1 ether;
        
        vm.expectRevert("Address blacklisted");
        securityManager.validateTrade(
            trader,
            address(token),
            amount,
            expectedPrice
        );
        
        assertTrue(securityManager.isAddressBlacklisted(trader));
    }

    function testSignatureValidation() public {
        bytes32 messageHash = keccak256("test message");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(1, messageHash);
        
        bytes memory signature = abi.encodePacked(r, s, v);
        address signer = vm.addr(1);
        
        bool isValid = securityManager.validateSignature(
            messageHash,
            signature,
            signer
        );
        assertTrue(isValid);
        
        // Test replay protection
        vm.expectRevert("Signature already used");
        securityManager.validateSignature(messageHash, signature, signer);
    }

  


    function testAuthorizationChecks() public {
        address unauthorized = address(0x3);
        
        vm.prank(unauthorized);
        vm.expectRevert();
        securityManager.setEmergencyMode(true);
        
        vm.prank(unauthorized);
        vm.expectRevert();
        securityManager.blacklistAddress(trader);
        
        vm.prank(unauthorized);
        vm.expectRevert();
        securityManager.clearTradingHistory(trader);
    }
}
