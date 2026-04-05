// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

/**
 * @title IChannelContract
 * @dev Interface for Channel contract
 */
interface IChannelContract {
    // ============ Enums ============

    enum ChannelType {
        None,       // 0
        Text,       // 1 - Text channel
        Voice,      // 2 - Voice channel
        Category,   // 3 - Channel category (folder)
        Announcement, // 4 - Announcement channel (read-only for most)
        Stage       // 5 - Stage channel (like Discord Stage)
    }

    enum ChannelPermission {
        Read,
        Write,
        Connect,
        Speak,
        Manage
    }

    // ============ Structs ============

    struct Channel {
        uint256 id;
        uint256 serverId;
        string name;
        ChannelType channelType;
        uint256 parentId;        // Category ID (0 if no category)
        uint256 position;        // Display position
        uint256 permissions;     // Permission overrides
        bool isNSFW;            // Age-restricted
        string topic;           // Channel description
        uint256 messageCount;   // For text channels
        uint256 createdAt;
        uint256 updatedAt;
        bool isActive;
    }

    struct Message {
        uint256 id;
        uint256 channelId;
        address sender;
        string content;         // On-chain: plaintext or IPFS hash
        bytes32 contentHash;    // Hash of content for verification
        uint256 replyTo;        // Message ID being replied to (0 if none)
        bool isPinned;
        bool isEdited;
        uint256 timestamp;
    }

    struct VoiceState {
        address participant;
        uint256 channelId;
        bool isMuted;
        bool isDeafened;
        uint256 joinedAt;
    }

    // ============ Channel Management ============

    function createChannel(
        uint256 serverId,
        string calldata name,
        ChannelType channelType,
        uint256 parentId,
        uint256 position
    ) external returns (uint256 channelId);

    function updateChannel(
        uint256 serverId,
        uint256 channelId,
        string calldata name,
        uint256 parentId,
        uint256 position,
        string calldata topic
    ) external;

    function deleteChannel(uint256 serverId, uint256 channelId) external;

    function setChannelPermissions(
        uint256 serverId,
        uint256 channelId,
        uint256 permissions
    ) external;

    // ============ Messages (Text Channels) ============

    function sendMessage(
        uint256 channelId,
        string calldata content,
        uint256 replyTo
    ) external returns (uint256 messageId);

    function editMessage(
        uint256 channelId,
        uint256 messageId,
        string calldata content
    ) external;

    function deleteMessage(uint256 channelId, uint256 messageId) external;

    function pinMessage(uint256 channelId, uint256 messageId) external;

    function unpinMessage(uint256 channelId, uint256 messageId) external;

    // ============ Voice Channels ============

    function joinVoiceChannel(uint256 channelId) external;

    function leaveVoiceChannel(uint256 channelId) external;

    function setVoiceState(
        uint256 channelId,
        bool isMuted,
        bool isDeafened
    ) external;

    // ============ View Functions ============

    function getChannel(uint256 channelId)
        external
        view
        returns (Channel memory);

    function getServerChannels(uint256 serverId)
        external
        view
        returns (uint256[] memory);

    function getCategoryChannels(uint256 categoryId)
        external
        view
        returns (uint256[] memory);

    function getMessage(uint256 channelId, uint256 messageId)
        external
        view
        returns (Message memory);

    function getChannelMessages(
        uint256 channelId,
        uint256 offset,
        uint256 limit
    ) external view returns (Message[] memory);

    function getPinnedMessages(uint256 channelId)
        external
        view
        returns (uint256[] memory);

    function getVoiceParticipants(uint256 channelId)
        external
        view
        returns (address[] memory);

    function getVoiceState(address participant)
        external
        view
        returns (VoiceState memory);

    // ============ Permission Checking ============

    function hasChannelPermission(
        uint256 channelId,
        address member,
        ChannelPermission permission
    ) external view returns (bool);

    function canReadChannel(uint256 channelId, address member)
        external
        view
        returns (bool);

    function canWriteInChannel(uint256 channelId, address member)
        external
        view
        returns (bool);

    // ============ Events ============

    event ChannelCreated(
        uint256 indexed serverId,
        uint256 indexed channelId,
        string name,
        ChannelType channelType,
        uint256 parentId
    );

    event ChannelUpdated(
        uint256 indexed serverId,
        uint256 indexed channelId,
        string name
    );

    event ChannelDeleted(uint256 indexed serverId, uint256 indexed channelId);

    event MessageSent(
        uint256 indexed channelId,
        uint256 indexed messageId,
        address indexed sender,
        string content
    );

    event MessageEdited(
        uint256 indexed channelId,
        uint256 indexed messageId,
        string newContent
    );

    event MessageDeleted(
        uint256 indexed channelId,
        uint256 indexed messageId
    );

    event MessagePinned(
        uint256 indexed channelId,
        uint256 indexed messageId
    );

    event MessageUnpinned(
        uint256 indexed channelId,
        uint256 indexed messageId
    );

    event VoiceJoined(
        uint256 indexed channelId,
        address indexed participant
    );

    event VoiceLeft(
        uint256 indexed channelId,
        address indexed participant
    );

    event VoiceStateChanged(
        uint256 indexed channelId,
        address indexed participant,
        bool isMuted,
        bool isDeafened
    );
}
