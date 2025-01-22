// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20} from "../lib/solmate/src/tokens/ERC20.sol";
import {SafeTransferLib} from "../lib/solmate/src/utils/SafeTransferLib.sol";
import {ReentrancyGuard} from "../lib/solmate/src/utils/ReentrancyGuard.sol";
import {HydraOpenZeppelin} from "./HydraOpenzeppelin.sol";

/**
 * @title MemePool
 * @author Degen4Life Team
 * @notice Liquidity pool for meme tokens and ETH using Hydra curve
 * @dev Implements Hydra curve AMM with dynamic liquidity
 * @custom:security-contact security@memeswap.exchange
 */
import {PausablePool} from "./security/PausablePool.sol";

contract MemePool is ERC20, PausablePool {
    address public immutable poolAuthority;
    using SafeTransferLib for ERC20;

       // Add reentrancy lock state
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    ERC20 public memeCoin;
    HydraOpenZeppelin public hydra;
    HydraOpenZeppelin.HydraConfig public hydraConfig;
    uint256 public constant MINIMUM_LIQUIDITY = 0.1 ether;

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

       modifier nonReentrantSwap() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }


   constructor(address _authority) 
        ERC20("MemeLiquidity", "MEMELP", 18)
        PausablePool(_authority) 
    {
        _status = _NOT_ENTERED;
        poolAuthority = _authority;
        hydra = new HydraOpenZeppelin();
        hydraConfig = hydra.standardConfig();
    }

    function initialize(address _memeCoin) external {
        require(msg.sender == poolAuthority, "Not authorized");
        require(address(memeCoin) == address(0), "Already initialized");
        require(_memeCoin != address(0), "Invalid token address");
        
        // Basic ERC20 validation
        ERC20 token = ERC20(_memeCoin);
        require(token.totalSupply() >= 0, "Invalid token");
        
        // Set token
        memeCoin = token;
    }

    function addLiquidity(
        uint256 tokenAmount
    ) external payable nonReentrant notPaused protectMEV returns (uint256 liquidity) {
        uint256 ethBalance = address(this).balance - msg.value;
        uint256 tokenBalance = memeCoin.balanceOf(address(this));
        uint256 ethAmount = msg.value;

        if (tokenBalance == 0) {
            // Initial liquidity
            liquidity = ethAmount - MINIMUM_LIQUIDITY;
            _mint(address(1), MINIMUM_LIQUIDITY); // Lock minimum liquidity forever
        } else {
            liquidity = (msg.value * totalSupply) / ethBalance;
        }

        require(liquidity > 0, "Insufficient liquidity minted");

        // Transfer tokens to pool using SafeTransferLib
        memeCoin.safeTransferFrom(msg.sender, address(this), tokenAmount);

        _mint(msg.sender, liquidity);

        emit LiquidityAdded(msg.sender, ethAmount, tokenAmount, liquidity);
    }

    function removeLiquidity(
        uint256 liquidity
    ) external nonReentrant notPaused protectMEV returns (uint256 ethAmount, uint256 tokenAmount) {
        require(liquidity > 0, "Invalid liquidity amount");

        uint256 ethBalance = address(this).balance;
        uint256 tokenBalance = memeCoin.balanceOf(address(this));
        uint256 totalSupplyValue = totalSupply;

        ethAmount = (liquidity * ethBalance) / totalSupplyValue;
        tokenAmount = (liquidity * tokenBalance) / totalSupplyValue;

        require(ethAmount > 0 && tokenAmount > 0, "Insufficient liquidity");

        _burn(msg.sender, liquidity);

        // Transfer assets back to provider using SafeTransferLib
        SafeTransferLib.safeTransferETH(msg.sender, ethAmount);
        memeCoin.safeTransfer(msg.sender, tokenAmount);

        emit LiquidityRemoved(msg.sender, ethAmount, tokenAmount, liquidity);
    }

     function swapExactETHForTokens()
        external
        payable
        nonReentrant
        nonReentrantSwap
        notPaused
        protectMEV
        returns (uint256 tokenAmount, uint256 expectedPrice)
    {
        require(msg.value > 0, "Invalid ETH amount");

        uint256 ethBalance = address(this).balance - msg.value;
        uint256 tokenBalance = memeCoin.balanceOf(address(this));

        // Calculate expected price and output amount first
        expectedPrice = (ethBalance * 1e18) / tokenBalance;
        tokenAmount = getAmountOut(msg.value, ethBalance, tokenBalance);
        require(tokenAmount > 0, "Insufficient output amount");

        // Validate slippage
        uint256 actualPrice = (msg.value * 1e18) / tokenAmount;
        validateSlippage(expectedPrice, actualPrice);

        // Effects before interactions
        _beforeSwap(msg.value, true);

        // Interactions last (CEI pattern)
        memeCoin.safeTransfer(msg.sender, tokenAmount);

        emit Swap(msg.sender, true, msg.value, tokenAmount);
    }


    function swapExactTokensForETH(uint256 tokenAmount)
        external
        nonReentrant
        nonReentrantSwap
        notPaused
        protectMEV
        returns (uint256 ethAmount, uint256 expectedPrice)
    {
        require(tokenAmount > 0, "Invalid token amount");

        uint256 ethBalance = address(this).balance;
        uint256 tokenBalance = memeCoin.balanceOf(address(this));

        // Calculate expected price and output amount first
        expectedPrice = (tokenBalance * 1e18) / ethBalance;
        ethAmount = getAmountOut(tokenAmount, tokenBalance, ethBalance);
        require(ethAmount > 0, "Insufficient output amount");

        // Validate slippage
        uint256 actualPrice = (tokenAmount * 1e18) / ethAmount;
        validateSlippage(expectedPrice, actualPrice);

        // Effects before interactions
        _beforeSwap(tokenAmount, false);

        // Transfer tokens first (CEI pattern)
        memeCoin.safeTransferFrom(msg.sender, address(this), tokenAmount);
        
        // Then send ETH
        SafeTransferLib.safeTransferETH(msg.sender, ethAmount);

        emit Swap(msg.sender, false, tokenAmount, ethAmount);
    }

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public view returns (uint256 amountOut) {
        require(amountIn > 0, "INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "INSUFFICIENT_LIQUIDITY");

        uint256 currentPrice = (reserveIn * 1e18) / reserveOut;
        uint256 targetPrice = 1e18; // Base price of 1:1

        // Calculate liquidity based on Hydra curve
        uint256 curveAdjustedLiquidity = hydra.calculateLiquidity(
            reserveIn,
            reserveOut,
            currentPrice,
            targetPrice,
            hydraConfig
        );

        // Apply the curve-adjusted liquidity
        amountOut = (amountIn * curveAdjustedLiquidity * 997) / (reserveIn * 1000);
    }

     function _beforeSwap(uint256 amount, bool isEthToToken) internal {
        // Add any pre-swap state changes here
    }

    // Required for receiving ETH
    receive() external payable {}
}