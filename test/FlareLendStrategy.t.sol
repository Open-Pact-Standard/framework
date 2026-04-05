// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {FlareLendStrategy} from "contracts/defi/protocols/FlareLendStrategy.sol";
import {DeFiStrategy} from "contracts/defi/DeFiStrategy.sol";
import {IDeFiStrategy} from "contracts/interfaces/IDeFiStrategy.sol";
import {IFlareLend} from "contracts/interfaces/IFlareLend.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract MockFlareLend is IFlareLend {
    mapping(address => mapping(address => uint256)) public deposits;
    uint256 public liquidityRate = 5e25; // ~5% APY

    function deposit(address asset, uint256 amount, address onBehalfOf, uint16) external {
        deposits[asset][onBehalfOf] += amount;
        IERC20(asset).transferFrom(msg.sender, address(this), amount);
    }

    function withdraw(address asset, uint256 amount, address to) external returns (uint256) {
        uint256 available = deposits[asset][msg.sender];
        uint256 toWithdraw = amount > available ? available : amount;
        deposits[asset][msg.sender] -= toWithdraw;
        IERC20(asset).transfer(to, toWithdraw);
        return toWithdraw;
    }

    function getUserAccountData(address) external pure override returns (
        uint256, uint256, uint256, uint256, uint256, uint256
    ) {
        return (0, 0, 0, 0, 0, 0);
    }

    function getReserveData(address) external view override returns (
        uint256, uint256, uint256, uint256, uint256,
        uint256 currentLiquidityRate,
        uint256, uint256, uint256, uint256, uint256
    ) {
        return (0, 0, 0, 0, 0, currentLiquidityRate = liquidityRate, 0, 0, 0, 0, 0);
    }
}

contract FlareLendStrategyTest is Test {
    FlareLendStrategy public strategy;
    MockFlareLend public flareLend;
    MockERC20 public token;
    address public treasury;
    address public nonTreasury;

    function setUp() public {
        treasury = address(this);
        nonTreasury = makeAddr("nonTreasury");
        token = new MockERC20("FLR Token", "FLR");
        flareLend = new MockFlareLend();
        strategy = new FlareLendStrategy(treasury, address(token), flareLend, 3);

        token.mint(treasury, 1_000_000 * 10**18);
        token.approve(address(strategy), 1_000_000 * 10**18);
    }

    function testDeployment() public view {
        assertEq(strategy.getTreasury(), treasury);
        assertEq(strategy.getToken(), address(token));
        assertEq(strategy.getProtocolRiskScore(), 3);
        assertEq(address(strategy.flareLendPool()), address(flareLend));
    }

    function testDeposit() public {
        strategy.deposit(1000 * 10**18);
        assertEq(strategy.getBalance(), 1000 * 10**18);
        assertEq(flareLend.deposits(address(token), address(strategy)), 1000 * 10**18);
    }

    function testWithdraw() public {
        strategy.deposit(1000 * 10**18);
        strategy.withdraw(500 * 10**18);
        assertEq(strategy.getBalance(), 500 * 10**18);
        assertEq(token.balanceOf(treasury), 999_500 * 10**18);
    }

    function testWithdrawAll() public {
        strategy.deposit(1000 * 10**18);
        strategy.withdraw(1000 * 10**18);
        assertEq(strategy.getBalance(), 0);
        assertEq(token.balanceOf(treasury), 1_000_000 * 10**18);
    }

    function testRevertWithdrawExceedsBalance() public {
        strategy.deposit(1000 * 10**18);
        vm.expectRevert(
            abi.encodeWithSelector(
                FlareLendStrategy.WithdrawalExceedsBalance.selector,
                uint256(2000 * 10**18),
                uint256(1000 * 10**18)
            )
        );
        strategy.withdraw(2000 * 10**18);
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

    function testGetAPY() public {
        uint256 apy = strategy.getAPY();
        // liquidityRate = 5e25, APY = 5e25 * 10000 / 1e27 = 500 bps = 5%
        assertEq(apy, 500);
    }

    function testGetProtocolRiskScore() public view {
        assertEq(strategy.getProtocolRiskScore(), 3);
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

    function testMultipleDeposits() public {
        strategy.deposit(1000 * 10**18);
        strategy.deposit(2000 * 10**18);
        assertEq(strategy.getBalance(), 3000 * 10**18);
    }

    function testMultipleWithdrawals() public {
        strategy.deposit(3000 * 10**18);
        strategy.withdraw(1000 * 10**18);
        strategy.withdraw(500 * 10**18);
        assertEq(strategy.getBalance(), 1500 * 10**18);
    }

    function testRevertZeroAddressPool() public {
        vm.expectRevert(FlareLendStrategy.InvalidFlareLendPool.selector);
        new FlareLendStrategy(treasury, address(token), IFlareLend(address(0)), 3);
    }
}
