// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

/**
 * @title IAutonomousExecutor
 * @dev Interface for autonomous execution on behalf of AI agents
 *      Enables AI agents to execute actions with budget controls and safety limits
 */
interface IAutonomousExecutor {
    /**
     * @dev Action to be executed
     */
    struct Action {
        address target;      // Contract to call
        uint256 value;       // ETH to send
        bytes data;          // Calldata
    }

    /**
     * @dev Execution result
     */
    struct ExecutionResult {
        bool success;        // Whether the call succeeded
        bytes returnData;    // Return data from the call
        uint256 gasUsed;     // Gas used by the call
    }

    // ============ Events ============

    event ActionExecuted(
        uint256 indexed agentId,
        address target,
        uint256 value,
        bytes4 selector,
        uint256 gasUsed,
        bool success
    );

    event BatchExecuted(
        uint256 indexed agentId,
        uint256 actionCount,
        uint256 totalValue,
        bool[] success
    );

    event BudgetSpent(
        uint256 indexed agentId,
        uint256 amount,
        uint256 remaining
    );

    event AgentPausedEvent(uint256 indexed agentId, address pausedBy);
    event AgentUnpausedEvent(uint256 indexed agentId, address unpausedBy);

    event TargetAddedToAllowlist(
        address indexed target,
        bytes4[] selectors
    );

    event TargetRemovedFromAllowlist(
        address indexed target,
        bytes4[] selectors
    );

    event DailyLimitSet(
        uint256 indexed agentId,
        uint256 oldLimit,
        uint256 newLimit
    );

    // ============ Errors ============

    error BudgetExceeded(uint256 requested, uint256 remaining);
    error ActionNotAllowed(address target, bytes4 selector);
    error AgentPaused(uint256 agentId);
    error AgentNotFound();
    error AgentNotActive();
    error Unauthorized();
    error InvalidAction();
    error BatchTooLarge(uint256 requested, uint256 max);
    error NoActions();

    // ============ Execution Functions ============

    /**
     * @notice Execute a single action on behalf of an AI agent
     * @param agentId The AI agent ID
     * @param target Contract to call
     * @param value ETH to send
     * @param data Calldata
     * @return result Execution result
     */
    function executeWithBudget(
        uint256 agentId,
        address target,
        bytes calldata data,
        uint256 value
    ) external payable returns (ExecutionResult memory);

    /**
     * @notice Execute multiple actions in a batch
     * @param agentId The AI agent ID
     * @param actions Array of actions to execute
     * @return results Array of execution results
     */
    function executeBatch(
        uint256 agentId,
        Action[] calldata actions
    ) external payable returns (ExecutionResult[] memory);

    // ============ Admin Functions ============

    /**
     * @notice Pause an AI agent (prevent all execution)
     * @param agentId The agent ID
     */
    function pauseAgent(uint256 agentId) external;

    /**
     * @notice Unpause an AI agent
     * @param agentId The agent ID
     */
    function unpauseAgent(uint256 agentId) external;

    /**
     * @notice Add target/selector to allowlist
     * @param target Contract address
     * @param selectors Function selectors to allow (empty = all)
     */
    function addToAllowlist(
        address target,
        bytes4[] calldata selectors
    ) external;

    /**
     * @notice Remove target/selector from allowlist
     * @param target Contract address
     * @param selectors Function selectors to remove
     */
    function removeFromAllowlist(
        address target,
        bytes4[] calldata selectors
    ) external;

    /**
     * @notice Set daily spending limit for an agent
     * @param agentId The agent ID
     * @param dailyLimit Daily limit in wei
     */
    function setDailyLimit(uint256 agentId, uint256 dailyLimit) external;

    // ============ View Functions ============

    /**
     * @notice Check if an action is allowed
     * @param agentId The agent ID
     * @param target Contract address
     * @param selector Function selector
     * @return True if allowed
     */
    function isActionAllowed(
        uint256 agentId,
        address target,
        bytes4 selector
    ) external view returns (bool);

    /**
     * @notice Get remaining budget for an agent
     * @param agentId The agent ID
     * @return remaining Remaining budget this month
     */
    function getRemainingBudget(uint256 agentId) external view returns (uint256);

    /**
     * @notice Check if agent is paused
     * @param agentId The agent ID
     * @return True if paused
     */
    function isAgentPaused(uint256 agentId) external view returns (bool);

    /**
     * @notice Get execution stats for an agent
     * @param agentId The agent ID
     * @return totalExecutions Total number of executions
     * @return totalValueSpent Total value spent
     * @return failedExecutions Number of failed executions
     */
    function getExecutionStats(uint256 agentId)
        external
        view
        returns (
            uint256 totalExecutions,
            uint256 totalValueSpent,
            uint256 failedExecutions
        );

    /**
     * @notice Get daily spending for an agent
     * @param agentId The agent ID
     * @return spentToday Amount spent today
     * @return dailyLimit Daily limit
     * @return lastReset Last time daily limit was reset
     */
    function getDailySpending(uint256 agentId)
        external
        view
        returns (
            uint256 spentToday,
            uint256 dailyLimit,
            uint256 lastReset
        );
}
