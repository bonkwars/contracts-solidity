// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Auth, Authority} from "../lib/solmate/src/auth/Auth.sol";
import {ReentrancyGuard} from "../lib/solmate/src/utils/ReentrancyGuard.sol";
import {SafeTransferLib} from "../lib/solmate/src/utils/SafeTransferLib.sol";
import {ERC20} from "../lib/solmate/src/tokens/ERC20.sol";
import {FixedPointMathLib} from "../lib/solmate/src/utils/FixedPointMathLib.sol";

/**
 * @title MarketManager
 * @author Degen4Life Team
 * @notice Manages trades, fees, and revenue distribution
 * @dev Implements fee collection and distribution to stakeholders
 */
contract MarketManager is Auth, ReentrancyGuard {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

     uint256 public constant MAX_RECIPIENTS = 10;
    uint256 public constant MAX_FEE_BPS = 100; // 1%
    
    error TooManyRecipients();
    error InvalidRecipients();
    error InvalidShares();
    error SharesExceedMax();

    /// @notice Fee collector address
    address public feeCollector;
    /// @notice Protocol fee in basis points (0.3% = 30)
    uint256 public protocolFeeBps;
    /// @notice Revenue sharing recipients
    address[] public revenueRecipients;
    /// @notice Revenue sharing percentages in basis points
    uint256[] public revenueShares;
    /// @notice Accumulated fees per token
    mapping(address => uint256) public accumulatedFees;
    /// @notice Last distribution timestamp per token
    mapping(address => uint256) public lastDistribution;
    /// @notice Distribution period in seconds (default 24 hours)
    uint256 public distributionPeriod;

    event FeeCollected(address indexed token, uint256 amount);
    event RevenueDistributed(address indexed token, uint256 amount);
    event FeeParametersUpdated(uint256 protocolFeeBps);
    event RevenueRecipientsUpdated(address[] recipients, uint256[] shares);

    /**
     * @notice Initializes the MarketManager contract
     * @param _authority Address of the authority contract
     * @param _feeCollector Address to collect fees
     * @param _protocolFeeBps Protocol fee in basis points
     */
    constructor(
        address _authority,
        address _feeCollector,
        uint256 _protocolFeeBps
    ) Auth(msg.sender, Authority(_authority)) {
        require(_feeCollector != address(0), "Invalid fee collector");
        require(_protocolFeeBps <= 100, "Fee too high"); // Max 1%

        feeCollector = _feeCollector;
        protocolFeeBps = _protocolFeeBps;
        distributionPeriod = 24 hours;
    }

    /**
     * @notice Processes a trade and collects fees
     * @param token Token being traded
     * @param amount Trade amount
     * @return fee Fee amount collected
     */
    function processTrade(
        address token,
        uint256 amount
    ) external nonReentrant returns (uint256 fee) {
        fee = (amount * protocolFeeBps) / 10000;
        accumulatedFees[token] += fee;
        
        ERC20(token).safeTransferFrom(msg.sender, address(this), fee);
        
        emit FeeCollected(token, fee);
        return fee;
    }

    /**
     * @notice Distributes accumulated fees to recipients
     * @param token Token to distribute
     */
    function distributeRevenue(address token) external nonReentrant {
        require(
            block.timestamp >= lastDistribution[token] + distributionPeriod,
            "Distribution period not elapsed"
        );
        require(revenueRecipients.length > 0, "No recipients configured");
        require(
            revenueRecipients.length == revenueShares.length,
            "Recipients/shares mismatch"
        );

        uint256 totalFees = accumulatedFees[token];
        require(totalFees > 0, "No fees to distribute");

        // Reset state before external calls
        accumulatedFees[token] = 0;
        lastDistribution[token] = block.timestamp;

        ERC20 tokenContract = ERC20(token);
        uint256 remainingFees = totalFees;

        // Cache array length
        uint256 recipientCount = revenueRecipients.length;
        
        // Distribute to recipients
        for(uint256 i = 0; i < recipientCount; i++) {
            uint256 share = (totalFees * revenueShares[i]) / 10000;
            if(share > 0) {
                tokenContract.safeTransfer(revenueRecipients[i], share);
                remainingFees -= share;
            }
        }

        // Send any remaining dust to fee collector
        if(remainingFees > 0) {
            tokenContract.safeTransfer(feeCollector, remainingFees);
        }

        emit RevenueDistributed(token, totalFees);
    }

    /**
     * @notice Updates protocol fee parameters
     * @param _protocolFeeBps New protocol fee in basis points
     */
    function updateFeeParameters(uint256 _protocolFeeBps) external requiresAuth {
        require(_protocolFeeBps <= 100, "Fee too high"); // Max 1%
        protocolFeeBps = _protocolFeeBps;
        emit FeeParametersUpdated(_protocolFeeBps);
    }

    /**
     * @notice Updates revenue sharing recipients and their shares
     * @param _recipients Array of recipient addresses
     * @param _shares Array of shares in basis points
     */
  function updateRevenueRecipients(
        address[] calldata _recipients,
        uint256[] calldata _shares
    ) external requiresAuth {
        // Input validation
        if(_recipients.length == 0) revert InvalidRecipients();
        if(_recipients.length > MAX_RECIPIENTS) revert TooManyRecipients();
        if(_recipients.length != _shares.length) revert InvalidRecipients();
        
        uint256 totalShares = 0;
        for(uint256 i = 0; i < _shares.length; i++) {
            if(_recipients[i] == address(0)) revert InvalidRecipients();
            totalShares += _shares[i];
        }
        if(totalShares > 10000) revert SharesExceedMax();

        // Clear existing arrays
        delete revenueRecipients;
        delete revenueShares;
        
        // Update with new values
        for(uint256 i = 0; i < _recipients.length; i++) {
            revenueRecipients.push(_recipients[i]);
            revenueShares.push(_shares[i]);
        }
        
        emit RevenueRecipientsUpdated(_recipients, _shares);
    }

    /**
     * @notice Updates the distribution period
     * @param _distributionPeriod New distribution period in seconds
     */
    function updateDistributionPeriod(
        uint256 _distributionPeriod
    ) external requiresAuth {
        require(_distributionPeriod > 0, "Invalid period");
        distributionPeriod = _distributionPeriod;
    }

    /**
     * @notice Gets accumulated fees for a token
     * @param token Token address
     * @return uint256 Accumulated fees
     */
    function getAccumulatedFees(address token) external view returns (uint256) {
        return accumulatedFees[token];
    }

    /**
     * @notice Gets all revenue recipients and their shares
     * @return recipients Array of recipient addresses
     * @return shares Array of shares in basis points
     */
    function getRevenueRecipients() external view returns (
        address[] memory recipients,
        uint256[] memory shares
    ) {
        return (revenueRecipients, revenueShares);
    }
}