// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/MemeDexFactory.sol";
import "../src/MemePool.sol";
import "../src/MemeCoin.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK", 18) {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract MemeDexFactoryTest is Test {
    MemeDexFactory public factory;
    MockToken public token;
    
    address public owner;
    address public user;
    uint256 constant COMMITMENT_DELAY = 5 minutes;

    event PoolCommitted(bytes32 indexed commitmentHash, address indexed token);
    event PoolCreated(address indexed token, address indexed pool, uint256 poolsCount);

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");
        
        vm.startPrank(owner);
        factory = new MemeDexFactory();
        token = new MockToken();
        vm.stopPrank();
    }

    function testPoolCreationFlow() public {
        vm.startPrank(owner);
        
        // Step 1: Commit pool creation
        bytes32 commitmentHash = _commitPool(address(token));
        
        // Try to create pool too early
        vm.expectRevert("Too early");
        factory.createPool(address(token), commitmentHash);
        
        // Wait for commitment delay
        vm.warp(block.timestamp + COMMITMENT_DELAY);
        
        // Step 2: Create pool
        address pool = factory.createPool(address(token), commitmentHash);
        
        // Verify pool creation
        assertFalse(pool == address(0), "Pool should be created");
        assertEq(factory.getPool(address(token)), pool, "Pool mapping incorrect");
        assertEq(factory.allPoolsLength(), 1, "Pool count should be 1");
        
        vm.stopPrank();
    }

    function testUnauthorizedAccess() public {
        vm.startPrank(user);
        
        // Try to commit pool as non-owner
        vm.expectRevert("Not authorized");
        factory.commitPoolCreation(address(token));
        
        // Try to create pool as non-owner
        vm.expectRevert("Not authorized");
        factory.createPool(address(token), bytes32(0));
        
        vm.stopPrank();
    }

    function testInvalidCommitment() public {
        vm.startPrank(owner);
        
        // Try to create pool without commitment
        vm.expectRevert("Invalid commitment");
        factory.createPool(address(token), bytes32(0));
        
        // Try with invalid commitment hash
        bytes32 fakeCommitment = keccak256("fake");
        vm.expectRevert("Invalid commitment");
        factory.createPool(address(token), fakeCommitment);
        
        vm.stopPrank();
    }

    function testDuplicatePool() public {
        vm.startPrank(owner);
        
        // Create first pool
        bytes32 commitment1 = _commitPool(address(token));
        vm.warp(block.timestamp + COMMITMENT_DELAY);
        factory.createPool(address(token), commitment1);
        
        // Try to commit same token again
        vm.expectRevert("Pool exists");
        factory.commitPoolCreation(address(token));
        
        vm.stopPrank();
    }

    function testPoolInitialization() public {
        vm.startPrank(owner);
        
        // Create pool
        bytes32 commitment = _commitPool(address(token));
        vm.warp(block.timestamp + COMMITMENT_DELAY);
        address poolAddr = factory.createPool(address(token), commitment);
        
        // Verify pool state
        MemePool pool = MemePool(payable(poolAddr));
        assertEq(address(pool.memeCoin()), address(token), "Wrong token");
        assertEq(address(pool.poolAuthority()), address(factory), "Wrong authority");
        
        vm.stopPrank();
    }

    function testFuzzCommitmentDelay(uint256 waitTime) public {
        vm.startPrank(owner);
        
        // Commit pool creation
        bytes32 commitment = _commitPool(address(token));
        
        // Bound wait time between 0 and 1 day
        waitTime = bound(waitTime, 0, 1 days);
        vm.warp(block.timestamp + waitTime);
        
        if (waitTime < COMMITMENT_DELAY) {
            vm.expectRevert("Too early");
            factory.createPool(address(token), commitment);
        } else {
            address pool = factory.createPool(address(token), commitment);
            assertFalse(pool == address(0), "Pool should be created");
        }
        
        vm.stopPrank();
    }

    // Helper function to commit pool creation
    function _commitPool(address tokenAddr) internal returns (bytes32) {
        vm.expectEmit(true, true, false, false);
        bytes32 expectedHash = keccak256(abi.encodePacked(
            tokenAddr,
            msg.sender,
            block.timestamp
        ));
        emit PoolCommitted(expectedHash, tokenAddr);
        
        factory.commitPoolCreation(tokenAddr);
        return expectedHash;
    }
}

