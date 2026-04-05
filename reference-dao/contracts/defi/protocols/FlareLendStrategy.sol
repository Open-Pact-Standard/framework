// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../DeFiStrategy.sol";
import "../../interfaces/IFlareLend.sol";

/**
 * @title FlareLendStrategy
 * @dev Concrete lending strategy for FlareLend (Aave V2 fork).
 *      Deposits tokens into FlareLend lending pool to earn yield.
 */
contract FlareLendStrategy is DeFiStrategy {
    using SafeERC20 for IERC20;

    IFlareLend public immutable flareLendPool;
    uint256 public immutable protocolRiskScore;

    error InvalidFlareLendPool();
    error WithdrawalExceedsBalance(uint256 requested, uint256 available);

    uint256 private constant RAY = 1e27;

    /**
     * @dev Deploy the FlareLend strategy.
     * @param _treasury Treasury address (authorized caller)
     * @param _token Token to lend
     * @param _flareLendPool FlareLend lending pool address
     * @param _riskScore Risk score (1-10)
     */
    constructor(
        address _treasury,
        address _token,
        IFlareLend _flareLendPool,
        uint256 _riskScore
    ) DeFiStrategy(_treasury, _token) {
        if (address(_flareLendPool) == address(0)) {
            revert InvalidFlareLendPool();
        }
        flareLendPool = _flareLendPool;
        protocolRiskScore = _riskScore;
    }

    /**
     * @inheritdoc IDeFiStrategy
     */
    function deposit(uint256 amount) external override onlyTreasury nonReentrant {
        _pullTokens(amount);
        strategyBalances[address(this)] += amount;

        // Approve FlareLend to spend tokens (zero-then-amount pattern for safety)
        IERC20(token).safeApprove(address(flareLendPool), 0);
        IERC20(token).safeApprove(address(flareLendPool), amount);

        flareLendPool.deposit(token, amount, address(this), 0);

        emit Deposited(address(this), amount);
    }

    /**
     * @inheritdoc IDeFiStrategy
     */
    function withdraw(uint256 amount) external override onlyTreasury nonReentrant {
        if (amount > strategyBalances[address(this)]) {
            revert WithdrawalExceedsBalance(amount, strategyBalances[address(this)]);
        }

        strategyBalances[address(this)] -= amount;
        flareLendPool.withdraw(token, amount, treasury);

        emit Withdrawn(address(this), amount);
    }

    /**
     * @inheritdoc IDeFiStrategy
     */
    function getBalance() external view override returns (uint256) {
        // Strategy balance is tracked in strategyBalances
        // Could also query aToken balance if aToken address is known
        return strategyBalances[address(this)];
    }

    /**
     * @inheritdoc IDeFiStrategy
     * @dev Converts FlareLend liquidity rate to APY in basis points.
     *      liquidityRate is in RAY (1e27) — annualized, where 1e27 = 100%.
     */
    function getAPY() external view override returns (uint256) {
        (
            ,
            ,
            ,
            ,
            ,
            uint256 currentLiquidityRate,
            ,
            ,
            ,
            ,
        ) = flareLendPool.getReserveData(token);

        // Aave V2 liquidity rate is in RAY (1e27 = 100%)
        // Convert to basis points: rate * 10000 / RAY
        if (currentLiquidityRate == 0) {
            return 0;
        }
        return currentLiquidityRate * 10000 / RAY;
    }

    /**
     * @inheritdoc IDeFiStrategy
     */
    function getProtocolRiskScore() external view override returns (uint256) {
        return protocolRiskScore;
    }
}
