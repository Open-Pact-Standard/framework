// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title IPaymentVerifier
 * @dev Interface for on-chain x402 payment verification and execution.
 *      Acts as the custom Flare facilitator for EIP-3009 authorizations.
 *      Supports PAY-01 (x402 payment processing).
 */
interface IPaymentVerifier {
    /**
     * @dev Payment parameters for x402 exact scheme
     */
    struct PaymentParams {
        address payer;
        address recipient;
        address token;
        uint256 amount;
        uint256 validAfter;
        uint256 validBefore;
        bytes32 nonce;
        uint8 v;
        bytes32 r;
        bytes32 s;
    }

    /**
     * @dev Emitted when a payment is successfully processed
     */
    event PaymentProcessed(
        address indexed payer,
        address indexed recipient,
        address token,
        uint256 amount,
        uint256 indexed ledgerPaymentId
    );

    /**
     * @dev Emitted when a payment verification fails
     */
    event PaymentVerificationFailed(
        address indexed payer,
        address indexed recipient,
        uint256 amount,
        bytes reason
    );

    /**
     * @dev Emitted when an authorization is canceled
     */
    event AuthorizationCanceled(
        address indexed authorizer,
        bytes32 indexed nonce
    );

    /**
     * @dev Process an x402 payment using EIP-3009 authorization.
     *      Verifies the signature, executes the token transfer, and records in ledger.
     * @param params Payment parameters including EIP-3009 authorization data
     * @return ledgerPaymentId Payment ID in the ledger
     */
    function processPayment(PaymentParams calldata params) external returns (uint256 ledgerPaymentId);

    /**
     * @dev Cancel an unused EIP-3009 authorization
     * @param token Token contract address
     * @param authorizer Address that signed the authorization
     * @param nonce Nonce of the authorization to cancel
     * @param v Signature v value
     * @param r Signature r value
     * @param s Signature s value
     */
    function cancelAuthorization(
        address token,
        address authorizer,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @dev Get the payment ledger address
     * @return Ledger contract address
     */
    function getLedger() external view returns (address);

    /**
     * @dev Check if an address is authorized as a facilitator
     * @param account Address to check
     * @return Whether the address is a facilitator
     */
    function isFacilitator(address account) external view returns (bool);

    /**
     * @dev Get the list of supported payment tokens
     * @return Array of supported token addresses
     */
    function getSupportedTokens() external view returns (address[] memory);
}
