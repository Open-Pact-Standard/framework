// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IRoyaltyRegistry.sol";
import "../interfaces/IPaymentLedger.sol";
import "./RoyaltyRegistry.sol";
/**
 * @title LicenseIssuer
 * @dev Handles tier selection, payment verification, and license acknowledgment
     *      for the Open-Pact (OPL-1.1) licensing system. Acts as the user-facing entry
 *      point: callers select a tier, acknowledge license terms, and receive a
 *      verifiable on-chain license from the RoyaltyRegistry.
 *
 *      This contract abstracts the royalty payments away from end users -- they
 *      interact with LicenseIssuer, which handles:
 *      1. Tier pricing lookup from RoyaltyRegistry
 *      2. Payment verification and forwarding to RoyaltyRegistry
 *      3. License acknowledgment recording (OPL-1.1 totalWorkforce)
 *      4. Public license registry for verification
 *
 *      Integration:
 *      - Companies verify their license before commercial deployment
 *      - CI/CD pipelines can check on-chain license status
 *      - AI training registries can verify AI_Training tier licenses
 */
contract LicenseIssuer is Ownable, Pausable, ReentrancyGuard {
    // Core registry
    IRoyaltyRegistry public immutable royaltyRegistry;
    IPaymentLedger public immutable paymentLedger;

    // License acknowledgment metadata
    struct Acknowledgment {
        string licenseTextHash;         // Hash of the Open-Pact license text
        string usageDescription;        // How the licensee intends to use the code
        string companyName;             // Legal entity name
        uint256 totalWorkforce;         // Per OPL-1.1 Section 1.5: total workers
        uint256 timestamp;
    }

    // Project -> licensee -> acknowledgment
    mapping(uint256 => mapping(address => Acknowledgment)) private _acknowledgments;

    // Price oracle support (optional: convert between token denominations)
    mapping(address => bool) private _authorizedOracles;

    // Default license text hash (should match the canonical OPL-1.1)
    bytes32 public defaultLicenseTextHash;

    // Errors
    error ZeroAddress();
    error LicenseNotActive(uint256 projectId, address licensee);
    error AcknowledgmentRequired();
    error OracleNotAuthorized();
    error InvalidProjectId();
    error NotAuthorized(address caller);

    // Events
    event LicenseAcknowledged(
        uint256 indexed projectId,
        address indexed licensee,
        string companyName,
        uint256 totalWorkforce
    );
    event DefaultLicenseHashUpdated(bytes32 oldHash, bytes32 newHash);
    event OracleAuthorized(address indexed oracle, bool status);

    modifier projectExists(uint256 projectId) {
        if (projectId >= royaltyRegistry.getProjectCount()) {
            revert InvalidProjectId();
        }
        _;
    }

    constructor(address _royaltyRegistry, address _paymentLedger) Ownable() {
        if (_royaltyRegistry == address(0) || _paymentLedger == address(0)) {
            revert ZeroAddress();
        }
        royaltyRegistry = IRoyaltyRegistry(_royaltyRegistry);
        paymentLedger = IPaymentLedger(_paymentLedger);
    }

    // ================================================================
    // LICENSE PURCHASE WITH ACKNOWLEDGMENT
    // ================================================================

    /**
     * @dev Purchase a license with full acknowledgment (native token)
     * @param projectId Project ID in RoyaltyRegistry
     * @param tier License tier
     * @param ack License acknowledgment data
     */
    function acquireLicense(
        uint256 projectId,
        RoyaltyRegistry.LicenseTier tier,
        Acknowledgment calldata ack
    ) external payable nonReentrant whenNotPaused projectExists(projectId) {
        if (bytes(ack.companyName).length == 0) {
            revert AcknowledgmentRequired();
        }

        // Record acknowledgment
        _acknowledgments[projectId][msg.sender] = Acknowledgment({
            licenseTextHash: ack.licenseTextHash,
            usageDescription: ack.usageDescription,
            companyName: ack.companyName,
            totalWorkforce: ack.totalWorkforce,
            timestamp: block.timestamp
        });

        // Purchase the license via RoyaltyRegistry
        royaltyRegistry.purchaseLicense{value: msg.value}(
            projectId,
            msg.sender,
            uint8(tier),
            _computeMetadataHash(ack)
        );

        emit LicenseAcknowledged(projectId, msg.sender, ack.companyName, ack.totalWorkforce);
    }

    /**
     * @dev Purchase a license with ERC20 token
     * @param projectId Project ID
     * @param tier License tier
     * @param ack Acknowledgment data
     * @param token Payment token address
     */
    function acquireLicenseWithToken(
        uint256 projectId,
        RoyaltyRegistry.LicenseTier tier,
        Acknowledgment calldata ack,
        address token
    ) external nonReentrant whenNotPaused projectExists(projectId) {
        if (bytes(ack.companyName).length == 0) {
            revert AcknowledgmentRequired();
        }

        _acknowledgments[projectId][msg.sender] = Acknowledgment({
            licenseTextHash: ack.licenseTextHash,
            usageDescription: ack.usageDescription,
            companyName: ack.companyName,
            totalWorkforce: ack.totalWorkforce,
            timestamp: block.timestamp
        });

        royaltyRegistry.purchaseLicenseWithToken(
            projectId,
            msg.sender,
            uint8(tier),
            _computeMetadataHash(ack),
            token
        );

        emit LicenseAcknowledged(projectId, msg.sender, ack.companyName, ack.totalWorkforce);
    }

    // ================================================================
    // LICENSE VERIFICATION
    // ================================================================

    /**
     * @dev Check if an address holds a valid license for a project
     * @param projectId Project ID
     * @param licensee Address to check
     * @return valid Whether the license is active and not expired
     * @return tier The license tier
     * @return expiresAt When the license expires
     */
    function verifyLicense(
        uint256 projectId,
        address licensee
    ) external view returns (bool valid, RoyaltyRegistry.LicenseTier tier, uint256 expiresAt) {
        IRoyaltyRegistry.ViewLicense memory license = royaltyRegistry.getLicense(projectId, licensee);
        valid = (license.status == 1 && // 1 = Active
                 license.expiresAt > block.timestamp);
        tier = RoyaltyRegistry.LicenseTier(license.tier);
        expiresAt = license.expiresAt;
    }

    /**
     * @dev Get the acknowledgment for a licensee
     * @param projectId Project ID
     * @param licensee Licensee address
     * @return ack The acknowledgment data
     */
    function getAcknowledgment(
        uint256 projectId,
        address licensee
    ) external view returns (Acknowledgment memory ack) {
        return _acknowledgments[projectId][licensee];
    }

    /**
     * @dev Get a comprehensive license report for verification
     * @param projectId Project ID
     * @param licensee Licensee address
     * @return license The license details
     * @return ack The acknowledgment details
     * @return valid Whether the license is currently valid
     */
    function getLicenseReport(
        uint256 projectId,
        address licensee
    ) external view returns (
        IRoyaltyRegistry.ViewLicense memory license,
        Acknowledgment memory ack,
        bool valid
    ) {
        license = royaltyRegistry.getLicense(projectId, licensee);
        ack = _acknowledgments[projectId][licensee];
        valid = (license.status == 1 && 
                 license.expiresAt > block.timestamp);
    }

    // ================================================================
    // BULK LICENSE PURCHASE (for DAOs/enterprises)
    // ================================================================

    /**
     * @dev Purchase licenses for multiple projects at once
     * @param projectIds Array of project IDs
     * @param tier License tier (applies to all)
     * @param ack Acknowledgment data
     */
    function acquireMultiLicense(
        uint256[] calldata projectIds,
        RoyaltyRegistry.LicenseTier tier,
        Acknowledgment calldata ack
    ) external payable nonReentrant whenNotPaused {
        if (bytes(ack.companyName).length == 0) {
            revert AcknowledgmentRequired();
        }

        uint256 totalRequired = 0;

        // Calculate total cost and record acknowledgments
        for (uint256 i = 0; i < projectIds.length; i++) {
            if (projectIds[i] >= royaltyRegistry.getProjectCount()) {
                revert InvalidProjectId();
            }

            IRoyaltyRegistry.ViewTierPricing memory pricing = royaltyRegistry.getTierPricing(
                projectIds[i], uint8(tier)
            );
            if (!pricing.enabled) {
                continue; // Skip unpriced tiers
            }
            if (pricing.token != address(0)) {
                continue; // Non-native tokens handled separately
            }
            totalRequired += pricing.amount;

            _acknowledgments[projectIds[i]][msg.sender] = Acknowledgment({
                licenseTextHash: ack.licenseTextHash,
                usageDescription: ack.usageDescription,
                companyName: ack.companyName,
                totalWorkforce: ack.totalWorkforce,
                timestamp: block.timestamp
            });
        }

        if (msg.value != totalRequired) {
            revert ZeroAddress();
        }

        // Purchase all licenses
        for (uint256 i = 0; i < projectIds.length; i++) {
            IRoyaltyRegistry.ViewTierPricing memory pricing = royaltyRegistry.getTierPricing(
                projectIds[i], uint8(tier)
            );
            if (pricing.enabled && pricing.token == address(0)) {
                // Note: In a real implementation, this would need the RoyaltyRegistry
                // to support batch purchasing to avoid reentrancy from multiple calls
                royaltyRegistry.purchaseLicense{value: pricing.amount}(
                    projectIds[i],
                    msg.sender,
                    uint8(tier),
                    _computeMetadataHash(ack)
                );
                emit LicenseAcknowledged(projectIds[i], msg.sender, ack.companyName, ack.totalWorkforce);
            }
        }
    }

    // ================================================================
    // ADMIN FUNCTIONS
    // ================================================================

    /**
     * @dev Update the default license text hash
     * @param newHash Keccak256 hash of the canonical OPL-1.0 license
     */
    function setDefaultLicenseHash(bytes32 newHash) external onlyOwner {
        bytes32 oldHash = defaultLicenseTextHash;
        defaultLicenseTextHash = newHash;
        emit DefaultLicenseHashUpdated(oldHash, newHash);
    }

    /**
     * @dev Authorize or deauthorize a price oracle
     * @param oracle Oracle address
     * @param status Whether to authorize
     */
    function authorizeOracle(address oracle, bool status) external onlyOwner {
        if (oracle == address(0)) {
            revert ZeroAddress();
        }
        _authorizedOracles[oracle] = status;
        emit OracleAuthorized(oracle, status);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // ================================================================
    // INTERNAL FUNCTIONS
    // ================================================================

    function _computeMetadataHash(Acknowledgment memory ack) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(
            ack.companyName,
            ack.totalWorkforce,
            ack.usageDescription,
            ack.licenseTextHash
        ));
    }
}
