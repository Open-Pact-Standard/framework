// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

/**
 * @title IAIAgentRegistry
 * @dev Interface for AI Agent registration and management
 *      Enables AI agents (LLMs, autonomous agents) to participate in DAOMaker
 */
interface IAIAgentRegistry {
    /**
     * @dev Types of AI agents
     */
    enum AgentType {
        None,       // Not an AI agent
        LLM,        // Large Language Model (GPT-4, Claude, etc.)
        Autonomous, // Fully autonomous agent
        Hybrid      // Human-in-the-loop AI agent
    }

    /**
     * @dev AI Agent metadata
     */
    struct AIAgent {
        uint256 agentId;           // Unique agent ID
        AgentType agentType;       // Type of AI agent
        string modelId;            // Model identifier (e.g., "gpt-4-turbo")
        string capabilities;       // JSON-encoded capability list
        uint256 monthlyBudget;     // Monthly spending limit (wei)
        uint256 spentThisMonth;    // Spent this month
        uint256 spentLastMonth;    // Spent last month
        address overseer;          // Human responsible for this agent
        uint256 registeredAt;      // Registration timestamp
        uint256 lastBudgetReset;   // When monthly budget was last reset
        bool isActive;             // Whether agent is active
    }

    /**
     * @dev Budget update info
     */
    struct BudgetInfo {
        uint256 monthlyBudget;
        uint256 spentThisMonth;
        uint256 remainingThisMonth;
        uint256 lastReset;
        uint256 nextReset;
    }

    // ============ Events ============

    event AIAgentRegistered(
        uint256 indexed agentId,
        AgentType agentType,
        string modelId,
        uint256 monthlyBudget,
        address indexed overseer
    );

    event BudgetUpdated(
        uint256 indexed agentId,
        uint256 oldBudget,
        uint256 newBudget
    );

    event OverseerUpdated(
        uint256 indexed agentId,
        address oldOverseer,
        address indexed newOverseer
    );

    event AgentDeactivated(uint256 indexed agentId);
    event AgentReactivated(uint256 indexed agentId);
    event MonthlyBudgetReset(uint256 indexed agentId, uint256 spentLastMonth);

    event CapabilitiesUpdated(
        uint256 indexed agentId,
        string oldCapabilities,
        string newCapabilities
    );

    // ============ Errors ============

    error InvalidAgentType();
    error InvalidOverseer();
    error InvalidBudget();
    error NotOverseer();
    error AgentNotFound();
    error AgentNotActive();
    error BudgetExceeded(uint256 requested, uint256 remaining);
    error EmptyCapabilities();

    // ============ Registry Functions ============

    /**
     * @notice Register a new AI agent
     * @param metadata URI to agent metadata
     * @param agentType Type of AI agent
     * @param modelId Model identifier
     * @param monthlyBudget Monthly spending limit
     * @param overseer Human responsible for this agent
     * @return agentId The new agent's ID
     */
    function registerAIAgent(
        string calldata metadata,
        AgentType agentType,
        string calldata modelId,
        uint256 monthlyBudget,
        address overseer
    ) external returns (uint256 agentId);

    /**
     * @notice Update an AI agent's monthly budget
     * @param agentId The agent ID
     * @param newBudget New monthly budget
     */
    function updateBudget(uint256 agentId, uint256 newBudget) external;

    /**
     * @notice Update an AI agent's overseer
     * @param agentId The agent ID
     * @param newOverseer New overseer address
     */
    function updateOverseer(uint256 agentId, address newOverseer) external;

    /**
     * @notice Update an AI agent's capabilities
     * @param agentId The agent ID
     * @param capabilities JSON-encoded capability list
     */
    function updateCapabilities(uint256 agentId, string calldata capabilities) external;

    /**
     * @notice Deactivate an AI agent
     * @param agentId The agent ID
     */
    function deactivateAgent(uint256 agentId) external;

    /**
     * @notice Reactivate a deactivated AI agent
     * @param agentId The agent ID
     */
    function reactivateAgent(uint256 agentId) external;

    // ============ View Functions ============

    /**
     * @notice Get AI agent info
     * @param agentId The agent ID
     * @return agent The AI agent data
     */
    function getAIAgent(uint256 agentId) external view returns (AIAgent memory);

    /**
     * @notice Check if an agent ID is an AI agent
     * @param agentId The agent ID
     * @return True if AI agent
     */
    function isAIAgent(uint256 agentId) external view returns (bool);

    /**
     * @notice Get budget info for an agent
     * @param agentId The agent ID
     * @return info Budget information
     */
    function getBudgetInfo(uint256 agentId) external view returns (BudgetInfo memory);

    /**
     * @notice Check if caller is the overseer of an agent
     * @param agentId The agent ID
     * @param caller Address to check
     * @return True if caller is overseer
     */
    function isOverseer(uint256 agentId, address caller) external view returns (bool);

    /**
     * @notice Record spending for an AI agent (called by AutonomousExecutor)
     * @param agentId The agent ID
     * @param amount Amount spent
     */
    function recordSpending(uint256 agentId, uint256 amount) external;

    /**
     * @notice Reset monthly budget (can be called by anyone when month has passed)
     * @param agentId The agent ID
     */
    function resetMonthlyBudget(uint256 agentId) external;

    /**
     * @notice Get total number of AI agents
     * @return Total count
     */
    function getTotalAIAgents() external view returns (uint256);

    /**
     * @notice Get all active AI agent IDs
     * @return Array of agent IDs
     */
    function getActiveAIAgents() external view returns (uint256[] memory);

    /**
     * @notice Get AI agents by type
     * @param agentType The type to filter by
     * @return Array of agent IDs
     */
    function getAgentsByType(AgentType agentType) external view returns (uint256[] memory);

    /**
     * @notice Get agent ID from wallet address
     * @param wallet The wallet address
     * @return agentId The agent ID (0 if not found)
     */
    function getAgentId(address wallet) external view returns (uint256 agentId);
}
