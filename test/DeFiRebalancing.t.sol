// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {DeFiStrategy} from "contracts/defi/DeFiStrategy.sol";
import {StrategyRegistry} from "contracts/defi/StrategyRegistry.sol";
import {IStrategyRegistry} from "contracts/interfaces/IStrategyRegistry.sol";
import {ExposureLimit} from "contracts/defi/risk/ExposureLimit.sol";
import {RiskManager} from "contracts/defi/risk/RiskManager.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockStrategy
 * @dev Mock DeFi strategy for testing
 */
contract MockStrategy is DeFiStrategy {
    uint256 public balance;
    uint256 public apy;
    uint256 public riskScore;

    event Deposited(uint256 amount);
    event Withdrawn(uint256 amount);

    constructor(address _treasury, address _token, uint256 _apy, uint256 _riskScore)
        DeFiStrategy(_treasury, _token)
    {
        apy = _apy;
        riskScore = _riskScore;
    }

    function deposit(uint256 amount) external override onlyTreasury nonReentrant {
        _pullTokens(amount);
        balance += amount;
        emit Deposited(amount);
    }

    function withdraw(uint256 amount) external override onlyTreasury nonReentrant {
        require(balance >= amount, "Insufficient balance");
        balance -= amount;
        _pushTokens(amount);
        emit Withdrawn(amount);
    }

    function getBalance() external view override returns (uint256) {
        return balance;
    }

    function getAPY() external view override returns (uint256) {
        return apy;
    }

    function getProtocolRiskScore() external view override returns (uint256) {
        return riskScore;
    }

    function simulateYield(uint256 yieldAmount) external {
        balance += yieldAmount;
    }
}

/**
 * @title DeFiRebalancingIntegrationTest
 * @dev Tests DeFi strategy rebalancing and portfolio management
 */
contract DeFiRebalancingIntegrationTest is Test {
    StrategyRegistry public registry;
    ExposureLimit public exposureLimit;
    RiskManager public riskManager;

    // Strategies
    MockStrategy public conservativeStrategy;  // Low risk, low APY
    MockStrategy public balancedStrategy;      // Medium risk, medium APY
    MockStrategy public aggressiveStrategy;    // High risk, high APY

    MockERC20 public token;

    // Addresses
    address public treasury;
    address public overseer;

    // Constants
    uint256 constant INITIAL_DEPOSIT = 1_000_000 * 10**18;
    uint256 constant CONSERVATIVE_APY = 300;      // 3%
    uint256 constant BALANCED_APY = 600;         // 6%
    uint256 constant AGGRESSIVE_APY = 1200;      // 12%

    function setUp() public {
        treasury = makeAddr("treasury");
        overseer = makeAddr("overseer");

        _deployContracts();
        _configureContracts();
        _deployStrategies();
        _registerStrategies();
    }

    function _deployContracts() private {
        // Deploy token
        token = new MockERC20();

        // Deploy DeFi infrastructure
        registry = new StrategyRegistry();
        exposureLimit = new ExposureLimit();
        riskManager = new RiskManager(treasury, exposureLimit);
    }

    function _configureContracts() private {
        // Configure exposure limits (in basis points, 10000 = 100%)
        // Note: test contract is the owner of ExposureLimit, deployed in _deployContracts
        exposureLimit.setTotalLimit(10000); // 100% of treasury
        exposureLimit.setAssetLimit(address(token), 10000); // 100% in this token
    }

    function _deployStrategies() private {
        conservativeStrategy = new MockStrategy(
            treasury,
            address(token),
            CONSERVATIVE_APY,
            2 // Low risk
        );

        balancedStrategy = new MockStrategy(
            treasury,
            address(token),
            BALANCED_APY,
            5 // Medium risk
        );

        aggressiveStrategy = new MockStrategy(
            treasury,
            address(token),
            AGGRESSIVE_APY,
            8 // High risk
        );
    }

    function _registerStrategies() private {
        // Note: test contract is the owner of StrategyRegistry, deployed in _deployContracts
        registry.registerStrategy(
            address(conservativeStrategy),
            "ConservativeLend",
            "Low-risk lending strategy",
            2
        );

        registry.registerStrategy(
            address(balancedStrategy),
            "BalancedYield",
            "Balanced yield strategy",
            5
        );

        registry.registerStrategy(
            address(aggressiveStrategy),
            "AggressiveFarm",
            "High-yield farming strategy",
            8
        );
    }

    // ============ Strategy Registry Tests ============

    function testGetAllStrategies() public {
        address[] memory strategies = registry.getStrategies();

        assertEq(strategies.length, 3);
        assertTrue(_contains(strategies, address(conservativeStrategy)));
        assertTrue(_contains(strategies, address(balancedStrategy)));
        assertTrue(_contains(strategies, address(aggressiveStrategy)));
    }

    function testGetStrategyInfo() public {
        IStrategyRegistry.StrategyInfo memory info = registry.getStrategy(address(conservativeStrategy));

        assertEq(info.protocolName, "ConservativeLend");
        assertEq(info.description, "Low-risk lending strategy");
        assertEq(info.riskScore, 2);
        assertTrue(info.active);
    }

    function testDeactivateStrategy() public {
        // Test contract is owner of StrategyRegistry
        registry.deactivateStrategy(address(conservativeStrategy));

        assertFalse(registry.isStrategyActive(address(conservativeStrategy)));
    }

    function testReactivateStrategy() public {
        // Test contract is owner of StrategyRegistry
        registry.deactivateStrategy(address(conservativeStrategy));

        assertFalse(registry.isStrategyActive(address(conservativeStrategy)));

        registry.activateStrategy(address(conservativeStrategy));

        assertTrue(registry.isStrategyActive(address(conservativeStrategy)));
    }

    // ============ Strategy Deployment Tests ============

    function testConservativeDeployment() public {
        // Fund treasury with tokens
        token.mint(treasury, INITIAL_DEPOSIT);

        // Approve strategy to spend
        vm.prank(treasury);
        token.approve(address(conservativeStrategy), INITIAL_DEPOSIT);

        // Deploy to strategy
        uint256 amount = 500_000 * 10**18;
        vm.prank(treasury);
        conservativeStrategy.deposit(amount);

        assertEq(conservativeStrategy.getBalance(), amount);
    }

    function testBalancedDeployment() public {
        // Fund treasury
        token.mint(treasury, INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(balancedStrategy), INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(conservativeStrategy), INITIAL_DEPOSIT);

        // Deploy 50/50
        uint256 amountPerStrategy = 250_000 * 10**18;

        vm.prank(treasury);
        balancedStrategy.deposit(amountPerStrategy);

        vm.prank(treasury);
        conservativeStrategy.deposit(amountPerStrategy);

        assertEq(balancedStrategy.getBalance(), amountPerStrategy);
        assertEq(conservativeStrategy.getBalance(), amountPerStrategy);
    }

    function testAggressiveDeployment() public {
        // Fund treasury
        token.mint(treasury, INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(conservativeStrategy), INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(balancedStrategy), INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(aggressiveStrategy), INITIAL_DEPOSIT);

        // Deploy 60% aggressive, 30% balanced, 10% conservative
        uint256 aggressiveAmount = 600_000 * 10**18;
        uint256 balancedAmount = 300_000 * 10**18;
        uint256 conservativeAmount = 100_000 * 10**18;

        vm.prank(treasury);
        aggressiveStrategy.deposit(aggressiveAmount);

        vm.prank(treasury);
        balancedStrategy.deposit(balancedAmount);

        vm.prank(treasury);
        conservativeStrategy.deposit(conservativeAmount);

        assertEq(aggressiveStrategy.getBalance(), aggressiveAmount);
        assertEq(balancedStrategy.getBalance(), balancedAmount);
        assertEq(conservativeStrategy.getBalance(), conservativeAmount);
    }

    // ============ Rebalancing Tests ============

    function testRebalanceFromConservativeToBalanced() public {
        // Initial: 100% conservative
        token.mint(treasury, INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(conservativeStrategy), INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(balancedStrategy), INITIAL_DEPOSIT);

        uint256 initialAmount = 500_000 * 10**18;
        vm.prank(treasury);
        conservativeStrategy.deposit(initialAmount);

        // Rebalance: 50% conservative, 50% balanced
        uint256 withdrawAmount = 250_000 * 10**18;

        vm.prank(treasury);
        conservativeStrategy.withdraw(withdrawAmount);

        vm.prank(treasury);
        balancedStrategy.deposit(withdrawAmount);

        // Verify new allocation
        assertEq(conservativeStrategy.getBalance(), 250_000 * 10**18);
        assertEq(balancedStrategy.getBalance(), 250_000 * 10**18);
    }

    function testRebalanceToHigherYield() public {
        // Deploy initial amounts
        token.mint(treasury, INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(conservativeStrategy), INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(balancedStrategy), INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(aggressiveStrategy), INITIAL_DEPOSIT);

        vm.prank(treasury);
        conservativeStrategy.deposit(400_000 * 10**18);

        vm.prank(treasury);
        balancedStrategy.deposit(100_000 * 10**18);

        // Rebalance toward higher yield (aggressive)
        vm.prank(treasury);
        conservativeStrategy.withdraw(200_000 * 10**18);

        vm.prank(treasury);
        aggressiveStrategy.deposit(200_000 * 10**18);

        // Verify rebalanced allocation
        assertEq(conservativeStrategy.getBalance(), 200_000 * 10**18);
        assertEq(balancedStrategy.getBalance(), 100_000 * 10**18);
        assertEq(aggressiveStrategy.getBalance(), 200_000 * 10**18);
    }

    function testPartialRebalance() public {
        // Deploy across all strategies
        token.mint(treasury, INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(conservativeStrategy), INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(balancedStrategy), INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(aggressiveStrategy), INITIAL_DEPOSIT);

        vm.prank(treasury);
        conservativeStrategy.deposit(300_000 * 10**18);

        vm.prank(treasury);
        balancedStrategy.deposit(200_000 * 10**18);

        vm.prank(treasury);
        aggressiveStrategy.deposit(100_000 * 10**18);

        // Partial rebalance: move 100k from conservative to aggressive
        vm.prank(treasury);
        conservativeStrategy.withdraw(100_000 * 10**18);

        vm.prank(treasury);
        aggressiveStrategy.deposit(100_000 * 10**18);

        assertEq(conservativeStrategy.getBalance(), 200_000 * 10**18);
        assertEq(balancedStrategy.getBalance(), 200_000 * 10**18);
        assertEq(aggressiveStrategy.getBalance(), 200_000 * 10**18);
    }

    // ============ Yield Calculation Tests ============

    function testCalculateExpectedYields() public {
        // Deploy equal amounts to all strategies
        uint256 amountPerStrategy = 100_000 * 10**18;

        token.mint(treasury, INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(conservativeStrategy), INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(balancedStrategy), INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(aggressiveStrategy), INITIAL_DEPOSIT);

        vm.prank(treasury);
        conservativeStrategy.deposit(amountPerStrategy);

        vm.prank(treasury);
        balancedStrategy.deposit(amountPerStrategy);

        vm.prank(treasury);
        aggressiveStrategy.deposit(amountPerStrategy);

        // Calculate expected annual yields
        uint256 conservativeYield = (amountPerStrategy * CONSERVATIVE_APY) / 10000;
        uint256 balancedYield = (amountPerStrategy * BALANCED_APY) / 10000;
        uint256 aggressiveYield = (amountPerStrategy * AGGRESSIVE_APY) / 10000;

        uint256 totalExpectedYield = conservativeYield + balancedYield + aggressiveYield;

        // Verify calculations
        assertEq(conservativeYield, 3_000 * 10**18);
        assertEq(balancedYield, 6_000 * 10**18);
        assertEq(aggressiveYield, 12_000 * 10**18);
        assertEq(totalExpectedYield, 21_000 * 10**18);
    }

    function testYieldAccrual() public {
        uint256 amount = 100_000 * 10**18;

        token.mint(treasury, amount);
        vm.prank(treasury);
        token.approve(address(conservativeStrategy), amount);

        vm.prank(treasury);
        conservativeStrategy.deposit(amount);

        // Simulate yield accrual (1 year)
        uint256 expectedYield = (amount * CONSERVATIVE_APY) / 10000;
        // Mint yield tokens to the strategy so it can withdraw them
        token.mint(address(conservativeStrategy), expectedYield);
        conservativeStrategy.simulateYield(expectedYield);

        // Withdraw total (principal + yield)
        uint256 totalBalance = conservativeStrategy.getBalance();
        assertEq(totalBalance, amount + expectedYield);

        vm.prank(treasury);
        conservativeStrategy.withdraw(totalBalance);

        assertEq(token.balanceOf(treasury), amount + expectedYield);
    }

    // ============ Risk Management Tests ============

    function testExposureLimitConfiguration() public {
        // Total limit set in setUp
        assertEq(exposureLimit.getTotalLimit(), 10000);

        // Asset limit
        assertEq(exposureLimit.getAssetLimit(address(token)), 10000);

        // Update total limit (test contract is owner)
        exposureLimit.setTotalLimit(5000);
        assertEq(exposureLimit.getTotalLimit(), 5000);
    }

    function testStrategyDeactivationPreventsDeployment() public {
        // Test contract is owner of StrategyRegistry
        registry.deactivateStrategy(address(conservativeStrategy));

        assertFalse(registry.isStrategyActive(address(conservativeStrategy)));
    }

    // ============ Multi-Strategy Withdrawal Tests ============

    function testWithdrawFromMultipleStrategies() public {
        // Deploy to all strategies
        token.mint(treasury, INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(conservativeStrategy), INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(balancedStrategy), INITIAL_DEPOSIT);
        vm.prank(treasury);
        token.approve(address(aggressiveStrategy), INITIAL_DEPOSIT);

        vm.prank(treasury);
        conservativeStrategy.deposit(300_000 * 10**18);

        vm.prank(treasury);
        balancedStrategy.deposit(200_000 * 10**18);

        vm.prank(treasury);
        aggressiveStrategy.deposit(100_000 * 10**18);

        // Withdraw from all proportionally
        vm.prank(treasury);
        conservativeStrategy.withdraw(300_000 * 10**18);

        vm.prank(treasury);
        balancedStrategy.withdraw(200_000 * 10**18);

        vm.prank(treasury);
        aggressiveStrategy.withdraw(100_000 * 10**18);

        assertEq(conservativeStrategy.getBalance(), 0);
        assertEq(balancedStrategy.getBalance(), 0);
        assertEq(aggressiveStrategy.getBalance(), 0);
        assertEq(token.balanceOf(treasury), INITIAL_DEPOSIT);
    }

    // ============ Helper Functions ============

    function _contains(address[] memory array, address value) private pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == value) {
                return true;
            }
        }
        return false;
    }
}

// Mock ERC20
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
