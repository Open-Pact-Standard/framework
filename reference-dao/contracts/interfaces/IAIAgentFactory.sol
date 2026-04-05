// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title IAIAgentFactory
 * @dev Interface for AI Agent Factory
 *      Deploys complete AI agent stacks in one transaction
 */
interface IAIAgentFactory {
    /**
     * @dev AI Agent deployment configuration
     */
    struct AIAgentDeployment {
        address aiRegistry;      // AIAgentRegistry address
        address executor;        // AutonomousExecutor address
        address communication;    // AgentCommunication address
        address deployer;        // Who initiated the deployment
        uint256 deployedAt;      // Deployment timestamp
    }

    /**
     * @dev Parameters for creating an AI agent stack
     */
    struct CreateAgentParams {
        string name;             // Organization/DAO name for this stack
        address admin;           // Admin address for all contracts
        address pauser;          // Pauser address for executor
        address allowlistManager;// Allowlist manager for executor
        uint256 dailyLimit;      // Default daily spending limit (wei)
    }

    // ============ Events ============

    event AIAgentStackCreated(
        string indexed name,
        address indexed aiRegistry,
        address indexed executor,
        address communication,
        address deployer
    );

    event AIAgentStackRegistered(
        string indexed name,
        address indexed aiRegistry,
        address deployer
    );

    // ============ Errors ============

    error StackAlreadyExists(string name);
    error EmptyName();
    error ZeroAddress();
    error InvalidParams();

    // ============ Functions ============

    /**
     * @notice Create a new AI agent stack
     * @param params Deployment parameters
     * @return deployment The deployed contract addresses
     */
    function createAgentStack(CreateAgentParams calldata params)
        external
        returns (AIAgentDeployment memory deployment);

    /**
     * @notice Register an existing AI agent stack
     * @param name Stack name
     * @param aiRegistry Existing AIAgentRegistry address
     * @param executor Existing AutonomousExecutor address
     * @param communication Existing AgentCommunication address
     */
    function registerAgentStack(
        string calldata name,
        address aiRegistry,
        address executor,
        address communication
    ) external;

    /**
     * @notice Get AI agent stack by name
     * @param name Stack name
     * @return deployment The deployment info
     */
    function getStack(string calldata name) external view returns (AIAgentDeployment memory);

    /**
     * @notice Check if a stack exists
     * @param name Stack name
     * @return True if exists
     */
    function stackExists(string calldata name) external view returns (bool);

    /**
     * @notice Get all stack names
     * @return Array of stack names
     */
    function getStackNames() external view returns (string[] memory);

    /**
     * @notice Get total stack count
     * @return Total number of stacks
     */
    function getStackCount() external view returns (uint256);
}
