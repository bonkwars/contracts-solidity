// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/MemeCoin.sol";
import "../src/security/AntiBot.sol";
import "../src/security/AntiRugPull.sol";

/**
* @title MemeCoinDetailedTest
* @author Degen4Life Team
* @notice Comprehensive test suite for MemeCoin, AntiBot and AntiRugPull functionality
* @dev Tests various security features, trading restrictions and edge cases
*/
contract MemeCoinDetailedTest is Test {
   MemeCoin public memeCoin;
   AntiBot public antiBot;
   AntiRugPull public antiRugPull;
   
   address public owner;
   address public user1;
   address public user2;
   address public user3;
   address public bot;
   
   uint256 public constant INITIAL_SUPPLY = 10000000 * 10**18;

   /**
    * @notice Sets up the test environment with necessary contracts and accounts
    * @dev Deploys MemeCoin, AntiRugPull, enables security and mints initial supply
    */
  function setUp() public {
        owner = address(this);
        user1 = address(0x1);
        user2 = address(0x2);
        user3 = address(0x3);
        bot = address(0x4);
        
        antiRugPull = new AntiRugPull(owner);
        memeCoin = new MemeCoin(
            "Test Meme",
            "TMEME",
            owner,
            address(antiRugPull)
        );
        
        // Mint initial supply first
        memeCoin.mint(owner, INITIAL_SUPPLY);

        // Enable security with basis points (100 = 1%)
        antiRugPull.enableSecurity(
            address(memeCoin),
            1000,  // 10% max sell
            2000,  // 20% max wallet
            5000   // 50% max daily sells
        );

        bool myBool = antiRugPull.isTokenSecurityEnabled(address(memeCoin));
        console.log("Security enabled:", myBool);


        // Whitelist the test contract
        antiRugPull.setWhitelisted(address(memeCoin), address(this), true);
          memeCoin.whitelistAddress(address(this), true);


        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        vm.deal(user3, 100 ether);
        vm.deal(bot, 100 ether);

        memeCoin.enableTrading();
    }

   /**
    * @notice Tests that security is properly enabled and configured
    * @dev Verifies all security parameters are set correctly
    */
   function testSecuritySetup() public {
       (
           uint256 maxSellPercentage,
           uint256 maxWalletPercentage,
           uint256 maxTotalSellPercentage,
           bool securityEnabled
       ) = antiRugPull.tokenSecurity(address(memeCoin));

assertTrue(antiRugPull.isTokenSecurityEnabled(address(memeCoin)) , "Security should be enabled");
       assertTrue(securityEnabled, "Security should be enabled in struct");
       assertEq(maxSellPercentage, 1000, "Max sell should be 10%");
       assertEq(maxWalletPercentage, 2000, "Max wallet should be 20%");
       assertEq(maxTotalSellPercentage, 5000, "Max total sell should be 50%");
   }

   /**
    * @notice Tests initial contract setup and parameters
    * @dev Verifies token name, symbol, decimals and initial supply
    */
   function testInitialSetup() public {
       assertEq(memeCoin.name(), "Test Meme");
       assertEq(memeCoin.symbol(), "TMEME");
       assertEq(memeCoin.decimals(), 18);
       assertEq(memeCoin.balanceOf(address(this)), INITIAL_SUPPLY);
   }

   /**
    * @notice Tests basic transfer functionality within allowed limits
    * @dev Attempts a transfer below the maximum limits
    */
   function testSmallTransfer() public {
       uint256 amount = INITIAL_SUPPLY * 5 / 100; // 5% - below limits
       memeCoin.transfer(user1, amount);
       assertEq(memeCoin.balanceOf(user1), amount);
   }

   /**
    * @notice Tests maximum sell limit enforcement
    * @dev Attempts to sell more than the allowed percentage
    */
   function testMaxSellLimit() public {
       // Verify security is enabled
       (,,, bool securityEnabled) = antiRugPull.tokenSecurity(address(memeCoin));
       assertTrue(securityEnabled, "Security should be enabled");

       uint256 safeAmount = INITIAL_SUPPLY * 5 / 100; // 5% - safe amount
       uint256 sellAmount = INITIAL_SUPPLY * 15 / 100; // 15% - above limit

       // Transfer to user1 first
       memeCoin.transfer(user1, sellAmount);
       assertEq(memeCoin.balanceOf(user1), sellAmount);

       // Try to sell above limit
       vm.prank(user1);
       vm.expectRevert("Sell amount too high");
       memeCoin.transfer(user2, sellAmount);

       // Verify can still sell safe amount
       vm.prank(user1);
       memeCoin.transfer(user2, safeAmount);
       assertEq(memeCoin.balanceOf(user2), safeAmount);
   }

   /**
    * @notice Tests maximum wallet size limit enforcement
    * @dev Attempts to exceed maximum wallet balance
    */
  function testMaxWalletLimit() public {
   
        uint256 maxAllowed = (INITIAL_SUPPLY * 2000) / 10000; // 20%
        
        // Transfer maximum allowed amount
        memeCoin.transfer(user1, maxAllowed);
        assertEq(memeCoin.balanceOf(user1), maxAllowed);

        // Try to transfer 1 more token
        vm.startPrank(owner);
      
        vm.expectRevert("Balance would exceed max");
        memeCoin.transfer(user1, INITIAL_SUPPLY + 1);
    }


   /**
    * @notice Tests whitelisted address bypass of restrictions
    * @dev Verifies whitelisted addresses can exceed normal limits
    */
   function testWhitelistBypass() public {
        uint256 largeAmount = INITIAL_SUPPLY * 30 / 100; // 30%
        
        // Whitelist in both contracts
        antiRugPull.setWhitelisted(address(memeCoin), user1, true);
        memeCoin.whitelistAddress(user1, true);
        
        // Transfer to whitelisted should work
        memeCoin.transfer(user1, largeAmount);
        assertEq(memeCoin.balanceOf(user1), largeAmount);

        // Whitelist receiver for second transfer
        antiRugPull.setWhitelisted(address(memeCoin), user2, true);
        memeCoin.whitelistAddress(user2, true);

        // Transfer from whitelisted should work
        vm.prank(user1);
        memeCoin.transfer(user2, largeAmount / 2);
        assertEq(memeCoin.balanceOf(user2), largeAmount / 2);
    }

   /**
    * @notice Tests security toggle functionality
    * @dev Verifies behavior when security is enabled vs disabled
    */
  function testSecurityToggle() public {
        uint256 amount = INITIAL_SUPPLY * 25 / 100; // 25%
        
        // Should fail with security enabled
        vm.expectRevert("Balance would exceed max");
        memeCoin.transfer(user1, amount);
        
        // Disable security
        antiRugPull.disableSecurity(address(memeCoin));
        
        assertTrue(!antiRugPull.isTokenSecurityEnabled(address(memeCoin)));
    }
}