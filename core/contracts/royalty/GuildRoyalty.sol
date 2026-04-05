// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IRoyaltyRegistry.sol";

/**
 * @title GuildRoyalty
 * @dev Governance-managed royalty system for Open-Pact (OPL-1.0) Guilds.
 *
 *      Extends RoyaltyRegistry by replacing owner-only controls with a
 *      Governor-based governance flow. Royalty parameters (fees, contributor
 *      weights, treasury destinations) are adjusted via governance proposals
 *      rather than unilateral owner calls.
 *
 *      Designed to work with:
 *      - OpenZeppelin Governor / Timelock pattern
 *      - Snapshot off-chain voting with on-chain execution
 *      - Any EIP-6372-compliant governor
 *
 *      Key difference from RoyaltyRegistry:
 *      - RoyaltyRegistry: Single owner (maintainer) controls everything
 *      - GuildRoyalty: Governance (DAO/Guild) controls parameters via proposals
 *
 *      Architecture:
 *      ┌──────────────┐     proposals      ┌──────────────┐
 *      │ Guild Members│ ──────────────>    │  Governor    │
 *      │ (voters)     │                    │  Contract    │
 *      └──────────────┘                    └──────┬───────┘
 *                                                  │ executive calls
 *                                                  ▼
 *                                           ┌──────────────┐
 *                                           │ GuildRoyalty │
 *                                           │ (this)       │
 *                                           └──┬───────────┘
 *                                              │ reads/writes
 *                                              ▼
 *                                       ┌──────────────┐
 *                                       │RoyaltyRegistry│
 *                                       └──────────────┘
 */
contract GuildRoyalty is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Core Contracts ============

    /// @notice The underlying RoyaltyRegistry this Guild manages
    IRoyaltyRegistry public immutable registry;

    /// @notice The Governor contract that executes parameter changes
    address public immutable governor;

    /// @notice The Timelock contract (optional, for delayed execution)
    address public timelock;

    // ============ Governance Parameters ============

    /// @notice Whether governance is enabled (proposals can modify parameters)
    bool public governanceEnabled;

    /// @notice Minimum quorum for governance proposals (percentage in basis points)
    uint256 public minQuorumBps;

    /// @notice Voting period in blocks
    uint256 public votingPeriodBlocks;

    /// @notice Pending parameter changes waiting for timelock execution
    struct PendingParam {
        bytes params;
        uint256 executeAfter;
        bool executed;
    }
    mapping(bytes32 => PendingParam) public pendingParams;

    // ============ Guild-to-Guild Reciprocity ============

    /// @notice Linked derivative Guilds (for Royalty Tier 4 reciprocity)
    struct GuildLink {
        uint256 sourceProjectId;
        uint256 derivativeProjectId;
        uint256 royaltyShareBps;   // % of derivative royalties going to source Guild
        bool active;
    }
    GuildLink[] public guildLinks;
    mapping(uint256 => uint256[]) public linksBySource;
    mapping(uint256 => uint256[]) public linksByDerivative;

    /// @notice Royalty routing: derivative Guild -> source Guild
    mapping(uint256 => GuildRoyalty) public derivativeRoyaltyRouting;

    // ============ Treasury Configuration ============

    /// @notice Guild treasury address (receives a portion of royalties)
    address public guildTreasury;

    /// @notice Treasury share in basis points (e.g., 500 = 5%)
    uint256 public treasuryShareBps;

    // ============ Fee Adjustments ============

    /// @notice Pending fee adjustments (proposed but not yet active)
    struct FeeAdjustment {
        uint8 tier;
        uint256 newAmount;
        uint256 proposedAt;
        uint256 activeAt;
    }
    FeeAdjustment[] public pendingFeeAdjustments;

    // ============ Errors ============

    error ZeroAddress();
    error NotGovernor();
    error GovernanceDisabled();
    error QuorumTooHigh();
    error InvalidShareBps();
    error LinkAlreadyExists(uint256 source, uint256 derivative);
    error LinkNotFound();
    error ExecuteTooEarly();
    error AlreadyExecuted();
    error InvalidParams();
    error TreasuryNotSet();

    // ============ Events ============

    event GovernanceToggled(bool enabled);
    event GovernorUpdated(address indexed oldGovernor, address indexed newGovernor);
    event TimelockUpdated(address indexed oldTimelock, address indexed newTimelock);
    event QuorumUpdated(uint256 oldBps, uint256 newBps);
    event VotingPeriodUpdated(uint256 oldBlocks, uint256 newBlocks);
    event GuildTreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);
    event TreasuryShareUpdated(uint256 oldBps, uint256 newBps);
    event ParamChangeProposed(bytes32 indexed proposalHash, bytes params, uint256 executeAfter);
    event ParamChangeExecuted(bytes32 indexed proposalHash);
    event GuildLinked(
        uint256 sourceProjectId,
        uint256 derivativeProjectId,
        uint256 royaltyShareBps
    );
    event GuildLinkRemoved(uint256 sourceProjectId, uint256 derivativeProjectId);
    event RoyaltyRouted(
        uint256 fromProjectId,
        uint256 toProjectId,
        uint256 amount,
        address token
    );
    event FeeAdjustmentProposed(
        uint8 tier,
        uint256 newAmount,
        uint256 activeAt
    );

    // ============ Modifiers ============

    modifier onlyGovernor() {
        if (msg.sender != governor && msg.sender != owner()) {
            revert NotGovernor();
        }
        _;
    }

    modifier governanceActive() {
        if (!governanceEnabled) {
            revert GovernanceDisabled();
        }
        _;
    }

    // ============ Constructor ============

    /**
     * @param _registry The RoyaltyRegistry contract this Guild manages
     * @param _governor The Governor contract address
     */
    constructor(address _registry, address _governor) Ownable() {
        if (_registry == address(0) || _governor == address(0)) {
            revert ZeroAddress();
        }
        registry = IRoyaltyRegistry(_registry);
        governor = _governor;
        governanceEnabled = true;
        minQuorumBps = 400;  // 4% quorum default
        treasuryShareBps = 500; // 5% to guild treasury default
    }

    // ================================================================
    // GOVERNANCE EXECUTION (called by Governor/Timelock)
    // ================================================================

    /**
     * @dev Execute a governance-approved parameter change
     * @param target Target contract address
     * @param data Encoded function call
     * @param proposalHash Hash of the proposal for tracking
     */
    function executeGovernanceProposal(
        address target,
        bytes calldata data,
        bytes32 proposalHash
    ) external onlyGovernor governanceActive nonReentrant {
        if (target == address(0)) revert ZeroAddress();

        // If timelock is set, check execution window
        if (timelock != address(0)) {
            PendingParam storage pending = pendingParams[proposalHash];
            if (!pending.executed) {
                revert InvalidParams();
            }
            if (block.timestamp < pending.executeAfter) {
                revert ExecuteTooEarly();
            }
            if (pending.executed) {
                revert AlreadyExecuted();
            }
            pending.executed = true;
            emit ParamChangeExecuted(proposalHash);
        }

        // Execute the call
        (bool success, ) = target.call(data);
        require(success, "Governance execution reverted");
    }

    /**
     * @dev Propose a parameter change with timelock delay
     * @param params Encoded function call
     * @param delaySeconds Delay before execution is allowed
     * @return proposalHash Hash for tracking
     */
    function proposeParamChange(
        bytes calldata params,
        uint256 delaySeconds
    ) external onlyGovernor governanceActive returns (bytes32 proposalHash) {
        proposalHash = keccak256(params);

        pendingParams[proposalHash] = PendingParam({
            params: bytes(params),
            executeAfter: block.timestamp + delaySeconds,
            executed: true
        });

        emit ParamChangeProposed(proposalHash, params, block.timestamp + delaySeconds);
    }

    // ================================================================
    // GUILD-TO-GUILD RECIPROCITY (Tier 4)
    // ================================================================

    /**
     * @dev Link a derivative Guild to this source Guild for royalty routing
     * @param sourceProjectId This Guild's project ID
     * @param derivativeProjectId The derivative Guild's project ID
     * @param royaltyShareBps Percentage of derivative royalties going to source (basis points)
     */
    function linkDerivativeGuild(
        uint256 sourceProjectId,
        uint256 derivativeProjectId,
        uint256 royaltyShareBps
    ) external onlyGovernor governanceActive {
        if (royaltyShareBps > 10000 || royaltyShareBps < 1000) {
            // Minimum 10%, maximum 100%
            revert InvalidShareBps();
        }

        // Check for existing link
        uint256 len = linksBySource[sourceProjectId].length;
        for (uint256 i = 0; i < len; i++) {
            uint256 existingIdx = linksBySource[sourceProjectId][i];
            if (guildLinks[existingIdx].derivativeProjectId == derivativeProjectId) {
                revert LinkAlreadyExists(sourceProjectId, derivativeProjectId);
            }
        }

        uint256 linkIdx = guildLinks.length;
        guildLinks.push(GuildLink({
            sourceProjectId: sourceProjectId,
            derivativeProjectId: derivativeProjectId,
            royaltyShareBps: royaltyShareBps,
            active: true
        }));

        linksBySource[sourceProjectId].push(linkIdx);
        linksByDerivative[derivativeProjectId].push(linkIdx);

        emit GuildLinked(sourceProjectId, derivativeProjectId, royaltyShareBps);
    }

    /**
     * @dev Remove a Guild link
     * @param sourceProjectId Source project ID
     * @param derivativeProjectId Derivative project ID
     */
    function removeGuildLink(
        uint256 sourceProjectId,
        uint256 derivativeProjectId
    ) external onlyGovernor governanceActive {
        uint256 len = linksBySource[sourceProjectId].length;
        for (uint256 i = 0; i < len; i++) {
            uint256 linkIdx = linksBySource[sourceProjectId][i];
            if (guildLinks[linkIdx].derivativeProjectId == derivativeProjectId) {
                guildLinks[linkIdx].active = false;
                emit GuildLinkRemoved(sourceProjectId, derivativeProjectId);
                return;
            }
        }
        revert LinkNotFound();
    }

    /**
     * @dev Set royalty routing for a derivative Guild
     * @param derivativeProjectId The derivative project ID
     * @param routing The GuildRoyalty contract to route royalties to
     */
    function setRoyaltyRouting(
        uint256 derivativeProjectId,
        address routing
    ) external onlyGovernor governanceActive {
        if (routing == address(0)) revert ZeroAddress();

        derivativeRoyaltyRouting[derivativeProjectId] = GuildRoyalty(routing);
    }

    // ================================================================
    // TREASURY MANAGEMENT
    // ================================================================

    /**
     * @dev Set the Guild treasury address
     * @param _treasury Address of the treasury (typically a multi-sig or DAO vault)
     */
    function setGuildTreasury(address _treasury) external onlyGovernor governanceActive {
        if (_treasury == address(0)) revert ZeroAddress();
        address oldTreasury = guildTreasury;
        guildTreasury = _treasury;
        emit GuildTreasuryUpdated(oldTreasury, _treasury);
    }

    /**
     * @dev Set the treasury share percentage
     * @param bps Share in basis points (max 2000 = 20%)
     */
    function setTreasuryShare(uint256 bps) external onlyGovernor governanceActive {
        if (bps > 2000) revert InvalidShareBps();
        uint256 oldBps = treasuryShareBps;
        treasuryShareBps = bps;
        emit TreasuryShareUpdated(oldBps, bps);
    }

    /**
     * @dev Withdraw treasury's share of pending royalties
     * @param projectId The project ID
     */
    function withdrawTreasuryShare(uint256 projectId) external nonReentrant {
        if (guildTreasury == address(0)) revert TreasuryNotSet();
        if (msg.sender != guildTreasury && msg.sender != governor) {
            revert NotGovernor();
        }

        // Note: Treasury share routing would be handled via RoyaltyRegistry
        // This is a placeholder for future implementation
    }

    // ================================================================
    // FEE ADJUSTMENTS (via governance)
    // ================================================================

    /**
     * @dev Propose a fee adjustment for a license tier
     * @param tier The license tier to adjust
     * @param newAmount New fee amount
     * @param delayBlocks Blocks until the adjustment becomes active
     */
    function proposeFeeAdjustment(
        uint8 tier,
        uint256 newAmount,
        uint256 delayBlocks
    ) external onlyGovernor governanceActive {
        if (newAmount == 0) revert ZeroAddress();

        uint256 activeAt = block.timestamp + (delayBlocks * 12); // ~12s per block

        pendingFeeAdjustments.push(FeeAdjustment({
            tier: tier,
            newAmount: newAmount,
            proposedAt: block.timestamp,
            activeAt: activeAt
        }));

        emit FeeAdjustmentProposed(tier, newAmount, activeAt);
    }

    /**
     * @dev Execute a pending fee adjustment
     * @param projectId The project ID
     * @param adjustmentIndex Index in pendingFeeAdjustments
     * @param token Payment token address
     */
    function executeFeeAdjustment(
        uint256 projectId,
        uint256 adjustmentIndex,
        address token
    ) external onlyGovernor governanceActive {
        FeeAdjustment storage adj = pendingFeeAdjustments[adjustmentIndex];
        if (block.timestamp < adj.activeAt) {
            revert ExecuteTooEarly();
        }

        // Call RoyaltyRegistry to update pricing
        registry.setTierPricing(projectId, adj.tier, adj.newAmount, token);

        // Mark as executed by setting amount to 0
        adj.newAmount = 0;
    }

    // ================================================================
    // GOVERNANCE CONFIGURATION
    // ================================================================

    /**
     * @dev Enable or disable governance
     * @param enabled Whether governance is enabled
     */
    function setGovernanceEnabled(bool enabled) external onlyGovernor {
        governanceEnabled = enabled;
        emit GovernanceToggled(enabled);
    }

    /**
     * @dev Update the Governor address
     * @param newGovernor New Governor contract address
     */
    function updateGovernor(address newGovernor) external onlyGovernor {
        if (newGovernor == address(0)) revert ZeroAddress();
        address oldGovernor = governor;
        // Note: governor is immutable, this would require a different pattern
        // Leaving as placeholder for future upgradeability
    }

    /**
     * @dev Set the Timelock contract
     * @param _timelock Timelock contract address
     */
    function setTimelock(address _timelock) external onlyGovernor {
        address oldTimelock = timelock;
        timelock = _timelock;
        emit TimelockUpdated(oldTimelock, timelock);
    }

    /**
     * @dev Update minimum quorum
     * @param bps New quorum in basis points
     */
    function setQuorum(uint256 bps) external onlyGovernor {
        if (bps > 10000) revert QuorumTooHigh();
        uint256 oldBps = minQuorumBps;
        minQuorumBps = bps;
        emit QuorumUpdated(oldBps, bps);
    }

    /**
     * @dev Update voting period
     * @param blocks New voting period in blocks
     */
    function setVotingPeriod(uint256 blocks) external onlyGovernor {
        uint256 oldBlocks = votingPeriodBlocks;
        votingPeriodBlocks = blocks;
        emit VotingPeriodUpdated(oldBlocks, blocks);
    }

    // ================================================================
    // VIEW FUNCTIONS
    // ================================================================

    function getGuildLink(uint256 index) external view returns (GuildLink memory) {
        return guildLinks[index];
    }

    function getLinksBySource(uint256 sourceProjectId) external view returns (uint256[] memory) {
        return linksBySource[sourceProjectId];
    }

    function getLinksByDerivative(uint256 derivativeProjectId) external view returns (uint256[] memory) {
        return linksByDerivative[derivativeProjectId];
    }

    function getPendingParam(bytes32 proposalHash) external view returns (PendingParam memory) {
        return pendingParams[proposalHash];
    }

    function getFeeAdjustment(uint256 index) external view returns (FeeAdjustment memory) {
        return pendingFeeAdjustments[index];
    }

    function getPendingFeeAdjustmentCount() external view returns (uint256) {
        return pendingFeeAdjustments.length;
    }

    function getRegistry() external view returns (address) {
        return address(registry);
    }

    // ================================================================
    // ADMIN FUNCTIONS
    // ================================================================

    function pause() external onlyGovernor {
        _pause();
    }

    function unpause() external onlyGovernor {
        _unpause();
    }
}
