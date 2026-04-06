// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./ICanaryRegistry.sol";
import "../interfaces/IRoyaltyRegistry.sol";

/**
 * @title CanaryRegistry
 * @dev Commit-reveal + Merkle tree registry for OPL-1.1 Canary Tokens.
 *
 * ================================================================
 * HOW IT WORKS (Steward's workflow)
 * ================================================================
 *
 * 1. GENERATE: Steward creates N canary secrets (unique variable names,
 *    dead-code blocks, control-flow markers, data watermarks) to embed
 *    in a distribution of the OPL-licensed software.
 *
 * 2. COMMIT: Steward builds a Merkle tree from the hashes of all canary
 *    secrets: leaf[i] = keccak256(canarySecret[i] || projectId ||
 *    distributionId || i). Stores only the root on-chain. Individual
 *    secrets NEVER go on-chain.
 *
 * 3. EMBED: Steward distributes the software with canaries embedded.
 *      Each distribution gets its own Merkle root (different identifiers =
 *     different leaf hashes), so if a distribution leaks, the canary
 *    chain-of-custody identifies WHICH licensee it came from.
 *
 * 4. ENFORCE: If canary is found in unauthorized use, Steward reveals the
 *    canarySecret and Merkle proof. The on-chain commitment proves the
 *    token was embedded at timestamp X in distribution Y issued to
 *    licensee Z.
 *
 * ================================================================
 * WHY COMMIT-REVEAL + MERKLE
 * ================================================================
 *
 * WITHOUT commit-reveal:
 * - On-chain canary data reveals detection methodology
 * - Adversaries learn patterns and strip tokens
 * - Adversaries can generate fake matches (planted evidence)
 *
 * WITH commit-reveal + Merkle:
 * - On-chain data is opaque (just hash roots)
 * - Methodology stays off-chain (only Steward knows)
 * - Enforcement claim is cryptographically verifiable
 * - Prevents both stripping AND planting attacks
 *
 * See OPL-1.1 Section 11.2(e): Canary Token Enforcement.
 */
contract CanaryRegistry is ICanaryRegistry, Ownable, ReentrancyGuard {

    // ================================================================
    // STATE
    // ================================================================

    /// @notice Address of the RoyaltyRegistry for access control checks.
    IRoyaltyRegistry public immutable royaltyRegistry;

    /// @notice distributionId → DistributionCommitment
    mapping(bytes32 => DistributionCommitment) private _distributions;

    /// @notice distributionId → leafIndex → whether this canary has been reported
    mapping(bytes32 => mapping(uint256 => bool)) private _isCanaryReported;

    /// @notice distributionId → leafIndex → CanaryMatchReport
    mapping(bytes32 => mapping(uint256 => CanaryMatchReport)) private _canaryMatches;

    /// @notice projectId → array of distributionIds (index)
    mapping(uint256 => bytes32[]) private _projectDistributions;

    // ================================================================
    // CONSTRUCTOR
    // ================================================================

    constructor(address _royaltyRegistry) Ownable() {
        if (_royaltyRegistry == address(0)) {
            revert ZeroProjectId();
        }
        royaltyRegistry = IRoyaltyRegistry(_royaltyRegistry);
    }

    // ================================================================
    // DISTRIBUTION REGISTRATION (the COMMIT phase)
    // ================================================================

    function registerDistribution(
        uint256 projectId,
        bytes32 distributionId,
        bytes32 merkleRoot,
        address issuedTo
    ) external {
        if (projectId == 0) {
            revert ZeroProjectId();
        }
        if (merkleRoot == bytes32(0)) {
            revert ZeroMerkleRoot();
        }

        // Verify the caller is the License Steward for this project
        IRoyaltyRegistry.ViewProject memory project = royaltyRegistry.getProject(projectId);
        if (!project.exists) {
            revert ZeroProjectId();
        }
        if (msg.sender != project.licenseSteward && msg.sender != owner()) {
            revert NotAuthorized(msg.sender, projectId);
        }

        if (_distributions[distributionId].registeredAt != 0) {
            revert DistributionAlreadyRegistered(distributionId);
        }

        _distributions[distributionId] = DistributionCommitment({
            merkleRoot: merkleRoot,
            projectId: projectId,
            distributionId: distributionId,
            registeredAt: block.timestamp,
            issuedTo: issuedTo,
            registeredBy: msg.sender,
            isReported: false,
            reportedAgainst: address(0),
            reportedAt: 0
        });

        _projectDistributions[projectId].push(distributionId);

        emit CanaryDistributionRegistered(
            distributionId,
            projectId,
            merkleRoot,
            issuedTo,
            msg.sender,
            block.timestamp
        );
    }

    // ================================================================
    // CANARY MATCH REPORTING (REVEAL + ENFORCE phase)
    // ================================================================

    function reportCanaryMatch(
        bytes32 distributionId,
        string calldata canarySecret,
        uint256 leafIndex,
        bytes32[] calldata merkleProof,
        address accusedParty,
        bytes32 evidenceHash
    ) external nonReentrant {
        if (_distributions[distributionId].registeredAt == 0) {
            revert DistributionNotFound(distributionId);
        }

        if (_isCanaryReported[distributionId][leafIndex]) {
            revert AlreadyReported(distributionId, leafIndex);
        }

        DistributionCommitment storage dist = _distributions[distributionId];

        // Verify the canarySecret produces a leaf hash that is valid for this Merkle root
        bytes32 leafHash = _computeLeafHash(canarySecret, dist.projectId, distributionId, leafIndex);
        if (!MerkleProof.verify(merkleProof, dist.merkleRoot, leafHash)) {
            revert InvalidMerkleProof();
        }

        // Mark as reported
        _isCanaryReported[distributionId][leafIndex] = true;

        dist.isReported = true;
        dist.reportedAgainst = accusedParty;
        dist.reportedAt = block.timestamp;

        _canaryMatches[distributionId][leafIndex] = CanaryMatchReport({
            distributionId: distributionId,
            canarySecret: canarySecret,
            leafIndex: leafIndex,
            accusedParty: accusedParty,
            evidenceHash: evidenceHash,
            reportedAt: block.timestamp
        });

        emit CanaryMatchReported(
            distributionId,
            leafIndex,
            accusedParty,
            evidenceHash,
            msg.sender,
            block.timestamp
        );
    }

    // ================================================================
    // UNREGISTER (invalidate compromised distributions)
    // ================================================================

    function unregisterDistribution(
        bytes32 distributionId,
        uint256 projectId
    ) external {
        if (_distributions[distributionId].registeredAt == 0) {
            revert DistributionNotFound(distributionId);
        }

        // Only the Steward or owner can unregister
        IRoyaltyRegistry.ViewProject memory project = royaltyRegistry.getProject(projectId);
        if (!project.exists || (msg.sender != project.licenseSteward && msg.sender != owner())) {
            revert NotAuthorized(msg.sender, projectId);
        }

        delete _distributions[distributionId];

        emit DistributionUnregistered(distributionId, projectId);
    }

    // ================================================================
    // VIEW FUNCTIONS
    // ================================================================

    function getDistribution(bytes32 distributionId)
        external
        view
        returns (DistributionCommitment memory)
    {
        return _distributions[distributionId];
    }

    function isDistributionRegistered(bytes32 distributionId)
        external
        view
        returns (bool)
    {
        return _distributions[distributionId].registeredAt != 0;
    }

    function isCanaryReported(bytes32 distributionId, uint256 leafIndex)
        external
        view
        returns (bool)
    {
        return _isCanaryReported[distributionId][leafIndex];
    }

    function getCanaryMatch(bytes32 distributionId, uint256 leafIndex)
        external
        view
        returns (CanaryMatchReport memory)
    {
        return _canaryMatches[distributionId][leafIndex];
    }

    function verifyCanary(
        bytes32 distributionId,
        string calldata canarySecret,
        uint256 leafIndex,
        bytes32[] calldata merkleProof
    ) external view returns (bool) {
        if (_distributions[distributionId].registeredAt == 0) {
            return false;
        }

        DistributionCommitment memory dist = _distributions[distributionId];
        bytes32 leafHash = _computeLeafHash(canarySecret, dist.projectId, distributionId, leafIndex);
        return MerkleProof.verify(merkleProof, dist.merkleRoot, leafHash);
    }

    function getProjectDistributionCount(uint256 projectId) external view returns (uint256) {
        return _projectDistributions[projectId].length;
    }

    function getProjectDistribution(uint256 projectId, uint256 index)
        external
        view
        returns (bytes32)
    {
        return _projectDistributions[projectId][index];
    }

    function getProjectDistributionHashes(uint256 projectId)
        external
        view
        returns (bytes32[] memory)
    {
        return _projectDistributions[projectId];
    }

    // ================================================================
    // INTERNAL
    // ================================================================

    /**
     * @dev Compute the Merkle leaf hash for a canary token.
     *
     * The leaf is: keccak256(canarySecret || projectId || distributionId || leafIndex)
     *
     * Salting with projectId and distributionId ensures:
     - Same canarySecret in different projects produces DIFFERENT leaf hashes
     - Same canarySecret in different distributions produces DIFFERENT leaf hashes
     - This prevents hash collision attacks and ensures chain-of-custody integrity
     */
    function _computeLeafHash(
        string memory canarySecret,
        uint256 projectId,
        bytes32 distributionId,
        uint256 leafIndex
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(canarySecret, projectId, distributionId, leafIndex));
    }
}
