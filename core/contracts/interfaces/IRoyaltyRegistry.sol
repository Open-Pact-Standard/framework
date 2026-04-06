// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "./IPaymentLedger.sol";

/**
 * @title IRoyaltyRegistry
 * @dev Pure view-only interface for external consumers and cross-contract calls.
 *      No enums - all numeric types are uint8/uint256 to avoid external ABI conflicts.
 *      Use RoyaltyRegistry.LicenseTier when you need the enum type locally.
 *
 *      Enum value mappings (defined in RoyaltyRegistry.sol):
 *      LicenseTier:    Tier1_Individual=0, Tier2_Team=1, Tier3_Organization=2, Tier4_LargeOrg=3, AI_Training=4
 *      LicenseStatus:  None=0, Active=1, Expired=2, Revoked=3
 *      PricingMode:    Structured=0, RevenueShare=1, Custom=2
 */
interface IRoyaltyRegistry {
    // View-only structs with simple types
    struct ViewProject {
        string name;
        bytes32 contentHash;
        string metadataURI;
        address licenseSteward;
        uint8 pricingMode;
        bool exists;
    }

    struct ViewLicense {
        address licensee;
        uint8 tier;
        uint8 status;
        uint256 paidAmount;
        uint256 paidAt;
        uint256 expiresAt;
        bytes32 metadataHash;
    }

    struct ViewTierPricing {
        uint256 amount;
        address token;
        bool enabled;
    }

    function paymentLedger() external view returns (IPaymentLedger);
    function paymentVerifier() external view returns (address);

    // SaaS Revenue reporting structs
    struct ViewRevenueReport {
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

    // Write/state-changing functions (for governance and management)
    function reportSaaSRevenue(
        uint256 projectId,
        uint256 grossRevenue,
        uint256 infrastructureCost,
        uint256 stewardShareBps,
        bytes32 evidenceHash
    ) external;
    function payRevenueShare(uint256 projectId, uint256 reportIndex) external payable;
    function getRevenueReport(uint256 projectId, address licensee, uint256 index) external view returns (ViewRevenueReport memory);

    // Workforce tracking (OPL-1.1 §1.5)
    function updateWorkforce(uint256 workforceSize) external;
    function getWorkforce(address licensee) external view returns (uint256);

    // AI Training disclosure (OPL-1.1 §4.3)
    function submitAITrainingDisclosure(
        uint256 projectId,
        string calldata softwareName,
        string calldata commitHash,
        string calldata repositoryURL,
        string calldata modelCardURI,
        bool downstreamNotified,
        bool notCompetingProduct
    ) external;
    function getAITrainingDisclosure(uint256 projectId, address licensee) external view returns (
        string memory softwareName,
        string memory commitHash,
        string memory repositoryURL,
        string memory modelCardURI,
        bool downstreamNotified,
        bool competingProductDeclared,
        bytes32 disclosureHash,
        uint256 disclosedAt
    );
    function hasAITrainingDisclosure(uint256 projectId, address licensee) external view returns (bool);
    function setTierPricing(
        uint256 projectId,
        uint8 tier,
        uint256 amount,
        address token
    ) external;
    function registerProject(
        string calldata name,
        bytes32 contentHash,
        string calldata metadataURI,
        address initialPricingToken
    ) external returns (uint256);
    function purchaseLicense(
        uint256 projectId,
        address licensee,
        uint8 tier,
        bytes32 metadataHash
    ) external payable;
    function purchaseLicenseWithToken(
        uint256 projectId,
        address licensee,
        uint8 tier,
        bytes32 metadataHash,
        address token
    ) external;
    function addContributor(
        uint256 projectId,
        address wallet,
        string calldata identifier,
        uint96 weight
    ) external;
    function disableTier(uint256 projectId, uint8 tier) external;
    function renewLicense(uint256 projectId, uint8 tier) external payable;
    function revokeLicense(uint256 projectId, address licensee) external;
    function setPricingMode(uint256 projectId, uint8 mode) external;
    function setCustomAITrainingPrice(
        uint256 projectId,
        uint256 customPrice,
        address token
    ) external;
    function setCustomCommercialPrice(
        uint256 projectId,
        uint256 customPrice,
        address token
    ) external;
    function setCustomBatchPricing(
        uint256 projectId,
        uint256[5] calldata prices,
        address token
    ) external;

    // Canonical registry identity and temporal fee tracking (OPL-1.1 §3.2.1, §3.2.3)
    function setRegistryIdentifier(string calldata identifier) external;
    function getRegistryIdentifier() external view returns (string memory);
    function setRegistryCertification(uint256 projectId, bytes32 certificationHash) external;
    function advanceFeeScheduleVersion(uint256 projectId) external;
    function getFeeScheduleVersion(uint256 projectId) external view returns (uint256);
    function getFeeScheduleStatus(uint256 projectId) external view returns (bool isInNoticePeriod, uint256 effectiveAt);
    function getFeeChangeEffectiveAt(uint256 projectId) external view returns (uint256);
    function getFeeVersionSnapshot(uint256 projectId, uint256 feeVersion, uint8 tier) external view returns (uint256);

    // Extended purchase functions with full metadata (per OPL-1.1 §1.20)
    function purchaseLicenseWithMetadata(
        uint256 projectId,
        address licensee,
        uint8 tier,
        bytes32 metadataHash,
        string calldata licenseVersion,
        uint256 totalWorkforce
    ) external payable;
    function purchaseLicenseWithTokenAndMetadata(
        uint256 projectId,
        address licensee,
        uint8 tier,
        bytes32 metadataHash,
        address token,
        string calldata licenseVersion,
        uint256 totalWorkforce
    ) external;

    // View functions
    function getProject(uint256 projectId) external view returns (ViewProject memory);
    function getProjectCount() external view returns (uint256);
    function getContributor(uint256 projectId, uint256 index) external view returns (
        address wallet,
        string memory identifier,
        uint96 weight,
        uint96 reputation,
        bool active
    );
    function getContributorCount(uint256 projectId) external view returns (uint256);
    function getTotalWeight(uint256 projectId) external view returns (uint256);
    function getLicense(uint256 projectId, address licensee) external view returns (ViewLicense memory);
    function getTierPricing(uint256 projectId, uint8 tier) external view returns (ViewTierPricing memory);
    function getPendingWithdrawal(address contributor, uint256 projectId) external view returns (uint256);
    function getTotalRoyaltiesCollected(uint256 projectId) external view returns (uint256);
    function getActiveLicenseCount(uint256 projectId) external view returns (uint256);
}
