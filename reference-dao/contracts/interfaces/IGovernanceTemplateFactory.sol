// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title IGovernanceTemplateFactory
 * @dev Interface for pre-built governance parameter templates.
 */
interface IGovernanceTemplateFactory {
    struct GovernanceConfig {
        uint256 votingDelay;
        uint256 votingPeriod;
        uint256 proposalThreshold;
        uint8 quorumFraction;
        uint256 timelockDelay;
    }

    event TemplateRegistered(string indexed name, GovernanceConfig config);
    event TemplateRemoved(string indexed name);

    /**
     * @dev Get a governance template by name.
     * @param name Template name (e.g. "Conservative", "Balanced", "Flexible")
     * @return The governance configuration
     */
    function getTemplate(string memory name) external view returns (GovernanceConfig memory);

    /**
     * @dev Register a custom governance template.
     * @param name Template name
     * @param config Governance configuration
     */
    function registerTemplate(string memory name, GovernanceConfig calldata config) external;

    /**
     * @dev Remove a governance template.
     * @param name Template name
     */
    function removeTemplate(string memory name) external;

    /**
     * @dev Check if a template exists.
     * @param name Template name
     * @return Whether the template exists
     */
    function templateExists(string memory name) external view returns (bool);
}
