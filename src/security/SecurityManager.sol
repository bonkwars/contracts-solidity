// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Auth, Authority} from "../../lib/solmate/src/auth/Auth.sol";
import {ReentrancyGuard} from "../../lib/solmate/src/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "../../lib/solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "../../lib/solmate/src/tokens/ERC20.sol";
import {FixedPointMathLib} from "../../lib/solmate/src/utils/FixedPointMathLib.sol";
import {IFalconVerifier} from "./interfaces/IFalconVerifier.sol";

/**
 * @title SecurityManager
 * @author Degen4Life Team
 * @notice Manages security features and trading restrictions
 * @dev Implements security checks, blacklisting, and emergency controls
 * @custom:security-contact security@memeswap.exchange
 */
contract SecurityManager is Auth, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    /// @notice Maximum possible uint256 value
    uint256 public constant MAX_UINT = type(uint256).max;
    /// @notice Maximum trade size in basis points (5% of total supply)
    uint256 public constant MAX_TRADE_SIZE_BPS = 500;
    /// @notice Maximum price impact in basis points (10%)
    uint256 public constant MAX_PRICE_IMPACT_BPS = 1000;
    /// @notice Circuit breaker threshold in basis points (50%)
    uint256 public constant CIRCUIT_BREAKER_THRESHOLD = 5000;

    /// @notice Minimum blocks between trades for a single address
    uint256 public constant MIN_TIME_BETWEEN_TRADES = 1;
    /// @notice Trading window duration for rate limiting
    uint256 public constant TRADE_WINDOW = 15 minutes;
    /// @notice Cooldown period after hitting limits
    uint256 public constant COOLDOWN_PERIOD = 1 hours;

    /// @notice Emergency mode status - if true, all trading is suspended
    bool public emergencyMode;
    /// @notice Mapping of last trade timestamp per address
    mapping(address => uint256) public lastTradeTime;
    /// @notice Mapping of cumulative trading volume per address
    mapping(address => uint256) public tradingVolume;
    /// @notice Mapping of blacklisted addresses
    mapping(address => bool) public blacklisted;

    /// @notice Mapping to track used signatures to prevent replay attacks
    mapping(bytes32 => bool) public usedSignatures;
    /// @notice Mapping of validation nonces per address
    mapping(address => uint256) public validationNonces;

    /// @notice IFalconVerifier instance used for Falcon signature verification
    IFalconVerifier public falconVerifier;

    /// @notice Emitted when emergency mode status changes
    event SecurityStateChanged(bool emergencyMode);
    /// @notice Emitted when an address is blacklisted
    event AddressBlacklisted(address indexed account);
    /// @notice Emitted when a security limit is updated
    event SecurityLimitUpdated(string parameter, uint256 value);
    /// @notice Emitted when suspicious activity is detected
    event AnomalyDetected(string anomalyType, address indexed source);
    /// @notice Emitted when a validation fails
    event ValidationFailed(string reason, bytes data);

    /**
     * @notice Initializes the SecurityManager contract
     * @param _authority Address of the authority contract for access control
     */
    constructor(address _authority) Auth(msg.sender, Authority(_authority)) {
        emergencyMode = false;
    }

    /**
     * @notice Sets the Falcon verifier contract address
     * @param _falconVerifier Address of the Falcon verifier contract
     * @dev Only callable by authorized addresses
     */
    function setFalconVerifier(address _falconVerifier) external requiresAuth {
        require(_falconVerifier != address(0), "Invalid verifier address");
        falconVerifier = IFalconVerifier(_falconVerifier);
    }
    
    /**
     * @notice Validates a trade against security parameters
     * @param trader Address initiating the trade
     * @param token Token being traded
     * @param amount Amount of tokens in the trade
     * @param expectedPrice Expected price for slippage check
     * @return bool True if trade is valid
     * @dev Checks trade size, frequency, and price impact
     */
    function validateTrade(
        address trader,
        address token,
        uint256 amount,
        uint256 expectedPrice
    ) external returns (bool) {
        require(!emergencyMode, "Trading suspended");
        require(!blacklisted[trader], "Address blacklisted");
        require(_validateTradeSize(token, amount), "Trade size too large");
        require(_validateTradeFrequency(trader), "Trading too frequently");
        require(
            _validatePriceImpact(expectedPrice, amount),
            "Price impact too high"
        );

        lastTradeTime[trader] = block.timestamp;
        tradingVolume[trader] += amount;

        return true;
    }

    function validateSignature(
        bytes32 hash,
        bytes memory signature,
        address signer
    ) external returns (bool) {
        require(!usedSignatures[hash], "Signature already used");
        require(
            _validateSignatureFormat(signature),
            "Invalid signature format"
        );

        address recoveredSigner = _recoverSigner(hash, signature);
        require(recoveredSigner == signer, "Invalid signature");

        usedSignatures[hash] = true;
        validationNonces[signer]++;

        return true;
    }

    function _validateTradeSize(
        address token,
        uint256 amount
    ) internal view returns (bool) {
        uint256 totalSupply = ERC20(token).totalSupply();
        return amount <= totalSupply.mulDivDown(MAX_TRADE_SIZE_BPS, 10000);
    }

    function _validateTradeFrequency(
        address trader
    ) internal view returns (bool) {
        if (lastTradeTime[trader] == 0) return true;
        return
            block.timestamp >= lastTradeTime[trader] + MIN_TIME_BETWEEN_TRADES;
    }

    function _validatePriceImpact(
        uint256 expectedPrice,
        uint256 actualPrice
    ) internal pure returns (bool) {
        if (expectedPrice == 0) return false;
        uint256 priceDiff = expectedPrice > actualPrice
            ? expectedPrice - actualPrice
            : actualPrice - expectedPrice;
        return
            priceDiff.mulDivDown(10000, expectedPrice) <= MAX_PRICE_IMPACT_BPS;
    }

    function _validateSignatureFormat(
        bytes memory signature
    ) internal pure returns (bool) {
        return signature.length == 65;
    }

    function _recoverSigner(
        bytes32 hash,
        bytes memory signature
    ) internal pure returns (address) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        if (v < 27) v += 27;
        require(v == 27 || v == 28, "Invalid signature v value");

        return ecrecover(hash, v, r, s);
    }

    function setEmergencyMode(bool _emergencyMode) external requiresAuth {
        emergencyMode = _emergencyMode;
        emit SecurityStateChanged(_emergencyMode);
    }

    function blacklistAddress(address account) external requiresAuth {
        blacklisted[account] = true;
        emit AddressBlacklisted(account);
    }

    function clearTradingHistory(address trader) external requiresAuth {
        lastTradeTime[trader] = 0;
        tradingVolume[trader] = 0;
    }

    function isAddressBlacklisted(
        address account
    ) external view returns (bool) {
        return blacklisted[account];
    }

    function getTraderStats(
        address trader
    )
        external
        view
        returns (uint256 lastTrade, uint256 volume, bool isBlacklisted)
    {
        return (
            lastTradeTime[trader],
            tradingVolume[trader],
            blacklisted[trader]
        );
    }

    function validateTransactionHash(
        bytes32 txHash
    ) external pure returns (bool) {
        return uint256(txHash) != 0;
    }
}