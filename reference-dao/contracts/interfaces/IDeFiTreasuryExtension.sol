// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

/**
 * @title IDeFiTreasuryExtension
 * @dev Interface for treasury DeFi integration.
 */
interface IDeFiTreasuryExtension {
    event StrategyDeployed(address indexed strategy, uint256 amount);
    event StrategyWithdrawn(address indexed strategy, uint256 amount);

    /**
     * @dev Deploy treasury funds to a DeFi strategy.
     * @param strategy Strategy address
     * @param amount Amount to deploy
     */
    function deployToStrategy(address strategy, uint256 amount) external;

    /**
     * @dev Withdraw treasury funds from a DeFi strategy.
     * @param strategy Strategy address
     * @param amount Amount to withdraw
     */
    function withdrawFromStrategy(address strategy, uint256 amount) external;

    function getStrategyBalance(address strategy) external view returns (uint256);
    function getStrategyAPY(address strategy) external view returns (uint256);
    function getTotalDeFiExposure() external view returns (uint256);
    function getRegisteredStrategies() external view returns (address[] memory);
    function isStrategyActive(address strategy) external view returns (bool);
}
