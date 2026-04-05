// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

/**
 * @title LicenseVerifier
 * @dev Utility contract for verifying Open-Pact (OPL) license compliance.
 *      Designed to be called by CI/CD pipelines, agent registries, or DAOs
 *      to verify that entities hold valid licenses for commercial/AI usage.
 *
 *      Uses staticcall to read from RoyaltyRegistry -- no state changes.
 *      All functions are view (no events emitted, no state writes).
 */
contract LicenseVerifier {
    struct ComplianceResult {
        uint256 projectId;
        address licensee;
        bool isValid;
        string tier;
        uint256 expiresAt;
    }

    /**
     * @dev Check if a specific address has a valid license for a project
     */
    function checkCompliance(
        address registry,
        uint256 projectId,
        address licensee
    ) external view returns (bool isValid) {
        (isValid, , ) = _checkCompliance(registry, projectId, licensee);
    }

    /**
     * @dev Detailed compliance check with tier and expiration
     */
    function checkComplianceDetailed(
        address registry,
        uint256 projectId,
        address licensee
    ) public view returns (bool compliant, string memory tier, uint256 expiresAt) {
        return _checkCompliance(registry, projectId, licensee);
    }

    /**
     * @dev Batch compliance check across multiple projects
     */
    function batchCheckCompliance(
        address registry,
        uint256[] calldata projectIds,
        address licensee
    ) external view returns (ComplianceResult[] memory results) {
        results = new ComplianceResult[](projectIds.length);
        uint256 compliantCount = 0;

        for (uint256 i = 0; i < projectIds.length; i++) {
            (bool compliant, string memory tier, uint256 expiresAt) = _checkCompliance(
                registry,
                projectIds[i],
                licensee
            );
            results[i] = ComplianceResult(projectIds[i], licensee, compliant, tier, expiresAt);
            if (compliant) compliantCount++;
        }
    }

    /**
     * @dev Check compliance for multiple licensees against one project
     */
    function batchCheckLicensees(
        address registry,
        uint256 projectId,
        address[] calldata licensees
    ) external view returns (bool[] memory results) {
        results = new bool[](licensees.length);
        for (uint256 i = 0; i < licensees.length; i++) {
            (results[i], , ) = _checkCompliance(registry, projectId, licensees[i]);
        }
    }

    /**
     * @dev Core compliance check via staticcall
     *      Calls RoyaltyRegistry.getLicense(uint256,address)
     */
    function _checkCompliance(
        address registry,
        uint256 projectId,
        address licensee
    ) internal view returns (bool valid, string memory tier, uint256 expiresAt) {
        bytes memory payload = abi.encodeWithSignature(
            "getLicense(uint256,address)",
            projectId,
            licensee
        );

        (bool success, bytes memory returndata) = registry.staticcall(payload);
        if (!success) {
            return (false, "error", 0);
        }

        // Decode ViewLicense: licensee, tier(uint8), status(uint8), paidAmount, paidAt, expiresAt, metadataHash
        (
            ,
            uint8 tierEnum,
            uint8 statusEnum,
            ,
            ,
            uint256 licenseExpiresAt,

        ) = abi.decode(returndata, (address, uint8, uint8, uint256, uint256, uint256, bytes32));

        bool isActive = (statusEnum == 1 && licenseExpiresAt > block.timestamp);

        string[5] memory tierNames = ["Micro", "Small", "Medium", "Enterprise", "AI_Training"];
        tier = tierNames[tierEnum];
        expiresAt = licenseExpiresAt;

        return (isActive, tier, expiresAt);
    }
}
