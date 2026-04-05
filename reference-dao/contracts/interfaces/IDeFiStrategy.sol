// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title IDeFiStrategy
 * @dev Interface for DeFi yield-generating strategies.
 */
interface IDeFiStrategy {
    event Deposited(address indexed strategy, uint256 amount);
    event Withdrawn(address indexed strategy, uint256 amount);

    /**
     * @dev Deposit tokens into the strategy.
     * @param amount Amount to deposit
     */
    function deposit(uint256 amount) external;

    /**
     * @dev Withdraw tokens from the strategy.
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external;

    /**
     * @dev Get current balance deployed in the strategy.
     * @return Current balance
     */
    function getBalance() external view returns (uint256);

    /**
     * @dev Get estimated APY in basis points (100 = 1%).
     * @return APY in basis points
     */
    function getAPY() external view returns (uint256);

    /**
     * @dev Get protocol risk score (1-10, 1 = lowest risk).
     * @return Risk score
     */
    function getProtocolRiskScore() external view returns (uint256);

    /**
     * @dev Get the treasury address authorized to call deposit/withdraw.
     * @return Treasury address
     */
    function getTreasury() external view returns (address);

    /**
     * @dev Get the token address this strategy manages.
     * @return Token address
     */
    function getToken() external view returns (address);
}
