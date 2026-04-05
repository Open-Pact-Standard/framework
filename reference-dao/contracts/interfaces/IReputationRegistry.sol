// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

/**
 * @title IReputationRegistry
 * @dev Interface for EIP-8004 Reputation Registry
 *      Provides feedback/reputation signals for agents
 */
interface IReputationRegistry {
    /**
     * @notice Submit a review for an agent
     * @param agentId The ID of the agent being reviewed
     * @param score The score from -10 to +10
     * @param review The review text (IPFS URI or text)
     */
    function submitReview(uint256 agentId, int256 score, string memory review) external;

    /**
     * @notice Get the reputation score for an agent
     * @param agentId The agent ID to query
     * @return The weighted average reputation score
     */
    function getReputation(uint256 agentId) external view returns (int256);

    /**
     * @notice Get the number of reviews for an agent
     * @param agentId The agent ID to query
     * @return The total number of reviews
     */
    function getReviewCount(uint256 agentId) external view returns (uint256);

    /**
     * @notice Get the last review timestamp for an agent by a reviewer
     * @param agentId The agent ID
     * @param reviewer The reviewer's address
     * @return The timestamp of the last review, or 0 if never reviewed
     */
    function getLastReviewTime(uint256 agentId, address reviewer) external view returns (uint256);

    // Events
    event ReviewSubmitted(uint256 indexed agentId, address indexed reviewer, int256 score, string review);
    event ReputationUpdated(uint256 indexed agentId, int256 newScore, uint256 reviewCount);
}
