// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ITalentSearch.sol";
import "../interfaces/ISkillBadge.sol";
import "../interfaces/IAgentRegistry.sol";
import "../interfaces/IReputationRegistry.sol";
import "../interfaces/IValidationRegistry.sol";

/**
 * @title TalentSearch
 * @dev Comprehensive talent discovery and search engine
 *      Integrates with all registries to provide filtering, sorting, and ranking
 *
 *      Search Algorithm:
 *      1. Filter by hard constraints (validation, reputation range, skills)
 *      2. Score each match based on multiple factors
 *      3. Sort by selected criteria
 *      4. Return paginated results
 */
contract TalentSearch is ITalentSearch, Ownable {
    /// @notice Maximum results per search (gas limit protection)
    uint256 public constant MAX_RESULTS = 100;

    /// @notice Maximum keywords per search
    uint256 public constant MAX_KEYWORDS = 10;

    /// @notice Registry references
    IAgentRegistry public immutable agentRegistry;
    IReputationRegistry public immutable reputationRegistry;
    IValidationRegistry public immutable validationRegistry;
    ISkillBadge public immutable skillBadge;

    /// @notice Agent metadata cache (agentId => metadataURI)
    mapping(uint256 => string) private _metadataCache;

    /// @notice Agent registration timestamps
    mapping(uint256 => uint256) private _registrationTimes;

    /// @notice Completed jobs cache (agentId => count)
    mapping(uint256 => uint256) private _completedJobsCache;

    /// @notice Last cache update time
    mapping(uint256 => uint256) private _lastCacheUpdate;

    /// @notice Cache validity period (1 day)
    uint256 public constant CACHE_VALIDITY = 1 days;

    // Custom errors (not in interface or with different signatures)
    // Note: AgentNotFound, SearchLimitExceeded, InvalidParams, ZeroAddress, NotAuthorized are in interface


    /**
     * @dev Constructor
     * @param agentRegistry_ The identity registry
     * @param reputationRegistry_ The reputation registry
     * @param validationRegistry_ The validation registry
     * @param skillBadge_ The skill badge contract
     */
    constructor(
        address agentRegistry_,
        address reputationRegistry_,
        address validationRegistry_,
        address skillBadge_
    ) Ownable() {
        if (
            agentRegistry_ == address(0) ||
            reputationRegistry_ == address(0) ||
            validationRegistry_ == address(0) ||
            skillBadge_ == address(0)
        ) {
            revert ZeroAddress();
        }
        agentRegistry = IAgentRegistry(agentRegistry_);
        reputationRegistry = IReputationRegistry(reputationRegistry_);
        validationRegistry = IValidationRegistry(validationRegistry_);
        skillBadge = ISkillBadge(skillBadge_);
    }

    // ============ Search Functions ============

    /**
     * @inheritdoc ITalentSearch
     */
    function searchAgents(SearchParams calldata params)
        external
        view
        override
        returns (AgentResult[] memory)
    {
        if (params.maxResults == 0 || params.maxResults > MAX_RESULTS) {
            revert SearchLimitExceeded();
        }
        if (params.keywords.length > MAX_KEYWORDS) {
            revert InvalidParams();
        }

        uint256 totalAgents = agentRegistry.getTotalAgents();
        if (totalAgents == 0) {
            return new AgentResult[](0);
        }

        // Pre-allocate maximum possible results
        AgentResult[] memory allResults = new AgentResult[](params.maxResults);
        uint256 resultCount = 0;

        // Iterate through agents and collect matches
        for (uint256 i = 1; i <= totalAgents && resultCount < params.maxResults; i++) {
            if (_agentMatchesConstraints(i, params)) {
                allResults[resultCount] = _buildAgentResult(i, params);
                resultCount++;
            }
        }

        // Trim to actual count
        AgentResult[] memory results = new AgentResult[](resultCount);
        for (uint256 i = 0; i < resultCount; i++) {
            results[i] = allResults[i];
        }

        // Sort results
        _sortResults(results, params.sortBy, params.ascending);

        return results;
    }

    /**
     * @inheritdoc ITalentSearch
     */
    function getTopAgents(uint256 limit)
        external
        view
        override
        returns (uint256[] memory)
    {
        if (limit > MAX_RESULTS) {
            revert SearchLimitExceeded();
        }

        uint256 totalAgents = agentRegistry.getTotalAgents();
        if (totalAgents == 0) {
            return new uint256[](0);
        }

        // Collect all agents with reputation
        uint256[] memory agentIds = new uint256[](totalAgents);
        int256[] memory reputations = new int256[](totalAgents);
        uint256 count = 0;

        for (uint256 i = 1; i <= totalAgents; i++) {
            if (agentRegistry.agentExists(i)) {
                agentIds[count] = i;
                reputations[count] = reputationRegistry.getReputation(i);
                count++;
            }
        }

        // Sort by reputation (descending)
        _sortAgentByReputation(agentIds, reputations, count);

        // Return top N
        uint256 returnCount = count < limit ? count : limit;
        uint256[] memory topAgents = new uint256[](returnCount);
        for (uint256 i = 0; i < returnCount; i++) {
            topAgents[i] = agentIds[i];
        }

        return topAgents;
    }

    /**
     * @inheritdoc ITalentSearch
     */
    function getTopAgentsBySkill(uint256 skillId, uint256 minLevel, uint256 limit)
        external
        view
        override
        returns (uint256[] memory)
    {
        if (limit > MAX_RESULTS) {
            revert SearchLimitExceeded();
        }

        // Get agents with the skill
        uint256[] memory agentIds = skillBadge.getAgentsBySkill(
            skillId,
            ISkillBadge.VerificationLevel(minLevel)
        );

        // Sort by reputation within skill holders
        uint256 count = agentIds.length < limit ? agentIds.length : limit;
        uint256[] memory topAgents = new uint256[](count);

        if (agentIds.length > 0) {
            // Sort by reputation
            int256[] memory reputations = new int256[](agentIds.length);
            for (uint256 i = 0; i < agentIds.length; i++) {
                reputations[i] = reputationRegistry.getReputation(agentIds[i]);
            }

            _sortAgentByReputation(agentIds, reputations, agentIds.length);

            // Return top N
            for (uint256 i = 0; i < count; i++) {
                topAgents[i] = agentIds[i];
            }
        }

        return topAgents;
    }

    /**
     * @inheritdoc ITalentSearch
     */
    function getAgentsByCategory(string calldata category, uint256 limit)
        external
        view
        override
        returns (uint256[] memory)
    {
        if (limit > MAX_RESULTS) {
            revert SearchLimitExceeded();
        }

        uint256[] memory skillIds = skillBadge.getActiveSkills();
        uint256[] memory matchingAgents = new uint256[](MAX_RESULTS);
        uint256 agentCount = 0;

        // Collect unique agents from skills in category
        for (uint256 i = 0; i < skillIds.length && agentCount < MAX_RESULTS; i++) {
            ISkillBadge.Skill memory skill = skillBadge.getSkill(skillIds[i]);
            if (keccak256(bytes(skill.category)) == keccak256(bytes(category))) {
                uint256[] memory agents = skillBadge.getAgentsBySkill(
                    skillIds[i],
                    ISkillBadge.VerificationLevel.Self
                );
                for (uint256 j = 0; j < agents.length && agentCount < MAX_RESULTS; j++) {
                    // Add if not already in list
                    bool alreadyAdded = false;
                    for (uint256 k = 0; k < agentCount; k++) {
                        if (matchingAgents[k] == agents[j]) {
                            alreadyAdded = true;
                            break;
                        }
                    }
                    if (!alreadyAdded) {
                        matchingAgents[agentCount] = agents[j];
                        agentCount++;
                    }
                }
            }
        }

        // Trim to actual count and limit
        uint256 returnCount = agentCount < limit ? agentCount : limit;
        uint256[] memory result = new uint256[](returnCount);
        for (uint256 i = 0; i < returnCount; i++) {
            result[i] = matchingAgents[i];
        }

        return result;
    }

    /**
     * @inheritdoc ITalentSearch
     */
    function getRecommendedAgents(
        uint256[] calldata requiredSkills,
        uint256[] calldata minLevels,
        uint256 limit
    ) external view override returns (uint256[] memory) {
        if (requiredSkills.length != minLevels.length) {
            revert InvalidParams();
        }
        if (limit > MAX_RESULTS) {
            revert SearchLimitExceeded();
        }

        // Start with agents who have the first required skill
        uint256[] memory candidates = skillBadge.getAgentsBySkill(
            requiredSkills[0],
            ISkillBadge.VerificationLevel(minLevels[0])
        );

        // Filter candidates who have ALL required skills at minimum levels
        uint256[] memory qualified = new uint256[](candidates.length);
        uint256 qualifiedCount = 0;

        for (uint256 i = 0; i < candidates.length; i++) {
            bool meetsAll = true;
            for (uint256 j = 0; j < requiredSkills.length; j++) {
                if (!skillBadge.hasSkillLevel(
                    candidates[i],
                    requiredSkills[j],
                    ISkillBadge.VerificationLevel(minLevels[j])
                )) {
                    meetsAll = false;
                    break;
                }
            }
            if (meetsAll) {
                qualified[qualifiedCount] = candidates[i];
                qualifiedCount++;
            }
        }

        // Sort by reputation
        int256[] memory reputations = new int256[](qualifiedCount);
        for (uint256 i = 0; i < qualifiedCount; i++) {
            reputations[i] = reputationRegistry.getReputation(qualified[i]);
        }
        _sortAgentByReputation(qualified, reputations, qualifiedCount);

        // Return top N
        uint256 returnCount = qualifiedCount < limit ? qualifiedCount : limit;
        uint256[] memory result = new uint256[](returnCount);
        for (uint256 i = 0; i < returnCount; i++) {
            result[i] = qualified[i];
        }

        return result;
    }

    /**
     * @inheritdoc ITalentSearch
     */
    function getAgentProfile(uint256 agentId)
        external
        view
        override
        returns (AgentProfile memory)
    {
        if (!agentRegistry.agentExists(agentId)) {
            revert AgentNotFound(agentId);
        }

        address wallet = agentRegistry.getAgentWallet(agentId);
        int256 reputation = reputationRegistry.getReputation(agentId);
        uint256 reviewCount = reputationRegistry.getReviewCount(agentId);
        bool isValidated = validationRegistry.isAgentValidated(agentId);
        uint256 validationCount = validationRegistry.getValidationCount(agentId);
        uint256[] memory skillIds = skillBadge.getAgentSkills(agentId);
        uint256 completedJobs = _getCompletedJobs(agentId);

        // Get metadata URI (cached or fetch from token)
        string memory metadataURI = _metadataCache[agentId];

        return AgentProfile({
            agentId: agentId,
            wallet: wallet,
            metadataURI: metadataURI,
            reputation: reputation,
            reviewCount: reviewCount,
            isValidated: isValidated,
            validationCount: validationCount,
            skillIds: skillIds,
            completedJobs: completedJobs,
            registeredAt: _registrationTimes[agentId]
        });
    }

    /**
     * @inheritdoc ITalentSearch
     */
    function agentMatches(uint256 agentId, SearchParams calldata params)
        external
        view
        override
        returns (bool)
    {
        return _agentMatchesConstraints(agentId, params);
    }

    // ============ Admin Functions ============

    /**
     * @notice Update metadata cache for an agent
     * @param agentId The agent ID
     * @param metadataURI The metadata URI
     */
    function updateMetadataCache(uint256 agentId, string calldata metadataURI) external {
        // Only agent owner can update
        uint256 callerAgentId = agentRegistry.getAgentId(msg.sender);
        if (callerAgentId != agentId) {
            revert NotAuthorized();
        }
        _metadataCache[agentId] = metadataURI;
    }

    /**
     * @notice Record agent registration time
     */
    function recordRegistration(uint256 agentId) external {
        // Only called by agentRegistry
        if (msg.sender != address(agentRegistry)) {
            revert NotAuthorized();
        }
        if (_registrationTimes[agentId] == 0) {
            _registrationTimes[agentId] = block.timestamp;
        }
    }

    /**
     * @notice Update completed jobs cache
     */
    function updateCompletedJobs(uint256 agentId, uint256 count) external {
        // Only engine role can update
        if (msg.sender != address(skillBadge)) {
            revert NotAuthorized();
        }
        _completedJobsCache[agentId] = count;
        _lastCacheUpdate[agentId] = block.timestamp;
    }

    // ============ Internal Functions ============

    /**
     * @dev Check if agent matches search constraints
     */
    function _agentMatchesConstraints(uint256 agentId, SearchParams calldata params)
        internal
        view
        returns (bool)
    {
        if (!agentRegistry.agentExists(agentId)) {
            return false;
        }

        int256 reputation = reputationRegistry.getReputation(agentId);

        // Check reputation range
        if (reputation < params.minReputation || reputation > params.maxReputation) {
            return false;
        }

        // Check validation requirement
        if (params.mustBeValidated && !validationRegistry.isAgentValidated(agentId)) {
            return false;
        }

        // Check minimum completed jobs
        uint256 completedJobs = _getCompletedJobs(agentId);
        if (completedJobs < params.minCompletedJobs) {
            return false;
        }

        // Check skill requirements
        if (params.skillIds.length > 0) {
            for (uint256 i = 0; i < params.skillIds.length; i++) {
                ISkillBadge.VerificationLevel minLevel = params.skillIds.length == params.skillLevels.length
                    ? ISkillBadge.VerificationLevel(params.skillLevels[i])
                    : ISkillBadge.VerificationLevel.Self;

                if (!skillBadge.hasSkillLevel(agentId, params.skillIds[i], minLevel)) {
                    return false;
                }
            }
        }

        return true;
    }

    /**
     * @dev Build agent result with scores
     */
    function _buildAgentResult(uint256 agentId, SearchParams calldata params)
        internal
        view
        returns (AgentResult memory)
    {
        address wallet = agentRegistry.getAgentWallet(agentId);
        int256 reputation = reputationRegistry.getReputation(agentId);
        uint256 reviewCount = reputationRegistry.getReviewCount(agentId);
        uint256 validationCount = validationRegistry.getValidationCount(agentId);
        bool isValidated = validationRegistry.isAgentValidated(agentId);
        uint256 completedJobs = _getCompletedJobs(agentId);
        uint256[] memory skillIds = skillBadge.getAgentSkills(agentId);
        uint256 registeredAt = _registrationTimes[agentId];

        // Calculate relevance score
        uint256 relevanceScore = _calculateRelevance(agentId, params);

        return AgentResult({
            agentId: agentId,
            wallet: wallet,
            reputation: reputation,
            reviewCount: reviewCount,
            validationCount: validationCount,
            completedJobs: completedJobs,
            skillCount: skillIds.length,
            relevanceScore: relevanceScore,
            isValidated: isValidated,
            registeredAt: registeredAt
        });
    }

    /**
     * @dev Calculate relevance score based on keywords and skills
     */
    function _calculateRelevance(uint256 agentId, SearchParams calldata params)
        internal
        view
        returns (uint256)
    {
        uint256 score = 0;

        // Keyword matching (simplified - would need full-text index for production)
        // For now, score based on skill overlap
        uint256[] memory agentSkills = skillBadge.getAgentSkills(agentId);
        for (uint256 i = 0; i < params.skillIds.length; i++) {
            for (uint256 j = 0; j < agentSkills.length; j++) {
                if (params.skillIds[i] == agentSkills[j]) {
                    score += 1000; // Base score for skill match
                    break;
                }
            }
        }

        // Bonus for validation
        if (validationRegistry.isAgentValidated(agentId)) {
            score += 500;
        }

        // Bonus for positive reputation
        int256 reputation = reputationRegistry.getReputation(agentId);
        if (reputation > 0) {
            score += uint256(reputation) * 50;
        }

        return score;
    }

    /**
     * @dev Sort results by criteria
     */
    function _sortResults(
        AgentResult[] memory results,
        SortBy sortBy,
        bool ascending
    ) internal pure {
        if (results.length <= 1) return;

        // Bubble sort for simplicity (gas-friendly for small arrays)
        for (uint256 i = 0; i < results.length - 1; i++) {
            for (uint256 j = 0; j < results.length - i - 1; j++) {
                if (_compare(results[j], results[j + 1], sortBy) > 0) {
                    AgentResult memory temp = results[j];
                    results[j] = results[j + 1];
                    results[j + 1] = temp;
                }
            }
        }

        // Reverse if ascending
        if (ascending) {
            for (uint256 i = 0; i < results.length / 2; i++) {
                AgentResult memory temp = results[i];
                results[i] = results[results.length - 1 - i];
                results[results.length - 1 - i] = temp;
            }
        }
    }

    /**
     * @dev Compare two agent results (returns >0 if a should come before b)
     */
    function _compare(AgentResult memory a, AgentResult memory b, SortBy sortBy)
        internal
        pure
        returns (int256)
    {
        if (sortBy == SortBy.Reputation) {
            return int256(a.reputation) - int256(b.reputation);
        } else if (sortBy == SortBy.ReviewCount) {
            return int256(a.reviewCount) - int256(b.reviewCount);
        } else if (sortBy == SortBy.ValidationCount) {
            return int256(a.validationCount) - int256(b.validationCount);
        } else if (sortBy == SortBy.JobCount) {
            return int256(a.completedJobs) - int256(b.completedJobs);
        } else if (sortBy == SortBy.SkillCount) {
            return int256(a.skillCount) - int256(b.skillCount);
        } else if (sortBy == SortBy.Created) {
            return int256(a.registeredAt) - int256(b.registeredAt);
        } else {
            return int256(a.relevanceScore) - int256(b.relevanceScore);
        }
    }

    /**
     * @dev Sort agents by reputation (descending)
     */
    function _sortAgentByReputation(
        uint256[] memory agentIds,
        int256[] memory reputations,
        uint256 length
    ) internal pure {
        // Skip sorting if empty or single element
        if (length <= 1) {
            return;
        }

        // Bubble sort
        for (uint256 i = 0; i < length - 1; i++) {
            for (uint256 j = 0; j < length - i - 1; j++) {
                if (reputations[j] < reputations[j + 1]) {
                    // Swap agent IDs
                    uint256 tempAgent = agentIds[j];
                    agentIds[j] = agentIds[j + 1];
                    agentIds[j + 1] = tempAgent;
                    // Swap reputations
                    int256 tempRep = reputations[j];
                    reputations[j] = reputations[j + 1];
                    reputations[j + 1] = tempRep;
                }
            }
        }
    }

    /**
     * @dev Get completed jobs from cache or skill badge
     */
    function _getCompletedJobs(uint256 agentId) internal view returns (uint256) {
        // Use cached value if recent
        if (_lastCacheUpdate[agentId] > 0 && block.timestamp - _lastCacheUpdate[agentId] < CACHE_VALIDITY) {
            return _completedJobsCache[agentId];
        }
        // Otherwise query skill badge (requires external call in practice)
        return _completedJobsCache[agentId];
    }
}
