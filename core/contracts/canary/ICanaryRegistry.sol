// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

/**
 * @title ICanaryRegistry
 * @dev Interface for the OPL-1.1 Canary Token Registry.
 *
 * Uses a commit-reveal + Merkle tree scheme to store canary token
 * commitments on-chain WITHOUT exposing:
 * - The actual canary payloads (variable names, dead code, markers)
 * - Embedding locations (which file/function the token lives in)
 * - Detection methodology (AST injection, data watermark, etc.)
 *
 * The on-chain commitment only proves:
 * - The canary existed at this timestamp
 * - It was embedded in a distribution for this project
 * - It was issued to a specific licensee (or public)
 *
 * Full canary details are revealed ONLY during enforcement.
 *
 * See OPL-1.1 Section 11.2(e): Canary Token Enforcement.
 */
interface ICanaryRegistry {

    // ================================================================
    // DATA STRUCTURES
    // ================================================================

    struct DistributionCommitment {
        bytes32 merkleRoot;           // Root hash of the canary Merkle tree
        uint256 projectId;            // Which OPL project owns this distribution
        bytes32 distributionId;       // Opaque distribution identifier (non-linking)
        uint256 registeredAt;         // When this commitment was registered on-chain
        address issuedTo;             // Licensee who received this distribution (0x0 = public)
        address registeredBy;         // License Steward who registered it
        bool isReported;              // Has a canary from this distribution been found in unauthorized use?
        address reportedAgainst;      // Who was caught using it
        uint256 reportedAt;           // When the match was reported
    }

    struct CanaryMatchReport {
        bytes32 distributionId;
        string canarySecret;          // The actual canary payload (revealed during enforcement)
        uint256 leafIndex;            // Position of this canary in the Merkle tree
        address accusedParty;         // Address or identifier of the infringing party
        bytes32 evidenceHash;         // Hash of the supporting evidence (code diff, screenshots, etc.)
        uint256 reportedAt;
    }

    // ================================================================
    // EVENTS
    // ================================================================

    event CanaryDistributionRegistered(
        bytes32 indexed distributionId,
        uint256 indexed projectId,
        bytes32 merkleRoot,
        address issuedTo,
        address registeredBy,
        uint256 registeredAt
    );

    event CanaryMatchReported(
        bytes32 indexed distributionId,
        uint256 leafIndex,
        address indexed accusedParty,
        bytes32 evidenceHash,
        address reportedBy,
        uint256 reportedAt
    );

    event DistributionUnregistered(
        bytes32 indexed distributionId,
        uint256 indexed projectId
    );

    // ================================================================
    // ERRORS
    // ================================================================

    error DistributionAlreadyRegistered(bytes32 distributionId);
    error DistributionNotFound(bytes32 distributionId);
    error InvalidMerkleProof();
    error CanarySecretRevealInvalid();
    error ZeroProjectId();
    error ZeroMerkleRoot();
    error AlreadyReported(bytes32 distributionId, uint256 leafIndex);
    error NotAuthorized(address caller, uint256 projectId);

    // ================================================================
    // WRITE FUNCTIONS
    // ================================================================

    /**
     * @dev Register a batch of canary tokens committed to in a Merkle tree.
     *
     *      The Steward pre-computes the Merkle root off-chain from all canary
     *      secrets to be embedded in a distribution. Only the root is stored
     *      on-chain. Individual canary secrets remain off-chain until
     *      enforcement is triggered.
     *
     * @param projectId     The OPL project this distribution belongs to
     * @param distributionId A unique opaque identifier for this distribution
     * @param merkleRoot    Root hash of the canary Merkle tree
     * @param issuedTo      Address of the licensee who received this distribution
     *                      (address(0) for public/eval distributions)
     */
    function registerDistribution(
        uint256 projectId,
        bytes32 distributionId,
        bytes32 merkleRoot,
        address issuedTo
    ) external;

    /**
     * @dev Report that a canary token was found in unauthorized use.
     *
     *      The Steward reveals the canarySecret and provides a Merkle proof
     *      demonstrating that this token belongs to the registered distribution.
     *      This creates an immutable public record of the infringement.
     *
     * @param distributionId The distribution identifier containing this canary
     * @param canarySecret   The actual canary payload string (revealed now)
     * @param leafIndex      The index of this canary in the Merkle tree
     * @param merkleProof    The Merkle path from leaf to root
     * @param accusedParty   Identifier of the entity found using the code
     * @param evidenceHash   keccak256 hash of supporting evidence bundle
     */
    function reportCanaryMatch(
        bytes32 distributionId,
        string calldata canarySecret,
        uint256 leafIndex,
        bytes32[] calldata merkleProof,
        address accusedParty,
        bytes32 evidenceHash
    ) external;

    /**
     * @dev Invalidate a distribution commitment (e.g., if the distribution
     *      was compromised before deployment). Only the Steward can call this.
     *
     * @param distributionId The distribution to invalidate
     * @param projectId      Project ID (access control check)
     */
    function unregisterDistribution(
        bytes32 distributionId,
        uint256 projectId
    ) external;

    // ================================================================
    // VIEW FUNCTIONS
    // ================================================================

    /**
     * @dev Get the DistributionCommitment for a given distribution.
     */
    function getDistribution(bytes32 distributionId)
        external
        view
        returns (DistributionCommitment memory);

    /**
     * @dev Check if a distribution is registered.
     */
    function isDistributionRegistered(bytes32 distributionId)
        external
        view
        returns (bool);

    /**
     * @dev Check if a specific canary (by distribution + leaf index)
     *      has been reported as a match against an unauthorized user.
     */
    function isCanaryReported(bytes32 distributionId, uint256 leafIndex)
        external
        view
        returns (bool);

    /**
     * @dev Get a CanaryMatchReport for a reported canary.
     */
    function getCanaryMatch(bytes32 distributionId, uint256 leafIndex)
        external
        view
        returns (CanaryMatchReport memory);

    /**
     * @dev Verify that a canarySecret belongs to a registered distribution
     *      by checking the Merkle proof against the on-chain root.
     *
     *      This is a pure verification function — anyone can call it to
     *      independently verify a Steward's enforcement claim.
     *
     * @param distributionId The registered distribution
     * @param canarySecret   The canary string to verify
     * @param leafIndex      Position in the Merkle tree
     * @param merkleProof    Merkle path from leaf to root
     */
    function verifyCanary(
        bytes32 distributionId,
        string calldata canarySecret,
        uint256 leafIndex,
        bytes32[] calldata merkleProof
    ) external view returns (bool);
}
