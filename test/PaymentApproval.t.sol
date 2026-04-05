// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "contracts/payments/PaymentApproval.sol";
import "contracts/interfaces/IPaymentApproval.sol";

contract PaymentApprovalTest is Test {
    PaymentApproval public approval;

    address public owner;
    address public signer1;
    address public signer2;
    address public signer3;
    address public nonSigner;
    address public recipient;
    address public token;
    address public verifier;

    function setUp() public {
        owner = address(this);
        signer1 = makeAddr("signer1");
        signer2 = makeAddr("signer2");
        signer3 = makeAddr("signer3");
        nonSigner = makeAddr("nonSigner");
        recipient = makeAddr("recipient");
        token = makeAddr("token");
        verifier = makeAddr("verifier");

        address[] memory signers = new address[](3);
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;

        // 2-of-3 multi-sig, approval threshold 0 (all payments require approval)
        approval = new PaymentApproval(signers, 2, verifier, 0);
    }

    // --- Deployment ---

    function testDeployment() public {
        assertEq(approval.getThreshold(), 2);
        assertEq(approval.getSigners().length, 3);
        assertTrue(approval.isSigner(signer1));
        assertTrue(approval.isSigner(signer2));
        assertTrue(approval.isSigner(signer3));
        assertFalse(approval.isSigner(nonSigner));
        assertEq(approval.getVerifier(), verifier);
    }

    function testCannotDeployWithZeroSigners() public {
        address[] memory emptySigners = new address[](0);
        vm.expectRevert(); // InvalidThreshold
        new PaymentApproval(emptySigners, 1, verifier, 0);
    }

    function testCannotDeployWithInvalidThreshold() public {
        address[] memory signers = new address[](2);
        signers[0] = signer1;
        signers[1] = signer2;

        // Threshold > signers.length
        vm.expectRevert(); // InvalidThreshold
        new PaymentApproval(signers, 3, verifier, 0);
    }

    // --- Submit Payment Request ---

    function testSubmitPaymentRequest() public {
        vm.prank(signer1);
        uint256 requestId = approval.submitPaymentRequest(
            recipient, token, 5000e6, "Large payment for services"
        );

        assertEq(requestId, 0);
        assertEq(approval.getRequestCount(), 1);

        IPaymentApproval.PaymentRequest memory request = approval.getPaymentRequest(requestId);
        assertEq(request.initiator, signer1);
        assertEq(request.recipient, recipient);
        assertEq(request.token, token);
        assertEq(request.amount, 5000e6);
        assertFalse(request.executed);
        assertFalse(request.canceled);

        // Submitter auto-confirms
        assertTrue(approval.hasConfirmed(requestId, signer1));
        assertEq(request.confirmations, 1);
    }

    function testSubmitEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IPaymentApproval.PaymentRequestSubmitted(0, signer1, recipient, token, 5000e6);

        vm.prank(signer1);
        approval.submitPaymentRequest(recipient, token, 5000e6, "test");
    }

    function testCannotSubmitAsNonSigner() public {
        vm.prank(nonSigner);
        vm.expectRevert(abi.encodeWithSignature("NotASigner(address)", nonSigner));
        approval.submitPaymentRequest(recipient, token, 100, "test");
    }

    function testCannotSubmitZeroAmount() public {
        vm.prank(signer1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        approval.submitPaymentRequest(recipient, token, 0, "test");
    }

    function testCannotSubmitZeroAddress() public {
        vm.prank(signer1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        approval.submitPaymentRequest(address(0), token, 100, "test");
    }

    // --- Confirm Payment Request ---

    function testConfirmPaymentRequest() public {
        vm.prank(signer1);
        uint256 requestId = approval.submitPaymentRequest(recipient, token, 5000e6, "test");

        vm.prank(signer2);
        approval.confirmPaymentRequest(requestId);

        assertTrue(approval.hasConfirmed(requestId, signer2));

        IPaymentApproval.PaymentRequest memory request = approval.getPaymentRequest(requestId);
        assertEq(request.confirmations, 2);
    }

    function testConfirmEmitsEvent() public {
        vm.prank(signer1);
        uint256 requestId = approval.submitPaymentRequest(recipient, token, 5000e6, "test");

        vm.expectEmit(true, true, false, false);
        emit IPaymentApproval.PaymentRequestConfirmed(requestId, signer2);

        vm.prank(signer2);
        approval.confirmPaymentRequest(requestId);
    }

    function testCannotConfirmTwice() public {
        vm.prank(signer1);
        uint256 requestId = approval.submitPaymentRequest(recipient, token, 5000e6, "test");

        vm.prank(signer1);
        vm.expectRevert(abi.encodeWithSignature("AlreadyConfirmed(address)", signer1));
        approval.confirmPaymentRequest(requestId);
    }

    function testCannotConfirmAsNonSigner() public {
        vm.prank(signer1);
        uint256 requestId = approval.submitPaymentRequest(recipient, token, 5000e6, "test");

        vm.prank(nonSigner);
        vm.expectRevert(abi.encodeWithSignature("NotASigner(address)", nonSigner));
        approval.confirmPaymentRequest(requestId);
    }

    // --- Execute Payment ---

    function testExecutePayment() public {
        vm.prank(signer1);
        uint256 requestId = approval.submitPaymentRequest(recipient, token, 5000e6, "test");

        vm.prank(signer2);
        approval.confirmPaymentRequest(requestId);

        // Now threshold of 2 is met
        IPaymentApproval.PaymentRequest memory request = approval.getPaymentRequest(requestId);
        assertTrue(request.executed);
    }

    function testAutoExecuteOnThresholdOne() public {
        // Deploy 1-of-3 approval
        address[] memory signers = new address[](3);
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;
        PaymentApproval approval1of3 = new PaymentApproval(signers, 1, verifier, 0);

        vm.prank(signer1);
        uint256 requestId = approval1of3.submitPaymentRequest(recipient, token, 100, "test");

        IPaymentApproval.PaymentRequest memory request = approval1of3.getPaymentRequest(requestId);
        assertTrue(request.executed);
    }

    function testCannotExecuteWithoutThreshold() public {
        // Deploy 3-of-3 approval
        address[] memory signers = new address[](3);
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;
        PaymentApproval approval3of3 = new PaymentApproval(signers, 3, verifier, 0);

        vm.prank(signer1);
        uint256 requestId = approval3of3.submitPaymentRequest(recipient, token, 5000e6, "test");

        vm.prank(signer2);
        approval3of3.confirmPaymentRequest(requestId);

        // Only 2 of 3 confirmed
        vm.prank(signer3);
        vm.expectRevert(); // InsufficientConfirmations
        approval3of3.executePayment(requestId);
    }

    function testCannotExecuteTwice() public {
        vm.prank(signer1);
        uint256 requestId = approval.submitPaymentRequest(recipient, token, 5000e6, "test");

        vm.prank(signer2);
        approval.confirmPaymentRequest(requestId);

        // Already executed
        vm.prank(signer3);
        vm.expectRevert(abi.encodeWithSignature("RequestAlreadyExecuted(uint256)", requestId));
        approval.executePayment(requestId);
    }

    // --- Revoke Confirmation ---

    function testRevokeConfirmation() public {
        // Use 3-of-3 so threshold isn't met after 2 confirmations
        address[] memory signers = new address[](3);
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;
        PaymentApproval approval3of3 = new PaymentApproval(signers, 3, verifier, 0);

        vm.prank(signer1);
        uint256 requestId = approval3of3.submitPaymentRequest(recipient, token, 5000e6, "test");

        vm.prank(signer2);
        approval3of3.confirmPaymentRequest(requestId);

        // Revoke signer2's confirmation (still below threshold)
        vm.prank(signer2);
        approval3of3.revokeConfirmation(requestId);

        assertFalse(approval3of3.hasConfirmed(requestId, signer2));

        IPaymentApproval.PaymentRequest memory request = approval3of3.getPaymentRequest(requestId);
        assertEq(request.confirmations, 1);
        assertFalse(request.executed);
    }

    function testRevokeEmitsEvent() public {
        // Use 3-of-3 so threshold isn't met after 2 confirmations
        address[] memory signers = new address[](3);
        signers[0] = signer1;
        signers[1] = signer2;
        signers[2] = signer3;
        PaymentApproval approval3of3 = new PaymentApproval(signers, 3, verifier, 0);

        vm.prank(signer1);
        uint256 requestId = approval3of3.submitPaymentRequest(recipient, token, 5000e6, "test");

        vm.prank(signer2);
        approval3of3.confirmPaymentRequest(requestId);

        vm.expectEmit(true, true, false, false);
        emit IPaymentApproval.ConfirmationRevoked(requestId, signer2);

        vm.prank(signer2);
        approval3of3.revokeConfirmation(requestId);
    }

    // --- Cancel Payment Request ---

    function testCancelPaymentRequest() public {
        vm.prank(signer1);
        uint256 requestId = approval.submitPaymentRequest(recipient, token, 5000e6, "test");

        vm.prank(signer1);
        approval.cancelPaymentRequest(requestId);

        IPaymentApproval.PaymentRequest memory request = approval.getPaymentRequest(requestId);
        assertTrue(request.canceled);
    }

    function testCancelEmitsEvent() public {
        vm.prank(signer1);
        uint256 requestId = approval.submitPaymentRequest(recipient, token, 5000e6, "test");

        vm.expectEmit(true, true, false, false);
        emit IPaymentApproval.PaymentRequestCanceled(requestId, signer1);

        vm.prank(signer1);
        approval.cancelPaymentRequest(requestId);
    }

    function testOnlyInitiatorCanCancel() public {
        vm.prank(signer1);
        uint256 requestId = approval.submitPaymentRequest(recipient, token, 5000e6, "test");

        vm.prank(signer2);
        vm.expectRevert(abi.encodeWithSignature("NotInitiator(address)", signer2));
        approval.cancelPaymentRequest(requestId);
    }

    function testCannotConfirmCanceledRequest() public {
        vm.prank(signer1);
        uint256 requestId = approval.submitPaymentRequest(recipient, token, 5000e6, "test");

        vm.prank(signer1);
        approval.cancelPaymentRequest(requestId);

        vm.prank(signer2);
        vm.expectRevert(abi.encodeWithSignature("RequestCanceled(uint256)", requestId));
        approval.confirmPaymentRequest(requestId);
    }

    // --- Verifier Management ---

    function testUpdateVerifier() public {
        address newVerifier = makeAddr("newVerifier");
        approval.updateVerifier(newVerifier);
        assertEq(approval.getVerifier(), newVerifier);
    }

    function testCannotUpdateVerifierAsNonOwner() public {
        vm.prank(signer1);
        vm.expectRevert();
        approval.updateVerifier(makeAddr("bad"));
    }

    // --- Multiple Requests ---

    function testMultipleRequests() public {
        vm.prank(signer1);
        uint256 req1 = approval.submitPaymentRequest(recipient, token, 1000e6, "first");
        vm.prank(signer2);
        uint256 req2 = approval.submitPaymentRequest(recipient, token, 2000e6, "second");

        assertEq(req1, 0);
        assertEq(req2, 1);
        assertEq(approval.getRequestCount(), 2);

        // req1: signer1 submitted (auto-confirmed), only 1 of 2 confirmations
        // req2: signer2 submitted (auto-confirmed), only 1 of 2 confirmations
        // Neither should be executed yet since threshold is 2
        IPaymentApproval.PaymentRequest memory r1 = approval.getPaymentRequest(req1);
        IPaymentApproval.PaymentRequest memory r2 = approval.getPaymentRequest(req2);

        assertFalse(r1.executed);
        assertFalse(r2.executed);

        // Now confirm req1 by signer2 — should execute since threshold met
        vm.prank(signer2);
        approval.confirmPaymentRequest(req1);

        r1 = approval.getPaymentRequest(req1);
        assertTrue(r1.executed);
        assertFalse(approval.getPaymentRequest(req2).executed);
    }
}
