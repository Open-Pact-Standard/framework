// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {DAOGovernor} from "contracts/governance/DAOGovernor.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";
import "test/mocks/MockDAOToken.sol";

contract DAOGovernorTest is Test {
    DAOGovernor public governor;
    TimelockController public timelock;
    MockDAOToken public token;

    address public owner;
    address public proposer;

    function setUp() public {
        owner = address(this);
        proposer = makeAddr("proposer");

        // Deploy token
        token = new MockDAOToken(owner);

        // Deploy timelock with owner as admin
        address[] memory proposers = new address[](1);
        proposers[0] = owner;
        address[] memory executors = new address[](1);
        executors[0] = owner;
        timelock = new TimelockController(1, proposers, executors, owner);

        // Deploy governor
        governor = new DAOGovernor(
            IVotes(address(token)),
            timelock,
            "TestGovernor",
            1, // votingDelay
            100, // votingPeriod
            0, // proposalThreshold
            4 // quorumFraction (4%)
        );

        // Grant governor proposer role on timelock
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
    }

    // ============ Deployment Tests ============

    function testDeployment() public {
        assertEq(governor.votingDelay(), 1);
        assertEq(governor.votingPeriod(), 100);
        assertEq(governor.proposalThreshold(), 0);
        assertEq(governor.name(), "TestGovernor");
    }

    // ============ Setter Tests ============

    function testSetVotingDelay() public {
        // Only timelock can call
        vm.prank(address(timelock));
        governor.setVotingDelay(10);
        assertEq(governor.votingDelay(), 10);
    }

    function testSetVotingDelayEmitsEvent() public {
        vm.prank(address(timelock));
        vm.expectEmit(true, true, false, false);
        emit DAOGovernor.VotingDelayUpdated(1, 10);
        governor.setVotingDelay(10);
    }

    function testSetVotingPeriod() public {
        vm.prank(address(timelock));
        governor.setVotingPeriod(200);
        assertEq(governor.votingPeriod(), 200);
    }

    function testSetVotingPeriodEmitsEvent() public {
        vm.prank(address(timelock));
        vm.expectEmit(true, true, false, false);
        emit DAOGovernor.VotingPeriodUpdated(100, 200);
        governor.setVotingPeriod(200);
    }

    function testSetProposalThreshold() public {
        vm.prank(address(timelock));
        governor.setProposalThreshold(1000);
        assertEq(governor.proposalThreshold(), 1000);
    }

    function testSetProposalThresholdEmitsEvent() public {
        vm.prank(address(timelock));
        vm.expectEmit(true, true, false, false);
        emit DAOGovernor.ProposalThresholdUpdated(0, 1000);
        governor.setProposalThreshold(1000);
    }

    function testOnlyTimelockCanSetVotingDelay() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(DAOGovernor.OnlyTimelock.selector, owner));
        governor.setVotingDelay(10);
    }

    function testOnlyTimelockCanSetVotingPeriod() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(DAOGovernor.OnlyTimelock.selector, owner));
        governor.setVotingPeriod(200);
    }

    function testOnlyTimelockCanSetProposalThreshold() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(DAOGovernor.OnlyTimelock.selector, owner));
        governor.setProposalThreshold(1000);
    }
}
