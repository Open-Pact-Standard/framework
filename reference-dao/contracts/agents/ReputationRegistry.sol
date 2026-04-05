// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IReputationRegistry.sol";

/**
 * @title ReputationRegistry
 * @dev Reputation tracking for agents per EIP-8004 specification.
 *      Allows submission of reviews/scores for agents with cooldown.
 */
contract ReputationRegistry is IReputationRegistry, Ownable {
    /// @notice Minimum score value
    int256 public constant MIN_SCORE = -10;

    /// @notice Maximum score value
    int256 public constant MAX_SCORE = 10;

    /// @notice Cooldown period between reviews (1 day in seconds)
    uint256 public constant COOLDOWN_PERIOD = 1 days;

    error InvalidAgentId();
    error ScoreOutOfRange();
    error EmptyReview();
    error CooldownActive();
    error InvalidIndex();

    /// @notice Structure to store review data
    struct Review {
        int256 score;
        string reviewText;
        uint256 timestamp;
    }

    /// @notice Mapping from agent ID to array of reviews
    mapping(uint256 => Review[]) private _agentReviews;
    
    /// @notice Mapping from agent ID to total score (sum of all scores)
    mapping(uint256 => int256) private _totalScores;
    
    /// @notice Mapping from agent ID to review count
    mapping(uint256 => uint256) private _reviewCounts;
    
    /// @notice Mapping from (agentId, reviewer) to last review timestamp
    mapping(uint256 => mapping(address => uint256)) private _lastReviewTime;

    constructor() Ownable() {}

    /**
     * @notice Submit a review for an agent
     * @param agentId The ID of the agent being reviewed
     * @param score The score from -10 to +10
     * @param review The review text or IPFS URI
     */
    function submitReview(uint256 agentId, int256 score, string memory review) external override {
        if (agentId == 0) revert InvalidAgentId();
        if (score < MIN_SCORE || score > MAX_SCORE) revert ScoreOutOfRange();
        if (bytes(review).length == 0) revert EmptyReview();
        
        // Check cooldown - one review per reviewer per agent per day
        uint256 lastReview = _lastReviewTime[agentId][msg.sender];
        if (lastReview > 0 && block.timestamp < lastReview + COOLDOWN_PERIOD) {
            revert CooldownActive();
        }
        
        // Add review to storage
        _agentReviews[agentId].push(Review({
            score: score,
            reviewText: review,
            timestamp: block.timestamp
        }));
        
        // Update totals
        _totalScores[agentId] += score;
        _reviewCounts[agentId]++;
        
        // Update last review time
        _lastReviewTime[agentId][msg.sender] = block.timestamp;
        
        // Calculate new average
        int256 newAverage = _totalScores[agentId] / int256(_reviewCounts[agentId]);
        
        emit ReviewSubmitted(agentId, msg.sender, score, review);
        emit ReputationUpdated(agentId, newAverage, _reviewCounts[agentId]);
    }

    /**
     * @notice Get the reputation score for an agent
     * @param agentId The agent ID to query
     * @return The weighted average reputation score (can be negative)
     */
    function getReputation(uint256 agentId) external view override returns (int256) {
        if (_reviewCounts[agentId] == 0) {
            return 0;
        }
        return _totalScores[agentId] / int256(_reviewCounts[agentId]);
    }

    /**
     * @notice Get the total score sum for an agent
     * @param agentId The agent ID to query
     * @return The sum of all scores
     */
    function getTotalScore(uint256 agentId) external view returns (int256) {
        return _totalScores[agentId];
    }

    /**
     * @notice Get the number of reviews for an agent
     * @param agentId The agent ID to query
     * @return The total number of reviews
     */
    function getReviewCount(uint256 agentId) external view override returns (uint256) {
        return _reviewCounts[agentId];
    }

    /**
     * @notice Get the last review timestamp for an agent by a reviewer
     * @param agentId The agent ID
     * @param reviewer The reviewer's address
     * @return The timestamp of the last review, or 0 if never reviewed
     */
    function getLastReviewTime(uint256 agentId, address reviewer) external view override returns (uint256) {
        return _lastReviewTime[agentId][reviewer];
    }

    /**
     * @notice Check if a reviewer can submit a review (cooldown expired)
     * @param agentId The agent ID
     * @param reviewer The reviewer's address
     * @return True if cooldown has expired
     */
    function canReview(uint256 agentId, address reviewer) external view returns (bool) {
        uint256 lastReview = _lastReviewTime[agentId][reviewer];
        return lastReview == 0 || block.timestamp >= lastReview + COOLDOWN_PERIOD;
    }

    /**
     * @notice Get a specific review for an agent
     * @param agentId The agent ID
     * @param index The review index
     * @return score, reviewText, timestamp
     */
    function getReview(uint256 agentId, uint256 index) external view returns (int256, string memory, uint256) {
        if (index >= _reviewCounts[agentId]) revert InvalidIndex();
        Review memory review = _agentReviews[agentId][index];
        return (review.score, review.reviewText, review.timestamp);
    }
}
