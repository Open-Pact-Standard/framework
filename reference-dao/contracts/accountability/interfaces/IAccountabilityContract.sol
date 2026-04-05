// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title IAccountabilityContract
 * @dev Interface for Accountability contract
 */
interface IAccountabilityContract {
    // ============ Enums ============

    enum DisputeStatus {
        None,           // 0
        Filed,          // 1 - Dispute filed
        Voting,         // 2 - Voting in progress
        Resolved,       // 3 - Dispute resolved
        Cancelled       // 4 - Dispute cancelled
    }

    enum DisputeType {
        Quality,        // 0 - Work quality dispute
        Payment,        // 1 - Payment dispute
        Behavior,       // 2 - Behavior/conduct dispute
        Deadline,       // 3 - Deadline/timeout dispute
        Other           // 4 - Other dispute
    }

    // ============ Structs ============

    struct Dispute {
        uint256 id;
        uint256 bountyId;           // Related bounty (0 if not applicable)
        address filer;             // Who filed the dispute
        address respondent;         // Who the dispute is against
        DisputeType disputeType;
        string description;        // IPFS hash for details
        uint256 filerStake;         // Stake to file dispute
        uint256 respondentStake;   // Stake to respond
        uint256 timestamp;
        uint256 votingDeadline;
        DisputeStatus status;
        uint256 forVotes;           // Votes in favor of filer
        uint256 againstVotes;       // Votes against filer
        address winner;             // Dispute winner (set when resolved)
        string resolutionReason;   // Explanation of resolution
    }

    struct Vote {
        uint256 disputeId;
        address voter;
        bool forFiler;             // true = for filer, false = for respondent
        uint256 stake;              // Voting stake
        uint256 timestamp;
    }

    struct PerformanceRecord {
        address user;
        uint256 totalJobs;
        uint256 onTimeJobs;
        uint256 lateJobs;
        uint256 cancelledJobs;
        uint256 disputedJobs;
        uint256 lostDisputes;
        uint256 avgQualityScore;    // 0-100
        uint256 completionRate;     // Basis points (0-10000)
        uint256 onTimeRate;         // Basis points
        uint256 lastUpdated;
    }

    struct Penalty {
        uint256 id;
        address user;
        string reason;
        uint256 severity;           // 1-10
        uint256 timestamp;
        bool active;
    }

    // ============ Dispute Management ============

    function fileDispute(
        uint256 bountyId,
        address respondent,
        DisputeType disputeType,
        string calldata description
    ) external payable returns (uint256 disputeId);

    function respondToDispute(uint256 disputeId, string calldata response) external payable;

    function voteOnDispute(uint256 disputeId, bool forFiler) external payable;

    function resolveDispute(
        uint256 disputeId,
        address winner,
        string calldata reason
    ) external;

    function cancelDispute(uint256 disputeId) external;

    // ============ Performance Tracking ============

    function recordCompletion(
        uint256 bountyId,
        address worker,
        bool onTime,
        uint8 qualityScore
    ) external;

    function recordCancellation(uint256 bountyId, address worker, string calldata reason) external;

    function getPerformanceStats(address user)
        external
        view
        returns (PerformanceRecord memory);

    // ============ Penalties ============

    function issuePenalty(
        address user,
        string calldata reason,
        uint256 severity
    ) external;

    function liftPenalty(uint256 penaltyId) external;

    function hasActivePenalty(address user)
        external
        view
        returns (bool);

    function getPenalties(address user)
        external
        view
        returns (Penalty[] memory);

    // ============ View Functions ============

    function getDispute(uint256 disputeId)
        external
        view
        returns (Dispute memory);

    function getDisputeVote(uint256 disputeId, address voter)
        external
        view
        returns (Vote memory);

    function getActiveDisputes(uint256 offset, uint256 limit)
        external
        view
        returns (Dispute[] memory);

    function getUserDisputes(address user, uint256 offset, uint256 limit)
        external
        view
        returns (Dispute[] memory);

    // ============ Events ============

    event DisputeFiled(
        uint256 indexed disputeId,
        uint256 indexed bountyId,
        address indexed filer,
        address respondent
    );

    event DisputeResponded(uint256 indexed disputeId, address respondent);

    event VoteCast(
        uint256 indexed disputeId,
        address indexed voter,
        bool forFiler,
        uint256 stake
    );

    event DisputeResolved(
        uint256 indexed disputeId,
        address indexed winner,
        string reason
    );

    event DisputeCancelled(uint256 indexed disputeId);

    event PerformanceRecorded(
        uint256 indexed bountyId,
        address indexed worker,
        bool onTime,
        uint8 qualityScore
    );

    event PenaltyIssued(
        uint256 indexed penaltyId,
        address indexed user,
        uint256 severity
    );

    event PenaltyLifted(uint256 indexed penaltyId, address indexed user);
}
