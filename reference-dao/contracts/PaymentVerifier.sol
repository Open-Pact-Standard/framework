// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IEIP3009.sol";
import "../interfaces/IPaymentVerifier.sol";
import "../interfaces/IPaymentLedger.sol";

/**
 * @title PaymentVerifier
 * @dev On-chain x402 payment verification and execution contract with rate limiting.
 *      Acts as the custom Flare facilitator for EIP-3009 authorizations.
 *      Supports PAY-01 (x402 payment processing).
 *
 *      Security Features:
 *      - Per-payer daily limits
 *      - Per-recipient daily limits
 *      - Global daily limit
 *      - Sliding window rate limiting
 *
 *      Flow:
 *      1. Client signs EIP-3009 authorization off-chain
 *      2. Server/facilitator calls processPayment() with the signed authorization
 *      3. Contract validates rate limits
 *      4. Contract calls USD₮0.transferWithAuthorization() to move tokens
 *      5. Payment is recorded and settled in PaymentLedger
 */
contract PaymentVerifier is IPaymentVerifier, Ownable, Pausable, ReentrancyGuard {
    // Storage
    address public immutable override getLedger;
    mapping(address => bool) private _facilitators;
    mapping(address => bool) private _supportedTokens;
    address[] private _tokenList;

    // Payment limits
    uint256 public maxPaymentAmount;
    uint256 public minPaymentAmount;

    // Rate limiting - 1 day window
    uint256 public constant RATE_LIMIT_WINDOW = 1 days;
    uint256 public maxDailyVolumeGlobal;        // Global daily limit
    uint256 public maxDailyVolumePerPayer;      // Per-payer daily limit
    uint256 public maxDailyVolumePerRecipient;  // Per-recipient daily limit

    // Rate limit tracking
    uint256 public currentDay;                  // Current day timestamp
    uint256 public globalDailyVolume;           // Today's global volume
    mapping(address => uint256) public payerDailyVolume;      // Payer -> today's volume
    mapping(address => uint256) public recipientDailyVolume; // Recipient -> today's volume
    mapping(address => uint256) private payerLastDay;         // Payer -> last update day
    mapping(address => uint256) private recipientLastDay;    // Recipient -> last update day

    // Circuit breaker
    uint256 public circuitBreakerThreshold;     // Threshold to trigger circuit breaker
    bool public circuitBreakerTriggered;        // Circuit breaker state

    // Events
    event FacilitatorUpdated(address indexed facilitator, bool status);
    event TokenSupported(address indexed token, bool status);
    event PaymentLimitsUpdated(uint256 minAmount, uint256 maxAmount);
    event RateLimitsUpdated(
        uint256 maxGlobal,
        uint256 maxPerPayer,
        uint256 maxPerRecipient,
        uint256 circuitBreakerThreshold
    );
    event DayReset(uint256 oldDay, uint256 newDay, uint256 previousVolume);
    event CircuitBreakerTriggered(uint256 volume, uint256 threshold);
    event CircuitBreakerReset();

    // Errors
    error ZeroAddress();
    error TokenNotSupported(address token);
    error AmountBelowMinimum(uint256 amount, uint256 minimum);
    error AmountAboveMaximum(uint256 amount, uint256 maximum);
    error NotFacilitator(address caller);
    error InvalidAuthorization(address from, address to);
    error AuthorizationExpired(uint256 validBefore);
    error AuthorizationNotYetValid(uint256 validAfter);
    error TransferFailed(bytes reason);
    error InvalidSignature();
    error InvalidLimits();
    error DailyLimitExceeded(uint256 amount, uint256 limit, string limitType);
    error CircuitBreakerActive();

    modifier onlyFacilitators() {
        if (!_facilitators[msg.sender] && msg.sender != owner()) {
            revert NotFacilitator(msg.sender);
        }
        _;
    }

    /**
     * @dev Constructor
     * @param _ledger PaymentLedger contract address
     * @param initialTokens Initial list of supported payment tokens
     * @param _maxPaymentAmount Maximum single payment amount
     * @param _maxDailyVolumeGlobal Global daily volume limit
     * @param _maxDailyVolumePerPayer Per-payer daily volume limit
     * @param _maxDailyVolumePerRecipient Per-recipient daily volume limit
     * @param _circuitBreakerThreshold Circuit breaker threshold (0 = disabled)
     */
    constructor(
        address _ledger,
        address[] memory initialTokens,
        uint256 _maxPaymentAmount,
        uint256 _maxDailyVolumeGlobal,
        uint256 _maxDailyVolumePerPayer,
        uint256 _maxDailyVolumePerRecipient,
        uint256 _circuitBreakerThreshold
    ) Ownable() {
        if (_ledger == address(0)) {
            revert ZeroAddress();
        }

        getLedger = _ledger;
        maxPaymentAmount = _maxPaymentAmount;
        minPaymentAmount = 1; // 1 wei minimum by default

        // Set rate limits
        maxDailyVolumeGlobal = _maxDailyVolumeGlobal;
        maxDailyVolumePerPayer = _maxDailyVolumePerPayer;
        maxDailyVolumePerRecipient = _maxDailyVolumePerRecipient;
        circuitBreakerThreshold = _circuitBreakerThreshold;

        // Initialize day tracking
        currentDay = block.timestamp / RATE_LIMIT_WINDOW;

        for (uint256 i = 0; i < initialTokens.length; i++) {
            if (initialTokens[i] == address(0)) {
                revert ZeroAddress();
            }
            _supportedTokens[initialTokens[i]] = true;
            _tokenList.push(initialTokens[i]);
        }

        // Owner is a facilitator by default
        _facilitators[msg.sender] = true;
    }

    /**
     * @inheritdoc IPaymentVerifier
     */
    function processPayment(
        PaymentParams calldata params
    ) external override onlyFacilitators nonReentrant whenNotPaused returns (uint256 ledgerPaymentId) {
        // Check circuit breaker first
        if (circuitBreakerTriggered) {
            revert CircuitBreakerActive();
        }

        // Validate token support
        if (!_supportedTokens[params.token]) {
            revert TokenNotSupported(params.token);
        }

        // Validate amount
        if (params.amount < minPaymentAmount) {
            revert AmountBelowMinimum(params.amount, minPaymentAmount);
        }
        if (params.amount > maxPaymentAmount) {
            revert AmountAboveMaximum(params.amount, maxPaymentAmount);
        }

        // Validate addresses
        if (params.payer == address(0) || params.recipient == address(0)) {
            revert ZeroAddress();
        }

        // Validate authorization timing
        if (block.timestamp < params.validAfter) {
            revert AuthorizationNotYetValid(params.validAfter);
        }
        if (block.timestamp >= params.validBefore) {
            revert AuthorizationExpired(params.validBefore);
        }

        // Update daily limits and check rate limits
        _updateDailyVolume(params.payer, params.recipient, params.amount);

        // Compute authorization hash for ledger record
        bytes32 authHash = keccak256(
            abi.encodePacked(
                params.payer,
                params.recipient,
                params.amount,
                params.validAfter,
                params.validBefore,
                params.nonce
            )
        );

        // Record payment in ledger (unsettled)
        ledgerPaymentId = IPaymentLedger(getLedger).recordPayment(
            params.payer,
            params.recipient,
            params.token,
            params.amount,
            IPaymentLedger.PaymentType.X402,
            authHash,
            ""
        );

        // Execute the EIP-3009 transfer
        IEIP3009 token = IEIP3009(params.token);
        try
            token.transferWithAuthorization(
                params.payer,
                params.recipient,
                params.amount,
                params.validAfter,
                params.validBefore,
                params.nonce,
                params.v,
                params.r,
                params.s
            )
        {
            // Transfer succeeded - settle the payment
            IPaymentLedger(getLedger).settlePayment(ledgerPaymentId, bytes32(0));

            emit PaymentProcessed(
                params.payer,
                params.recipient,
                params.token,
                params.amount,
                ledgerPaymentId
            );
        } catch (bytes memory reason) {
            emit PaymentVerificationFailed(
                params.payer,
                params.recipient,
                params.amount,
                reason
            );
            revert TransferFailed(reason);
        }

        return ledgerPaymentId;
    }

    /**
     * @dev Update daily volume tracking and check limits
     * @param payer Payer address
     * @param recipient Recipient address
     * @param amount Payment amount
     */
    function _updateDailyVolume(address payer, address recipient, uint256 amount) internal {
        uint256 newDay = block.timestamp / RATE_LIMIT_WINDOW;

        // Reset global counter if new day
        if (newDay != currentDay) {
            uint256 oldVolume = globalDailyVolume;
            currentDay = newDay;
            globalDailyVolume = 0;
            emit DayReset(currentDay, newDay, oldVolume);
        }

        // Reset payer volume if new day for this payer
        if (payerLastDay[payer] != newDay) {
            payerDailyVolume[payer] = 0;
            payerLastDay[payer] = newDay;
        }

        // Reset recipient volume if new day for this recipient
        if (recipientLastDay[recipient] != newDay) {
            recipientDailyVolume[recipient] = 0;
            recipientLastDay[recipient] = newDay;
        }

        // Check and update global limit
        uint256 newGlobalVolume = globalDailyVolume + amount;
        if (newGlobalVolume > maxDailyVolumeGlobal) {
            revert DailyLimitExceeded(newGlobalVolume, maxDailyVolumeGlobal, "global");
        }
        globalDailyVolume = newGlobalVolume;

        // Check and update payer limit
        uint256 newPayerVolume = payerDailyVolume[payer] + amount;
        if (newPayerVolume > maxDailyVolumePerPayer) {
            revert DailyLimitExceeded(newPayerVolume, maxDailyVolumePerPayer, "payer");
        }
        payerDailyVolume[payer] = newPayerVolume;

        // Check and update recipient limit
        uint256 newRecipientVolume = recipientDailyVolume[recipient] + amount;
        if (newRecipientVolume > maxDailyVolumePerRecipient) {
            revert DailyLimitExceeded(newRecipientVolume, maxDailyVolumePerRecipient, "recipient");
        }
        recipientDailyVolume[recipient] = newRecipientVolume;

        // Check circuit breaker
        if (circuitBreakerThreshold > 0 && newGlobalVolume >= circuitBreakerThreshold) {
            circuitBreakerTriggered = true;
            emit CircuitBreakerTriggered(newGlobalVolume, circuitBreakerThreshold);
        }
    }

    /**
     * @inheritdoc IPaymentVerifier
     */
    function cancelAuthorization(
        address token,
        address authorizer,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        if (!_supportedTokens[token]) {
            revert TokenNotSupported(token);
        }

        IEIP3009(token).cancelAuthorization(authorizer, nonce, v, r, s);

        emit AuthorizationCanceled(authorizer, nonce);
    }

    /**
     * @inheritdoc IPaymentVerifier
     */
    function isFacilitator(address account) external view override returns (bool) {
        return _facilitators[account];
    }

    /**
     * @inheritdoc IPaymentVerifier
     */
    function getSupportedTokens() external view override returns (address[] memory) {
        return _tokenList;
    }

    /**
     * @dev Check if a token is supported
     * @param token Token address to check
     * @return Whether the token is supported
     */
    function isTokenSupported(address token) external view returns (bool) {
        return _supportedTokens[token];
    }

    /**
     * @dev Get current daily volume for an address
     * @param addr Address to check
     * @return payerVolume Volume as payer
     * @return recipientVolume Volume as recipient
     */
    function getAddressDailyVolume(address addr) external view returns (
        uint256 payerVolume,
        uint256 recipientVolume
    ) {
        return (payerDailyVolume[addr], recipientDailyVolume[addr]);
    }

    /**
     * @dev Get rate limit status
     * @return globalRemaining Remaining global volume for today
     * @return payerRemaining Remaining volume for payer
     * @return recipientRemaining Remaining volume for recipient
     * @return currentTimestamp Current day timestamp
     * @return secondsUntilReset Seconds until daily reset
     */
    function getRateLimitStatus(address payer, address recipient) external view returns (
        uint256 globalRemaining,
        uint256 payerRemaining,
        uint256 recipientRemaining,
        uint256 currentTimestamp,
        uint256 secondsUntilReset
    ) {
        uint256 remainingGlobal = globalDailyVolume >= maxDailyVolumeGlobal ? 0 : maxDailyVolumeGlobal - globalDailyVolume;
        uint256 remainingPayer = payerDailyVolume[payer] >= maxDailyVolumePerPayer ? 0 : maxDailyVolumePerPayer - payerDailyVolume[payer];
        uint256 remainingRecipient = recipientDailyVolume[recipient] >= maxDailyVolumePerRecipient ? 0 : maxDailyVolumePerRecipient - recipientDailyVolume[recipient];
        uint256 dayEnd = (currentDay + 1) * RATE_LIMIT_WINDOW;

        return (
            remainingGlobal,
            remainingPayer,
            remainingRecipient,
            currentDay * RATE_LIMIT_WINDOW,
            dayEnd > block.timestamp ? dayEnd - block.timestamp : 0
        );
    }

    /**
     * @dev Add or remove a facilitator
     * @param facilitator Address to update
     * @param status Whether the address should be a facilitator
     */
    function setFacilitator(address facilitator, bool status) external onlyOwner {
        if (facilitator == address(0)) {
            revert ZeroAddress();
        }
        _facilitators[facilitator] = status;
        emit FacilitatorUpdated(facilitator, status);
    }

    /**
     * @dev Add a supported payment token
     * @param token Token address to support
     */
    function addSupportedToken(address token) external onlyOwner {
        if (token == address(0)) {
            revert ZeroAddress();
        }
        if (!_supportedTokens[token]) {
            _supportedTokens[token] = true;
            _tokenList.push(token);
            emit TokenSupported(token, true);
        }
    }

    /**
     * @dev Remove a supported payment token
     * @param token Token address to remove
     */
    function removeSupportedToken(address token) external onlyOwner {
        _supportedTokens[token] = false;
        emit TokenSupported(token, false);
    }

    /**
     * @dev Update payment amount limits
     * @param _minPaymentAmount New minimum amount
     * @param _maxPaymentAmount New maximum amount
     */
    function setPaymentLimits(uint256 _minPaymentAmount, uint256 _maxPaymentAmount) external onlyOwner {
        if (_minPaymentAmount > _maxPaymentAmount || _maxPaymentAmount == 0) {
            revert InvalidLimits();
        }
        minPaymentAmount = _minPaymentAmount;
        maxPaymentAmount = _maxPaymentAmount;
        emit PaymentLimitsUpdated(_minPaymentAmount, _maxPaymentAmount);
    }

    /**
     * @dev Update rate limit configuration
     * @param _maxDailyVolumeGlobal New global daily limit
     * @param _maxDailyVolumePerPayer New per-payer daily limit
     * @param _maxDailyVolumePerRecipient New per-recipient daily limit
     * @param _circuitBreakerThreshold New circuit breaker threshold (0 to disable)
     */
    function setRateLimits(
        uint256 _maxDailyVolumeGlobal,
        uint256 _maxDailyVolumePerPayer,
        uint256 _maxDailyVolumePerRecipient,
        uint256 _circuitBreakerThreshold
    ) external onlyOwner {
        if (_maxDailyVolumeGlobal == 0 || _maxDailyVolumePerPayer == 0 || _maxDailyVolumePerRecipient == 0) {
            revert InvalidLimits();
        }
        maxDailyVolumeGlobal = _maxDailyVolumeGlobal;
        maxDailyVolumePerPayer = _maxDailyVolumePerPayer;
        maxDailyVolumePerRecipient = _maxDailyVolumePerRecipient;
        circuitBreakerThreshold = _circuitBreakerThreshold;

        emit RateLimitsUpdated(
            _maxDailyVolumeGlobal,
            _maxDailyVolumePerPayer,
            _maxDailyVolumePerRecipient,
            _circuitBreakerThreshold
        );
    }

    /**
     * @dev Reset the circuit breaker (owner only)
     */
    function resetCircuitBreaker() external onlyOwner {
        circuitBreakerTriggered = false;
        emit CircuitBreakerReset();
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
