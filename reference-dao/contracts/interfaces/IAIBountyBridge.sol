// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "../interfaces/IMarketplace.sol";
import "../ai/IAIAgentRegistry.sol";

/**
 * @title IAIBountyBridge
 * @dev Interface for AI Agent to Marketplace integration
 *      Enables AI agents to discover, claim, and complete marketplace bounties
 */
interface IAIBountyBridge {
    /**
     * @dev Bounty claim request from AI agent
     */
    struct AIBountyClaim {
        uint256 claimId;          // Unique claim ID
        uint256 bountyId;        // Bounty being claimed
        uint256 agentId;         // AI agent claiming
        address claimer;         // Address submitting claim (overseer or agent)
        string workProof;        // IPFS hash of work proof/metadata
        uint256 claimedAt;       // When claim was submitted
        bool approved;           // Whether claim was approved
        bool rejected;           // Whether claim was rejected
        uint256 completedAt;     // When bounty was completed
    }

    // ============ Events ============

    event AIBountyClaimed(
        uint256 indexed claimId,
        uint256 indexed bountyId,
        uint256 indexed agentId,
        address claimer,
        string workProof
    );

    event AIBountyApproved(
        uint256 indexed claimId,
        uint256 indexed bountyId,
        uint256 indexed agentId
    );

    event AIBountyRejected(
        uint256 indexed claimId,
        uint256 indexed bountyId,
        string reason
    );

    event AgentReputationUpdated(
        uint256 indexed agentId,
        uint256 oldReputation,
        uint256 newReputation
    );

    // ============ Errors ============

    error NotAIAgent();
    error NotOverseer();
    error BountyNotFound();
    error InvalidClaim();
    error ClaimAlreadyExists();
    error Unauthorized();
    error InvalidParams();
    error ZeroAddress();

    // ============ Marketplace Functions ============

    /**
     * @notice Claim a bounty on behalf of an AI agent
     * @param bountyId The bounty to claim
     * @param agentId The AI agent claiming the bounty
     * @param workProof IPFS hash of work proof
     * @return claimId The new claim ID
     */
    function claimBountyForAgent(
        uint256 bountyId,
        uint256 agentId,
        string calldata workProof
    ) external returns (uint256 claimId);

    /**
     * @notice Approve an AI agent's bounty claim
     * @param claimId The claim to approve
     */
    function approveClaim(uint256 claimId) external;

    /**
     * @notice Reject an AI agent's bounty claim
     * @param claimId The claim to reject
     * @param reason Reason for rejection
     */
    function rejectClaim(uint256 claimId, string calldata reason) external;

    /**
     * @notice Get claim details
     * @param claimId The claim ID
     * @return claim The claim details
     */
    function getClaim(uint256 claimId) external view returns (AIBountyClaim memory);

    /**
     * @notice Get all claims for a bounty
     * @param bountyId The bounty ID
     * @return claims Array of claim IDs
     */
    function getBountyClaims(uint256 bountyId) external view returns (uint256[] memory);

    /**
     * @notice Get all claims for an agent
     * @param agentId The agent ID
     * @return claims Array of claim IDs
     */
    function getAgentClaims(uint256 agentId) external view returns (uint256[] memory);
}
