// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title IPaymentLedger
 * @dev Interface for on-chain payment tracking and audit trail.
 *      Supports PAY-02 (tracking/reconciliation) and PAY-04 (auditability).
 */
interface IPaymentLedger {
    /**
     * @dev Payment record structure
     */
    struct PaymentRecord {
        address payer;
        address recipient;
        address token;
        uint256 amount;
        uint256 timestamp;
        PaymentType paymentType;
        bytes32 authorizationHash;
        string metadata;
        bool settled;
    }

    /**
     * @dev Payment type classification
     */
    enum PaymentType {
        X402,           // Standard x402 payment flow
        MultiSig,       // Multi-sig approved payment
        Treasury,       // Treasury-initiated payment
        Refund,         // Refund of a previous payment
        Marketplace     // Marketplace purchase or bounty payout
    }

    /**
     * @dev Emitted when a payment is recorded
     */
    event PaymentRecorded(
        uint256 indexed paymentId,
        address indexed payer,
        address indexed recipient,
        address token,
        uint256 amount,
        PaymentType paymentType
    );

    /**
     * @dev Emitted when a payment is settled on-chain
     */
    event PaymentSettled(uint256 indexed paymentId, bytes32 txHash);

    /**
     * @dev Emitted when a refund is issued
     */
    event RefundIssued(uint256 indexed originalPaymentId, uint256 indexed refundPaymentId, uint256 amount);

    /**
     * @dev Record a payment
     * @param payer Address paying
     * @param recipient Address receiving
     * @param token Payment token address
     * @param amount Payment amount
     * @param paymentType Type of payment
     * @param authorizationHash Hash of the authorization (for x402) or zero
     * @param metadata Optional metadata string
     * @return paymentId Unique payment identifier
     */
    function recordPayment(
        address payer,
        address recipient,
        address token,
        uint256 amount,
        PaymentType paymentType,
        bytes32 authorizationHash,
        string calldata metadata
    ) external returns (uint256);

    /**
     * @dev Mark a payment as settled
     * @param paymentId Payment to settle
     * @param txHash On-chain transaction hash
     */
    function settlePayment(uint256 paymentId, bytes32 txHash) external;

    /**
     * @dev Record a refund for a previous payment
     * @param originalPaymentId Original payment to refund
     * @param refundAmount Amount being refunded
     * @param metadata Refund reason or metadata
     * @return refundPaymentId New payment ID for the refund
     */
    function recordRefund(
        uint256 originalPaymentId,
        uint256 refundAmount,
        string calldata metadata
    ) external returns (uint256);

    /**
     * @dev Get a payment record by ID
     * @param paymentId Payment ID to query
     * @return The payment record
     */
    function getPayment(uint256 paymentId) external view returns (PaymentRecord memory);

    /**
     * @dev Get total number of payments
     * @return Payment count
     */
    function getPaymentCount() external view returns (uint256);

    /**
     * @dev Get payments by payer
     * @param payer Payer address to filter by
     * @return Array of payment IDs
     */
    function getPaymentsByPayer(address payer) external view returns (uint256[] memory);

    /**
     * @dev Get payments by recipient
     * @param recipient Recipient address to filter by
     * @return Array of payment IDs
     */
    function getPaymentsByRecipient(address recipient) external view returns (uint256[] memory);

    /**
     * @dev Get total volume by token
     * @param token Token address
     * @return Total volume transferred
     */
    function getTotalVolume(address token) external view returns (uint256);
}
