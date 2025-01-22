// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Owned} from "../../lib/solmate/src/auth/Owned.sol";
import "../../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import "../../lib/openzeppelin-contracts/contracts/utils/Address.sol";

/**
 * @title AntiBot
 * @author Degen4Life Team
 * @notice Anti-bot protection for token trading
 * @dev Implements various measures to prevent bot trading
 * @custom:security-contact security@memeswap.exchange
 */
contract AntiBot is Owned {
    using Address for address;

    struct TradingLimit {
        uint256 maxBuyAmount;
        uint256 maxSellAmount;
        uint256 cooldownPeriod;
        uint256 maxTxPerDay;
    }

    struct UserTrading {
        uint256 lastTradeTime;
        uint256 dailyTxCount;
        uint256 dayStartTime;
        uint256 totalBought;
        uint256 totalSold;
    }

    mapping(address => bool) public isBot;
    mapping(address => UserTrading) public userTrading;
    mapping(address => bool) public whitelisted;

    TradingLimit public tradingLimit;
    bool public tradingEnabled;
    uint256 public launchTime;
    uint256 public botPenaltyFee;

    // Advanced bot detection
    uint256 public constant MIN_TIME_BETWEEN_TX = 2; // blocks
    uint256 public constant SUSPICIOUS_TX_COUNT = 5;
    uint256 public constant SUSPICIOUS_GAS_PRICE = 1000 gwei;

    event BotDetected(address indexed bot, string reason);
    event TradingLimitUpdated(uint256 maxBuy, uint256 maxSell);
    event TradingEnabled();

    constructor() Owned(msg.sender) {
        tradingLimit = TradingLimit({
            maxBuyAmount: 1000 * 10 ** 18, // 1000 tokens
            maxSellAmount: 500 * 10 ** 18, // 500 tokens
            cooldownPeriod: 5 minutes,
            maxTxPerDay: 10
        });
        botPenaltyFee = 50; // 50% penalty for detected bots
    }

    modifier onlyAfterLaunch() {
        require(
            tradingEnabled && block.timestamp >= launchTime,
            "Trading not started"
        );
        _;
    }

    function enableTrading() external onlyOwner {
        tradingEnabled = true;
        launchTime = block.timestamp;
        emit TradingEnabled();
    }

    function checkAndUpdateTrading(
        address account,
        uint256 amount,
        bool isBuy
    ) external virtual onlyAfterLaunch returns (uint256 penaltyAmount) {
        require(!isBot[account], "Bot detected");
        if (whitelisted[account]) return 0;

        UserTrading storage user = userTrading[account];

        // Reset daily counts if new day
        if (block.timestamp >= user.dayStartTime + 1 days) {
            user.dailyTxCount = 0;
            user.dayStartTime = block.timestamp;
        }

        // Check trading limits
        require(
            user.dailyTxCount < tradingLimit.maxTxPerDay,
            "Daily limit reached"
        );
        require(
            block.timestamp >= user.lastTradeTime + tradingLimit.cooldownPeriod,
            "Cooldown period"
        );

        // Bot detection checks
        if (_isLikelyBot(account)) {
            isBot[account] = true;
            emit BotDetected(account, "Suspicious behavior");
            return (amount * botPenaltyFee) / 100;
        }

        // Update user trading info
        user.lastTradeTime = block.timestamp;
        user.dailyTxCount++;

        if (isBuy) {
            require(amount <= tradingLimit.maxBuyAmount, "Exceeds max buy");
            user.totalBought += amount;
        } else {
            require(amount <= tradingLimit.maxSellAmount, "Exceeds max sell");
            user.totalSold += amount;
        }

        return 0;
    }

    function _isLikelyBot(address account) internal view returns (bool) {
        // Check contract interaction
        if (account.code.length > 0) return true;

        UserTrading storage user = userTrading[account];

        // Check transaction patterns
        if (
            block.number - user.lastTradeTime < MIN_TIME_BETWEEN_TX &&
            user.dailyTxCount >= SUSPICIOUS_TX_COUNT
        ) {
            return true;
        }

        // Check gas price manipulation
        if (tx.gasprice > SUSPICIOUS_GAS_PRICE) {
            return true;
        }

        return false;
    }

    function updateTradingLimits(
        uint256 maxBuy,
        uint256 maxSell,
        uint256 cooldown,
        uint256 maxDaily
    ) external onlyOwner {
        tradingLimit.maxBuyAmount = maxBuy;
        tradingLimit.maxSellAmount = maxSell;
        tradingLimit.cooldownPeriod = cooldown;
        tradingLimit.maxTxPerDay = maxDaily;
        emit TradingLimitUpdated(maxBuy, maxSell);
    }

    function whitelistAddress(address account, bool status) external onlyOwner {
        whitelisted[account] = status;
    }
}
