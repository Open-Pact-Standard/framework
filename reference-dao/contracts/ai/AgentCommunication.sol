// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./IAgentCommunication.sol";
import "./IAIAgentRegistry.sol";

/**
 * @title AgentCommunication
 * @dev Agent-to-agent communication system
 *      Enables AI agents to send messages and collaborate
 *
 *      Features:
 *      - Async message passing between agents
 *      - Message expiration and replay protection
 *      - Batch/broadcast messaging
 *      - Response handling
 */
contract AgentCommunication is IAgentCommunication, Ownable, AccessControl {
    using Counters for Counters.Counter;

    /// @notice Role for message processing
    bytes32 public constant PROCESSOR_ROLE = keccak256("PROCESSOR_ROLE");

    /// @notice Maximum message params length (to prevent gas issues)
    uint256 public constant MAX_PARAMS_LENGTH = 10000;

    /// @notice Maximum pending messages per agent
    uint256 public constant MAX_PENDING = 100;

    /// @notice Minimum message expiration time (1 hour)
    uint256 public constant MIN_EXPIRATION = 1 hours;

    /// @notice Maximum message expiration time (30 days)
    uint256 public constant MAX_EXPIRATION = 30 days;

    /// @notice AI Agent Registry reference
    IAIAgentRegistry public immutable aiRegistry;

    /// @notice Message ID => Message data
    mapping(uint256 => Message) private _messages;

    /// @notice Agent ID => Array of pending message IDs
    mapping(uint256 => uint256[]) private _pendingMessages;

    /// @notice Message ID => Index in _pendingMessages (for removal)
    mapping(uint256 => mapping(uint256 => uint256)) private _pendingMessageIndex;

    /// @notice (Agent ID, Nonce) => Used nonces (for replay protection)
    mapping(uint256 => mapping(uint256 => bool)) private _usedNonces;

    /// @notice Agent ID => Total messages received
    mapping(uint256 => uint256) private _totalMessages;

    /// @notice Message ID => Agent who sent response (if any)
    mapping(uint256 => address) private _responders;

    // ============ Constructor ============

    constructor(address aiRegistry_) Ownable() {
        if (aiRegistry_ == address(0)) {
            revert InvalidParams();
        }

        aiRegistry = IAIAgentRegistry(aiRegistry_);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PROCESSOR_ROLE, msg.sender);
    }

    // ============ Message Functions ============

    /**
     * @inheritdoc IAgentCommunication
     */
    function sendMessage(
        uint256 toAgentId,
        string calldata method,
        string calldata params,
        uint256 expiresAt
    ) external override returns (uint256 messageId) {
        return _sendMessage(msg.sender, toAgentId, method, params, expiresAt);
    }

    /**
     * @dev Internal function to send a message
     */
    function _sendMessage(
        address sender,
        uint256 toAgentId,
        string calldata method,
        string calldata params,
        uint256 expiresAt
    ) internal returns (uint256 messageId) {
        // Validate sender
        uint256 fromAgentId = aiRegistry.getAgentId(sender);
        if (fromAgentId == 0) {
            revert AgentNotFound();
        }

        // Validate recipient
        if (!aiRegistry.isAIAgent(toAgentId)) {
            revert AgentNotFound();
        }

        IAIAgentRegistry.AIAgent memory toAgent = aiRegistry.getAIAgent(toAgentId);
        if (!toAgent.isActive) {
            revert AgentNotActive();
        }

        if (fromAgentId == toAgentId) {
            revert CannotSendToSelf();
        }

        if (bytes(method).length == 0) {
            revert EmptyMethod();
        }

        if (bytes(params).length > MAX_PARAMS_LENGTH) {
            revert InvalidParams();
        }

        // Validate expiration
        if (expiresAt < block.timestamp + MIN_EXPIRATION) {
            revert InvalidParams();
        }
        if (expiresAt > block.timestamp + MAX_EXPIRATION) {
            revert InvalidParams();
        }

        // Check recipient's pending queue
        if (_pendingMessages[toAgentId].length >= MAX_PENDING) {
            revert InvalidParams();
        }

        // Generate message ID
        _messageIdCounter.increment();
        messageId = _messageIdCounter.current();

        // Generate nonce
        uint256 nonce = uint256(keccak256(abi.encodePacked(
            fromAgentId,
            toAgentId,
            block.timestamp,
            messageId
        )));

        // Store message
        _messages[messageId] = Message({
            messageId: messageId,
            fromAgentId: fromAgentId,
            toAgentId: toAgentId,
            method: method,
            params: params,
            nonce: nonce,
            timestamp: block.timestamp,
            expiresAt: expiresAt,
            processed: false,
            response: ""
        });

        // Add to recipient's pending queue
        _pendingMessages[toAgentId].push(messageId);
        _pendingMessageIndex[toAgentId][messageId] = _pendingMessages[toAgentId].length - 1;

        // Track stats
        _totalMessages[toAgentId]++;

        emit MessageSent(messageId, fromAgentId, toAgentId, method);
        emit MessageReceived(messageId, toAgentId);

        return messageId;
    }

    /**
     * @inheritdoc IAgentCommunication
     */
    function processMessage(uint256 messageId)
        external
        override
        returns (bool success, bytes memory response)
    {
        if (!_messages[messageId].processed) {
            if (_messages[messageId].messageId == 0) {
                revert MessageNotFound();
            }

            if (_messages[messageId].expiresAt < block.timestamp) {
                _messages[messageId].processed = true;
                emit MessageExpiredEvent(messageId);
                revert MessageExpired();
            }

            // Verify the caller is the recipient
            uint256 callerAgentId = aiRegistry.getAgentId(msg.sender);
            if (callerAgentId == 0 || callerAgentId != _messages[messageId].toAgentId) {
                revert NotAuthorized();
            }

            // Mark as processed
            _messages[messageId].processed = true;

            // Remove from pending queue
            _removeFromPending(_messages[messageId].toAgentId, messageId);

            // Default success response (empty)
            response = abi.encodePacked(uint256(1)); // 1 = success

            emit MessageProcessed(messageId, true, response);

            return (true, response);
        }

        revert AlreadyProcessed();
    }

    /**
     * @inheritdoc IAgentCommunication
     */
    function respondToMessage(uint256 messageId, bytes calldata response) external override {
        if (_messages[messageId].messageId == 0) {
            revert MessageNotFound();
        }

        // Verify the caller is the recipient
        uint256 callerAgentId = aiRegistry.getAgentId(msg.sender);
        if (callerAgentId == 0 || callerAgentId != _messages[messageId].toAgentId) {
            revert NotAuthorized();
        }

        // Store response
        _messages[messageId].response = response;
        _responders[messageId] = msg.sender;

        emit MessageProcessed(messageId, true, response);
    }

    /**
     * @inheritdoc IAgentCommunication
     */
    function broadcastMessage(
        uint256[] calldata toAgentIds,
        string calldata method,
        string calldata params,
        uint256 expiresAt
    ) external override returns (uint256[] memory messageIds) {
        if (toAgentIds.length == 0) {
            revert InvalidRecipient();
        }

        if (toAgentIds.length > 50) {
            revert InvalidParams();
        }

        uint256[] memory ids = new uint256[](toAgentIds.length);

        for (uint256 i = 0; i < toAgentIds.length; i++) {
            ids[i] = _sendMessage(msg.sender, toAgentIds[i], method, params, expiresAt);
        }

        return ids;
    }

    // ============ View Functions ============

    /**
     * @inheritdoc IAgentCommunication
     */
    function getMessage(uint256 messageId) external view override returns (Message memory) {
        if (_messages[messageId].messageId == 0) {
            revert MessageNotFound();
        }
        return _messages[messageId];
    }

    /**
     * @inheritdoc IAgentCommunication
     */
    function getPendingMessages(uint256 agentId, uint256 limit)
        external
        view
        override
        returns (Message[] memory)
    {
        if (!aiRegistry.isAIAgent(agentId)) {
            revert AgentNotFound();
        }

        uint256[] memory pendingIds = _pendingMessages[agentId];

        // First pass: count valid (unprocessed and not expired) messages
        uint256 validCount = 0;
        uint256 maxCount = pendingIds.length < limit ? pendingIds.length : limit;

        for (uint256 i = 0; i < pendingIds.length && validCount < maxCount; i++) {
            uint256 msgId = pendingIds[i];
            if (!_messages[msgId].processed && _messages[msgId].expiresAt >= block.timestamp) {
                validCount++;
            }
        }

        // Create array with exact size needed
        Message[] memory messages = new Message[](validCount);

        // Second pass: populate array
        uint256 index = 0;
        for (uint256 i = 0; i < pendingIds.length && index < validCount; i++) {
            uint256 msgId = pendingIds[i];
            if (!_messages[msgId].processed && _messages[msgId].expiresAt >= block.timestamp) {
                messages[index] = _messages[msgId];
                index++;
            }
        }

        return messages;
    }

    /**
     * @inheritdoc IAgentCommunication
     */
    function getMessageStats(uint256 agentId)
        external
        view
        override
        returns (uint256 pending, uint256 total)
    {
        if (!aiRegistry.isAIAgent(agentId)) {
            revert AgentNotFound();
        }

        // Count actual pending (unprocessed and not expired)
        uint256 actualPending = 0;
        uint256[] memory pendingIds = _pendingMessages[agentId];

        for (uint256 i = 0; i < pendingIds.length; i++) {
            uint256 msgId = pendingIds[i];
            if (!_messages[msgId].processed && _messages[msgId].expiresAt >= block.timestamp) {
                actualPending++;
            }
        }

        return (actualPending, _totalMessages[agentId]);
    }

    /**
     * @inheritdoc IAgentCommunication
     */
    function canReceive(uint256 agentId) external view override returns (bool) {
        if (!aiRegistry.isAIAgent(agentId)) {
            return false;
        }

        IAIAgentRegistry.AIAgent memory agent = aiRegistry.getAIAgent(agentId);
        if (!agent.isActive) {
            return false;
        }

        // Check if pending queue is full
        return _pendingMessages[agentId].length < MAX_PENDING;
    }

    /**
     * @notice Clean up expired messages for an agent
     * @param agentId The agent ID
     * @return count Number of messages cleaned up
     */
    function cleanupExpiredMessages(uint256 agentId) external returns (uint256 count) {
        if (!aiRegistry.isAIAgent(agentId)) {
            revert AgentNotFound();
        }

        // Only recipient or admin can cleanup
        uint256 callerAgentId = aiRegistry.getAgentId(msg.sender);
        if (callerAgentId != agentId && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAuthorized();
        }

        uint256[] memory pendingIds = _pendingMessages[agentId];
        uint256 removed = 0;

        for (uint256 i = pendingIds.length; i > 0; i--) {
            uint256 msgId = pendingIds[i - 1];

            if (_messages[msgId].expiresAt < block.timestamp) {
                // Mark as processed
                _messages[msgId].processed = true;
                // Emit event
                emit MessageExpiredEvent(msgId);
                // Remove from pending array
                _removeFromPending(agentId, msgId);
                removed++;
            }
        }

        return removed;
    }

    // ============ Internal Functions ============

    /**
     * @dev Remove message from pending queue
     */
    function _removeFromPending(uint256 agentId, uint256 messageId) internal {
        uint256 index = _pendingMessageIndex[agentId][messageId];

        if (index < _pendingMessages[agentId].length) {
            uint256 lastIndex = _pendingMessages[agentId].length - 1;

            if (index != lastIndex) {
                uint256 lastMsgId = _pendingMessages[agentId][lastIndex];
                _pendingMessages[agentId][index] = lastMsgId;
                _pendingMessageIndex[agentId][lastMsgId] = index;
            }

            _pendingMessages[agentId].pop();
            delete _pendingMessageIndex[agentId][messageId];
        }
    }

    // ============ Required Override ============

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Message ID counter
    Counters.Counter private _messageIdCounter;
}
