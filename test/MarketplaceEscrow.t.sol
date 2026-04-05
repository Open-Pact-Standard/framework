// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "contracts/payments/MarketplaceEscrow.sol";
import "contracts/interfaces/IMarketplaceEscrow.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Simple ERC20 mock for escrow tests
 */
contract MockERC20 is ERC20 {
    constructor() ERC20("MockToken", "MTK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MarketplaceEscrowTest is Test {
    MarketplaceEscrow public escrow;
    MockERC20 public token;

    address public owner;
    address public marketplace;
    address public buyer;
    address public seller;
    address public feeRecipient;

    uint256 constant ESCROW_TIMEOUT = 7 days;

    function setUp() public {
        owner = address(this);
        marketplace = makeAddr("marketplace");
        buyer = makeAddr("buyer");
        seller = makeAddr("seller");
        feeRecipient = makeAddr("feeRecipient");

        escrow = new MarketplaceEscrow(ESCROW_TIMEOUT);
        token = new MockERC20();

        // Set marketplace authorization
        escrow.setMarketplace(marketplace);

        // Mint tokens to escrow (simulating PaymentVerifier deposit)
        token.mint(address(escrow), 1_000_000e18);
    }

    // ============ Deployment Tests ============

    function testDeployment() public {
        assertEq(escrow.escrowTimeout(), ESCROW_TIMEOUT);
        assertEq(escrow.getMarketplace(), marketplace);
        assertEq(escrow.getEscrowCount(), 0);
    }

    // ============ Fund Tests ============

    function testFund() public {
        uint256 amount = 1000e18;
        uint256 fee = 25e18;

        vm.prank(marketplace);
        uint256 escrowId = escrow.fund(1, buyer, seller, address(token), amount, fee);

        assertEq(escrowId, 0);
        assertEq(escrow.getEscrowCount(), 1);

        IMarketplaceEscrow.EscrowEntry memory entry = escrow.getEscrow(escrowId);
        assertEq(entry.listingId, 1);
        assertEq(entry.buyer, buyer);
        assertEq(entry.seller, seller);
        assertEq(entry.token, address(token));
        assertEq(entry.amount, amount);
        assertEq(entry.platformFee, fee);
        assertEq(uint256(entry.status), uint256(IMarketplaceEscrow.EscrowStatus.Pending));
        assertTrue(entry.expiresAt > block.timestamp);
    }

    function testFundEmitsEvent() public {
        vm.prank(marketplace);
        vm.expectEmit(true, true, true, false);
        emit IMarketplaceEscrow.EscrowFunded(0, 1, buyer, seller, 1000e18);
        escrow.fund(1, buyer, seller, address(token), 1000e18, 25e18);
    }

    function testCannotFundFromNonMarketplace() public {
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSignature("NotMarketplace()"));
        escrow.fund(1, buyer, seller, address(token), 1000e18, 0);
    }

    function testCannotFundZeroAmount() public {
        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        escrow.fund(1, buyer, seller, address(token), 0, 0);
    }

    // ============ Release Tests ============

    function testRelease() public {
        uint256 amount = 1000e18;
        uint256 fee = 25e18;

        vm.prank(marketplace);
        uint256 escrowId = escrow.fund(1, buyer, seller, address(token), amount, fee);

        uint256 sellerBalBefore = token.balanceOf(seller);

        vm.prank(marketplace);
        escrow.release(escrowId, feeRecipient);

        // Seller receives net amount (amount - fee)
        assertEq(token.balanceOf(seller), sellerBalBefore + amount - fee);

        // Fee recipient receives fee
        assertEq(token.balanceOf(feeRecipient), fee);

        IMarketplaceEscrow.EscrowEntry memory entry = escrow.getEscrow(escrowId);
        assertEq(uint256(entry.status), uint256(IMarketplaceEscrow.EscrowStatus.Released));
    }

    function testReleaseEmitsEvent() public {
        vm.prank(marketplace);
        uint256 escrowId = escrow.fund(1, buyer, seller, address(token), 1000e18, 25e18);

        vm.prank(marketplace);
        vm.expectEmit(true, true, true, false);
        emit IMarketplaceEscrow.EscrowReleased(escrowId, 1, seller, 975e18);
        escrow.release(escrowId, feeRecipient);
    }

    function testCannotReleaseTwice() public {
        vm.prank(marketplace);
        uint256 escrowId = escrow.fund(1, buyer, seller, address(token), 1000e18, 25e18);

        vm.prank(marketplace);
        escrow.release(escrowId, feeRecipient);

        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSignature("EscrowNotPending(uint256)", escrowId));
        escrow.release(escrowId, feeRecipient);
    }

    function testCannotReleaseFromNonMarketplace() public {
        vm.prank(marketplace);
        uint256 escrowId = escrow.fund(1, buyer, seller, address(token), 1000e18, 25e18);

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSignature("NotMarketplace()"));
        escrow.release(escrowId, feeRecipient);
    }

    function testReleaseWithNoFee() public {
        uint256 amount = 1000e18;

        vm.prank(marketplace);
        uint256 escrowId = escrow.fund(1, buyer, seller, address(token), amount, 0);

        uint256 sellerBalBefore = token.balanceOf(seller);

        vm.prank(marketplace);
        escrow.release(escrowId, feeRecipient);

        // Seller receives full amount (no fee)
        assertEq(token.balanceOf(seller), sellerBalBefore + amount);
    }

    // ============ Refund Tests ============

    function testRefundAfterTimeout() public {
        uint256 amount = 1000e18;

        vm.prank(marketplace);
        uint256 escrowId = escrow.fund(1, buyer, seller, address(token), amount, 25e18);

        // Warp past timeout
        vm.warp(block.timestamp + ESCROW_TIMEOUT + 1);

        uint256 buyerBalBefore = token.balanceOf(buyer);

        vm.prank(marketplace);
        escrow.refund(escrowId);

        // Buyer receives full amount back
        assertEq(token.balanceOf(buyer), buyerBalBefore + amount);

        IMarketplaceEscrow.EscrowEntry memory entry = escrow.getEscrow(escrowId);
        assertEq(uint256(entry.status), uint256(IMarketplaceEscrow.EscrowStatus.Refunded));
    }

    function testRefundEmitsEvent() public {
        vm.prank(marketplace);
        uint256 escrowId = escrow.fund(1, buyer, seller, address(token), 1000e18, 25e18);

        vm.warp(block.timestamp + ESCROW_TIMEOUT + 1);

        vm.prank(marketplace);
        vm.expectEmit(true, true, true, false);
        emit IMarketplaceEscrow.EscrowRefunded(escrowId, 1, buyer, 1000e18);
        escrow.refund(escrowId);
    }

    function testCannotRefundBeforeTimeout() public {
        vm.prank(marketplace);
        uint256 escrowId = escrow.fund(1, buyer, seller, address(token), 1000e18, 0);

        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSignature("EscrowNotExpired(uint256)", escrowId));
        escrow.refund(escrowId);
    }

    function testCannotRefundAlreadyReleased() public {
        vm.prank(marketplace);
        uint256 escrowId = escrow.fund(1, buyer, seller, address(token), 1000e18, 0);

        vm.prank(marketplace);
        escrow.release(escrowId, feeRecipient);

        vm.warp(block.timestamp + ESCROW_TIMEOUT + 1);

        vm.prank(marketplace);
        vm.expectRevert(abi.encodeWithSignature("EscrowNotPending(uint256)", escrowId));
        escrow.refund(escrowId);
    }

    // ============ Admin Tests ============

    function testSetMarketplace() public {
        address newMarketplace = makeAddr("newMarketplace");
        escrow.setMarketplace(newMarketplace);
        assertEq(escrow.getMarketplace(), newMarketplace);
    }

    function testSetMarketplaceEmitsEvent() public {
        address newMarketplace = makeAddr("newMarketplace");
        vm.expectEmit(true, true, false, false);
        emit IMarketplaceEscrow.MarketplaceUpdated(marketplace, newMarketplace);
        escrow.setMarketplace(newMarketplace);
    }

    function testOnlyOwnerCanSetMarketplace() public {
        vm.prank(buyer);
        vm.expectRevert();
        escrow.setMarketplace(makeAddr("bad"));
    }

    function testTransferOwnership() public {
        address newOwner = makeAddr("newOwner");

        // Step 1: Initiate transfer
        escrow.transferOwnership(newOwner);
        assertEq(escrow.pendingOwner(), newOwner);

        // Old owner can still set marketplace (transfer not complete)
        escrow.setMarketplace(makeAddr("stillOwner"));

        // Step 2: New owner accepts
        vm.prank(newOwner);
        escrow.acceptOwnership();

        // Old owner can no longer set marketplace
        vm.expectRevert();
        escrow.setMarketplace(makeAddr("bad"));

        // New owner can
        vm.prank(newOwner);
        escrow.setMarketplace(makeAddr("good"));
    }

    // ============ Multiple Escrows Test ============

    function testMultipleEscrows() public {
        // Fund first escrow
        vm.prank(marketplace);
        uint256 id1 = escrow.fund(1, buyer, seller, address(token), 100e18, 2e18);

        // Fund second escrow
        vm.prank(marketplace);
        uint256 id2 = escrow.fund(2, buyer, seller, address(token), 200e18, 5e18);

        assertEq(id1, 0);
        assertEq(id2, 1);
        assertEq(escrow.getEscrowCount(), 2);

        // Release first
        vm.prank(marketplace);
        escrow.release(id1, feeRecipient);

        // Second still pending
        IMarketplaceEscrow.EscrowEntry memory entry = escrow.getEscrow(id2);
        assertEq(uint256(entry.status), uint256(IMarketplaceEscrow.EscrowStatus.Pending));
    }
}
