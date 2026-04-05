// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title IServerRegistry
 * @dev Interface for Server Registry contract
 */
interface IServerRegistry {
    // ============ Enums ============

    enum ServerType {
        None,       // 0
        Public,     // 1 - Anyone can join
        Private,    // 2 - Invite only
        Verified    // 3 - Require verification to join
    }

    // ============ Structs ============

    struct Server {
        uint256 id;
        address owner;
        string name;
        string icon;
        string description;
        string category;
        ServerType serverType;
        uint256 memberCount;
        uint256 createdAt;
        uint256 updatedAt;
        bool isActive;
    }

    struct Invite {
        bytes32 code;
        uint256 maxUses;
        uint256 useCount;
        uint256 expiresAt;
    }

    // ============ Server Management ============

    function createServer(
        string calldata name,
        string calldata icon,
        string calldata description,
        string calldata category,
        ServerType serverType
    ) external returns (uint256 serverId);

    function updateServer(
        uint256 serverId,
        string calldata name,
        string calldata icon,
        string calldata description
    ) external;

    function setServerType(uint256 serverId, ServerType serverType) external;

    function setCategory(uint256 serverId, string calldata category) external;

    // ============ Membership ============

    function joinServer(uint256 serverId) external;

    function leaveServer(uint256 serverId) external;

    function kickMember(uint256 serverId, address member, string calldata reason) external;

    // ============ View Functions ============

    function getServer(uint256 serverId) external view returns (Server memory);

    function getServersByCategory(string calldata category)
        external
        view
        returns (uint256[] memory);

    function getAllServers() external view returns (uint256[] memory);

    function getServerMembers(uint256 serverId)
        external
        view
        returns (address[] memory);

    function getMemberServers(address member)
        external
        view
        returns (uint256[] memory);

    function isMember(uint256 serverId, address member) external view returns (bool);

    function getTotalServers() external view returns (uint256);

    // ============ Invite Codes ============

    function createInviteCode(
        uint256 serverId,
        uint256 maxUses,
        uint256 expiresAt
    ) external returns (bytes32 code);

    function useInviteCode(uint256 serverId, bytes32 code) external;
}
