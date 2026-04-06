// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

/**
 * @title IPaymentLedger
 * @dev Interface for the OPL-1.1 Payment Ledger.
 *      Part of the broader DAO x402/PAY-02 framework but referenced by
 *      the core OPL-1.1 royalty contracts for audit trail integration.
 *      See framework/contracts/PaymentLedger.sol for the full implementation.
 */
interface IPaymentLedger {
    function recordPayment(
        address payer,
        address recipient,
        address token,
        uint256 amount,
        string calldata description,
        uint256 projectId
    ) external returns (uint256 ledgerPaymentId);

    function settlePayment(uint256 paymentId) external;

    function getVersion() external pure returns (string memory);
}
