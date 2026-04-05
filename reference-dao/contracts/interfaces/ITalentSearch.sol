// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title ITalentSearch
 * @dev Interface for talent discovery and search functionality
 *      Provides filtering, sorting, and ranking of agents based on various criteria
 */
interface ITalentSearch {
    /**
     * @dev Search parameters for filtering agents
     */
    struct SearchParams {
        string[] keywords;           // Keyword search in metadata
        uint256[] skillIds;          // Required skills
        uint256[] skillLevels;       // Minimum levels for each skill (0 = any)
        int256 minReputation;        // Minimum reputation score
        int256 maxReputation;        // Maximum reputation score
        bool mustBeValidated;        // Must pass validation registry
        uint256 minCompletedJobs;    // Minimum completed jobs/bounties
        uint256 maxResults;          // Maximum results to return
        SortBy sortBy;               // Sorting criteria
        bool ascending;              // Sort order
    }

    /**
     * @dev Sorting criteria for search results
     */
    enum SortBy {
        Reputation,      // Sort by reputation score
        ReviewCount,     // Sort by number of reviews
        ValidationCount, // Sort by validation count
        JobCount,        // Sort by completed jobs
        SkillCount,      // Sort by number of skills
        Created,         // Sort by registration date
        Relevance        // Sort by keyword relevance
    }

    /**
     * @dev Agent search result with ranking data
     */
    struct AgentResult {
        uint256 agentId;
        address wallet;
        int256 reputation;
        uint256 reviewCount;
        uint256 validationCount;
        uint256 completedJobs;
        uint256 skillCount;
        uint256 relevanceScore;     // For keyword/skill matching
        bool isValidated;
        uint256 registeredAt;
    }

    /**
     * @dev Agent profile summary
     */
    struct AgentProfile {
        uint256 agentId;
        address wallet;
        string metadataURI;
        int256 reputation;
        uint256 reviewCount;
        bool isValidated;
        uint256 validationCount;
        uint256[] skillIds;
        uint256 completedJobs;
        uint256 registeredAt;
    }

    // Errors
    error ZeroAddress();
    error NotAuthorized();
    error InvalidParams();
    error AgentNotFound(uint256 agentId);
    error TooManyResults();
    error SearchLimitExceeded();

    /**
     * @notice Search for agents based on criteria
     * @param params The search parameters
     * @return results Array of matching agents with rankings
     */
    function searchAgents(SearchParams calldata params) external view returns (AgentResult[] memory);

    /**
     * @notice Get top agents by reputation
     * @param limit Maximum number of results
     * @return agentIds Array of top agent IDs
     */
    function getTopAgents(uint256 limit) external view returns (uint256[] memory);

    /**
     * @notice Get top agents by skill
     * @param skillId The skill to filter by
     * @param minLevel Minimum verification level
     * @param limit Maximum number of results
     * @return agentIds Array of top agent IDs
     */
    function getTopAgentsBySkill(uint256 skillId, uint256 minLevel, uint256 limit) external view returns (uint256[] memory);

    /**
     * @notice Get agents by category
     * @param category The skill category
     * @param limit Maximum number of results
     * @return agentIds Array of agent IDs
     */
    function getAgentsByCategory(string calldata category, uint256 limit) external view returns (uint256[] memory);

    /**
     * @notice Get recommended agents for a bounty
     * @param requiredSkills Skills required for the bounty
     * @param minLevels Minimum levels for each skill
     * @param limit Maximum number of recommendations
     * @return agentIds Array of recommended agent IDs
     */
    function getRecommendedAgents(
        uint256[] calldata requiredSkills,
        uint256[] calldata minLevels,
        uint256 limit
    ) external view returns (uint256[] memory);

    /**
     * @notice Get detailed agent profile
     * @param agentId The agent ID
     * @return profile The agent's profile
     */
    function getAgentProfile(uint256 agentId) external view returns (AgentProfile memory);

    /**
     * @notice Check if an agent matches given criteria
     * @param agentId The agent ID
     * @param params The search parameters to check against
     * @return True if agent matches all criteria
     */
    function agentMatches(uint256 agentId, SearchParams calldata params) external view returns (bool);

    // Events
    event AgentSearched(address indexed searcher, uint256 resultCount);
    event RecommendationViewed(uint256 indexed bountyId, uint256[] agentIds);
}
