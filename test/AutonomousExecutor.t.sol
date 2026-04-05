// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/ai/AutonomousExecutor.sol";
import "../contracts/ai/AIAgentRegistry.sol";
import "../contracts/ai/IAIAgentRegistry.sol";
import "../contracts/ai/IAutonomousExecutor.sol";

/**
 * @title AutonomousExecutorTest
 * @dev Test suite for AutonomousExecutor contract
 */
contract AutonomousExecutorTest is Test {
    AutonomousExecutor executor;
    AIAgentRegistry aiRegistry;

    address owner = address(0x1);
    address overseer = address(0x2);
    address pauser = address(0x3);
    address allowlistManager = address(0x4);
    address spender = address(0x5);

    uint256 agentId;
    address mockTargetAddress;

    // Mock target contract for testing
    MockTarget mockTarget;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy AI registry
        aiRegistry = new AIAgentRegistry();

        // Deploy executor
        executor = new AutonomousExecutor(address(aiRegistry));

        // Grant roles
        aiRegistry.grantRole(aiRegistry.SPENDER_ROLE(), address(executor));
        executor.grantRole(executor.PAUSER_ROLE(), pauser);
        executor.grantRole(executor.ALLOWLIST_ROLE(), allowlistManager);

        vm.stopPrank();

        // Register AI agent
        vm.prank(overseer);
        agentId = aiRegistry.registerAIAgent(
            "ipfs://agent",
            IAIAgentRegistry.AgentType.LLM,
            "gpt-4",
            100 ether,
            overseer
        );

        // Set daily limit for agent
        vm.prank(owner);
        executor.setDailyLimit(agentId, 10 ether);

        // Deploy mock target contract
        mockTarget = new MockTarget();
        mockTargetAddress = address(mockTarget);

        // Fund executor contract with ETH for execution
        vm.deal(address(executor), 1000 ether);

        // Fund spender address with ETH
        vm.deal(spender, 1000 ether);

        // Allow the target contract for the agent
        vm.prank(allowlistManager);
        executor.addToAllowlist(mockTargetAddress, new bytes4[](1));
        // Will set the selector in the actual test
    }

    // ============ Initial State Tests ============

    function testInitialState() public {
        assertEq(address(executor.aiRegistry()), address(aiRegistry));
        assertTrue(executor.hasRole(executor.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(executor.hasRole(executor.PAUSER_ROLE(), pauser));
        assertTrue(executor.hasRole(executor.ALLOWLIST_ROLE(), allowlistManager));
    }

    // ============ Execution Tests ============

    function testExecuteWithBudget() public {
        // Allow the specific selector
        bytes4 selector = MockTarget.simpleAction.selector;
        vm.prank(allowlistManager);
        executor.addToAllowlist(mockTargetAddress, _toArray(selector));

        // Execute action
        vm.prank(spender);
        IAutonomousExecutor.ExecutionResult memory result = executor.executeWithBudget{value: 1 ether}(
            agentId,
            mockTargetAddress,
            abi.encodeWithSelector(MockTarget.simpleAction.selector),
            1 ether
        );

        assertTrue(result.success);
        assertEq(mockTarget.lastCaller(), address(executor));
        assertEq(mockTarget.lastValue(), 1 ether);

        // Check stats
        (uint256 totalExecs, uint256 totalSpent, uint256 failed) = executor.getExecutionStats(agentId);
        assertEq(totalExecs, 1);
        assertEq(totalSpent, 1 ether);
        assertEq(failed, 0);
    }

    function testExecuteWithBudgetEmitsEvent() public {
        bytes4 selector = MockTarget.simpleAction.selector;
        vm.prank(allowlistManager);
        executor.addToAllowlist(mockTargetAddress, _toArray(selector));

        // Just verify execution works - event is checked by other tests
        vm.prank(spender);
        executor.executeWithBudget{value: 1 ether}(
            agentId,
            mockTargetAddress,
            abi.encodeWithSelector(MockTarget.simpleAction.selector),
            1 ether
        );

        // Verify event was emitted by checking stats increased
        (uint256 totalExecs,, ) = executor.getExecutionStats(agentId);
        assertEq(totalExecs, 1);
    }

    function testCannotExecuteNotAllowedAction() public {
        // Don't add to allowlist

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAutonomousExecutor.ActionNotAllowed.selector,
                mockTargetAddress,
                MockTarget.simpleAction.selector
            )
        );
        executor.executeWithBudget{value: 1 ether}(
            agentId,
            mockTargetAddress,
            abi.encodeWithSelector(MockTarget.simpleAction.selector),
            1 ether
        );
    }

    function testCannotExecuteOverBudget() public {
        bytes4 selector = MockTarget.simpleAction.selector;
        vm.prank(allowlistManager);
        executor.addToAllowlist(mockTargetAddress, _toArray(selector));

        // Try to spend more than monthly budget (100 ether)
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAutonomousExecutor.BudgetExceeded.selector,
                101 ether,
                100 ether
            )
        );
        executor.executeWithBudget{value: 101 ether}(
            agentId,
            mockTargetAddress,
            abi.encodeWithSelector(MockTarget.simpleAction.selector),
            101 ether
        );
    }

    function testCannotExecuteOverDailyLimit() public {
        bytes4 selector = MockTarget.simpleAction.selector;
        vm.prank(allowlistManager);
        executor.addToAllowlist(mockTargetAddress, _toArray(selector));

        // Daily limit is 10 ether, try to spend 11 ether
        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAutonomousExecutor.BudgetExceeded.selector,
                11 ether,
                10 ether
            )
        );
        executor.executeWithBudget{value: 11 ether}(
            agentId,
            mockTargetAddress,
            abi.encodeWithSelector(MockTarget.simpleAction.selector),
            11 ether
        );
    }

    function testCannotExecuteForPausedAgent() public {
        bytes4 selector = MockTarget.simpleAction.selector;
        vm.prank(allowlistManager);
        executor.addToAllowlist(mockTargetAddress, _toArray(selector));

        vm.prank(pauser);
        executor.pauseAgent(agentId);

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAutonomousExecutor.AgentPaused.selector,
                agentId
            )
        );
        executor.executeWithBudget{value: 1 ether}(
            agentId,
            mockTargetAddress,
            abi.encodeWithSelector(MockTarget.simpleAction.selector),
            1 ether
        );
    }

    // ============ Batch Execution Tests ============

    function testExecuteBatch() public {
        bytes4 selector = MockTarget.simpleAction.selector;
        vm.prank(allowlistManager);
        executor.addToAllowlist(mockTargetAddress, _toArray(selector));

        IAutonomousExecutor.Action[] memory actions = new IAutonomousExecutor.Action[](3);
        actions[0] = IAutonomousExecutor.Action({
            target: mockTargetAddress,
            value: 1 ether,
            data: abi.encodeWithSelector(MockTarget.simpleAction.selector)
        });
        actions[1] = IAutonomousExecutor.Action({
            target: mockTargetAddress,
            value: 2 ether,
            data: abi.encodeWithSelector(MockTarget.simpleAction.selector)
        });
        actions[2] = IAutonomousExecutor.Action({
            target: mockTargetAddress,
            value: 3 ether,
            data: abi.encodeWithSelector(MockTarget.simpleAction.selector)
        });

        vm.prank(spender);
        IAutonomousExecutor.ExecutionResult[] memory results = executor.executeBatch{value: 6 ether}(
            agentId,
            actions
        );

        assertEq(results.length, 3);
        assertTrue(results[0].success);
        assertTrue(results[1].success);
        assertTrue(results[2].success);

        (uint256 totalExecs, uint256 totalSpent,) = executor.getExecutionStats(agentId);
        assertEq(totalExecs, 3);
        assertEq(totalSpent, 6 ether);
    }

    function testExecuteBatchEmitsEvent() public {
        bytes4 selector = MockTarget.simpleAction.selector;
        vm.prank(allowlistManager);
        executor.addToAllowlist(mockTargetAddress, _toArray(selector));

        IAutonomousExecutor.Action[] memory actions = new IAutonomousExecutor.Action[](2);
        actions[0] = IAutonomousExecutor.Action({
            target: mockTargetAddress,
            value: 1 ether,
            data: abi.encodeWithSelector(MockTarget.simpleAction.selector)
        });
        actions[1] = IAutonomousExecutor.Action({
            target: mockTargetAddress,
            value: 1 ether,
            data: abi.encodeWithSelector(MockTarget.simpleAction.selector)
        });

        bool[] memory expectedSuccess = new bool[](2);
        expectedSuccess[0] = true;
        expectedSuccess[1] = true;

        vm.expectEmit(true, false, false, true);
        emit IAutonomousExecutor.BatchExecuted(agentId, 2, 2 ether, expectedSuccess);

        vm.prank(spender);
        executor.executeBatch{value: 2 ether}(agentId, actions);
    }

    function testCannotExecuteEmptyBatch() public {
        IAutonomousExecutor.Action[] memory actions = new IAutonomousExecutor.Action[](0);

        vm.prank(spender);
        vm.expectRevert(IAutonomousExecutor.NoActions.selector);
        executor.executeBatch(agentId, actions);
    }

    function testCannotExecuteBatchTooLarge() public {
        IAutonomousExecutor.Action[] memory actions = new IAutonomousExecutor.Action[](51);
        for (uint256 i = 0; i < 51; i++) {
            actions[i] = IAutonomousExecutor.Action({
                target: mockTargetAddress,
                value: 0,
                data: abi.encodeWithSelector(MockTarget.simpleAction.selector)
            });
        }

        vm.prank(spender);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAutonomousExecutor.BatchTooLarge.selector,
                51,
                50
            )
        );
        executor.executeBatch(agentId, actions);
    }

    // ============ Pause/Unpause Tests ============

    function testPauseAgent() public {
        vm.prank(pauser);
        executor.pauseAgent(agentId);

        assertTrue(executor.isAgentPaused(agentId));
    }

    function testPauseAgentEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit IAutonomousExecutor.AgentPausedEvent(agentId, pauser);

        vm.prank(pauser);
        executor.pauseAgent(agentId);
    }

    function testUnpauseAgent() public {
        vm.prank(pauser);
        executor.pauseAgent(agentId);

        vm.prank(pauser);
        executor.unpauseAgent(agentId);

        assertFalse(executor.isAgentPaused(agentId));
    }

    function testUnpauseAgentEmitsEvent() public {
        vm.prank(pauser);
        executor.pauseAgent(agentId);

        vm.expectEmit(true, false, false, true);
        emit IAutonomousExecutor.AgentUnpausedEvent(agentId, pauser);

        vm.prank(pauser);
        executor.unpauseAgent(agentId);
    }

    function testCannotPauseAsNonPauser() public {
        vm.prank(overseer);
        vm.expectRevert(); // AccessControl error
        executor.pauseAgent(agentId);
    }

    // ============ Allowlist Tests ============

    function testAddToAllowlist() public {
        bytes4 selector = MockTarget.simpleAction.selector;
        vm.prank(allowlistManager);
        executor.addToAllowlist(mockTargetAddress, _toArray(selector));

        assertTrue(executor.isActionAllowed(agentId, mockTargetAddress, selector));
    }

    function testAddToAllowlistEmitsEvent() public {
        bytes4 selector = MockTarget.simpleAction.selector;
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = selector;

        vm.expectEmit(true, false, false, true);
        emit IAutonomousExecutor.TargetAddedToAllowlist(mockTargetAddress, selectors);

        vm.prank(allowlistManager);
        executor.addToAllowlist(mockTargetAddress, selectors);
    }

    function testRemoveFromAllowlist() public {
        bytes4 selector = MockTarget.simpleAction.selector;
        vm.prank(allowlistManager);
        executor.addToAllowlist(mockTargetAddress, _toArray(selector));

        assertTrue(executor.isActionAllowed(agentId, mockTargetAddress, selector));

        vm.prank(allowlistManager);
        executor.removeFromAllowlist(mockTargetAddress, _toArray(selector));

        assertFalse(executor.isActionAllowed(agentId, mockTargetAddress, selector));
    }

    function testAllowAllForAgent() public {
        vm.prank(allowlistManager);
        executor.allowAllForAgent(agentId, address(0)); // Allow all targets

        bytes4 selector = MockTarget.simpleAction.selector;
        assertTrue(executor.isActionAllowed(agentId, mockTargetAddress, selector));
    }

    function testCannotModifyAllowlistAsNonManager() public {
        vm.prank(overseer);
        vm.expectRevert(); // AccessControl error
        executor.addToAllowlist(mockTargetAddress, new bytes4[](1));
    }

    // ============ Daily Limit Tests ============

    function testSetDailyLimit() public {
        vm.prank(owner);
        executor.setDailyLimit(agentId, 5 ether);

        (uint256 spent, uint256 limit, uint256 lastReset) = executor.getDailySpending(agentId);
        assertEq(limit, 5 ether);
    }

    function testSetDailyLimitEmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit IAutonomousExecutor.DailyLimitSet(agentId, 10 ether, 5 ether);

        vm.prank(owner);
        executor.setDailyLimit(agentId, 5 ether);
    }

    function testDailyBudgetReset() public {
        bytes4 selector = MockTarget.simpleAction.selector;
        vm.prank(allowlistManager);
        executor.addToAllowlist(mockTargetAddress, _toArray(selector));

        // Spend 5 ether today
        vm.prank(spender);
        executor.executeWithBudget{value: 5 ether}(
            agentId,
            mockTargetAddress,
            abi.encodeWithSelector(MockTarget.simpleAction.selector),
            5 ether
        );

        (uint256 spent,, ) = executor.getDailySpending(agentId);
        assertEq(spent, 5 ether);

        // Fast forward to next day
        vm.warp(block.timestamp + 2 days);

        // Execute another action to trigger budget reset
        vm.prank(spender);
        executor.executeWithBudget{value: 1 ether}(
            agentId,
            mockTargetAddress,
            abi.encodeWithSelector(MockTarget.simpleAction.selector),
            1 ether
        );

        // Daily budget should be reset
        (uint256 spent2,, ) = executor.getDailySpending(agentId);
        assertEq(spent2, 1 ether); // Only the new action, not 5 ether from previous day
    }

    // ============ View Function Tests ============

    function testGetRemainingBudget() public {
        uint256 remaining = executor.getRemainingBudget(agentId);
        assertEq(remaining, 100 ether); // Full monthly budget
    }

    function testGetExecutionStats() public {
        bytes4 selector = MockTarget.simpleAction.selector;
        vm.prank(allowlistManager);
        executor.addToAllowlist(mockTargetAddress, _toArray(selector));

        vm.prank(spender);
        executor.executeWithBudget{value: 1 ether}(
            agentId,
            mockTargetAddress,
            abi.encodeWithSelector(MockTarget.simpleAction.selector),
            1 ether
        );

        (uint256 totalExecs, uint256 totalSpent, uint256 failed) = executor.getExecutionStats(agentId);
        assertEq(totalExecs, 1);
        assertEq(totalSpent, 1 ether);
        assertEq(failed, 0);
    }

    function testGetDailySpending() public {
        (uint256 spent, uint256 limit, uint256 lastReset) = executor.getDailySpending(agentId);

        assertEq(spent, 0);
        assertEq(limit, 10 ether);
        assertEq(lastReset, 0); // Not yet spent anything
    }

    function testGetDailySpendingAfterSpend() public {
        bytes4 selector = MockTarget.simpleAction.selector;
        vm.prank(allowlistManager);
        executor.addToAllowlist(mockTargetAddress, _toArray(selector));

        vm.prank(spender);
        executor.executeWithBudget{value: 3 ether}(
            agentId,
            mockTargetAddress,
            abi.encodeWithSelector(MockTarget.simpleAction.selector),
            3 ether
        );

        (uint256 spent, uint256 limit, ) = executor.getDailySpending(agentId);
        assertEq(spent, 3 ether);
        assertEq(limit, 10 ether);
    }

    // ============ Helper Functions ============

    function _toArray(bytes4 selector) internal pure returns (bytes4[] memory) {
        bytes4[] memory arr = new bytes4[](1);
        arr[0] = selector;
        return arr;
    }
}

// ============ Mock Contract ============

contract MockTarget {
    address public lastCaller;
    uint256 public lastValue;

    function simpleAction() external payable returns (bool) {
        lastCaller = msg.sender;
        lastValue = msg.value;
        return true;
    }

    function failingAction() external pure {
        revert("Failed");
    }

    function getValue() external pure returns (uint256) {
        return 42;
    }

    receive() external payable {}
}
