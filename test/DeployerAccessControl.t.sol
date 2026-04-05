// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {TokenDeployer} from "contracts/dao-maker/TokenDeployer.sol";
import {TimelockDeployer} from "contracts/dao-maker/TimelockDeployer.sol";
import {GovernorDeployer} from "contracts/dao-maker/GovernorDeployer.sol";

contract DeployerAccessControlTest is Test {
    TokenDeployer public tokenDeployer;
    TimelockDeployer public timelockDeployer;
    GovernorDeployer public governorDeployer;

    address public owner;
    address public factory;
    address public attacker;

    function setUp() public {
        owner = address(this);
        factory = makeAddr("factory");
        attacker = makeAddr("attacker");

        tokenDeployer = new TokenDeployer();
        timelockDeployer = new TimelockDeployer();
        governorDeployer = new GovernorDeployer();
    }

    // ============ TokenDeployer Tests ============

    function testTokenDeployerOpenAccessByDefault() public {
        // Factory is address(0) by default, so anyone can deploy
        assertEq(tokenDeployer.factory(), address(0));

        vm.prank(attacker);
        address token = tokenDeployer.deploy("Test", "TST", attacker, 1000);
        assertTrue(token != address(0));
    }

    function testTokenDeployerSetFactory() public {
        tokenDeployer.setFactory(factory);
        assertEq(tokenDeployer.factory(), factory);
    }

    function testTokenDeployerOnlyOwnerCanSetFactory() public {
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(TokenDeployer.NotOwner.selector, attacker));
        tokenDeployer.setFactory(factory);
    }

    function testTokenDeployerCannotSetFactoryTwice() public {
        tokenDeployer.setFactory(factory);

        vm.expectRevert(TokenDeployer.FactoryAlreadySet.selector);
        tokenDeployer.setFactory(makeAddr("other"));
    }

    function testTokenDeployerOnlyFactoryAfterSet() public {
        tokenDeployer.setFactory(factory);

        // Attacker can no longer deploy
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(TokenDeployer.NotFactory.selector, attacker));
        tokenDeployer.deploy("Test", "TST", attacker, 1000);

        // Factory can deploy
        vm.prank(factory);
        address token = tokenDeployer.deploy("Test", "TST", factory, 1000);
        assertTrue(token != address(0));
    }

    function testTokenDeployerCannotSetZeroFactory() public {
        vm.expectRevert(TokenDeployer.ZeroAddress.selector);
        tokenDeployer.setFactory(address(0));
    }

    // ============ TimelockDeployer Tests ============

    function testTimelockDeployerOpenAccessByDefault() public {
        assertEq(timelockDeployer.factory(), address(0));

        vm.prank(attacker);
        address timelock = timelockDeployer.deploy(0, attacker);
        assertTrue(timelock != address(0));
    }

    function testTimelockDeployerSetFactory() public {
        timelockDeployer.setFactory(factory);
        assertEq(timelockDeployer.factory(), factory);
    }

    function testTimelockDeployerOnlyFactoryAfterSet() public {
        timelockDeployer.setFactory(factory);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(TimelockDeployer.NotFactory.selector, attacker));
        timelockDeployer.deploy(0, attacker);

        vm.prank(factory);
        address timelock = timelockDeployer.deploy(0, factory);
        assertTrue(timelock != address(0));
    }

    // ============ GovernorDeployer Tests ============

    function testGovernorDeployerOpenAccessByDefault() public {
        assertEq(governorDeployer.factory(), address(0));
    }

    function testGovernorDeployerSetFactory() public {
        governorDeployer.setFactory(factory);
        assertEq(governorDeployer.factory(), factory);
    }

    function testGovernorDeployerOnlyFactoryAfterSet() public {
        governorDeployer.setFactory(factory);

        // Attacker cannot deploy
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(GovernorDeployer.NotFactory.selector, attacker));
        governorDeployer.deploy(attacker, attacker, "Test", 1, 100, 0, 4);
    }
}
