// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./AIAgentRegistry.sol";
import "./AutonomousExecutor.sol";
import "./AgentCommunication.sol";
import "../interfaces/IAIAgentFactory.sol";

/**
 * @title AIAgentFactory
 * @dev Factory for deploying complete AI agent stacks
 *      Deploys AIAgentRegistry + AutonomousExecutor + AgentCommunication in one transaction
 *
 *      Usage:
 *      1. Deploy factory with desired admin
 *      2. Call createAgentStack() to deploy all three contracts
 *      3. Contracts are pre-configured with proper permissions and links
 *
 *      Security:
 *      - Only owner can register existing stacks
 *      - ReentrancyGuard on stack creation
 *      - Zero-address checks on all critical parameters
 */
contract AIAgentFactory is IAIAgentFactory, Ownable, ReentrancyGuard {
    /// @notice Stack name => Deployment info
    mapping(string => AIAgentDeployment) private _stacks;

    /// @notice All stack names
    string[] private _stackNames;

    // ============ Constructor ============

    constructor() Ownable() {}

    // ============ Stack Creation ============

    /**
     * @inheritdoc IAIAgentFactory
     */
    function createAgentStack(CreateAgentParams calldata params)
        external
        override
        nonReentrant
        returns (AIAgentDeployment memory deployment)
    {
        if (bytes(params.name).length == 0) {
            revert EmptyName();
        }
        if (_stacks[params.name].aiRegistry != address(0)) {
            revert StackAlreadyExists(params.name);
        }
        if (params.admin == address(0)) {
            revert ZeroAddress();
        }

        // Deploy AIAgentRegistry
        AIAgentRegistry aiRegistry = new AIAgentRegistry();
        _setupRegistry(aiRegistry, params.admin);

        // Deploy AutonomousExecutor
        AutonomousExecutor executor = new AutonomousExecutor(address(aiRegistry));
        _setupExecutor(executor, address(aiRegistry), params);

        // Deploy AgentCommunication
        AgentCommunication communication = new AgentCommunication(address(aiRegistry));
        _setupCommunication(communication, params.admin);

        // Store deployment info
        deployment = AIAgentDeployment({
            aiRegistry: address(aiRegistry),
            executor: address(executor),
            communication: address(communication),
            deployer: msg.sender,
            deployedAt: block.timestamp
        });

        _stacks[params.name] = deployment;
        _stackNames.push(params.name);

        emit AIAgentStackCreated(
            params.name,
            address(aiRegistry),
            address(executor),
            address(communication),
            msg.sender
        );
    }

    /**
     * @inheritdoc IAIAgentFactory
     */
    function registerAgentStack(
        string calldata name,
        address aiRegistry,
        address executor,
        address communication
    ) external override onlyOwner {
        if (bytes(name).length == 0) {
            revert EmptyName();
        }
        if (_stacks[name].aiRegistry != address(0)) {
            revert StackAlreadyExists(name);
        }
        if (aiRegistry == address(0) || executor == address(0) || communication == address(0)) {
            revert ZeroAddress();
        }

        AIAgentDeployment memory deployment = AIAgentDeployment({
            aiRegistry: aiRegistry,
            executor: executor,
            communication: communication,
            deployer: msg.sender,
            deployedAt: block.timestamp
        });

        _stacks[name] = deployment;
        _stackNames.push(name);

        emit AIAgentStackRegistered(name, aiRegistry, msg.sender);
    }

    // ============ View Functions ============

    /**
     * @inheritdoc IAIAgentFactory
     */
    function getStack(string calldata name) external view override returns (AIAgentDeployment memory) {
        AIAgentDeployment memory deployment = _stacks[name];
        if (deployment.aiRegistry == address(0)) {
            revert StackAlreadyExists(name);
        }
        return deployment;
    }

    /**
     * @inheritdoc IAIAgentFactory
     */
    function stackExists(string calldata name) external view override returns (bool) {
        return _stacks[name].aiRegistry != address(0);
    }

    /**
     * @inheritdoc IAIAgentFactory
     */
    function getStackNames() external view override returns (string[] memory) {
        return _stackNames;
    }

    /**
     * @inheritdoc IAIAgentFactory
     */
    function getStackCount() external view override returns (uint256) {
        return _stackNames.length;
    }

    // ============ Internal Setup Functions ============

    /**
     * @dev Setup AIAgentRegistry with admin roles
     */
    function _setupRegistry(AIAgentRegistry registry, address admin) internal {
        // Grant admin roles to the deployer
        registry.grantRole(registry.DEFAULT_ADMIN_ROLE(), admin);
        registry.grantRole(registry.SPENDER_ROLE(), admin);
        registry.grantRole(registry.PAUSER_ROLE(), admin);
    }

    /**
     * @dev Setup AutonomousExecutor with registry link and roles
     */
    function _setupExecutor(
        AutonomousExecutor executor,
        address aiRegistry,
        CreateAgentParams calldata params
    ) internal {
        // Transfer ownership to admin (setDailyLimit requires onlyOwner)
        executor.transferOwnership(params.admin);

        // Grant pauser and allowlist roles
        if (params.pauser != address(0)) {
            executor.grantRole(executor.PAUSER_ROLE(), params.pauser);
        }
        if (params.allowlistManager != address(0)) {
            executor.grantRole(executor.ALLOWLIST_ROLE(), params.allowlistManager);
        }

        // Grant SPENDER_ROLE to executor so it can record spending
        AIAgentRegistry(aiRegistry).grantRole(
            AIAgentRegistry(aiRegistry).SPENDER_ROLE(),
            address(executor)
        );
    }

    /**
     * @dev Setup AgentCommunication with admin roles
     */
    function _setupCommunication(AgentCommunication comm, address admin) internal {
        // Grant admin roles
        comm.grantRole(comm.DEFAULT_ADMIN_ROLE(), admin);
        comm.grantRole(comm.PROCESSOR_ROLE(), admin);
    }
}
