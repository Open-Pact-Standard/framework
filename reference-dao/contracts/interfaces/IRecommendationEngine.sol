// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

/**
 * @title IRecommendationEngine
 * @dev Interface for bounty-agent matchmaking and recommendations
 *      Uses scoring algorithms to match bounties with suitable agents
 */
interface IRecommendationEngine {
    /**
     * @dev Bounty requirements for matching
     */
    struct BountyRequirements {
        uint256 bountyId;           // Marketplace listing ID
        string title;               // Bounty title for keyword matching
        string description;         // Description for keyword matching
        uint256[] requiredSkills;   // Required skill IDs
        uint256[] minLevels;        // Minimum levels for each skill
        uint256 budget;             // Budget tier
        uint256 deadline;           // Deadline timestamp
        bool isActive;              // Whether bounty is still open
    }

    /**
     * @dev Match result with score
     */
    struct MatchResult {
        uint256 agentId;
        uint256 score;              // Match score (0-10000)
        uint256 skillMatchScore;    // Skill compatibility score
        uint256 reputationScore;    // Reputation contribution
        uint256 availabilityScore;  // Availability prediction
        uint256 priceFitScore;      // Budget-price fit
    }

    /**
     * @dev Agent availability status
     */
    struct AgentAvailability {
        bool isAvailable;
        uint256 currentBounties;    // Currently active bounties
        uint256 capacity;           // Maximum concurrent bounties
        uint256 lastActive;         // Last activity timestamp
    }

    // Errors
    error InvalidBounty();
    error AgentNotFound();
    error BountyAlreadyAssigned();
    error InvalidCapacity();
    error AgentNotAvailable();
    error MismatchedArrays();

    /**
     * @notice Get recommendations for a bounty
     * @param requirements The bounty requirements
     * @param limit Maximum number of recommendations
     * @return matches Array of match results sorted by score
     */
    function getRecommendations(
        BountyRequirements calldata requirements,
        uint256 limit
    ) external view returns (MatchResult[] memory);

    /**
     * @notice Get recommended bounties for an agent
     * @param agentId The agent ID
     * @param bountyIds Available bounty IDs to consider
     * @param limit Maximum number of recommendations
     * @return bountyIds Array of recommended bounty IDs
     */
    function getRecommendedBounties(
        uint256 agentId,
        uint256[] calldata bountyIds,
        uint256 limit
    ) external view returns (uint256[] memory);

    /**
     * @notice Calculate match score for agent-bounty pair
     * @param agentId The agent ID
     * @param requirements The bounty requirements
     * @return score The match score (0-10000)
     */
    function calculateMatchScore(
        uint256 agentId,
        BountyRequirements calldata requirements
    ) external view returns (uint256 score);

    /**
     * @notice Set agent availability preferences
     * @param capacity Maximum concurrent bounties
     * @param isAvailable Current availability status
     */
    function setAvailability(uint256 capacity, bool isAvailable) external;

    /**
     * @notice Get agent availability status
     * @param agentId The agent ID
     * @return availability The agent's availability
     */
    function getAgentAvailability(uint256 agentId) external view returns (AgentAvailability memory);

    /**
     * @notice Record bounty assignment for availability tracking
     * @param agentId The agent taking the bounty
     * @param bountyId The bounty being taken
     */
    function recordBountyAssignment(uint256 agentId, uint256 bountyId) external;

    /**
     * @notice Record bounty completion for availability tracking
     * @param agentId The agent completing the bounty
     * @param bountyId The bounty being completed
     */
    function recordBountyCompletion(uint256 agentId, uint256 bountyId) external;

    /**
     * @notice Get match score breakdown
     * @param agentId The agent ID
     * @param requirements The bounty requirements
     * @return skillMatch Score from skill compatibility
     * @return reputation Score from reputation
     * @return availability Score from availability
     * @return priceFit Score from budget fit
     */
    function getScoreBreakdown(
        uint256 agentId,
        BountyRequirements calldata requirements
    ) external view returns (
        uint256 skillMatch,
        uint256 reputation,
        uint256 availability,
        uint256 priceFit
    );

    // Events
    event RecommendationsGenerated(uint256 indexed bountyId, uint256[] agentIds);
    event AvailabilitySet(uint256 indexed agentId, bool isAvailable, uint256 capacity);
    event BountyAssigned(uint256 indexed bountyId, uint256 indexed agentId);
    event BountyCompleted(uint256 indexed bountyId, uint256 indexed agentId);
}
