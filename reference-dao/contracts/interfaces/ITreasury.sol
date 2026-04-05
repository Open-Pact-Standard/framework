// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

/**
 * @title ITreasury
 * @dev Interface for multi-sig treasury management
 */
interface ITreasury {
    /**
     * @dev Submit a transaction for execution
     * @param destination Address to call
     * @param value Amount of native tokens to send
     * @param data Calldata for the transaction
     * @return Transaction ID
     */
    function submitTransaction(
        address destination,
        uint256 value,
        bytes calldata data
    ) external returns (uint256);

    /**
     * @dev Confirm a transaction
     * @param txId Transaction ID to confirm
     */
    function confirmTransaction(uint256 txId) external;

    /**
     * @dev Revoke a previous confirmation
     * @param txId Transaction ID to revoke confirmation from
     */
    function revokeConfirmation(uint256 txId) external;

    /**
     * @dev Get addresses that confirmed a transaction
     * @param txId Transaction ID
     * @return Array of confirmer addresses
     */
    function getTransactionConfirmers(uint256 txId) external view returns (address[] memory);

    /**
     * @dev Execute a confirmed transaction
     * @param txId Transaction ID to execute
     * @return Return data from the execution
     */
    function executeTransaction(uint256 txId) external returns (bytes memory);

    /**
     * @dev Get transaction details
     * @param txId Transaction ID to query
     * @return destination, value, data, executed
     */
    function getTransaction(
        uint256 txId
    ) external view returns (address, uint256, bytes memory, bool);

    /**
     * @dev Get number of confirmations for a transaction
     * @param txId Transaction ID
     * @return Number of confirmations
     */
    function getConfirmationCount(uint256 txId) external view returns (uint256);

    /**
     * @dev Check if transaction is confirmed by a specific signer
     * @param txId Transaction ID
     * @param signer Signer address
     * @return Whether the signer has confirmed
     */
    function isConfirmed(uint256 txId, address signer) external view returns (bool);

    /**
     * @dev Get the list of signers
     * @return Array of signer addresses
     */
    function getSigners() external view returns (address[] memory);

    /**
     * @dev Get the confirmation threshold
     * @return Number of confirmations required
     */
    function getThreshold() external view returns (uint256);

    /**
     * @dev Get the number of transactions
     * @return Total number of transactions
     */
    function getTransactionCount() external view returns (uint256);

    /**
     * @dev Check if address is a signer
     * @param account Address to check
     * @return Whether the address is a signer
     */
    function isSigner(address account) external view returns (bool);

    // Events
    event TransactionSubmitted(
        uint256 indexed txId,
        address indexed submitter,
        address destination,
        uint256 value
    );
    event TransactionConfirmed(uint256 indexed txId, address indexed confirmer);
    event TransactionExecuted(
        uint256 indexed txId,
        address indexed executor,
        bytes returnData
    );
    event ConfirmationRevoked(uint256 indexed txId, address indexed revoker);
}
