// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import {Treasury} from "contracts/treasury/Treasury.sol";
import {PaymentLedger} from "contracts/payments/PaymentLedger.sol";
import {IPaymentLedger} from "contracts/interfaces/IPaymentLedger.sol";
import {PaymentVerifier} from "contracts/payments/PaymentVerifier.sol";
import {PaymentApproval} from "contracts/payments/PaymentApproval.sol";
import {MarketplaceEscrow} from "contracts/payments/MarketplaceEscrow.sol";
import {RevenueSharing} from "contracts/dao-maker/RevenueSharing.sol";
import {PayoutDistributor} from "contracts/dao-maker/PayoutDistributor.sol";
import {IDAOToken} from "contracts/interfaces/IDAOToken.sol";
import {IReputationRegistry} from "contracts/interfaces/IReputationRegistry.sol";
import {IAgentRegistry} from "contracts/interfaces/IAgentRegistry.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MCK") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract MockDAOToken is ERC20 {
    uint256 public constant MAX_SUPPLY = 1_000_000e18;
    constructor() ERC20("DAO", "DAO") {}

    function getPastVotes(address, uint256) external view returns (uint256) {
        return 0;
    }

    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract PausableTest is Test {
    // Shared
    address owner;
    address user1;
    address user2;
    address user3;

    // Contracts
    Treasury treasury;
    PaymentLedger paymentLedger;
    PaymentVerifier paymentVerifier;
    PaymentApproval paymentApproval;
    MarketplaceEscrow marketplaceEscrow;
    RevenueSharing revenueSharing;
    PayoutDistributor payoutDistributor;
    MockERC20 mockToken;
    MockDAOToken mockDAOToken;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        mockToken = new MockERC20();

        // Deploy Treasury
        address[] memory signers = new address[](2);
        signers[0] = user1;
        signers[1] = user2;
        treasury = new Treasury(signers, 2);
        payable(address(treasury)).transfer(10 ether);

        // Deploy PaymentLedger
        paymentLedger = new PaymentLedger();

        // Deploy PaymentVerifier (with ledger)
        address[] memory tokens = new address[](1);
        tokens[0] = address(mockToken);
        paymentVerifier = new PaymentVerifier(
            address(paymentLedger),
            tokens,
            1_000_000e18,
            10_000_000e18,
            1_000_000e18,
            500_000e18,
            9_000_000e18
        );

        // Deploy PaymentApproval
        address[] memory approvalSigners = new address[](2);
        approvalSigners[0] = user1;
        approvalSigners[1] = user2;
        paymentApproval = new PaymentApproval(approvalSigners, 2, address(paymentVerifier), 0);

        // Deploy MarketplaceEscrow
        marketplaceEscrow = new MarketplaceEscrow(7 days);
        marketplaceEscrow.setMarketplace(address(this));

        // Deploy RevenueSharing
        revenueSharing = new RevenueSharing();

        // Deploy PayoutDistributor
        mockDAOToken = new MockDAOToken();
        address[] memory participants = new address[](0);
        payoutDistributor = new PayoutDistributor(
            IDAOToken(address(mockDAOToken)),
            IReputationRegistry(makeAddr("reputationRegistry")),
            IAgentRegistry(makeAddr("agentRegistry")),
            participants
        );
    }

    // ============ Treasury ============

    function testTreasuryPauseUnpause() public {
        assertFalse(treasury.paused());
        treasury.pause();
        assertTrue(treasury.paused());
        treasury.unpause();
        assertFalse(treasury.paused());
    }

    function testTreasurySubmitBlockedWhenPaused() public {
        treasury.pause();

        vm.prank(user1);
        vm.expectRevert("Pausable: paused");
        treasury.submitTransaction(user3, 100, bytes(""));
    }

    function testTreasuryConfirmBlockedWhenPaused() public {
        // Submit while unpaused
        vm.prank(user1);
        uint256 txId = treasury.submitTransaction(user3, 100, bytes(""));

        treasury.pause();

        vm.prank(user2);
        vm.expectRevert("Pausable: paused");
        treasury.confirmTransaction(txId);
    }

    function testTreasuryExecuteBlockedWhenPaused() public {
        // Deploy 3-signer treasury with threshold 3
        address[] memory signers3 = new address[](3);
        signers3[0] = user1;
        signers3[1] = user2;
        signers3[2] = user3;
        Treasury treasury3 = new Treasury(signers3, 3);
        payable(address(treasury3)).transfer(10 ether);

        vm.prank(user1);
        uint256 txId = treasury3.submitTransaction(user3, 100, bytes(""));
        vm.prank(user2);
        treasury3.confirmTransaction(txId);

        treasury3.pause();

        vm.prank(user3);
        vm.expectRevert("Pausable: paused");
        treasury3.confirmTransaction(txId);
    }

    function testTreasuryOnlyOwnerCanPause() public {
        vm.prank(user1);
        vm.expectRevert();
        treasury.pause(); // user1 is signer, not owner
    }

    // ============ PaymentLedger ============

    function testPaymentLedgerPauseUnpause() public {
        assertFalse(paymentLedger.paused());
        paymentLedger.pause();
        assertTrue(paymentLedger.paused());
        paymentLedger.unpause();
        assertFalse(paymentLedger.paused());
    }

    function testPaymentLedgerRecordBlockedWhenPaused() public {
        paymentLedger.addVerifier(address(this));
        paymentLedger.pause();

        vm.expectRevert("Pausable: paused");
        paymentLedger.recordPayment(
            user1, user2, address(mockToken), 100,
            IPaymentLedger.PaymentType.X402, bytes32(0), ""
        );
    }

    // ============ PaymentVerifier ============

    function testPaymentVerifierPauseUnpause() public {
        assertFalse(paymentVerifier.paused());
        paymentVerifier.pause();
        assertTrue(paymentVerifier.paused());
        paymentVerifier.unpause();
        assertFalse(paymentVerifier.paused());
    }

    // ============ PaymentApproval ============

    function testPaymentApprovalPauseUnpause() public {
        assertFalse(paymentApproval.paused());
        paymentApproval.pause();
        assertTrue(paymentApproval.paused());
        paymentApproval.unpause();
        assertFalse(paymentApproval.paused());
    }

    function testPaymentApprovalSubmitBlockedWhenPaused() public {
        paymentApproval.pause();

        vm.prank(user1);
        vm.expectRevert("Pausable: paused");
        paymentApproval.submitPaymentRequest(user3, address(mockToken), 100, "test");
    }

    // ============ MarketplaceEscrow ============

    function testMarketplaceEscrowPauseUnpause() public {
        assertFalse(marketplaceEscrow.paused());
        marketplaceEscrow.pause();
        assertTrue(marketplaceEscrow.paused());
        marketplaceEscrow.unpause();
        assertFalse(marketplaceEscrow.paused());
    }

    function testMarketplaceEscrowFundBlockedWhenPaused() public {
        marketplaceEscrow.pause();

        vm.expectRevert("Pausable: paused");
        marketplaceEscrow.fund(1, user1, user2, address(mockToken), 1000, 25);
    }

    function testMarketplaceEscrowReleaseBlockedWhenPaused() public {
        uint256 escrowId = marketplaceEscrow.fund(1, user1, user2, address(mockToken), 1000, 25);

        marketplaceEscrow.pause();

        vm.expectRevert("Pausable: paused");
        marketplaceEscrow.release(escrowId, user3);
    }

    // ============ RevenueSharing ============

    function testRevenueSharingPauseUnpause() public {
        assertFalse(revenueSharing.paused());
        revenueSharing.pause();
        assertTrue(revenueSharing.paused());
        revenueSharing.unpause();
        assertFalse(revenueSharing.paused());
    }

    function testRevenueSharingDepositBlockedWhenPaused() public {
        revenueSharing.pause();

        vm.expectRevert("Pausable: paused");
        revenueSharing.depositNative{value: 1 ether}();
    }

    // ============ PayoutDistributor ============

    function testPayoutDistributorPauseUnpause() public {
        assertFalse(payoutDistributor.paused());
        payoutDistributor.pause();
        assertTrue(payoutDistributor.paused());
        payoutDistributor.unpause();
        assertFalse(payoutDistributor.paused());
    }

    function testPayoutDistributorFundBlockedWhenPaused() public {
        payoutDistributor.pause();

        mockToken.mint(address(this), 1000);
        mockToken.approve(address(payoutDistributor), 1000);

        vm.expectRevert("Pausable: paused");
        payoutDistributor.fundEpoch(address(mockToken), 1000);
    }

    // ============ Events ============

    function testTreasuryPauseEmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit Pausable.Paused(owner);
        treasury.pause();
    }

    function testTreasuryUnpauseEmitsEvent() public {
        treasury.pause();
        vm.expectEmit(true, false, false, false);
        emit Pausable.Unpaused(owner);
        treasury.unpause();
    }
}
