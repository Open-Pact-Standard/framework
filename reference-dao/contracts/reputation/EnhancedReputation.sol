// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import { IEnhancedReputation } from "./interfaces/IEnhancedReputation.sol";

/**
 * @title EnhancedReputation
 * @dev Anti-brigading reputation system
 *
 *      Features:
 *      - Stake-weighted reviews (must stake tokens to review)
 *      - Diversity bonus (reviews from diverse sources count more)
 *      - Attestation chains (verified members' reviews count more)
 *      - Time decay (recent reviews matter more)
 *      - Challenge system (flagged reviews can be disputed)
 *
 *      Anti-Brigading Protections:
 *      1. Must stake tokens to review - lose stake if malicious
 *      2. Diversity bonus - reviews from different sources count more
 *      3. Attestation chains - verified members carry more weight
 *      4. Time decay - old reviews have less impact
 *      5. Challenge system - anyone can challenge with stake
 */
contract EnhancedReputation is IEnhancedReputation, Ownable, AccessControl {
    /// @notice Review ID counter
    uint256 private _reviewIdCounter;

    /// @notice Challenge ID counter
    uint256 private _challengeIdCounter;

    /// @notice Review ID => Review data
    mapping(uint256 => Review) private _reviews;

    /// @notice Subject ID => Review IDs
    mapping(uint256 => uint256[]) private _subjectReviews;

    /// @notice Review ID => Attestation ID => Attestation
    mapping(uint256 => mapping(uint256 => Attestation)) private _attestations;

    /// @notice Review ID => Attestation IDs
    mapping(uint256 => uint256[]) private _reviewAttestations;

    /// @notice Review ID => Attester => Has attested
    mapping(uint256 => mapping(address => bool)) private _hasAttested;

    /// @notice Review ID => Challenge
    mapping(uint256 => Challenge) private _challenges;

    /// @notice Subject ID => ReputationScore
    mapping(uint256 => ReputationScore) private _reputationScores;

    /// @notice Reviewer => Subjects reviewed (for diversity calculation)
    mapping(address => uint256[]) private _reviewerSubjects;

    /// @notice Subject => Reviewers (for reverse lookup)
    mapping(uint256 => mapping(address => bool)) private _hasReviewed;

    /// @notice Verifier role (can attest to reviews)
    bytes32 public constant VERIFIER_ROLE = keccak256("VERIFIER_ROLE");

    /// @notice Platform resolver role
    bytes32 public constant RESOLVER_ROLE = keccak256("RESOLVER_ROLE");

    // ============ Constants ============

    /// @notice Minimum stake to submit a review
    uint256 public constant MIN_STAKE = 0.01 ether;

    /// @notice Maximum stake for a review
    uint256 public constant MAX_STAKE = 10 ether;

    /// @notice Minimum challenge stake
    uint256 public constant MIN_CHALLENGE_STAKE = 0.05 ether;

    /// @notice Review score range
    int8 public constant MIN_SCORE = -5;
    int8 public constant MAX_SCORE = 5;

    /// @notice Decay period (90 days)
    uint256 public constant DECAY_PERIOD = 90 days;

    /// @notice Attestation bonus multiplier (basis points)
    uint256 public constant ATTESTATION_BONUS_BPS = 5000; // 1.5x

    /// @notice Diversity bonus multiplier (basis points)
    uint256 public constant DIVERSITY_BONUS_BPS = 3000; // 1.3x

    /// @notice Time decay factor (per period)
    uint256 public constant TIME_DECAY_BPS = 9000; // 0.9x per period

    /// @notice Slash percentage for successful challenges
    uint256 public constant CHALLENGE_SLASH_BPS = 5000; // 50%

    // ============ Custom Errors ============

    error InvalidScore();
    error InvalidStake();
    error InvalidSubject();
    error SelfReview();
    error AlreadyReviewed();
    error ReviewNotFound();
    error NotReviewer();
    error AlreadyAttested();
    error ChallengeNotFound();
    error ChallengeNotActive();
    error InsufficientStake();
    error InvalidVerifier();

    // ============ Constructor ============

    constructor() Ownable() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VERIFIER_ROLE, msg.sender);
        _grantRole(RESOLVER_ROLE, msg.sender);
    }

    // ============ Reviews ============

    /**
     * @notice Submit a staked review
     */
    function submitReview(
        uint256 subjectId,
        int8 score,
        uint256 stake,
        string calldata evidence
    ) external payable returns (uint256 reviewId) {
        if (score < MIN_SCORE || score > MAX_SCORE) revert InvalidScore();
        if (stake < MIN_STAKE || stake > MAX_STAKE) revert InvalidStake();
        if (subjectId == 0) revert InvalidSubject();
        if (subjectId == uint256(uint160(msg.sender))) revert SelfReview();

        // Check if already reviewed
        if (_hasReviewed[subjectId][msg.sender]) revert AlreadyReviewed();

        _reviewIdCounter++;
        reviewId = _reviewIdCounter;

        // Transfer stake
        if (msg.value < stake) revert InsufficientStake();

        // Calculate initial weighted score
        uint256 stakeWeight = _getStakeWeight(stake);
        uint256 diversityBonus = _getDiversityBonus(msg.sender, subjectId);
        int256 weightedScore = int256(int8(score)) * int256(stakeWeight + diversityBonus);

        _reviews[reviewId] = Review({
            id: reviewId,
            subjectId: subjectId,
            reviewer: msg.sender,
            score: score,
            stake: stake,
            evidence: evidence,
            timestamp: block.timestamp,
            isValid: true,
            isChallenged: false,
            attestations: 0,
            diversityScore: diversityBonus,
            finalScore: weightedScore
        });

        _subjectReviews[subjectId].push(reviewId);
        _reviewerSubjects[msg.sender].push(subjectId);
        _hasReviewed[subjectId][msg.sender] = true;

        // Update subject's reputation
        _updateReputation(subjectId);

        emit ReviewSubmitted(reviewId, subjectId, msg.sender, score, stake);
        return reviewId;
    }

    /**
     * @notice Attest to a review (verifiers only)
     */
    function attestReview(uint256 reviewId, bool isValid) external {
        if (!hasRole(VERIFIER_ROLE, msg.sender)) revert InvalidVerifier();

        Review storage review = _reviews[reviewId];
        if (review.id != reviewId) revert ReviewNotFound();

        if (_hasAttested[reviewId][msg.sender]) revert AlreadyAttested();

        _attestations[reviewId][review.attestations] = Attestation({
            reviewId: reviewId,
            attester: msg.sender,
            isValid: isValid,
            timestamp: block.timestamp
        });

        _reviewAttestations[reviewId].push(review.attestations);
        _hasAttested[reviewId][msg.sender] = true;

        review.attestations++;

        // Update weighted score based on attestation
        if (isValid) {
            uint256 attestationBonus = (review.stake * ATTESTATION_BONUS_BPS) / 10000;
            review.finalScore += int256(attestationBonus);
        } else {
            // Penalty for invalid attestation
            review.finalScore = review.finalScore / 2;
        }

        _updateReputation(review.subjectId);

        emit ReviewAttested(reviewId, msg.sender, isValid);
    }

    /**
     * @notice Challenge a review
     */
    function challengeReview(
        uint256 reviewId,
        string calldata reason
    ) external payable returns (uint256 challengeId) {
        Review storage review = _reviews[reviewId];
        if (review.id != reviewId) revert ReviewNotFound();
        if (!review.isValid) revert ReviewNotFound();
        if (msg.value < MIN_CHALLENGE_STAKE) revert InsufficientStake();

        _challengeIdCounter++;
        challengeId = _challengeIdCounter;

        _challenges[challengeId] = Challenge({
            reviewId: reviewId,
            challenger: msg.sender,
            reason: reason,
            stake: msg.value,
            timestamp: block.timestamp,
            resolved: false,
            successful: false
        });

        review.isChallenged = true;

        emit ReviewChallenged(reviewId, challengeId, msg.sender, reason);
        return challengeId;
    }

    /**
     * @notice Resolve a challenge (resolvers only)
     */
    function resolveChallenge(uint256 challengeId, bool upholdChallenge) external onlyRole(RESOLVER_ROLE) {
        Challenge storage challenge = _challenges[challengeId];
        if (challenge.reviewId == 0) revert ChallengeNotFound();
        if (challenge.resolved) revert ChallengeNotActive();

        Review storage review = _reviews[challenge.reviewId];
        challenge.resolved = true;
        challenge.successful = upholdChallenge;

        uint256 penalty;

        if (upholdChallenge) {
            // Challenge successful - slash reviewer
            penalty = (review.stake * CHALLENGE_SLASH_BPS) / 10000;

            // Split penalty between challenger and platform
            uint256 challengerReward = penalty / 2;
            uint256 platformReward = penalty - challengerReward;

            // Refund challenger's stake + reward
            uint256 totalToChallenger = challenge.stake + challengerReward;
            (bool success, ) = challenge.challenger.call{value: totalToChallenger}("");
            require(success, "ETH transfer failed");

            // Platform keeps the rest
            review.finalScore = 0; // Nullify the review
            review.isValid = false;
        } else {
            // Challenge failed - challenger loses stake
            penalty = challenge.stake;

            // Reviewer gets the challenger's stake as bonus
            (bool success, ) = review.reviewer.call{value: penalty}("");
            require(success, "ETH transfer failed");

            // Bonus for successfully defending review
            review.finalScore += int256(penalty);
        }

        review.isChallenged = false;

        // Update subject's reputation
        _updateReputation(review.subjectId);

        emit ChallengeResolved(challengeId, upholdChallenge, penalty);
    }

    // ============ View Functions ============

    /**
     * @notice Get review details
     */
    function getReview(uint256 reviewId)
        external
        view
        returns (Review memory)
    {
        Review storage review = _reviews[reviewId];
        if (review.id != reviewId) revert ReviewNotFound();
        return review;
    }

    /**
     * @notice Get reviews for a subject
     */
    function getSubjectReviews(uint256 subjectId, uint256 offset, uint256 limit)
        external
        view
        returns (Review[] memory)
    {
        uint256[] memory reviewIds = _subjectReviews[subjectId];

        uint256 start = offset;
        uint256 end = offset + limit;
        if (end > reviewIds.length) end = reviewIds.length;

        Review[] memory reviews = new Review[](end - start);

        for (uint256 i = start; i < end; i++) {
            reviews[i - start] = _reviews[reviewIds[i]];
        }

        return reviews;
    }

    /**
     * @notice Get reputation score for a subject
     */
    function getReputation(uint256 subjectId)
        external
        view
        returns (ReputationScore memory)
    {
        return _reputationScores[subjectId];
    }

    /**
     * @notice Calculate reputation for a subject
     */
    function calculateReputation(uint256 subjectId)
        external
        view
        returns (uint256)
    {
        return _calculateReputationInternal(subjectId);
    }

    /**
     * @notice Check if attester can attest
     */
    function canAttest(address attester, uint256 reviewId)
        external
        view
        returns (bool)
    {
        return hasRole(VERIFIER_ROLE, attester) && !_hasAttested[reviewId][attester];
    }

    /**
     * @notice Get attestations for a review
     */
    function getAttestations(uint256 reviewId)
        external
        view
        returns (Attestation[] memory)
    {
        uint256[] memory attestationIds = _reviewAttestations[reviewId];
        Attestation[] memory attestations = new Attestation[](attestationIds.length);

        for (uint256 i = 0; i < attestationIds.length; i++) {
            attestations[i] = _attestations[reviewId][attestationIds[i]];
        }

        return attestations;
    }

    /**
     * @notice Get challenge details
     */
    function getChallenge(uint256 challengeId)
        external
        view
        returns (Challenge memory)
    {
        Challenge storage challenge = _challenges[challengeId];
        if (challenge.reviewId == 0) revert ChallengeNotFound();
        return challenge;
    }

    // ============ Reputation Weights ============

    /**
     * @notice Get stake weight
     */
    function getStakeWeight(uint256 stake)
        external
        pure
        returns (uint256)
    {
        return _getStakeWeight(stake);
    }

    /**
     * @notice Get diversity bonus
     */
    function getDiversityBonus(address reviewer, uint256 subjectId)
        external
        view
        returns (uint256)
    {
        return _getDiversityBonus(reviewer, subjectId);
    }

    /**
     * @notice Get time decay factor
     */
    function getTimeDecay(uint256 reviewTimestamp)
        external
        view
        returns (uint256)
    {
        return _getTimeDecay(reviewTimestamp);
    }

    // ============ Internal Functions ============

    function _getStakeWeight(uint256 stake)
        internal
        pure
        returns (uint256)
    {
        // Linear scaling: 1 stake = 1 weight, 10 stake = 10 weight
        return stake / 1e14; // Scale down for manageable numbers
    }

    function _getDiversityBonus(address reviewer, uint256 subjectId)
        internal
        view
        returns (uint256)
    {
        // Check if reviewer has reviewed this subject before
        if (_hasReviewed[subjectId][reviewer]) {
            return 0; // No bonus for repeat reviews
        }

        // Check how many different subjects this reviewer has reviewed
        uint256 uniqueSubjects = _reviewerSubjects[reviewer].length;

        // Bonus increases with diversity (more subjects reviewed = higher diversity)
        // Base bonus + 10% per unique subject (max 100% bonus)
        uint256 diversityBonus = (uniqueSubjects * 1000) / 100; // 10% per subject

        if (diversityBonus > DIVERSITY_BONUS_BPS) {
            diversityBonus = DIVERSITY_BONUS_BPS;
        }

        return diversityBonus;
    }

    function _getTimeDecay(uint256 reviewTimestamp)
        internal
        view
        returns (uint256)
    {
        if (block.timestamp <= reviewTimestamp) return 10000; // 100% (no decay)

        uint256 elapsed = block.timestamp - reviewTimestamp;
        uint256 periods = elapsed / DECAY_PERIOD;

        // Apply decay for each period: 0.9 ^ periods
        uint256 decay = 10000;
        for (uint256 i = 0; i < periods && decay > 1000; i++) {
            decay = (decay * TIME_DECAY_BPS) / 10000;
        }

        return decay;
    }

    function _updateReputation(uint256 subjectId) internal {
        uint256 newScore = _calculateReputationInternal(subjectId);
        ReputationScore storage rep = _reputationScores[subjectId];

        uint256 oldScore = rep.finalScore;
        rep.subjectId = subjectId;
        rep.finalScore = newScore;
        rep.lastUpdated = block.timestamp;

        emit ReputationUpdated(subjectId, oldScore, newScore);
    }

    function _calculateReputationInternal(uint256 subjectId)
        internal
        view
        returns (uint256)
    {
        uint256[] memory reviewIds = _subjectReviews[subjectId];
        int256 totalScore = 0;
        uint256 validReviews = 0;

        for (uint256 i = 0; i < reviewIds.length; i++) {
            Review storage review = _reviews[reviewIds[i]];

            if (!review.isValid) continue;

            // Apply time decay
            uint256 timeDecay = _getTimeDecay(review.timestamp);
            int256 decayedScore = (review.finalScore * int256(timeDecay)) / 10000;

            totalScore += decayedScore;
            validReviews++;
        }

        // Ensure non-negative result
        if (totalScore < 0) totalScore = 0;

        // Base reputation of 100 + weighted score
        uint256 finalScore = 100 + uint256(totalScore);

        return finalScore;
    }

    /**
     * @notice Grant verifier role
     */
    function grantVerifierRole(address verifier) external onlyOwner {
        _grantRole(VERIFIER_ROLE, verifier);
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
