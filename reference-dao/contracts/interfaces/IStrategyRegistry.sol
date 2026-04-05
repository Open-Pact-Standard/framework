// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title IStrategyRegistry
 * @dev Interface for strategy lifecycle management.
 */
interface IStrategyRegistry {
    struct StrategyInfo {
        bool registered;
        bool active;
        string protocolName;
        string description;
        uint256 riskScore;
        uint256 createdAt;
    }

    event StrategyRegistered(address indexed strategy, string protocolName);
    event StrategyUpdated(address indexed strategy);
    event StrategyDeactivated(address indexed strategy);
    event StrategyActivated(address indexed strategy);

    /**
     * @dev Register a new strategy.
     * @param strategy Strategy contract address
     * @param protocolName Human-readable protocol name
     * @param description Strategy description
     * @param riskScore Risk score (1-10)
     */
    function registerStrategy(
        address strategy,
        string calldata protocolName,
        string calldata description,
        uint256 riskScore
    ) external;

    /**
     * @dev Update strategy metadata.
     */
    function updateStrategy(
        address strategy,
        string calldata protocolName,
        string calldata description,
        uint256 riskScore
    ) external;

    /**
     * @dev Deactivate a strategy (prevent new deposits).
     * @param strategy Strategy address
     */
    function deactivateStrategy(address strategy) external;

    /**
     * @dev Reactivate a strategy.
     * @param strategy Strategy address
     */
    function activateStrategy(address strategy) external;

    /**
     * @dev Get all registered strategy addresses.
     * @return Array of strategy addresses
     */
    function getStrategies() external view returns (address[] memory);

    /**
     * @dev Get strategy metadata.
     * @param strategy Strategy address
     * @return Strategy info
     */
    function getStrategy(address strategy) external view returns (StrategyInfo memory);

    /**
     * @dev Check if strategy is registered and active.
     * @param strategy Strategy address
     * @return Whether the strategy is active
     */
    function isStrategyActive(address strategy) external view returns (bool);
}
