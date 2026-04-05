// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Treasury} from "contracts/treasury/Treasury.sol";
import {PaymentApproval} from "contracts/payments/PaymentApproval.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MCK") {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract SignerManagementTest is Test {
    Treasury treasury;
    PaymentApproval paymentApproval;

    address owner;
    address user1;
    address user2;
    address user3;
    address user4;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        user4 = makeAddr("user4");

        // Deploy Treasury with 2 signers, threshold 2
        address[] memory signers = new address[](2);
        signers[0] = user1;
        signers[1] = user2;
        treasury = new Treasury(signers, 2);

        // Deploy PaymentApproval with 2 signers, threshold 2
        address[] memory approvalSigners = new address[](2);
        approvalSigners[0] = user1;
        approvalSigners[1] = user2;
        paymentApproval = new PaymentApproval(approvalSigners, 2, makeAddr("verifier"), 0);
    }

    // ============ Treasury Signer Management ============

    function testTreasuryAddSigner() public {
        treasury.addSigner(user3);
        assertTrue(treasury.isSigner(user3));
        assertEq(treasury.getSigners().length, 3);
    }

    function testTreasuryAddSignerEmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit Treasury.SignerAdded(user3);
        treasury.addSigner(user3);
    }

    function testTreasuryCannotAddZeroAddress() public {
        vm.expectRevert();
        treasury.addSigner(address(0));
    }

    function testTreasuryCannotAddDuplicateSigner() public {
        vm.expectRevert(
            abi.encodeWithSignature("SignerAlreadyExists(address)", user1)
        );
        treasury.addSigner(user1);
    }

    function testTreasuryRemoveSigner() public {
        treasury.addSigner(user3); // Now 3 signers
        treasury.removeSigner(user3);
        assertFalse(treasury.isSigner(user3));
        assertEq(treasury.getSigners().length, 2);
    }

    function testTreasuryRemoveSignerEmitsEvent() public {
        treasury.addSigner(user3);
        vm.expectEmit(true, false, false, false);
        emit Treasury.SignerRemoved(user3);
        treasury.removeSigner(user3);
    }

    function testTreasuryCannotRemoveNonSigner() public {
        vm.expectRevert(
            abi.encodeWithSignature("SignerNotFound(address)", user4)
        );
        treasury.removeSigner(user4);
    }

    function testTreasuryCannotRemoveBelowThreshold() public {
        // 2 signers, threshold 2 - removing 1 would leave 1 < threshold 2
        vm.expectRevert(
            abi.encodeWithSignature("WouldViolateThreshold(uint256,uint256)", 1, 2)
        );
        treasury.removeSigner(user1);
    }

    function testTreasurySetThreshold() public {
        treasury.addSigner(user3);
        treasury.setThreshold(3);
        assertEq(treasury.getThreshold(), 3);
    }

    function testTreasurySetThresholdEmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit Treasury.ThresholdUpdated(1);
        treasury.setThreshold(1);
    }

    function testTreasuryCannotSetThresholdAboveSignerCount() public {
        vm.expectRevert(
            abi.encodeWithSignature("InvalidThreshold(uint256,uint256)", 3, 2)
        );
        treasury.setThreshold(3);
    }

    function testTreasuryCannotSetThresholdZero() public {
        vm.expectRevert(
            abi.encodeWithSignature("InvalidThreshold(uint256,uint256)", 0, 2)
        );
        treasury.setThreshold(0);
    }

    function testTreasuryOnlyOwnerCanAddSigner() public {
        vm.prank(user1);
        vm.expectRevert();
        treasury.addSigner(user3);
    }

    function testTreasuryOnlyOwnerCanRemoveSigner() public {
        treasury.addSigner(user3);
        vm.prank(user1);
        vm.expectRevert();
        treasury.removeSigner(user3);
    }

    function testTreasuryNewSignerCanSubmit() public {
        treasury.addSigner(user3);
        vm.prank(user3);
        uint256 txId = treasury.submitTransaction(user4, 100, bytes(""));
        assertTrue(treasury.isConfirmed(txId, user3));
    }

    // ============ PaymentApproval Signer Management ============

    function testPaymentApprovalAddSigner() public {
        paymentApproval.addSigner(user3);
        assertTrue(paymentApproval.isSigner(user3));
        assertEq(paymentApproval.getSigners().length, 3);
    }

    function testPaymentApprovalRemoveSigner() public {
        paymentApproval.addSigner(user3);
        paymentApproval.removeSigner(user3);
        assertFalse(paymentApproval.isSigner(user3));
    }

    function testPaymentApprovalCannotRemoveBelowThreshold() public {
        vm.expectRevert(
            abi.encodeWithSignature("WouldViolateThreshold(uint256,uint256)", 1, 2)
        );
        paymentApproval.removeSigner(user1);
    }

    function testPaymentApprovalSetThreshold() public {
        paymentApproval.addSigner(user3);
        paymentApproval.setThreshold(3);
        assertEq(paymentApproval.getThreshold(), 3);
    }

    function testPaymentApprovalOnlyOwnerCanManageSigners() public {
        vm.prank(user1);
        vm.expectRevert();
        paymentApproval.addSigner(user3);
    }
}
