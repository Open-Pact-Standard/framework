// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

/**
 * @title IEnhancedReputation
 * @dev Interface for Enhanced Reputation contract
 *      Anti-brigading reputation system
 */
interface IEnhancedReputation {
    // ============ Structs ============

    struct Review {
        uint256 id;
        uint256 subjectId;          // User being reviewed
        address reviewer;
        int8 score;                 // -5 to +5
        uint256 stake;              // Amount staked
        string evidence;            // IPFS hash of evidence
        uint256 timestamp;
        bool isValid;
        bool isChallenged;
        uint256 attestations;       // Number of attestations
        uint256 diversityScore;     // Calculated diversity bonus
        int256 finalScore;          // Score after all adjustments
    }

    struct Attestation {
        uint256 reviewId;
        address attester;
        bool isValid;
        uint256 timestamp;
    }

    struct Challenge {
        uint256 reviewId;
        address challenger;
        string reason;
        uint256 stake;
        uint256 timestamp;
        bool resolved;
        bool successful;            // true if challenge succeeded
    }

    struct ReputationScore {
        uint256 subjectId;
        address subject;
        uint256 rawScore;           // Sum of raw scores
        uint256 weightedScore;      // After stake weighting
        uint256 diversityBonus;     // Bonus for diverse reviewers
        uint256 attestationBonus;   // Bonus for verified attestations
        uint256 timeDecay;          // Decay factor for old reviews
        uint256 finalScore;         // Final reputation score
        uint256 reviewCount;
        uint256 lastUpdated;
    }

    // ============ Reviews ============

    function submitReview(
        uint256 subjectId,
        int8 score,
        uint256 stake,
        string calldata evidence
    ) external payable returns (uint256 reviewId);

    function attestReview(uint256 reviewId, bool isValid) external;

    function challengeReview(
        uint256 reviewId,
        string calldata reason
    ) external payable returns (uint256 challengeId);

    function resolveChallenge(uint256 challengeId, bool upholdChallenge) external;

    // ============ View Functions ============

    function getReview(uint256 reviewId)
        external
        view
        returns (Review memory);

    function getSubjectReviews(uint256 subjectId, uint256 offset, uint256 limit)
        external
        view
        returns (Review[] memory);

    function getReputation(uint256 subjectId)
        external
        view
        returns (ReputationScore memory);

    function calculateReputation(uint256 subjectId)
        external
        view
        returns (uint256);

    function canAttest(address attester, uint256 reviewId)
        external
        view
        returns (bool);

    function getAttestations(uint256 reviewId)
        external
        view
        returns (Attestation[] memory);

    function getChallenge(uint256 challengeId)
        external
        view
        returns (Challenge memory);

    // ============ Reputation Weights ============

    function getStakeWeight(uint256 stake)
        external
        view
        returns (uint256);

    function getDiversityBonus(address reviewer, uint256 subjectId)
        external
        view
        returns (uint256);

    function getTimeDecay(uint256 reviewTimestamp)
        external
        view
        returns (uint256);

    // ============ Events ============

    event ReviewSubmitted(
        uint256 indexed reviewId,
        uint256 indexed subjectId,
        address indexed reviewer,
        int8 score,
        uint256 stake
    );

    event ReviewAttested(
        uint256 indexed reviewId,
        address indexed attester,
        bool isValid
    );

    event ReviewChallenged(
        uint256 indexed reviewId,
        uint256 indexed challengeId,
        address indexed challenger,
        string reason
    );

    event ChallengeResolved(
        uint256 indexed challengeId,
        bool successful,
        uint256 penalty
    );

    event ReputationUpdated(
        uint256 indexed subjectId,
        uint256 oldScore,
        uint256 newScore
    );
}
