// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/ai/AIAgentRegistry.sol";
import "../contracts/ai/IAIAgentRegistry.sol";

/**
 * @title AIAgentRegistryTest
 * @dev Test suite for AIAgentRegistry contract
 */
contract AIAgentRegistryTest is Test {
    AIAgentRegistry registry;
    IAIAgentRegistry.AgentType constant LLM = IAIAgentRegistry.AgentType.LLM;
    IAIAgentRegistry.AgentType constant AUTONOMOUS = IAIAgentRegistry.AgentType.Autonomous;
    IAIAgentRegistry.AgentType constant HYBRID = IAIAgentRegistry.AgentType.Hybrid;

    address owner = address(0x1);
    address overseer1 = address(0x2);
    address overseer2 = address(0x3);
    address spender = address(0x4);

    uint256 agentId1;
    uint256 agentId2;

    function setUp() public {
        vm.startPrank(owner);
        registry = new AIAgentRegistry();

        // Grant spender role for testing
        registry.grantRole(registry.SPENDER_ROLE(), spender);
        vm.stopPrank();

        // Register initial AI agents
        vm.prank(overseer1);
        agentId1 = registry.registerAIAgent(
            "ipfs://agent1",
            LLM,
            "gpt-4-turbo",
            10 ether,
            overseer1
        );

        vm.prank(overseer2);
        agentId2 = registry.registerAIAgent(
            "ipfs://agent2",
            AUTONOMOUS,
            "claude-3-opus",
            5 ether,
            overseer2
        );
    }

    // ============ Registration Tests ============

    function testInitialState() public {
        assertEq(registry.getTotalAIAgents(), 2);
        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(registry.hasRole(registry.SPENDER_ROLE(), owner));
        assertTrue(registry.hasRole(registry.SPENDER_ROLE(), spender));
    }

    function testRegisterAIAgent() public {
        address newOverseer = address(0x5);
        vm.prank(newOverseer);
        uint256 newAgentId = registry.registerAIAgent(
            "ipfs://agent3",
            HYBRID,
            "gemini-pro",
            15 ether,
            newOverseer
        );

        assertEq(newAgentId, 3);
        assertEq(registry.getTotalAIAgents(), 3);

        IAIAgentRegistry.AIAgent memory agent = registry.getAIAgent(newAgentId);
        assertEq(uint256(agent.agentType), uint256(HYBRID));
        assertEq(agent.modelId, "gemini-pro");
        assertEq(agent.monthlyBudget, 15 ether);
        assertEq(agent.overseer, newOverseer);
        assertTrue(agent.isActive);
    }

    function testRegisterAIAgentEmitsEvent() public {
        address newOverseer = address(0x5);

        vm.expectEmit(true, true, false, true);
        emit IAIAgentRegistry.AIAgentRegistered(
            3,
            HYBRID,
            "gemini-pro",
            15 ether,
            newOverseer
        );

        vm.prank(newOverseer);
        registry.registerAIAgent(
            "ipfs://agent3",
            HYBRID,
            "gemini-pro",
            15 ether,
            newOverseer
        );
    }

    function testCannotRegisterWithNoneType() public {
        vm.prank(overseer1);
        vm.expectRevert(IAIAgentRegistry.InvalidAgentType.selector);
        registry.registerAIAgent(
            "ipfs://bad",
            IAIAgentRegistry.AgentType.None,
            "model",
            1 ether,
            overseer1
        );
    }

    function testCannotRegisterWithZeroOverseer() public {
        vm.prank(overseer1);
        vm.expectRevert(IAIAgentRegistry.InvalidOverseer.selector);
        registry.registerAIAgent(
            "ipfs://bad",
            LLM,
            "model",
            1 ether,
            address(0)
        );
    }

    function testCannotRegisterWithZeroBudget() public {
        vm.prank(overseer1);
        vm.expectRevert(IAIAgentRegistry.InvalidBudget.selector);
        registry.registerAIAgent(
            "ipfs://bad",
            LLM,
            "model",
            0,
            overseer1
        );
    }

    // ============ Budget Management Tests ============

    function testUpdateBudget() public {
        vm.prank(overseer1);
        registry.updateBudget(agentId1, 20 ether);

        IAIAgentRegistry.AIAgent memory agent = registry.getAIAgent(agentId1);
        assertEq(agent.monthlyBudget, 20 ether);
    }

    function testUpdateBudgetEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit IAIAgentRegistry.BudgetUpdated(agentId1, 10 ether, 20 ether);

        vm.prank(overseer1);
        registry.updateBudget(agentId1, 20 ether);
    }

    function testCannotUpdateBudgetAsNonOverseer() public {
        vm.prank(overseer2);
        vm.expectRevert(IAIAgentRegistry.NotOverseer.selector);
        registry.updateBudget(agentId1, 20 ether);
    }

    function testCannotUpdateBudgetToZero() public {
        vm.prank(overseer1);
        vm.expectRevert(IAIAgentRegistry.InvalidBudget.selector);
        registry.updateBudget(agentId1, 0);
    }

    function testGetBudgetInfo() public {
        IAIAgentRegistry.BudgetInfo memory info = registry.getBudgetInfo(agentId1);

        assertEq(info.monthlyBudget, 10 ether);
        assertEq(info.spentThisMonth, 0);
        assertEq(info.remainingThisMonth, 10 ether);
        assertEq(info.lastReset, _getRegisteredTime(agentId1));
        assertEq(info.nextReset, _getRegisteredTime(agentId1) + 30 days);
    }

    // ============ Overseer Management Tests ============

    function testUpdateOverseer() public {
        address newOverseer = address(0x5);
        vm.prank(overseer1);
        registry.updateOverseer(agentId1, newOverseer);

        IAIAgentRegistry.AIAgent memory agent = registry.getAIAgent(agentId1);
        assertEq(agent.overseer, newOverseer);
    }

    function testUpdateOverseerEmitsEvent() public {
        address newOverseer = address(0x5);

        vm.expectEmit(true, true, false, true);
        emit IAIAgentRegistry.OverseerUpdated(agentId1, overseer1, newOverseer);

        vm.prank(overseer1);
        registry.updateOverseer(agentId1, newOverseer);
    }

    function testCannotUpdateOverseerAsNonOverseer() public {
        vm.prank(overseer2);
        vm.expectRevert(IAIAgentRegistry.NotOverseer.selector);
        registry.updateOverseer(agentId1, address(0x5));
    }

    function testCannotUpdateOverseerToZero() public {
        vm.prank(overseer1);
        vm.expectRevert(IAIAgentRegistry.InvalidOverseer.selector);
        registry.updateOverseer(agentId1, address(0));
    }

    function testIsOverseer() public {
        assertTrue(registry.isOverseer(agentId1, overseer1));
        assertFalse(registry.isOverseer(agentId1, overseer2));
    }

    // ============ Capabilities Management Tests ============

    function testUpdateCapabilities() public {
        string memory capabilities = '{"skills": ["solidity", "rust"], "experience": "5 years"}';

        vm.prank(overseer1);
        registry.updateCapabilities(agentId1, capabilities);

        IAIAgentRegistry.AIAgent memory agent = registry.getAIAgent(agentId1);
        assertEq(agent.capabilities, capabilities);
    }

    function testUpdateCapabilitiesEmitsEvent() public {
        string memory newCapabilities = '{"skills": ["solidity"]}';

        vm.expectEmit(true, false, false, true);
        emit IAIAgentRegistry.CapabilitiesUpdated(agentId1, "", newCapabilities);

        vm.prank(overseer1);
        registry.updateCapabilities(agentId1, newCapabilities);
    }

    function testCannotUpdateCapabilitiesAsNonOverseer() public {
        vm.prank(overseer2);
        vm.expectRevert(IAIAgentRegistry.NotOverseer.selector);
        registry.updateCapabilities(agentId1, '{"skills": ["solidity"]}');
    }

    function testCannotUpdateCapabilitiesToEmpty() public {
        vm.prank(overseer1);
        vm.expectRevert(IAIAgentRegistry.EmptyCapabilities.selector);
        registry.updateCapabilities(agentId1, "");
    }

    // ============ Activation Tests ============

    function testDeactivateAgent() public {
        vm.prank(overseer1);
        registry.deactivateAgent(agentId1);

        IAIAgentRegistry.AIAgent memory agent = registry.getAIAgent(agentId1);
        assertFalse(agent.isActive);
    }

    function testDeactivateAgentEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit IAIAgentRegistry.AgentDeactivated(agentId1);

        vm.prank(overseer1);
        registry.deactivateAgent(agentId1);
    }

    function testDeactivateAgentRemovesFromActiveList() public {
        vm.prank(overseer1);
        registry.deactivateAgent(agentId1);

        uint256[] memory activeAgents = registry.getActiveAIAgents();
        assertEq(activeAgents.length, 1);
        assertEq(activeAgents[0], agentId2);
    }

    function testCannotDeactivateAsNonOverseer() public {
        vm.prank(overseer2);
        vm.expectRevert(IAIAgentRegistry.NotOverseer.selector);
        registry.deactivateAgent(agentId1);
    }

    function testReactivateAgent() public {
        vm.prank(overseer1);
        registry.deactivateAgent(agentId1);

        vm.prank(overseer1);
        registry.reactivateAgent(agentId1);

        IAIAgentRegistry.AIAgent memory agent = registry.getAIAgent(agentId1);
        assertTrue(agent.isActive);
    }

    function testReactivateAgentEmitsEvent() public {
        vm.prank(overseer1);
        registry.deactivateAgent(agentId1);

        vm.expectEmit(true, false, false, true);
        emit IAIAgentRegistry.AgentReactivated(agentId1);

        vm.prank(overseer1);
        registry.reactivateAgent(agentId1);
    }

    function testReactivateAgentAddsToActiveList() public {
        vm.prank(overseer1);
        registry.deactivateAgent(agentId1);

        vm.prank(overseer1);
        registry.reactivateAgent(agentId1);

        uint256[] memory activeAgents = registry.getActiveAIAgents();
        assertEq(activeAgents.length, 2);
    }

    // ============ Spending Tests ============

    function testRecordSpending() public {
        vm.prank(spender);
        registry.recordSpending(agentId1, 1 ether);

        IAIAgentRegistry.BudgetInfo memory info = registry.getBudgetInfo(agentId1);
        assertEq(info.spentThisMonth, 1 ether);
        assertEq(info.remainingThisMonth, 9 ether);
    }

    function testRecordSpendingMultiple() public {
        vm.startPrank(spender);
        registry.recordSpending(agentId1, 1 ether);
        registry.recordSpending(agentId1, 2 ether);
        registry.recordSpending(agentId1, 3 ether);
        vm.stopPrank();

        IAIAgentRegistry.BudgetInfo memory info = registry.getBudgetInfo(agentId1);
        assertEq(info.spentThisMonth, 6 ether);
        assertEq(info.remainingThisMonth, 4 ether);
    }

    function testCannotRecordSpendingOverBudget() public {
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAIAgentRegistry.BudgetExceeded.selector,
                6 ether,
                5 ether
            )
        );
        registry.recordSpending(agentId2, 6 ether); // agent2 has 5 ether budget
    }

    function testCannotRecordSpendingAsNonSpender() public {
        vm.prank(overseer1);
        vm.expectRevert(); // AccessControl error
        registry.recordSpending(agentId1, 1 ether);
    }

    function testCannotRecordSpendingForInactiveAgent() public {
        vm.prank(overseer1);
        registry.deactivateAgent(agentId1);

        vm.prank(spender);
        vm.expectRevert(IAIAgentRegistry.AgentNotActive.selector);
        registry.recordSpending(agentId1, 1 ether);
    }

    function testMonthlyBudgetReset() public {
        // Spend some amount
        vm.prank(spender);
        registry.recordSpending(agentId1, 5 ether);

        // Fast forward past month
        vm.warp(block.timestamp + 31 days);

        // Reset budget
        registry.resetMonthlyBudget(agentId1);

        IAIAgentRegistry.BudgetInfo memory info = registry.getBudgetInfo(agentId1);
        assertEq(info.spentThisMonth, 0);
        assertEq(info.remainingThisMonth, 10 ether);
    }

    function testMonthlyBudgetResetEmitsEvent() public {
        vm.prank(spender);
        registry.recordSpending(agentId1, 5 ether);

        vm.warp(block.timestamp + 31 days);

        vm.expectEmit(true, false, false, true);
        emit IAIAgentRegistry.MonthlyBudgetReset(agentId1, 5 ether);

        registry.resetMonthlyBudget(agentId1);
    }

    function testSpendingAfterMonthReset() public {
        // Spend in first month
        vm.prank(spender);
        registry.recordSpending(agentId1, 8 ether);

        // Fast forward to next month
        vm.warp(block.timestamp + 31 days);

        // Should be able to spend again
        vm.prank(spender);
        registry.recordSpending(agentId1, 5 ether);

        IAIAgentRegistry.BudgetInfo memory info = registry.getBudgetInfo(agentId1);
        assertEq(info.spentThisMonth, 5 ether);
        assertEq(info.remainingThisMonth, 5 ether);
    }

    // ============ Query Tests ============

    function testGetAIAgent() public {
        IAIAgentRegistry.AIAgent memory agent = registry.getAIAgent(agentId1);

        assertEq(agent.agentId, agentId1);
        assertEq(uint256(agent.agentType), uint256(LLM));
        assertEq(agent.modelId, "gpt-4-turbo");
        assertEq(agent.monthlyBudget, 10 ether);
        assertEq(agent.overseer, overseer1);
        assertTrue(agent.isActive);
    }

    function testGetAIAgentNotFound() public {
        vm.expectRevert(IAIAgentRegistry.AgentNotFound.selector);
        registry.getAIAgent(999);
    }

    function testIsAIAgent() public {
        assertTrue(registry.isAIAgent(agentId1));
        assertTrue(registry.isAIAgent(agentId2));
        assertFalse(registry.isAIAgent(999));
    }

    function testGetActiveAIAgents() public {
        uint256[] memory activeAgents = registry.getActiveAIAgents();

        assertEq(activeAgents.length, 2);
        assertEq(activeAgents[0], agentId1);
        assertEq(activeAgents[1], agentId2);
    }

    function testGetAgentsByType() public {
        // Register another LLM agent
        address newOverseer = address(0x5);
        vm.prank(newOverseer);
        registry.registerAIAgent(
            "ipfs://agent3",
            LLM,
            "gpt-3.5-turbo",
            3 ether,
            newOverseer
        );

        uint256[] memory llmAgents = registry.getAgentsByType(LLM);
        assertEq(llmAgents.length, 2);

        uint256[] memory autonomousAgents = registry.getAgentsByType(AUTONOMOUS);
        assertEq(autonomousAgents.length, 1);
    }

    // ============ Access Control Tests ============

    function testPauserCanDeactivateAgent() public {
        // Grant pauser role
        vm.startPrank(owner);
        registry.grantRole(registry.PAUSER_ROLE(), overseer2);
        vm.stopPrank();

        vm.prank(overseer2);
        registry.deactivateAgent(agentId1); // overseer2 is not overseer of agent1 but has pauser role

        IAIAgentRegistry.AIAgent memory agent = registry.getAIAgent(agentId1);
        assertFalse(agent.isActive);
    }

    function testPauserCanReactivateAgent() public {
        vm.prank(overseer1);
        registry.deactivateAgent(agentId1);

        // Grant pauser role
        vm.startPrank(owner);
        registry.grantRole(registry.PAUSER_ROLE(), overseer2);
        vm.stopPrank();

        vm.prank(overseer2);
        registry.reactivateAgent(agentId1);

        IAIAgentRegistry.AIAgent memory agent = registry.getAIAgent(agentId1);
        assertTrue(agent.isActive);
    }

    // ============ Fuzz Tests ============

    function testFuzzBudgetUpdates(uint256 newBudget) public {
        // Bound to reasonable values (1 gwei to 1000 ether)
        newBudget = bound(newBudget, 1 gwei, 1000 ether);

        vm.prank(overseer1);
        registry.updateBudget(agentId1, newBudget);

        IAIAgentRegistry.AIAgent memory agent = registry.getAIAgent(agentId1);
        assertEq(agent.monthlyBudget, newBudget);
    }

    function testFuzzSpending(uint256 amount1, uint256 amount2) public {
        // Bound to reasonable values
        amount1 = bound(amount1, 0, 5 ether);
        amount2 = bound(amount2, 0, 5 ether);

        vm.startPrank(spender);
        if (amount1 > 0) {
            if (amount1 <= 10 ether) {
                registry.recordSpending(agentId1, amount1);
            }
        }
        if (amount2 > 0) {
            if (amount1 + amount2 <= 10 ether) {
                registry.recordSpending(agentId1, amount2);
            }
        }
        vm.stopPrank();

        IAIAgentRegistry.BudgetInfo memory info = registry.getBudgetInfo(agentId1);
        uint256 expectedSpent = (amount1 <= 10 ether ? amount1 : 0) +
                                ((amount1 + amount2 <= 10 ether && amount2 > 0) ? amount2 : 0);
        assertEq(info.spentThisMonth, expectedSpent);
    }

    // ============ Helper Functions ============

    function _getRegisteredTime(uint256 agentId) internal view returns (uint256) {
        IAIAgentRegistry.AIAgent memory agent = registry.getAIAgent(agentId);
        return agent.registeredAt;
    }
}
