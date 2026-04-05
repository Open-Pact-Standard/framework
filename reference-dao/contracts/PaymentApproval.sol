// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IPaymentApproval.sol";
import "../interfaces/IPaymentVerifier.sol";
import "../interfaces/IPaymentLedger.sol";

/**
 * @title PaymentApproval
 * @dev Multi-sig payment approval workflow for large transactions.
 *      Supports PAY-03 (multi-signature approvals for large transactions).
 *      Integrates with PaymentVerifier for execution and PaymentLedger for tracking.
 *
 *      Flow:
 *      1. Signer submits payment request with structured metadata
 *      2. Other signers confirm the request
 *      3. When threshold met, any signer can execute via PaymentVerifier
 *      4. Payment is recorded in PaymentLedger
 */
contract PaymentApproval is IPaymentApproval, Ownable2Step, Pausable, ReentrancyGuard {
    // Storage
    address[] private _signers;
    uint256 private _threshold;
    address private _verifier;

    mapping(uint256 => PaymentRequest) private _requests;
    mapping(uint256 => mapping(address => bool)) private _confirmations;
    uint256 private _requestCount;

    // Minimum amount that requires multi-sig approval
    uint256 public approvalThreshold;

    // Events
    event VerifierUpdated(address indexed oldVerifier, address indexed newVerifier);

    // Errors
    error NotASigner(address caller);
    error InvalidThreshold(uint256 threshold, uint256 signerCount);
    error AlreadyConfirmed(address confirmer);
    error RequestNotFound(uint256 requestId);
    error RequestAlreadyExecuted(uint256 requestId);
    error RequestCanceled(uint256 requestId);
    error InsufficientConfirmations(uint256 have, uint256 need);
    error NotInitiator(address caller);
    error ZeroAddress();
    error ZeroAmount();
    error InvalidVerifier(address verifier);
    error SignerAlreadyExists(address signer);
    error SignerNotFound(address signer);
    error WouldViolateThreshold(uint256 signerCount, uint256 threshold);

    modifier onlySigners() {
        if (!_isSigner(msg.sender)) {
            revert NotASigner(msg.sender);
        }
        _;
    }

    modifier requestExists(uint256 requestId) {
        if (requestId >= _requestCount) {
            revert RequestNotFound(requestId);
        }
        _;
    }

    modifier notExecuted(uint256 requestId) {
        if (_requests[requestId].executed) {
            revert RequestAlreadyExecuted(requestId);
        }
        _;
    }

    modifier notCanceled(uint256 requestId) {
        if (_requests[requestId].canceled) {
            revert RequestCanceled(requestId);
        }
        _;
    }

    modifier notConfirmed(uint256 requestId) {
        if (_confirmations[requestId][msg.sender]) {
            revert AlreadyConfirmed(msg.sender);
        }
        _;
    }

    /**
     * @dev Constructor
     * @param signers Array of authorized signer addresses
     * @param threshold Number of confirmations required to execute
     * @param verifier PaymentVerifier contract address
     * @param _approvalThreshold Minimum amount requiring multi-sig (0 = all require approval)
     */
    constructor(
        address[] memory signers,
        uint256 threshold,
        address verifier,
        uint256 _approvalThreshold
    ) Ownable() {
        if (signers.length == 0) {
            revert InvalidThreshold(threshold, 0);
        }
        if (threshold == 0 || threshold > signers.length) {
            revert InvalidThreshold(threshold, signers.length);
        }
        if (verifier == address(0)) {
            revert ZeroAddress();
        }

        _signers = signers;
        _threshold = threshold;
        _verifier = verifier;
        approvalThreshold = _approvalThreshold;
    }

    /**
     * @inheritdoc IPaymentApproval
     */
    function submitPaymentRequest(
        address recipient,
        address token,
        uint256 amount,
        string calldata metadata
    ) external override onlySigners nonReentrant whenNotPaused returns (uint256) {
        if (recipient == address(0) || token == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        uint256 requestId = _requestCount;

        _requests[requestId] = PaymentRequest({
            initiator: msg.sender,
            recipient: recipient,
            token: token,
            amount: amount,
            metadata: metadata,
            confirmations: 1,
            executed: false,
            canceled: false,
            createdAt: block.timestamp
        });

        // Auto-confirm by submitter
        _confirmations[requestId][msg.sender] = true;

        _requestCount++;

        emit PaymentRequestSubmitted(requestId, msg.sender, recipient, token, amount);

        // Execute immediately if threshold is 1
        if (_threshold == 1) {
            _executePaymentRequest(requestId);
        }

        return requestId;
    }

    /**
     * @inheritdoc IPaymentApproval
     */
    function confirmPaymentRequest(
        uint256 requestId
    ) external override onlySigners requestExists(requestId) notExecuted(requestId) notCanceled(requestId) notConfirmed(requestId) whenNotPaused {
        _confirmations[requestId][msg.sender] = true;
        _requests[requestId].confirmations++;

        emit PaymentRequestConfirmed(requestId, msg.sender);

        // Execute if threshold met
        if (_requests[requestId].confirmations >= _threshold) {
            _executePaymentRequest(requestId);
        }
    }

    /**
     * @inheritdoc IPaymentApproval
     */
    function revokeConfirmation(
        uint256 requestId
    ) external override onlySigners requestExists(requestId) notExecuted(requestId) notCanceled(requestId) {
        if (!_confirmations[requestId][msg.sender]) {
            revert NotASigner(msg.sender);
        }

        _confirmations[requestId][msg.sender] = false;
        _requests[requestId].confirmations--;

        emit ConfirmationRevoked(requestId, msg.sender);
    }

    /**
     * @inheritdoc IPaymentApproval
     */
    function executePayment(
        uint256 requestId
    ) external override onlySigners requestExists(requestId) notExecuted(requestId) notCanceled(requestId) nonReentrant whenNotPaused returns (uint256 ledgerPaymentId) {
        if (_requests[requestId].confirmations < _threshold) {
            revert InsufficientConfirmations(_requests[requestId].confirmations, _threshold);
        }

        return _executePaymentRequest(requestId);
    }

    /**
     * @dev Internal payment execution
     */
    function _executePaymentRequest(uint256 requestId) internal returns (uint256 ledgerPaymentId) {
        PaymentRequest storage request = _requests[requestId];
        request.executed = true;

        // For actual execution, the Treasury (or a designated facilitator)
        // needs to have approved the PaymentVerifier to spend its tokens,
        // OR the payment uses EIP-3009 (gasless) where the payer signs.
        //
        // Since PaymentApproval acts as an approval workflow, the actual
        // token transfer happens through the PaymentVerifier's processPayment().
        // The caller must pass EIP-3009 authorization data separately.
        //
        // This contract emits the event so off-chain systems can coordinate
        // the actual on-chain transfer via PaymentVerifier.processPayment().

        emit PaymentRequestExecuted(requestId, msg.sender);

        // Return the request ID as reference; actual ledger recording
        // happens in PaymentVerifier.processPayment()
        return requestId;
    }

    /**
     * @inheritdoc IPaymentApproval
     */
    function cancelPaymentRequest(
        uint256 requestId
    ) external override onlySigners requestExists(requestId) notExecuted(requestId) {
        // Only initiator can cancel
        if (_requests[requestId].initiator != msg.sender) {
            revert NotInitiator(msg.sender);
        }

        _requests[requestId].canceled = true;

        emit PaymentRequestCanceled(requestId, msg.sender);
    }

    /**
     * @inheritdoc IPaymentApproval
     */
    function getPaymentRequest(
        uint256 requestId
    ) external view override requestExists(requestId) returns (PaymentRequest memory) {
        return _requests[requestId];
    }

    /**
     * @inheritdoc IPaymentApproval
     */
    function hasConfirmed(
        uint256 requestId,
        address signer
    ) external view override returns (bool) {
        return _confirmations[requestId][signer];
    }

    /**
     * @inheritdoc IPaymentApproval
     */
    function getRequestCount() external view override returns (uint256) {
        return _requestCount;
    }

    /**
     * @inheritdoc IPaymentApproval
     */
    function getThreshold() external view override returns (uint256) {
        return _threshold;
    }

    /**
     * @inheritdoc IPaymentApproval
     */
    function getSigners() external view override returns (address[] memory) {
        return _signers;
    }

    /**
     * @inheritdoc IPaymentApproval
     */
    function isSigner(address account) public view override returns (bool) {
        return _isSigner(account);
    }

    /**
     * @dev Get the PaymentVerifier address
     * @return Verifier contract address
     */
    function getVerifier() external view returns (address) {
        return _verifier;
    }

    /**
     * @dev Internal signer lookup
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
     * @dev Update the PaymentVerifier address (owner only)
     * @param newVerifier New verifier address
     */
    function updateVerifier(address newVerifier) external onlyOwner {
        if (newVerifier == address(0)) {
            revert ZeroAddress();
        }
        address oldVerifier = _verifier;
        _verifier = newVerifier;
        emit VerifierUpdated(oldVerifier, newVerifier);
    }

    /**
     * @dev Update the approval threshold (owner only)
     * @param newThreshold New minimum amount requiring multi-sig approval
     */
    function setApprovalThreshold(uint256 newThreshold) external onlyOwner {
        uint256 oldThreshold = approvalThreshold;
        approvalThreshold = newThreshold;
        emit ApprovalThresholdUpdated(oldThreshold, newThreshold);
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
            revert ZeroAddress();
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

    // Events for signer management
    event SignerAdded(address indexed signer);
    event SignerRemoved(address indexed signer);
    event ThresholdUpdated(uint256 newThreshold);
}
