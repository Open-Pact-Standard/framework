// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./IAIAgentRegistry.sol";

/**
 * @title AIAgentRegistry
 * @dev Registry for AI agents (LLMs, autonomous agents) in DAOMaker
 *      Manages AI agent identities, budgets, and oversight
 *
 *      AI agents can:
 *      - Register with model type and capabilities
 *      - Have monthly budget limits for autonomous spending
 *      - Be overseen by a human for safety
 *      - Participate in bounties alongside human agents
 */
contract AIAgentRegistry is IAIAgentRegistry, Ownable, AccessControl {
    using Counters for Counters.Counter;

    /// @notice Role for spending recording (AutonomousExecutor)
    bytes32 public constant SPENDER_ROLE = keccak256("SPENDER_ROLE");

    /// @notice Role for pausing agents
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice AI Agent ID counter
    Counters.Counter private _aiAgentIdCounter;

    /// @notice Agent ID => AIAgent data
    mapping(uint256 => AIAgent) private _aiAgents;

    /// @notice Address => Agent ID (for overseer lookup and reverse lookup)
    mapping(address => uint256) private _addressToAgentId;

    /// @notice Address => Agent ID (for overseer lookup)
    mapping(uint256 => address) private _agentOverseers;

    /// @notice Active AI agent IDs
    uint256[] private _activeAIAgents;

    /// @notice Agent Type => Array of agent IDs
    mapping(AgentType => uint256[]) private _agentsByType;

    /// @notice Agent ID => Index in _agentsByType (for removal)
    mapping(uint256 => mapping(AgentType => uint256)) private _agentTypeIndex;

    /// @notice Agent ID => Index in _activeAIAgents
    mapping(uint256 => uint256) private _activeAgentIndex;

    /// @notice 30 days in seconds
    uint256 public constant MONTH_SECONDS = 30 days;

    // ============ Constructor ============

    constructor() Ownable() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SPENDER_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
    }

    // ============ Registry Functions ============

    /**
     * @inheritdoc IAIAgentRegistry
     */
    function registerAIAgent(
        string calldata metadata,
        AgentType agentType,
        string calldata modelId,
        uint256 monthlyBudget,
        address overseer
    ) external override returns (uint256 agentId) {
        if (agentType == AgentType.None) {
            revert InvalidAgentType();
        }
        if (overseer == address(0)) {
            revert InvalidOverseer();
        }
        if (monthlyBudget == 0) {
            revert InvalidBudget();
        }
        if (bytes(modelId).length == 0) {
            revert InvalidBudget(); // Using same error for empty modelId
        }

        _aiAgentIdCounter.increment();
        agentId = _aiAgentIdCounter.current();

        _aiAgents[agentId] = AIAgent({
            agentId: agentId,
            agentType: agentType,
            modelId: modelId,
            capabilities: "",
            monthlyBudget: monthlyBudget,
            spentThisMonth: 0,
            spentLastMonth: 0,
            overseer: overseer,
            registeredAt: block.timestamp,
            lastBudgetReset: block.timestamp,
            isActive: true
        });

        // Store address -> agentId mapping
        _addressToAgentId[msg.sender] = agentId;
        _agentOverseers[agentId] = overseer;

        // Add to active agents list
        _activeAIAgents.push(agentId);
        _activeAgentIndex[agentId] = _activeAIAgents.length - 1;

        // Add to type-specific list
        _agentsByType[agentType].push(agentId);
        _agentTypeIndex[agentId][agentType] = _agentsByType[agentType].length - 1;

        emit AIAgentRegistered(agentId, agentType, modelId, monthlyBudget, overseer);
    }

    /**
     * @inheritdoc IAIAgentRegistry
     */
    function updateBudget(uint256 agentId, uint256 newBudget) external override {
        if (!_aiAgents[agentId].isActive) {
            revert AgentNotActive();
        }
        if (!_isOverseer(agentId, msg.sender)) {
            revert NotOverseer();
        }
        if (newBudget == 0) {
            revert InvalidBudget();
        }

        uint256 oldBudget = _aiAgents[agentId].monthlyBudget;
        _aiAgents[agentId].monthlyBudget = newBudget;

        emit BudgetUpdated(agentId, oldBudget, newBudget);
    }

    /**
     * @inheritdoc IAIAgentRegistry
     */
    function updateOverseer(uint256 agentId, address newOverseer) external override {
        if (!_aiAgents[agentId].isActive) {
            revert AgentNotActive();
        }
        if (!_isOverseer(agentId, msg.sender)) {
            revert NotOverseer();
        }
        if (newOverseer == address(0)) {
            revert InvalidOverseer();
        }

        address oldOverseer = _aiAgents[agentId].overseer;
        _aiAgents[agentId].overseer = newOverseer;
        _agentOverseers[agentId] = newOverseer;

        emit OverseerUpdated(agentId, oldOverseer, newOverseer);
    }

    /**
     * @inheritdoc IAIAgentRegistry
     */
    function updateCapabilities(uint256 agentId, string calldata capabilities) external override {
        if (!_aiAgents[agentId].isActive) {
            revert AgentNotActive();
        }
        if (!_isOverseer(agentId, msg.sender)) {
            revert NotOverseer();
        }
        if (bytes(capabilities).length == 0) {
            revert EmptyCapabilities();
        }

        string memory oldCapabilities = _aiAgents[agentId].capabilities;
        _aiAgents[agentId].capabilities = capabilities;

        emit CapabilitiesUpdated(agentId, oldCapabilities, capabilities);
    }

    /**
     * @inheritdoc IAIAgentRegistry
     */
    function deactivateAgent(uint256 agentId) external override {
        if (!_aiAgents[agentId].isActive) {
            revert AgentNotActive();
        }
        if (!_isOverseer(agentId, msg.sender) && !hasRole(PAUSER_ROLE, msg.sender)) {
            revert NotOverseer();
        }

        _aiAgents[agentId].isActive = false;

        // Remove from active agents list
        _removeFromActiveList(agentId);

        emit AgentDeactivated(agentId);
    }

    /**
     * @inheritdoc IAIAgentRegistry
     */
    function reactivateAgent(uint256 agentId) external override {
        if (_aiAgents[agentId].isActive) {
            revert AgentNotActive(); // Already active
        }
        if (!_isOverseer(agentId, msg.sender) && !hasRole(PAUSER_ROLE, msg.sender)) {
            revert NotOverseer();
        }

        _aiAgents[agentId].isActive = true;

        // Add back to active agents list
        _activeAIAgents.push(agentId);
        _activeAgentIndex[agentId] = _activeAIAgents.length - 1;

        emit AgentReactivated(agentId);
    }

    // ============ View Functions ============

    /**
     * @inheritdoc IAIAgentRegistry
     */
    function getAIAgent(uint256 agentId) external view override returns (AIAgent memory) {
        if (_aiAgents[agentId].agentId == 0) {
            revert AgentNotFound();
        }
        return _aiAgents[agentId];
    }

    /**
     * @inheritdoc IAIAgentRegistry
     */
    function isAIAgent(uint256 agentId) external view override returns (bool) {
        return _aiAgents[agentId].agentId != 0;
    }

    /**
     * @inheritdoc IAIAgentRegistry
     */
    function getBudgetInfo(uint256 agentId) external view override returns (BudgetInfo memory) {
        if (_aiAgents[agentId].agentId == 0) {
            revert AgentNotFound();
        }

        AIAgent storage agent = _aiAgents[agentId];

        return BudgetInfo({
            monthlyBudget: agent.monthlyBudget,
            spentThisMonth: agent.spentThisMonth,
            remainingThisMonth: agent.monthlyBudget - agent.spentThisMonth,
            lastReset: agent.lastBudgetReset,
            nextReset: agent.lastBudgetReset + MONTH_SECONDS
        });
    }

    /**
     * @inheritdoc IAIAgentRegistry
     */
    function isOverseer(uint256 agentId, address caller) external view override returns (bool) {
        return _isOverseer(agentId, caller);
    }

    /**
     * @inheritdoc IAIAgentRegistry
     */
    function recordSpending(uint256 agentId, uint256 amount) external override onlyRole(SPENDER_ROLE) {
        if (_aiAgents[agentId].agentId == 0) {
            revert AgentNotFound();
        }
        if (!_aiAgents[agentId].isActive) {
            revert AgentNotActive();
        }

        // Check if budget reset is needed
        _checkAndResetBudget(agentId);

        // Check if spending would exceed budget
        if (_aiAgents[agentId].spentThisMonth + amount > _aiAgents[agentId].monthlyBudget) {
            revert BudgetExceeded(amount, _aiAgents[agentId].monthlyBudget - _aiAgents[agentId].spentThisMonth);
        }

        _aiAgents[agentId].spentThisMonth += amount;
    }

    /**
     * @inheritdoc IAIAgentRegistry
     */
    function resetMonthlyBudget(uint256 agentId) external override {
        if (_aiAgents[agentId].agentId == 0) {
            revert AgentNotFound();
        }

        _checkAndResetBudget(agentId);
    }

    /**
     * @inheritdoc IAIAgentRegistry
     */
    function getTotalAIAgents() external view override returns (uint256) {
        return _aiAgentIdCounter.current();
    }

    /**
     * @inheritdoc IAIAgentRegistry
     */
    function getActiveAIAgents() external view override returns (uint256[] memory) {
        return _activeAIAgents;
    }

    /**
     * @inheritdoc IAIAgentRegistry
     */
    function getAgentsByType(AgentType agentType) external view override returns (uint256[] memory) {
        return _agentsByType[agentType];
    }

    /**
     * @inheritdoc IAIAgentRegistry
     */
    function getAgentId(address wallet) external view override returns (uint256 agentId) {
        return _addressToAgentId[wallet];
    }

    // ============ Internal Functions ============

    /**
     * @dev Check if caller is the overseer of an agent
     */
    function _isOverseer(uint256 agentId, address caller) internal view returns (bool) {
        return _agentOverseers[agentId] == caller;
    }

    /**
     * @dev Check and reset monthly budget if needed
     */
    function _checkAndResetBudget(uint256 agentId) internal {
        AIAgent storage agent = _aiAgents[agentId];

        if (block.timestamp >= agent.lastBudgetReset + MONTH_SECONDS) {
            agent.spentLastMonth = agent.spentThisMonth;
            agent.spentThisMonth = 0;
            agent.lastBudgetReset = block.timestamp;

            emit MonthlyBudgetReset(agentId, agent.spentLastMonth);
        }
    }

    /**
     * @dev Remove agent from active list
     */
    function _removeFromActiveList(uint256 agentId) internal {
        uint256 index = _activeAgentIndex[agentId];
        uint256 lastIndex = _activeAIAgents.length - 1;

        if (index != lastIndex) {
            uint256 lastAgentId = _activeAIAgents[lastIndex];
            _activeAIAgents[index] = lastAgentId;
            _activeAgentIndex[lastAgentId] = index;
        }

        _activeAIAgents.pop();
        delete _activeAgentIndex[agentId];
    }

    // ============ Required Override ============

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
