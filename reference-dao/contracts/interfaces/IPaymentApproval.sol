// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

/**
 * @title IPaymentApproval
 * @dev Interface for multi-sig payment approval workflow.
 *      Supports PAY-03 (multi-signature approvals for large transactions).
 *      Integrates with PaymentVerifier for execution and PaymentLedger for tracking.
 */
interface IPaymentApproval {
    /**
     * @dev Payment request structure
     */
    struct PaymentRequest {
        address initiator;
        address recipient;
        address token;
        uint256 amount;
        string metadata;
        uint256 confirmations;
        bool executed;
        bool canceled;
        uint256 createdAt;
    }

    /**
     * @dev Emitted when a payment request is submitted
     */
    event PaymentRequestSubmitted(
        uint256 indexed requestId,
        address indexed initiator,
        address indexed recipient,
        address token,
        uint256 amount
    );

    /**
     * @dev Emitted when a signer confirms a payment request
     */
    event PaymentRequestConfirmed(uint256 indexed requestId, address indexed signer);

    /**
     * @dev Emitted when a signer revokes their confirmation
     */
    event ConfirmationRevoked(uint256 indexed requestId, address indexed signer);

    /**
     * @dev Emitted when a payment request is executed
     */
    event PaymentRequestExecuted(uint256 indexed requestId, address indexed executor);

    /**
     * @dev Emitted when a payment request is canceled
     */
    event PaymentRequestCanceled(uint256 indexed requestId, address indexed canceler);

    /**
     * @dev Emitted when the approval threshold is updated
     */
    event ApprovalThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    /**
     * @dev Submit a new payment request requiring multi-sig approval
     * @param recipient Payment recipient
     * @param token Payment token address
     * @param amount Payment amount
     * @param metadata Description or reference data
     * @return requestId Unique request identifier
     */
    function submitPaymentRequest(
        address recipient,
        address token,
        uint256 amount,
        string calldata metadata
    ) external returns (uint256);

    /**
     * @dev Confirm a payment request
     * @param requestId Request to confirm
     */
    function confirmPaymentRequest(uint256 requestId) external;

    /**
     * @dev Revoke a previous confirmation
     * @param requestId Request to revoke confirmation from
     */
    function revokeConfirmation(uint256 requestId) external;

    /**
     * @dev Execute a confirmed payment request (threshold must be met)
     * @param requestId Request to execute
     * @return ledgerPaymentId Payment ID in the ledger
     */
    function executePayment(uint256 requestId) external returns (uint256 ledgerPaymentId);

    /**
     * @dev Cancel a pending payment request (initiator only)
     * @param requestId Request to cancel
     */
    function cancelPaymentRequest(uint256 requestId) external;

    /**
     * @dev Get a payment request by ID
     * @param requestId Request ID to query
     * @return The payment request
     */
    function getPaymentRequest(uint256 requestId) external view returns (PaymentRequest memory);

    /**
     * @dev Check if a signer has confirmed a request
     * @param requestId Request ID
     * @param signer Signer address
     * @return Whether the signer has confirmed
     */
    function hasConfirmed(uint256 requestId, address signer) external view returns (bool);

    /**
     * @dev Get the total number of payment requests
     * @return Request count
     */
    function getRequestCount() external view returns (uint256);

    /**
     * @dev Get the confirmation threshold
     * @return Number of confirmations required
     */
    function getThreshold() external view returns (uint256);

    /**
     * @dev Get the list of authorized signers
     * @return Array of signer addresses
     */
    function getSigners() external view returns (address[] memory);

    /**
     * @dev Check if an address is a signer
     * @param account Address to check
     * @return Whether the address is a signer
     */
    function isSigner(address account) external view returns (bool);

    /**
     * @dev Get the minimum amount that requires multi-sig approval
     * @return The approval threshold
     */
    function approvalThreshold() external view returns (uint256);

    /**
     * @dev Update the approval threshold (owner only)
     * @param newThreshold New minimum amount requiring multi-sig approval
     */
    function setApprovalThreshold(uint256 newThreshold) external;
}
