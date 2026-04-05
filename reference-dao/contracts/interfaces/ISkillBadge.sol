// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/**
 * @title ISkillBadge
 * @dev Interface for skill badge verification system using ERC-1155
 *      Each skill ID represents a different skill (e.g., 1 = Solidity, 2 = Rust)
 *      Agents can hold multiple badges, and each badge has a verification level
 */
interface ISkillBadge is IERC1155 {
    /**
     * @dev Skill verification levels
     */
    enum VerificationLevel {
        None,       // 0 - No verification
        Self,       // 1 - Self-claimed
        Peer,       // 2 - Peer-reviewed
        Verified,   // 3 - Validator-verified
        Master      // 4 - Master-level (proven track record)
    }

    /**
     * @dev Skill metadata
     */
    struct Skill {
        string name;           // e.g., "Solidity Development"
        string category;       // e.g., "Blockchain", "AI", "Design"
        bool active;           // Whether the skill is currently active
        uint256 created;       // Timestamp when skill was created
    }

    /**
     * @dev Agent skill data
     */
    struct AgentSkill {
        uint256 skillId;
        VerificationLevel level;
        uint256 endorsedCount;     // Number of peers who endorsed
        uint256 completedBounties; // Bounties completed with this skill
        uint256 lastUpdated;
    }

    // Errors
    error ZeroAddress();
    error InvalidSkillId();
    error InvalidLevel();
    error SkillAlreadyExists();
    error NotAuthorized();
    error CannotEndorseSelf();
    error AlreadyEndorsed();
    error InvalidAgent();

    /**
     * @notice Register a new skill type (admin only)
     * @param name The skill name
     * @param category The skill category
     * @return skillId The new skill ID
     */
    function registerSkill(string calldata name, string calldata category) external returns (uint256);

    /**
     * @notice Claim a skill for oneself (VerificationLevel.Self)
     * @param skillId The skill to claim
     */
    function claimSkill(uint256 skillId) external;

    /**
     * @notice Endorse another agent's skill (increases level to Peer)
     * @param agentId The agent to endorse
     * @param skillId The skill to endorse
     */
    function endorseSkill(uint256 agentId, uint256 skillId) external;

    /**
     * @notice Verify an agent's skill (validator only, increases to Verified)
     * @param agentId The agent to verify
     * @param skillId The skill to verify
     * @param level The verification level to assign
     */
    function verifySkill(uint256 agentId, uint256 skillId, VerificationLevel level) external;

    /**
     * @notice Record bounty completion with a skill
     * @param agentId The agent who completed the bounty
     * @param skillId The skill used
     */
    function recordBountyCompletion(uint256 agentId, uint256 skillId) external;

    /**
     * @notice Get an agent's skill data
     * @param agentId The agent ID
     * @param skillId The skill ID
     * @return skill The agent's skill data
     */
    function getAgentSkill(uint256 agentId, uint256 skillId) external view returns (AgentSkill memory);

    /**
     * @notice Get all skills for an agent
     * @param agentId The agent ID
     * @return skillIds Array of skill IDs the agent has
     */
    function getAgentSkills(uint256 agentId) external view returns (uint256[] memory);

    /**
     * @notice Get skill metadata
     * @param skillId The skill ID
     * @return skill The skill metadata
     */
    function getSkill(uint256 skillId) external view returns (Skill memory);

    /**
     * @notice Get all active skill IDs
     * @return skillIds Array of active skill IDs
     */
    function getActiveSkills() external view returns (uint256[] memory);

    /**
     * @notice Get agents by skill and minimum level
     * @param skillId The skill ID
     * @param minLevel The minimum verification level
     * @return agentIds Array of agent IDs meeting the criteria
     */
    function getAgentsBySkill(uint256 skillId, VerificationLevel minLevel) external view returns (uint256[] memory);

    /**
     * @notice Check if an agent has a skill at minimum level
     * @param agentId The agent ID
     * @param skillId The skill ID
     * @param minLevel The minimum level required
     * @return True if agent has skill at or above the level
     */
    function hasSkillLevel(uint256 agentId, uint256 skillId, VerificationLevel minLevel) external view returns (bool);

    // Events
    event SkillRegistered(uint256 indexed skillId, string name, string category);
    event SkillClaimed(uint256 indexed agentId, uint256 indexed skillId);
    event SkillEndorsed(uint256 indexed agentId, uint256 indexed skillId, address indexed endorser);
    event SkillVerified(uint256 indexed agentId, uint256 indexed skillId, VerificationLevel level, address indexed validator);
    event BountyRecorded(uint256 indexed agentId, uint256 indexed skillId);
    event SkillDeactivated(uint256 indexed skillId);
}
