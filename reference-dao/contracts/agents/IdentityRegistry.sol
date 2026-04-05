// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "../interfaces/IAgentRegistry.sol";

/**
 * @title IdentityRegistry
 * @dev ERC-721 based agent identity registry per EIP-8004 specification.
 *      Enables agent registration with on-chain identity and metadata URI.
 */
contract IdentityRegistry is IAgentRegistry, ERC721, ERC721URIStorage, Ownable {
    using Counters for Counters.Counter;

    Counters.Counter private _agentIdCounter;

    /// @notice Mapping from agent ID to wallet address
    mapping(uint256 => address) private _agentWallets;

    /// @notice Mapping from wallet to agent ID (one-to-one)
    mapping(address => uint256) private _walletToAgentId;

    // Custom errors
    error EmptyURI();
    error WalletAlreadyRegistered();
    error ZeroAddress();
    error SameWallet();
    error NewWalletAlreadyRegistered();
    error NoAgent();
    error AgentDoesNotExist();
    error NotAgentOwner();

    /**
     * @dev Initializes the contract with a name and symbol for the ERC-721 token.
     */
    constructor() ERC721("Agent Identity", "AID") Ownable() {}

    /**
     * @notice Register a new agent with metadata URI
     * @dev Mints a new ERC-721 token representing the agent's identity
     * @param agentURI IPFS or HTTPS URI pointing to agent metadata
     * @return agentId The unique identifier for the newly registered agent
     */
    function register(string memory agentURI) external override returns (uint256) {
        if (bytes(agentURI).length == 0) {
            revert EmptyURI();
        }
        if (_walletToAgentId[msg.sender] != 0) {
            revert WalletAlreadyRegistered();
        }

        // Increment and get new agent ID (starts at 1)
        _agentIdCounter.increment();
        uint256 agentId = _agentIdCounter.current();

        // Mint NFT to sender
        _mint(msg.sender, agentId);
        _setTokenURI(agentId, agentURI);

        // Set up wallet mapping
        _agentWallets[agentId] = msg.sender;
        _walletToAgentId[msg.sender] = agentId;

        emit Registered(agentId, msg.sender, agentURI);

        return agentId;
    }

    /**
     * @notice Set a new wallet address for an agent
     * @dev Allows the current wallet owner to change their wallet
     * @param newWallet The new wallet address
     */
    function setAgentWallet(address newWallet) external override {
        if (newWallet == address(0)) {
            revert ZeroAddress();
        }
        if (newWallet == msg.sender) {
            revert SameWallet();
        }
        if (_walletToAgentId[newWallet] != 0) {
            revert NewWalletAlreadyRegistered();
        }

        uint256 agentId = _walletToAgentId[msg.sender];
        if (agentId == 0 || _agentWallets[agentId] != msg.sender) {
            revert NoAgent();
        }

        // Update mappings
        address oldWallet = _agentWallets[agentId];
        _agentWallets[agentId] = newWallet;
        _walletToAgentId[oldWallet] = 0;
        _walletToAgentId[newWallet] = agentId;

        // Transfer NFT to new wallet
        _transfer(oldWallet, newWallet, agentId);

        emit WalletChanged(agentId, oldWallet, newWallet);
    }

    /**
     * @notice Get the wallet address associated with an agent
     * @param agentId The agent ID to query
     * @return The wallet address of the agent
     */
    function getAgentWallet(uint256 agentId) external view override returns (address) {
        if (_ownerOf(agentId) == address(0)) {
            revert AgentDoesNotExist();
        }
        return _agentWallets[agentId];
    }

    /**
     * @notice Get the agent ID associated with a wallet
     * @param wallet The wallet address to query
     * @return The agent ID, or 0 if not registered
     */
    function getAgentId(address wallet) external view override returns (uint256) {
        return _walletToAgentId[wallet];
    }

    /**
     * @notice Get the total number of registered agents
     * @return The total count of agents
     */
    function getTotalAgents() external view override returns (uint256) {
        return _agentIdCounter.current();
    }

    /**
     * @notice Check if an agent exists (token exists)
     * @param agentId The agent ID to check
     * @return True if the agent exists
     */
    function agentExists(uint256 agentId) external view override returns (bool) {
        return _ownerOf(agentId) != address(0);
    }

    /**
     * @notice Set the metadata URI for an existing agent
     * @param agentId The agent ID
     * @param agentURI The new URI
     */
    function setAgentURI(uint256 agentId, string memory agentURI) external {
        if (_ownerOf(agentId) != msg.sender) {
            revert NotAgentOwner();
        }
        _setTokenURI(agentId, agentURI);
        emit MetadataSet(agentId, agentURI);
    }

    // Required overrides for multiple inheritance
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function _burn(uint256 tokenId) internal override(ERC721, ERC721URIStorage) {
        super._burn(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
