// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { IEarningContract } from "./interfaces/IEarningContract.sol";

/**
 * @title EarningContract
 * @dev Track and manage user earnings with payment streaming
 *
 *      Features:
 *      - Track user earnings across multiple tokens
 *      - Deposit and withdraw earnings
 *      - Create payment streams (salary, recurring payments)
 *      - Earning history/records
 *      - Multi-token support
 */
contract EarningContract is IEarningContract, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Native ETH address (0x0)
    address private constant NATIVE_TOKEN = address(0);

    /// @notice Stream ID counter
    uint256 private _streamIdCounter;

    /// @notice Record ID counter
    uint256 private _recordIdCounter;

    /// @notice Earner => Token => Earning
    mapping(address => mapping(address => Earning)) private _earnings;

    /// @notice Earner => List of tokens they have earned
    mapping(address => address[]) private _earnerTokens;

    /// @notice Stream ID => PaymentStream
    mapping(uint256 => PaymentStream) private _streams;

    /// @notice Payer => Stream IDs
    mapping(address => uint256[]) private _payerStreams;

    /// @notice Recipient => Stream IDs
    mapping(address => uint256[]) private _recipientStreams;

    /// @notice Record ID => EarningRecord
    mapping(uint256 => EarningRecord) private _records;

    /// @notice Earner => Record IDs
    mapping(address => uint256[]) private _earnerRecords;

    /// @notice Min stream rate per second (prevents dust)
    uint256 public constant MIN_RATE_PER_SECOND = 1 wei;

    /// @notice Max stream duration (1 year)
    uint256 public constant MAX_STREAM_DURATION = 365 days;

    // ============ Custom Errors ============

    error EC_InvalidAmount();
    error EC_InvalidToken();
    error EC_InvalidRate();
    error EC_InvalidDuration();
    error EC_StreamNotFound();
    error EC_StreamNotActive();
    error EC_NotPayer();
    error EC_NotRecipient();
    error EC_InsufficientBalance();
    error EC_StreamNotCancellable();
    error EC_ZeroAddress();

    // ============ Constructor ============

    constructor() Ownable() {}

    // ============ Balance Management ============

    /**
     * @notice Deposit earnings to a user
     */
    function depositEarnings(
        address earner,
        address token,
        uint256 amount,
        string calldata reason
    ) external payable {
        if (amount == 0) revert EC_InvalidAmount();
        if (earner == address(0)) revert EC_ZeroAddress();

        _recordIdCounter++;
        uint256 recordId = _recordIdCounter;

        if (token == NATIVE_TOKEN) {
            if (msg.value < amount) revert EC_InvalidAmount();
        } else {
            if (msg.value != 0) revert EC_InvalidToken();
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        }

        // Update earning balance
        Earning storage earning = _earnings[earner][token];
        earning.earner = earner;
        earning.token = token;
        earning.balance += amount;
        earning.totalEarned += amount;
        earning.lastUpdated = block.timestamp;

        // Add token to earner's list if new
        if (earning.balance == amount) {
            _earnerTokens[earner].push(token);
        }

        // Record earning
        _records[recordId] = EarningRecord({
            id: recordId,
            earner: earner,
            source: msg.sender,
            token: token,
            amount: amount,
            reason: reason,
            timestamp: block.timestamp
        });

        _earnerRecords[earner].push(recordId);

        emit EarningsDeposited(earner, token, amount, reason);
    }

    /**
     * @notice Withdraw earnings
     */
    function withdrawEarnings(
        address token,
        uint256 amount
    ) external {
        if (amount == 0) revert EC_InvalidAmount();

        Earning storage earning = _earnings[msg.sender][token];

        if (earning.balance < amount) revert EC_InsufficientBalance();

        earning.balance -= amount;
        earning.lastUpdated = block.timestamp;

        if (token == NATIVE_TOKEN) {
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit EarningsWithdrawn(msg.sender, token, amount);
    }

    /**
     * @notice Withdraw all earnings for a token
     */
    function withdrawAll(address token) external {
        Earning storage earning = _earnings[msg.sender][token];

        uint256 amount = earning.balance;
        if (amount == 0) revert EC_InvalidAmount();

        earning.balance = 0;
        earning.lastUpdated = block.timestamp;

        if (token == NATIVE_TOKEN) {
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit EarningsWithdrawn(msg.sender, token, amount);
    }

    // ============ Payment Streams ============

    /**
     * @notice Create a payment stream
     */
    function createStream(
        address recipient,
        address token,
        uint256 ratePerSecond,
        uint256 totalAmount
    ) external payable returns (uint256 streamId) {
        if (recipient == address(0)) revert EC_ZeroAddress();
        if (ratePerSecond < MIN_RATE_PER_SECOND) revert EC_InvalidRate();
        if (totalAmount == 0) revert EC_InvalidAmount();

        uint256 duration = totalAmount / ratePerSecond;
        if (duration > MAX_STREAM_DURATION) revert EC_InvalidDuration();

        _streamIdCounter++;
        streamId = _streamIdCounter;

        // Transfer total amount to contract
        if (token == NATIVE_TOKEN) {
            if (msg.value < totalAmount) revert EC_InvalidAmount();
        } else {
            if (msg.value != 0) revert EC_InvalidToken();
            IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);
        }

        uint256 stopTime = block.timestamp + duration;

        _streams[streamId] = PaymentStream({
            id: streamId,
            payer: msg.sender,
            recipient: recipient,
            token: token,
            ratePerSecond: ratePerSecond,
            totalAmount: totalAmount,
            withdrawnAmount: 0,
            startTime: block.timestamp,
            stopTime: stopTime,
            status: StreamStatus.Active
        });

        _payerStreams[msg.sender].push(streamId);
        _recipientStreams[recipient].push(streamId);

        emit StreamCreated(streamId, msg.sender, recipient, token, ratePerSecond, totalAmount);
        return streamId;
    }

    /**
     * @notice Cancel a stream (payer only, before recipient withdraws)
     */
    function cancelStream(uint256 streamId) external {
        PaymentStream storage stream = _streams[streamId];

        if (stream.id != streamId) revert EC_StreamNotFound();
        if (stream.payer != msg.sender) revert EC_NotPayer();
        if (stream.status != StreamStatus.Active) revert EC_StreamNotActive();

        // Calculate remaining amount
        uint256 remaining = _getStreamBalance(stream);

        stream.status = StreamStatus.Cancelled;

        // Refund remaining to payer
        if (remaining > 0) {
            if (stream.token == NATIVE_TOKEN) {
                (bool success, ) = stream.payer.call{value: remaining}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(stream.token).safeTransfer(stream.payer, remaining);
            }
        }

        emit StreamCancelled(streamId);
    }

    /**
     * @notice Pause a stream
     */
    function pauseStream(uint256 streamId) external {
        PaymentStream storage stream = _streams[streamId];

        if (stream.id != streamId) revert EC_StreamNotFound();
        if (stream.payer != msg.sender) revert EC_NotPayer();
        if (stream.status != StreamStatus.Active) revert EC_StreamNotActive();

        stream.status = StreamStatus.Paused;

        emit StreamPaused(streamId);
    }

    /**
     * @notice Resume a paused stream
     */
    function resumeStream(uint256 streamId) external {
        PaymentStream storage stream = _streams[streamId];

        if (stream.id != streamId) revert EC_StreamNotFound();
        if (stream.payer != msg.sender) revert EC_NotPayer();
        if (stream.status != StreamStatus.Paused) revert EC_StreamNotActive();

        // Adjust stop time to account for paused period
        uint256 elapsed = block.timestamp - stream.startTime;
        uint256 alreadyPaid = (elapsed * stream.ratePerSecond);
        uint256 remaining = stream.totalAmount - alreadyPaid;
        uint256 newDuration = remaining / stream.ratePerSecond;

        stream.stopTime = block.timestamp + newDuration;
        stream.status = StreamStatus.Active;

        emit StreamResumed(streamId);
    }

    /**
     * @notice Withdraw from a stream
     */
    function withdrawFromStream(uint256 streamId, uint256 amount) external {
        PaymentStream storage stream = _streams[streamId];

        if (stream.id != streamId) revert EC_StreamNotFound();
        if (stream.recipient != msg.sender) revert EC_NotRecipient();
        if (stream.status != StreamStatus.Active && stream.status != StreamStatus.Paused) {
            revert EC_StreamNotActive();
        }

        uint256 available = _getStreamBalance(stream);
        if (amount > available) revert EC_InsufficientBalance();

        stream.withdrawnAmount += amount;

        if (stream.token == NATIVE_TOKEN) {
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(stream.token).safeTransfer(msg.sender, amount);
        }

        // Check if stream is complete
        if (stream.withdrawnAmount >= stream.totalAmount) {
            stream.status = StreamStatus.Completed;
            emit StreamCompleted(streamId);
        }

        emit StreamWithdrawn(streamId, msg.sender, amount);
    }

    /**
     * @notice Withdraw all available from a stream
     */
    function withdrawAllFromStream(uint256 streamId) external {
        PaymentStream storage stream = _streams[streamId];

        if (stream.id != streamId) revert EC_StreamNotFound();
        if (stream.recipient != msg.sender) revert EC_NotRecipient();

        uint256 amount = _getStreamBalance(stream);
        if (amount == 0) revert EC_InvalidAmount();

        stream.withdrawnAmount += amount;

        if (stream.token == NATIVE_TOKEN) {
            (bool success, ) = msg.sender.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(stream.token).safeTransfer(msg.sender, amount);
        }

        if (stream.withdrawnAmount >= stream.totalAmount) {
            stream.status = StreamStatus.Completed;
            emit StreamCompleted(streamId);
        }

        emit StreamWithdrawn(streamId, msg.sender, amount);
    }

    // ============ View Functions ============

    /**
     * @notice Get earning for a specific token
     */
    function getEarning(address earner, address token)
        external
        view
        returns (Earning memory)
    {
        return _earnings[earner][token];
    }

    /**
     * @notice Get all earnings for an earner
     */
    function getAllEarnings(address earner)
        external
        view
        returns (Earning[] memory)
    {
        address[] memory tokens = _earnerTokens[earner];
        Earning[] memory earnings = new Earning[](tokens.length);

        for (uint256 i = 0; i < tokens.length; i++) {
            earnings[i] = _earnings[earner][tokens[i]];
        }

        return earnings;
    }

    /**
     * @notice Get total earnings across all tokens (USD value would need oracle)
     */
    function getTotalEarnings(address earner)
        external
        view
        returns (uint256)
    {
        address[] memory tokens = _earnerTokens[earner];
        uint256 total = 0;

        for (uint256 i = 0; i < tokens.length; i++) {
            total += _earnings[earner][tokens[i]].totalEarned;
        }

        return total;
    }

    /**
     * @notice Get stream details
     */
    function getStream(uint256 streamId)
        external
        view
        returns (PaymentStream memory)
    {
        PaymentStream storage stream = _streams[streamId];
        if (stream.id != streamId) revert EC_StreamNotFound();
        return stream;
    }

    /**
     * @notice Get stream IDs by payer
     */
    function getStreamsByPayer(address payer)
        external
        view
        returns (uint256[] memory)
    {
        return _payerStreams[payer];
    }

    /**
     * @notice Get stream IDs by recipient
     */
    function getStreamsByRecipient(address recipient)
        external
        view
        returns (uint256[] memory)
    {
        return _recipientStreams[recipient];
    }

    /**
     * @notice Get available balance in a stream
     */
    function getStreamBalance(uint256 streamId)
        external
        view
        returns (uint256)
    {
        PaymentStream storage stream = _streams[streamId];
        if (stream.id != streamId) revert EC_StreamNotFound();
        return _getStreamBalance(stream);
    }

    /**
     * @notice Get earning records
     */
    function getEarningRecords(address earner, uint256 offset, uint256 limit)
        external
        view
        returns (EarningRecord[] memory)
    {
        uint256[] memory recordIds = _earnerRecords[earner];

        uint256 start = offset;
        uint256 end = offset + limit;
        if (end > recordIds.length) end = recordIds.length;

        EarningRecord[] memory records = new EarningRecord[](end - start);

        for (uint256 i = start; i < end; i++) {
            records[i - start] = _records[recordIds[recordIds.length - 1 - i]];
        }

        return records;
    }

    // ============ Internal Functions ============

    function _getStreamBalance(PaymentStream storage stream)
        internal
        view
        returns (uint256)
    {
        if (stream.status == StreamStatus.Completed) return 0;
        if (stream.status == StreamStatus.Cancelled) return 0;

        uint256 currentTime = block.timestamp;
        if (stream.status == StreamStatus.Paused) {
            currentTime = stream.stopTime; // Use pause time as current
        }

        if (currentTime < stream.startTime) return 0;
        if (currentTime > stream.stopTime) currentTime = stream.stopTime;

        uint256 elapsed = currentTime - stream.startTime;
        uint256 accrued = (elapsed * stream.ratePerSecond);

        if (accrued > stream.totalAmount) accrued = stream.totalAmount;

        return accrued - stream.withdrawnAmount;
    }

    /**
     * @notice Allow contract to receive ETH
     */
    receive() external payable {}
}
