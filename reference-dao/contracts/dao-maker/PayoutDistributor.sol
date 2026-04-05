// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IPayoutDistributor.sol";
import "../interfaces/IDAOToken.sol";
import "../interfaces/IReputationRegistry.sol";
import "../interfaces/IAgentRegistry.sol";

/**
 * @title PayoutDistributor
 * @dev Hybrid 70% stake-snapshot + 30% reputation-weighted payouts, epoch-based.
 *      Uses DAOToken.getPastVotes() for stake snapshots and ReputationRegistry
 *      scores normalized to 0-100 for contribution weighting.
 */
contract PayoutDistributor is IPayoutDistributor, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant TOTAL_RATIO = 10_000;
    uint256 public constant EPOCH_DURATION = 7 days;

    IDAOToken public immutable daoToken;
    IReputationRegistry public immutable reputationRegistry;
    IAgentRegistry public immutable agentRegistry;
    address[] public participants;
    mapping(address => bool) public isParticipant;

    uint256 private _stakeRatio;
    uint256 private _reputationRatio;
    uint256 private _epochStart;

    struct EpochData {
        mapping(address => uint256) weights;
        mapping(address => mapping(address => uint256)) claimed;
        mapping(address => uint256) totalDeposited;
        uint256 totalWeight;
        bool initialized;
    }

    mapping(uint256 => EpochData) private _epochs;

    error ZeroAddress();
    error InvalidRatio(uint256 stake, uint256 reputation);
    error NoFunds();
    error AlreadyClaimed();
    error InvalidEpoch();
    error NotInitialized();

    /**
     * @dev Deploy the payout distributor.
     * @param daoToken_ The governance token for stake snapshots
     * @param reputationRegistry_ The reputation registry for contribution weighting
     * @param agentRegistry_ The agent registry for address-to-agentId resolution
     * @param participants_ Addresses eligible for payouts
     */
    constructor(
        IDAOToken daoToken_,
        IReputationRegistry reputationRegistry_,
        IAgentRegistry agentRegistry_,
        address[] memory participants_
    ) Ownable() {
        if (address(daoToken_) == address(0) || address(reputationRegistry_) == address(0) || address(agentRegistry_) == address(0)) {
            revert ZeroAddress();
        }
        daoToken = daoToken_;
        reputationRegistry = reputationRegistry_;
        agentRegistry = agentRegistry_;
        participants = participants_;
        for (uint256 i = 0; i < participants_.length; i++) {
            isParticipant[participants_[i]] = true;
        }
        _stakeRatio = 7000;
        _reputationRatio = 3000;
        _epochStart = block.timestamp;
    }

    receive() external payable {
        if (msg.value > 0) {
            uint256 epoch = currentEpoch();
            _epochs[epoch].totalDeposited[address(0)] += msg.value;
            emit EpochFunded(epoch, address(0), msg.value);
        }
    }

    /**
     * @inheritdoc IPayoutDistributor
     */
    function fundEpoch(address token, uint256 amount) external override onlyOwner nonReentrant whenNotPaused {
        if (token == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert NoFunds();
        }
        uint256 epoch = currentEpoch();
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _epochs[epoch].totalDeposited[token] += amount;
        emit EpochFunded(epoch, token, amount);
    }

    /**
     * @inheritdoc IPayoutDistributor
     */
    function fundEpochNative() external payable override onlyOwner nonReentrant whenNotPaused {
        if (msg.value == 0) {
            revert NoFunds();
        }
        uint256 epoch = currentEpoch();
        _epochs[epoch].totalDeposited[address(0)] += msg.value;
        emit EpochFunded(epoch, address(0), msg.value);
    }

    /**
     * @inheritdoc IPayoutDistributor
     */
    function initializeEpoch(uint256 epoch) external override onlyOwner whenNotPaused {
        _initializeEpoch(epoch);
        emit EpochInitialized(epoch, _epochs[epoch].totalWeight);
    }

    /**
     * @inheritdoc IPayoutDistributor
     */
    function addParticipant(address participant) external override onlyOwner {
        if (participant == address(0)) {
            revert ZeroAddress();
        }
        if (isParticipant[participant]) {
            return;
        }
        isParticipant[participant] = true;
        participants.push(participant);
        emit ParticipantAdded(participant);
    }

    /**
     * @inheritdoc IPayoutDistributor
     */
    function removeParticipant(address participant) external override onlyOwner {
        if (!isParticipant[participant]) {
            return;
        }
        isParticipant[participant] = false;

        // Find and remove by swapping with last element
        for (uint256 i = 0; i < participants.length; i++) {
            if (participants[i] == participant) {
                participants[i] = participants[participants.length - 1];
                participants.pop();
                break;
            }
        }
        emit ParticipantRemoved(participant);
    }

    /**
     * @inheritdoc IPayoutDistributor
     */
    function claim(uint256 epoch, address token) external override nonReentrant whenNotPaused {
        if (epoch >= currentEpoch()) {
            revert InvalidEpoch();
        }
        EpochData storage epochData = _epochs[epoch];
        if (!epochData.initialized) {
            revert NotInitialized();
        }
        if (epochData.claimed[token][msg.sender] > 0) {
            revert AlreadyClaimed();
        }
        uint256 amount = _calculateClaim(msg.sender, epoch, token);
        if (amount == 0) {
            revert NoFunds();
        }
        epochData.claimed[token][msg.sender] = amount;

        if (token == address(0)) {
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            if (!success) {
                revert NoFunds();
            }
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit Claimed(msg.sender, epoch, token, amount);
    }

    /**
     * @inheritdoc IPayoutDistributor
     */
    function setEpochConfig(
        uint256 stakeRatio,
        uint256 reputationRatio
    ) external override onlyOwner {
        if (stakeRatio + reputationRatio != TOTAL_RATIO) {
            revert InvalidRatio(stakeRatio, reputationRatio);
        }
        _stakeRatio = stakeRatio;
        _reputationRatio = reputationRatio;
        emit EpochConfigUpdated(stakeRatio, reputationRatio);
    }

    /**
     * @inheritdoc IPayoutDistributor
     */
    function getClaimableAmount(
        address account,
        uint256 epoch,
        address token
    ) external view override returns (uint256) {
        EpochData storage epochData = _epochs[epoch];
        if (epochData.claimed[token][account] > 0) {
            return 0;
        }
        return _calculateClaim(account, epoch, token);
    }

    /**
     * @inheritdoc IPayoutDistributor
     */
    function currentEpoch() public view override returns (uint256) {
        return (block.timestamp - _epochStart) / EPOCH_DURATION;
    }

    /**
     * @dev Get participant list.
     * @return Array of participant addresses
     */
    function getParticipants() external view returns (address[] memory) {
        return participants;
    }

    /**
     * @dev Get the epoch start timestamp.
     * @return The epoch start time
     */
    function getEpochStart() external view returns (uint256) {
        return _epochStart;
    }

    /**
     * @dev Initialize epoch weights for all participants.
     *      Snapshots stake at epoch boundary block and reads reputation scores.
     */
    function _initializeEpoch(uint256 epoch) internal {
        EpochData storage epochData = _epochs[epoch];
        if (epochData.initialized) {
            return;
        }
        epochData.initialized = true;

        uint256 epochBlock = _epochStart + epoch * EPOCH_DURATION;
        uint256 blockNum = _getBlockAtTimestamp(epochBlock);

        uint256 totalWeight;
        uint256 len = participants.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 weight = _calculateWeight(participants[i], blockNum);
            epochData.weights[participants[i]] = weight;
            totalWeight += weight;
        }
        epochData.totalWeight = totalWeight;
    }

    /**
     * @dev Calculate the weight for a participant (stake + reputation hybrid).
     * @param account The participant
     * @param blockNum Block number for stake snapshot
     * @return The combined weight
     */
    function _calculateWeight(address account, uint256 blockNum) internal view returns (uint256) {
        uint256 stake = daoToken.getPastVotes(account, blockNum);
        uint256 maxSupply = daoToken.MAX_SUPPLY();
        uint256 stakeWeight = (stake * _stakeRatio) / maxSupply;

        int256 reputation = reputationRegistry.getReputation(agentRegistry.getAgentId(account));
        uint256 normalizedRep = _normalizeReputation(reputation);
        uint256 reputationWeight = (normalizedRep * _reputationRatio) / 100;

        return stakeWeight + reputationWeight;
    }

    /**
     * @dev Normalize reputation from [-10, +10] to [0, 100].
     *      Formula: (score + 10) * 5
     * @param score Raw reputation score
     * @return Normalized score (0-100)
     */
    function _normalizeReputation(int256 score) internal pure returns (uint256) {
        if (score <= -10) {
            return 0;
        }
        if (score >= 10) {
            return 100;
        }
        return uint256(score + 10) * 5;
    }

    /**
     * @dev Calculate claimable amount for a participant.
     * @param account The participant
     * @param epoch The epoch
     * @param token The token
     * @return The claimable amount
     */
    function _calculateClaim(
        address account,
        uint256 epoch,
        address token
    ) internal view returns (uint256) {
        EpochData storage epochData = _epochs[epoch];
        if (epochData.totalWeight == 0) {
            return 0;
        }
        uint256 weight = epochData.weights[account];
        if (weight == 0) {
            return 0;
        }
        uint256 totalDeposited = epochData.totalDeposited[token];
        return (totalDeposited * weight) / epochData.totalWeight;
    }

    /**
     * @dev Approximate block number at a timestamp.
     *      Flare has ~12 second blocks.
     * @param timestamp Target timestamp
     * @return Approximate block number (guaranteed in the past)
     */
    function _getBlockAtTimestamp(uint256 timestamp) internal view returns (uint256) {
        if (timestamp >= block.timestamp) {
            return block.number > 0 ? block.number - 1 : 0;
        }
        uint256 elapsed = block.timestamp - timestamp;
        uint256 blocksAgo = elapsed / 12;
        if (blocksAgo >= block.number) {
            return 0;
        }
        // Return block.number - blocksAgo - 1 to ensure it's strictly in the past
        return block.number - blocksAgo - 1;
    }

    /**
     * @dev Pause the contract (owner only)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract (owner only)
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
