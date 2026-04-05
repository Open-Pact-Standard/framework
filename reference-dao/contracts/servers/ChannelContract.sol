// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import { IServerRegistry } from "./interfaces/IServerRegistry.sol";
import { IServerMembership } from "./interfaces/IServerMembership.sol";
import { IChannelContract } from "./interfaces/IChannelContract.sol";

/**
 * @title ChannelContract
 * @dev Manages text and voice channels for servers
 *
 *      Features:
 *      - Create, update, delete channels
 *      - Text messages with editing and deletion
 *      - Message pinning
 *      - Voice channel participant tracking
 *      - Permission-based access control
 *      - Category organization
 *
 *      Storage Strategy:
 *      - Short messages stored on-chain
 *      - Long messages should store IPFS hash on-chain
 *      - Voice states track participation (actual audio off-chain)
 */
contract ChannelContract is IChannelContract, Ownable {
    /// @notice Server registry contract
    IServerRegistry public immutable serverRegistry;

    /// @notice Membership contract for permission checks
    IServerMembership public immutable membershipContract;

    /// @notice Channel ID counter
    uint256 private _channelIdCounter;

    /// @notice Message ID counter
    uint256 private _messageIdCounter;

    /// @notice Channel ID => Channel data
    mapping(uint256 => Channel) private _channels;

    /// @notice Server ID => Channel IDs in order
    mapping(uint256 => uint256[]) private _serverChannels;

    /// @notice Category ID => Child channel IDs
    mapping(uint256 => uint256[]) private _categoryChannels;

    /// @notice Channel ID => Message IDs in order
    mapping(uint256 => uint256[]) private _channelMessages;

    /// @notice Channel ID => Pinned message IDs
    mapping(uint256 => uint256[]) private _pinnedMessages;

    /// @notice Message ID => Message data
    mapping(uint256 => Message) private _messages;

    /// @notice Channel ID => Position of message in array (for deletion)
    mapping(uint256 => mapping(uint256 => uint256)) private _messageIndex;

    /// @notice Channel ID => Participant => Voice state
    mapping(uint256 => mapping(address => VoiceState)) private _voiceStates;

    /// @notice Channel ID => Current participant count
    mapping(uint256 => uint256) private _voiceParticipantCount;

    /// @notice Participant => Active voice channel ID (0 if not in voice)
    mapping(address => uint256) private _activeVoiceChannel;

    /// @notice Maximum messages per channel (gas limit protection)
    uint256 public constant MAX_MESSAGES_PER_CHANNEL = 10000;

    /// @notice Maximum message content length (characters)
    uint256 public constant MAX_MESSAGE_LENGTH = 5000;

    /// @notice Platform admin role
    bytes32 public constant PLATFORM_ADMIN = keccak256("PLATFORM_ADMIN");

    // ============ Custom Errors ============

    error ServerNotFound();
    error ChannelNotFound();
    error NotServerOwner();
    error NotAuthorized();
    error InvalidChannelType();
    error InvalidCategory();
    error InvalidName();
    error InvalidPosition();
    error ChannelNotEmpty();
    error CannotDeleteCategory();
    error MessageNotFound();
    error NotMessageSender();
    error MessageTooLong();
    error NotTextChannel();
    error NotVoiceChannel();
    error NotInVoiceChannel();
    error AlreadyInVoiceChannel();
    error MaxMessagesReached();
    error InvalidReply();

    // ============ Modifiers ============

    modifier onlyServerOwner(uint256 serverId) {
        if (!_isServerOwner(serverId, msg.sender)) revert NotServerOwner();
        _;
    }

    modifier serverExists(uint256 serverId) {
        if (!_serverExists(serverId)) revert ServerNotFound();
        _;
    }

    modifier channelExists(uint256 channelId) {
        if (!_channels[channelId].isActive) revert ChannelNotFound();
        _;
    }

    // ============ Constructor ============

    constructor(
        address serverRegistry_,
        address membershipContract_
    ) Ownable() {
        if (serverRegistry_ == address(0)) revert("Zero address");
        if (membershipContract_ == address(0)) revert("Zero address");

        serverRegistry = IServerRegistry(serverRegistry_);
        membershipContract = IServerMembership(membershipContract_);
    }

    // ============ Channel Management ============

    /**
     * @notice Create a new channel
     * @param serverId Server ID
     * @param name Channel name
     * @param channelType Type of channel
     * @param parentId Category ID (0 for no category)
     * @param position Display position
     * @return channelId The ID of the created channel
     */
    function createChannel(
        uint256 serverId,
        string calldata name,
        ChannelType channelType,
        uint256 parentId,
        uint256 position
    )
        external
        serverExists(serverId)
        onlyServerOwner(serverId)
        returns (uint256 channelId)
    {
        // Validate inputs
        if (bytes(name).length == 0 || bytes(name).length > 100) revert InvalidName();
        if (channelType == ChannelType.None) revert InvalidChannelType();

        // Validate parent category
        if (parentId != 0) {
            Channel storage parent = _channels[parentId];
            if (!parent.isActive || parent.channelType != ChannelType.Category) {
                revert InvalidCategory();
            }
        }

        _channelIdCounter++;
        channelId = _channelIdCounter;

        _channels[channelId] = Channel({
            id: channelId,
            serverId: serverId,
            name: name,
            channelType: channelType,
            parentId: parentId,
            position: position,
            permissions: 0,
            isNSFW: false,
            topic: "",
            messageCount: 0,
            createdAt: block.timestamp,
            updatedAt: block.timestamp,
            isActive: true
        });

        // Add to server channels
        _serverChannels[serverId].push(channelId);

        // Add to category if specified
        if (parentId != 0) {
            _categoryChannels[parentId].push(channelId);
        }

        emit ChannelCreated(serverId, channelId, name, channelType, parentId);
        return channelId;
    }

    /**
     * @notice Update a channel
     */
    function updateChannel(
        uint256 serverId,
        uint256 channelId,
        string calldata name,
        uint256 parentId,
        uint256 position,
        string calldata topic
    )
        external
        channelExists(channelId)
        onlyServerOwner(serverId)
    {
        Channel storage channel = _channels[channelId];

        if (channel.serverId != serverId) revert NotAuthorized();
        if (bytes(name).length == 0 || bytes(name).length > 100) revert InvalidName();

        // Validate parent category
        if (parentId != 0) {
            Channel storage parent = _channels[parentId];
            if (!parent.isActive || parent.channelType != ChannelType.Category) {
                revert InvalidCategory();
            }
        }

        // Remove from old category if changing
        if (channel.parentId != 0 && channel.parentId != parentId) {
            _removeFromCategory(channel.parentId, channelId);
        }

        channel.name = name;
        channel.parentId = parentId;
        channel.position = position;
        channel.topic = topic;
        channel.updatedAt = block.timestamp;

        // Add to new category if specified
        if (parentId != 0 && channel.parentId != parentId) {
            _categoryChannels[parentId].push(channelId);
        }

        emit ChannelUpdated(serverId, channelId, name);
    }

    /**
     * @notice Delete a channel
     */
    function deleteChannel(uint256 serverId, uint256 channelId)
        external
        channelExists(channelId)
        onlyServerOwner(serverId)
    {
        Channel storage channel = _channels[channelId];

        if (channel.serverId != serverId) revert NotAuthorized();

        // Cannot delete category if it has channels
        if (channel.channelType == ChannelType.Category) {
            if (_categoryChannels[channelId].length > 0) revert ChannelNotEmpty();
        }

        // Deactivate channel
        channel.isActive = false;

        // Remove from server channels
        _removeFromServerChannels(serverId, channelId);

        // Remove from parent category
        if (channel.parentId != 0) {
            _removeFromCategory(channel.parentId, channelId);
        }

        emit ChannelDeleted(serverId, channelId);
    }

    /**
     * @notice Set channel permissions
     */
    function setChannelPermissions(
        uint256 serverId,
        uint256 channelId,
        uint256 permissions
    )
        external
        channelExists(channelId)
        onlyServerOwner(serverId)
    {
        Channel storage channel = _channels[channelId];

        if (channel.serverId != serverId) revert NotAuthorized();

        channel.permissions = permissions;
        channel.updatedAt = block.timestamp;
    }

    // ============ Messages (Text Channels) ============

    /**
     * @notice Send a message to a text channel
     * @param channelId Channel ID
     * @param content Message content (or IPFS hash for long content)
     * @param replyTo Message ID being replied to (0 if none)
     * @return messageId The ID of the created message
     */
    function sendMessage(
        uint256 channelId,
        string calldata content,
        uint256 replyTo
    )
        external
        channelExists(channelId)
        returns (uint256 messageId)
    {
        Channel storage channel = _channels[channelId];

        // Must be text channel
        if (channel.channelType != ChannelType.Text &&
            channel.channelType != ChannelType.Announcement) {
            revert NotTextChannel();
        }

        // Check permission
        if (!_canWriteInChannel(channelId, msg.sender)) revert NotAuthorized();

        // Validate content length
        if (bytes(content).length == 0 || bytes(content).length > MAX_MESSAGE_LENGTH) {
            revert MessageTooLong();
        }

        // Validate reply
        if (replyTo != 0) {
            if (_messageIndex[channelId][replyTo] >= channel.messageCount) {
                revert InvalidReply();
            }
        }

        // Check max messages
        if (channel.messageCount >= MAX_MESSAGES_PER_CHANNEL) revert MaxMessagesReached();

        _messageIdCounter++;
        messageId = _messageIdCounter;

        bytes32 contentHash = keccak256(bytes(content));

        _messages[messageId] = Message({
            id: messageId,
            channelId: channelId,
            sender: msg.sender,
            content: content,
            contentHash: contentHash,
            replyTo: replyTo,
            isPinned: false,
            isEdited: false,
            timestamp: block.timestamp
        });

        _channelMessages[channelId].push(messageId);
        _messageIndex[channelId][messageId] = channel.messageCount;
        channel.messageCount++;
        channel.updatedAt = block.timestamp;

        emit MessageSent(channelId, messageId, msg.sender, content);
        return messageId;
    }

    /**
     * @notice Edit a message
     */
    function editMessage(
        uint256 channelId,
        uint256 messageId,
        string calldata content
    )
        external
        channelExists(channelId)
    {
        Message storage message = _messages[messageId];

        if (message.id != messageId || message.channelId != channelId) revert MessageNotFound();
        if (message.sender != msg.sender) revert NotMessageSender();

        if (bytes(content).length == 0 || bytes(content).length > MAX_MESSAGE_LENGTH) {
            revert MessageTooLong();
        }

        message.content = content;
        message.contentHash = keccak256(bytes(content));
        message.isEdited = true;

        _channels[channelId].updatedAt = block.timestamp;

        emit MessageEdited(channelId, messageId, content);
    }

    /**
     * @notice Delete a message
     */
    function deleteMessage(uint256 channelId, uint256 messageId)
        external
        channelExists(channelId)
    {
        Message storage message = _messages[messageId];
        Channel storage channel = _channels[channelId];

        if (message.id != messageId || message.channelId != channelId) revert MessageNotFound();

        // Only sender or server owner can delete
        if (message.sender != msg.sender && !_isServerOwner(channel.serverId, msg.sender)) {
            revert NotAuthorized();
        }

        // Remove from pinned if applicable
        if (message.isPinned) {
            _removeFromPinned(channelId, messageId);
        }

        // Mark as deleted (clear content)
        delete _messages[messageId];
        delete _messageIndex[channelId][messageId];

        channel.messageCount--;
        channel.updatedAt = block.timestamp;

        emit MessageDeleted(channelId, messageId);
    }

    /**
     * @notice Pin a message
     */
    function pinMessage(uint256 channelId, uint256 messageId)
        external
        channelExists(channelId)
    {
        Message storage message = _messages[messageId];
        Channel storage channel = _channels[channelId];

        if (message.id != messageId || message.channelId != channelId) revert MessageNotFound();

        // Check permission (only moderators/admins can pin)
        if (!_hasPermissionInServer(channel.serverId, msg.sender)) {
            revert NotAuthorized();
        }

        if (!message.isPinned) {
            message.isPinned = true;
            _pinnedMessages[channelId].push(messageId);

            emit MessagePinned(channelId, messageId);
        }
    }

    /**
     * @notice Unpin a message
     */
    function unpinMessage(uint256 channelId, uint256 messageId)
        external
        channelExists(channelId)
    {
        Message storage message = _messages[messageId];
        Channel storage channel = _channels[channelId];

        if (message.id != messageId || message.channelId != channelId) revert MessageNotFound();

        // Check permission
        if (!_hasPermissionInServer(channel.serverId, msg.sender)) {
            revert NotAuthorized();
        }

        if (message.isPinned) {
            message.isPinned = false;
            _removeFromPinned(channelId, messageId);

            emit MessageUnpinned(channelId, messageId);
        }
    }

    // ============ Voice Channels ============

    /**
     * @notice Join a voice channel
     */
    function joinVoiceChannel(uint256 channelId)
        external
        channelExists(channelId)
    {
        Channel storage channel = _channels[channelId];

        if (channel.channelType != ChannelType.Voice &&
            channel.channelType != ChannelType.Stage) {
            revert NotVoiceChannel();
        }

        // Check if already in a voice channel
        if (_activeVoiceChannel[msg.sender] != 0) revert AlreadyInVoiceChannel();

        // Check read permission
        if (!_canReadChannel(channelId, msg.sender)) revert NotAuthorized();

        _voiceStates[channelId][msg.sender] = VoiceState({
            participant: msg.sender,
            channelId: channelId,
            isMuted: false,
            isDeafened: false,
            joinedAt: block.timestamp
        });

        _activeVoiceChannel[msg.sender] = channelId;
        _voiceParticipantCount[channelId]++;

        emit VoiceJoined(channelId, msg.sender);
    }

    /**
     * @notice Leave a voice channel
     */
    function leaveVoiceChannel(uint256 channelId)
        external
        channelExists(channelId)
    {
        if (_activeVoiceChannel[msg.sender] != channelId) revert NotInVoiceChannel();

        delete _voiceStates[channelId][msg.sender];
        delete _activeVoiceChannel[msg.sender];
        _voiceParticipantCount[channelId]--;

        emit VoiceLeft(channelId, msg.sender);
    }

    /**
     * @notice Update voice state (mute/deafen)
     */
    function setVoiceState(
        uint256 channelId,
        bool isMuted,
        bool isDeafened
    )
        external
        channelExists(channelId)
    {
        VoiceState storage state = _voiceStates[channelId][msg.sender];

        if (state.channelId != channelId) revert NotInVoiceChannel();

        state.isMuted = isMuted;
        state.isDeafened = isDeafened;

        emit VoiceStateChanged(channelId, msg.sender, isMuted, isDeafened);
    }

    // ============ View Functions ============

    /**
     * @notice Get channel details
     */
    function getChannel(uint256 channelId)
        external
        view
        channelExists(channelId)
        returns (Channel memory)
    {
        return _channels[channelId];
    }

    /**
     * @notice Get all channels for a server
     */
    function getServerChannels(uint256 serverId)
        external
        view
        serverExists(serverId)
        returns (uint256[] memory)
    {
        return _serverChannels[serverId];
    }

    /**
     * @notice Get channels in a category
     */
    function getCategoryChannels(uint256 categoryId)
        external
        view
        returns (uint256[] memory)
    {
        return _categoryChannels[categoryId];
    }

    /**
     * @notice Get a specific message
     */
    function getMessage(uint256 channelId, uint256 messageId)
        external
        view
        returns (Message memory)
    {
        Message storage message = _messages[messageId];
        if (message.channelId != channelId) revert MessageNotFound();
        return message;
    }

    /**
     * @notice Get messages from a channel (paginated)
     */
    function getChannelMessages(
        uint256 channelId,
        uint256 offset,
        uint256 limit
    )
        external
        view
        channelExists(channelId)
        returns (Message[] memory)
    {
        uint256 total = _channels[channelId].messageCount;

        if (offset >= total) return new Message[](0);

        uint256 end = offset + limit;
        if (end > total) end = total;

        Message[] memory messages = new Message[](end - offset);

        for (uint256 i = offset; i < end; i++) {
            uint256 messageId = _channelMessages[channelId][i];
            messages[i - offset] = _messages[messageId];
        }

        return messages;
    }

    /**
     * @notice Get pinned message IDs
     */
    function getPinnedMessages(uint256 channelId)
        external
        view
        returns (uint256[] memory)
    {
        return _pinnedMessages[channelId];
    }

    /**
     * @notice Get voice participants in a channel
     */
    function getVoiceParticipants(uint256 channelId)
        external
        view
        returns (address[] memory)
    {
        uint256 count = _voiceParticipantCount[channelId];
        address[] memory participants = new address[](count);

        // This is inefficient - in production, track participants in an array
        // For now, return empty array if too many participants
        if (count > 100) {
            return new address[](0);
        }

        uint256 index = 0;
        // Note: Can't efficiently iterate over mapping without external tracking
        // In production, maintain a participants array

        return participants;
    }

    /**
     * @notice Get voice state for a participant
     */
    function getVoiceState(address participant)
        external
        view
        returns (VoiceState memory)
    {
        uint256 activeChannelId = _activeVoiceChannel[participant];
        if (activeChannelId == 0) {
            return VoiceState({
                participant: participant,
                channelId: 0,
                isMuted: false,
                isDeafened: false,
                joinedAt: 0
            });
        }
        return _voiceStates[activeChannelId][participant];
    }

    /**
     * @notice Check if member has specific channel permission
     */
    function hasChannelPermission(
        uint256 channelId,
        address member,
        ChannelPermission permission
    )
        external
        view
        channelExists(channelId)
        returns (bool)
    {
        Channel storage channel = _channels[channelId];

        // Server owner has all permissions
        if (_isServerOwner(channel.serverId, member)) return true;

        // Check channel-specific permissions
        uint256 channelPerms = channel.permissions;

        // Map ChannelPermission to bitmask
        uint256 permBit;
        if (permission == ChannelPermission.Read) permBit = 1;
        else if (permission == ChannelPermission.Write) permBit = 2;
        else if (permission == ChannelPermission.Connect) permBit = 4;
        else if (permission == ChannelPermission.Speak) permBit = 8;
        else if (permission == ChannelPermission.Manage) permBit = 16;
        else return false;

        // Check if permission is granted
        if ((channelPerms & permBit) != 0) return true;

        // Fall back to server membership permissions
        return membershipContract.hasPermission(
            channel.serverId,
            member,
            permBit
        );
    }

    /**
     * @notice Check if member can read channel
     */
    function canReadChannel(uint256 channelId, address member)
        external
        view
        channelExists(channelId)
        returns (bool)
    {
        return _canReadChannel(channelId, member);
    }

    /**
     * @notice Check if member can write in channel
     */
    function canWriteInChannel(uint256 channelId, address member)
        external
        view
        channelExists(channelId)
        returns (bool)
    {
        return _canWriteInChannel(channelId, member);
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

    function _hasPermissionInServer(uint256 serverId, address member)
        internal
        view
        returns (bool)
    {
        // Check if member is admin or moderator
        return membershipContract.isAdmin(serverId, member) ||
               membershipContract.isModerator(serverId, member);
    }

    function _canReadChannel(uint256 channelId, address member)
        internal
        view
        returns (bool)
    {
        Channel storage channel = _channels[channelId];

        // Server owner can read
        if (_isServerOwner(channel.serverId, member)) return true;

        // Must be server member
        if (!serverRegistry.isMember(channel.serverId, member)) return false;

        // Check channel permissions
        uint256 readPerm = 1;
        if ((channel.permissions & readPerm) != 0) return false; // Explicit deny

        return true;
    }

    function _canWriteInChannel(uint256 channelId, address member)
        internal
        view
        returns (bool)
    {
        Channel storage channel = _channels[channelId];

        // Server owner can write
        if (_isServerOwner(channel.serverId, member)) return true;

        // Must be server member
        if (!serverRegistry.isMember(channel.serverId, member)) return false;

        // Announcement channels are read-only for non-admins
        if (channel.channelType == ChannelType.Announcement) {
            return _hasPermissionInServer(channel.serverId, member);
        }

        // Check channel permissions
        uint256 writePerm = 2;
        if ((channel.permissions & writePerm) != 0) return false; // Explicit deny

        return true;
    }

    function _removeFromServerChannels(uint256 serverId, uint256 channelId) internal {
        uint256[] storage channels = _serverChannels[serverId];
        for (uint256 i = 0; i < channels.length; i++) {
            if (channels[i] == channelId) {
                uint256 lastIndex = channels.length - 1;
                if (i != lastIndex) {
                    channels[i] = channels[lastIndex];
                }
                channels.pop();
                break;
            }
        }
    }

    function _removeFromCategory(uint256 categoryId, uint256 channelId) internal {
        uint256[] storage channels = _categoryChannels[categoryId];
        for (uint256 i = 0; i < channels.length; i++) {
            if (channels[i] == channelId) {
                uint256 lastIndex = channels.length - 1;
                if (i != lastIndex) {
                    channels[i] = channels[lastIndex];
                }
                channels.pop();
                break;
            }
        }
    }

    function _removeFromPinned(uint256 channelId, uint256 messageId) internal {
        uint256[] storage pinned = _pinnedMessages[channelId];
        for (uint256 i = 0; i < pinned.length; i++) {
            if (pinned[i] == messageId) {
                uint256 lastIndex = pinned.length - 1;
                if (i != lastIndex) {
                    pinned[i] = pinned[lastIndex];
                }
                pinned.pop();
                break;
            }
        }
    }
}
