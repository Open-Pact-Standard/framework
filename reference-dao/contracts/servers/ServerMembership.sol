// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { IServerRegistry } from "./interfaces/IServerRegistry.sol";
import { IServerMembership } from "./interfaces/IServerMembership.sol";
import { Permissions } from "./Permissions.sol";

/**
 * @title ServerMembership
 * @dev Manages server membership with roles and permissions
 *      Discord-compatible role system
 *
 *      Features:
 *      - Role creation and management
 *      - Role assignment to members
 *      - Permission checking
 *      - Join requests for private servers
 *      - Member removal
 */
contract ServerMembership is IServerMembership, Ownable, AccessControl {
    /// @notice Server registry contract
    IServerRegistry public immutable serverRegistry;

    /// @notice Server ID => Role data
    mapping(uint256 => mapping(uint256 => Role)) private _roles;

    /// @notice Next role ID for each server
    mapping(uint256 => uint256) private _nextRoleId;

    /// @notice Server ID => Member address => Role IDs
    mapping(uint256 => mapping(address => uint256[])) private _memberRoles;

    /// @notice Server ID => Address => Join request
    mapping(uint256 => mapping(address => JoinRequest)) private _joinRequests;

    /// @notice Server ID => Join request count
    mapping(uint256 => uint256) private _joinRequestCount;

    /// @notice Platform admin role
    bytes32 public constant PLATFORM_ADMIN = keccak256("PLATFORM_ADMIN");

    // ============ Events ============

    event RoleCreated(uint256 indexed serverId, uint256 indexed roleId, string name, uint256 color, uint256 permissions);
    event RoleUpdated(uint256 indexed serverId, uint256 indexed roleId, string name, uint256 color, uint256 permissions);
    event RoleDeleted(uint256 indexed serverId, uint256 indexed roleId);
    event RoleAssigned(uint256 indexed serverId, address indexed member, uint256 indexed roleId);
    event RoleRemoved(uint256 indexed serverId, address indexed member, uint256 indexed roleId);
    event JoinRequested(uint256 indexed serverId, address indexed member, string application);
    event JoinApproved(uint256 indexed serverId, address indexed member);
    event JoinRejected(uint256 indexed serverId, address indexed member, string reason);
    event MemberRemoved(uint256 indexed serverId, address indexed member);

    // ============ Custom Errors ============

    error ServerNotFound();
    error NotServerOwner();
    error NotAuthorized();
    error RoleNotFound();
    error InvalidPermissions();
    error RoleExists();
    error InvalidName();
    error AlreadyHasRole();
    error DoesNotHaveRole();
    error NotMember();
    error NoJoinRequest();
    error RequestAlreadyProcessed();
    error MaxRolesReached();

    /// @notice Max roles per member per server
    uint256 public constant MAX_ROLES_PER_MEMBER = 50;

    // ============ Modifiers ============

    modifier onlyServerOwner(uint256 serverId) {
        if (!_isServerOwner(serverId, msg.sender)) revert NotServerOwner();
        _;
    }

    modifier serverExists(uint256 serverId) {
        if (!_serverExists(serverId)) revert ServerNotFound();
        _;
    }

    // ============ Constructor ============

    constructor(address serverRegistry_) Ownable() {
        if (serverRegistry_ == address(0)) revert("Zero address");

        serverRegistry = IServerRegistry(serverRegistry_);

        // Grant admin role to contract deployer
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PLATFORM_ADMIN, msg.sender);
    }

    // ============ Role Management ============

    /**
     * @notice Create a new role
     * @param serverId Server ID
     * @param name Role name
     * @param color Role color (Discord format: 0xRRGGBB)
     * @param permissions Permission bitmask
     */
    function createRole(
        uint256 serverId,
        string calldata name,
        uint256 color,
        uint256 permissions
    )
        external
        serverExists(serverId)
        onlyServerOwner(serverId)
        returns (uint256 roleId)
    {
        if (bytes(name).length == 0 || bytes(name).length > 100) revert InvalidName();

        roleId = _nextRoleId[serverId]++;

        _roles[serverId][roleId] = Role({
            id: roleId,
            name: name,
            color: color,
            permissions: permissions,
            isActive: true
        });

        emit RoleCreated(serverId, roleId, name, color, permissions);
        return roleId;
    }

    /**
     * @notice Update a role
     */
    function updateRole(
        uint256 serverId,
        uint256 roleId,
        string calldata name,
        uint256 color,
        uint256 permissions
    )
        external
        serverExists(serverId)
        onlyServerOwner(serverId)
    {
        Role storage role = _roles[serverId][roleId];

        if (role.id != roleId || !role.isActive) revert RoleNotFound();

        role.name = name;
        role.color = color;
        role.permissions = permissions;

        emit RoleUpdated(serverId, roleId, name, color, permissions);
    }

    /**
     * @notice Delete a role
     */
    function deleteRole(uint256 serverId, uint256 roleId)
        external
        serverExists(serverId)
        onlyServerOwner(serverId)
    {
        Role storage role = _roles[serverId][roleId];

        if (role.id != roleId || !role.isActive) revert RoleNotFound();

        role.isActive = false;
        delete _roles[serverId][roleId];

        emit RoleDeleted(serverId, roleId);
    }

    /**
     * @notice Assign a role to a member
     */
    function assignRole(
        uint256 serverId,
        address member,
        uint256 roleId
    )
        external
        serverExists(serverId)
        onlyServerOwner(serverId)
    {
        if (!_isMember(serverId, member)) revert NotMember();

        Role storage role = _roles[serverId][roleId];
        if (role.id != roleId || !role.isActive) revert RoleNotFound();

        uint256[] storage roles = _memberRoles[serverId][member];

        // Check if already has role
        for (uint256 i = 0; i < roles.length; i++) {
            if (roles[i] == roleId) revert AlreadyHasRole();
        }

        // Check max roles
        if (roles.length >= MAX_ROLES_PER_MEMBER) revert MaxRolesReached();

        _memberRoles[serverId][member].push(roleId);

        emit RoleAssigned(serverId, member, roleId);
    }

    /**
     * @notice Remove a role from a member
     */
    function removeRole(
        uint256 serverId,
        address member,
        uint256 roleId
    )
        external
        serverExists(serverId)
        onlyServerOwner(serverId)
    {
        uint256[] storage roles = _memberRoles[serverId][member];

        // Find and remove role
        uint256 foundIndex = type(uint256).max;
        for (uint256 i = 0; i < roles.length; i++) {
            if (roles[i] == roleId) {
                foundIndex = i;
                break;
            }
        }

        if (foundIndex == type(uint256).max) revert DoesNotHaveRole();

        // Move last element to found position
        uint256 lastIndex = roles.length - 1;
        if (foundIndex != lastIndex) {
            roles[foundIndex] = roles[lastIndex];
        }
        roles.pop();

        emit RoleRemoved(serverId, member, roleId);
    }

    /**
     * @notice Batch assign roles
     */
    function batchAssignRoles(
        uint256 serverId,
        address[] calldata members,
        uint256 roleId
    )
        external
        serverExists(serverId)
        onlyServerOwner(serverId)
    {
        for (uint256 i = 0; i < members.length; i++) {
            if (_isMember(serverId, members[i])) {
                // Check if already has role
                bool alreadyHas = false;
                uint256[] storage roles = _memberRoles[serverId][members[i]];
                for (uint256 j = 0; j < roles.length; j++) {
                    if (roles[j] == roleId) {
                        alreadyHas = true;
                        break;
                    }
                }

                if (!alreadyHas) {
                    _memberRoles[serverId][members[i]].push(roleId);
                    emit RoleAssigned(serverId, members[i], roleId);
                }
            }
        }
    }

    // ============ Join Requests ============

    /**
     * @notice Request to join a private/verified server
     */
    function requestToJoin(uint256 serverId, string calldata application)
        external
        serverExists(serverId)
    {
        if (_isMember(serverId, msg.sender)) revert AlreadyHasRole();

        // Check if already has pending request
        JoinRequest storage request = _joinRequests[serverId][msg.sender];
        if (request.member == msg.sender && !request.processed) {
            revert RequestAlreadyProcessed();
        }

        _joinRequests[serverId][msg.sender] = JoinRequest({
            member: msg.sender,
            application: application,
            timestamp: block.timestamp,
            processed: false
        });

        _joinRequestCount[serverId]++;

        emit JoinRequested(serverId, msg.sender, application);
    }

    /**
     * @notice Approve a join request
     */
    function approveJoinRequest(uint256 serverId, address member)
        external
        serverExists(serverId)
        onlyServerOwner(serverId)
    {
        JoinRequest storage request = _joinRequests[serverId][member];

        if (request.member != member || request.processed) revert NoJoinRequest();

        request.processed = true;
        delete _joinRequests[serverId][member];
        _joinRequestCount[serverId]--;

        // Add member
        _addMemberToServer(serverId, member);

        emit JoinApproved(serverId, member);
    }

    /**
     * @notice Reject a join request
     */
    function rejectJoinRequest(uint256 serverId, address member, string calldata reason)
        external
        serverExists(serverId)
        onlyServerOwner(serverId)
    {
        JoinRequest storage request = _joinRequests[serverId][member];

        if (request.member != member) revert NoJoinRequest();

        request.processed = true;
        delete _joinRequests[serverId][member];
        _joinRequestCount[serverId]--;

        emit JoinRejected(serverId, member, reason);
    }

    // ============ Member Management ============

    /**
     * @notice Remove a member from server
     */
    function removeMember(uint256 serverId, address member)
        external
        serverExists(serverId)
    {
            // Only server owner or platform admin can remove members
            if (!_isServerOwner(serverId, msg.sender) &&
                !hasRole(PLATFORM_ADMIN, msg.sender)) {
                revert NotAuthorized();
            }

            if (!_isMember(serverId, member)) revert NotMember();

            // Cannot remove owner
            if (_isServerOwner(serverId, member)) revert NotAuthorized();

            _removeMemberFromServer(serverId, member);

            emit MemberRemoved(serverId, member);
    }

    // ============ Permission Checking ============

    /**
     * @notice Check if a member has a specific permission
     */
    function hasPermission(
        uint256 serverId,
        address member,
        uint256 permission
    )
        external
        view
        returns (bool)
    {
        return _hasPermission(serverId, member, permission);
    }

    /**
     * @notice Check if member has admin permission
     */
    function isAdmin(uint256 serverId, address member)
        external
        view
        returns (bool)
    {
        return _hasPermission(serverId, member, Permissions.PERMISSION_ADMIN);
    }

    /**
     * @notice Check if member can moderate
     */
    function isModerator(uint256 serverId, address member)
        external
        view
        returns (bool)
    {
        return _hasPermission(serverId, member, Permissions.PERMISSION_MODERATION);
    }

    // ============ View Functions ============

    /**
     * @notice Get role details
     */
    function getRole(uint256 serverId, uint256 roleId)
        external
        view
        returns (Role memory)
    {
        return _roles[serverId][roleId];
    }

    /**
     * @notice Get all roles for a server
     */
    function getRoles(uint256 serverId)
        external
        view
        returns (uint256[] memory roleIds)
    {
        uint256 count = _nextRoleId[serverId];
        uint256[] memory tempIds = new uint256[](count);

        uint256 index = 0;
        for (uint256 i = 1; i <= count; i++) {
            if (_roles[serverId][i].isActive) {
                tempIds[index++] = i;
            }
        }

        // Trim to actual count
        roleIds = new uint256[](index);
        for (uint256 i = 0; i < index; i++) {
            roleIds[i] = tempIds[i];
        }

        return roleIds;
    }

    /**
     * @notice Get member's roles
     */
    function getMemberRoles(uint256 serverId, address member)
        external
        view
        returns (uint256[] memory)
    {
        return _memberRoles[serverId][member];
    }

    /**
     * @notice Get pending join requests
     */
    function getJoinRequests(uint256 serverId)
        external
        view
        returns (JoinRequest[] memory)
    {
        uint256[] memory requestIndices = new uint256[](_joinRequestCount[serverId]);
        uint256 index = 0;

        // Collect all pending requests
        // This is expensive and would typically be paginated
        // For now, return empty if too many
        if (_joinRequestCount[serverId] > 100) {
            return new JoinRequest[](0);
        }

        JoinRequest[] memory requests = new JoinRequest[](_joinRequestCount[serverId]);

        // Note: This is a simplified implementation
        // In production, you'd want a more efficient data structure
        return requests;
    }

    // ============ Internal Functions ============

    function _isServerOwner(uint256 serverId, address caller)
        internal
        view
        returns (bool)
    {
        return serverRegistry.getServer(serverId).owner == caller;
    }

    function _serverExists(uint256 serverId) internal view returns (bool) {
        try serverRegistry.getServer(serverId) {
            return true;
        } catch {
            return false;
        }
    }

    function _isMember(uint256 serverId, address member) internal view returns (bool) {
        return serverRegistry.isMember(serverId, member);
    }

    function _hasPermission(
        uint256 serverId,
        address member,
        uint256 permission
    ) internal view returns (bool) {
        // Server owner has all permissions
        if (_isServerOwner(serverId, member)) {
            return true;
        }

        // Check member's roles for permission
        uint256[] storage roles = _memberRoles[serverId][member];
        for (uint256 i = 0; i < roles.length; i++) {
            Role storage role = _roles[serverId][roles[i]];
            if (role.isActive && (role.permissions & permission) != 0) {
                return true;
            }
        }

        return false;
    }

    function _addMemberToServer(uint256 serverId, address member) internal {
        // This is called by the ServerRegistry when joining
        // We don't need to add the member here as ServerRegistry handles it
        // This function is for any additional membership logic
        emit RoleAssigned(serverId, member, 0); // Assign default role
    }

    function _removeMemberFromServer(uint256 serverId, address member) internal {
        // Remove all roles
        delete _memberRoles[serverId][member];
    }
}
