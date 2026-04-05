// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IEarningContract
 * @dev Interface for Earning contract
 */
interface IEarningContract {
    // ============ Enums ============

    enum StreamStatus {
        None,           // 0
        Active,         // 1 - Streaming
        Paused,         // 2 - Temporarily paused
        Cancelled,      // 3 - Cancelled
        Completed       // 4 - Fully streamed
    }

    // ============ Structs ============

    struct Earning {
        address earner;
        address token;
        uint256 balance;
        uint256 totalEarned;
        uint256 lastUpdated;
    }

    struct PaymentStream {
        uint256 id;
        address payer;
        address recipient;
        address token;
        uint256 ratePerSecond;      // Payment rate
        uint256 totalAmount;        // Total amount to be streamed
        uint256 withdrawnAmount;    // Amount already withdrawn
        uint256 startTime;
        uint256 stopTime;
        StreamStatus status;
    }

    struct EarningRecord {
        uint256 id;
        address earner;
        address source;             // Who paid
        address token;
        uint256 amount;
        string reason;              // Bounty ID, job reference, etc.
        uint256 timestamp;
    }

    // ============ Balance Management ============

    function depositEarnings(
        address earner,
        address token,
        uint256 amount,
        string calldata reason
    ) external payable;

    function withdrawEarnings(
        address token,
        uint256 amount
    ) external;

    function withdrawAll(address token) external;

    // ============ Payment Streams ============

    function createStream(
        address recipient,
        address token,
        uint256 ratePerSecond,
        uint256 totalAmount
    ) external payable returns (uint256 streamId);

    function cancelStream(uint256 streamId) external;

    function pauseStream(uint256 streamId) external;

    function resumeStream(uint256 streamId) external;

    function withdrawFromStream(uint256 streamId, uint256 amount) external;

    function withdrawAllFromStream(uint256 streamId) external;

    // ============ View Functions ============

    function getEarning(address earner, address token)
        external
        view
        returns (Earning memory);

    function getAllEarnings(address earner)
        external
        view
        returns (Earning[] memory);

    function getTotalEarnings(address earner)
        external
        view
        returns (uint256);

    function getStream(uint256 streamId)
        external
        view
        returns (PaymentStream memory);

    function getStreamsByPayer(address payer)
        external
        view
        returns (uint256[] memory);

    function getStreamsByRecipient(address recipient)
        external
        view
        returns (uint256[] memory);

    function getStreamBalance(uint256 streamId)
        external
        view
        returns (uint256);

    function getEarningRecords(address earner, uint256 offset, uint256 limit)
        external
        view
        returns (EarningRecord[] memory);

    // ============ Events ============

    event EarningsDeposited(
        address indexed earner,
        address indexed token,
        uint256 amount,
        string reason
    );

    event EarningsWithdrawn(
        address indexed earner,
        address indexed token,
        uint256 amount
    );

    event StreamCreated(
        uint256 indexed streamId,
        address indexed payer,
        address indexed recipient,
        address token,
        uint256 ratePerSecond,
        uint256 totalAmount
    );

    event StreamCancelled(uint256 indexed streamId);

    event StreamPaused(uint256 indexed streamId);

    event StreamResumed(uint256 indexed streamId);

    event StreamWithdrawn(
        uint256 indexed streamId,
        address indexed recipient,
        uint256 amount
    );

    event StreamCompleted(uint256 indexed streamId);
}
