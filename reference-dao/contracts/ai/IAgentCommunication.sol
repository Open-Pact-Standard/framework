// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title IAgentCommunication
 * @dev Interface for agent-to-agent communication
 *      Enables AI agents to send messages and collaborate
 */
interface IAgentCommunication {
    /**
     * @dev Message structure for agent communication
     */
    struct Message {
        uint256 messageId;         // Unique message ID
        uint256 fromAgentId;        // Sender agent ID
        uint256 toAgentId;          // Recipient agent ID
        string method;              // Method/action to perform
        string params;              // JSON-encoded parameters
        uint256 nonce;              // For replay protection
        uint256 timestamp;         // When message was sent
        uint256 expiresAt;         // When message expires
        bool processed;             // Whether message has been processed
        bytes response;             // Response data (if any)
    }

    // ============ Events ============

    event MessageSent(
        uint256 indexed messageId,
        uint256 indexed fromAgentId,
        uint256 indexed toAgentId,
        string method
    );

    event MessageReceived(
        uint256 indexed messageId,
        uint256 indexed toAgentId
    );

    event MessageProcessed(
        uint256 indexed messageId,
        bool success,
        bytes response
    );

    event MessageExpiredEvent(uint256 indexed messageId);

    // ============ Errors ============

    error AgentNotFound();
    error AgentNotActive();
    error InvalidRecipient();
    error CannotSendToSelf();
    error MessageExpired();
    error InvalidParams();
    error NotAuthorized();
    error MessageNotFound();
    error AlreadyProcessed();
    error EmptyMethod();
    error InvalidNonce();

    // ============ Message Functions ============

    /**
     * @notice Send a message to another agent
     * @param toAgentId Recipient agent ID
     * @param method Method/action to perform
     * @param params JSON-encoded parameters
     * @param expiresAt When the message expires
     * @return messageId The new message ID
     */
    function sendMessage(
        uint256 toAgentId,
        string calldata method,
        string calldata params,
        uint256 expiresAt
    ) external returns (uint256 messageId);

    /**
     * @notice Process a pending message
     * @param messageId The message ID
     * @return success Whether processing succeeded
     * @return response Response data
     */
    function processMessage(uint256 messageId)
        external
        returns (bool success, bytes memory response);

    /**
     * @notice Send a response to a message
     * @param messageId Original message ID
     * @param response Response data
     */
    function respondToMessage(uint256 messageId, bytes calldata response) external;

    /**
     * @notice Batch send messages to multiple agents
     * @param toAgentIds Array of recipient agent IDs
     * @param method Method/action to perform
     * @param params JSON-encoded parameters
     * @param expiresAt When messages expire
     * @return messageIds Array of new message IDs
     */
    function broadcastMessage(
        uint256[] calldata toAgentIds,
        string calldata method,
        string calldata params,
        uint256 expiresAt
    ) external returns (uint256[] memory messageIds);

    // ============ View Functions ============

    /**
     * @notice Get a message by ID
     * @param messageId The message ID
     * @return message The message data
     */
    function getMessage(uint256 messageId) external view returns (Message memory);

    /**
     * @notice Get pending messages for an agent
     * @param agentId The agent ID
     * @param limit Maximum number of messages to return
     * @return messages Array of pending messages
     */
    function getPendingMessages(uint256 agentId, uint256 limit)
        external
        view
        returns (Message[] memory);

    /**
     * @notice Get message count for an agent
     * @param agentId The agent ID
     * @return pending Number of pending messages
     * @return total Total messages received
     */
    function getMessageStats(uint256 agentId)
        external
        view
        returns (uint256 pending, uint256 total);

    /**
     * @notice Check if agent can receive messages
     * @param agentId The agent ID
     * @return True if agent can receive
     */
    function canReceive(uint256 agentId) external view returns (bool);
}
