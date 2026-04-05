// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

/**
 * @title IDAOGovernor
 * @dev Interface for DAO Governor contract.
 */
interface IDAOGovernor {
    /**
     * @dev Create a new proposal.
     * @param targets Array of target addresses to call
     * @param values Array of ETH values to send
     * @param calldatas Array of call data to execute
     * @param description Proposal description
     * @return Proposal ID
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) external returns (uint256);

    /**
     * @dev Cast a vote on a proposal.
     * @param proposalId Proposal ID
     * @param support Vote support: 0=Against, 1=For, 2=Abstain
     * @return Weight of the vote
     */
    function castVote(uint256 proposalId, uint8 support) external returns (uint256);

    /**
     * @dev Cast a vote with reason.
     * @param proposalId Proposal ID
     * @param support Vote support
     * @param reason Reason for vote
     * @return Weight of the vote
     */
    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) external returns (uint256);

    /**
     * @dev Execute a successful proposal.
     * @param targets Array of target addresses
     * @param values Array of ETH values
     * @param calldatas Array of call data
     * @param descriptionHash Hash of description
     * @return Proposal ID
     */
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) external payable returns (uint256);

    /**
     * @dev Get the voting delay in blocks.
     * @return Voting delay
     */
    function votingDelay() external view returns (uint256);

    /**
     * @dev Get the voting period in blocks.
     * @return Voting period
     */
    function votingPeriod() external view returns (uint256);

    /**
     * @dev Get the proposal threshold.
     * @return Threshold in tokens
     */
    function proposalThreshold() external view returns (uint256);

    /**
     * @dev Get the quorum required for a proposal to pass.
     * @param proposalId Proposal ID
     * @param blockNumber Block number to check quorum at
     * @return Required quorum votes
     */
    function quorum(uint256 proposalId, uint256 blockNumber) external view returns (uint256);

    /**
     * @dev Get the current state of a proposal.
     * @param proposalId Proposal ID
     * @return Proposal state
     */
    function state(uint256 proposalId) external view returns (uint8);

    /**
     * @dev Get the number of votes for an account at a specific block.
     * @param account Account to query
     * @param blockNumber Block number
     * @return Vote count
     */
    function getVotes(address account, uint256 blockNumber) external view returns (uint256);

    /**
     * @dev Get the token used for governance.
     * @return Token address
     */
    function token() external view returns (address);

    /**
     * @dev Update voting delay (only timelock can call).
     * @param newVotingDelay New voting delay
     */
    function setVotingDelay(uint256 newVotingDelay) external;

    /**
     * @dev Update voting period (only timelock can call).
     * @param newVotingPeriod New voting period
     */
    function setVotingPeriod(uint256 newVotingPeriod) external;

    /**
     * @dev Update proposal threshold (only timelock can call).
     * @param newThreshold New threshold
     */
    function setProposalThreshold(uint256 newThreshold) external;
}
