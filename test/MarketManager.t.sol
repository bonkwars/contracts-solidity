// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/MarketManager.sol";
import "../lib/solmate/src/tokens/ERC20.sol";
import "../lib/solmate/src/auth/Auth.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK", 18) {
        _mint(msg.sender, 1000000 * 10**18);
    }
}

contract MockAuthority is Authority {
    mapping(address => mapping(address => mapping(bytes4 => bool))) public canCall;
    
    constructor(address owner) {
        // Batch set permissions for common selectors
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = MarketManager.updateFeeParameters.selector;
        selectors[1] = MarketManager.updateRevenueRecipients.selector;  
        selectors[2] = MarketManager.updateDistributionPeriod.selector;

        for(uint i = 0; i < selectors.length; i++) {
            canCall[owner][address(0)][selectors[i]] = true;
        }
    }
}

contract MarketManagerTest is Test {
    // Constants for cleaner tests
    uint256 constant FEE_BPS = 30; // 0.3%
    uint256 constant TRADE_AMOUNT = 1000 * 10**18;
    uint256 constant MIN_DISTRIBUTION_PERIOD = 1 hours;
    uint256 constant MAX_FEE_BPS = 100; // 1%
    
    // Common storage
    MarketManager public manager;
    MockToken public token;
    address public owner;
    address public trader;
    address public feeCollector;
    address[] public recipients;
    uint256[] public shares;
    
    // Events to test
    event FeeCollected(address indexed token, uint256 amount);
    event RevenueDistributed(address indexed token, uint256 amount);
    event FeeParametersUpdated(uint256 protocolFeeBps);
    event RevenueRecipientsUpdated(address[] recipients, uint256[] shares);

     function setUp() public {
        owner = address(this);
        trader = makeAddr("trader");
        feeCollector = makeAddr("feeCollector");
        
        vm.deal(trader, 100 ether);
        
        // Deploy contracts with proper authority setup
        MockAuthority auth = new MockAuthority(address(this));
        manager = new MarketManager(address(auth), feeCollector, FEE_BPS);
        token = new MockToken();
        
        // Transfer tokens to trader
        token.transfer(trader, TRADE_AMOUNT * 2);

        // Set up revenue recipients
        recipients = new address[](2);
        recipients[0] = makeAddr("recipient1");
        recipients[1] = makeAddr("recipient2");
        
        shares = new uint256[](2);
        shares[0] = 6000; // 60%
        shares[1] = 3000; // 30%

        // Update revenue recipients using proper authorization
        vm.prank(owner);
        manager.updateRevenueRecipients(recipients, shares);
    }

    function testInitialConfiguration() public {
        assertEq(manager.feeCollector(), feeCollector);
        assertEq(manager.protocolFeeBps(), FEE_BPS);
        assertEq(manager.distributionPeriod(), 24 hours);

        (address[] memory storedRecipients, uint256[] memory storedShares) = manager.getRevenueRecipients();
        assertEq(storedRecipients.length, recipients.length);
        assertEq(storedShares.length, shares.length);
        
        for(uint i = 0; i < recipients.length; i++) {
            assertEq(storedRecipients[i], recipients[i]);
            assertEq(storedShares[i], shares[i]);
        }
    }

    function testProcessTrade() public {
        uint256 expectedFee = (TRADE_AMOUNT * FEE_BPS) / 10000;

        vm.startPrank(trader);
        token.approve(address(manager), expectedFee);
        
        vm.expectEmit(true, false, false, true);
        emit FeeCollected(address(token), expectedFee);
        
        uint256 actualFee = manager.processTrade(address(token), TRADE_AMOUNT);
        vm.stopPrank();

        assertEq(actualFee, expectedFee, "Fee calculation mismatch");
        assertEq(token.balanceOf(address(manager)), expectedFee, "Fee not collected");
        assertEq(manager.getAccumulatedFees(address(token)), expectedFee, "Accumulated fees mismatch");
    }

    function testRevenueDistribution() public {
        // Process trade to accumulate fees
        uint256 fee = (TRADE_AMOUNT * FEE_BPS) / 10000;
        vm.startPrank(trader);
        token.approve(address(manager), fee);
        manager.processTrade(address(token), TRADE_AMOUNT);
        vm.stopPrank();

        // Advance time to allow distribution
        skip(24 hours);

        // Distribute revenue
        vm.expectEmit(true, false, false, true);
        emit RevenueDistributed(address(token), fee);
        
        manager.distributeRevenue(address(token));

        // Verify distributions
        assertEq(token.balanceOf(recipients[0]), (fee * shares[0]) / 10000, "Recipient 1 share incorrect");
        assertEq(token.balanceOf(recipients[1]), (fee * shares[1]) / 10000, "Recipient 2 share incorrect");
        assertEq(token.balanceOf(feeCollector), fee - ((fee * (shares[0] + shares[1])) / 10000), "Fee collector share incorrect");
    }

    function testFeeParameterUpdates() public {
        uint256 newFeeBps = 50; // 0.5%
        
        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit FeeParametersUpdated(newFeeBps);
        manager.updateFeeParameters(newFeeBps);
        
        assertEq(manager.protocolFeeBps(), newFeeBps);

        // Test fee too high
        vm.expectRevert("Fee too high");
        vm.prank(owner);
        manager.updateFeeParameters(MAX_FEE_BPS + 1);
    }

    function testDistributionPeriodEnforcement() public {
        // Setup revenue 
        uint256 fee = (TRADE_AMOUNT * FEE_BPS) / 10000;
        vm.startPrank(trader);
        token.approve(address(manager), fee);
        manager.processTrade(address(token), TRADE_AMOUNT);
        vm.stopPrank();

        // Try distribute too early
        vm.expectRevert("Distribution period not elapsed");
        manager.distributeRevenue(address(token));

        // Advance time partially and try again
        skip(12 hours);
        vm.expectRevert("Distribution period not elapsed");
        manager.distributeRevenue(address(token));

        // Advance remaining time
        skip(12 hours);
        manager.distributeRevenue(address(token)); // Should succeed
    }

    function testFuzzRevenueShares(uint256 share1, uint256 share2) public {
        vm.assume(share1 <= 10000 && share2 <= 10000);
        vm.assume(share1 + share2 <= 10000);

        // Update shares
        shares[0] = share1;
        shares[1] = share2;

        vm.prank(owner);
        manager.updateRevenueRecipients(recipients, shares);

        // Process trade and distribute
        uint256 fee = (TRADE_AMOUNT * FEE_BPS) / 10000;
        vm.startPrank(trader);
        token.approve(address(manager), fee);
        manager.processTrade(address(token), TRADE_AMOUNT);
        vm.stopPrank();

        skip(24 hours);
        manager.distributeRevenue(address(token));

        // Verify distributions are proportional
        uint256 recipient1Balance = token.balanceOf(recipients[0]);
        uint256 recipient2Balance = token.balanceOf(recipients[1]);

        if (share1 > 0) {
            assertApproxEqRel(recipient1Balance, (fee * share1) / 10000, 1e16); // 1% tolerance
        }
        if (share2 > 0) {
            assertApproxEqRel(recipient2Balance, (fee * share2) / 10000, 1e16); // 1% tolerance
        }
    }

    function testRevertOnInvalidUpdates() public {
        vm.startPrank(owner);

        // Test empty recipients
        address[] memory emptyRecipients = new address[](0);
        uint256[] memory emptyShares = new uint256[](0);
        vm.expectRevert("Empty recipients");
        manager.updateRevenueRecipients(emptyRecipients, emptyShares);

        // Test mismatched arrays
        address[] memory moreRecipients = new address[](3);
        vm.expectRevert("Length mismatch");
        manager.updateRevenueRecipients(moreRecipients, shares);

        // Test excessive shares
        shares[0] = 9000;
        shares[1] = 2000; // Total > 100%
        vm.expectRevert("Total shares exceeds 100%");
        manager.updateRevenueRecipients(recipients, shares);

        vm.stopPrank();
    }

    receive() external payable {}
}