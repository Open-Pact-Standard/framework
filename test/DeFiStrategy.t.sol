// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {DeFiStrategy} from "contracts/defi/DeFiStrategy.sol";
import {IDeFiStrategy} from "contracts/interfaces/IDeFiStrategy.sol";
import {StrategyRegistry} from "contracts/defi/StrategyRegistry.sol";
import {IStrategyRegistry} from "contracts/interfaces/IStrategyRegistry.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockDeFiStrategy is DeFiStrategy {
    uint256 public mockBalance;
    uint256 public mockAPY;
    uint256 public mockRiskScore;

    constructor(
        address _treasury,
        address _token,
        uint256 _riskScore
    ) DeFiStrategy(_treasury, _token) {
        mockRiskScore = _riskScore;
        mockAPY = 500; // 5%
    }

    function deposit(uint256 amount) external override onlyTreasury nonReentrant {
        _pullTokens(amount);
        strategyBalances[address(this)] += amount;
        mockBalance += amount;
        emit Deposited(address(this), amount);
    }

    function withdraw(uint256 amount) external override onlyTreasury nonReentrant {
        require(amount <= strategyBalances[address(this)], "Exceeds balance");
        strategyBalances[address(this)] -= amount;
        mockBalance -= amount;
        _pushTokens(amount);
        emit Withdrawn(address(this), amount);
    }

    function getBalance() external view override returns (uint256) {
        return mockBalance;
    }

    function getAPY() external view override returns (uint256) {
        return mockAPY;
    }

    function getProtocolRiskScore() external view override returns (uint256) {
        return mockRiskScore;
    }
}

contract DeFiStrategyTest is Test {
    StrategyRegistry public registry;
    MockDeFiStrategy public strategy;
    MockERC20 public token;
    address public treasury;
    address public nonTreasury;

    function setUp() public {
        treasury = address(this);
        nonTreasury = makeAddr("nonTreasury");
        token = new MockERC20("Test Token", "TST");
        registry = new StrategyRegistry();
        strategy = new MockDeFiStrategy(treasury, address(token), 3);

        // Fund treasury with tokens
        token.mint(treasury, 1_000_000 * 10**18);
        // Approve strategy to spend treasury tokens
        token.approve(address(strategy), 1_000_000 * 10**18);
    }

    // === DeFiStrategy Base Tests ===

    function testStrategyDeployment() public view {
        assertEq(strategy.getTreasury(), treasury);
        assertEq(strategy.getToken(), address(token));
        assertEq(strategy.getBalance(), 0);
        assertEq(strategy.getAPY(), 500);
        assertEq(strategy.getProtocolRiskScore(), 3);
    }

    function testStrategyDeposit() public {
        strategy.deposit(1000 * 10**18);
        assertEq(strategy.getBalance(), 1000 * 10**18);
        assertEq(token.balanceOf(address(strategy)), 1000 * 10**18);
    }

    function testStrategyWithdraw() public {
        strategy.deposit(1000 * 10**18);
        strategy.withdraw(500 * 10**18);
        assertEq(strategy.getBalance(), 500 * 10**18);
        assertEq(token.balanceOf(treasury), 999_500 * 10**18);
    }

    function testRevertDepositNonTreasury() public {
        vm.prank(nonTreasury);
        vm.expectRevert(abi.encodeWithSelector(DeFiStrategy.NotTreasury.selector, nonTreasury));
        strategy.deposit(1000);
    }

    function testRevertWithdrawNonTreasury() public {
        strategy.deposit(1000);
        vm.prank(nonTreasury);
        vm.expectRevert(abi.encodeWithSelector(DeFiStrategy.NotTreasury.selector, nonTreasury));
        strategy.withdraw(500);
    }

    function testRevertWithdrawExceedsBalance() public {
        strategy.deposit(1000);
        vm.expectRevert("Exceeds balance");
        strategy.withdraw(2000);
    }

    function testDepositEvent() public {
        vm.expectEmit(true, false, false, true);
        emit IDeFiStrategy.Deposited(address(strategy), 1000 * 10**18);
        strategy.deposit(1000 * 10**18);
    }

    function testWithdrawEvent() public {
        strategy.deposit(1000 * 10**18);
        vm.expectEmit(true, false, false, true);
        emit IDeFiStrategy.Withdrawn(address(strategy), 500 * 10**18);
        strategy.withdraw(500 * 10**18);
    }

    // === StrategyRegistry Tests ===

    function testRegisterStrategy() public {
        registry.registerStrategy(address(strategy), "MockLend", "Mock lending strategy", 3);
        assertTrue(registry.isStrategyActive(address(strategy)));

        IStrategyRegistry.StrategyInfo memory info = registry.getStrategy(address(strategy));
        assertEq(info.protocolName, "MockLend");
        assertEq(info.riskScore, 3);
        assertTrue(info.active);
    }

    function testRegisterMultipleStrategies() public {
        MockDeFiStrategy strategy2 = new MockDeFiStrategy(treasury, address(token), 5);
        registry.registerStrategy(address(strategy), "MockLend", "Lending", 3);
        registry.registerStrategy(address(strategy2), "MockLP", "LP", 5);

        address[] memory strategies = registry.getStrategies();
        assertEq(strategies.length, 2);
        assertEq(registry.getStrategyCount(), 2);
    }

    function testDeactivateStrategy() public {
        registry.registerStrategy(address(strategy), "MockLend", "Lending", 3);
        registry.deactivateStrategy(address(strategy));
        assertFalse(registry.isStrategyActive(address(strategy)));
    }

    function testActivateStrategy() public {
        registry.registerStrategy(address(strategy), "MockLend", "Lending", 3);
        registry.deactivateStrategy(address(strategy));
        registry.activateStrategy(address(strategy));
        assertTrue(registry.isStrategyActive(address(strategy)));
    }

    function testUpdateStrategy() public {
        registry.registerStrategy(address(strategy), "MockLend", "Lending", 3);
        registry.updateStrategy(address(strategy), "MockLendV2", "Updated lending", 4);

        IStrategyRegistry.StrategyInfo memory info = registry.getStrategy(address(strategy));
        assertEq(info.protocolName, "MockLendV2");
        assertEq(info.riskScore, 4);
    }

    function testRevertDuplicateRegistration() public {
        registry.registerStrategy(address(strategy), "MockLend", "Lending", 3);
        vm.expectRevert(
            abi.encodeWithSelector(StrategyRegistry.StrategyAlreadyRegistered.selector, address(strategy))
        );
        registry.registerStrategy(address(strategy), "Dup", "Dup", 5);
    }

    function testRevertInvalidRiskScore() public {
        vm.expectRevert(
            abi.encodeWithSelector(StrategyRegistry.InvalidRiskScore.selector, uint256(0))
        );
        registry.registerStrategy(address(strategy), "Bad", "Bad", 0);

        vm.expectRevert(
            abi.encodeWithSelector(StrategyRegistry.InvalidRiskScore.selector, uint256(11))
        );
        registry.registerStrategy(address(strategy), "Bad", "Bad", 11);
    }

    function testRevertNonExistentStrategy() public {
        address fake = makeAddr("fake");
        vm.expectRevert(
            abi.encodeWithSelector(StrategyRegistry.StrategyNotFound.selector, fake)
        );
        registry.getStrategy(fake);
    }

    function testOnlyOwnerCanRegister() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        registry.registerStrategy(address(strategy), "Hack", "Hack", 1);
    }
}
