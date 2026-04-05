// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

/**
 * @title IPayoutDistributor
 * @dev Interface for hybrid stake + reputation-weighted epoch payouts.
 */
interface IPayoutDistributor {
    event EpochFunded(uint256 indexed epoch, address indexed token, uint256 amount);
    event Claimed(address indexed account, uint256 indexed epoch, address indexed token, uint256 amount);
    event EpochConfigUpdated(uint256 stakeRatio, uint256 reputationRatio);
    event EpochInitialized(uint256 indexed epoch, uint256 totalWeight);
    event ParticipantAdded(address indexed participant);
    event ParticipantRemoved(address indexed participant);

    /**
     * @dev Fund an epoch with ERC-20 tokens.
     * @param token The token to fund with
     * @param amount The amount to deposit
     */
    function fundEpoch(address token, uint256 amount) external;

    /**
     * @dev Fund an epoch with native tokens.
     */
    function fundEpochNative() external payable;

    /**
     * @dev Initialize epoch weights for all participants.
     *      Must be called after fundEpoch and before claim.
     * @param epoch The epoch to initialize
     */
    function initializeEpoch(uint256 epoch) external;

    /**
     * @dev Claim payout for a specific epoch and token.
     * @param epoch The epoch number
     * @param token The token to claim
     */
    function claim(uint256 epoch, address token) external;

    /**
     * @dev Set the stake/reputation ratio for weighting (basis points).
     * @param stakeRatio Weight for stake (e.g. 7000 = 70%)
     * @param reputationRatio Weight for reputation (e.g. 3000 = 30%)
     */
    function setEpochConfig(uint256 stakeRatio, uint256 reputationRatio) external;

    /**
     * @dev Add a participant eligible for payouts.
     * @param participant Address to add
     */
    function addParticipant(address participant) external;

    /**
     * @dev Remove a participant from payout eligibility.
     * @param participant Address to remove
     */
    function removeParticipant(address participant) external;

    /**
     * @dev Get the claimable amount for a user at an epoch for a token.
     * @param account The user address
     * @param epoch The epoch number
     * @param token The token address
     * @return The claimable amount
     */
    function getClaimableAmount(
        address account,
        uint256 epoch,
        address token
    ) external view returns (uint256);

    /**
     * @dev Get the current epoch number.
     * @return The current epoch
     */
    function currentEpoch() external view returns (uint256);
}
