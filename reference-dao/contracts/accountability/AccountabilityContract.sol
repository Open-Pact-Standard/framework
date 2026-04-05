// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import { IAccountabilityContract } from "./interfaces/IAccountabilityContract.sol";
import { IProfileRegistry } from "../profiles/interfaces/IProfileRegistry.sol";

/**
 * @title AccountabilityContract
 * @dev Handle disputes, performance tracking, and penalties
 *
 *      Features:
 *      - File and resolve disputes
 *      - Stake-weighted voting on disputes
 *      - Performance statistics tracking
 *      - Penalty system for bad actors
 *      - Integration with reputation system
 */
contract AccountabilityContract is IAccountabilityContract, Ownable, AccessControl {
    /// @notice Profile registry for reputation updates
    IProfileRegistry public immutable profileRegistry;

    /// @notice Dispute ID counter
    uint256 private _disputeIdCounter;

    /// @notice Vote ID counter
    uint256 private _voteIdCounter;

    /// @notice Penalty ID counter
    uint256 private _penaltyIdCounter;

    /// @notice Dispute ID => Dispute data
    mapping(uint256 => Dispute) private _disputes;

    /// @notice Dispute ID => Voter => Vote
    mapping(uint256 => mapping(address => Vote)) private _votes;

    /// @notice Voter => Voted dispute IDs
    mapping(address => uint256[]) private _voterDisputes;

    /// @notice User => PerformanceRecord
    mapping(address => PerformanceRecord) private _performance;

    /// @notice User => Penalty IDs
    mapping(address => uint256[]) private _userPenalties;

    /// @notice Penalty ID => Penalty
    mapping(uint256 => Penalty) private _penalties;

    /// @notice Active dispute IDs
    uint256[] private _activeDisputes;

    /// @notice Dispute ID => Index in _activeDisputes
    mapping(uint256 => uint256) private _activeDisputeIndex;

    /// @notice Minimum stake to file a dispute
    uint256 public constant MIN_DISPUTE_STAKE = 0.05 ether;

    /// @notice Minimum stake to vote
    uint256 public constant MIN_VOTE_STAKE = 0.01 ether;

    /// @notice Voting period (3 days)
    uint256 public constant VOTING_PERIOD = 3 days;

    /// @notice Resolver role (can resolve disputes)
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");

    /// @notice Maximum severity for penalties
    uint256 public constant MAX_SEVERITY = 10;

    // ============ Custom Errors ============

    error InvalidBounty();
    error InvalidRespondent();
    error DisputeNotFound();
    error DisputeNotActive();
    error DisputeNotVoting();
    error DisputeAlreadyResolved();
    error AlreadyVoted();
    error InsufficientStake();
    error NotAuthorized();
    error InvalidSeverity();
    error PenaltyNotFound();
    error PenaltyNotActive();

    // ============ Constructor ============

    constructor(address profileRegistry_) Ownable() {
        if (profileRegistry_ == address(0)) revert("Zero address");
        profileRegistry = IProfileRegistry(profileRegistry_);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(RESOLVER_ROLE, msg.sender);
    }

    // ============ Dispute Management ============

    /**
     * @notice File a dispute
     */
    function fileDispute(
        uint256 bountyId,
        address respondent,
        DisputeType disputeType,
        string calldata description
    ) external payable returns (uint256 disputeId) {
        if (msg.value < MIN_DISPUTE_STAKE) revert InsufficientStake();
        if (respondent == msg.sender) revert InvalidRespondent();

        _disputeIdCounter++;
        disputeId = _disputeIdCounter;

        uint256 votingDeadline = block.timestamp + VOTING_PERIOD;

        _disputes[disputeId] = Dispute({
            id: disputeId,
            bountyId: bountyId,
            filer: msg.sender,
            respondent: respondent,
            disputeType: disputeType,
            description: description,
            filerStake: msg.value,
            respondentStake: 0,
            timestamp: block.timestamp,
            votingDeadline: votingDeadline,
            status: DisputeStatus.Filed,
            forVotes: 0,
            againstVotes: 0,
            winner: address(0),
            resolutionReason: ""
        });

        _activeDisputes.push(disputeId);
        _activeDisputeIndex[disputeId] = _activeDisputes.length - 1;

        emit DisputeFiled(disputeId, bountyId, msg.sender, respondent);
        return disputeId;
    }

    /**
     * @notice Respond to a dispute
     */
    function respondToDispute(uint256 disputeId, string calldata response) external payable {
        Dispute storage dispute = _disputes[disputeId];

        if (dispute.id != disputeId) revert DisputeNotFound();
        if (dispute.respondent != msg.sender) revert NotAuthorized();
        if (dispute.status != DisputeStatus.Filed) revert DisputeNotActive();
        if (msg.value < MIN_DISPUTE_STAKE) revert InsufficientStake();

        dispute.respondentStake = msg.value;
        dispute.status = DisputeStatus.Voting;

        emit DisputeResponded(disputeId, msg.sender);
    }

    /**
     * @notice Vote on a dispute
     */
    function voteOnDispute(uint256 disputeId, bool forFiler) external payable {
        Dispute storage dispute = _disputes[disputeId];

        if (dispute.id != disputeId) revert DisputeNotFound();
        if (dispute.status != DisputeStatus.Voting) revert DisputeNotVoting();
        if (block.timestamp >= dispute.votingDeadline) revert DisputeNotActive();
        if (msg.value < MIN_VOTE_STAKE) revert InsufficientStake();

        // Check if already voted
        if (_votes[disputeId][msg.sender].stake != 0) revert AlreadyVoted();

        // Record vote
        _votes[disputeId][msg.sender] = Vote({
            disputeId: disputeId,
            voter: msg.sender,
            forFiler: forFiler,
            stake: msg.value,
            timestamp: block.timestamp
        });

        _voterDisputes[msg.sender].push(disputeId);

        // Update vote counts
        if (forFiler) {
            dispute.forVotes += msg.value;
        } else {
            dispute.againstVotes += msg.value;
        }

        emit VoteCast(disputeId, msg.sender, forFiler, msg.value);
    }

    /**
     * @notice Resolve a dispute (resolvers only)
     */
    function resolveDispute(
        uint256 disputeId,
        address winner,
        string calldata reason
    ) external onlyRole(RESOLVER_ROLE) {
        Dispute storage dispute = _disputes[disputeId];

        if (dispute.id != disputeId) revert DisputeNotFound();
        if (dispute.status == DisputeStatus.Resolved) revert DisputeAlreadyResolved();

        // Determine winner based on votes if not specified
        if (winner == address(0)) {
            winner = dispute.forVotes >= dispute.againstVotes ? dispute.filer : dispute.respondent;
        }

        dispute.winner = winner;
        dispute.resolutionReason = reason;
        dispute.status = DisputeStatus.Resolved;

        // Distribute stakes
        uint256 totalStake = dispute.filerStake + dispute.respondentStake;

        // Loser's stake goes to winner
        uint256 loserStake;
        address loser;

        if (winner == dispute.filer) {
            loser = dispute.respondent;
            loserStake = dispute.respondentStake;
        } else {
            loser = dispute.filer;
            loserStake = dispute.filerStake;
        }

        // Winner gets loser's stake
        if (loserStake > 0) {
            (bool success, ) = winner.call{value: loserStake}("");
            require(success, "ETH transfer failed");
        }

        // Return winner's stake
        uint256 winnerStake = winner == dispute.filer ? dispute.filerStake : dispute.respondentStake;
        if (winnerStake > 0) {
            (bool success, ) = winner.call{value: winnerStake}("");
            require(success, "ETH transfer failed");
        }

        // Update performance records
        if (winner == dispute.filer) {
            // Filer won - respondent loses a dispute
            _performance[dispute.respondent].lostDisputes++;
        } else {
            // Respondent won - filer loses a dispute
            _performance[dispute.filer].lostDisputes++;
        }

        // Remove from active disputes
        _removeFromActiveDisputes(disputeId);

        emit DisputeResolved(disputeId, winner, reason);
    }

    /**
     * @notice Cancel a dispute
     */
    function cancelDispute(uint256 disputeId) external {
        Dispute storage dispute = _disputes[disputeId];

        if (dispute.id != disputeId) revert DisputeNotFound();
        if (dispute.filer != msg.sender) revert NotAuthorized();
        if (dispute.status != DisputeStatus.Filed) revert DisputeNotActive();

        dispute.status = DisputeStatus.Cancelled;

        // Refund stakes
        if (dispute.filerStake > 0) {
            (bool success, ) = dispute.filer.call{value: dispute.filerStake}("");
            require(success, "ETH transfer failed");
        }

        if (dispute.respondentStake > 0) {
            (bool success, ) = dispute.respondent.call{value: dispute.respondentStake}("");
            require(success, "ETH transfer failed");
        }

        _removeFromActiveDisputes(disputeId);

        emit DisputeCancelled(disputeId);
    }

    // ============ Performance Tracking ============

    /**
     * @notice Record job completion
     */
    function recordCompletion(
        uint256 bountyId,
        address worker,
        bool onTime,
        uint8 qualityScore
    ) external {
        if (qualityScore > 100) revert("Invalid score");

        PerformanceRecord storage perf = _performance[worker];

        perf.totalJobs++;
        perf.lastUpdated = block.timestamp;

        if (onTime) {
            perf.onTimeJobs++;
        } else {
            perf.lateJobs++;
        }

        // Update average quality score
        uint256 oldAvg = perf.avgQualityScore;
        perf.avgQualityScore = (oldAvg * (perf.totalJobs - 1) + qualityScore) / perf.totalJobs;

        // Update completion rate
        perf.completionRate = (perf.totalJobs * 10000) / (perf.totalJobs + perf.cancelledJobs);

        // Update on-time rate
        perf.onTimeRate = (perf.onTimeJobs * 10000) / perf.totalJobs;

        emit PerformanceRecorded(bountyId, worker, onTime, qualityScore);
    }

    /**
     * @notice Record job cancellation
     */
    function recordCancellation(uint256 bountyId, address worker, string calldata reason) external {
        PerformanceRecord storage perf = _performance[worker];

        perf.cancelledJobs++;
        perf.lastUpdated = block.timestamp;

        // Update completion rate
        perf.completionRate = (perf.totalJobs * 10000) / (perf.totalJobs + perf.cancelledJobs);
    }

    /**
     * @notice Get performance stats
     */
    function getPerformanceStats(address user)
        external
        view
        returns (PerformanceRecord memory)
    {
        return _performance[user];
    }

    // ============ Penalties ============

    /**
     * @notice Issue a penalty to a user
     */
    function issuePenalty(
        address user,
        string calldata reason,
        uint256 severity
    ) external onlyRole(RESOLVER_ROLE) {
        if (severity == 0 || severity > MAX_SEVERITY) revert InvalidSeverity();

        _penaltyIdCounter++;
        uint256 penaltyId = _penaltyIdCounter;

        _penalties[penaltyId] = Penalty({
            id: penaltyId,
            user: user,
            reason: reason,
            severity: severity,
            timestamp: block.timestamp,
            active: true
        });

        _userPenalties[user].push(penaltyId);

        // Update reputation
        int256 penaltyAmount = -int256(severity * 10); // -10 to -100 points
        profileRegistry.updateReputation(user, penaltyAmount);

        emit PenaltyIssued(penaltyId, user, severity);
    }

    /**
     * @notice Lift a penalty
     */
    function liftPenalty(uint256 penaltyId) external onlyRole(RESOLVER_ROLE) {
        Penalty storage penalty = _penalties[penaltyId];

        if (penalty.id != penaltyId) revert PenaltyNotFound();
        if (!penalty.active) revert PenaltyNotActive();

        penalty.active = false;

        emit PenaltyLifted(penaltyId, penalty.user);
    }

    /**
     * @notice Check if user has active penalty
     */
    function hasActivePenalty(address user)
        external
        view
        returns (bool)
    {
        uint256[] memory penaltyIds = _userPenalties[user];

        for (uint256 i = 0; i < penaltyIds.length; i++) {
            if (_penalties[penaltyIds[i]].active) {
                return true;
            }
        }

        return false;
    }

    /**
     * @notice Get user's penalties
     */
    function getPenalties(address user)
        external
        view
        returns (Penalty[] memory)
    {
        uint256[] memory penaltyIds = _userPenalties[user];
        Penalty[] memory penalties = new Penalty[](penaltyIds.length);

        for (uint256 i = 0; i < penaltyIds.length; i++) {
            penalties[i] = _penalties[penaltyIds[i]];
        }

        return penalties;
    }

    // ============ View Functions ============

    /**
     * @notice Get dispute details
     */
    function getDispute(uint256 disputeId)
        external
        view
        returns (Dispute memory)
    {
        Dispute storage dispute = _disputes[disputeId];
        if (dispute.id != disputeId) revert DisputeNotFound();
        return dispute;
    }

    /**
     * @notice Get vote details
     */
    function getDisputeVote(uint256 disputeId, address voter)
        external
        view
        returns (Vote memory)
    {
        return _votes[disputeId][voter];
    }

    /**
     * @notice Get active disputes
     */
    function getActiveDisputes(uint256 offset, uint256 limit)
        external
        view
        returns (Dispute[] memory)
    {
        uint256 total = _activeDisputes.length;

        if (offset >= total) return new Dispute[](0);

        uint256 end = offset + limit;
        if (end > total) end = total;

        Dispute[] memory disputes = new Dispute[](end - offset);

        for (uint256 i = offset; i < end; i++) {
            disputes[i - offset] = _disputes[_activeDisputes[i]];
        }

        return disputes;
    }

    /**
     * @notice Get user's disputes
     */
    function getUserDisputes(address user, uint256 offset, uint256 limit)
        external
        view
        returns (Dispute[] memory)
    {
        // In production, maintain user => disputes mapping
        // For now, return empty
        return new Dispute[](0);
    }

    // ============ Internal Functions ============

    function _removeFromActiveDisputes(uint256 disputeId) internal {
        uint256 index = _activeDisputeIndex[disputeId];

        if (index >= _activeDisputes.length) return;
        if (_activeDisputes[index] != disputeId) return;

        uint256 lastIndex = _activeDisputes.length - 1;

        if (index != lastIndex) {
            uint256 lastDisputeId = _activeDisputes[lastIndex];
            _activeDisputes[index] = lastDisputeId;
            _activeDisputeIndex[lastDisputeId] = index;
        }

        _activeDisputes.pop();
        delete _activeDisputeIndex[disputeId];
    }

    /**
     * @notice Grant resolver role
     */
    function grantResolverRole(address resolver) external onlyOwner {
        _grantRole(RESOLVER_ROLE, resolver);
    }

    /**
     * @notice Allow contract to receive ETH
     */
    receive() external payable {}
}
