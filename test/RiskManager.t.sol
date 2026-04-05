// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {ExposureLimit} from "contracts/defi/risk/ExposureLimit.sol";
import {IExposureLimit} from "contracts/interfaces/IExposureLimit.sol";
import {RiskManager} from "contracts/defi/risk/RiskManager.sol";
import {IRiskManager} from "contracts/interfaces/IRiskManager.sol";
import {DeFiStrategy} from "contracts/defi/DeFiStrategy.sol";
import {IDeFiStrategy} from "contracts/interfaces/IDeFiStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockStrategy is DeFiStrategy {
    uint256 public mockBalance;

    constructor(address _treasury, address _token) DeFiStrategy(_treasury, _token) {}

    function deposit(uint256 amount) external override onlyTreasury nonReentrant {
        _pullTokens(amount);
        mockBalance += amount;
        emit Deposited(address(this), amount);
    }

    function withdraw(uint256 amount) external override onlyTreasury nonReentrant {
        mockBalance -= amount;
        _pushTokens(amount);
        emit Withdrawn(address(this), amount);
    }

    function getBalance() external view override returns (uint256) { return mockBalance; }
    function getAPY() external view override returns (uint256) { return 500; }
    function getProtocolRiskScore() external view override returns (uint256) { return 3; }
}

contract RiskManagerTest is Test {
    ExposureLimit public exposureLimit;
    RiskManager public riskManager;
    MockStrategy public strategy;
    MockERC20 public token;
    address public treasury;

    function setUp() public {
        treasury = address(this);
        token = new MockERC20("Test", "TST");
        exposureLimit = new ExposureLimit();
        riskManager = new RiskManager(treasury, exposureLimit);
        strategy = new MockStrategy(treasury, address(token));

        token.mint(treasury, 1_000_000 * 10**18);
        token.approve(address(strategy), 1_000_000 * 10**18);
    }

    // === ExposureLimit Tests ===

    function testSetProtocolLimit() public {
        exposureLimit.setProtocolLimit(address(strategy), 3000); // 30%
        assertEq(exposureLimit.getProtocolLimit(address(strategy)), 3000);
    }

    function testSetAssetLimit() public {
        exposureLimit.setAssetLimit(address(token), 5000); // 50%
        assertEq(exposureLimit.getAssetLimit(address(token)), 5000);
    }

    function testSetTotalLimit() public {
        exposureLimit.setTotalLimit(8000); // 80%
        assertEq(exposureLimit.getTotalLimit(), 8000);
    }

    function testRevertLimitTooHigh() public {
        vm.expectRevert(
            abi.encodeWithSelector(ExposureLimit.LimitTooHigh.selector, uint256(10001))
        );
        exposureLimit.setTotalLimit(10001);
    }

    function testOnlyOwnerSetLimits() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        exposureLimit.setTotalLimit(5000);
    }

    // === RiskManager Validation Tests ===

    function testValidateDeploymentAllowed() public {
        // No limits set — should allow
        (bool allowed, string memory reason) = riskManager.validateDeployment(address(strategy), 1000);
        assertTrue(allowed);
        assertEq(reason, "");
    }

    function testValidateDeploymentBlockProtocolLimit() public {
        // Set exposure first, then set limit below current
        riskManager.updateExposure(address(strategy), 5000, true);
        exposureLimit.setProtocolLimit(address(strategy), 1000); // 10%

        (bool allowed, ) = riskManager.validateDeployment(address(strategy), 1000);
        // Should be blocked because new exposure exceeds protocol limit
        assertFalse(allowed);
    }

    function testValidateDeploymentBlockTotalLimit() public {
        exposureLimit.setTotalLimit(5000);
        riskManager.updateExposure(address(strategy), 4000, true);

        (bool allowed, ) = riskManager.validateDeployment(address(strategy), 2000);
        assertFalse(allowed); // 4000 + 2000 = 6000 > 5000
    }

    // === RiskManager Exposure Tests ===

    function testUpdateExposureDeploy() public {
        riskManager.updateExposure(address(strategy), 1000, true);
        assertEq(riskManager.getExposure(address(strategy)), 1000);
        assertEq(riskManager.getTotalExposure(), 1000);
    }

    function testUpdateExposureWithdraw() public {
        riskManager.updateExposure(address(strategy), 1000, true);
        riskManager.updateExposure(address(strategy), 400, false);
        assertEq(riskManager.getExposure(address(strategy)), 600);
        assertEq(riskManager.getTotalExposure(), 600);
    }

    function testUpdateExposureFloorAtZero() public {
        riskManager.updateExposure(address(strategy), 100, true);
        riskManager.updateExposure(address(strategy), 500, false); // withdraw more than deployed
        assertEq(riskManager.getExposure(address(strategy)), 0);
        assertEq(riskManager.getTotalExposure(), 0);
    }

    function testOnlyTreasuryCanUpdateExposure() public {
        address nonTreasury = makeAddr("nonTreasury");
        vm.prank(nonTreasury);
        vm.expectRevert(abi.encodeWithSelector(RiskManager.NotTreasury.selector, nonTreasury));
        riskManager.updateExposure(address(strategy), 1000, true);
    }

    // === Drawdown Tests ===

    function testNoDrawdownWhenNoPeak() public {
        bool shouldUnwind = riskManager.checkDrawdown(address(strategy), 1000);
        assertFalse(shouldUnwind);
    }

    function testNoDrawdownWhenPriceUp() public {
        riskManager.updateStrategyMetrics(address(strategy), 1000);
        bool shouldUnwind = riskManager.checkDrawdown(address(strategy), 1200);
        assertFalse(shouldUnwind);
    }

    function testDrawdownTriggeredPeak() public {
        riskManager.updateStrategyMetrics(address(strategy), 1000);
        // 25% drop from peak (threshold is 20%)
        bool shouldUnwind = riskManager.checkDrawdown(address(strategy), 750);
        assertTrue(shouldUnwind);
    }

    function testNoDrawdownUnderThreshold() public {
        riskManager.updateStrategyMetrics(address(strategy), 1000);
        // 10% drop from peak (under both 20% peak and 15% time thresholds)
        bool shouldUnwind = riskManager.checkDrawdown(address(strategy), 900);
        assertFalse(shouldUnwind);
    }

    function testDrawdownTimeBased() public {
        riskManager.updateStrategyMetrics(address(strategy), 1000);
        // Value drops 16% within 7 days
        bool shouldUnwind = riskManager.checkDrawdown(address(strategy), 840);
        assertTrue(shouldUnwind); // 16% > 15% time threshold within period
    }

    function testDrawdownPeakUpdated() public {
        riskManager.updateStrategyMetrics(address(strategy), 1000);
        riskManager.updateStrategyMetrics(address(strategy), 1500); // new peak
        // 15% drop from new peak
        bool shouldUnwind = riskManager.checkDrawdown(address(strategy), 1275);
        assertFalse(shouldUnwind); // 1275/1500 = 15% drop, under 20%
    }

    // === Strategy Metrics Tests ===

    function testUpdateStrategyMetricsPeak() public {
        riskManager.updateStrategyMetrics(address(strategy), 1000);
        assertEq(riskManager.strategyPeakValue(address(strategy)), 1000);

        riskManager.updateStrategyMetrics(address(strategy), 1500);
        assertEq(riskManager.strategyPeakValue(address(strategy)), 1500);

        riskManager.updateStrategyMetrics(address(strategy), 1200);
        assertEq(riskManager.strategyPeakValue(address(strategy)), 1500); // peak doesn't decrease
    }

    function testUpdateStrategyMetricsEntry() public {
        riskManager.updateStrategyMetrics(address(strategy), 1000);
        assertEq(riskManager.strategyEntryValue(address(strategy)), 1000);
        assertGt(riskManager.strategyEntryTime(address(strategy)), 0);
    }

    // === Threshold Config Tests ===

    function testSetDrawdownThreshold() public {
        riskManager.setDrawdownThreshold(2500); // 25%
        assertEq(riskManager.drawdownThreshold(), 2500);
    }

    function testSetTimeBasedDrawdown() public {
        riskManager.setTimeBasedDrawdown(1000, 3 days);
        assertEq(riskManager.timeBasedDrawdownThreshold(), 1000);
        assertEq(riskManager.timeBasedDrawdownPeriod(), 3 days);
    }

    function testOnlyOwnerSetThresholds() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        riskManager.setDrawdownThreshold(2500);
    }

    // === First Deployment Limit Tests ===

    function testFirstDeploymentRespectsProtocolLimit() public {
        // Set protocol limit before any exposure
        exposureLimit.setProtocolLimit(address(strategy), 5000); // 50%

        // First deployment should still be checked even with 0 totalDeFiExposure
        (bool allowed, ) = riskManager.validateDeployment(address(strategy), 1000);
        // With totalDeFiExposure=0: maxAllowed = (0+1000)*5000/10000 = 500
        // protocolExposure = 0, newProtocolExposure = 1000 > 500
        assertFalse(allowed);
    }

    function testFirstDeploymentRespectsTotalLimit() public {
        exposureLimit.setTotalLimit(500);

        (bool allowed, ) = riskManager.validateDeployment(address(strategy), 1000);
        assertFalse(allowed); // 1000 > 500
    }
}
