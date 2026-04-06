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
        FixedTiers,
        RevenueShare,
        Custom
    }

    enum LicenseTier {
        Micro,
        Small,
        Medium,
        Enterprise,
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
        address maintainer;
        PricingMode pricingMode;
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
        address indexed maintainer
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

    modifier projectExists(uint256 projectId) {
        if (!_projects[projectId].exists) {
            revert ProjectNotFound(projectId);
        }
        _;
    }

    modifier onlyProjectMaintainer(uint256 projectId) {
        if (_projects[projectId].maintainer != msg.sender && msg.sender != owner()) {
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
            maintainer: msg.sender,
            pricingMode: PricingMode.FixedTiers,
            exists: true
        });

        _projectIdByContentHash[contentHash] = projectId;
        _projectCount++;

        // Set default tier pricing if token provided
        if (initialPricingToken != address(0)) {
            _setDefaultPricing(projectId, initialPricingToken);
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

        // Check existing license
        InternalLicense storage existing = _licenses[projectId][licensee];
        if (existing.status == LicenseStatus.Active && existing.expiresAt > block.timestamp) {
            revert LicenseAlreadyActive(licensee);
        }

        uint256 amount = pricing.amount;

        // Transfer tokens from caller to this contract
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
     * @dev Revoke a license (maintainer only, e.g., for license violation)
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
        return ViewProject(p.name, p.contentHash, p.metadataURI, p.maintainer, uint8(p.pricingMode), p.exists);
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
        // If renewing, update existing
        InternalLicense storage license = _licenses[projectId][licensee];
        bool isNew = (license.status == LicenseStatus.None);

        license.licensee = licensee;
        license.tier = LicenseTier(tier);
        license.status = LicenseStatus.Active;
        license.paidAmount = amount;
        license.paidAt = block.timestamp;
        license.expiresAt = block.timestamp + 365 days;
        license.metadataHash = metadataHash;

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
    function setRecommendedPricing(uint256 projectId, address token) internal {
        _tierPricing[projectId][LicenseTier.Micro] = TierPricing(100 * 10**18, token, true);
        _tierPricing[projectId][LicenseTier.Small] = TierPricing(1000 * 10**18, token, true);
        _tierPricing[projectId][LicenseTier.Medium] = TierPricing(10000 * 10**18, token, true);
        _tierPricing[projectId][LicenseTier.Enterprise] = TierPricing(50000 * 10**18, token, true);
        _tierPricing[projectId][LicenseTier.AI_Training] = TierPricing(25000 * 10**18, token, true);
    }

    /**
     * @dev Set custom pricing for the Commercial tier (tier 0).
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
        _tierPricing[projectId][LicenseTier.Micro] = TierPricing(customPrice, token, true);
        emit TierPricingUpdated(projectId, LicenseTier.Micro, customPrice, token);
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
     * @param prices Array of prices for each tier [Micro, Small, Medium, Enterprise, AI_Training]
     * @param token Payment token
     */
    function setCustomBatchPricing(
        uint256 projectId,
        uint256[5] calldata prices,
        address token
    ) external onlyProjectMaintainer(projectId) {
        LicenseTier[5] memory tiers = [
            LicenseTier.Micro,
            LicenseTier.Small,
            LicenseTier.Medium,
            LicenseTier.Enterprise,
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
