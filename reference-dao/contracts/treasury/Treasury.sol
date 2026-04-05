// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/ITreasury.sol";

/**
 * @title Treasury
 * @dev Multi-sig treasury for DAO fund management
 * @notice Enables secure treasury management with configurable multi-sig approval
 */
contract Treasury is ITreasury, Ownable, Pausable, ReentrancyGuard {
    // Storage
    address[] private _signers;
    uint256 private _threshold;
    mapping(uint256 => Transaction) private _transactions;
    mapping(uint256 => mapping(address => bool)) private _confirmations;
    uint256 private _transactionCount;

    // Structs
    struct Transaction {
        address destination;
        uint256 value;
        bytes data;
        bool executed;
        uint256 confirmations;
    }

    // Errors
    error NotASigner(address caller);
    error InvalidThreshold(uint256 threshold, uint256 signerCount);
    error AlreadyConfirmed(address confirmer);
    error NotConfirmed(uint256 txId);
    error AlreadyExecuted(uint256 txId);
    error TxNotExecuted(uint256 txId);
    error InvalidDestination(address destination);
    error InsufficientConfirmations(uint256 have, uint256 need);
    error SignerAlreadyExists(address signer);
    error SignerNotFound(address signer);
    error WouldViolateThreshold(uint256 signerCount, uint256 threshold);

    // Modifiers
    modifier onlySigners() {
        if (!_isSigner(msg.sender)) {
            revert NotASigner(msg.sender);
        }
        _;
    }

    modifier txExists(uint256 txId) {
        if (txId >= _transactionCount) {
            revert TxNotExecuted(txId);
        }
        _;
    }

    modifier notExecuted(uint256 txId) {
        if (_transactions[txId].executed) {
            revert AlreadyExecuted(txId);
        }
        _;
    }

    modifier notConfirmed(uint256 txId) {
        if (_confirmations[txId][msg.sender]) {
            revert AlreadyConfirmed(msg.sender);
        }
        _;
    }

    /**
     * @dev Constructor
     * @param signers Array of signer addresses
     * @param threshold Number of confirmations required
     */
    constructor(address[] memory signers, uint256 threshold) Ownable() {
        if (signers.length == 0) {
            revert InvalidThreshold(threshold, 0);
        }
        if (threshold == 0 || threshold > signers.length) {
            revert InvalidThreshold(threshold, signers.length);
        }

        _signers = signers;
        _threshold = threshold;
    }

    // Receive native tokens
    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /**
     * @inheritdoc ITreasury
     */
    function submitTransaction(
        address destination,
        uint256 value,
        bytes calldata data
    ) external override onlySigners nonReentrant whenNotPaused returns (uint256) {
        if (destination == address(0)) {
            revert InvalidDestination(destination);
        }

        uint256 txId = _transactionCount;
        _transactions[txId] = Transaction({
            destination: destination,
            value: value,
            data: data,
            executed: false,
            confirmations: 0
        });

        // Auto-confirm by submitter
        _confirmations[txId][msg.sender] = true;
        _transactions[txId].confirmations = 1;

        _transactionCount++;

        emit TransactionSubmitted(txId, msg.sender, destination, value);

        // Execute immediately if threshold is 1
        if (_threshold == 1) {
            _executeTransaction(txId);
        }

        return txId;
    }

    /**
     * @inheritdoc ITreasury
     */
    function confirmTransaction(
        uint256 txId
    ) external override onlySigners txExists(txId) notExecuted(txId) notConfirmed(txId) nonReentrant whenNotPaused {
        _confirmations[txId][msg.sender] = true;
        _transactions[txId].confirmations++;

        emit TransactionConfirmed(txId, msg.sender);

        // Execute if threshold met
        if (_transactions[txId].confirmations >= _threshold) {
            _executeTransaction(txId);
        }
    }

    /**
     * @inheritdoc ITreasury
     */
    function executeTransaction(
        uint256 txId
    ) external override onlySigners txExists(txId) notExecuted(txId) nonReentrant whenNotPaused returns (bytes memory) {
        if (_transactions[txId].confirmations < _threshold) {
            revert InsufficientConfirmations(_transactions[txId].confirmations, _threshold);
        }

        return _executeTransaction(txId);
    }

    /**
     * @inheritdoc ITreasury
     */
    function revokeConfirmation(uint256 txId) external override onlySigners txExists(txId) notExecuted(txId) {
        if (!_confirmations[txId][msg.sender]) {
            revert NotConfirmed(txId);
        }

        _confirmations[txId][msg.sender] = false;
        _transactions[txId].confirmations--;

        emit ConfirmationRevoked(txId, msg.sender);
    }

    /**
     * @dev Internal execution function
     */
    function _executeTransaction(uint256 txId) internal returns (bytes memory) {
        Transaction storage transaction = _transactions[txId];

        if (transaction.executed) {
            revert AlreadyExecuted(txId);
        }

        transaction.executed = true;

        bytes memory returnData;
        if (transaction.data.length > 0) {
            (bool success, bytes memory data) = transaction.destination.call{
                value: transaction.value
            }(transaction.data);
            if (!success) {
                // Revert with original error data
                assembly {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
            }
            returnData = data;
        } else {
            (bool success, ) = transaction.destination.call{value: transaction.value}(
                ""
            );
            if (!success) {
                assembly {
                    returndatacopy(0, 0, returndatasize())
                    revert(0, returndatasize())
                }
            }
        }

        emit TransactionExecuted(txId, msg.sender, returnData);

        return returnData;
    }

    /**
     * @inheritdoc ITreasury
     */
    function getTransaction(
        uint256 txId
    ) external view override returns (address, uint256, bytes memory, bool) {
        Transaction storage transaction = _transactions[txId];
        return (transaction.destination, transaction.value, transaction.data, transaction.executed);
    }

    /**
     * @inheritdoc ITreasury
     */
    function getConfirmationCount(
        uint256 txId
    ) external view override returns (uint256) {
        return _transactions[txId].confirmations;
    }

    /**
     * @inheritdoc ITreasury
     */
    function isConfirmed(
        uint256 txId,
        address signer
    ) external view override returns (bool) {
        return _confirmations[txId][signer];
    }

    /**
     * @inheritdoc ITreasury
     */
    function getSigners() external view override returns (address[] memory) {
        return _signers;
    }

    /**
     * @inheritdoc ITreasury
     */
    function getThreshold() external view override returns (uint256) {
        return _threshold;
    }

    /**
     * @inheritdoc ITreasury
     */
    function getTransactionCount() external view override returns (uint256) {
        return _transactionCount;
    }

    /**
     * @dev Check if address is a signer
     * @param account Address to check
     * @return Whether the address is a signer
     */
    function isSigner(address account) external view override returns (bool) {
        return _isSigner(account);
    }

    /**
     * @dev Internal signer check
     */
    function _isSigner(address account) internal view returns (bool) {
        for (uint256 i = 0; i < _signers.length; i++) {
            if (_signers[i] == account) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev Get balance of native tokens
     * @return Balance in wei
     */
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /**
     * @dev Get addresses that confirmed a transaction
     * @param txId Transaction ID
     * @return Array of confirmer addresses
     */
    function getTransactionConfirmers(uint256 txId) external view override returns (address[] memory) {
        if (txId >= _transactionCount) {
            return new address[](0);
        }

        uint256 count = _transactions[txId].confirmations;
        address[] memory confirmers = new address[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < _signers.length && index < count; i++) {
            if (_confirmations[txId][_signers[i]]) {
                confirmers[index] = _signers[i];
                index++;
            }
        }

        return confirmers;
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

    /**
     * @dev Add a new signer (owner only)
     * @param signer Address to add as signer
     */
    function addSigner(address signer) external onlyOwner {
        if (signer == address(0)) {
            revert InvalidDestination(signer);
        }
        if (_isSigner(signer)) {
            revert SignerAlreadyExists(signer);
        }
        _signers.push(signer);
        emit SignerAdded(signer);
    }

    /**
     * @dev Remove a signer (owner only)
     * @param signer Address to remove
     */
    function removeSigner(address signer) external onlyOwner {
        if (!_isSigner(signer)) {
            revert SignerNotFound(signer);
        }
        if (_signers.length - 1 < _threshold) {
            revert WouldViolateThreshold(_signers.length - 1, _threshold);
        }

        // Find and remove by swapping with last element
        for (uint256 i = 0; i < _signers.length; i++) {
            if (_signers[i] == signer) {
                _signers[i] = _signers[_signers.length - 1];
                _signers.pop();
                break;
            }
        }
        emit SignerRemoved(signer);
    }

    /**
     * @dev Update the confirmation threshold (owner only)
     * @param newThreshold New threshold value
     */
    function setThreshold(uint256 newThreshold) external onlyOwner {
        if (newThreshold == 0 || newThreshold > _signers.length) {
            revert InvalidThreshold(newThreshold, _signers.length);
        }
        _threshold = newThreshold;
        emit ThresholdUpdated(newThreshold);
    }

    // Events
    event Received(address indexed from, uint256 amount);
    event SignerAdded(address indexed signer);
    event SignerRemoved(address indexed signer);
    event ThresholdUpdated(uint256 newThreshold);
}
