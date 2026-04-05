// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/IRecommendationEngine.sol";
import "../interfaces/ISkillBadge.sol";
import "../interfaces/IAgentRegistry.sol";
import "../interfaces/IReputationRegistry.sol";

/**
 * @title RecommendationEngine
 * @dev Advanced matchmaking algorithm for bounty-agent pairing
 *
 *      Scoring Algorithm (0-10000):
 *      - Skill Match Score (0-4000): Based on skill overlap and level requirements
 *      - Reputation Score (0-2500): Based on reputation score percentile
 *      - Availability Score (0-2000): Based on current capacity and activity
 *      - Price Fit Score (0-1500): Based on budget alignment
 *
 *      The engine uses a weighted sum to rank agents for each bounty.
 */
contract RecommendationEngine is IRecommendationEngine, Ownable, AccessControl {
    /// @notice Role for marketplace to call bounty assignment/completion
    bytes32 public constant MARKETPLACE_ROLE = keccak256("MARKETPLACE_ROLE");

    /// @notice Maximum concurrent bounties per agent default
    uint256 public constant DEFAULT_CAPACITY = 3;

    /// @notice Inactivity threshold (30 days)
    uint256 public constant INACTIVITY_THRESHOLD = 30 days;

    /// @notice Registry references
    IAgentRegistry public immutable agentRegistry;
    IReputationRegistry public immutable reputationRegistry;
    ISkillBadge public immutable skillBadge;

    /// @notice Agent availability settings
    mapping(uint256 => AgentAvailability) private _availability;

    /// @notice Agent's current active bounties
    mapping(uint256 => uint256[]) private _activeBounties;

    /// @notice Bounty => Assigned agent (if any)
    mapping(uint256 => uint256) private _bountyAgents;

    /// @notice Agent => Bounty completion count
    mapping(uint256 => uint256) private _completionCount;

    /// @notice Score weights (sum to 10000)
    uint256 public weightSkillMatch = 4000;  // 40%
    uint256 public weightReputation = 2500;  // 25%
    uint256 public weightAvailability = 2000; // 20%
    uint256 public weightPriceFit = 1500;    // 15%

    /// @notice Maximum results per recommendation
    uint256 public maxRecommendations = 20;

    // Custom errors (not in interface)
    error ZeroAddress();
    error InvalidParams();

    /**
     * @dev Constructor
     */
    constructor(
        address agentRegistry_,
        address reputationRegistry_,
        address skillBadge_
    ) Ownable() {
        if (
            agentRegistry_ == address(0) ||
            reputationRegistry_ == address(0) ||
            skillBadge_ == address(0)
        ) {
            revert ZeroAddress();
        }
        agentRegistry = IAgentRegistry(agentRegistry_);
        reputationRegistry = IReputationRegistry(reputationRegistry_);
        skillBadge = ISkillBadge(skillBadge_);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(MARKETPLACE_ROLE, msg.sender);
    }

    // ============ Recommendation Functions ============

    /**
     * @inheritdoc IRecommendationEngine
     */
    function getRecommendations(
        BountyRequirements calldata requirements,
        uint256 limit
    ) external view override returns (MatchResult[] memory) {
        if (limit == 0 || limit > maxRecommendations) {
            limit = maxRecommendations;
        }

        // Get candidates with required skills
        uint256[] memory candidates = _getSkillQualifiedCandidates(
            requirements.requiredSkills,
            requirements.minLevels
        );

        if (candidates.length == 0) {
            return new MatchResult[](0);
        }

        // Score each candidate
        MatchResult[] memory results = new MatchResult[](candidates.length);
        uint256 validCount = 0;

        for (uint256 i = 0; i < candidates.length; i++) {
            uint256 agentId = candidates[i];

            // Skip if unavailable or at capacity
            if (!_isAvailable(agentId)) {
                continue;
            }

            // Calculate match score
            (
                uint256 skillMatchScore,
                uint256 reputationScore,
                uint256 availabilityScore,
                uint256 priceFitScore
            ) = _calculateScoreBreakdown(agentId, requirements);

            uint256 totalScore =
                (skillMatchScore * weightSkillMatch / 10000) +
                (reputationScore * weightReputation / 10000) +
                (availabilityScore * weightAvailability / 10000) +
                (priceFitScore * weightPriceFit / 10000);

            results[validCount] = MatchResult({
                agentId: agentId,
                score: totalScore,
                skillMatchScore: skillMatchScore,
                reputationScore: reputationScore,
                availabilityScore: availabilityScore,
                priceFitScore: priceFitScore
            });

            validCount++;
        }

        // Trim to valid count
        MatchResult[] memory validResults = new MatchResult[](validCount);
        for (uint256 i = 0; i < validCount; i++) {
            validResults[i] = results[i];
        }

        // Sort by score (descending)
        _sortMatchResults(validResults);

        // Return top N
        uint256 returnCount = validCount < limit ? validCount : limit;
        MatchResult[] memory topResults = new MatchResult[](returnCount);
        for (uint256 i = 0; i < returnCount; i++) {
            topResults[i] = validResults[i];
        }

        return topResults;
    }

    /**
     * @inheritdoc IRecommendationEngine
     */
    function getRecommendedBounties(
        uint256 agentId,
        uint256[] calldata bountyIds,
        uint256 limit
    ) external view override returns (uint256[] memory) {
        if (!agentRegistry.agentExists(agentId)) {
            revert AgentNotFound();
        }
        if (limit == 0 || limit > maxRecommendations) {
            limit = maxRecommendations;
        }

        // Score each bounty for this agent
        uint256[] memory scores = new uint256[](bountyIds.length);
        uint256 validCount = 0;

        for (uint256 i = 0; i < bountyIds.length; i++) {
            uint256 score = _calculateAgentBountyScore(agentId, bountyIds[i]);
            if (score > 0) {
                scores[validCount] = score;
                validCount++;
            }
        }

        // Sort by score
        _sortBountiesByScore(bountyIds, scores, bountyIds.length);

        // Return top N
        uint256 returnCount = validCount < limit ? validCount : limit;
        uint256[] memory result = new uint256[](returnCount);
        for (uint256 i = 0; i < returnCount; i++) {
            result[i] = bountyIds[i];
        }

        return result;
    }

    /**
     * @inheritdoc IRecommendationEngine
     */
    function calculateMatchScore(
        uint256 agentId,
        BountyRequirements calldata requirements
    ) external view override returns (uint256) {
        if (!agentRegistry.agentExists(agentId)) {
            return 0;
        }

        (
            uint256 skillMatchScore,
            uint256 reputationScore,
            uint256 availabilityScore,
            uint256 priceFitScore
        ) = _calculateScoreBreakdown(agentId, requirements);

        return
            (skillMatchScore * weightSkillMatch / 10000) +
            (reputationScore * weightReputation / 10000) +
            (availabilityScore * weightAvailability / 10000) +
            (priceFitScore * weightPriceFit / 10000);
    }

    // ============ Availability Functions ============

    /**
     * @inheritdoc IRecommendationEngine
     */
    function setAvailability(uint256 capacity, bool isAvailable) external override {
        uint256 agentId = agentRegistry.getAgentId(msg.sender);
        if (agentId == 0) {
            revert AgentNotFound();
        }
        if (capacity == 0 || capacity > 10) {
            revert InvalidCapacity();
        }

        AgentAvailability storage avail = _availability[agentId];
        avail.capacity = capacity;
        avail.isAvailable = isAvailable;
        avail.lastActive = block.timestamp;

        emit AvailabilitySet(agentId, isAvailable, capacity);
    }

    /**
     * @inheritdoc IRecommendationEngine
     */
    function getAgentAvailability(uint256 agentId)
        external
        view
        override
        returns (AgentAvailability memory)
    {
        if (!agentRegistry.agentExists(agentId)) {
            revert AgentNotFound();
        }

        AgentAvailability memory avail = _availability[agentId];

        // Initialize if not set
        if (avail.capacity == 0) {
            avail.capacity = DEFAULT_CAPACITY;
            avail.isAvailable = true;
            avail.lastActive = block.timestamp;
        }

        avail.currentBounties = _activeBounties[agentId].length;

        return avail;
    }

    /**
     * @inheritdoc IRecommendationEngine
     */
    function recordBountyAssignment(uint256 agentId, uint256 bountyId)
        external
        override
        onlyRole(MARKETPLACE_ROLE)
    {
        if (!agentRegistry.agentExists(agentId)) {
            revert AgentNotFound();
        }
        if (_bountyAgents[bountyId] != 0) {
            revert BountyAlreadyAssigned();
        }

        // Add to agent's active bounties
        _activeBounties[agentId].push(bountyId);
        _bountyAgents[bountyId] = agentId;

        // Update last active
        _availability[agentId].lastActive = block.timestamp;

        emit BountyAssigned(bountyId, agentId);
    }

    /**
     * @inheritdoc IRecommendationEngine
     */
    function recordBountyCompletion(uint256 agentId, uint256 bountyId)
        external
        override
        onlyRole(MARKETPLACE_ROLE)
    {
        if (!agentRegistry.agentExists(agentId)) {
            revert AgentNotFound();
        }
        if (_bountyAgents[bountyId] != agentId) {
            revert InvalidBounty();
        }

        // Remove from active bounties
        uint256[] storage activeBounties = _activeBounties[agentId];
        for (uint256 i = 0; i < activeBounties.length; i++) {
            if (activeBounties[i] == bountyId) {
                activeBounties[i] = activeBounties[activeBounties.length - 1];
                activeBounties.pop();
                break;
            }
        }

        // Clear bounty assignment
        _bountyAgents[bountyId] = 0;

        // Increment completion count
        _completionCount[agentId]++;

        emit BountyCompleted(bountyId, agentId);
    }

    /**
     * @inheritdoc IRecommendationEngine
     */
    function getScoreBreakdown(
        uint256 agentId,
        BountyRequirements calldata requirements
    ) external view override returns (
        uint256 skillMatch,
        uint256 reputation,
        uint256 availability,
        uint256 priceFit
    ) {
        return _calculateScoreBreakdown(agentId, requirements);
    }

    // ============ Admin Functions ============

    /**
     * @notice Update scoring weights
     */
    function setWeights(
        uint256 skillMatch,
        uint256 reputation,
        uint256 availability,
        uint256 priceFit
    ) external onlyOwner {
        uint256 total = skillMatch + reputation + availability + priceFit;
        if (total != 10000) {
            revert InvalidParams();
        }
        weightSkillMatch = skillMatch;
        weightReputation = reputation;
        weightAvailability = availability;
        weightPriceFit = priceFit;
    }

    /**
     * @notice Set maximum recommendations
     */
    function setMaxRecommendations(uint256 maxRec) external onlyOwner {
        if (maxRec == 0 || maxRec > 100) {
            revert InvalidParams();
        }
        maxRecommendations = maxRec;
    }

    /**
     * @notice Grant marketplace role
     */
    function grantMarketplaceRole(address marketplace) external onlyOwner {
        _grantRole(MARKETPLACE_ROLE, marketplace);
    }

    // ============ View Functions ============

    /**
     * @notice Get agent's active bounties
     */
    function getActiveBounties(uint256 agentId) external view returns (uint256[] memory) {
        return _activeBounties[agentId];
    }

    /**
     * @notice Get agent assigned to a bounty
     */
    function getBountyAgent(uint256 bountyId) external view returns (uint256) {
        return _bountyAgents[bountyId];
    }

    /**
     * @notice Get agent's completion count
     */
    function getCompletionCount(uint256 agentId) external view returns (uint256) {
        return _completionCount[agentId];
    }

    // ============ Internal Functions ============

    /**
     * @dev Get candidates who meet skill requirements
     */
    function _getSkillQualifiedCandidates(
        uint256[] memory requiredSkills,
        uint256[] memory minLevels
    ) internal view returns (uint256[] memory) {
        if (requiredSkills.length == 0) {
            // Return all agents if no skill requirements
            uint256 totalAgents = agentRegistry.getTotalAgents();
            uint256[] memory allAgents = new uint256[](totalAgents);
            for (uint256 i = 0; i < totalAgents; i++) {
                allAgents[i] = i + 1;
            }
            return allAgents;
        }

        // Start with agents who have first skill
        uint256[] memory candidates = skillBadge.getAgentsBySkill(
            requiredSkills[0],
            ISkillBadge.VerificationLevel(minLevels[0])
        );

        // Filter for remaining skills
        uint256 validCount = 0;
        for (uint256 i = 0; i < candidates.length; i++) {
            bool hasAllSkills = true;
            for (uint256 j = 1; j < requiredSkills.length; j++) {
                if (!skillBadge.hasSkillLevel(
                    candidates[i],
                    requiredSkills[j],
                    ISkillBadge.VerificationLevel(minLevels[j])
                )) {
                    hasAllSkills = false;
                    break;
                }
            }
            if (hasAllSkills) {
                candidates[validCount] = candidates[i];
                validCount++;
            }
        }

        // Trim to valid count
        uint256[] memory result = new uint256[](validCount);
        for (uint256 i = 0; i < validCount; i++) {
            result[i] = candidates[i];
        }

        return result;
    }

    /**
     * @dev Calculate score breakdown for agent-bounty pair
     */
    function _calculateScoreBreakdown(uint256 agentId, BountyRequirements calldata requirements)
        internal
        view
        returns (
            uint256 skillMatchScore,
            uint256 reputationScore,
            uint256 availabilityScore,
            uint256 priceFitScore
        )
    {
        // Skill Match Score (0-4000)
        skillMatchScore = _calculateSkillMatchScore(agentId, requirements);

        // Reputation Score (0-2500)
        reputationScore = _calculateReputationScore(agentId);

        // Availability Score (0-2000)
        availabilityScore = _calculateAvailabilityScore(agentId);

        // Price Fit Score (0-1500)
        priceFitScore = _calculatePriceFitScore(agentId, requirements.budget);
    }

    /**
     * @dev Calculate skill match score
     */
    function _calculateSkillMatchScore(uint256 agentId, BountyRequirements calldata requirements)
        internal
        view
        returns (uint256)
    {
        if (requirements.requiredSkills.length == 0) {
            return 2000; // Neutral score if no requirements
        }

        uint256 totalScore = 0;
        uint256 maxScore = 0;

        for (uint256 i = 0; i < requirements.requiredSkills.length; i++) {
            uint256 skillId = requirements.requiredSkills[i];
            uint256 minLevel = requirements.minLevels[i];

            // Get agent's skill level
            (, ISkillBadge.AgentSkill memory agentSkill) = _getAgentSkill(agentId, skillId);

            // Calculate score based on level
            uint256 skillScore;
            if (agentSkill.level == ISkillBadge.VerificationLevel.None) {
                skillScore = 0;
            } else if (uint256(agentSkill.level) < minLevel) {
                skillScore = 0;
            } else {
                // Bonus for exceeding minimum level
                uint256 levelBonus = (uint256(agentSkill.level) - minLevel) * 500;
                skillScore = 1000 + levelBonus; // Base 1000, up to 3000
                if (skillScore > 4000) skillScore = 4000;
            }

            totalScore += skillScore;
            maxScore += 4000;
        }

        return maxScore > 0 ? (totalScore * 4000) / maxScore : 0;
    }

    /**
     * @dev Calculate reputation score
     */
    function _calculateReputationScore(uint256 agentId) internal view returns (uint256) {
        int256 reputation = reputationRegistry.getReputation(agentId);

        // Normalize from [-10, 10] to [0, 2500]
        // -10 -> 0, 0 -> 1250, +10 -> 2500
        if (reputation <= -10) return 0;
        if (reputation >= 10) return 2500;

        return uint256(reputation + 10) * 125;
    }

    /**
     * @dev Calculate availability score
     */
    function _calculateAvailabilityScore(uint256 agentId) internal view returns (uint256) {
        AgentAvailability memory avail = _availability[agentId];

        // Initialize if not set
        if (avail.capacity == 0) {
            avail.capacity = DEFAULT_CAPACITY;
            avail.isAvailable = true;
            avail.lastActive = block.timestamp;
        }

        if (!avail.isAvailable) {
            return 0;
        }

        uint256 currentBounties = _activeBounties[agentId].length;
        uint256 utilization = (currentBounties * 100) / avail.capacity;

        // Higher score for lower utilization
        // 0% -> 2000, 100% -> 0
        uint256 score = 2000 - (utilization * 20);

        // Penalty for inactivity
        if (block.timestamp - avail.lastActive > INACTIVITY_THRESHOLD) {
            score = score / 2;
        }

        return score;
    }

    /**
     * @dev Calculate price fit score (simplified)
     */
    function _calculatePriceFitScore(uint256 agentId, uint256 budget) internal pure returns (uint256) {
        // In production, would use historical payment data
        // For now, return neutral score
        return 750;
    }

    /**
     * @dev Get agent's skill data
     */
    function _getAgentSkill(uint256 agentId, uint256 skillId)
        internal
        view
        returns (bool, ISkillBadge.AgentSkill memory)
    {
        // Try to get skill
        try skillBadge.getAgentSkill(agentId, skillId) returns (ISkillBadge.AgentSkill memory skill) {
            return (true, skill);
        } catch {
            return (false, ISkillBadge.AgentSkill(0, ISkillBadge.VerificationLevel.None, 0, 0, 0));
        }
    }

    /**
     * @dev Check if agent is available
     */
    function _isAvailable(uint256 agentId) internal view returns (bool) {
        AgentAvailability memory avail = _availability[agentId];

        if (avail.capacity == 0) {
            return true; // Default available
        }

        if (!avail.isAvailable) {
            return false;
        }

        return _activeBounties[agentId].length < avail.capacity;
    }

    /**
     * @dev Calculate agent's score for a bounty (reverse of calculateMatchScore)
     */
    function _calculateAgentBountyScore(uint256 agentId, uint256 bountyId) internal pure returns (uint256) {
        // Simplified - in production would fetch bounty requirements
        // For now, return a pseudo-score based on IDs for determinism
        return (agentId * 13 + bountyId * 7) % 5000;
    }

    /**
     * @dev Sort match results by score (descending)
     */
    function _sortMatchResults(MatchResult[] memory results) internal pure {
        // Skip sorting if empty or single element
        if (results.length <= 1) {
            return;
        }

        for (uint256 i = 0; i < results.length - 1; i++) {
            for (uint256 j = 0; j < results.length - i - 1; j++) {
                if (results[j].score < results[j + 1].score) {
                    MatchResult memory temp = results[j];
                    results[j] = results[j + 1];
                    results[j + 1] = temp;
                }
            }
        }
    }

    /**
     * @dev Sort bounties by score (descending)
     */
    function _sortBountiesByScore(
        uint256[] memory bountyIds,
        uint256[] memory scores,
        uint256 length
    ) internal pure {
        // Skip sorting if empty or single element
        if (length <= 1) {
            return;
        }

        for (uint256 i = 0; i < length - 1; i++) {
            for (uint256 j = 0; j < length - i - 1; j++) {
                if (scores[j] < scores[j + 1]) {
                    // Swap bounties
                    uint256 tempBounty = bountyIds[j];
                    bountyIds[j] = bountyIds[j + 1];
                    bountyIds[j + 1] = tempBounty;
                    // Swap scores
                    uint256 tempScore = scores[j];
                    scores[j] = scores[j + 1];
                    scores[j + 1] = tempScore;
                }
            }
        }
    }
}
