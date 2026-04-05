// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "./IPaymentLedger.sol";

/**
 * @title IRoyaltyRegistry
 * @dev Pure view-only interface for external consumers and cross-contract calls.
 *      No enums - all numeric types are uint8/uint256 to avoid external ABI conflicts.
 *      Use RoyaltyRegistry.LicenseTier when you need the enum type locally.
 *
 *      Enum value mappings (defined in RoyaltyRegistry.sol):
 *      LicenseTier:    Micro=0, Small=1, Medium=2, Enterprise=3, AI_Training=4
 *      LicenseStatus:  None=0, Active=1, Expired=2, Revoked=3
 *      PricingMode:    FixedTiers=0, RevenueShare=1, Custom=2
 */
interface IRoyaltyRegistry {
    // View-only structs with simple types
    struct ViewProject {
        string name;
        bytes32 contentHash;
        string metadataURI;
        address maintainer;
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

    // Write/state-changing functions (for governance and management)
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
