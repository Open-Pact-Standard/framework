// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

/**
 * @title IFlareLend
 * @dev Interface for FlareLend lending pool (Aave V2 fork).
 *      Minimal interface for deposit, withdraw, and data queries.
 */
interface IFlareLend {
    /**
     * @dev Deposit assets into the lending pool.
     * @param asset Token address to deposit
     * @param amount Amount to deposit
     * @param onBehalfOf Address that receives the aTokens
     * @param referralCode Referral code (0 if none)
     */
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /**
     * @dev Withdraw assets from the lending pool.
     * @param asset Token address to withdraw
     * @param amount Amount to withdraw (type(uint256).max for all)
     * @param to Recipient address
     * @return Amount withdrawn
     */
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);

    /**
     * @dev Get user account data (collateral, debt, health factor).
     */
    function getUserAccountData(
        address user
    )
        external
        view
        returns (
            uint256 totalCollateralETH,
            uint256 totalDebtETH,
            uint256 availableBorrowsETH,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

    /**
     * @dev Get reserve data for an asset.
     */
    function getReserveData(
        address asset
    )
        external
        view
        returns (
            uint256 unbacked,
            uint256 accruedToTreasuryScaled,
            uint256 totalAToken,
            uint256 totalStableDebt,
            uint256 totalVariableDebt,
            uint256 currentLiquidityRate,
            uint256 currentVariableBorrowRate,
            uint256 currentStableBorrowRate,
            uint256 liquidityIndex,
            uint256 variableBorrowIndex,
            uint256 lastUpdateTimestamp
        );
}
