// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IRoyaltyRegistry.sol";
import "../interfaces/IPaymentLedger.sol";

/**
 * @title RoyaltyRegistry
 * @dev Core royalty collection and contributor distribution contract for
 *      Open-Pact (OPL-1.1) licensed projects. Receives payments (native or ERC20)
 *      from commercial/AI usage and distributes them to registered contributors
 *      according to weighted shares.
 *
 *      Integrates with x402 payment flows via x402-compatible facilitators
 *      (PaymentVerifier) and records all royalty events in PaymentLedger.
 *
 *      Usage:
 *      1. Project owner registers the project (content hash + metadata URI)
 *      2. Owner adds contributors with weight allocations
 *      3. Commercial users pay royalties for usage licenses
 *      4. Royalties are batched and distributed to contributors
 *
 *      Pricing model: Per-OPL-1.1 Section 3.2, pricing is NOT fixed by the
 *      license text. Maintainers define fees dynamically via the Project
 *      Registry or this contract's Custom pricing mode.
 */
contract RoyaltyRegistry is IRoyaltyRegistry, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // ============ Enums ============

    enum PricingMode {
        Structured,
        RevenueShare,
        Custom
    }

    enum LicenseTier {
        Tier1_Individual,
        Tier2_Team,
        Tier3_Organization,
        Tier4_LargeOrg,
        AI_Training
    }

    enum LicenseStatus {
        None,
        Active,
        Expired,
        Revoked
    }

    // ============ Internal Structs ============

    struct InternalProject {
        string name;
        bytes32 contentHash;
        string metadataURI;
        address licenseSteward;
        PricingMode pricingMode;
        bytes32 registryCertificationHash; // ENS/DID hash proving canonical registry identity (per OPL-1.1 §3.2.1)
        uint256 feeScheduleVersion;       // Monotonically increasing version counter for temporal tracking
        bool exists;
    }

    struct InternalContributor {
        address wallet;
        string identifier;
        uint96 weight;
        uint96 reputation;
        bool active;
    }

    struct InternalLicense {
        address licensee;
        LicenseTier tier;
        LicenseStatus status;
        uint256 paidAmount;
        uint256 paidAt;
        uint256 expiresAt;
        bytes32 metadataHash;
        string licenseVersion;         // OPL version string (e.g., "1.1") referenced in this License Record
        uint256 totalWorkforce;        // Per OPL-1.1 §1.5, snapshot at time of registration
        uint256 feeScheduleVersionAtPurchase; // Fee schedule version at time of payment (per §3.2.3)
    }

    struct TierPricing {
        uint256 amount;
        address token;            // Payment token (address(0) for native ETH/FLR)
        bool enabled;
    }

    // ============ State ============

    uint256 private _projectCount;
    mapping(uint256 => InternalProject) private _projects;
    mapping(bytes32 => uint256) private _projectIdByContentHash;

    // Project -> contributors (projectID -> contributorIndex -> Contributor)
    mapping(uint256 => InternalContributor[]) private _contributors;
    mapping(uint256 => uint96) private _totalWeight;

    // Project -> license (projectID -> licensee address -> License)
    mapping(uint256 => mapping(address => InternalLicense)) private _licenses;
    mapping(uint256 => uint256) private _activeLicenseCount;

    // Tier pricing (projectId -> tier -> TierPricing)
    mapping(uint256 => mapping(LicenseTier => TierPricing)) private _tierPricing;

    // Pending withdrawals (contributorWallet -> projectId -> amount)
    mapping(address => mapping(uint256 => uint256)) private _pendingWithdrawals;
    mapping(address => uint256[]) private _contributorProjects;

    // Payment ledger integration
    IPaymentLedger public immutable paymentLedger;
    address public paymentVerifier;

    // Royalty collection totals
    mapping(uint256 => uint256) private _totalRoyaltiesCollected;
    mapping(uint256 => mapping(address => uint256)) private _totalRoyaltiesByToken;

    // Authorized fee recipients (for multi-signature scenarios)
    mapping(address => bool) private _authorizedRecipients;

    // Total Workforce tracking for tier-crossing detection (OPL-1.1 Section 1.5)
    mapping(address => uint256) private _lastDeclaredWorkforce;

    // Canonical registry identifier (ENS/DID) for this project's Project Registry (per OPL-1.1 §3.2.1)
    string private _registryIdentifier;

    // Fee changes require advance notice period (per OPL-1.1 §3.2.3).
    // Existing payments at old rates remain valid; new payments after effectiveDate use new rates.
    uint256 public constant FEE_CHANGE_NOTICE_PERIOD = 7 days;

    // Track when fee changes become effective (projectId -> effectiveTimestamp)
    mapping(uint256 => uint256) private _feeChangeEffectiveAt;

    // Map from (projectId -> effectiveFeeVersion -> TierPricing snapshot)
    // Preserves historical pricing for dispute resolution
    mapping(uint256 => mapping(uint256 => mapping(uint8 => uint256))) private _feeVersionSnapshots;

    // SaaS Revenue Reporting (per OPL-1.1 §1.14 — Royalties include hosted/managed service revenue)
    struct RevenueReport {
        uint256 reportedGrossRevenue;
        uint256 reportedInfrastructure;
        uint256 reportedNetRevenue;
        uint256 sharePercentage;
        uint256 amountOwed;
        uint256 amountPaid;
        bytes32 evidenceHash;
        uint256 reportedAt;
        bool isPaidInFull;
    }
    mapping(uint256 => mapping(address => RevenueReport[])) private _revenueReports;

    // AI Training Disclosure (per OPL-1.1 §4.3)
    struct AITrainingDisclosure {
        string softwareName;          // §4.3(a)(i): Name of the Software
        string commitHash;            // §4.3(a)(ii): Version or commit hash used
        string repositoryURL;         // §4.3(a)(iii): Link to the Software's repo
        string modelCardURI;          // URI to the model card containing the disclosure
        bool downstreamNotified;      // §4.3(b): Whether downstream users are notified
        bool competingProductDeclared; // §4.3(c): Licensee declares NOT creating competing product
        bytes32 disclosureHash;       // keccak256 of all disclosure fields for integrity
        uint256 disclosedAt;
    }
    mapping(uint256 => mapping(address => AITrainingDisclosure)) private _aiDisclosures;

    // View-only struct for complete License Record (per OPL-1.1 §1.20)
    struct CompleteLicenseRecord {
        address licensee;
        string tierName;
        LicenseStatus status;
        uint256 paidAmount;
        uint256 paidAt;
        uint256 expiresAt;
        bytes32 metadataHash;
        string licenseVersion;
        uint256 totalWorkforce;
        uint256 feeScheduleVersionAtPurchase;
    }

    // Errors
    error ProjectExists(uint256 projectId);
    error ProjectNotFound(uint256 projectId);
    error ZeroAddress();
    error ZeroAmount();
    error InvalidName();
    error InvalidWeight();
    error WeightOverflow();
    error ContributorNotFound(uint256 projectId, uint256 contributorIndex);
    error ContributorAlreadyExists(uint256 projectId, address wallet);
    error LicenseAlreadyActive(address licensee);
    error NoActiveLicense(address licensee);
    error LicenseExpired(address licensee);
    error InvalidPricingMode();
    error PaymentTokenNotSupported(address token);
    error TierNotPriced(LicenseTier tier);
    error NotAuthorized(address caller);
    error NothingToWithdraw();
    error MetadataHashMismatch(bytes32 expected, bytes32 actual);
    error InvalidTier();
    error DuplicateProjectContent();
    error WrongPaymentAmount(uint256 sent, uint256 required);

    // Events
    event ProjectRegistered(
        uint256 indexed projectId,
        string name,
        bytes32 contentHash,
        address indexed licenseSteward
    );
    event ContributorAdded(
        uint256 indexed projectId,
        address indexed wallet,
        string identifier,
        uint96 weight
    );
    event ContributorRemoved(
        uint256 indexed projectId,
        address indexed wallet
    );
    event ContributorWeightUpdated(
        uint256 indexed projectId,
        address indexed wallet,
        uint96 oldWeight,
        uint96 newWeight
    );
    event LicenseIssued(
        uint256 indexed projectId,
        address indexed licensee,
        LicenseTier tier,
        address token,
        uint256 amount,
        uint256 expiresAt
    );
    event LicenseRenewed(
        uint256 indexed projectId,
        address indexed licensee,
        uint256 newExpiresAt
    );
    event LicenseRevoked(
        uint256 indexed projectId,
        address indexed licensee
    );
    event RoyaltyCollected(
        uint256 indexed projectId,
        address indexed payer,
        address token,
        uint256 amount,
        LicenseTier tier
    );
    event RoyaltyDistributed(
        uint256 indexed projectId,
        address indexed contributor,
        address token,
        uint256 amount
    );
    event RoyaltyWithdrawn(
        address indexed contributor,
        uint256 indexed projectId,
        address token,
        uint256 amount
    );
    event TierPricingUpdated(
        uint256 indexed projectId,
        LicenseTier tier,
        uint256 amount,
        address token
    );
    event PricingModeChanged(
        uint256 indexed projectId,
        PricingMode oldMode,
        PricingMode newMode
    );
    event PaymentVerifierUpdated(address indexed verifier);
    event RegistryIdentifierSet(string indexed identifier);
    event RegistryCertified(uint256 indexed projectId, bytes32 indexed certificationHash);
    event FeeScheduleVersionChanged(uint256 indexed projectId, uint256 newVersion, uint256 effectiveAt);
    event RevenueReported(
        uint256 indexed projectId,
        address indexed licensee,
        uint256 grossRevenue,
        uint256 netRevenue,
        uint256 amountOwed,
        uint256 stewardShareBps,
        uint256 reportedAt
    );
    event RevenueSharePayment(
        uint256 indexed projectId,
        address indexed payer,
        uint256 reportIndex,
        uint256 amount,
        uint256 remaining
    );
    event AITrainingDisclosureSubmitted(
        uint256 indexed projectId,
        address indexed licensee,
        string softwareName,
        string commitHash,
        string modelCardURI,
        bool notCompetingProduct,
        uint256 disclosedAt
    );

    event WorkforceUpdated(
        address indexed licensee,
        uint256 oldWorkforce,
        uint256 newWorkforce,
        bool crossedTierBoundary
    );
    modifier projectExists(uint256 projectId) {
        if (!_projects[projectId].exists) {
            revert ProjectNotFound(projectId);
        }
        _;
    }

    modifier onlyProjectMaintainer(uint256 projectId) {
        if (_projects[projectId].licenseSteward != msg.sender && msg.sender != owner()) {
            revert NotAuthorized(msg.sender);
        }
        _;
    }

    constructor(address _paymentLedger) Ownable() {
        if (_paymentLedger == address(0)) {
            revert ZeroAddress();
        }
        paymentLedger = IPaymentLedger(_paymentLedger);
        _authorizedRecipients[msg.sender] = true;
    }

    // ================================================================
    // PROJECT REGISTRATION
    // ================================================================

    /**
     * @dev Register a new project for royalty collection
     * @param name Human-readable project name
     * @param contentHash Cryptographic hash of project source (git commit hash, IPFS hash)
     * @param metadataURI URI to project metadata, documentation, or license text
     * @param initialPricingToken Token for tier pricing (address(0) for native)
     */
    function registerProject(
        string calldata name,
        bytes32 contentHash,
        string calldata metadataURI,
        address initialPricingToken
    ) external returns (uint256 projectId) {
        if (bytes(name).length == 0) {
            revert InvalidName();
        }
        if (contentHash == bytes32(0)) {
            revert ZeroAddress();
        }
        if (_projectIdByContentHash[contentHash] != 0) {
            revert DuplicateProjectContent();
        }

        projectId = _projectCount;

        _projects[projectId] = InternalProject({
            name: name,
            contentHash: contentHash,
            metadataURI: metadataURI,
            licenseSteward: msg.sender,
            pricingMode: PricingMode.Structured,
            registryCertificationHash: bytes32(0), // Set separately via setRegistryIdentifier
            feeScheduleVersion: 1,                 // Initial fee schedule version
            exists: true
        });

        _projectIdByContentHash[contentHash] = projectId;
        _projectCount++;

        // Set default tier pricing if token provided
        if (initialPricingToken != address(0)) {
            setRecommendedPricing(projectId, initialPricingToken);
        }

        emit ProjectRegistered(projectId, name, contentHash, msg.sender);
    }

    /**
     * @dev Verify a project by its content hash and get ID
     * @param contentHash Hash to look up
     * @return projectId Registered project ID
     * @return exists Whether a project with this hash exists
     */
    function getProjectIdByHash(bytes32 contentHash) external view returns (uint256 projectId, bool exists) {
        projectId = _projectIdByContentHash[contentHash];
        exists = _projects[projectId].exists;
    }

    // ================================================================
    // CANONICAL REGISTRY IDENTITY (OPL-1.1 §3.2.1)
    // ================================================================

    /**
     * @dev Set the canonical Project Registry identifier for this contract.
     *      This should be an ENS name, DID, or other verifiable identifier
     *      that proves THIS contract is THE authoritative registry for the
     *      Software. Prevents registry spoofing attacks.
     * @param identifier Registry identifier string (e.g., ENS name, DID, contract address)
     */
    function setRegistryIdentifier(string calldata identifier) external {
        if (bytes(identifier).length == 0) {
            revert InvalidName();
        }
        _registryIdentifier = identifier;
        emit RegistryIdentifierSet(identifier);
    }

    /**
     * @dev Returns the canonical registry identifier for this deployment.
     */
    function getRegistryIdentifier() external view returns (string memory) {
        return _registryIdentifier;
    }

    /**
     * @dev Set the registry certification hash (ENS/DID proof) for a specific project.
     *      This hashes the canonical identifier to the project, linking them on-chain.
     * @param projectId Project ID
     * @param certificationHash Hash of the canonical registry identifier
     */
    function setRegistryCertification(
        uint256 projectId,
        bytes32 certificationHash
    ) external onlyProjectMaintainer(projectId) projectExists(projectId) {
        if (certificationHash == bytes32(0)) {
            revert InvalidName();
        }
        _projects[projectId].registryCertificationHash = certificationHash;
        emit RegistryCertified(projectId, certificationHash);
    }

    // ================================================================
    // TEMPORAL FEE TRACKING (OPL-1.1 §3.2.3)
    // ================================================================
    // Payments are frictionless/per-request via x402 (no billing cycles).
    // Fee changes apply prospectively with advance notice. The effective
    // date is set and any payment processed after that date uses the new rate.
    // Existing License Records (annual/multi-year) remain at their paid rate
    // until their expiresAt; they are NOT repriced retroactively.

    /**
     * @dev Stage a fee schedule version change with an effective future date.
     *      Per §3.2.3: fee changes apply prospectively, not retroactively.
     *      The change must be announced at least FEE_CHANGE_NOTICE_PERIOD in
     *      advance so licensees can decide whether to continue at the new rate.
     * @param projectId Project ID
     */
    function advanceFeeScheduleVersion(uint256 projectId)
        external
        onlyProjectMaintainer(projectId)
        projectExists(projectId)
    {
        uint256 currentVersion = _projects[projectId].feeScheduleVersion;

        // Snapshot current tier pricing against this version for auditability
        LicenseTier[5] memory allTiers = [
            LicenseTier.Tier1_Individual,
            LicenseTier.Tier2_Team,
            LicenseTier.Tier3_Organization,
            LicenseTier.Tier4_LargeOrg,
            LicenseTier.AI_Training
        ];
        for (uint8 i = 0; i < 5; i++) {
            _feeVersionSnapshots[projectId][currentVersion][i] =
                _tierPricing[projectId][allTiers[i]].amount;
        }

        _projects[projectId].feeScheduleVersion = currentVersion + 1;
        _feeChangeEffectiveAt[projectId] = block.timestamp + FEE_CHANGE_NOTICE_PERIOD;

        emit FeeScheduleVersionChanged(
            projectId,
            currentVersion + 1,
            block.timestamp + FEE_CHANGE_NOTICE_PERIOD  // effective date, 7 days from now
        );
    }

    /**
     * @dev Check if a fee schedule version change is currently in its notice period.
     *      Returns (isInNoticePeriod, effectiveDate).
     */
    function getFeeScheduleStatus(uint256 projectId)
        external
        view
        returns (bool isInNoticePeriod, uint256 effectiveAt)
    {
        effectiveAt = _feeChangeEffectiveAt[projectId];
        isInNoticePeriod = effectiveAt > block.timestamp;
    }

    /**
     * @dev Get the effective fee change date for a project.
     */
    function getFeeChangeEffectiveAt(uint256 projectId) external view returns (uint256) {
        return _feeChangeEffectiveAt[projectId];
    }

    /**
     * @dev Get historical fee snapshot for a given version and tier.
     *      Used for dispute resolution: proves what the rate WAS at the time
     *      a licensee registered (per §3.2.3).
     */
    function getFeeVersionSnapshot(
        uint256 projectId,
        uint256 feeVersion,
        uint8 tier
    ) external view returns (uint256) {
        return _feeVersionSnapshots[projectId][feeVersion][tier];
    }

    /**
     * @dev Get the current fee schedule version for a project.
     */
    function getFeeScheduleVersion(uint256 projectId) external view returns (uint256) {
        return _projects[projectId].feeScheduleVersion;
    }

    // ================================================================
    // CONTRIBUTOR MANAGEMENT
    // ================================================================

    /**
     * @dev Add a contributor to a project with weight allocation
     * @param projectId Project ID
     * @param wallet Contributor wallet address
     * @param identifier Human-readable identifier (GitHub username, ENS, etc.)
     * @param weight Distribution weight in basis points (1-10000)
     */
    function addContributor(
        uint256 projectId,
        address wallet,
        string calldata identifier,
        uint96 weight
    ) external onlyProjectMaintainer(projectId) projectExists(projectId) {
        if (wallet == address(0)) {
            revert ZeroAddress();
        }
        if (weight == 0) {
            revert InvalidWeight();
        }

        // Check for duplicate contributor
        uint256 len = _contributors[projectId].length;
        for (uint256 i = 0; i < len; i++) {
            if (_contributors[projectId][i].wallet == wallet) {
                revert ContributorAlreadyExists(projectId, wallet);
            }
        }

        uint256 newTotal = uint256(_totalWeight[projectId]) + weight;
        if (newTotal > 10000) {
            revert WeightOverflow();
        }

        _contributors[projectId].push(InternalContributor({
            wallet: wallet,
            identifier: identifier,
            weight: weight,
            reputation: 0,
            active: true
        }));

        _totalWeight[projectId] = uint96(newTotal);

        // Track projects for this contributor
        _contributorProjects[wallet].push(projectId);

        emit ContributorAdded(projectId, wallet, identifier, weight);
    }

    /**
     * @dev Remove a contributor (set inactive, preserve weight for historical accuracy)
     * @param projectId Project ID
     * @param contributorIndex Index in contributors array
     */
    function removeContributor(
        uint256 projectId,
        uint256 contributorIndex
    ) external onlyProjectMaintainer(projectId) projectExists(projectId) {
        if (contributorIndex >= _contributors[projectId].length) {
            revert ContributorNotFound(projectId, contributorIndex);
        }

        InternalContributor storage c = _contributors[projectId][contributorIndex];
        c.active = false;
        _totalWeight[projectId] -= c.weight;

        emit ContributorRemoved(projectId, c.wallet);
    }

    /**
     * @dev Update a contributor's weight allocation
     * @param projectId Project ID
     * @param contributorIndex Index in contributors array
     * @param newWeight New weight in basis points
     */
    function updateContributorWeight(
        uint256 projectId,
        uint256 contributorIndex,
        uint96 newWeight
    ) external onlyProjectMaintainer(projectId) projectExists(projectId) {
        if (contributorIndex >= _contributors[projectId].length) {
            revert ContributorNotFound(projectId, contributorIndex);
        }
        if (newWeight == 0) {
            revert InvalidWeight();
        }

        InternalContributor storage c = _contributors[projectId][contributorIndex];
        uint96 oldWeight = c.weight;

        uint256 newTotal = uint256(_totalWeight[projectId]) - oldWeight + newWeight;
        if (newTotal > 10000) {
            revert WeightOverflow();
        }

        c.weight = newWeight;
        _totalWeight[projectId] = uint96(newTotal);

        emit ContributorWeightUpdated(projectId, c.wallet, oldWeight, newWeight);
    }

    // ================================================================
    // TIER PRICING CONFIGURATION
    // ================================================================

    /**
     * @dev Set pricing for a specific license tier
     * @param projectId Project ID
     * @param tier License tier
     * @param amount Payment amount
     * @param token Payment token (address(0) for native ETH/FLR)
     */
    function setTierPricing(
        uint256 projectId,
        uint8 tier,
        uint256 amount,
        address token
    ) external onlyProjectMaintainer(projectId) projectExists(projectId) {
        if (tier > uint8(LicenseTier.AI_Training)) {
            revert InvalidTier();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        _tierPricing[projectId][LicenseTier(tier)] = TierPricing({
            amount: amount,
            token: token,
            enabled: true
        });

        emit TierPricingUpdated(projectId, LicenseTier(tier), amount, token);
    }

    /**
     * @dev Disable a tier's pricing (cannot purchase this tier)
     * @param projectId Project ID
     * @param tier License tier
     */
    function disableTier(
        uint256 projectId,
        uint8 tier
    ) external onlyProjectMaintainer(projectId) {
        _tierPricing[projectId][LicenseTier(tier)].enabled = false;
    }

    /**
     * @dev Change the project's pricing mode
     * @param projectId Project ID
     * @param mode New pricing mode
     */
    function setPricingMode(
        uint256 projectId,
        uint8 mode
    ) external onlyProjectMaintainer(projectId) projectExists(projectId) {
        PricingMode oldMode = _projects[projectId].pricingMode;
        _projects[projectId].pricingMode = PricingMode(mode);
        emit PricingModeChanged(projectId, oldMode, PricingMode(mode));
    }

    // ================================================================
    // ================================================================
    // WORKFORCE TRACKING (OPL-1.1 Section 1.5)
    // Licensees update workforce; tier boundary crossings are tracked
    // ================================================================

    /**
     * @dev Update the declaring Total Workforce for this address.
     *      Per Section 1.5, workforce determines tier eligibility.
     * @param workforceSize New Total Workforce count
     */
    function updateWorkforce(uint256 workforceSize) external {
        uint256 oldWorkforce = _lastDeclaredWorkforce[msg.sender];
        _lastDeclaredWorkforce[msg.sender] = workforceSize;

        // Check if tier boundary was crossed (<100 vs >=100)
        bool oldSmall = oldWorkforce < 100;
        bool newSmall = workforceSize < 100;
        bool crossedBoundary = (oldSmall != newSmall);

        emit WorkforceUpdated(msg.sender, oldWorkforce, workforceSize, crossedBoundary);
    }

    /**
     * @dev Get the last declared workforce for an address
     */
    function getWorkforce(address licensee) external view returns (uint256) {
        return _lastDeclaredWorkforce[licensee];
    }

    // AI TRAINING DISCLOSURE (OPL-1.1 §4.3)
    // Required for AI_Training tier licensees
    // ================================================================

    /**
     * @dev Submit AI Training disclosure per Section 4.3.
     *      Required for any Licensee holding an AI Training license.
     *
     * @param projectId Project ID
     * @param softwareName Name of the OPL Software used in training (Section 4.3(a)(i))
     * @param commitHash Version or commit hash used (Section 4.3(a)(ii))
     * @param repositoryURL Link to the Software repository (Section 4.3(a)(iii))
     * @param modelCardURI URI to the model card where disclosure is published
     * @param downstreamNotified Whether downstream/users are notified of licensing conditions
     * @param notCompetingProduct Declaration that this is NOT a competing product per Section 4.3(c)
     */
    function submitAITrainingDisclosure(
        uint256 projectId,
        string calldata softwareName,
        string calldata commitHash,
        string calldata repositoryURL,
        string calldata modelCardURI,
        bool downstreamNotified,
        bool notCompetingProduct
    ) external projectExists(projectId) {
        if (bytes(softwareName).length == 0 || bytes(commitHash).length == 0) {
            revert InvalidName();
        }

        bytes32 disclosureHash = keccak256(abi.encodePacked(
            softwareName, commitHash, repositoryURL, modelCardURI, msg.sender
        ));

        _aiDisclosures[projectId][msg.sender] = AITrainingDisclosure({
            softwareName: softwareName,
            commitHash: commitHash,
            repositoryURL: repositoryURL,
            modelCardURI: modelCardURI,
            downstreamNotified: downstreamNotified,
            competingProductDeclared: notCompetingProduct,
            disclosureHash: disclosureHash,
            disclosedAt: block.timestamp
        });

        emit AITrainingDisclosureSubmitted(
            projectId,
            msg.sender,
            softwareName,
            commitHash,
            modelCardURI,
            notCompetingProduct,
            block.timestamp
        );
    }

    /**
     * @dev View function to get the AI Training disclosure for a licensee
     */
    function getAITrainingDisclosure(uint256 projectId, address licensee)
        external
        view
        returns (
            string memory softwareName,
            string memory commitHash,
            string memory repositoryURL,
            string memory modelCardURI,
            bool downstreamNotified,
            bool competingProductDeclared,
            bytes32 disclosureHash,
            uint256 disclosedAt
        )
    {
        AITrainingDisclosure storage d = _aiDisclosures[projectId][licensee];
        return (
            d.softwareName,
            d.commitHash,
            d.repositoryURL,
            d.modelCardURI,
            d.downstreamNotified,
            d.competingProductDeclared,
            d.disclosureHash,
            d.disclosedAt
        );
    }

    /**
     * @dev Check if an AI Training disclosure exists for a licensee
     */
    function hasAITrainingDisclosure(uint256 projectId, address licensee)
        external
        view
        returns (bool)
    {
        AITrainingDisclosure storage d = _aiDisclosures[projectId][licensee];
        return d.disclosedAt > 0;
    }

    // ================================================================
    // SAAS REVENUE REPORTING (OPL-1.1 §1.14, §5.2)
    // Royalties include net revenue from hosted/managed services
    // ================================================================

    /**
     * @dev Report SaaS/managed service revenue for a project that uses OPL code.
     *      Per Section 1.14, \"Royalties\" include net revenue from hosted services.
     *      Per Section 5.2, the Steward receives 10%-50% of Derivative Work revenues.
     *
     * @param projectId Project ID
     * @param grossRevenue Gross revenue attributable to the OPL-integrated service
     * @param infrastructureCost Deductible infrastructure costs (hosting, bandwidth, etc.)
     * @param stewardShareBps Steward's share in basis points (Registry-defined)
     * @param evidenceHash keccak256 hash of supporting documentation/audit
     */
    function reportSaaSRevenue(
        uint256 projectId,
        uint256 grossRevenue,
        uint256 infrastructureCost,
        uint256 stewardShareBps,
        bytes32 evidenceHash
    ) external projectExists(projectId) nonReentrant {
        if (grossRevenue == 0) {
            revert ZeroAmount();
        }

        uint256 netRevenue = grossRevenue > infrastructureCost
            ? grossRevenue - infrastructureCost
            : 0;
        uint256 amountOwed = (netRevenue * stewardShareBps) / 10000;

        _revenueReports[projectId][msg.sender].push(RevenueReport({
            reportedGrossRevenue: grossRevenue,
            reportedInfrastructure: infrastructureCost,
            reportedNetRevenue: netRevenue,
            sharePercentage: stewardShareBps,
            amountOwed: amountOwed,
            amountPaid: 0,
            evidenceHash: evidenceHash,
            reportedAt: block.timestamp,
            isPaidInFull: false
        }));

        emit RevenueReported(
            projectId,
            msg.sender,
            grossRevenue,
            netRevenue,
            amountOwed,
            stewardShareBps,
            block.timestamp
        );
    }

    /**
     * @dev Pay revenue share owed from a SaaS revenue report.
     * @param projectId Project ID
     * @param reportIndex Index of the revenue report to pay against
     */
    function payRevenueShare(uint256 projectId, uint256 reportIndex)
        external
        payable
        projectExists(projectId)
        nonReentrant
    {
        RevenueReport storage report = _revenueReports[projectId][msg.sender][reportIndex];
        if (report.reportedAt == 0) {
            revert ZeroAmount(); // No report at this index
        }
        uint256 remaining = report.amountOwed - report.amountPaid;
        if (remaining == 0) {
            revert NothingToWithdraw();
        }
        uint256 payment = msg.value < remaining ? msg.value : remaining;
        report.amountPaid += payment;
        if (report.amountPaid >= report.amountOwed) {
            report.isPaidInFull = true;
        }

        // Distribute to contributors
        _distributeRoyalty(projectId, payment, address(0));

        emit RevenueSharePayment(
            projectId,
            msg.sender,
            reportIndex,
            payment,
            report.amountOwed - report.amountPaid
        );
    }

    /**
     * @dev Get all revenue reports for a licensee on a project
     */
    function getRevenueReports(uint256 projectId, address licensee)
        external
        view
        returns (RevenueReport[] memory)
    {
        return _revenueReports[projectId][licensee];
    }

    /**
     * @dev Get a specific revenue report
     */
    function getRevenueReport(uint256 projectId, address licensee, uint256 index)
        external
        view
        returns (ViewRevenueReport memory)
    {
        RevenueReport storage r = _revenueReports[projectId][licensee][index];
        return ViewRevenueReport({
            reportedGrossRevenue: r.reportedGrossRevenue,
            reportedInfrastructure: r.reportedInfrastructure,
            reportedNetRevenue: r.reportedNetRevenue,
            sharePercentage: r.sharePercentage,
            amountOwed: r.amountOwed,
            amountPaid: r.amountPaid,
            evidenceHash: r.evidenceHash,
            reportedAt: r.reportedAt,
            isPaidInFull: r.isPaidInFull
        });
    }

    // ================================================================
    // LICENSE ISSUANCE & PAYMENT
    // ================================================================

    /**
     * @dev Purchase a license for a specific tier (native token payment)
     * @param projectId Project ID
     * @param licensee Licensee address (who will be using the code)
     * @param tier License tier
     * @param metadataHash Hash of license terms acknowledgment
     */
    function purchaseLicense(
        uint256 projectId,
        address licensee,
        uint8 tier,
        bytes32 metadataHash
    ) external payable projectExists(projectId) nonReentrant whenNotPaused {
        _purchaseLicenseInternal(projectId, licensee, tier, metadataHash, address(0));
        // Set defaults for the new metadata fields (use the extended function for full data)
        InternalLicense storage l = _licenses[projectId][licensee];
        l.feeScheduleVersionAtPurchase = _projects[projectId].feeScheduleVersion;
    }

    /**
     * @dev Purchase a license with full metadata (licenseVersion + totalWorkforce).
     *      This is the PRIMARY purchase path that populates the complete License Record
     *      per OPL-1.1 §1.20. The metadataHash parameter should be computed from
     *      the licensee's acknowledgment data for verification.
     * @param projectId Project ID
     * @param licensee Licensee address (who will be using the code)
     * @param tier License tier
     * @param metadataHash Hash of license terms acknowledgment
     * @param licenseVersion OPL version string (e.g., "1.1") per §12.2
     * @param totalWorkforce Licensee's Total Workforce per §1.5
     */
    function purchaseLicenseWithMetadata(
        uint256 projectId,
        address licensee,
        uint8 tier,
        bytes32 metadataHash,
        string calldata licenseVersion,
        uint256 totalWorkforce
    ) external payable projectExists(projectId) nonReentrant whenNotPaused {
        _purchaseLicenseInternal(projectId, licensee, tier, metadataHash, address(0));
        InternalLicense storage l = _licenses[projectId][licensee];
        l.licenseVersion = licenseVersion;
        l.totalWorkforce = totalWorkforce;
        l.feeScheduleVersionAtPurchase = _projects[projectId].feeScheduleVersion;
    }

    /**
     * @dev Purchase a license with full metadata via ERC20 token.
     * @param projectId Project ID
     * @param licensee Licensee address
     * @param tier License tier
     * @param metadataHash Hash of license terms acknowledgment
     * @param token ERC20 token address
     * @param licenseVersion OPL version string (e.g., "1.1") per §12.2
     * @param totalWorkforce Licensee's Total Workforce per §1.5
     */
    function purchaseLicenseWithTokenAndMetadata(
        uint256 projectId,
        address licensee,
        uint8 tier,
        bytes32 metadataHash,
        address token,
        string calldata licenseVersion,
        uint256 totalWorkforce
    ) external projectExists(projectId) nonReentrant whenNotPaused {
        if (token == address(0)) {
            revert ZeroAddress();
        }

        TierPricing storage pricing = _tierPricing[projectId][LicenseTier(tier)];
        if (!pricing.enabled) {
            revert TierNotPriced(LicenseTier(tier));
        }
        if (pricing.token != token) {
            revert PaymentTokenNotSupported(token);
        }

        InternalLicense storage existing = _licenses[projectId][licensee];
        if (existing.status == LicenseStatus.Active && existing.expiresAt > block.timestamp) {
            revert LicenseAlreadyActive(licensee);
        }

        uint256 amount = pricing.amount;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        _issueLicenseInternal(projectId, licensee, tier, amount, token, metadataHash);
        InternalLicense storage l = _licenses[projectId][licensee];
        l.licenseVersion = licenseVersion;
        l.totalWorkforce = totalWorkforce;
        l.feeScheduleVersionAtPurchase = _projects[projectId].feeScheduleVersion;
    }

    /**
     * @dev Purchase a license with ERC20 payment
     * @param projectId Project ID
     * @param licensee Licensee address
     * @param tier License tier
     * @param metadataHash Hash of license terms acknowledgment
     * @param token ERC20 token address
     */
    function purchaseLicenseWithToken(
        uint256 projectId,
        address licensee,
        uint8 tier,
        bytes32 metadataHash,
        address token
    ) external projectExists(projectId) nonReentrant whenNotPaused {
        if (token == address(0)) {
            revert ZeroAddress();
        }

        TierPricing storage pricing = _tierPricing[projectId][LicenseTier(tier)];
        if (!pricing.enabled) {
            revert TierNotPriced(LicenseTier(tier));
        }
        if (pricing.token != token) {
            revert PaymentTokenNotSupported(token);
        }

        InternalLicense storage existing = _licenses[projectId][licensee];
        if (existing.status == LicenseStatus.Active && existing.expiresAt > block.timestamp) {
            revert LicenseAlreadyActive(licensee);
        }

        uint256 amount = pricing.amount;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        _issueLicenseInternal(projectId, licensee, tier, amount, token, metadataHash);
    }

    /**
     * @dev Renew an existing license (native token)
     * @param projectId Project ID
     * @param tier License tier to renew
     */
    function renewLicense(
        uint256 projectId,
        uint8 tier
    ) external payable projectExists(projectId) nonReentrant whenNotPaused {
        InternalLicense storage license = _licenses[projectId][msg.sender];
        if (license.status == LicenseStatus.None) {
            revert NoActiveLicense(msg.sender);
        }

        TierPricing storage pricing = _tierPricing[projectId][LicenseTier(tier)];
        if (!pricing.enabled || pricing.token != address(0)) {
            revert TierNotPriced(LicenseTier(tier));
        }

        if (msg.value < pricing.amount) {
            revert WrongPaymentAmount(msg.value, pricing.amount);
        }

        license.paidAmount += msg.value;
        license.paidAt = block.timestamp;
        license.expiresAt = block.timestamp + 365 days;
        if (license.status != LicenseStatus.Active) {
            license.status = LicenseStatus.Active;
            _activeLicenseCount[projectId]++;
        }

        // Distribute to contributors
        _distributeRoyalty(projectId, msg.value, address(0));

        emit LicenseRenewed(projectId, msg.sender, license.expiresAt);
        emit RoyaltyCollected(projectId, msg.sender, address(0), msg.value, LicenseTier(tier));
    }

    /**
     * @dev Revoke a license (License Steward only, e.g., for license violation)
     * @param projectId Project ID
     * @param licensee Licensee to revoke
     */
    function revokeLicense(
        uint256 projectId,
        address licensee
    ) external onlyProjectMaintainer(projectId) projectExists(projectId) {
        InternalLicense storage license = _licenses[projectId][licensee];
        if (license.status == LicenseStatus.None) {
            revert NoActiveLicense(licensee);
        }

        license.status = LicenseStatus.Revoked;
        _activeLicenseCount[projectId]--;

        emit LicenseRevoked(projectId, licensee);
    }

    // ================================================================
    // CONTRIBUTOR WITHDRAWALS
    // ================================================================

    /**
     * @dev Withdraw pending native token royalties
     * @param projectId Project ID
     */
    function withdrawNative(uint256 projectId) external projectExists(projectId) nonReentrant {
        uint256 amount = _pendingWithdrawals[msg.sender][projectId];
        if (amount == 0) {
            revert NothingToWithdraw();
        }

        _pendingWithdrawals[msg.sender][projectId] = 0;

        (bool success, ) = msg.sender.call{value: amount}("");
        if (!success) {
            // Refund on failure
            _pendingWithdrawals[msg.sender][projectId] = amount;
        }

        emit RoyaltyWithdrawn(msg.sender, projectId, address(0), amount);
    }

    /**
     * @dev Withdraw pending ERC20 royalties
     * @param projectId Project ID
     * @param token ERC20 token address
     */
    function withdrawToken(
        uint256 projectId,
        address token
    ) external projectExists(projectId) nonReentrant {
        uint256 amount = _pendingWithdrawals[msg.sender][projectId];
        if (amount == 0) {
            revert NothingToWithdraw();
        }

        _pendingWithdrawals[msg.sender][projectId] = 0;

        IERC20(token).safeTransfer(msg.sender, amount);

        emit RoyaltyWithdrawn(msg.sender, projectId, token, amount);
    }

    /**
     * @dev Batch withdraw from multiple projects
     * @param projectIds Array of project IDs
     */
    function batchWithdrawNative(uint256[] calldata projectIds) external nonReentrant {
        for (uint256 i = 0; i < projectIds.length; i++) {
            uint256 amount = _pendingWithdrawals[msg.sender][projectIds[i]];
            if (amount > 0) {
                _pendingWithdrawals[msg.sender][projectIds[i]] = 0;
                (bool success, ) = msg.sender.call{value: amount}("");
                if (success) {
                    emit RoyaltyWithdrawn(msg.sender, projectIds[i], address(0), amount);
                } else {
                    _pendingWithdrawals[msg.sender][projectIds[i]] = amount;
                }
            }
        }
    }

    // ================================================================
    // PAYMENT VERIFIER INTEGRATION (x402-compatible)
    // ================================================================

    /**
     * @dev Set the authorized payment verifier contract
     * @param verifier PaymentVerifier contract address
     */
    function setPaymentVerifier(address verifier) external onlyOwner {
        if (verifier == address(0)) {
            revert ZeroAddress();
        }
        paymentVerifier = verifier;
        emit PaymentVerifierUpdated(verifier);
    }

    /**
     * @dev Record a royalty payment from x402/PaymentVerifier
     * @param projectId Project ID
     * @param licensee Licensee address
     * @param tier License tier
     * @param amount Payment amount
     * @param token Payment token
     */
    function recordRoyaltyPayment(
        uint256 projectId,
        address licensee,
        uint8 tier,
        uint256 amount,
        address token
    ) external projectExists(projectId) {
        if (msg.sender != paymentVerifier && msg.sender != owner()) {
            revert NotAuthorized(msg.sender);
        }

        _issueLicenseInternal(projectId, licensee, tier, amount, token, bytes32(0));
        emit RoyaltyCollected(projectId, licensee, token, amount, LicenseTier(tier));
    }

    // ================================================================
    // VIEW FUNCTIONS
    // ================================================================

    function getProject(uint256 projectId) external view returns (ViewProject memory) {
        InternalProject storage p = _projects[projectId];
        return ViewProject(p.name, p.contentHash, p.metadataURI, p.licenseSteward, uint8(p.pricingMode), p.exists);
    }

    function getProjectCount() external view returns (uint256) {
        return _projectCount;
    }

    function getContributors(uint256 projectId) external view returns (
        address[] memory wallets,
        string[] memory identifiers,
        uint96[] memory weights,
        uint96[] memory reputations,
        bool[] memory actives
    ) {
        uint256 len = _contributors[projectId].length;
        wallets = new address[](len);
        identifiers = new string[](len);
        weights = new uint96[](len);
        reputations = new uint96[](len);
        actives = new bool[](len);
        for (uint256 i; i < len; i++) {
            InternalContributor storage c = _contributors[projectId][i];
            wallets[i] = c.wallet;
            identifiers[i] = c.identifier;
            weights[i] = c.weight;
            reputations[i] = c.reputation;
            actives[i] = c.active;
        }
    }

    function getContributor(uint256 projectId, uint256 index) external view returns (
        address wallet,
        string memory identifier,
        uint96 weight,
        uint96 reputation,
        bool active
    ) {
        InternalContributor storage c = _contributors[projectId][index];
        return (c.wallet, c.identifier, c.weight, c.reputation, c.active);
    }

    function getContributorCount(uint256 projectId) external view returns (uint256) {
        return _contributors[projectId].length;
    }

    function getTotalWeight(uint256 projectId) external view returns (uint256) {
        return _totalWeight[projectId];
    }

    function getLicense(uint256 projectId, address licensee) external view returns (ViewLicense memory) {
        InternalLicense storage l = _licenses[projectId][licensee];
        return ViewLicense(l.licensee, uint8(l.tier), uint8(l.status), l.paidAmount, l.paidAt, l.expiresAt, l.metadataHash);
    }

    function getTierPricing(uint256 projectId, uint8 tier) external view returns (ViewTierPricing memory) {
        TierPricing storage tp = _tierPricing[projectId][LicenseTier(tier)];
        return ViewTierPricing(tp.amount, tp.token, tp.enabled);
    }

    function getPendingWithdrawal(address contributor, uint256 projectId) external view returns (uint256) {
        return _pendingWithdrawals[contributor][projectId];
    }

    function getContributorProjects(address contributor) external view returns (uint256[] memory) {
        return _contributorProjects[contributor];
    }

    function getTotalRoyaltiesCollected(uint256 projectId) external view returns (uint256) {
        return _totalRoyaltiesCollected[projectId];
    }
    function getActiveLicenseCount(uint256 projectId) external view returns (uint256) {
        return _activeLicenseCount[projectId];
    }

    function isAuthorizedRecipient(address account) external view returns (bool) {
        return _authorizedRecipients[account];
    }

    // ================================================================
    // ADMIN FUNCTIONS
    // ================================================================

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Emergency withdrawal of collected royalties (owner only)
     * @param token Token address (address(0) for native)
     */
    function emergencyWithdraw(address token) external onlyOwner {
        if (token == address(0)) {
            uint256 balance = address(this).balance;
            if (balance > 0) {
                (bool success, ) = msg.sender.call{value: balance}("");
                require(success, "Native withdrawal failed");
            }
        } else {
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                IERC20(token).safeTransfer(msg.sender, balance);
            }
        }
    }

    // ================================================================
    // INTERNAL FUNCTIONS
    // ================================================================

    function _purchaseLicenseInternal(
        uint256 projectId,
        address licensee,
        uint8 tier,
        bytes32 metadataHash,
        address token
    ) internal {
        TierPricing storage pricing = _tierPricing[projectId][LicenseTier(tier)];
        if (!pricing.enabled) {
            revert TierNotPriced(LicenseTier(tier));
        }
        if (pricing.token != token) {
            revert PaymentTokenNotSupported(token);
        }

        InternalLicense storage existing = _licenses[projectId][licensee];
        if (existing.status == LicenseStatus.Active && existing.expiresAt > block.timestamp) {
            revert LicenseAlreadyActive(licensee);
        }

        uint256 requiredAmount = pricing.amount;
        if (token == address(0)) {
            if (msg.value != requiredAmount) {
                revert WrongPaymentAmount(msg.value, requiredAmount);
            }
        }

        _issueLicenseInternal(projectId, licensee, tier, requiredAmount, token, metadataHash);
    }

    function _issueLicenseInternal(
        uint256 projectId,
        address licensee,
        uint8 tier,
        uint256 amount,
        address token,
        bytes32 metadataHash
    ) internal {
        InternalLicense storage license = _licenses[projectId][licensee];
        bool isNew = (license.status == LicenseStatus.None);

        license.licensee = licensee;
        license.tier = LicenseTier(tier);
        license.status = LicenseStatus.Active;
        license.paidAmount = amount;
        license.paidAt = block.timestamp;
        license.expiresAt = block.timestamp + 365 days;
        license.metadataHash = metadataHash;

        // Populate metadata fields if not already set (extended purchase paths override these)
        if (bytes(license.licenseVersion).length == 0) {
            license.licenseVersion = "1.1"; // Default to current OPL version
        }
        if (license.feeScheduleVersionAtPurchase == 0) {
            license.feeScheduleVersionAtPurchase = _projects[projectId].feeScheduleVersion;
        }

        if (isNew) {
            _activeLicenseCount[projectId]++;
        }

        emit LicenseIssued(projectId, licensee, LicenseTier(tier), token, amount, license.expiresAt);

        // Distribute royalties to contributors
        _distributeRoyalty(projectId, amount, token);
    }

    function _distributeRoyalty(
        uint256 projectId,
        uint256 amount,
        address token
    ) internal {
        uint256 totalW = _totalWeight[projectId];
        if (totalW == 0) {
            return; // No contributors yet; funds stay in contract
        }

        uint256 contributorCount = _contributors[projectId].length;
        for (uint256 i = 0; i < contributorCount; i++) {
            InternalContributor storage c = _contributors[projectId][i];
            if (!c.active) continue;

            uint256 share = (amount * c.weight) / totalW;
            _pendingWithdrawals[c.wallet][projectId] += share;

            emit RoyaltyDistributed(projectId, c.wallet, token, share);
        }

        _totalRoyaltiesCollected[projectId] += amount;
        _totalRoyaltiesByToken[projectId][token] += amount;
    }

    /// @notice Sets recommended default tier prices (stablecoin-equivalent, 18 decimals).
    /// @dev This is OPTIONAL and provided purely for convenience. Maintainers SHOULD
    /// override these with values appropriate for their project. Per OPL-1.1 Section 3.2,
    /// pricing is NOT fixed by the license text and is determined dynamically by the Steward.
    /// These values are intentionally modest and should be adjusted for real deployments.
    function setRecommendedPricing(uint256 projectId, address token) internal {
        _tierPricing[projectId][LicenseTier.Tier1_Individual] = TierPricing(100 * 10**18, token, true);
        _tierPricing[projectId][LicenseTier.Tier2_Team] = TierPricing(1000 * 10**18, token, true);
        _tierPricing[projectId][LicenseTier.Tier3_Organization] = TierPricing(10000 * 10**18, token, true);
        _tierPricing[projectId][LicenseTier.Tier4_LargeOrg] = TierPricing(50000 * 10**18, token, true);
        _tierPricing[projectId][LicenseTier.AI_Training] = TierPricing(25000 * 10**18, token, true);
    }

    /**
     * @dev Set custom pricing for the Tier1_Individual (Commercial) tier.
     *      Per OPL-1.1 Section 3.2, Stewards define fees dynamically.
     * @param projectId Project ID
     * @param customPrice Fee amount (in token decimals)
     * @param token Payment token (address(0) for native)
     */
    function setCustomCommercialPrice(
        uint256 projectId,
        uint256 customPrice,
        address token
    ) external onlyProjectMaintainer(projectId) {
        if (customPrice == 0) revert ZeroAmount();
        _tierPricing[projectId][LicenseTier.Tier1_Individual] = TierPricing(customPrice, token, true);
        emit TierPricingUpdated(projectId, LicenseTier.Tier1_Individual, customPrice, token);
    }

    /**
     * @dev Set custom pricing for the AI Training tier (tier 4).
     * @param projectId Project ID
     * @param customPrice Fee amount (in token decimals)
     * @param token Payment token
     */
    function setCustomAITrainingPrice(
        uint256 projectId,
        uint256 customPrice,
        address token
    ) external onlyProjectMaintainer(projectId) {
        if (customPrice == 0) revert ZeroAmount();
        _tierPricing[projectId][LicenseTier.AI_Training] = TierPricing(customPrice, token, true);
        emit TierPricingUpdated(projectId, LicenseTier.AI_Training, customPrice, token);
    }

    /**
     * @dev Set batch custom pricing for all tiers using the Custom pricing mode.
     *      This allows Stewards to define completely arbitrary fee structures.
     * @param projectId Project ID
     * @param prices Array of prices for each tier [Tier1_Individual, Tier2_Team, Tier3_Organization, Tier4_LargeOrg, AI_Training]
     * @param token Payment token
     */
    function setCustomBatchPricing(
        uint256 projectId,
        uint256[5] calldata prices,
        address token
    ) external onlyProjectMaintainer(projectId) {
        LicenseTier[5] memory tiers = [
            LicenseTier.Tier1_Individual,
            LicenseTier.Tier2_Team,
            LicenseTier.Tier3_Organization,
            LicenseTier.Tier4_LargeOrg,
            LicenseTier.AI_Training
        ];
        for (uint256 i = 0; i < 5; i++) {
            if (prices[i] > 0) {
                _tierPricing[projectId][tiers[i]] = TierPricing(prices[i], token, true);
                emit TierPricingUpdated(projectId, tiers[i], prices[i], token);
            }
        }
        emit PricingModeChanged(projectId, _projects[projectId].pricingMode, PricingMode.Custom);
        _projects[projectId].pricingMode = PricingMode.Custom;
    }

    /// @notice Receive native token payments for license purchases
    receive() external payable {}
}
