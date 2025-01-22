// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Auth, Authority} from "../../lib/solmate/src/auth/Auth.sol";
import {ReentrancyGuard} from "../../lib/solmate/src/utils/ReentrancyGuard.sol";

/**
 * @title PausablePool
 * @author Degen4Life Team
 * @notice Base contract for pausable liquidity pools with enhanced security features
 * @dev Implements emergency pause, timelock, and MEV protection mechanisms
 */
contract PausablePool is Auth, ReentrancyGuard {
    // State variables for pause mechanism
    bool public paused;
    uint256 public lastPauseTime;
    
    // Timelock settings
    uint256 public constant TIMELOCK_DELAY = 24 hours;
    mapping(bytes32 => uint256) public timelockDeadlines;
    mapping(bytes32 => bool) public timelockExecuted;
    
    // Slippage protection
    uint256 public constant MAX_SLIPPAGE_BPS = 100; // 1%
    uint256 public slippageLimit;
    
    // MEV protection
    uint256 public constant MIN_BLOCKS_DELAY = 1;
    mapping(address => uint256) public lastBlockTraded;
    
    // Events
    event PoolPaused(address indexed admin);
    event PoolUnpaused(address indexed admin);
    event TimelockProposed(bytes32 indexed proposalId, uint256 executeAfter);
    event TimelockExecuted(bytes32 indexed proposalId);
    event SlippageLimitUpdated(uint256 newLimit);
    
    /**
     * @notice Initializes the PausablePool contract
     * @param _authority Address of the authority contract
     */
    constructor(address _authority) Auth(msg.sender, Authority(_authority)) {
        slippageLimit = MAX_SLIPPAGE_BPS;
    }
    
    /**
     * @notice Modifier to check if contract is not paused
     */
    modifier notPaused() {
        require(!paused, "Pool is paused");
        _;
    }
    
    /**
     * @notice Modifier to enforce MEV protection
     */
    modifier protectMEV() {
        require(
            block.number > lastBlockTraded[msg.sender] + MIN_BLOCKS_DELAY,
            "Must wait for next block"
        );
        lastBlockTraded[msg.sender] = block.number;
        _;
    }
    
    /**
     * @notice Pauses all pool operations
     */
    function pause() external requiresAuth {
        require(!paused, "Already paused");
        paused = true;
        lastPauseTime = block.timestamp;
        emit PoolPaused(msg.sender);
    }
    
    /**
     * @notice Unpauses pool operations
     */
    function unpause() external requiresAuth {
        require(paused, "Not paused");
        paused = false;
        emit PoolUnpaused(msg.sender);
    }
    
    /**
     * @notice Proposes a parameter change with timelock
     * @param paramId Unique identifier for the parameter
     * @param value New value to set after timelock
     */
    function proposeChange(bytes32 paramId, uint256 value) external requiresAuth {
        require(timelockDeadlines[paramId] == 0, "Change already pending");
        timelockDeadlines[paramId] = block.timestamp + TIMELOCK_DELAY;
        emit TimelockProposed(paramId, timelockDeadlines[paramId]);
    }
    
    /**
     * @notice Executes a timelocked parameter change
     * @param paramId Parameter identifier
     * @return deadline Timelock deadline timestamp
     */
    function checkTimelock(bytes32 paramId) internal returns (uint256 deadline) {
        deadline = timelockDeadlines[paramId];
        require(deadline != 0, "No proposal exists");
        require(block.timestamp >= deadline, "Timelock not expired");
        require(!timelockExecuted[paramId], "Already executed");
        
        timelockExecuted[paramId] = true;
        emit TimelockExecuted(paramId);
    }
    
    /**
     * @notice Validates trade against slippage limit
     * @param expectedPrice Expected execution price
     * @param actualPrice Actual execution price
     */
    function validateSlippage(uint256 expectedPrice, uint256 actualPrice) internal view {
        require(expectedPrice > 0, "Invalid expected price");
        uint256 priceDiff = expectedPrice > actualPrice ? 
            expectedPrice - actualPrice : actualPrice - expectedPrice;
        require(
            (priceDiff * 10000) / expectedPrice <= slippageLimit,
            "Slippage exceeded"
        );
    }
    
    /**
     * @notice Updates slippage limit (requires timelock)
     * @param newLimit New slippage limit in basis points
     */
    function updateSlippageLimit(uint256 newLimit) external requiresAuth {
        bytes32 paramId = keccak256("SLIPPAGE_LIMIT");
        uint256 deadline = checkTimelock(paramId);
        require(newLimit <= MAX_SLIPPAGE_BPS, "Exceeds maximum");
        
        slippageLimit = newLimit;
        emit SlippageLimitUpdated(newLimit);
    }
}