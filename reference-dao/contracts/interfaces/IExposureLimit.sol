// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title IExposureLimit
 * @dev Interface for per-protocol and per-asset exposure limits.
 */
interface IExposureLimit {
    event ProtocolLimitSet(address indexed protocol, uint256 oldLimit, uint256 newLimit);
    event AssetLimitSet(address indexed asset, uint256 oldLimit, uint256 newLimit);
    event TotalLimitSet(uint256 oldLimit, uint256 newLimit);

    /**
     * @dev Set protocol exposure limit in basis points.
     * @param protocol Protocol address
     * @param limitBasisPoints Limit (10000 = 100%)
     */
    function setProtocolLimit(address protocol, uint256 limitBasisPoints) external;

    /**
     * @dev Set asset exposure limit in basis points.
     * @param asset Token address
     * @param limitBasisPoints Limit (10000 = 100%)
     */
    function setAssetLimit(address asset, uint256 limitBasisPoints) external;

    /**
     * @dev Set total DeFi exposure limit in basis points.
     * @param limitBasisPoints Limit (10000 = 100%)
     */
    function setTotalLimit(uint256 limitBasisPoints) external;

    function getProtocolLimit(address protocol) external view returns (uint256);
    function getAssetLimit(address asset) external view returns (uint256);
    function getTotalLimit() external view returns (uint256);
}
