// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/HydraOpenzeppelin.sol";

contract HydraOpenZeppelinTest is Test {
    HydraOpenZeppelin hydra;
    
    // Test constants
    uint256 constant PRECISION = 1e18;
    uint256 constant MAX_PRICE_RATIO = 1000 * 1e18;
    uint256 constant MIN_LIQUIDITY = 1e9;

    function setUp() public {
        hydra = new HydraOpenZeppelin();
    }

    function testCalculateLiquidityInputValidation() public {
        HydraOpenZeppelin.HydraConfig memory config = hydra.standardConfig();

        // Test zero inputs
        vm.expectRevert(HydraOpenZeppelin.InvalidInput.selector);
        hydra.calculateLiquidity(0, 1e18, 1e18, 1e18, config);

        vm.expectRevert(HydraOpenZeppelin.InvalidInput.selector);
        hydra.calculateLiquidity(1e18, 0, 1e18, 1e18, config);

        vm.expectRevert(HydraOpenZeppelin.InvalidInput.selector);
        hydra.calculateLiquidity(1e18, 1e18, 0, 1e18, config);

        vm.expectRevert(HydraOpenZeppelin.InvalidInput.selector);
        hydra.calculateLiquidity(1e18, 1e18, 1e18, 0, config);
    }

    function testPriceRatioBounds() public {
        HydraOpenZeppelin.HydraConfig memory config = hydra.standardConfig();
        uint256 exceeded_price = MAX_PRICE_RATIO + 1;

        vm.expectRevert(HydraOpenZeppelin.PriceOutOfBounds.selector);
        hydra.calculateLiquidity(1e18, 1e18, exceeded_price, 1e18, config);

        vm.expectRevert(HydraOpenZeppelin.PriceOutOfBounds.selector);
        hydra.calculateLiquidity(1e18, 1e18, 1e18, exceeded_price, config);
    }

    function testConfigValidation() public {
        HydraOpenZeppelin.HydraConfig memory config = hydra.standardConfig();
        
        // Test invalid steepness
        config.sigmoidSteepness = 5; // Below MIN_STEEPNESS
        vm.expectRevert(HydraOpenZeppelin.InvalidConfig.selector);
        hydra.calculateLiquidity(1e18, 1e18, 1e18, 1e18, config);

        // Test invalid gaussian width
        config = hydra.standardConfig();
        config.gaussianWidth = 5e15; // Below minimum
        vm.expectRevert(HydraOpenZeppelin.InvalidConfig.selector);
        hydra.calculateLiquidity(1e18, 1e18, 1e18, 1e18, config);

        // Test invalid weights sum
        config = hydra.standardConfig();
        config.sigmoidWeight = uint64(PRECISION); // Makes total > PRECISION
        vm.expectRevert(HydraOpenZeppelin.InvalidConfig.selector);
        hydra.calculateLiquidity(1e18, 1e18, 1e18, 1e18, config);
    }

    function testMinimumLiquidity() public {
        HydraOpenZeppelin.HydraConfig memory config = hydra.standardConfig();
        
        // Test extremely small liquidity
        vm.expectRevert(HydraOpenZeppelin.InvalidInput.selector);
        hydra.calculateLiquidity(100, 100, 1e18, 1e18, config);
    }

    function testMathOverflowProtection() public {
        HydraOpenZeppelin.HydraConfig memory config = hydra.standardConfig();
        uint256 maxUint = type(uint256).max;

        vm.expectRevert(HydraOpenZeppelin.MathOverflow.selector);
        hydra.calculateLiquidity(maxUint, maxUint, 1e18, 1e18, config);
    }

    function testFuzzCalculateLiquidity(
        uint256 x,
        uint256 y,
        uint256 currentPrice,
        uint256 targetPrice
    ) public {
        // Bound inputs to reasonable ranges
        x = bound(x, MIN_LIQUIDITY, type(uint128).max);
        y = bound(y, MIN_LIQUIDITY, type(uint128).max);
        currentPrice = bound(currentPrice, 1, MAX_PRICE_RATIO);
        targetPrice = bound(targetPrice, 1, MAX_PRICE_RATIO);

        HydraOpenZeppelin.HydraConfig memory config = hydra.standardConfig();
        
        uint256 liquidity = hydra.calculateLiquidity(x, y, currentPrice, targetPrice, config);
        
        assertTrue(liquidity > 0, "Liquidity should be positive");
        assertTrue(liquidity <= Math.sqrt(x * y), "Liquidity should not exceed geometric mean");
    }

    function testEdgeCaseReversion() public {
        HydraOpenZeppelin.HydraConfig memory config = hydra.standardConfig();
        uint256 maxUint = type(uint256).max;

        // Test various edge cases
        vm.expectRevert();
        hydra.calculateLiquidity(maxUint, maxUint - 1, 1e18, 1e18, config);

        vm.expectRevert();
        hydra.calculateLiquidity(1e18, 1e18, maxUint, 1e18, config);

        vm.expectRevert();
        hydra.calculateLiquidity(1e18, 1e18, 1e18, maxUint, config);
    }

    function testPriceDeviation() public {
        HydraOpenZeppelin.HydraConfig memory config = hydra.standardConfig();
        uint256 baseAmount = 1000e18;

        // Test different price deviations
        uint256 liquidity1 = hydra.calculateLiquidity(
            baseAmount, 
            baseAmount, 
            1e18, // 1:1 price
            1e18,
            config
        );

        uint256 liquidity2 = hydra.calculateLiquidity(
            baseAmount,
            baseAmount,
            2e18, // 2:1 price
            1e18,
            config
        );

        assertTrue(liquidity1 > liquidity2, "Higher deviation should reduce liquidity");
    }

    function testConfigurationBehavior() public {
        uint256 baseAmount = 1000e18;
        uint256 price = 1e18;

        HydraOpenZeppelin.HydraConfig memory stableConfig = hydra.stableConfig();
        HydraOpenZeppelin.HydraConfig memory volatileConfig = hydra.volatileConfig();

        uint256 stableLiquidity = hydra.calculateLiquidity(
            baseAmount,
            baseAmount,
            price,
            price,
            stableConfig
        );

        uint256 volatileLiquidity = hydra.calculateLiquidity(
            baseAmount,
            baseAmount,
            price,
            price,
            volatileConfig
        );

        assertTrue(stableLiquidity >= volatileLiquidity, "Stable config should provide more liquidity");
    }
}