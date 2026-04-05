// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "contracts/payments/PaymentLedger.sol";
import "contracts/interfaces/IPaymentLedger.sol";

contract PaymentLedgerTest is Test {
    PaymentLedger public ledger;

    address public owner;
    address public verifier;
    address public payer;
    address public recipient;
    address public token;

    function setUp() public {
        owner = address(this);
        verifier = makeAddr("verifier");
        payer = makeAddr("payer");
        recipient = makeAddr("recipient");
        token = makeAddr("token");

        ledger = new PaymentLedger();

        // Authorize the verifier
        ledger.addVerifier(verifier);
    }

    // --- Verifier Management ---

    function testAddVerifier() public {
        address newVerifier = makeAddr("newVerifier");
        assertFalse(ledger.isVerifier(newVerifier));

        ledger.addVerifier(newVerifier);
        assertTrue(ledger.isVerifier(newVerifier));
    }

    function testAddVerifierEmitsEvent() public {
        address newVerifier = makeAddr("newVerifier");
        vm.expectEmit(true, false, false, false);
        emit PaymentLedger.VerifierAdded(newVerifier);
        ledger.addVerifier(newVerifier);
    }

    function testRemoveVerifier() public {
        assertTrue(ledger.isVerifier(verifier));

        ledger.removeVerifier(verifier);
        assertFalse(ledger.isVerifier(verifier));
    }

    function testRemoveVerifierEmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit PaymentLedger.VerifierRemoved(verifier);
        ledger.removeVerifier(verifier);
    }

    function testOwnerCanRecordPayments() public {
        // Owner bypasses verifier check via onlyVerifiers modifier
        uint256 paymentId = ledger.recordPayment(
            payer, recipient, token, 100,
            IPaymentLedger.PaymentType.X402, bytes32(0), "owner payment"
        );
        assertEq(paymentId, 0);
    }

    function testCannotAddVerifierAsNonOwner() public {
        vm.prank(payer);
        vm.expectRevert("Ownable: caller is not the owner");
        ledger.addVerifier(makeAddr("bad"));
    }

    // --- Record Payment ---

    function testRecordPayment() public {
        vm.prank(verifier);
        uint256 paymentId = ledger.recordPayment(
            payer,
            recipient,
            token,
            1000e6,
            IPaymentLedger.PaymentType.X402,
            keccak256("auth"),
            "test payment"
        );

        assertEq(paymentId, 0);
        assertEq(ledger.getPaymentCount(), 1);

        IPaymentLedger.PaymentRecord memory record = ledger.getPayment(paymentId);
        assertEq(record.payer, payer);
        assertEq(record.recipient, recipient);
        assertEq(record.token, token);
        assertEq(record.amount, 1000e6);
        assertEq(uint256(record.paymentType), uint256(IPaymentLedger.PaymentType.X402));
        assertFalse(record.settled);
    }

    function testRecordPaymentEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IPaymentLedger.PaymentRecorded(0, payer, recipient, token, 1000e6, IPaymentLedger.PaymentType.X402);

        vm.prank(verifier);
        ledger.recordPayment(payer, recipient, token, 1000e6, IPaymentLedger.PaymentType.X402, keccak256("auth"), "");
    }

    function testCannotRecordPaymentAsUnauthorized() public {
        address unauthorized = makeAddr("unauthorized");

        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSignature("NotAuthorized(address)", unauthorized));
        ledger.recordPayment(payer, recipient, token, 100, IPaymentLedger.PaymentType.X402, bytes32(0), "");
    }

    function testCannotRecordPaymentZeroAddress() public {
        vm.prank(verifier);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        ledger.recordPayment(address(0), recipient, token, 100, IPaymentLedger.PaymentType.X402, bytes32(0), "");
    }

    function testCannotRecordPaymentZeroAmount() public {
        vm.prank(verifier);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        ledger.recordPayment(payer, recipient, token, 0, IPaymentLedger.PaymentType.X402, bytes32(0), "");
    }

    // --- Settle Payment ---

    function testSettlePayment() public {
        vm.prank(verifier);
        uint256 paymentId = ledger.recordPayment(
            payer, recipient, token, 1000e6,
            IPaymentLedger.PaymentType.X402, bytes32(0), ""
        );

        vm.prank(verifier);
        ledger.settlePayment(paymentId, keccak256("txHash"));

        IPaymentLedger.PaymentRecord memory record = ledger.getPayment(paymentId);
        assertTrue(record.settled);
    }

    function testCannotSettleTwice() public {
        vm.prank(verifier);
        uint256 paymentId = ledger.recordPayment(
            payer, recipient, token, 1000e6,
            IPaymentLedger.PaymentType.X402, bytes32(0), ""
        );

        vm.prank(verifier);
        ledger.settlePayment(paymentId, keccak256("txHash"));

        vm.prank(verifier);
        vm.expectRevert(abi.encodeWithSignature("AlreadySettled(uint256)", paymentId));
        ledger.settlePayment(paymentId, keccak256("txHash2"));
    }

    // --- Volume Tracking ---

    function testVolumeTracking() public {
        assertEq(ledger.getTotalVolume(token), 0);

        vm.prank(verifier);
        uint256 id1 = ledger.recordPayment(payer, recipient, token, 500e6, IPaymentLedger.PaymentType.X402, bytes32(0), "");
        vm.prank(verifier);
        ledger.settlePayment(id1, bytes32(0));

        assertEq(ledger.getTotalVolume(token), 500e6);

        vm.prank(verifier);
        uint256 id2 = ledger.recordPayment(payer, recipient, token, 300e6, IPaymentLedger.PaymentType.X402, bytes32(0), "");
        vm.prank(verifier);
        ledger.settlePayment(id2, bytes32(0));

        assertEq(ledger.getTotalVolume(token), 800e6);
    }

    // --- Refund ---

    function testRecordRefund() public {
        vm.prank(verifier);
        uint256 paymentId = ledger.recordPayment(
            payer, recipient, token, 1000e6,
            IPaymentLedger.PaymentType.X402, bytes32(0), ""
        );
        vm.prank(verifier);
        ledger.settlePayment(paymentId, bytes32(0));

        vm.prank(verifier);
        uint256 refundId = ledger.recordRefund(paymentId, 500e6, "partial refund");

        IPaymentLedger.PaymentRecord memory refund = ledger.getPayment(refundId);
        assertEq(refund.payer, recipient); // Swapped
        assertEq(refund.recipient, payer); // Swapped
        assertEq(refund.amount, 500e6);
        assertTrue(refund.settled);
        assertEq(uint256(refund.paymentType), uint256(IPaymentLedger.PaymentType.Refund));
    }

    function testRefundUpdatesVolume() public {
        vm.prank(verifier);
        uint256 paymentId = ledger.recordPayment(
            payer, recipient, token, 1000e6,
            IPaymentLedger.PaymentType.X402, bytes32(0), ""
        );
        vm.prank(verifier);
        ledger.settlePayment(paymentId, bytes32(0));

        assertEq(ledger.getTotalVolume(token), 1000e6);

        vm.prank(verifier);
        ledger.recordRefund(paymentId, 400e6, "refund");

        assertEq(ledger.getTotalVolume(token), 600e6);
    }

    function testCannotRefundUnsettled() public {
        vm.prank(verifier);
        uint256 paymentId = ledger.recordPayment(
            payer, recipient, token, 1000e6,
            IPaymentLedger.PaymentType.X402, bytes32(0), ""
        );

        vm.prank(verifier);
        vm.expectRevert(abi.encodeWithSignature("NotSettled(uint256)", paymentId));
        ledger.recordRefund(paymentId, 500e6, "refund");
    }

    function testCannotRefundMoreThanAmount() public {
        vm.prank(verifier);
        uint256 paymentId = ledger.recordPayment(
            payer, recipient, token, 1000e6,
            IPaymentLedger.PaymentType.X402, bytes32(0), ""
        );
        vm.prank(verifier);
        ledger.settlePayment(paymentId, bytes32(0));

        vm.prank(verifier);
        vm.expectRevert(); // InvalidRefundAmount
        ledger.recordRefund(paymentId, 1001e6, "over refund");
    }

    // --- Querying ---

    function testGetPaymentsByPayer() public {
        vm.prank(verifier);
        ledger.recordPayment(payer, recipient, token, 100, IPaymentLedger.PaymentType.X402, bytes32(0), "");
        vm.prank(verifier);
        ledger.recordPayment(payer, makeAddr("other"), token, 200, IPaymentLedger.PaymentType.X402, bytes32(0), "");

        uint256[] memory payerPayments = ledger.getPaymentsByPayer(payer);
        assertEq(payerPayments.length, 2);
        assertEq(payerPayments[0], 0);
        assertEq(payerPayments[1], 1);
    }

    function testGetPaymentsByRecipient() public {
        vm.prank(verifier);
        ledger.recordPayment(payer, recipient, token, 100, IPaymentLedger.PaymentType.X402, bytes32(0), "");
        vm.prank(verifier);
        ledger.recordPayment(makeAddr("other"), recipient, token, 200, IPaymentLedger.PaymentType.X402, bytes32(0), "");

        uint256[] memory recipientPayments = ledger.getPaymentsByRecipient(recipient);
        assertEq(recipientPayments.length, 2);
    }

    // --- Payment Types ---

    function testMultiSigPaymentType() public {
        vm.prank(verifier);
        uint256 id = ledger.recordPayment(
            payer, recipient, token, 5000e6,
            IPaymentLedger.PaymentType.MultiSig, bytes32(0), "large payment"
        );

        IPaymentLedger.PaymentRecord memory record = ledger.getPayment(id);
        assertEq(uint256(record.paymentType), uint256(IPaymentLedger.PaymentType.MultiSig));
    }

    function testTreasuryPaymentType() public {
        vm.prank(verifier);
        uint256 id = ledger.recordPayment(
            payer, recipient, token, 10000e6,
            IPaymentLedger.PaymentType.Treasury, bytes32(0), "treasury disbursement"
        );

        IPaymentLedger.PaymentRecord memory record = ledger.getPayment(id);
        assertEq(uint256(record.paymentType), uint256(IPaymentLedger.PaymentType.Treasury));
    }
}
