// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IDeFiTreasuryExtension.sol";
import "../interfaces/IDeFiStrategy.sol";
import "../interfaces/IStrategyRegistry.sol";
import "../interfaces/IRiskManager.sol";
import "../interfaces/ITreasury.sol";

/**
 * @title DeFiTreasuryExtension
 * @dev Bridges the multi-sig Treasury with DeFi strategies.
 *      Validates via RiskManager, manages through StrategyRegistry.
 *      Only treasury signers can deploy/withdraw.
 */
contract DeFiTreasuryExtension is IDeFiTreasuryExtension, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    ITreasury public immutable treasury;
    IStrategyRegistry public immutable strategyRegistry;
    IRiskManager public immutable riskManager;

    error StrategyNotActive(address strategy);
    error DeploymentNotAllowed(string reason);
    error WithdrawalExceedsBalance(uint256 requested, uint256 available);
    error NotTreasurySigner(address caller);
    error InvalidStrategy(address strategy);

    modifier onlySigner() {
        if (!treasury.isSigner(msg.sender)) {
            revert NotTreasurySigner(msg.sender);
        }
        _;
    }

    /**
     * @dev Deploy the treasury extension.
     * @param _treasury Treasury contract (for signer checks)
     * @param _strategyRegistry Strategy registry
     * @param _riskManager Risk manager for validation
     */
    constructor(
        ITreasury _treasury,
        IStrategyRegistry _strategyRegistry,
        IRiskManager _riskManager
    ) Ownable() {
        if (address(_treasury) == address(0) || address(_strategyRegistry) == address(0) || address(_riskManager) == address(0)) {
            revert InvalidStrategy(address(0));
        }
        treasury = _treasury;
        strategyRegistry = _strategyRegistry;
        riskManager = _riskManager;
    }

    /**
     * @inheritdoc IDeFiTreasuryExtension
     */
    function deployToStrategy(
        address strategy,
        uint256 amount
    ) external override onlySigner nonReentrant whenNotPaused {
        if (!strategyRegistry.isStrategyActive(strategy)) {
            revert StrategyNotActive(strategy);
        }

        // Validate via RiskManager
        (bool allowed, string memory reason) = riskManager.validateDeployment(strategy, amount);
        if (!allowed) {
            revert DeploymentNotAllowed(reason);
        }

        // Get token from strategy
        address tokenAddr = IDeFiStrategy(strategy).getToken();

        // Transfer tokens from treasury to strategy
        IERC20(tokenAddr).safeTransferFrom(address(treasury), strategy, amount);

        // Deposit into strategy
        IDeFiStrategy(strategy).deposit(amount);

        // Update RiskManager exposure
        riskManager.updateExposure(strategy, amount, true);

        // Update strategy metrics
        uint256 newBalance = IDeFiStrategy(strategy).getBalance();
        riskManager.updateStrategyMetrics(strategy, newBalance);

        emit StrategyDeployed(strategy, amount);
    }

    /**
     * @inheritdoc IDeFiTreasuryExtension
     */
    function withdrawFromStrategy(
        address strategy,
        uint256 amount
    ) external override onlySigner nonReentrant whenNotPaused {
        if (!strategyRegistry.isStrategyActive(strategy)) {
            revert StrategyNotActive(strategy);
        }

        IDeFiStrategy strat = IDeFiStrategy(strategy);
        uint256 currentBalance = strat.getBalance();

        if (amount > currentBalance) {
            revert WithdrawalExceedsBalance(amount, currentBalance);
        }

        // Check if drawdown should trigger full unwind
        bool shouldUnwind = riskManager.checkDrawdown(strategy, currentBalance);
        if (shouldUnwind) {
            amount = currentBalance;
        }

        // Withdraw from strategy (tokens go to treasury)
        strat.withdraw(amount);

        // Update RiskManager exposure
        riskManager.updateExposure(strategy, amount, false);

        emit StrategyWithdrawn(strategy, amount);
    }

    /**
     * @inheritdoc IDeFiTreasuryExtension
     */
    function getStrategyBalance(address strategy) external view override returns (uint256) {
        return IDeFiStrategy(strategy).getBalance();
    }

    /**
     * @inheritdoc IDeFiTreasuryExtension
     */
    function getStrategyAPY(address strategy) external view override returns (uint256) {
        return IDeFiStrategy(strategy).getAPY();
    }

    /**
     * @inheritdoc IDeFiTreasuryExtension
     */
    function getTotalDeFiExposure() external view override returns (uint256) {
        return riskManager.getTotalExposure();
    }

    /**
     * @inheritdoc IDeFiTreasuryExtension
     */
    function getRegisteredStrategies() external view override returns (address[] memory) {
        return strategyRegistry.getStrategies();
    }

    /**
     * @inheritdoc IDeFiTreasuryExtension
     */
    function isStrategyActive(address strategy) external view override returns (bool) {
        return strategyRegistry.isStrategyActive(strategy);
    }

    /**
     * @dev Pause the contract (owner only)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract (owner only)
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
