// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title IRiskManager
 * @dev Interface for risk validation and exposure tracking.
 */
interface IRiskManager {
    event ExposureUpdated(address indexed strategy, uint256 amount, bool isDeployment);
    event DrawdownTriggered(address indexed strategy, uint256 currentValue, uint256 peak);
    event StrategyMetricsUpdated(address indexed strategy, uint256 currentValue);
    event DrawdownThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    /**
     * @dev Validate if a deployment is allowed under current risk limits.
     * @param strategy Strategy to deploy to
     * @param amount Amount to deploy
     * @return allowed Whether deployment is permitted
     * @return reason Revert reason if not allowed
     */
    function validateDeployment(
        address strategy,
        uint256 amount
    ) external view returns (bool allowed, string memory reason);

    /**
     * @dev Update exposure tracking after deployment or withdrawal.
     * @param strategy Strategy address
     * @param amount Amount deployed or withdrawn
     * @param isDeployment True for deployment, false for withdrawal
     */
    function updateExposure(address strategy, uint256 amount, bool isDeployment) external;

    /**
     * @dev Check if a position should be unwound due to drawdown.
     * @param strategy Strategy address
     * @param currentValue Current position value
     * @return shouldUnwind Whether the position should be unwound
     */
    function checkDrawdown(address strategy, uint256 currentValue) external view returns (bool shouldUnwind);

    /**
     * @dev Update strategy metrics (peak value, entry tracking).
     * @param strategy Strategy address
     * @param currentValue Current position value
     */
    function updateStrategyMetrics(address strategy, uint256 currentValue) external;

    function getExposure(address protocol) external view returns (uint256);
    function getTotalExposure() external view returns (uint256);
}
