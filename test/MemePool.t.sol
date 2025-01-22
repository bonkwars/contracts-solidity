// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/MemePool.sol";
import "../src/HydraOpenzeppelin.sol";


contract MemePoolTest is Test {
    MemePool public pool;
    MockToken public token;
    address public owner;
    address public user1;
    address public user2;
    
    uint256 constant INITIAL_LIQUIDITY = 1000 * 10**18;
    uint256 constant INITIAL_ETH = 1 ether;

    event LiquidityAdded(
        address indexed provider,
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 liquidity
    );
    
    event LiquidityRemoved(
        address indexed provider,
        uint256 ethAmount,
        uint256 tokenAmount,
        uint256 liquidity
    );
    
    event Swap(
        address indexed user,
        bool ethToToken,
        uint256 amountIn,
        uint256 amountOut
    );

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        vm.startPrank(owner);
        token = new MockToken();
        pool = new MemePool(owner);
        pool.initialize(address(token));
        
        // Fund users
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
        token.transfer(user1, INITIAL_LIQUIDITY * 2);
        token.transfer(user2, INITIAL_LIQUIDITY * 2);
        vm.roll(10);
        vm.stopPrank();
    }

    function testInitialLiquidityProvision() public {
        vm.startPrank(user1);
        
        // Approve tokens
        token.approve(address(pool), INITIAL_LIQUIDITY);
      
        emit LiquidityAdded(user1, INITIAL_ETH, INITIAL_LIQUIDITY, INITIAL_LIQUIDITY - 1e17);
        
        pool.addLiquidity{value: INITIAL_ETH}(INITIAL_LIQUIDITY);
        
        // Verify state
        assertEq(address(pool).balance, INITIAL_ETH, "Incorrect ETH balance");
        assertEq(token.balanceOf(address(pool)), INITIAL_LIQUIDITY, "Incorrect token balance");
        assertTrue(pool.balanceOf(user1) > 0, "No LP tokens minted");
        
        vm.stopPrank();
    }

    function testReentrantSwap() public {
        // Setup initial liquidity
        vm.startPrank(user1);
        token.approve(address(pool), INITIAL_LIQUIDITY);
        pool.addLiquidity{value: INITIAL_ETH}(INITIAL_LIQUIDITY);
        vm.stopPrank();
        
        vm.startPrank(user2);
        
        // Try reentrancy
        ReentrantAttacker attacker = new ReentrantAttacker(address(pool));
        vm.expectRevert("ReentrancyGuard: reentrant call");
        attacker.attack{value: 1 ether}();
        
        vm.stopPrank();
    }

    function testSwapExactETHForTokens() public {
        // Setup initial liquidity
        vm.startPrank(user1);
        token.approve(address(pool), INITIAL_LIQUIDITY);
        pool.addLiquidity{value: INITIAL_ETH}(INITIAL_LIQUIDITY);
        vm.stopPrank();
        
        vm.startPrank(user2);
        
        uint256 ethAmount = 0.1 ether;
        uint256 userInitialETH = user2.balance;
        uint256 userInitialTokens = token.balanceOf(user2);
        
        // Perform swap
        (uint256 tokenAmount, uint256 expectedPrice) = pool.swapExactETHForTokens{value: ethAmount}();
        
        // Verify state changes
        assertEq(user2.balance, userInitialETH - ethAmount, "ETH not deducted");
        assertEq(token.balanceOf(user2), userInitialTokens + tokenAmount, "Tokens not received");
        assertTrue(tokenAmount > 0, "No tokens received");
        assertTrue(expectedPrice > 0, "Invalid price");
        
        vm.stopPrank();
    }

    function testSwapExactTokensForETH() public {
        // Setup initial liquidity
        vm.startPrank(user1);
        token.approve(address(pool), INITIAL_LIQUIDITY);
        pool.addLiquidity{value: INITIAL_ETH}(INITIAL_LIQUIDITY);
        vm.stopPrank();
        
        vm.startPrank(user2);
        
        uint256 tokenAmount = INITIAL_LIQUIDITY / 10;
        uint256 userInitialETH = user2.balance;
        token.approve(address(pool), tokenAmount);
        
        // Perform swap
        (uint256 ethAmount, uint256 expectedPrice) = pool.swapExactTokensForETH(tokenAmount);
        
        // Verify state changes
        assertEq(user2.balance, userInitialETH + ethAmount, "ETH not received");
        assertTrue(ethAmount > 0, "No ETH received");
        assertTrue(expectedPrice > 0, "Invalid price");
        
        vm.stopPrank();
    }

    function testPausedOperations() public {
        // Setup initial liquidity
        vm.startPrank(user1);
        token.approve(address(pool), INITIAL_LIQUIDITY);
        pool.addLiquidity{value: INITIAL_ETH}(INITIAL_LIQUIDITY);
        vm.stopPrank();
        
        // Pause pool
        vm.prank(owner);
        pool.pause();
        
        vm.startPrank(user2);
        
        // Try operations while paused
        vm.expectRevert("Pool is paused");
        pool.swapExactETHForTokens{value: 0.1 ether}();
        
        vm.expectRevert("Pool is paused");
        pool.swapExactTokensForETH(1000);
        
        vm.expectRevert("Pool is paused");
        pool.addLiquidity{value: 1 ether}(1000);
        
        vm.stopPrank();
    }

    function testFuzzSwaps(uint256 ethAmount) public {
        // Setup initial liquidity
        
        vm.startPrank(user1);
        token.approve(address(pool), INITIAL_LIQUIDITY);
        pool.addLiquidity{value: INITIAL_ETH}(INITIAL_LIQUIDITY);
        vm.stopPrank();
      
        // Bound input to reasonable values
        ethAmount = bound(ethAmount, 0.01 ether, 10 ether);
        
        vm.startPrank(user2);
        vm.deal(user2, ethAmount);
        
        // Perform swap
        if (ethAmount > 0) {
            (uint256 tokenAmount,) = pool.swapExactETHForTokens{value: ethAmount}();
            assertTrue(tokenAmount > 0, "No tokens received");
            
            // Swap back
            token.approve(address(pool), tokenAmount);
            (uint256 ethReceived,) = pool.swapExactTokensForETH(tokenAmount);
            assertTrue(ethReceived > 0, "No ETH received");
        }
        
        vm.stopPrank();
    }

    function testRemoveLiquidity() public {
        // Setup initial liquidity
        vm.startPrank(user1);
        token.approve(address(pool), INITIAL_LIQUIDITY);
        uint256 lpTokens = pool.addLiquidity{value: INITIAL_ETH}(INITIAL_LIQUIDITY);
        
        // Remove half liquidity
        uint256 halfLp = lpTokens / 2;
        (uint256 ethAmount, uint256 tokenAmount) = pool.removeLiquidity(halfLp);
        
        // Verify amounts
        assertTrue(ethAmount > 0, "No ETH received");
        assertTrue(tokenAmount > 0, "No tokens received");
        assertEq(pool.balanceOf(user1), halfLp, "LP tokens not burned");
        
        vm.stopPrank();
    }
}

// Helper contract for testing reentrancy
contract ReentrantAttacker {
    MemePool public pool;
    
    constructor(address _pool) {
        pool = MemePool(payable(_pool));
    }
    
    function attack() external payable {
        pool.swapExactETHForTokens{value: msg.value}();
    }
    
    receive() external payable {
        // Try to reenter
        if (address(pool).balance >= 0.1 ether) {
            pool.swapExactETHForTokens{value: 0.1 ether}();
        }
    }
}

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK", 18) {
        _mint(msg.sender, 1000000 * 10**18);
    }
}
