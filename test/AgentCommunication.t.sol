// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/ai/AgentCommunication.sol";
import "../contracts/ai/AIAgentRegistry.sol";
import "../contracts/ai/IAIAgentRegistry.sol";
import "../contracts/ai/IAgentCommunication.sol";

/**
 * @title AgentCommunicationTest
 * @dev Test suite for AgentCommunication contract
 */
contract AgentCommunicationTest is Test {
    AgentCommunication comm;
    AIAgentRegistry aiRegistry;

    address owner = address(0x1);
    address overseer1 = address(0x2);
    address overseer2 = address(0x3);
    address overseer3 = address(0x4);

    uint256 agentId1;
    uint256 agentId2;
    uint256 agentId3;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy AI registry
        aiRegistry = new AIAgentRegistry();

        // Deploy communication
        comm = new AgentCommunication(address(aiRegistry));

        // Grant processor role to overseers (so agents can process their own messages)
        aiRegistry.grantRole(aiRegistry.SPENDER_ROLE(), address(comm));

        vm.stopPrank();

        // Register AI agents
        vm.prank(overseer1);
        agentId1 = aiRegistry.registerAIAgent(
            "ipfs://agent1",
            IAIAgentRegistry.AgentType.LLM,
            "gpt-4",
            100 ether,
            overseer1
        );

        vm.prank(overseer2);
        agentId2 = aiRegistry.registerAIAgent(
            "ipfs://agent2",
            IAIAgentRegistry.AgentType.Autonomous,
            "claude-3",
            50 ether,
            overseer2
        );

        vm.prank(overseer3);
        agentId3 = aiRegistry.registerAIAgent(
            "ipfs://agent3",
            IAIAgentRegistry.AgentType.Hybrid,
            "gemini-pro",
            75 ether,
            overseer3
        );
    }

    // ============ Initial State Tests ============

    function testInitialState() public {
        assertEq(address(comm.aiRegistry()), address(aiRegistry));
        assertTrue(comm.hasRole(comm.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(comm.hasRole(comm.PROCESSOR_ROLE(), owner));
    }

    // ============ Send Message Tests ============

    function testSendMessage() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.prank(overseer1); // agentId1
        uint256 messageId = comm.sendMessage(agentId2, "requestHelp", '{"task": "audit"}', expiresAt);

        assertEq(messageId, 1);

        IAgentCommunication.Message memory message = comm.getMessage(messageId);
        assertEq(message.fromAgentId, agentId1);
        assertEq(message.toAgentId, agentId2);
        assertEq(message.method, "requestHelp");
        assertEq(message.params, '{"task": "audit"}');
        assertFalse(message.processed);
        assertEq(message.expiresAt, expiresAt);
    }

    function testSendMessageEmitsEvents() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.expectEmit(true, true, true, false);
        emit IAgentCommunication.MessageSent(1, agentId1, agentId2, "testMethod");

        vm.expectEmit(true, false, true, false);
        emit IAgentCommunication.MessageReceived(1, agentId2);

        vm.prank(overseer1);
        comm.sendMessage(agentId2, "testMethod", '{}', expiresAt);
    }

    function testCannotSendToNonexistentAgent() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.prank(overseer1);
        vm.expectRevert(IAgentCommunication.AgentNotFound.selector);
        comm.sendMessage(999, "test", '{}', expiresAt);
    }

    function testCannotSendToInactiveAgent() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.prank(overseer3); // overseer3 is the overseer of agentId3
        aiRegistry.deactivateAgent(agentId3);

        vm.prank(overseer1);
        vm.expectRevert(IAgentCommunication.AgentNotActive.selector);
        comm.sendMessage(agentId3, "test", '{}', expiresAt);
    }

    function testCannotSendToSelf() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.prank(overseer1);
        vm.expectRevert(IAgentCommunication.CannotSendToSelf.selector);
        comm.sendMessage(agentId1, "test", '{}', expiresAt);
    }

    function testCannotSendWithEmptyMethod() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.prank(overseer1);
        vm.expectRevert(IAgentCommunication.EmptyMethod.selector);
        comm.sendMessage(agentId2, "", '{}', expiresAt);
    }

    function testCannotSendWithInvalidExpiration() public {
        // Too short
        vm.prank(overseer1);
        vm.expectRevert(IAgentCommunication.InvalidParams.selector);
        comm.sendMessage(agentId2, "test", '{}', block.timestamp + 10 minutes);

        // Too long
        vm.prank(overseer1);
        vm.expectRevert(IAgentCommunication.InvalidParams.selector);
        comm.sendMessage(agentId2, "test", '{}', block.timestamp + 31 days);
    }

    function testGetMessage() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.prank(overseer1);
        uint256 messageId = comm.sendMessage(agentId2, "test", '{"value": 42}', expiresAt);

        IAgentCommunication.Message memory message = comm.getMessage(messageId);
        assertEq(message.messageId, messageId);
        assertEq(message.fromAgentId, agentId1);
        assertEq(message.toAgentId, agentId2);
        assertEq(message.method, "test");
        assertEq(message.params, '{"value": 42}');
    }

    function testGetMessageNotFound() public {
        vm.expectRevert(IAgentCommunication.MessageNotFound.selector);
        comm.getMessage(999);
    }

    // ============ Process Message Tests ============

    function testProcessMessage() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.prank(overseer1);
        uint256 messageId = comm.sendMessage(agentId2, "test", '{}', expiresAt);

        // Process the message
        vm.prank(overseer2);
        (bool success, bytes memory response) = comm.processMessage(messageId);

        assertTrue(success);
        assertEq(response, abi.encodePacked(uint256(1)));

        IAgentCommunication.Message memory message = comm.getMessage(messageId);
        assertTrue(message.processed);
    }

    function testProcessMessageEmitsEvent() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.prank(overseer1);
        uint256 messageId = comm.sendMessage(agentId2, "test", '{}', expiresAt);

        vm.expectEmit(true, false, false, true);
        emit IAgentCommunication.MessageProcessed(messageId, true, abi.encodePacked(uint256(1)));

        vm.prank(overseer2);
        comm.processMessage(messageId);
    }

    function testCannotProcessAsNonRecipient() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.prank(overseer1);
        uint256 messageId = comm.sendMessage(agentId2, "test", '{}', expiresAt);

        vm.prank(overseer1);
        vm.expectRevert(IAgentCommunication.NotAuthorized.selector);
        comm.processMessage(messageId);
    }

    function testCannotProcessExpiredMessage() public {
        uint256 expiresAt = block.timestamp + 1 hours;

        vm.prank(overseer1);
        uint256 messageId = comm.sendMessage(agentId2, "test", '{}', expiresAt);

        // Fast forward past expiration
        vm.warp(block.timestamp + 2 hours);

        vm.prank(overseer2);
        vm.expectRevert(IAgentCommunication.MessageExpired.selector);
        comm.processMessage(messageId);
    }

    function testCannotProcessTwice() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.prank(overseer1);
        uint256 messageId = comm.sendMessage(agentId2, "test", '{}', expiresAt);

        vm.prank(overseer2);
        comm.processMessage(messageId);

        vm.prank(overseer2);
        vm.expectRevert(IAgentCommunication.AlreadyProcessed.selector);
        comm.processMessage(messageId);
    }

    // ============ Response Tests ============

    function testRespondToMessage() public {
        uint256 expiresAt = block.timestamp + 1 days;
        bytes memory response = abi.encodePacked(uint256(42));

        vm.prank(overseer1);
        uint256 messageId = comm.sendMessage(agentId2, "test", '{}', expiresAt);

        vm.prank(overseer2);
        comm.respondToMessage(messageId, response);

        IAgentCommunication.Message memory message = comm.getMessage(messageId);
        assertEq(message.response, response);
    }

    function testCannotRespondAsNonRecipient() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.prank(overseer1);
        uint256 messageId = comm.sendMessage(agentId2, "test", '{}', expiresAt);

        vm.prank(overseer1);
        vm.expectRevert(IAgentCommunication.NotAuthorized.selector);
        comm.respondToMessage(messageId, hex"01");
    }

    // ============ Broadcast Tests ============

    function testBroadcastMessage() public {
        uint256 expiresAt = block.timestamp + 1 days;
        uint256[] memory recipients = new uint256[](2);
        recipients[0] = agentId2;
        recipients[1] = agentId3;

        vm.prank(overseer1);
        uint256[] memory messageIds = comm.broadcastMessage(recipients, "broadcast", '{}', expiresAt);

        assertEq(messageIds.length, 2);
        assertEq(messageIds[0], 1);
        assertEq(messageIds[1], 2);

        // Verify both messages exist
        IAgentCommunication.Message memory msg1 = comm.getMessage(messageIds[0]);
        IAgentCommunication.Message memory msg2 = comm.getMessage(messageIds[1]);

        assertEq(msg1.fromAgentId, agentId1);
        assertEq(msg1.toAgentId, agentId2);
        assertEq(msg2.fromAgentId, agentId1);
        assertEq(msg2.toAgentId, agentId3);
    }

    function testCannotBroadcastToEmptyArray() public {
        uint256 expiresAt = block.timestamp + 1 days;
        uint256[] memory recipients = new uint256[](0);

        vm.prank(overseer1);
        vm.expectRevert(IAgentCommunication.InvalidRecipient.selector);
        comm.broadcastMessage(recipients, "test", '{}', expiresAt);
    }

    function testCannotBroadcastTooMany() public {
        uint256 expiresAt = block.timestamp + 1 days;
        uint256[] memory recipients = new uint256[](51);

        vm.prank(overseer1);
        vm.expectRevert(IAgentCommunication.InvalidParams.selector);
        comm.broadcastMessage(recipients, "test", '{}', expiresAt);
    }

    // ============ Pending Messages Tests ============

    function testGetPendingMessages() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.startPrank(overseer1);
        comm.sendMessage(agentId2, "test1", '{}', expiresAt);
        comm.sendMessage(agentId2, "test2", '{}', expiresAt);
        vm.stopPrank();

        vm.prank(overseer2);
        IAgentCommunication.Message[] memory pending = comm.getPendingMessages(agentId2, 10);

        assertEq(pending.length, 2);
        assertEq(pending[0].messageId, 1);
        assertEq(pending[0].method, "test1");
        assertEq(pending[1].messageId, 2);
        assertEq(pending[1].method, "test2");
    }

    function testGetPendingMessagesFiltersProcessed() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.startPrank(overseer1);
        comm.sendMessage(agentId2, "test1", '{}', expiresAt);
        comm.sendMessage(agentId2, "test2", '{}', expiresAt);
        vm.stopPrank();

        // Process first message
        vm.prank(overseer2);
        comm.processMessage(1);

        vm.prank(overseer2);
        IAgentCommunication.Message[] memory pending = comm.getPendingMessages(agentId2, 10);

        assertEq(pending.length, 1);
        assertEq(pending[0].messageId, 2);
    }

    function testGetPendingMessagesFiltersExpired() public {
        uint256 expiresAt = block.timestamp + 1 hours;

        vm.prank(overseer1);
        uint256 msg1 = comm.sendMessage(agentId2, "test1", '{}', expiresAt);

        // Fast forward past expiration
        vm.warp(block.timestamp + 2 hours);

        vm.prank(overseer2);
        IAgentCommunication.Message[] memory pending = comm.getPendingMessages(agentId2, 10);

        // Expired messages are filtered out in view function
        assertEq(pending.length, 0);

        // But the message still exists with processed=false
        IAgentCommunication.Message memory message = comm.getMessage(msg1);
        assertFalse(message.processed);
    }

    function testGetPendingMessagesLimit() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.prank(overseer1);
        comm.sendMessage(agentId2, "test1", '{}', expiresAt);

        vm.prank(overseer2);
        IAgentCommunication.Message[] memory pending = comm.getPendingMessages(agentId2, 1);

        assertEq(pending.length, 1);
    }

    // ============ Message Stats Tests ============

    function testGetMessageStats() public {
        uint256 expiresAt = block.timestamp + 1 days;

        // Send messages
        vm.startPrank(overseer1);
        comm.sendMessage(agentId2, "test1", '{}', expiresAt);
        comm.sendMessage(agentId2, "test2", '{}', expiresAt);
        vm.stopPrank();

        vm.prank(overseer3);
        comm.sendMessage(agentId2, "test3", '{}', expiresAt);

        (uint256 pending, uint256 total) = comm.getMessageStats(agentId2);

        assertEq(pending, 3);
        assertEq(total, 3);
    }

    function testGetMessageStatsAfterProcessing() public {
        uint256 expiresAt = block.timestamp + 1 days;

        vm.startPrank(overseer1);
        comm.sendMessage(agentId2, "test1", '{}', expiresAt);
        comm.sendMessage(agentId2, "test2", '{}', expiresAt);
        vm.stopPrank();

        // Process one message
        vm.prank(overseer2);
        comm.processMessage(1);

        (uint256 pending, uint256 total) = comm.getMessageStats(agentId2);

        assertEq(pending, 1);
        assertEq(total, 2);
    }

    // ============ Can Receive Tests ============

    function testCanReceive() public {
        assertTrue(comm.canReceive(agentId1));
        assertTrue(comm.canReceive(agentId2));
        assertTrue(comm.canReceive(agentId3));
    }

    function testCannotReceiveWhenInactive() public {
        vm.prank(overseer3);
        aiRegistry.deactivateAgent(agentId3);

        assertFalse(comm.canReceive(agentId3));
    }

    function testCannotReceiveWhenQueueFull() public {
        // Fill up the queue to MAX_PENDING (100)
        uint256 expiresAt = block.timestamp + 1 days;

        vm.startPrank(overseer1);
        for (uint256 i = 0; i < 100; i++) {
            comm.sendMessage(agentId2, string(abi.encodePacked(i)), '{}', expiresAt);
        }
        vm.stopPrank();

        assertFalse(comm.canReceive(agentId2));
    }

    // ============ Cleanup Tests ============

    function testCleanupExpiredMessages() public {
        uint256 expiresAt = block.timestamp + 1 hours;

        // Send messages that will expire
        vm.startPrank(overseer1);
        comm.sendMessage(agentId2, "test1", '{}', expiresAt);
        comm.sendMessage(agentId2, "test2", '{}', expiresAt);
        vm.stopPrank();

        // Fast forward past expiration
        vm.warp(block.timestamp + 2 hours);

        // Cleanup
        vm.prank(overseer2);
        uint256 cleaned = comm.cleanupExpiredMessages(agentId2);

        assertEq(cleaned, 2);

        // Verify stats updated
        (uint256 pending, uint256 total) = comm.getMessageStats(agentId2);
        assertEq(pending, 0);
        assertEq(total, 2);
    }

    function testCleanupEmitsEvent() public {
        uint256 expiresAt = block.timestamp + 1 hours;

        vm.prank(overseer1);
        comm.sendMessage(agentId2, "test1", '{}', expiresAt);

        vm.warp(block.timestamp + 2 hours);

        vm.expectEmit(true, false, false, true);
        emit IAgentCommunication.MessageExpiredEvent(1);

        vm.prank(overseer2);
        comm.cleanupExpiredMessages(agentId2);
    }

    function testCannotCleanupAsUnauthorized() public {
        uint256 expiresAt = block.timestamp + 1 hours;

        vm.prank(overseer1);
        comm.sendMessage(agentId2, "test1", '{}', expiresAt);

        vm.warp(block.timestamp + 2 hours);

        vm.prank(overseer1); // overseer1 is not the recipient
        vm.expectRevert(IAgentCommunication.NotAuthorized.selector);
        comm.cleanupExpiredMessages(agentId2);
    }

    // ============ Fuzz Tests ============

    function testFuzzMessageExpiration(uint256 timeOffset) public {
        // Bound to reasonable range (-1 day to +31 days)
        timeOffset = bound(timeOffset, 1 days, 31 days);

        // Only test valid offsets (must be at least 1 hour in future)
        if (timeOffset < 1 hours) {
            return;
        }

        uint256 expiresAt = block.timestamp + timeOffset;

        // Should succeed if within valid range
        if (timeOffset <= 30 days) {
            vm.prank(overseer1);
            comm.sendMessage(agentId2, "test", '{}', expiresAt);
        } else {
            vm.prank(overseer1);
            vm.expectRevert(IAgentCommunication.InvalidParams.selector);
            comm.sendMessage(agentId2, "test", '{}', expiresAt);
        }
    }
}
