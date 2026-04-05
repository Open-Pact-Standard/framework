// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "../interfaces/IPaymentLedger.sol";

/**
 * @title PaymentLedger
 * @dev On-chain payment tracking and audit trail for x402 payments.
 *      Supports PAY-02 (tracking/reconciliation) and PAY-04 (auditability).
 *      Stores immutable payment records with settlement status and volume tracking.
 */
contract PaymentLedger is IPaymentLedger, Ownable, Pausable {
    // Storage
    mapping(uint256 => PaymentRecord) private _payments;
    mapping(address => uint256[]) private _paymentsByPayer;
    mapping(address => uint256[]) private _paymentsByRecipient;
    mapping(address => uint256) private _totalVolume;
    uint256 private _paymentCount;

    // Authorized verifiers that can write to the ledger
    mapping(address => bool) private _verifiers;

    // Errors
    error PaymentNotFound(uint256 paymentId);
    error AlreadySettled(uint256 paymentId);
    error NotSettled(uint256 paymentId);
    error InvalidPaymentId(uint256 paymentId);
    error ZeroAddress();
    error ZeroAmount();
    error InvalidRefundAmount(uint256 refundAmount, uint256 originalAmount);
    error NotAuthorized(address caller);
    error InvalidRefundType();

    event VerifierAdded(address indexed verifier);
    event VerifierRemoved(address indexed verifier);

    modifier onlyVerifiers() {
        if (!_verifiers[msg.sender] && msg.sender != owner()) {
            revert NotAuthorized(msg.sender);
        }
        _;
    }

    modifier paymentExists(uint256 paymentId) {
        if (paymentId >= _paymentCount) {
            revert PaymentNotFound(paymentId);
        }
        _;
    }

    constructor() Ownable() {}

    /**
     * @inheritdoc IPaymentLedger
     */
    function recordPayment(
        address payer,
        address recipient,
        address token,
        uint256 amount,
        PaymentType paymentType,
        bytes32 authorizationHash,
        string calldata metadata
    ) external override onlyVerifiers whenNotPaused returns (uint256) {
        if (payer == address(0) || recipient == address(0)) {
            revert ZeroAddress();
        }
        if (token == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        uint256 paymentId = _paymentCount;

        _payments[paymentId] = PaymentRecord({
            payer: payer,
            recipient: recipient,
            token: token,
            amount: amount,
            timestamp: block.timestamp,
            paymentType: paymentType,
            authorizationHash: authorizationHash,
            metadata: metadata,
            settled: false
        });

        _paymentsByPayer[payer].push(paymentId);
        _paymentsByRecipient[recipient].push(paymentId);

        _paymentCount++;

        emit PaymentRecorded(paymentId, payer, recipient, token, amount, paymentType);

        return paymentId;
    }

    /**
     * @inheritdoc IPaymentLedger
     */
    function settlePayment(
        uint256 paymentId,
        bytes32 txHash
    ) external override onlyVerifiers paymentExists(paymentId) whenNotPaused {
        if (_payments[paymentId].settled) {
            revert AlreadySettled(paymentId);
        }

        _payments[paymentId].settled = true;
        _totalVolume[_payments[paymentId].token] += _payments[paymentId].amount;

        emit PaymentSettled(paymentId, txHash);
    }

    /**
     * @inheritdoc IPaymentLedger
     */
    function recordRefund(
        uint256 originalPaymentId,
        uint256 refundAmount,
        string calldata metadata
    ) external override onlyVerifiers paymentExists(originalPaymentId) whenNotPaused returns (uint256) {
        PaymentRecord storage original = _payments[originalPaymentId];

        if (!original.settled) {
            revert NotSettled(originalPaymentId);
        }
        if (refundAmount == 0 || refundAmount > original.amount) {
            revert InvalidRefundAmount(refundAmount, original.amount);
        }

        // Create refund payment record (payer and recipient swapped)
        uint256 refundPaymentId = _paymentCount;

        _payments[refundPaymentId] = PaymentRecord({
            payer: original.recipient,
            recipient: original.payer,
            token: original.token,
            amount: refundAmount,
            timestamp: block.timestamp,
            paymentType: PaymentType.Refund,
            authorizationHash: bytes32(0),
            metadata: metadata,
            settled: true
        });

        _paymentsByPayer[original.recipient].push(refundPaymentId);
        _paymentsByRecipient[original.payer].push(refundPaymentId);
        _totalVolume[original.token] -= refundAmount;

        _paymentCount++;

        emit RefundIssued(originalPaymentId, refundPaymentId, refundAmount);

        return refundPaymentId;
    }

    /**
     * @inheritdoc IPaymentLedger
     */
    function getPayment(uint256 paymentId) external view override paymentExists(paymentId) returns (PaymentRecord memory) {
        return _payments[paymentId];
    }

    /**
     * @inheritdoc IPaymentLedger
     */
    function getPaymentCount() external view override returns (uint256) {
        return _paymentCount;
    }

    /**
     * @inheritdoc IPaymentLedger
     */
    function getPaymentsByPayer(address payer) external view override returns (uint256[] memory) {
        return _paymentsByPayer[payer];
    }

    /**
     * @inheritdoc IPaymentLedger
     */
    function getPaymentsByRecipient(address recipient) external view override returns (uint256[] memory) {
        return _paymentsByRecipient[recipient];
    }

    /**
     * @inheritdoc IPaymentLedger
     */
    function getTotalVolume(address token) external view override returns (uint256) {
        return _totalVolume[token];
    }

    /**
     * @dev Authorize a verifier to write to the ledger
     * @param verifier Address to authorize
     */
    function addVerifier(address verifier) external onlyOwner {
        if (verifier == address(0)) {
            revert ZeroAddress();
        }
        _verifiers[verifier] = true;
        emit VerifierAdded(verifier);
    }

    /**
     * @dev Remove a verifier's authorization
     * @param verifier Address to remove
     */
    function removeVerifier(address verifier) external onlyOwner {
        _verifiers[verifier] = false;
        emit VerifierRemoved(verifier);
    }

    /**
     * @dev Check if an address is an authorized verifier
     * @param account Address to check
     * @return Whether the address is authorized
     */
    function isVerifier(address account) external view returns (bool) {
        return _verifiers[account];
    }

    /**
     * @dev Pause the contract (owner only)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract (owner only)
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
