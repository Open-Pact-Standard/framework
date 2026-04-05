// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {DeFiTreasuryExtension} from "contracts/treasury/DeFiTreasuryExtension.sol";
import {IDeFiTreasuryExtension} from "contracts/interfaces/IDeFiTreasuryExtension.sol";
import {IDeFiStrategy} from "contracts/interfaces/IDeFiStrategy.sol";
import {DeFiStrategy} from "contracts/defi/DeFiStrategy.sol";
import {StrategyRegistry} from "contracts/defi/StrategyRegistry.sol";
import {ExposureLimit} from "contracts/defi/risk/ExposureLimit.sol";
import {RiskManager} from "contracts/defi/risk/RiskManager.sol";
import {Treasury} from "contracts/treasury/Treasury.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    function mint(address to, uint256 amount) external { _mint(to, amount); }
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

contract DeFiTreasuryExtensionTest is Test {
    DeFiTreasuryExtension public extension;
    Treasury public treasury;
    StrategyRegistry public registry;
    ExposureLimit public exposureLimit;
    RiskManager public riskManager;
    MockStrategy public strategy;
    MockERC20 public token;

    address public signer1;
    address public signer2;
    address public nonSigner;

    function setUp() public {
        signer1 = makeAddr("signer1");
        signer2 = makeAddr("signer2");
        nonSigner = makeAddr("nonSigner");

        // Deploy treasury with 2 signers, threshold 2
        address[] memory signers = new address[](2);
        signers[0] = signer1;
        signers[1] = signer2;
        treasury = new Treasury(signers, 2);

        token = new MockERC20("Test", "TST");
        registry = new StrategyRegistry();
        exposureLimit = new ExposureLimit();
        riskManager = new RiskManager(address(treasury), exposureLimit);

        // Deploy strategy — treasury is the authorized caller
        strategy = new MockStrategy(address(treasury), address(token));

        // Deploy extension — note: signer checks go through treasury.isSigner()
        extension = new DeFiTreasuryExtension(treasury, registry, riskManager);

        // Fund treasury with tokens
        token.mint(address(treasury), 1_000_000 * 10**18);

        // Register strategy
        registry.registerStrategy(address(strategy), "MockLend", "Mock lending", 3);
    }

    function testDeployment() public view {
        assertEq(address(extension.treasury()), address(treasury));
        assertEq(address(extension.strategyRegistry()), address(registry));
        assertEq(address(extension.riskManager()), address(riskManager));
    }

    function testRevertZeroAddressRiskManager() public {
        vm.expectRevert();
        new DeFiTreasuryExtension(treasury, registry, RiskManager(address(0)));
    }

    function testRevertNonSignerDeploy() public {
        vm.prank(nonSigner);
        vm.expectRevert(
            abi.encodeWithSelector(DeFiTreasuryExtension.NotTreasurySigner.selector, nonSigner)
        );
        extension.deployToStrategy(address(strategy), 1000);
    }

    function testRevertInactiveStrategy() public {
        registry.deactivateStrategy(address(strategy));
        vm.prank(signer1);
        vm.expectRevert(
            abi.encodeWithSelector(DeFiTreasuryExtension.StrategyNotActive.selector, address(strategy))
        );
        extension.deployToStrategy(address(strategy), 1000);
    }

    function testRevertWithdrawExceedsBalance() public {
        vm.prank(signer1);
        vm.expectRevert(
            abi.encodeWithSelector(
                DeFiTreasuryExtension.WithdrawalExceedsBalance.selector,
                uint256(5000),
                uint256(0)
            )
        );
        extension.withdrawFromStrategy(address(strategy), 5000);
    }

    function testGetStrategyBalance() public view {
        assertEq(extension.getStrategyBalance(address(strategy)), 0);
    }

    function testGetStrategyAPY() public view {
        assertEq(extension.getStrategyAPY(address(strategy)), 500);
    }

    function testGetTotalDeFiExposure() public view {
        assertEq(extension.getTotalDeFiExposure(), 0);
    }

    function testGetRegisteredStrategies() public {
        address[] memory strategies = extension.getRegisteredStrategies();
        assertEq(strategies.length, 1);
        assertEq(strategies[0], address(strategy));
    }

    function testIsStrategyActive() public view {
        assertTrue(extension.isStrategyActive(address(strategy)));
    }

    function testRevertDeployBlockedByRisk() public {
        // Set a very low total exposure limit
        exposureLimit.setTotalLimit(100);

        vm.prank(signer1);
        vm.expectRevert();
        extension.deployToStrategy(address(strategy), 1000);
    }

    function testOnlyOwnerCanSet() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        exposureLimit.setTotalLimit(5000);
    }
}
