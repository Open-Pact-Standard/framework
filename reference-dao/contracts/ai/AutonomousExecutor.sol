// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./IAutonomousExecutor.sol";
import "./IAIAgentRegistry.sol";

/**
 * @title AutonomousExecutor
 * @dev Executes actions on behalf of AI agents with budget controls and safety limits
 *
 *      Key features:
 *      - Budget enforcement (monthly and daily limits)
 *      - Action whitelisting (target contracts and function selectors)
 *      - Pause/resume functionality
 *      - Batch execution support
 *      - Execution tracking and statistics
 */
contract AutonomousExecutor is IAutonomousExecutor, Ownable, AccessControl {
    /// @notice Role for pausing agents
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role for managing allowlists
    bytes32 public constant ALLOWLIST_ROLE = keccak256("ALLOWLIST_ROLE");

    /// @notice Maximum batch size
    uint256 public constant MAX_BATCH_SIZE = 50;

    /// @notice 1 day in seconds
    uint256 public constant DAY_SECONDS = 1 days;

    /// @notice AI Agent Registry reference
    IAIAgentRegistry public immutable aiRegistry;

    /// @notice Agent ID => paused status
    mapping(uint256 => bool) private _paused;

    /// @notice (Target, Selector) => allowed (global allowlist for all agents)
    mapping(address => mapping(bytes4 => bool)) private _allowlist;

    /// @notice Target => all selectors allowed
    mapping(address => bool) private _targetAllowAll;

    /// @notice Agent ID => daily spending limit
    mapping(uint256 => uint256) private _dailyLimits;

    /// @notice Agent ID => amount spent today
    mapping(uint256 => uint256) private _dailySpent;

    /// @notice Agent ID => last daily reset time
    mapping(uint256 => uint256) private _dailyLastReset;

    /// @notice Agent ID => execution stats
    mapping(uint256 => ExecutionStats) private _stats;

    /**
     * @dev Execution statistics
     */
    struct ExecutionStats {
        uint256 totalExecutions;
        uint256 totalValueSpent;
        uint256 failedExecutions;
    }

    // ============ Constructor ============

    constructor(address aiRegistry_) Ownable() {
        if (aiRegistry_ == address(0)) {
            revert InvalidAction();
        }

        aiRegistry = IAIAgentRegistry(aiRegistry_);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(PAUSER_ROLE, msg.sender);
        _grantRole(ALLOWLIST_ROLE, msg.sender);
    }

    // ============ Execution Functions ============

    /**
     * @inheritdoc IAutonomousExecutor
     */
    function executeWithBudget(
        uint256 agentId,
        address target,
        bytes calldata data,
        uint256 value
    ) external payable override returns (ExecutionResult memory) {
        _validateExecution(agentId, target, value);

        bytes4 selector = bytes4(data);

        if (!_isActionAllowed(agentId, target, selector)) {
            revert ActionNotAllowed(target, selector);
        }

        return _executeAction(agentId, target, value, data);
    }

    /**
     * @inheritdoc IAutonomousExecutor
     */
    function executeBatch(
        uint256 agentId,
        Action[] calldata actions
    ) external payable override returns (ExecutionResult[] memory) {
        if (actions.length == 0) {
            revert NoActions();
        }
        if (actions.length > MAX_BATCH_SIZE) {
            revert BatchTooLarge(actions.length, MAX_BATCH_SIZE);
        }

        _validateExecution(agentId, address(0), msg.value);

        ExecutionResult[] memory results = new ExecutionResult[](actions.length);
        bool[] memory successArray = new bool[](actions.length);

        uint256 totalValue = 0;

        for (uint256 i = 0; i < actions.length; i++) {
            Action calldata action = actions[i];

            if (!_isActionAllowed(agentId, action.target, bytes4(action.data))) {
                revert ActionNotAllowed(action.target, bytes4(action.data));
            }

            results[i] = _executeAction(agentId, action.target, action.value, action.data);
            successArray[i] = results[i].success;

            totalValue += action.value;
        }

        emit BatchExecuted(agentId, actions.length, totalValue, successArray);

        return results;
    }

    // ============ Admin Functions ============

    /**
     * @inheritdoc IAutonomousExecutor
     */
    function pauseAgent(uint256 agentId) external override onlyRole(PAUSER_ROLE) {
        if (!aiRegistry.isAIAgent(agentId)) {
            revert AgentNotFound();
        }

        _paused[agentId] = true;
        emit IAutonomousExecutor.AgentPausedEvent(agentId, msg.sender);
    }

    /**
     * @inheritdoc IAutonomousExecutor
     */
    function unpauseAgent(uint256 agentId) external override onlyRole(PAUSER_ROLE) {
        if (!aiRegistry.isAIAgent(agentId)) {
            revert AgentNotFound();
        }

        _paused[agentId] = false;
        emit IAutonomousExecutor.AgentUnpausedEvent(agentId, msg.sender);
    }

    /**
     * @inheritdoc IAutonomousExecutor
     */
    function addToAllowlist(
        address target,
        bytes4[] calldata selectors
    ) external override onlyRole(ALLOWLIST_ROLE) {
        if (selectors.length == 0) {
            // Allow all selectors for this target - requires special handling
            // For now, we'll require explicit selectors
            revert InvalidAction();
        }

        for (uint256 i = 0; i < selectors.length; i++) {
            _allowlist[target][selectors[i]] = true;
        }

        emit TargetAddedToAllowlist(target, selectors);
    }

    /**
     * @notice Allow all targets/selectors for a specific agent
     * @param agentId The agent ID (not used with global allowlist)
     * @param target Target contract (address(0) for all targets)
     */
    function allowAllForAgent(uint256 agentId, address target) external onlyRole(ALLOWLIST_ROLE) {
        // agentId parameter kept for interface compatibility but not used
        _targetAllowAll[target] = true;
        emit TargetAddedToAllowlist(target, new bytes4[](0));
    }

    /**
     * @inheritdoc IAutonomousExecutor
     */
    function removeFromAllowlist(
        address target,
        bytes4[] calldata selectors
    ) external override onlyRole(ALLOWLIST_ROLE) {
        for (uint256 i = 0; i < selectors.length; i++) {
            _allowlist[target][selectors[i]] = false;
        }

        emit TargetRemovedFromAllowlist(target, selectors);
    }

    /**
     * @inheritdoc IAutonomousExecutor
     */
    function setDailyLimit(uint256 agentId, uint256 dailyLimit) external override onlyOwner {
        if (!aiRegistry.isAIAgent(agentId)) {
            revert AgentNotFound();
        }

        uint256 oldLimit = _dailyLimits[agentId];
        _dailyLimits[agentId] = dailyLimit;

        emit DailyLimitSet(agentId, oldLimit, dailyLimit);
    }

    // ============ View Functions ============

    /**
     * @inheritdoc IAutonomousExecutor
     */
    function isActionAllowed(
        uint256 agentId,
        address target,
        bytes4 selector
    ) external view override returns (bool) {
        return _isActionAllowed(agentId, target, selector);
    }

    /**
     * @inheritdoc IAutonomousExecutor
     */
    function getRemainingBudget(uint256 agentId) external view override returns (uint256) {
        IAIAgentRegistry.BudgetInfo memory info = aiRegistry.getBudgetInfo(agentId);
        return info.remainingThisMonth;
    }

    /**
     * @inheritdoc IAutonomousExecutor
     */
    function isAgentPaused(uint256 agentId) external view override returns (bool) {
        return _paused[agentId];
    }

    /**
     * @inheritdoc IAutonomousExecutor
     */
    function getExecutionStats(uint256 agentId)
        external
        view
        override
        returns (
            uint256 totalExecutions,
            uint256 totalValueSpent,
            uint256 failedExecutions
        )
    {
        if (!aiRegistry.isAIAgent(agentId)) {
            revert AgentNotFound();
        }

        ExecutionStats storage stats = _stats[agentId];
        return (stats.totalExecutions, stats.totalValueSpent, stats.failedExecutions);
    }

    /**
     * @inheritdoc IAutonomousExecutor
     */
    function getDailySpending(uint256 agentId)
        external
        view
        override
        returns (
            uint256 spentToday,
            uint256 dailyLimit,
            uint256 lastReset
        )
    {
        if (!aiRegistry.isAIAgent(agentId)) {
            revert AgentNotFound();
        }

        return (_dailySpent[agentId], _dailyLimits[agentId], _dailyLastReset[agentId]);
    }

    // ============ Internal Functions ============

    /**
     * @dev Validate execution preconditions
     */
    function _validateExecution(uint256 agentId, address, uint256 value) internal {
        if (!aiRegistry.isAIAgent(agentId)) {
            revert AgentNotFound();
        }

        if (_paused[agentId]) {
            revert IAutonomousExecutor.AgentPaused(agentId);
        }

        // Check and reset daily budget if needed
        _checkAndResetDaily(agentId);

        // Check monthly budget
        uint256 remainingMonthly = this.getRemainingBudget(agentId);
        if (value > remainingMonthly) {
            revert BudgetExceeded(value, remainingMonthly);
        }

        // Check daily budget
        uint256 remainingDaily = _dailyLimits[agentId] - _dailySpent[agentId];
        if (value > remainingDaily) {
            revert BudgetExceeded(value, remainingDaily);
        }
    }

    /**
     * @dev Execute a single action
     */
    function _executeAction(
        uint256 agentId,
        address target,
        uint256 value,
        bytes memory data
    ) internal returns (ExecutionResult memory) {
        uint256 gasBefore = gasleft();

        // Record spending
        _recordSpending(agentId, value);

        // Update stats
        _stats[agentId].totalExecutions++;
        _stats[agentId].totalValueSpent += value;

        // Execute the call
        (bool success, bytes memory returnData) = target.call{value: value}(data);

        if (!success) {
            _stats[agentId].failedExecutions++;
        }

        uint256 gasUsed = gasBefore - gasleft();

        emit ActionExecuted(agentId, target, value, bytes4(data), gasUsed, success);

        return ExecutionResult({
            success: success,
            returnData: returnData,
            gasUsed: gasUsed
        });
    }

    /**
     * @dev Check if an action is allowed for an agent
     */
    function _isActionAllowed(uint256, address target, bytes4 selector) internal view returns (bool) {
        // Check if all targets allowed
        if (_targetAllowAll[address(0)]) {
            return true;
        }

        // Check if specific target allowed
        if (_targetAllowAll[target]) {
            return true;
        }

        // Check if specific selector allowed for target
        return _allowlist[target][selector];
    }

    /**
     * @dev Record spending in both registries
     */
    function _recordSpending(uint256 agentId, uint256 amount) internal {
        // Record in AI registry (monthly)
        aiRegistry.recordSpending(agentId, amount);

        // Record daily spending
        _dailySpent[agentId] += amount;

        emit BudgetSpent(agentId, amount, this.getRemainingBudget(agentId));
    }

    /**
     * @dev Check and reset daily budget if needed
     */
    function _checkAndResetDaily(uint256 agentId) internal {
        if (_dailyLastReset[agentId] == 0) {
            _dailyLastReset[agentId] = block.timestamp;
            return;
        }

        if (block.timestamp >= _dailyLastReset[agentId] + DAY_SECONDS) {
            _dailySpent[agentId] = 0;
            _dailyLastReset[agentId] = block.timestamp;
        }
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

    // ============ Receive ============

    /// @notice Accept ETH for execution
    receive() external payable {}
}
