// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title Permissions
 * @dev Library defining Discord-compatible permission flags
 */
library Permissions {
    // ============ Individual Permissions ============

    uint256 internal constant PERMISSION_ADMINISTRATOR = 1 << 0;  // 0x1
    uint256 internal constant PERMISSION_MODERATOR = 1 << 1;       // 0x2
    uint256 internal constant PERMISSION_MEMBER = 1 << 2;           // 0x4
    uint256 internal constant PERMISSION_BOUNTY_POSTER = 1 << 3;    // 0x8
    uint256 internal constant PERMISSION_BOUNTY_APPROVER = 1 << 4; // 0x10
    uint256 internal constant PERMISSION_KICK = 1 << 5;             // 0x20
    uint256 internal constant PERMISSION_BAN = 1 << 6;              // 0x40
    uint256 internal constant PERMISSION_MANAGE_CHANNELS = 1 << 7; // 0x80
    uint256 internal constant PERMISSION_MANAGE_ROLES = 1 << 8;    // 0x100

    // ============ Permission Combinations ============

    uint256 internal constant PERMISSION_ADMIN = PERMISSION_ADMINISTRATOR |
                                            PERMISSION_MODERATOR |
                                            PERMISSION_KICK |
                                            PERMISSION_BAN |
                                            PERMISSION_MANAGE_CHANNELS |
                                            PERMISSION_MANAGE_ROLES;

    uint256 internal constant PERMISSION_MODERATION = PERMISSION_MODERATOR |
                                              PERMISSION_KICK |
                                              PERMISSION_MANAGE_CHANNELS;

    // ============ Helper Functions ============

    /// @notice Check if permissions include a specific flag
    function hasPermission(uint256 permissions, uint256 flag)
        internal
        pure
        returns (bool)
    {
        return (permissions & flag) != 0;
    }

    /// @notice Add a permission flag
    function addPermission(uint256 permissions, uint256 flag)
        internal
        pure
        returns (uint256)
    {
        return permissions | flag;
    }

    /// @notice Remove a permission flag
    function removePermission(uint256 permissions, uint256 flag)
        internal
        pure
        returns (uint256)
    {
        return permissions & ~flag;
    }
}
