// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../../interfaces/IExposureLimit.sol";

/**
 * @title ExposureLimit
 * @dev Manages per-protocol, per-asset, and total exposure limits in basis points.
 */
contract ExposureLimit is IExposureLimit, Ownable {
    uint256 public constant MAX_LIMIT = 10_000;

    mapping(address => uint256) public protocolExposureLimit;
    mapping(address => uint256) public assetExposureLimit;
    uint256 public totalExposureLimit;

    error LimitTooHigh(uint256 limit);
    error ZeroAddress();

    constructor() Ownable() {}

    /**
     * @inheritdoc IExposureLimit
     */
    function setProtocolLimit(address protocol, uint256 limitBasisPoints) external override onlyOwner {
        if (protocol == address(0)) {
            revert ZeroAddress();
        }
        if (limitBasisPoints > MAX_LIMIT) {
            revert LimitTooHigh(limitBasisPoints);
        }
        uint256 oldLimit = protocolExposureLimit[protocol];
        protocolExposureLimit[protocol] = limitBasisPoints;
        emit ProtocolLimitSet(protocol, oldLimit, limitBasisPoints);
    }

    /**
     * @inheritdoc IExposureLimit
     */
    function setAssetLimit(address asset, uint256 limitBasisPoints) external override onlyOwner {
        if (asset == address(0)) {
            revert ZeroAddress();
        }
        if (limitBasisPoints > MAX_LIMIT) {
            revert LimitTooHigh(limitBasisPoints);
        }
        uint256 oldLimit = assetExposureLimit[asset];
        assetExposureLimit[asset] = limitBasisPoints;
        emit AssetLimitSet(asset, oldLimit, limitBasisPoints);
    }

    /**
     * @inheritdoc IExposureLimit
     */
    function setTotalLimit(uint256 limitBasisPoints) external override onlyOwner {
        if (limitBasisPoints > MAX_LIMIT) {
            revert LimitTooHigh(limitBasisPoints);
        }
        uint256 oldLimit = totalExposureLimit;
        totalExposureLimit = limitBasisPoints;
        emit TotalLimitSet(oldLimit, limitBasisPoints);
    }

    /**
     * @inheritdoc IExposureLimit
     */
    function getProtocolLimit(address protocol) external view override returns (uint256) {
        return protocolExposureLimit[protocol];
    }

    /**
     * @inheritdoc IExposureLimit
     */
    function getAssetLimit(address asset) external view override returns (uint256) {
        return assetExposureLimit[asset];
    }

    /**
     * @inheritdoc IExposureLimit
     */
    function getTotalLimit() external view override returns (uint256) {
        return totalExposureLimit;
    }
}
