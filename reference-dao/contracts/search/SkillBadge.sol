// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "../interfaces/ISkillBadge.sol";
import "../interfaces/IAgentRegistry.sol";
import "../interfaces/IValidationRegistry.sol";

/**
 * @title SkillBadge
 * @dev ERC-1155 based skill verification and badge system
 *      Each token ID represents a different skill
 *      Token amounts represent verification levels (1=Self, 2=Peer, 3=Verified, 4=Master)
 *
 *      Skill ID mapping:
 *      - 1-999:   Blockchain/Development skills
 *      - 1000-1999: AI/ML skills
 *      - 2000-2999: Design/Creative skills
 *      - 3000-3999: Business/Operations skills
 *      - 4000-4999: Security/Audit skills
 *      - 5000+:   Custom/community skills
 */
contract SkillBadge is ISkillBadge, ERC1155, Ownable, AccessControl {
    using Counters for Counters.Counter;

    /// @notice Role for validators who can verify skills
    bytes32 public constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");

    /// @notice Role for recommendation engine to update bounty completions
    bytes32 public constant ENGINE_ROLE = keccak256("ENGINE_ROLE");

    /// @notice Skill ID counter
    Counters.Counter private _skillIdCounter;

    /// @notice Maximum agents per skill index (for gas efficiency)
    uint256 public constant MAX_AGENTS_PER_SKILL = 500;

    /// @notice Registry references
    IAgentRegistry public immutable agentRegistry;
    IValidationRegistry public immutable validationRegistry;

    /// @notice Skill ID => Skill metadata
    mapping(uint256 => Skill) private _skills;

    /// @notice Active skill IDs
    uint256[] private _activeSkills;

    /// @notice Agent ID => Skill IDs they possess
    mapping(uint256 => uint256[]) private _agentSkills;

    /// @notice (Agent ID, Skill ID) => AgentSkill data
    mapping(uint256 => mapping(uint256 => AgentSkill)) private _agentSkillData;

    /// @notice (Agent ID, Skill ID, Endorser) => Whether endorsement exists
    mapping(uint256 => mapping(uint256 => mapping(address => bool))) private _endorsements;

    /// @notice Skill ID => Array of agent IDs (for reverse lookup)
    mapping(uint256 => uint256[]) private _skillAgents;

    /// @notice (Skill ID, Agent Index) => Whether agent is still in array
    mapping(uint256 => mapping(uint256 => bool)) private _agentInSkillArray;

    /// @notice Agent ID => Index in _agentSkills for quick lookup
    mapping(uint256 => mapping(uint256 => uint256)) private _agentSkillIndex;

    /// @notice Agent ID => Total completed bounties (across all skills)
    mapping(uint256 => uint256) private _agentCompletedJobs;

    constructor(
        string memory uri,
        address agentRegistry_,
        address validationRegistry_
    ) ERC1155(uri) Ownable() {
        if (agentRegistry_ == address(0) || validationRegistry_ == address(0)) {
            revert ZeroAddress();
        }
        agentRegistry = IAgentRegistry(agentRegistry_);
        validationRegistry = IValidationRegistry(validationRegistry_);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VALIDATOR_ROLE, msg.sender);

        // Register default skills
        _registerDefaultSkills();
    }

    // ============ Admin Functions ============

    /**
     * @inheritdoc ISkillBadge
     */
    function registerSkill(string calldata name, string calldata category)
        external
        override
        onlyOwner
        returns (uint256)
    {
        _skillIdCounter.increment();
        uint256 skillId = _skillIdCounter.current();

        _skills[skillId] = Skill({
            name: name,
            category: category,
            active: true,
            created: block.timestamp
        });

        _activeSkills.push(skillId);

        emit SkillRegistered(skillId, name, category);
        return skillId;
    }

    /**
     * @notice Deactivate a skill (prevents new claims)
     * @param skillId The skill ID to deactivate
     */
    function deactivateSkill(uint256 skillId) external onlyOwner {
        if (!_skills[skillId].active) {
            revert InvalidSkillId();
        }
        _skills[skillId].active = false;
        emit SkillDeactivated(skillId);
    }

    /**
     * @notice Set the base URI for token metadata
     * @param uri The new base URI
     */
    function setURI(string calldata uri) external onlyOwner {
        _setURI(uri);
    }

    // ============ User Functions ============

    /**
     * @inheritdoc ISkillBadge
     */
    function claimSkill(uint256 skillId) external override {
        if (!_skills[skillId].active) {
            revert InvalidSkillId();
        }

        uint256 agentId = agentRegistry.getAgentId(msg.sender);
        if (agentId == 0) {
            revert InvalidAgent();
        }

        _addSkillToAgent(agentId, skillId, VerificationLevel.Self);
    }

    /**
     * @inheritdoc ISkillBadge
     */
    function endorseSkill(uint256 agentId, uint256 skillId) external override {
        if (!_skills[skillId].active) {
            revert InvalidSkillId();
        }
        if (agentId == agentRegistry.getAgentId(msg.sender)) {
            revert CannotEndorseSelf();
        }

        uint256 endorserAgentId = agentRegistry.getAgentId(msg.sender);
        if (endorserAgentId == 0) {
            revert InvalidAgent();
        }

        // Check if endorser has the skill (at least Self level)
        if (_agentSkillData[endorserAgentId][skillId].level == VerificationLevel.None) {
            revert NotAuthorized();
        }

        // Check if already endorsed
        if (_endorsements[agentId][skillId][msg.sender]) {
            revert AlreadyEndorsed();
        }

        // Record endorsement
        _endorsements[agentId][skillId][msg.sender] = true;

        // Get or create agent skill
        AgentSkill storage agentSkill = _agentSkillData[agentId][skillId];

        if (agentSkill.level == VerificationLevel.None) {
            // First claim/add
            _addSkillToAgent(agentId, skillId, VerificationLevel.Self);
        } else {
            // Update existing
            agentSkill.endorsedCount++;
            agentSkill.lastUpdated = block.timestamp;

            // Upgrade to Peer if enough endorsements (3+)
            if (agentSkill.endorsedCount >= 3 && agentSkill.level < VerificationLevel.Peer) {
                agentSkill.level = VerificationLevel.Peer;
                _mintAgentToken(agentId, skillId, uint256(VerificationLevel.Peer));
            }
        }

        emit SkillEndorsed(agentId, skillId, msg.sender);
    }

    /**
     * @inheritdoc ISkillBadge
     */
    function verifySkill(
        uint256 agentId,
        uint256 skillId,
        VerificationLevel level
    ) external override onlyRole(VALIDATOR_ROLE) {
        if (!_skills[skillId].active) {
            revert InvalidSkillId();
        }
        if (level < VerificationLevel.Verified) {
            revert InvalidLevel();
        }

        AgentSkill storage agentSkill = _agentSkillData[agentId][skillId];

        if (agentSkill.level == VerificationLevel.None) {
            _addSkillToAgent(agentId, skillId, level);
        } else if (level > agentSkill.level) {
            agentSkill.level = level;
            agentSkill.lastUpdated = block.timestamp;
            _mintAgentToken(agentId, skillId, uint256(level));
        }

        emit SkillVerified(agentId, skillId, level, msg.sender);
    }

    /**
     * @inheritdoc ISkillBadge
     */
    function recordBountyCompletion(uint256 agentId, uint256 skillId) external override onlyRole(ENGINE_ROLE) {
        if (!agentRegistry.agentExists(agentId)) {
            revert InvalidAgent();
        }

        AgentSkill storage agentSkill = _agentSkillData[agentId][skillId];

        if (agentSkill.level != VerificationLevel.None) {
            agentSkill.completedBounties++;

            // Auto-upgrade to Master after 10+ bounties with Verified level
            if (
                agentSkill.completedBounties >= 10 &&
                agentSkill.level == VerificationLevel.Verified
            ) {
                agentSkill.level = VerificationLevel.Master;
                _mintAgentToken(agentId, skillId, uint256(VerificationLevel.Master));
            }
        }

        _agentCompletedJobs[agentId]++;

        emit BountyRecorded(agentId, skillId);
    }

    // ============ View Functions ============

    /**
     * @inheritdoc ISkillBadge
     */
    function getAgentSkill(uint256 agentId, uint256 skillId)
        external
        view
        override
        returns (AgentSkill memory)
    {
        return _agentSkillData[agentId][skillId];
    }

    /**
     * @inheritdoc ISkillBadge
     */
    function getAgentSkills(uint256 agentId) external view override returns (uint256[] memory) {
        return _agentSkills[agentId];
    }

    /**
     * @inheritdoc ISkillBadge
     */
    function getSkill(uint256 skillId) external view override returns (Skill memory) {
        if (!_skills[skillId].active && _skills[skillId].created == 0) {
            revert InvalidSkillId();
        }
        return _skills[skillId];
    }

    /**
     * @inheritdoc ISkillBadge
     */
    function getActiveSkills() external view override returns (uint256[] memory) {
        return _activeSkills;
    }

    /**
     * @inheritdoc ISkillBadge
     */
    function getAgentsBySkill(uint256 skillId, VerificationLevel minLevel)
        external
        view
        override
        returns (uint256[] memory)
    {
        uint256[] memory allAgents = _skillAgents[skillId];
        uint256 count = 0;

        // First pass: count matching agents
        for (uint256 i = 0; i < allAgents.length; i++) {
            if (_agentSkillData[allAgents[i]][skillId].level >= minLevel) {
                count++;
            }
        }

        // Second pass: collect matching agents
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < allAgents.length; i++) {
            if (_agentSkillData[allAgents[i]][skillId].level >= minLevel) {
                result[index] = allAgents[i];
                index++;
            }
        }

        return result;
    }

    /**
     * @inheritdoc ISkillBadge
     */
    function hasSkillLevel(uint256 agentId, uint256 skillId, VerificationLevel minLevel)
        external
        view
        override
        returns (bool)
    {
        return _agentSkillData[agentId][skillId].level >= minLevel;
    }

    /**
     * @notice Get total completed jobs for an agent
     * @param agentId The agent ID
     * @return Total number of completed bounties
     */
    function getAgentCompletedJobs(uint256 agentId) external view returns (uint256) {
        return _agentCompletedJobs[agentId];
    }

    /**
     * @notice Check if an address has endorsed an agent's skill
     * @param agentId The agent ID
     * @param skillId The skill ID
     * @param endorser The endorser address
     * @return True if endorsed
     */
    function hasEndorsed(uint256 agentId, uint256 skillId, address endorser) external view returns (bool) {
        return _endorsements[agentId][skillId][endorser];
    }

    // ============ Internal Functions ============

    /**
     * @dev Add a skill to an agent (internal)
     */
    function _addSkillToAgent(uint256 agentId, uint256 skillId, VerificationLevel level) internal {
        AgentSkill storage agentSkill = _agentSkillData[agentId][skillId];

        // Check if already has the skill
        if (agentSkill.level != VerificationLevel.None) {
            // Update level if higher
            if (level > agentSkill.level) {
                agentSkill.level = level;
                agentSkill.lastUpdated = block.timestamp;
                _mintAgentToken(agentId, skillId, uint256(level));
            }
            return;
        }

        // Add new skill
        agentSkill.skillId = skillId;
        agentSkill.level = level;
        agentSkill.endorsedCount = 0;
        agentSkill.completedBounties = 0;
        agentSkill.lastUpdated = block.timestamp;

        // Add to agent's skill list
        _agentSkills[agentId].push(skillId);
        _agentSkillIndex[agentId][skillId] = _agentSkills[agentId].length - 1;

        // Add to skill's agent list
        if (_skillAgents[skillId].length < MAX_AGENTS_PER_SKILL) {
            _skillAgents[skillId].push(agentId);
            _agentInSkillArray[skillId][agentId] = true;
        }

        // Mint the badge token
        _mintAgentToken(agentId, skillId, uint256(level));

        emit SkillClaimed(agentId, skillId);
    }

    /**
     * @dev Mint badge token for agent
     */
    function _mintAgentToken(uint256 agentId, uint256 skillId, uint256 level) internal {
        address wallet = agentRegistry.getAgentWallet(agentId);
        if (wallet != address(0)) {
            // Mint with amount = level (1=Self, 2=Peer, 3=Verified, 4=Master)
            // Burn any existing tokens first, then mint new level
            uint256 balance = balanceOf(wallet, skillId);
            if (balance > 0) {
                _burn(wallet, skillId, balance);
            }
            _mint(wallet, skillId, level, "");
        }
    }

    /**
     * @dev Register default skills on deployment
     */
    function _registerDefaultSkills() internal {
        // Register specific skills with predetermined IDs
        _registerSkillDirect(1, "Solidity Development", "Blockchain");
        _registerSkillDirect(2, "Rust Development", "Blockchain");
        _registerSkillDirect(3, "Smart Contract Auditing", "Security");
        _registerSkillDirect(4, "Zero-Knowledge Proofs", "Blockchain");
        _registerSkillDirect(5, "Chaincode Development", "Blockchain");

        // Update counter to 5 after manual registrations
        _skillIdCounter._value = 5;

        // Now use counter for remaining skills (IDs 6+)
        _registerDefaultSkill("LLM Fine-tuning", "AI");
        _registerDefaultSkill("Computer Vision", "AI");
        _registerDefaultSkill("Natural Language Processing", "AI");
        _registerDefaultSkill("AI Agent Development", "AI");
        _registerDefaultSkill("Prompt Engineering", "AI");

        // Design/Creative (2000-2099)
        _registerDefaultSkill("UI/UX Design", "Design");
        _registerDefaultSkill("Graphic Design", "Design");
        _registerDefaultSkill("3D Modeling", "Design");
        _registerDefaultSkill("Animation", "Design");

        // Business/Operations (3000-3099)
        _registerDefaultSkill("Project Management", "Business");
        _registerDefaultSkill("Community Management", "Business");
        _registerDefaultSkill("Business Development", "Business");
        _registerDefaultSkill("DAO Governance", "Business");

        // Security (4000-4099)
        _registerDefaultSkill("Penetration Testing", "Security");
        _registerDefaultSkill("Security Auditing", "Security");
        _registerDefaultSkill("Cryptography", "Security");
        _registerDefaultSkill("Red Teaming", "Security");
    }

    /**
     * @dev Register a skill with a specific ID (bypasses counter)
     */
    function _registerSkillDirect(uint256 skillId, string memory name, string memory category) internal {
        _skills[skillId] = Skill({
            name: name,
            category: category,
            active: true,
            created: block.timestamp
        });

        _activeSkills.push(skillId);
    }

    /**
     * @dev Register a single default skill (uses counter)
     */
    function _registerDefaultSkill(string memory name, string memory category) internal {
        _skillIdCounter.increment();
        uint256 skillId = _skillIdCounter.current();

        _skills[skillId] = Skill({
            name: name,
            category: category,
            active: true,
            created: block.timestamp
        });

        _activeSkills.push(skillId);
    }

    // Required override for multiple inheritance
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl, IERC165)  // Add IERC165
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
