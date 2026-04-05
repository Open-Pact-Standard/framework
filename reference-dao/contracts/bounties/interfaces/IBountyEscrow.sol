// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IBountyEscrow
 * @dev Interface for Bounty Escrow contract
 */
interface IBountyEscrow {
    // ============ Enums ============

    enum EscrowStatus {
        None,           // 0
        Active,         // 1 - Funds deposited, awaiting completion
        Released,       // 2 - Payment released to worker
        Refunded,       // 3 - Refunded to poster
        Disputed,       // 4 - In dispute resolution
        ClaimedByPlatform // 5 - After dispute timeout
    }

    // ============ Structs ============

    struct Escrow {
        uint256 id;
        uint256 bountyId;
        address poster;             // Bounty creator
        address worker;             // Bounty assignee (set when assigned)
        address paymentToken;       // ERC-20 token
        uint256 amount;             // Payment amount
        uint256 platformFee;        // Platform fee amount
        uint256 netAmount;          // Amount after fees
        EscrowStatus status;
        uint256 createdAt;
        uint256 releaseDeadline;    // Auto-refund deadline
        uint256 disputeDeadline;    // Deadline to raise dispute
        bool isDisputable;          // Whether dispute can be raised
    }

    // ============ Escrow Management ============

    function createEscrow(
        uint256 bountyId,
        address paymentToken,
        uint256 amount,
        uint256 releaseDeadline
    ) external payable returns (uint256 escrowId);

    function fundEscrow(uint256 escrowId, uint256 amount) external payable;

    function releaseToWorker(uint256 escrowId) external;

    function refundToPoster(uint256 escrowId) external;

    function raiseDispute(uint256 escrowId, string calldata reason) external;

    function resolveDispute(
        uint256 escrowId,
        address winner,
        uint256 workerPercentage // Basis points (0-10000)
    ) external;

    function claimTimedOut(uint256 escrowId) external;

    // ============ View Functions ============

    function getEscrow(uint256 escrowId)
        external
        view
        returns (Escrow memory);

    function getEscrowByBounty(uint256 bountyId)
        external
        view
        returns (uint256 escrowId);

    function canRelease(uint256 escrowId)
        external
        view
        returns (bool);

    function canRefund(uint256 escrowId)
        external
        view
        returns (bool);

    function isDisputable(uint256 escrowId)
        external
        view
        returns (bool);

    function getPlatformFee(uint256 amount)
        external
        view
        returns (uint256 fee);

    function getPlatformFeeBps()
        external
        view
        returns (uint256);

    // ============ Platform Management ============

    function setPlatformFeeBps(uint256 newFeeBps) external;

    function withdrawPlatformFees(address token, uint256 amount) external;

    function getPlatformBalance(address token)
        external
        view
        returns (uint256);

    function setWorker(uint256 escrowId, address worker) external;

    // ============ Events ============

    event EscrowCreated(
        uint256 indexed escrowId,
        uint256 indexed bountyId,
        address indexed poster,
        address paymentToken,
        uint256 amount
    );

    event EscrowFunded(uint256 indexed escrowId, uint256 amount);

    event EscrowReleased(
        uint256 indexed escrowId,
        address indexed worker,
        uint256 amount
    );

    event EscrowRefunded(
        uint256 indexed escrowId,
        address indexed poster,
        uint256 amount
    );

    event DisputeRaised(uint256 indexed escrowId, address indexed raiser, string reason);

    event DisputeResolved(
        uint256 indexed escrowId,
        address winner,
        uint256 workerPercentage
    );

    event PlatformFeeCollected(
        uint256 indexed escrowId,
        uint256 fee
    );

    event PlatformFeesWithdrawn(
        address indexed token,
        uint256 amount
    );

    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
}
