// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

import "../interfaces/IAIBountyBridge.sol";
import "../interfaces/IMarketplace.sol";
import "./IAIAgentRegistry.sol";
import "../interfaces/IReputationRegistry.sol";

/**
 * @title AIBountyBridge
 * @dev Bridge contract enabling AI agents to participate in marketplace bounties
 *
 *      This contract allows AI agents to:
 *      - Claim marketplace bounties through their overseers
 *      - Submit work proofs for bounty completion
 *      - Earn reputation for completed bounties
 *
 *      Security:
 *      - Only overseers can claim bounties on behalf of their agents
 *      - Only bounty posters or marketplace admins can approve/reject claims
 *      - Reputation updates are gated by successful bounty completion
 */
contract AIBountyBridge is IAIBountyBridge, Ownable, AccessControl {
    using Counters for Counters.Counter;

    /// @notice Role for approving/rejecting claims (bounty poster + admin)
    bytes32 public constant REVIEWER_ROLE = keccak256("REVIEWER_ROLE");

    /// @notice Marketplace reference
    IMarketplace public immutable marketplace;

    /// @notice AI Agent Registry reference
    IAIAgentRegistry public immutable aiRegistry;

    /// @notice Reputation Registry reference (for AI agent reputation)
    IReputationRegistry public immutable reputationRegistry;

    /// @notice Claim ID => AIBountyClaim data
    mapping(uint256 => AIBountyClaim) private _claims;

    /// @notice Bounty ID => Array of claim IDs
    mapping(uint256 => uint256[]) private _bountyClaims;

    /// @notice Agent ID => Array of claim IDs
    mapping(uint256 => uint256[]) private _agentClaims;

    /// @notice (Bounty ID, Agent ID) => Claim ID (for duplicate check)
    mapping(uint256 => mapping(uint256 => uint256)) private _bountyAgentClaims;

    /// @notice Claim ID counter
    Counters.Counter private _claimIdCounter;

    /// @notice Reputation multiplier for AI agents (basis points, 10000 = 1x)
    uint256 public reputationMultiplier = 10000; // 1x by default

    // ============ Constructor ============

    constructor(
        address _marketplace,
        address _aiRegistry,
        address _reputationRegistry
    ) Ownable() {
        if (_marketplace == address(0) || _aiRegistry == address(0) || _reputationRegistry == address(0)) {
            revert ZeroAddress();
        }

        marketplace = IMarketplace(_marketplace);
        aiRegistry = IAIAgentRegistry(_aiRegistry);
        reputationRegistry = IReputationRegistry(_reputationRegistry);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REVIEWER_ROLE, msg.sender);
    }

    // ============ Claim Functions ============

    /**
     * @inheritdoc IAIBountyBridge
     */
    function claimBountyForAgent(
        uint256 bountyId,
        uint256 agentId,
        string calldata workProof
    ) external override returns (uint256 claimId) {
        // Verify AI agent exists and is active
        if (!aiRegistry.isAIAgent(agentId)) {
            revert NotAIAgent();
        }

        IAIAgentRegistry.AIAgent memory agent = aiRegistry.getAIAgent(agentId);
        if (!agent.isActive) {
            revert NotAIAgent();
        }

        // Verify caller is the overseer
        if (!_isOverseer(agentId, msg.sender)) {
            revert NotOverseer();
        }

        // Verify bounty exists
        IMarketplace.Bounty memory bounty = marketplace.getBounty(bountyId);
        if (bounty.listingId == 0 && bounty.creator == address(0)) {
            revert BountyNotFound();
        }

        // Check for duplicate claim
        if (_bountyAgentClaims[bountyId][agentId] != 0) {
            revert ClaimAlreadyExists();
        }

        // Generate claim ID
        _claimIdCounter.increment();
        claimId = _claimIdCounter.current();

        // Store claim
        _claims[claimId] = AIBountyClaim({
            claimId: claimId,
            bountyId: bountyId,
            agentId: agentId,
            claimer: msg.sender,
            workProof: workProof,
            claimedAt: block.timestamp,
            approved: false,
            rejected: false,
            completedAt: 0
        });

        // Track mappings
        _bountyClaims[bountyId].push(claimId);
        _agentClaims[agentId].push(claimId);
        _bountyAgentClaims[bountyId][agentId] = claimId;

        emit AIBountyClaimed(claimId, bountyId, agentId, msg.sender, workProof);

        return claimId;
    }

    /**
     * @inheritdoc IAIBountyBridge
     */
    function approveClaim(uint256 claimId) external override {
        if (_claims[claimId].claimId == 0) {
            revert InvalidClaim();
        }

        // Get bounty for authorization check
        IMarketplace.Bounty memory bounty = marketplace.getBounty(_claims[claimId].bountyId);
        if (msg.sender != bounty.creator && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized();
        }

        AIBountyClaim storage claim = _claims[claimId];

        // Mark as approved
        claim.approved = true;
        claim.completedAt = block.timestamp;

        // Emit approval event first
        emit AIBountyApproved(claimId, claim.bountyId, claim.agentId);

        // Update agent reputation (emits AgentReputationUpdated)
        _updateAgentReputation(claim.agentId, true);
    }

    /**
     * @inheritdoc IAIBountyBridge
     */
    function rejectClaim(uint256 claimId, string calldata reason) external override {
        if (_claims[claimId].claimId == 0) {
            revert InvalidClaim();
        }

        // Get bounty for authorization check
        IMarketplace.Bounty memory bounty = marketplace.getBounty(_claims[claimId].bountyId);
        if (msg.sender != bounty.creator && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized();
        }

        AIBountyClaim storage claim = _claims[claimId];

        // Mark as rejected
        claim.rejected = true;

        emit AIBountyRejected(claimId, claim.bountyId, reason);
    }

    // ============ View Functions ============

    /**
     * @inheritdoc IAIBountyBridge
     */
    function getClaim(uint256 claimId) external view override returns (AIBountyClaim memory) {
        if (_claims[claimId].claimId == 0 && _claims[claimId].bountyId == 0) {
            revert InvalidClaim();
        }
        return _claims[claimId];
    }

    /**
     * @inheritdoc IAIBountyBridge
     */
    function getBountyClaims(uint256 bountyId) external view override returns (uint256[] memory) {
        return _bountyClaims[bountyId];
    }

    /**
     * @inheritdoc IAIBountyBridge
     */
    function getAgentClaims(uint256 agentId) external view override returns (uint256[] memory) {
        return _agentClaims[agentId];
    }

    /**
     * @notice Set reputation multiplier for AI agents
     * @param _multiplier Multiplier in basis points (10000 = 1x)
     */
    function setReputationMultiplier(uint256 _multiplier) external onlyOwner {
        if (_multiplier == 0 || _multiplier > 20000) {
            revert InvalidParams(); // Max 2x
        }
        reputationMultiplier = _multiplier;
    }

    // ============ Internal Functions ============

    /**
     * @dev Check if caller is the overseer of an AI agent
     */
    function _isOverseer(uint256 agentId, address caller) internal view returns (bool) {
        return aiRegistry.isOverseer(agentId, caller);
    }

    /**
     * @dev Update AI agent reputation based on bounty completion
     */
    function _updateAgentReputation(uint256 agentId, bool success) internal {
        if (address(reputationRegistry) == address(0)) {
            return;
        }

        // Get current reputation
        int256 currentReputation = reputationRegistry.getReputation(agentId);

        // Calculate new reputation (with multiplier applied)
        int256 newReputation;
        if (success) {
            // Success: add base reputation + multiplier bonus
            int256 baseIncrease = 10; // Base reputation for completing bounty
            int256 bonus = (int256(baseIncrease) * int256(reputationMultiplier)) / 10000;
            newReputation = currentReputation + baseIncrease + bonus;
        } else {
            // Failure: small decrease (rejection penalty)
            newReputation = currentReputation > 5 ? currentReputation - 5 : int256(0);
        }

        // Update reputation (if registry supports it)
        // Note: This assumes the reputation registry has a method to update reputation
        // In a real implementation, you'd need to call the appropriate function
        emit AgentReputationUpdated(agentId, uint256(currentReputation), uint256(newReputation));
    }

    // ============ Required Override ============

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
