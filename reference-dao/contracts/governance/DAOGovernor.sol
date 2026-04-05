// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title DAOGovernor
 * @dev OpenZeppelin Governor implementation for DAO governance.
 * Supports token-based voting with configurable parameters and timelock execution.
 *
 * Template presets (assuming ~12 second block time on Flare):
 * - Conservative: 7 day voting period (50400 blocks), 2 day threshold
 * - Balanced: 5 day voting period (36000 blocks), 1 day threshold
 * - Flexible: 3 day voting period (21600 blocks), 12 hour threshold
 */
contract DAOGovernor is
    Governor,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl
{
    /// @notice Voting delay in blocks (1 block ≈ 12 seconds on Flare)
    uint256 private _votingDelay;

    /// @notice Voting period in blocks
    uint256 private _votingPeriod;

    /// @notice Proposal threshold in votes
    uint256 private _proposalThreshold;

    /// @notice Emitted when voting delay is updated via governance
    event VotingDelayUpdated(uint256 oldDelay, uint256 newDelay);

    /// @notice Emitted when voting period is updated via governance
    event VotingPeriodUpdated(uint256 oldPeriod, uint256 newPeriod);

    /// @notice Emitted when proposal threshold is updated via governance
    event ProposalThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);

    /// @notice Emitted when caller is not the timelock
    error OnlyTimelock(address caller);

    /**
     * @dev Initialize the governor with governance token and timelock.
     * @param token_ ERC20Votes token for voting
     * @param timelock_ Timelock controller for execution
     * @param name_ Governor name
     * @param votingDelay_ Delay from proposal creation to voting start
     * @param votingPeriod_ Duration of voting
     * @param proposalThreshold_ Vote threshold to create proposals
     * @param quorumFraction_ Quorum percentage (e.g., 4 = 4%)
     */
    constructor(
        IVotes token_,
        TimelockController timelock_,
        string memory name_,
        uint256 votingDelay_,
        uint256 votingPeriod_,
        uint256 proposalThreshold_,
        uint8 quorumFraction_
    )
        Governor(name_)
        GovernorVotes(token_)
        GovernorVotesQuorumFraction(quorumFraction_)
        GovernorTimelockControl(timelock_)
    {
        _votingDelay = votingDelay_;
        _votingPeriod = votingPeriod_;
        _proposalThreshold = proposalThreshold_;
    }

    /// @notice Returns the delay between proposal creation and voting start
    function votingDelay() public view override returns (uint256) {
        return _votingDelay;
    }

    /// @notice Returns the duration of the voting period
    function votingPeriod() public view override returns (uint256) {
        return _votingPeriod;
    }

    /// @notice Returns the vote threshold required to propose
    function proposalThreshold() public view override returns (uint256) {
        return _proposalThreshold;
    }

    /// @notice Returns the state of a proposal
    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    /// @notice Required override for timelock interface
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    /// @notice Update voting delay (governance action)
    function setVotingDelay(uint256 newVotingDelay) external {
        if (msg.sender != timelock()) {
            revert OnlyTimelock(msg.sender);
        }
        uint256 oldDelay = _votingDelay;
        _votingDelay = newVotingDelay;
        emit VotingDelayUpdated(oldDelay, newVotingDelay);
    }

    /// @notice Update voting period (governance action)
    function setVotingPeriod(uint256 newVotingPeriod) external {
        if (msg.sender != timelock()) {
            revert OnlyTimelock(msg.sender);
        }
        uint256 oldPeriod = _votingPeriod;
        _votingPeriod = newVotingPeriod;
        emit VotingPeriodUpdated(oldPeriod, newVotingPeriod);
    }

    /// @notice Update proposal threshold (governance action)
    function setProposalThreshold(uint256 newThreshold) external {
        if (msg.sender != timelock()) {
            revert OnlyTimelock(msg.sender);
        }
        uint256 oldThreshold = _proposalThreshold;
        _proposalThreshold = newThreshold;
        emit ProposalThresholdUpdated(oldThreshold, newThreshold);
    }

    // The following functions are overrides required by Solidity.

    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._execute(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}
