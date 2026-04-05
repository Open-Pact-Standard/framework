// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title IBountyBoard
 * @dev Interface for Bounty Board contract
 */
interface IBountyBoard {
    // ============ Enums ============

    enum BountyStatus {
        None,           // 0
        Open,           // 1 - Accepting applications
        InProgress,     // 2 - Assigned, work in progress
        UnderReview,    // 3 - Submitted, awaiting review
        Completed,      // 4 - Approved and paid
        Cancelled,      // 5 - Cancelled, funds refunded
        Disputed        // 6 - In dispute resolution
    }

    enum BountyType {
        Open,           // 0 - Anyone can apply
        ServerOnly,     // 1 - Server members only
        RoleOnly,       // 2 - Specific role required
        InviteOnly,     // 3 - Invite only
        VerifiedOnly    // 4 - Verified users only
    }

    enum ApplicationStatus {
        None,           // 0
        Pending,        // 1 - Submitted, awaiting review
        Accepted,       // 2 - Approved for work
        Rejected,       // 3 - Not selected
        Withdrawn       // 4 - User withdrew
    }

    // ============ Structs ============

    struct Bounty {
        uint256 id;
        uint256 serverId;           // Server posting the bounty
        address poster;             // Who posted
        string title;
        string description;         // IPFS hash for long content
        address paymentToken;       // ERC-20 token address
        uint256 reward;             // Payment amount
        uint256 escrowId;           // Reference to escrow contract
        BountyType bountyType;
        uint8 minReputation;        // Minimum reputation required
        uint256[] requiredSkills;   // Required skill IDs
        uint256 deadline;           // Unix timestamp
        uint256 maxApplicants;      // Max number of applicants (0 = unlimited)
        BountyStatus status;
        address assignee;           // Current worker
        uint256 applicationCount;
        uint256 createdAt;
        uint256 updatedAt;
        bool isActive;
    }

    struct Application {
        uint256 id;
        uint256 bountyId;
        address applicant;
        string proposal;            // Application text/IPFS
        uint256 askedPrice;         // Optional: proposed price
        ApplicationStatus status;
        uint256 appliedAt;
        uint256 respondedAt;
    }

    struct Submission {
        uint256 id;
        uint256 bountyId;
        address submitter;
        string proof;               // IPFS hash of work proof
        string notes;
        uint256 submittedAt;
        bool isApproved;
    }

    // ============ Bounty Management ============

    function postBounty(
        uint256 serverId,
        string calldata title,
        string calldata description,
        address paymentToken,
        uint256 reward,
        uint256 deadline,
        uint256[] calldata requiredSkills,
        uint8 minReputation,
        BountyType bountyType,
        uint256 maxApplicants
    ) external payable returns (uint256 bountyId);

    function updateBounty(
        uint256 bountyId,
        string calldata title,
        string calldata description,
        uint256 deadline
    ) external;

    function cancelBounty(uint256 bountyId) external;

    // ============ Applications ============

    function applyForBounty(
        uint256 bountyId,
        string calldata proposal,
        uint256 askedPrice
    ) external returns (uint256 applicationId);

    function acceptApplication(uint256 bountyId, uint256 applicationId) external;

    function rejectApplication(uint256 bountyId, uint256 applicationId, string calldata reason) external;

    function withdrawApplication(uint256 applicationId) external;

    // ============ Work Submission ============

    function submitWork(
        uint256 bountyId,
        string calldata proof,
        string calldata notes
    ) external returns (uint256 submissionId);

    function approveWork(uint256 bountyId) external;

    function rejectWork(uint256 bountyId, string calldata reason) external;

    // ============ View Functions ============

    function getBounty(uint256 bountyId)
        external
        view
        returns (Bounty memory);

    function getApplication(uint256 applicationId)
        external
        view
        returns (Application memory);

    function getBountyApplications(uint256 bountyId)
        external
        view
        returns (Application[] memory);

    function getOpenBounties(uint256 offset, uint256 limit)
        external
        view
        returns (Bounty[] memory);

    function getBountiesByStatus(BountyStatus status, uint256 offset, uint256 limit)
        external
        view
        returns (Bounty[] memory);

    function getBountiesByServer(uint256 serverId, uint256 offset, uint256 limit)
        external
        view
        returns (Bounty[] memory);

    function getBountiesByApplicant(address applicant, uint256 offset, uint256 limit)
        external
        view
        returns (Bounty[] memory);

    function getUserApplications(address applicant)
        external
        view
        returns (uint256[] memory);

    function canApplyForBounty(uint256 bountyId, address applicant)
        external
        view
        returns (bool);

    // ============ Events ============

    event BountyPosted(
        uint256 indexed bountyId,
        uint256 indexed serverId,
        address indexed poster,
        string title,
        uint256 reward
    );

    event BountyUpdated(uint256 indexed bountyId, string title);

    event BountyCancelled(uint256 indexed bountyId);

    event ApplicationSubmitted(
        uint256 indexed applicationId,
        uint256 indexed bountyId,
        address indexed applicant
    );

    event ApplicationAccepted(
        uint256 indexed applicationId,
        uint256 indexed bountyId
    );

    event ApplicationRejected(
        uint256 indexed applicationId,
        uint256 indexed bountyId
    );

    event ApplicationWithdrawn(uint256 indexed applicationId);

    event WorkSubmitted(
        uint256 indexed submissionId,
        uint256 indexed bountyId,
        address indexed submitter
    );

    event WorkApproved(uint256 indexed bountyId, address worker);

    event WorkRejected(uint256 indexed bountyId, string reason);

    event BountyCompleted(uint256 indexed bountyId, uint256 reward);
}
