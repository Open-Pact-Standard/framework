// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { IServerRegistry } from "./interfaces/IServerRegistry.sol";

/**
 * @title ServerRegistry
 * @dev Registry for creating and managing servers (communities)
 *      Each server is an ERC-721 NFT owned by the server creator
 *
 *      Server types:
 *      - Public: Anyone can join
 *      - Private: Invite only
 *      - Verified: Requires verification to join
 *
 *      Features:
 *      - Discord-like server creation
 *      - Server categories for discovery
 *      - Invite code generation
 *      - Server metadata (IPFS)
 */
contract ServerRegistry is IServerRegistry, ERC721, ERC721URIStorage, Ownable {
    /// @notice Server ID counter
    uint256 private _serverIdCounter;

    /// @notice Server ID => Server data
    mapping(uint256 => Server) private _servers;

    /// @notice Server owner => Server ID (primary server)
    mapping(address => uint256) private _ownerToServerId;

    /// @notice Server owner => Number of servers owned
    mapping(address => uint256) private _ownerServerCount;

    /// @notice Invite code => Server ID
    mapping(bytes32 => uint256) private _inviteCodes;

    /// @notice Invite code => creator address
    mapping(bytes32 => address) private _inviteCreators;

    /// @notice Invite code => Invite data
    mapping(bytes32 => Invite) private _invites;

    /// @notice Server ID => Member addresses
    mapping(uint256 => address[]) private _serverMembers;

    /// @notice Member => Server IDs they're in
    mapping(address => uint256[]) private _memberServers;

    /// @notice Member => Position in _serverMembers array (for removal)
    mapping(uint256 => mapping(address => uint256)) private _memberIndex;

    /// @notice Category => Server IDs
    mapping(string => uint256[]) private _categoryServers;

    /// @notice All active server IDs
    uint256[] private _allServers;

    /// @notice Server ID => Position in _allServers (for removal)
    mapping(uint256 => uint256) private _allServersIndex;

    /// @notice Maximum servers one account can create
    uint256 public constant MAX_SERVERS_PER_ACCOUNT = 100;

    /// @notice Maximum members per server
    uint256 public constant MAX_MEMBERS_PER_SERVER = 500000;

    /// @notice Platform fee (basis points, e.g., 250 = 2.5%)
    uint256 public platformFeeBps = 250; // 2.5%

    // ============ Events ============

    event ServerCreated(
        uint256 indexed serverId,
        address indexed owner,
        string name,
        string category,
        ServerType serverType
    );
    event ServerUpdated(uint256 indexed serverId, string name, string icon, string description);
    event ServerTypeChanged(uint256 indexed serverId, ServerType newType);
    event ServerCategoryChanged(uint256 indexed serverId, string category);
    event MemberJoined(uint256 indexed serverId, address indexed member);
    event MemberLeft(uint256 indexed serverId, address indexed member);
    event InviteCodeCreated(uint256 indexed serverId, bytes32 indexed code, uint256 maxUses, uint256 expiresAt);
    event InviteCodeUsed(uint256 indexed serverId, bytes32 indexed code, address member);
    event InviteCodeRevoked(uint256 indexed serverId, bytes32 indexed code);
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);

    // ============ Custom Errors ============

    error ServerNotFound();
    error NotServerOwner();
    error InvalidServerType();
    error InvalidCategory();
    error InvalidName();
    error MaxServersReached();
    error MaxMembersReached();
    error AlreadyMember();
    error NotMember();
    error InvalidInviteCode();
    error InviteExpired();
    error InviteMaxUsesReached();
    error Unauthorized();

    // ============ Modifiers ============

    modifier onlyServerOwner(uint256 serverId) {
        if (_servers[serverId].owner != msg.sender) revert NotServerOwner();
        _;
    }

    // ============ Constructor ============

    constructor() ERC721("DiscordServers", "SERVER") Ownable() {}

    // ============ Server Creation ============

    /**
     * @notice Create a new server
     * @param name Server name
     * @param icon Server icon URL (IPFS)
     * @param description Server description
     * @param category Server category (Gaming, Dev, Art, etc.)
     * @param serverType Type of server (public/private/verified)
     * @return serverId The ID of the created server
     */
    function createServer(
        string calldata name,
        string calldata icon,
        string calldata description,
        string calldata category,
        ServerType serverType
    ) external override returns (uint256 serverId) {
        // Validate inputs
        if (bytes(name).length == 0 || bytes(name).length > 100) revert InvalidName();
        if (serverType == ServerType.None) revert InvalidServerType();
        if (bytes(category).length == 0) revert InvalidCategory();

        // Check max servers
        if (_ownerServerCount[msg.sender] >= MAX_SERVERS_PER_ACCOUNT) {
            revert MaxServersReached();
        }

        _serverIdCounter++;
        serverId = _serverIdCounter;

        // Create server
        _servers[serverId] = Server({
            id: serverId,
            owner: msg.sender,
            name: name,
            icon: icon,
            description: description,
            category: category,
            serverType: serverType,
            memberCount: 1,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            isActive: true
        });

        // Mint NFT to owner
        _safeMint(msg.sender, serverId);
        _ownerToServerId[msg.sender] = serverId;
        _ownerServerCount[msg.sender]++;

        // Add owner as first member
        _serverMembers[serverId].push(msg.sender);
        _memberServers[msg.sender].push(serverId);
        _memberIndex[serverId][msg.sender] = 0;

        // Add to category
        _categoryServers[category].push(serverId);

        // Add to all servers
        _allServers.push(serverId);
        _allServersIndex[serverId] = _allServers.length - 1;

        emit ServerCreated(serverId, msg.sender, name, category, serverType);
        return serverId;
    }

    /**
     * @notice Update server details
     */
    function updateServer(
        uint256 serverId,
        string calldata name,
        string calldata icon,
        string calldata description
    )
        external
        onlyServerOwner(serverId)
    {
        if (bytes(name).length == 0 || bytes(name).length > 100) revert InvalidName();

        _servers[serverId].name = name;
        _servers[serverId].icon = icon;
        _servers[serverId].description = description;
        _servers[serverId].updatedAt = block.timestamp;

        emit ServerUpdated(serverId, name, icon, description);
    }

    /**
     * @notice Change server type
     */
    function setServerType(uint256 serverId, ServerType serverType)
        external
        onlyServerOwner(serverId)
    {
        if (serverType == ServerType.None) revert InvalidServerType();

        _servers[serverId].serverType = serverType;
        _servers[serverId].updatedAt = block.timestamp;

        emit ServerTypeChanged(serverId, serverType);
    }

    /**
     * @notice Change server category
     */
    function setCategory(uint256 serverId, string calldata category)
        external
        onlyServerOwner(serverId)
    {
        if (bytes(category).length == 0) revert InvalidCategory();

        // Remove from old category
        string memory oldCategory = _servers[serverId].category;
        _removeFromCategory(oldCategory, serverId);

        // Add to new category
        _categoryServers[category].push(serverId);

        _servers[serverId].category = category;
        _servers[serverId].updatedAt = block.timestamp;

        emit ServerCategoryChanged(serverId, category);
    }

    // ============ Membership ============

    /**
     * @notice Join a public server
     */
    function joinServer(uint256 serverId)
        external
        override
    {
        Server storage server = _servers[serverId];
        if (!server.isActive || server.id != serverId) revert ServerNotFound();

        // Only public servers can be joined directly
        if (server.serverType != ServerType.Public) revert Unauthorized();

        _addMember(serverId, msg.sender);
    }

    /**
     * @notice Leave a server
     */
    function leaveServer(uint256 serverId)
        external
        override
    {
        Server storage server = _servers[serverId];
        if (!server.isActive || server.id != serverId) revert ServerNotFound();

        // Owner cannot leave their own server
        if (server.owner == msg.sender) revert Unauthorized();

        _removeMember(serverId, msg.sender);
    }

    /**
     * @notice Add a member to a server
     */
    function _addMember(uint256 serverId, address member) internal {
        // Check if already member
        if (_isMember(serverId, member)) revert AlreadyMember();

        Server storage server = _servers[serverId];
        if (server.memberCount >= MAX_MEMBERS_PER_SERVER) {
            revert MaxMembersReached();
        }

        // Add to server members
        _serverMembers[serverId].push(member);
        _memberIndex[serverId][member] = server.memberCount;

        // Add to member's server list
        _memberServers[member].push(serverId);

        server.memberCount++;
        server.updatedAt = block.timestamp;

        emit MemberJoined(serverId, member);
    }

    /**
     * @notice Remove a member from a server
     */
    function _removeMember(uint256 serverId, address member) internal {
        if (!_isMember(serverId, member)) revert NotMember();

        Server storage server = _servers[serverId];

        // Remove from server members array
        uint256 index = _memberIndex[serverId][member];
        uint256 lastIndex = server.memberCount - 1;

        if (index != lastIndex) {
            address lastMember = _serverMembers[serverId][lastIndex];
            _serverMembers[serverId][index] = lastMember;
            _memberIndex[serverId][lastMember] = index;
        }

        _serverMembers[serverId].pop();
        delete _memberIndex[serverId][member];

        // Remove from member's server list
        _removeFromMemberServers(member, serverId);

        server.memberCount--;
        server.updatedAt = block.timestamp;

        emit MemberLeft(serverId, member);
    }

    /**
     * @notice Kick a member from the server (owner/admin only)
     */
    function kickMember(uint256 serverId, address member, string calldata reason)
        external
        onlyServerOwner(serverId)
    {
        Server storage server = _servers[serverId];

        // Cannot kick owner
        if (member == server.owner) revert Unauthorized();

        _removeMember(serverId, member);
    }

    /**
     * @notice Remove server from member's server list
     */
    function _removeFromMemberServers(address member, uint256 serverId) internal {
        uint256[] storage servers = _memberServers[member];
        uint256 length = servers.length;

        for (uint256 i = 0; i < length; i++) {
            if (servers[i] == serverId) {
                // Move last element to this position
                uint256 lastIndex = length - 1;
                if (i != lastIndex) {
                    servers[i] = servers[lastIndex];
                }
                servers.pop();
                break;
            }
        }
    }

    /**
     * @notice Remove server from category list
     */
    function _removeFromCategory(string memory category, uint256 serverId) internal {
        uint256[] storage servers = _categoryServers[category];
        uint256 length = servers.length;

        for (uint256 i = 0; i < length; i++) {
            if (servers[i] == serverId) {
                // Move last element to this position
                uint256 lastIndex = length - 1;
                if (i != lastIndex) {
                    servers[i] = servers[lastIndex];
                }
                servers.pop();
                break;
            }
        }
    }

    // ============ Invite Codes ============

    /**
     * @notice Create an invite code
     */
    function createInviteCode(
        uint256 serverId,
        uint256 maxUses,
        uint256 expiresAt
    )
        external
        onlyServerOwner(serverId)
        returns (bytes32 code)
    {
        if (expiresAt <= block.timestamp) revert InvalidInviteCode();
        if (maxUses == 0) revert InvalidInviteCode();

        code = keccak256(abi.encodePacked(serverId, block.timestamp, msg.sender));

        _inviteCodes[code] = serverId;
        _inviteCreators[code] = msg.sender;

        emit InviteCodeCreated(serverId, code, maxUses, expiresAt);
    }

    /**
     * @notice Use an invite code to join a server
     */
    function useInviteCode(uint256 serverId, bytes32 code)
        external
        override
    {
        if (_inviteCodes[code] != serverId) revert InvalidInviteCode();

        Invite storage invite = _invites[code];

        // Check expiration
        if (invite.expiresAt > 0 && block.timestamp > invite.expiresAt) {
            revert InviteExpired();
        }

        // Check max uses
        if (invite.maxUses > 0 && invite.useCount >= invite.maxUses) {
            revert InviteMaxUsesReached();
        }

        // Add member
        _addMember(serverId, msg.sender);

        // Update invite
        invite.useCount++;

        emit InviteCodeUsed(serverId, code, msg.sender);
    }

    /**
     * @notice Revoke an invite code
     */
    function revokeInviteCode(uint256 serverId, bytes32 code)
        external
    {
        if (_inviteCreators[code] != msg.sender) revert Unauthorized();

        delete _inviteCodes[code];
        delete _inviteCreators[code];

        emit InviteCodeRevoked(serverId, code);
    }

    // ============ Platform Fees ============

    /**
     * @notice Update platform fee
     */
    function setPlatformFee(uint256 newFeeBps)
        external
        onlyOwner
    {
        if (newFeeBps > 1000) revert Unauthorized(); // Max 10%

        uint256 oldFee = platformFeeBps;
        platformFeeBps = newFeeBps;

        emit PlatformFeeUpdated(oldFee, newFeeBps);
    }

    // ============ View Functions ============

    /**
     * @notice Get server details
     */
    function getServer(uint256 serverId)
        external
        view
        override
        returns (Server memory)
    {
        if (!_servers[serverId].isActive) revert ServerNotFound();
        return _servers[serverId];
    }

    /**
     * @notice Get all servers in a category
     */
    function getServersByCategory(string calldata category)
        external
        view
        override
        returns (uint256[] memory)
    {
        return _categoryServers[category];
    }

    /**
     * @notice Get all active servers
     */
    function getAllServers()
        external
        view
        override
        returns (uint256[] memory)
    {
        return _allServers;
    }

    /**
     * @notice Get server members
     */
    function getServerMembers(uint256 serverId)
        external
        view
        override
        returns (address[] memory)
    {
        return _serverMembers[serverId];
    }

    /**
     * @notice Get servers for a member
     */
    function getMemberServers(address member)
        external
        view
        override
        returns (uint256[] memory)
    {
        return _memberServers[member];
    }

    /**
     * @notice Get server ID by owner
     */
    function getServerIdByOwner(address owner)
        external
        view
        returns (uint256)
    {
        return _ownerToServerId[owner];
    }

    /**
     * @notice Check if an address is a member of a server
     */
    function isMember(uint256 serverId, address member)
        external
        view
        override
        returns (bool)
    {
        return _isMember(serverId, member);
    }

    /**
     * @notice Get invite code details
     */
    function getInviteCode(bytes32 code)
        external
        view
        returns (uint256 serverId, uint256 maxUses, uint256 useCount, uint256 expiresAt)
    {
        serverId = _inviteCodes[code];

        if (serverId == 0) {
            return (0, 0, 0, 0);
        }

        Invite storage invite = _invites[code];

        return (
            serverId,
            invite.maxUses,
            invite.useCount,
            invite.expiresAt
        );
    }

    /**
     * @notice Get total server count
     */
    function getTotalServers()
        external
        view
        override
        returns (uint256)
    {
        return _allServers.length;
    }

    /**
     * @notice Deactivate a server (owner only)
     */
    function deactivateServer(uint256 serverId)
        external
        onlyServerOwner(serverId)
    {
        _servers[serverId].isActive = false;

        // Remove from active servers list
        uint256 index = _allServersIndex[serverId];
        uint256 lastIndex = _allServers.length - 1;

        if (index != lastIndex) {
            uint256 lastServerId = _allServers[lastIndex];
            _allServers[index] = lastServerId;
            _allServersIndex[lastServerId] = index;
        }

        _allServers.pop();
        delete _allServersIndex[serverId];

        // Burn NFT
        _burn(serverId);
    }

    // ============ Internal Functions ============

    function _isMember(uint256 serverId, address member) internal view returns (bool) {
        return _memberIndex[serverId][member] < _servers[serverId].memberCount;
    }

    // Required overrides
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function _burn(uint256 tokenId)
        internal
        override(ERC721, ERC721URIStorage)
    {
        super._burn(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
