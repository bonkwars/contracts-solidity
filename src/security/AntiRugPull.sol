// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Owned} from "../../lib/solmate/src/auth/Owned.sol";
import {ReentrancyGuard} from "../../lib/solmate/src/utils/ReentrancyGuard.sol";
import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";

/**
 * @title AntiRugPull
 * @author Degen4Life Team
 * @notice Prevents rug pulls by implementing trading restrictions
 * @dev Implements sell limits, wallet size limits, and daily trading limits
 * @custom:security-contact security@memeswap.exchange
 */
contract AntiRugPull is Owned, ReentrancyGuard {
    struct TokenSecurity {
        uint256 maxSellPercentage; 
        uint256 maxWalletPercentage; 
        uint256 maxTotalSellPercentage; 
        bool securityEnabled;
    }

    mapping(address => TokenSecurity) public tokenSecurity;
    mapping(address => mapping(uint256 => uint256)) private dailySells;
    mapping(address => mapping(address => bool)) public whitelisted;
    mapping(address => mapping(address => uint256)) public walletSizes;
    mapping(address => mapping(address => uint256)) public dailyTrades;
    mapping(address => mapping(address => uint256)) public dailySellsCount;
    mapping(address => mapping(address => uint256)) public dailySellsAmount;
    mapping(address => mapping(address => uint256)) public dailyTradesCount;
    mapping(address => mapping(address => uint256)) public dailyTradesAmount;
    mapping(address => mapping(address => uint256)) public dailySellsCountTotal;
    mapping(address => mapping(address => uint256)) public dailyTradesCountTotal;
    mapping(address => mapping(address => uint256)) public dailySellsAmountTotal;
    mapping(address => mapping(address => uint256)) public dailyTradesAmountTotal;
    mapping(address => bool) public isTokenSecurityEnabled;

    event SecurityEnabled(address indexed token);
    event SecurityDisabled(address indexed token);

    constructor(address _owner) Owned(_owner) {}

    function enableSecurity(
        address token,
        uint256 maxSellPct,
        uint256 maxWalletPct,
        uint256 maxTotalSellPct
    ) public onlyOwner {
        require(
            maxSellPct <= 10000 && maxWalletPct <= 10000,
            "Invalid percentages"
        );

        tokenSecurity[token] = TokenSecurity({
            maxSellPercentage: maxSellPct,
            maxWalletPercentage: maxWalletPct,
            maxTotalSellPercentage: maxTotalSellPct,
            securityEnabled: true
        });
        isTokenSecurityEnabled[token] = true;

        emit SecurityEnabled(token);
    }

    function checkAndUpdateSell(
        address token,
        address seller,
        uint256 amount
    ) public nonReentrant returns (bool) {
        TokenSecurity storage security = tokenSecurity[token];
        require(isTokenSecurityEnabled[token], "Security not enabled");

        // Skip checks for whitelisted addresses
        if (whitelisted[token][seller]) return true;

        uint256 totalSupply = ERC20(token).totalSupply();

        // Check sell amount against max percentage (multiply by 100 for percentage)
        require(
            (amount * 10000) / totalSupply <= security.maxSellPercentage,
            "Sell amount too high"
        );

        // Check daily sell limit
        uint256 today = block.timestamp / 1 days;
        uint256 dailyTotal = dailySells[token][today] + amount;
        require(
            (dailyTotal * 10000) / totalSupply <= security.maxTotalSellPercentage,
            "Daily sell limit exceeded"
        );

        dailySells[token][today] = dailyTotal;
        return true;
    }

    function checkAndUpdateBalance(
        address token,
        address holder,
        uint256 amount,
        bool isReceiving
    ) public view returns (bool) {
        TokenSecurity storage security = tokenSecurity[token];
        if (!security.securityEnabled || !isTokenSecurityEnabled[token]) return true;

        // Skip checks for whitelisted addresses
        if (whitelisted[token][holder]) return true;

        if (isReceiving) {
            uint256 totalSupply = ERC20(token).totalSupply();
            uint256 newBalance = ERC20(token).balanceOf(holder) + amount;
            require(
                (newBalance * 10000) / totalSupply <= security.maxWalletPercentage,
                "Balance would exceed max"
            );
           
        }

        return true;
    }

    function setWhitelisted(address token, address account, bool status) external onlyOwner {
        whitelisted[token][account] = status;
    }

    function disableSecurity(address token) public onlyOwner {
        isTokenSecurityEnabled[token] = false;
        tokenSecurity[token].securityEnabled = false;
        emit SecurityDisabled(token);
    }
}