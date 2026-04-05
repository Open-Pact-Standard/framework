// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {GovernanceTemplateFactory} from "contracts/dao-maker/GovernanceTemplateFactory.sol";
import {IGovernanceTemplateFactory} from "contracts/interfaces/IGovernanceTemplateFactory.sol";

contract GovernanceTemplateFactoryTest is Test {
    GovernanceTemplateFactory public factory;
    address public owner;

    function setUp() public {
        owner = address(this);
        factory = new GovernanceTemplateFactory();
    }

    function testDefaultTemplatesExist() public view {
        assertTrue(factory.templateExists("Conservative"));
        assertTrue(factory.templateExists("Balanced"));
        assertTrue(factory.templateExists("Flexible"));
    }

    function testGetConservativeTemplate() public view {
        IGovernanceTemplateFactory.GovernanceConfig memory config = factory.getTemplate("Conservative");
        assertEq(config.votingDelay, 7200);
        assertEq(config.votingPeriod, 50400);
        assertEq(config.proposalThreshold, 1_000_000 * 10**18);
        assertEq(config.quorumFraction, 10);
        assertEq(config.timelockDelay, 2 days);
    }

    function testGetBalancedTemplate() public view {
        IGovernanceTemplateFactory.GovernanceConfig memory config = factory.getTemplate("Balanced");
        assertEq(config.votingDelay, 3600);
        assertEq(config.votingPeriod, 36000);
        assertEq(config.quorumFraction, 4);
        assertEq(config.timelockDelay, 1 days);
    }

    function testGetFlexibleTemplate() public view {
        IGovernanceTemplateFactory.GovernanceConfig memory config = factory.getTemplate("Flexible");
        assertEq(config.votingDelay, 1800);
        assertEq(config.votingPeriod, 21600);
        assertEq(config.quorumFraction, 2);
        assertEq(config.timelockDelay, 12 hours);
    }

    function testRegisterCustomTemplate() public {
        IGovernanceTemplateFactory.GovernanceConfig memory config = IGovernanceTemplateFactory
            .GovernanceConfig({
                votingDelay: 100,
                votingPeriod: 1000,
                proposalThreshold: 0,
                quorumFraction: 5,
                timelockDelay: 1 hours
            });

        factory.registerTemplate("Custom", config);
        assertTrue(factory.templateExists("Custom"));

        IGovernanceTemplateFactory.GovernanceConfig memory retrieved = factory.getTemplate("Custom");
        assertEq(retrieved.votingDelay, 100);
        assertEq(retrieved.votingPeriod, 1000);
        assertEq(retrieved.quorumFraction, 5);
    }

    function testRevertRegisterExisting() public {
        IGovernanceTemplateFactory.GovernanceConfig memory config = IGovernanceTemplateFactory
            .GovernanceConfig({
                votingDelay: 100,
                votingPeriod: 1000,
                proposalThreshold: 0,
                quorumFraction: 5,
                timelockDelay: 1 hours
            });

        vm.expectRevert(
            abi.encodeWithSelector(
                GovernanceTemplateFactory.TemplateAlreadyExists.selector,
                "Conservative"
            )
        );
        factory.registerTemplate("Conservative", config);
    }

    function testRevertGetNonExistent() public {
        vm.expectRevert(
            abi.encodeWithSelector(GovernanceTemplateFactory.TemplateNotFound.selector, "NonExistent")
        );
        factory.getTemplate("NonExistent");
    }

    function testRemoveTemplate() public {
        factory.removeTemplate("Flexible");
        assertFalse(factory.templateExists("Flexible"));
    }

    function testRemoveTemplateCleansUpNamesArray() public {
        uint256 countBefore = factory.getTemplateNames().length;
        factory.removeTemplate("Flexible");
        uint256 countAfter = factory.getTemplateNames().length;
        assertEq(countAfter, countBefore - 1);

        // Verify "Flexible" is not in the names array
        string[] memory names = factory.getTemplateNames();
        for (uint256 i = 0; i < names.length; i++) {
            assertTrue(keccak256(bytes(names[i])) != keccak256(bytes("Flexible")));
        }
    }

    function testRemoveTemplateThenRegisterAgain() public {
        factory.removeTemplate("Flexible");

        // Should be able to register "Flexible" again since it was fully removed
        IGovernanceTemplateFactory.GovernanceConfig memory config = IGovernanceTemplateFactory
            .GovernanceConfig({
                votingDelay: 900,
                votingPeriod: 10800,
                proposalThreshold: 5_000 * 10**18,
                quorumFraction: 3,
                timelockDelay: 6 hours
            });

        factory.registerTemplate("Flexible", config);
        assertTrue(factory.templateExists("Flexible"));

        IGovernanceTemplateFactory.GovernanceConfig memory retrieved = factory.getTemplate("Flexible");
        assertEq(retrieved.votingDelay, 900);
    }

    function testRevertRemoveNonExistent() public {
        vm.expectRevert(
            abi.encodeWithSelector(GovernanceTemplateFactory.TemplateNotFound.selector, "NonExistent")
        );
        factory.removeTemplate("NonExistent");
    }

    function testRevertInvalidVotingPeriod() public {
        IGovernanceTemplateFactory.GovernanceConfig memory config = IGovernanceTemplateFactory
            .GovernanceConfig({
                votingDelay: 100,
                votingPeriod: 0,
                proposalThreshold: 0,
                quorumFraction: 5,
                timelockDelay: 1 hours
            });

        vm.expectRevert(GovernanceTemplateFactory.InvalidConfig.selector);
        factory.registerTemplate("Bad", config);
    }

    function testRevertInvalidQuorum() public {
        IGovernanceTemplateFactory.GovernanceConfig memory config = IGovernanceTemplateFactory
            .GovernanceConfig({
                votingDelay: 100,
                votingPeriod: 1000,
                proposalThreshold: 0,
                quorumFraction: 0,
                timelockDelay: 1 hours
            });

        vm.expectRevert(GovernanceTemplateFactory.InvalidConfig.selector);
        factory.registerTemplate("Bad", config);
    }

    function testOnlyOwnerCanRegister() public {
        address nonOwner = makeAddr("nonOwner");
        IGovernanceTemplateFactory.GovernanceConfig memory config = IGovernanceTemplateFactory
            .GovernanceConfig({
                votingDelay: 100,
                votingPeriod: 1000,
                proposalThreshold: 0,
                quorumFraction: 5,
                timelockDelay: 1 hours
            });

        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        factory.registerTemplate("Bad", config);
    }
}
