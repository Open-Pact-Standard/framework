// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IStrategyRegistry.sol";


/**
 * @title StrategyRegistry
 * @dev Manages the lifecycle of DeFi strategies (register, update, activate, deactivate).
 */
contract StrategyRegistry is IStrategyRegistry, Ownable {
    mapping(address => StrategyInfo) private _strategies;
    address[] private _strategyList;

    error StrategyAlreadyRegistered(address strategy);
    error StrategyNotFound(address strategy);
    error InvalidRiskScore(uint256 score);
    error ZeroAddress();

    constructor() Ownable() {}

    /**
     * @inheritdoc IStrategyRegistry
     */
    function registerStrategy(
        address strategy,
        string calldata protocolName,
        string calldata description,
        uint256 riskScore
    ) external override onlyOwner {
        if (strategy == address(0)) {
            revert ZeroAddress();
        }
        if (_strategies[strategy].registered) {
            revert StrategyAlreadyRegistered(strategy);
        }
        if (riskScore == 0 || riskScore > 10) {
            revert InvalidRiskScore(riskScore);
        }

        _strategies[strategy] = StrategyInfo({
            registered: true,
            active: true,
            protocolName: protocolName,
            description: description,
            riskScore: riskScore,
            createdAt: block.timestamp
        });

        _strategyList.push(strategy);
        emit StrategyRegistered(strategy, protocolName);
    }

    /**
     * @inheritdoc IStrategyRegistry
     */
    function updateStrategy(
        address strategy,
        string calldata protocolName,
        string calldata description,
        uint256 riskScore
    ) external override onlyOwner {
        if (strategy == address(0)) {
            revert ZeroAddress();
        }
        if (!_strategies[strategy].registered) {
            revert StrategyNotFound(strategy);
        }
        if (riskScore == 0 || riskScore > 10) {
            revert InvalidRiskScore(riskScore);
        }

        _strategies[strategy].protocolName = protocolName;
        _strategies[strategy].description = description;
        _strategies[strategy].riskScore = riskScore;

        emit StrategyUpdated(strategy);
    }

    /**
     * @inheritdoc IStrategyRegistry
     */
    function deactivateStrategy(address strategy) external override onlyOwner {
        if (strategy == address(0)) {
            revert ZeroAddress();
        }
        if (!_strategies[strategy].registered) {
            revert StrategyNotFound(strategy);
        }
        _strategies[strategy].active = false;
        emit StrategyDeactivated(strategy);
    }

    /**
     * @inheritdoc IStrategyRegistry
     */
    function activateStrategy(address strategy) external override onlyOwner {
        if (strategy == address(0)) {
            revert ZeroAddress();
        }
        if (!_strategies[strategy].registered) {
            revert StrategyNotFound(strategy);
        }
        _strategies[strategy].active = true;
        emit StrategyActivated(strategy);
    }

    /**
     * @inheritdoc IStrategyRegistry
     */
    function getStrategies() external view override returns (address[] memory) {
        return _strategyList;
    }

    /**
     * @inheritdoc IStrategyRegistry
     */
    function getStrategy(address strategy) external view override returns (StrategyInfo memory) {
        if (!_strategies[strategy].registered) {
            revert StrategyNotFound(strategy);
        }
        return _strategies[strategy];
    }

    /**
     * @inheritdoc IStrategyRegistry
     */
    function isStrategyActive(address strategy) external view override returns (bool) {
        return _strategies[strategy].registered && _strategies[strategy].active;
    }

    /**
     * @dev Get the number of registered strategies.
     * @return Strategy count
     */
    function getStrategyCount() external view returns (uint256) {
        return _strategyList.length;
    }
}
