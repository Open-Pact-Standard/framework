// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title IAgentRegistry
 * @dev Interface for EIP-8004 Agent Identity Registry
 *      Provides on-chain identity for agents via ERC-721
 */
interface IAgentRegistry {
    /**
     * @notice Register a new agent with metadata URI
     * @param agentURI IPFS or HTTPS URI pointing to agent metadata
     * @return agentId The unique identifier for the newly registered agent
     */
    function register(string memory agentURI) external returns (uint256);

    /**
     * @notice Set a new wallet address for an agent
     * @param newWallet The new wallet address
     */
    function setAgentWallet(address newWallet) external;

    /**
     * @notice Get the wallet address associated with an agent
     * @param agentId The agent ID to query
     * @return The wallet address of the agent
     */
    function getAgentWallet(uint256 agentId) external view returns (address);

    /**
     * @notice Get the agent ID associated with a wallet
     * @param wallet The wallet address to query
     * @return The agent ID, or 0 if not registered
     */
    function getAgentId(address wallet) external view returns (uint256);

    /**
     * @notice Get the total number of registered agents
     * @return The total count of agents
     */
    function getTotalAgents() external view returns (uint256);

    /**
     * @notice Check if an agent exists
     * @param agentId The agent ID to check
     * @return True if the agent exists
     */
    function agentExists(uint256 agentId) external view returns (bool);

    // Events
    event Registered(uint256 indexed agentId, address indexed wallet, string agentURI);
    event MetadataSet(uint256 indexed agentId, string agentURI);
    event WalletChanged(uint256 indexed agentId, address indexed oldWallet, address indexed newWallet);
}
