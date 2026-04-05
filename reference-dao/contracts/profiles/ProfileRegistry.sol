// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import { IProfileRegistry } from "./interfaces/IProfileRegistry.sol";

/**
 * @title ProfileRegistry
 * @dev User profiles with work showcase, skills, and reputation tracking
 *
 *      Features:
 *      - Create and update profiles
 *      - Portfolio/work samples showcase
 *      - Skill management with verification
 *      - Server membership display
 *      - Reputation and earnings tracking
 *      - Links to social accounts
 */
contract ProfileRegistry is IProfileRegistry, Ownable, AccessControl {
    /// @notice Profile ID counter
    uint256 private _profileIdCounter;

    /// @notice Work sample ID counter
    uint256 private _sampleIdCounter;

    /// @notice Skill ID counter
    uint256 private _skillIdCounter;

    /// @notice User address => Profile
    mapping(address => Profile) private _profiles;

    /// @notice Sample ID => WorkSample
    mapping(uint256 => WorkSample) private _workSamples;

    /// @notice User address => Work sample IDs
    mapping(address => uint256[]) private _userWorkSamples;

    /// @notice Skill ID => Skill definition
    mapping(uint256 => Skill) private _skills;

    /// @notice User address => skill ID => UserSkill
    mapping(address => mapping(uint256 => UserSkill)) private _userSkills;

    /// @notice User address => User's skill IDs
    mapping(address => uint256[]) private _userSkillList;

    /// @notice User address => server ID => ServerMembership
    mapping(address => mapping(uint256 => ServerMembership)) private _serverMemberships;

    /// @notice User address => Server membership IDs
    mapping(address => uint256[]) private _userServerList;

    /// @notice Platform verifier role (can verify skills)
    bytes32 public constant SKILL_VERIFIER = keccak256("SKILL_VERIFIER");

    /// @notice Maximum work samples per user
    uint256 public constant MAX_WORK_SAMPLES = 50;

    /// @notice Maximum skills per user
    uint256 public constant MAX_SKILLS = 30;

    /// @notice Maximum server memberships to display
    uint256 public constant MAX_SERVER_DISPLAYS = 20;

    // ============ Custom Errors ============

    error ProfileNotFound();
    error ProfileExists();
    error InvalidInput();
    error WorkSampleNotFound();
    error NotWorkSampleOwner();
    error MaxWorkSamplesReached();
    error SkillNotFound();
    error SkillAlreadyAdded();
    error MaxSkillsReached();
    error NotSkillVerifier();
    error ServerMembershipNotFound();
    error InvalidReputationDelta();

    // ============ Constructor ============

    constructor() Ownable() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SKILL_VERIFIER, msg.sender);

        // Initialize base skills
        _initializeBaseSkills();
    }

    // ============ Profile Management ============

    /**
     * @notice Create a new profile
     */
    function createProfile(
        string calldata displayName,
        string calldata avatar,
        string calldata bio,
        string calldata metadataURI
    ) external returns (uint256 profileId) {
        if (_profiles[msg.sender].isActive) revert ProfileExists();
        if (bytes(displayName).length == 0 || bytes(displayName).length > 50) revert InvalidInput();

        _profileIdCounter++;
        profileId = _profileIdCounter;

        _profiles[msg.sender] = Profile({
            owner: msg.sender,
            displayName: displayName,
            avatar: avatar,
            bio: bio,
            location: "",
            website: "",
            twitter: "",
            github: "",
            discord: "",
            reputationScore: 100, // Start with base reputation
            completedJobs: 0,
            totalEarnings: 0,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            isActive: true
        });

        emit ProfileCreated(profileId, msg.sender, displayName);
        return profileId;
    }

    /**
     * @notice Update profile basic info (name, avatar, bio)
     */
    function updateBasicInfo(
        string calldata displayName,
        string calldata avatar,
        string calldata bio
    ) external {
        if (!_profiles[msg.sender].isActive) revert ProfileNotFound();
        if (bytes(displayName).length == 0 || bytes(displayName).length > 50) revert InvalidInput();

        Profile storage profile = _profiles[msg.sender];
        profile.displayName = displayName;
        profile.avatar = avatar;
        profile.bio = bio;
        profile.updatedAt = block.timestamp;

        emit ProfileUpdated(msg.sender, displayName);
    }

    /**
     * @notice Update profile social links
     */
    function updateSocialLinks(
        string calldata location,
        string calldata website,
        string calldata twitter,
        string calldata github,
        string calldata discord
    ) external {
        if (!_profiles[msg.sender].isActive) revert ProfileNotFound();

        Profile storage profile = _profiles[msg.sender];
        profile.location = location;
        profile.website = website;
        profile.twitter = twitter;
        profile.github = github;
        profile.discord = discord;
        profile.updatedAt = block.timestamp;

        emit ProfileUpdated(msg.sender, profile.displayName);
    }

    /**
     * @notice Deactivate profile
     */
    function deactivateProfile() external {
        if (!_profiles[msg.sender].isActive) revert ProfileNotFound();

        _profiles[msg.sender].isActive = false;

        emit ProfileDeactivated(msg.sender);
    }

    // ============ Work Samples / Portfolio ============

    /**
     * @notice Add a work sample to portfolio
     */
    function addWorkSample(
        string calldata title,
        string calldata description,
        string calldata ipfsHash,
        string calldata proofLink,
        uint256[] calldata skillTags
    ) external returns (uint256 sampleId) {
        if (!_profiles[msg.sender].isActive) revert ProfileNotFound();
        if (bytes(title).length == 0 || bytes(title).length > 100) revert InvalidInput();
        if (_userWorkSamples[msg.sender].length >= MAX_WORK_SAMPLES) revert MaxWorkSamplesReached();

        _sampleIdCounter++;
        sampleId = _sampleIdCounter;

        _workSamples[sampleId] = WorkSample({
            id: sampleId,
            creator: msg.sender,
            title: title,
            description: description,
            ipfsHash: ipfsHash,
            proofLink: proofLink,
            skillTags: skillTags,
            createdAt: block.timestamp,
            isActive: true
        });

        _userWorkSamples[msg.sender].push(sampleId);

        emit WorkSampleAdded(sampleId, msg.sender, title);
        return sampleId;
    }

    /**
     * @notice Update a work sample
     */
    function updateWorkSample(
        uint256 sampleId,
        string calldata title,
        string calldata description,
        string calldata ipfsHash,
        string calldata proofLink
    ) external {
        WorkSample storage sample = _workSamples[sampleId];

        if (sample.id != sampleId || !sample.isActive) revert WorkSampleNotFound();
        if (sample.creator != msg.sender) revert NotWorkSampleOwner();

        if (bytes(title).length == 0 || bytes(title).length > 100) revert InvalidInput();

        sample.title = title;
        sample.description = description;
        sample.ipfsHash = ipfsHash;
        sample.proofLink = proofLink;

        emit WorkSampleUpdated(sampleId, title);
    }

    /**
     * @notice Remove a work sample
     */
    function removeWorkSample(uint256 sampleId) external {
        WorkSample storage sample = _workSamples[sampleId];

        if (sample.id != sampleId || !sample.isActive) revert WorkSampleNotFound();
        if (sample.creator != msg.sender) revert NotWorkSampleOwner();

        sample.isActive = false;
        delete _workSamples[sampleId];

        // Remove from user's list
        _removeFromArray(_userWorkSamples[msg.sender], sampleId);

        emit WorkSampleRemoved(sampleId);
    }

    // ============ Skills ============

    /**
     * @notice Add a skill to user profile
     */
    function addSkill(uint256 skillId, uint256 level) external {
        if (!_profiles[msg.sender].isActive) revert ProfileNotFound();
        if (skillId == 0 || skillId > _skillIdCounter) revert SkillNotFound();
        if (_userSkills[msg.sender][skillId].skillId == skillId) revert SkillAlreadyAdded();
        if (level == 0 || level > 10) revert InvalidInput();
        if (_userSkillList[msg.sender].length >= MAX_SKILLS) revert MaxSkillsReached();

        _userSkills[msg.sender][skillId] = UserSkill({
            skillId: skillId,
            level: level,
            verifiedLevel: 0,
            verifiedBy: address(0),
            verifiedAt: 0,
            isVerified: false
        });

        _userSkillList[msg.sender].push(skillId);

        emit SkillAdded(msg.sender, skillId, level);
    }

    /**
     * @notice Verify a user's skill (verifier only)
     */
    function verifySkill(
        address user,
        uint256 skillId,
        uint256 verifiedLevel,
        string calldata proof
    ) external onlyRole(SKILL_VERIFIER) {
        if (_userSkills[user][skillId].skillId == 0) revert SkillNotFound();
        if (verifiedLevel > 5) revert InvalidInput();

        UserSkill storage userSkill = _userSkills[user][skillId];

        userSkill.verifiedLevel = verifiedLevel;
        userSkill.isVerified = true;
        userSkill.verifiedBy = msg.sender;
        userSkill.verifiedAt = block.timestamp;

        emit SkillVerified(user, skillId, verifiedLevel, msg.sender);
    }

    /**
     * @notice Remove a skill from profile
     */
    function removeSkill(uint256 skillId) external {
        if (_userSkills[msg.sender][skillId].skillId != skillId) revert SkillNotFound();

        delete _userSkills[msg.sender][skillId];

        _removeFromArray(_userSkillList[msg.sender], skillId);

        emit SkillRemoved(msg.sender, skillId);
    }

    // ============ Server Memberships ============

    /**
     * @notice Link a server membership to profile
     */
    function linkServerMembership(
        uint256 serverId,
        string calldata serverName,
        string calldata role,
        bool displayPublicly
    ) external {
        if (!_profiles[msg.sender].isActive) revert ProfileNotFound();
        if (bytes(serverName).length == 0) revert InvalidInput();

        _serverMemberships[msg.sender][serverId] = ServerMembership({
            serverId: serverId,
            serverName: serverName,
            displayPublicly: displayPublicly,
            joinedAt: block.timestamp,
            role: role
        });

        // Add to user's server list if not already present
        bool alreadyInList = false;
        for (uint256 i = 0; i < _userServerList[msg.sender].length; i++) {
            if (_userServerList[msg.sender][i] == serverId) {
                alreadyInList = true;
                break;
            }
        }

        if (!alreadyInList) {
            _userServerList[msg.sender].push(serverId);
        }

        emit ServerMembershipLinked(msg.sender, serverId, role);
    }

    /**
     * @notice Unlink a server membership
     */
    function unlinkServerMembership(uint256 serverId) external {
        if (_serverMemberships[msg.sender][serverId].serverId != serverId) revert ServerMembershipNotFound();

        delete _serverMemberships[msg.sender][serverId];

        _removeFromArray(_userServerList[msg.sender], serverId);

        emit ServerMembershipUnlinked(msg.sender, serverId);
    }

    /**
     * @notice Update server membership display settings
     */
    function updateServerDisplay(
        uint256 serverId,
        string calldata role,
        bool displayPublicly
    ) external {
        ServerMembership storage membership = _serverMemberships[msg.sender][serverId];

        if (membership.serverId != serverId) revert ServerMembershipNotFound();

        membership.role = role;
        membership.displayPublicly = displayPublicly;
    }

    // ============ View Functions ============

    /**
     * @notice Get user profile
     */
    function getProfile(address user)
        external
        view
        returns (Profile memory)
    {
        if (!_profiles[user].isActive) revert ProfileNotFound();
        return _profiles[user];
    }

    /**
     * @notice Get work sample
     */
    function getWorkSample(uint256 sampleId)
        external
        view
        returns (WorkSample memory)
    {
        if (!_workSamples[sampleId].isActive) revert WorkSampleNotFound();
        return _workSamples[sampleId];
    }

    /**
     * @notice Get all work samples for a user
     */
    function getUserWorkSamples(address user)
        external
        view
        returns (WorkSample[] memory)
    {
        uint256[] memory sampleIds = _userWorkSamples[user];
        WorkSample[] memory samples = new WorkSample[](sampleIds.length);

        for (uint256 i = 0; i < sampleIds.length; i++) {
            samples[i] = _workSamples[sampleIds[i]];
        }

        return samples;
    }

    /**
     * @notice Get user's skills
     */
    function getUserSkills(address user)
        external
        view
        returns (UserSkill[] memory)
    {
        uint256[] memory skillIds = _userSkillList[user];
        UserSkill[] memory skills = new UserSkill[](skillIds.length);

        for (uint256 i = 0; i < skillIds.length; i++) {
            skills[i] = _userSkills[user][skillIds[i]];
        }

        return skills;
    }

    /**
     * @notice Get skill definition
     */
    function getSkill(uint256 skillId)
        external
        view
        returns (Skill memory)
    {
        return _skills[skillId];
    }

    /**
     * @notice Get all skill IDs
     */
    function getAllSkills()
        external
        view
        returns (uint256[] memory)
    {
        uint256[] memory skillIds = new uint256[](_skillIdCounter);
        for (uint256 i = 1; i <= _skillIdCounter; i++) {
            skillIds[i - 1] = i;
        }
        return skillIds;
    }

    /**
     * @notice Get user's server memberships
     */
    function getUserServerMemberships(address user)
        external
        view
        returns (ServerMembership[] memory)
    {
        uint256[] memory serverIds = _userServerList[user];
        ServerMembership[] memory memberships = new ServerMembership[](serverIds.length);

        for (uint256 i = 0; i < serverIds.length; i++) {
            memberships[i] = _serverMemberships[user][serverIds[i]];
        }

        return memberships;
    }

    /**
     * @notice Check if profile exists
     */
    function isProfileCreated(address user)
        external
        view
        returns (bool)
    {
        return _profiles[user].isActive;
    }

    // ============ Reputation Stats ============

    /**
     * @notice Update user reputation (called by other contracts)
     */
    function updateReputation(
        address user,
        int256 delta
    ) external {
        if (!_profiles[user].isActive) revert ProfileNotFound();

        Profile storage profile = _profiles[user];
        uint256 oldScore = profile.reputationScore;

        if (delta < 0 && uint256(-delta) > profile.reputationScore) {
            profile.reputationScore = 0;
        } else {
            profile.reputationScore = uint256(int256(profile.reputationScore) + delta);
        }

        emit ReputationUpdated(user, oldScore, profile.reputationScore);
    }

    /**
     * @notice Record a completed job
     */
    function recordCompletedJob(
        address user,
        uint256 earnings
    ) external {
        if (!_profiles[user].isActive) revert ProfileNotFound();

        Profile storage profile = _profiles[user];

        profile.completedJobs++;
        profile.totalEarnings += earnings;

        emit JobCompleted(user, earnings, profile.completedJobs);
    }

    /**
     * @notice Get user's reputation score
     */
    function getReputationScore(address user)
        external
        view
        returns (uint256)
    {
        if (!_profiles[user].isActive) revert ProfileNotFound();
        return _profiles[user].reputationScore;
    }

    // ============ Internal Functions ============

    /**
     * @notice Initialize base skills
     */
    function _initializeBaseSkills() internal {
        // Development skills
        _createSkill("Solidity", "Development");
        _createSkill("JavaScript", "Development");
        _createSkill("TypeScript", "Development");
        _createSkill("Python", "Development");
        _createSkill("Rust", "Development");
        _createSkill("Go", "Development");
        _createSkill("Smart Contracts", "Development");
        _createSkill("Web Development", "Development");
        _createSkill("Mobile Development", "Development");
        _createSkill("DevOps", "Development");

        // Design skills
        _createSkill("UI Design", "Design");
        _createSkill("UX Design", "Design");
        _createSkill("Graphic Design", "Design");
        _createSkill("3D Modeling", "Design");
        _createSkill("Animation", "Design");

        // Marketing skills
        _createSkill("Content Marketing", "Marketing");
        _createSkill("Social Media", "Marketing");
        _createSkill("SEO", "Marketing");
        _createSkill("Community Management", "Marketing");
        _createSkill("Copywriting", "Marketing");

        // Business skills
        _createSkill("Project Management", "Business");
        _createSkill("Business Analysis", "Business");
        _createSkill("Strategy", "Business");
        _createSkill("Legal", "Business");
    }

    /**
     * @notice Create a new skill
     */
    function _createSkill(string memory name, string memory category) internal {
        _skillIdCounter++;

        _skills[_skillIdCounter] = Skill({
            id: _skillIdCounter,
            name: name,
            category: category,
            verifiedLevel: 0
        });
    }

    /**
     * @notice Remove element from array
     */
    function _removeFromArray(uint256[] storage array, uint256 element) internal {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == element) {
                uint256 lastIndex = array.length - 1;
                if (i != lastIndex) {
                    array[i] = array[lastIndex];
                }
                array.pop();
                break;
            }
        }
    }

    /**
     * @notice Create a new skill (admin only)
     */
    function createSkill(
        string calldata name,
        string calldata category
    ) external onlyOwner returns (uint256 skillId) {
        if (bytes(name).length == 0 || bytes(category).length == 0) revert InvalidInput();

        _skillIdCounter++;
        skillId = _skillIdCounter;

        _skills[skillId] = Skill({
            id: skillId,
            name: name,
            category: category,
            verifiedLevel: 0
        });

        return skillId;
    }

    /**
     * @notice Grant skill verifier role
     */
    function grantSkillVerifier(address verifier) external onlyOwner {
        _grantRole(SKILL_VERIFIER, verifier);
    }

    /**
     * @notice Revoke skill verifier role
     */
    function revokeSkillVerifier(address verifier) external onlyOwner {
        _revokeRole(SKILL_VERIFIER, verifier);
    }
}
