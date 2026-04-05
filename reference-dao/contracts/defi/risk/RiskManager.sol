// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../../interfaces/IRiskManager.sol";
import "../../interfaces/IDeFiStrategy.sol";
import "./ExposureLimit.sol";

/**
 * @title RiskManager
 * @dev Validates deployments against exposure limits and tracks drawdown triggers.
 *      Uses ExposureLimit for limit configuration and IDeFiStrategy for balance queries.
 */
contract RiskManager is IRiskManager, Ownable, ReentrancyGuard {
    address public immutable treasury;
    ExposureLimit public immutable exposureLimit;

    // Current exposure tracking
    mapping(address => uint256) public protocolExposure;
    mapping(address => uint256) public assetExposure;
    uint256 public totalDeFiExposure;

    // Drawdown tracking
    mapping(address => uint256) public strategyPeakValue;
    mapping(address => uint256) public strategyEntryValue;
    mapping(address => uint256) public strategyEntryTime;

    // Drawdown thresholds (basis points)
    uint256 public drawdownThreshold = 2000; // 20%
    uint256 public timeBasedDrawdownThreshold = 1500; // 15%
    uint256 public timeBasedDrawdownPeriod = 7 days;

    error NotTreasury(address caller);
    error ProtocolExposureExceeded(address protocol, uint256 current, uint256 limit);
    error AssetExposureExceeded(address asset, uint256 current, uint256 limit);
    error TotalExposureExceeded(uint256 current, uint256 limit);
    error InvalidStrategy(address strategy);

    modifier onlyTreasury() {
        if (msg.sender != treasury) {
            revert NotTreasury(msg.sender);
        }
        _;
    }

    /**
     * @dev Deploy the risk manager.
     * @param _treasury Treasury address (only caller for exposure updates)
     * @param _exposureLimit ExposureLimit contract for limit configuration
     */
    constructor(address _treasury, ExposureLimit _exposureLimit) Ownable() {
        if (_treasury == address(0)) {
            revert InvalidStrategy(address(0));
        }
        treasury = _treasury;
        exposureLimit = _exposureLimit;
    }

    /**
     * @inheritdoc IRiskManager
     */
    function validateDeployment(
        address strategy,
        uint256 amount
    ) external view override returns (bool allowed, string memory reason) {
        if (strategy == address(0)) {
            return (false, "Invalid strategy");
        }

        IDeFiStrategy strat = IDeFiStrategy(strategy);
        address protocol = strategy; // Strategy address as protocol identifier
        address tokenAddr = strat.getToken();

        // Check protocol exposure
        uint256 protocolLimit = exposureLimit.getProtocolLimit(protocol);
        if (protocolLimit > 0) {
            uint256 newProtocolExposure = protocolExposure[protocol] + amount;
            // Calculate max allowed based on total DeFi and protocol limit
            // protocolLimit is in basis points of total treasury (approximated by totalDeFiExposure)
            uint256 maxAllowed = (totalDeFiExposure + amount) * protocolLimit / 10000;
            if (newProtocolExposure > maxAllowed) {
                return (false, "Protocol exposure exceeded");
            }
        }

        // Check asset exposure
        uint256 assetLimit = exposureLimit.getAssetLimit(tokenAddr);
        if (assetLimit > 0) {
            uint256 newAssetExposure = assetExposure[tokenAddr] + amount;
            uint256 maxAllowed = (totalDeFiExposure + amount) * assetLimit / 10000;
            if (newAssetExposure > maxAllowed) {
                return (false, "Asset exposure exceeded");
            }
        }

        // Check total exposure
        uint256 totalLimit = exposureLimit.getTotalLimit();
        if (totalLimit > 0) {
            uint256 newTotalExposure = totalDeFiExposure + amount;
            // Total limit is absolute, not relative
            if (newTotalExposure > totalLimit) {
                return (false, "Total exposure exceeded");
            }
        }

        return (true, "");
    }

    /**
     * @inheritdoc IRiskManager
     */
    function updateExposure(
        address strategy,
        uint256 amount,
        bool isDeployment
    ) external override onlyTreasury nonReentrant {
        if (strategy == address(0)) {
            revert InvalidStrategy(strategy);
        }

        address protocol = strategy;
        address tokenAddr = IDeFiStrategy(strategy).getToken();

        if (isDeployment) {
            protocolExposure[protocol] += amount;
            assetExposure[tokenAddr] += amount;
            totalDeFiExposure += amount;
        } else {
            protocolExposure[protocol] = protocolExposure[protocol] > amount
                ? protocolExposure[protocol] - amount
                : 0;
            assetExposure[tokenAddr] = assetExposure[tokenAddr] > amount
                ? assetExposure[tokenAddr] - amount
                : 0;
            totalDeFiExposure = totalDeFiExposure > amount
                ? totalDeFiExposure - amount
                : 0;
        }

        emit ExposureUpdated(strategy, amount, isDeployment);
    }

    /**
     * @inheritdoc IRiskManager
     */
    function checkDrawdown(
        address strategy,
        uint256 currentValue
    ) external view override returns (bool shouldUnwind) {
        uint256 peak = strategyPeakValue[strategy];
        uint256 entry = strategyEntryValue[strategy];
        uint256 entryTime = strategyEntryTime[strategy];

        if (peak == 0 || currentValue >= peak) {
            return false;
        }

        // Peak-based drawdown: >20% from peak
        uint256 dropFromPeak = (peak - currentValue) * 10000 / peak;
        if (dropFromPeak >= drawdownThreshold) {
            return true;
        }

        // Time-based drawdown: >15% within 7 days of entry
        if (entry > 0 && entryTime > 0) {
            bool isWithinPeriod = block.timestamp - entryTime < timeBasedDrawdownPeriod;
            if (isWithinPeriod && currentValue < entry) {
                uint256 dropFromEntry = (entry - currentValue) * 10000 / entry;
                if (dropFromEntry >= timeBasedDrawdownThreshold) {
                    return true;
                }
            }
        }

        return false;
    }

    /**
     * @inheritdoc IRiskManager
     */
    function updateStrategyMetrics(
        address strategy,
        uint256 currentValue
    ) external override onlyTreasury {
        if (currentValue > strategyPeakValue[strategy]) {
            strategyPeakValue[strategy] = currentValue;
        }
        if (strategyEntryValue[strategy] == 0 && currentValue > 0) {
            strategyEntryValue[strategy] = currentValue;
            strategyEntryTime[strategy] = block.timestamp;
        }
        emit StrategyMetricsUpdated(strategy, currentValue);
    }

    /**
     * @dev Set the peak drawdown threshold.
     * @param thresholdBasisPoints New threshold (e.g. 2000 = 20%)
     */
    function setDrawdownThreshold(uint256 thresholdBasisPoints) external onlyOwner {
        uint256 old = drawdownThreshold;
        drawdownThreshold = thresholdBasisPoints;
        emit DrawdownThresholdUpdated(old, thresholdBasisPoints);
    }

    /**
     * @dev Set time-based drawdown threshold and period.
     * @param thresholdBasisPoints New threshold (e.g. 1500 = 15%)
     * @param period Time period (e.g. 7 days)
     */
    function setTimeBasedDrawdown(uint256 thresholdBasisPoints, uint256 period) external onlyOwner {
        timeBasedDrawdownThreshold = thresholdBasisPoints;
        timeBasedDrawdownPeriod = period;
    }

    /**
     * @inheritdoc IRiskManager
     */
    function getExposure(address protocol) external view override returns (uint256) {
        return protocolExposure[protocol];
    }

    /**
     * @inheritdoc IRiskManager
     */
    function getTotalExposure() external view override returns (uint256) {
        return totalDeFiExposure;
    }
}
