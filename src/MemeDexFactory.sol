// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./MemePool.sol";
import "./MemeCoin.sol";

/**
 * @title MemeDexFactory
 * @author Degen4Life Team
 * @notice Factory contract for creating and managing Meme DEX pools
 * @dev Creates and tracks liquidity pools for meme token pairs
 */
contract MemeDexFactory {
   mapping(address => address) public getPool;
    mapping(bytes32 => uint256) public poolCommitments;
    address[] public allPools;
    address public immutable owner;

    uint256 public constant COMMITMENT_DELAY = 5 minutes;

    event PoolCommitted(bytes32 indexed commitmentHash, address indexed token);
    event PoolCreated(address indexed token, address indexed pool, uint256 poolsCount);

    constructor() {
        owner = msg.sender;
    }

    function commitPoolCreation(address token) external {
        require(msg.sender == owner, "Not authorized");
        require(token != address(0), "Invalid token address");
        require(getPool[token] == address(0), "Pool exists");

        bytes32 commitmentHash = keccak256(abi.encodePacked(
            token,
            msg.sender,
            block.timestamp
        ));

        poolCommitments[commitmentHash] = block.timestamp;
        emit PoolCommitted(commitmentHash, token);
    }

    function createPool(address token, bytes32 commitmentHash) external returns (address pool) {
        require(msg.sender == owner, "Not authorized");
        require(poolCommitments[commitmentHash] != 0, "Invalid commitment");
        require(block.timestamp >= poolCommitments[commitmentHash] + COMMITMENT_DELAY, "Too early");
        require(token != address(0), "Invalid token address");
        require(getPool[token] == address(0), "Pool exists");

        // Validate commitment hash
        require(commitmentHash == keccak256(abi.encodePacked(
            token,
            msg.sender,
            poolCommitments[commitmentHash]
        )), "Invalid commitment hash");

        // Deploy pool with create2 for deterministic address
        bytes32 salt = keccak256(abi.encodePacked(token, commitmentHash));
        bytes memory bytecode = type(MemePool).creationCode;
        bytes memory encodedArgs = abi.encode(address(this));
        bytes memory combinedBytecode = bytes.concat(bytecode, encodedArgs);

        assembly {
            pool := create2(0, add(combinedBytecode, 32), mload(combinedBytecode), salt)
            if iszero(extcodesize(pool)) {
                revert(0, 0)
            }
        }

        // Initialize pool
        MemePool(payable(pool)).initialize(token);

        // Update state
        getPool[token] = pool;
        allPools.push(pool);
        delete poolCommitments[commitmentHash];
        
        emit PoolCreated(token, pool, allPools.length);
    }

    function allPoolsLength() external view returns (uint256) {
        return allPools.length;
    }
}