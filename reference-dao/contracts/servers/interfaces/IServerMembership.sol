// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title IServerMembership
 * @dev Interface for Server Membership contract
 */
interface IServerMembership {
    // ============ Structs ============

    struct Role {
        uint256 id;
        string name;
        uint256 color;
        uint256 permissions;
        bool isActive;
    }

    struct JoinRequest {
        address member;
        string application;
        uint256 timestamp;
        bool processed;
    }

    // ============ Role Management ============

    function createRole(
        uint256 serverId,
        string calldata name,
        uint256 color,
        uint256 permissions
    ) external returns (uint256 roleId);

    function updateRole(
        uint256 serverId,
        uint256 roleId,
        string calldata name,
        uint256 color,
        uint256 permissions
    ) external;

    function deleteRole(uint256 serverId, uint256 roleId) external;

    function assignRole(uint256 serverId, address member, uint256 roleId) external;

    function removeRole(uint256 serverId, address member, uint256 roleId) external;

    function batchAssignRoles(
        uint256 serverId,
        address[] calldata members,
        uint256 roleId
    ) external;

    // ============ Join Requests ============

    function requestToJoin(uint256 serverId, string calldata application) external;

    function approveJoinRequest(uint256 serverId, address member) external;

    function rejectJoinRequest(uint256 serverId, address member, string calldata reason) external;

    // ============ Member Management ============

    function removeMember(uint256 serverId, address member) external;

    // ============ Permission Checking ============

    function hasPermission(
        uint256 serverId,
        address member,
        uint256 permission
    ) external view returns (bool);

    function isAdmin(uint256 serverId, address member) external view returns (bool);

    function isModerator(uint256 serverId, address member) external view returns (bool);

    // ============ View Functions ============

    function getRole(uint256 serverId, uint256 roleId)
        external
        view
        returns (Role memory);

    function getRoles(uint256 serverId) external view returns (uint256[] memory);

    function getMemberRoles(uint256 serverId, address member)
        external
        view
        returns (uint256[] memory);

    function getJoinRequests(uint256 serverId)
        external
        view
        returns (JoinRequest[] memory);
}
