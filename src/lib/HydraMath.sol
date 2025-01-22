// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title UltraOptimizedHydraMath
 * @notice Hyper-efficient, high-precision fixed-point math library
 * @dev Maximizes computational efficiency with advanced assembly techniques
 */
library HydraMath {

    uint256 internal constant LN2 = 693_147_180_559_945_309; // ln(2) * 1e18
    uint256 internal constant PRECISION = 1e18;
    uint256 internal constant HALF_PRECISION = 5e17;
    uint256 internal constant LN2_INVERSE = 1468802684000000000; // 1/ln(2) * 1e18
    uint256 internal constant POLY_COEFFICIENT = 995063000000; // Polynomial approximation coefficient
    error MathOverflow();

   /**
     * @notice Ultra-optimized binary exponential function
     * @dev Minimizes gas by using advanced assembly techniques
     */
    function exp(int256 inputExponent) internal pure returns (uint256) {
        // Extreme value handling
        if (inputExponent <= -41_446_531_673_892_822_312) return 0;
        if (inputExponent >= 135_305_999_368_893_231_589) revert MathOverflow();

        // Negative exponent handling
        bool isNegative = inputExponent < 0;
        if (isNegative) inputExponent = -inputExponent;
        uint256 absExponent = uint256(inputExponent);

        uint256 expResult;
        assembly ("memory-safe") {
            // Core exponential approximation
            let t := div(mul(absExponent, LN2_INVERSE), PRECISION)
            
            // Integer part computation
            let shift := div(t, PRECISION)
            expResult := shl(shift, PRECISION)
            
            // Fractional part polynomial approximation
            let frac := and(t, sub(PRECISION, 1))
            let poly := add(PRECISION, 
                div(mul(frac, POLY_COEFFICIENT), PRECISION)
            )
            expResult := div(mul(expResult, poly), PRECISION)
        }

        // Final adjustment for negative exponents
        return isNegative ? fdiv(PRECISION, expResult) : expResult;
    }

    function fmul(uint256 inputX, uint256 inputY) internal pure returns (uint256 result) {
        assembly ("memory-safe") {
            result := div(mul(inputX, inputY), PRECISION)
        }
    }

    function fdiv(uint256 x, uint256 y) internal pure returns (uint256) {
        return (x * PRECISION) / y;
    }

    function sigmoid(uint256 x, uint256 steepness) internal pure returns (uint256) {
        unchecked {
            if (x == 0 || steepness == 0) return HALF_PRECISION;

            // Calculate -steepness * x efficiently
            uint256 scaledValue;
            assembly {
                scaledValue := div(mul(steepness, x), PRECISION)
                scaledValue := sub(0, scaledValue) // Negate
            }
            
            uint256 expValue = exp(int256(scaledValue));
            return (PRECISION * PRECISION) / (PRECISION + expValue);
        }
    }

    function gaussian(uint256 x, uint256 width) internal pure returns (uint256) {
        unchecked {
            if (width == 0) revert MathOverflow();
            if (x == 0) return PRECISION;

            uint256 squared;
            assembly {
                // Calculate (x/width)^2 efficiently
                let scaledX := div(mul(x, PRECISION), width)
                squared := div(mul(scaledX, scaledX), PRECISION)
                // Prevent overflow in negation
                if gt(squared, 0x8000000000000000000000000000000000000000000000000000000000000000) {
                    squared := 0x8000000000000000000000000000000000000000000000000000000000000000
                }
            }
            
            return exp(-int256(squared));
        }
    }

    function rational(uint256 x, uint256 power) internal pure returns (uint256) {
        unchecked {
            if (power == 0 || x == 0) return PRECISION;

            uint256 result;
            assembly {
                // Initialize accumulator
                let acc := PRECISION
                let term := x

                // Efficient power calculation
                for { let i := 0 } lt(i, power) { i := add(i, 1) } {
                    // acc = acc * (1 + term) / PRECISION
                    acc := div(mul(acc, add(PRECISION, term)), PRECISION)
                    // term = term * x / PRECISION
                    term := div(mul(term, x), PRECISION)
                }

                // Final result = PRECISION^2 / acc
                result := div(mul(PRECISION, PRECISION), acc)
            }
            return result;
        }
    }
    
    function computeComponents(
        uint256 deltaPriceDelta,
        uint32 sigmoidSteepness,
        uint32 gaussianWidth,
        uint32 rationalPower
    ) internal pure returns (uint256, uint256, uint256) {
        unchecked {
            // Early return for edge cases
            if (deltaPriceDelta == 0) {
                return (HALF_PRECISION, PRECISION, PRECISION);
            }

            uint256 sigmoidResult;
            uint256 gaussianResult;
            uint256 rationalResult;
            
            assembly {
                // Sigmoid calculation
                let scaledSigmoid := div(mul(sigmoidSteepness, deltaPriceDelta), PRECISION)
                scaledSigmoid := sub(0, scaledSigmoid) // Negate
                let expValue := exp(0,scaledSigmoid)
                sigmoidResult := div(mul(PRECISION, PRECISION), add(PRECISION, expValue))
                
                // Gaussian calculation
                let gaussianWidth256 := mul(gaussianWidth, 100000000000000) // 1e14
                let scaledX := div(mul(deltaPriceDelta, PRECISION), gaussianWidth256)
                let squared := div(mul(scaledX, scaledX), PRECISION)
                if gt(squared, 0x8000000000000000000000000000000000000000000000000000000000000000) {
                    squared := 0x8000000000000000000000000000000000000000000000000000000000000000
                }
                gaussianResult := exp(0, sub(0, squared))
                
                // Rational calculation
                let acc := PRECISION
                let term := deltaPriceDelta
                for { let i := 0 } lt(i, rationalPower) { i := add(i, 1) } {
                    acc := div(mul(acc, add(PRECISION, term)), PRECISION)
                    term := div(mul(term, deltaPriceDelta), PRECISION)
                }
                rationalResult := div(mul(PRECISION, PRECISION), acc)
            }
            
            return (sigmoidResult, gaussianResult, rationalResult);
        }
    }

    // Alias for compatibility
    function calculateComponents(
        uint256 deltaPriceDelta,
        uint32 sigmoidSteepness,
        uint32 gaussianWidth,
        uint32 rationalPower
    ) internal pure returns (uint256, uint256, uint256) {
        return computeComponents(deltaPriceDelta, sigmoidSteepness, gaussianWidth, rationalPower);
    }
}