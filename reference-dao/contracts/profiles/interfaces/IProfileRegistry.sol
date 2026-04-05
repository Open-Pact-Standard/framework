// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title IProfileRegistry
 * @dev Interface for Profile Registry contract
 */
interface IProfileRegistry {
    // ============ Structs ============

    struct Profile {
        address owner;
        string displayName;
        string avatar;       // IPFS hash or URL
        string bio;
        string location;
        string website;
        string twitter;
        string github;
        string discord;
        uint256 reputationScore;
        uint256 completedJobs;
        uint256 totalEarnings;
        uint256 createdAt;
        uint256 updatedAt;
        bool isActive;
    }

    struct WorkSample {
        uint256 id;
        address creator;
        string title;
        string description;
        string ipfsHash;      // Work content/files
        string proofLink;     // External proof (GitHub, etc.)
        uint256[] skillTags;  // Associated skill IDs
        uint256 createdAt;
        bool isActive;
    }

    struct Skill {
        uint256 id;
        string name;
        string category;     // e.g., "Development", "Design", "Marketing"
        uint256 verifiedLevel; // 0-5, verified by platform or experts
    }

    struct UserSkill {
        uint256 skillId;
        uint256 level;       // Self-assessed level 1-10
        uint256 verifiedLevel; // Platform verified level 0-5
        address verifiedBy;  // Who verified this skill
        uint256 verifiedAt;
        bool isVerified;
    }

    struct ServerMembership {
        uint256 serverId;
        string serverName;
        bool displayPublicly; // Show on profile
        uint256 joinedAt;
        string role;         // User's role/display name
    }

    // ============ Profile Management ============

    function createProfile(
        string calldata displayName,
        string calldata avatar,
        string calldata bio,
        string calldata metadataURI
    ) external returns (uint256 profileId);

    function updateBasicInfo(
        string calldata displayName,
        string calldata avatar,
        string calldata bio
    ) external;

    function updateSocialLinks(
        string calldata location,
        string calldata website,
        string calldata twitter,
        string calldata github,
        string calldata discord
    ) external;

    function deactivateProfile() external;

    // ============ Work Samples / Portfolio ============

    function addWorkSample(
        string calldata title,
        string calldata description,
        string calldata ipfsHash,
        string calldata proofLink,
        uint256[] calldata skillTags
    ) external returns (uint256 sampleId);

    function updateWorkSample(
        uint256 sampleId,
        string calldata title,
        string calldata description,
        string calldata ipfsHash,
        string calldata proofLink
    ) external;

    function removeWorkSample(uint256 sampleId) external;

    // ============ Skills ============

    function addSkill(uint256 skillId, uint256 level) external;

    function verifySkill(
        address user,
        uint256 skillId,
        uint256 verifiedLevel,
        string calldata proof
    ) external;

    function removeSkill(uint256 skillId) external;

    // ============ Server Memberships ============

    function linkServerMembership(
        uint256 serverId,
        string calldata serverName,
        string calldata role,
        bool displayPublicly
    ) external;

    function unlinkServerMembership(uint256 serverId) external;

    function updateServerDisplay(
        uint256 serverId,
        string calldata role,
        bool displayPublicly
    ) external;

    // ============ View Functions ============

    function getProfile(address user)
        external
        view
        returns (Profile memory);

    function getWorkSample(uint256 sampleId)
        external
        view
        returns (WorkSample memory);

    function getUserWorkSamples(address user)
        external
        view
        returns (WorkSample[] memory);

    function getUserSkills(address user)
        external
        view
        returns (UserSkill[] memory);

    function getSkill(uint256 skillId)
        external
        view
        returns (Skill memory);

    function getAllSkills()
        external
        view
        returns (uint256[] memory);

    function getUserServerMemberships(address user)
        external
        view
        returns (ServerMembership[] memory);

    function isProfileCreated(address user)
        external
        view
        returns (bool);

    // ============ Reputation Stats ============

    function updateReputation(
        address user,
        int256 delta
    ) external;

    function recordCompletedJob(
        address user,
        uint256 earnings
    ) external;

    function getReputationScore(address user)
        external
        view
        returns (uint256);

    // ============ Events ============

    event ProfileCreated(uint256 indexed profileId, address indexed owner, string displayName);
    event ProfileUpdated(address indexed owner, string displayName);
    event ProfileDeactivated(address indexed owner);
    event WorkSampleAdded(uint256 indexed sampleId, address indexed creator, string title);
    event WorkSampleUpdated(uint256 indexed sampleId, string title);
    event WorkSampleRemoved(uint256 indexed sampleId);
    event SkillAdded(address indexed user, uint256 skillId, uint256 level);
    event SkillVerified(address indexed user, uint256 skillId, uint256 verifiedLevel, address verifiedBy);
    event SkillRemoved(address indexed user, uint256 skillId);
    event ServerMembershipLinked(address indexed user, uint256 serverId, string role);
    event ServerMembershipUnlinked(address indexed user, uint256 serverId);
    event ReputationUpdated(address indexed user, uint256 oldScore, uint256 newScore);
    event JobCompleted(address indexed user, uint256 earnings, uint256 totalJobs);
}
