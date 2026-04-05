// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IGovernanceTemplateFactory.sol";

/**
 * @title GovernanceTemplateFactory
 * @dev Stores pre-built governance parameter configurations.
 *      Provides Conservative, Balanced, and Flexible presets.
 *      Templates are parameter sets — the DAOFactory reads them during creation.
 */
contract GovernanceTemplateFactory is IGovernanceTemplateFactory, Ownable {
    mapping(string => GovernanceConfig) private _templates;
    mapping(string => bool) private _exists;
    string[] private _templateNames;

    error TemplateNotFound(string name);
    error TemplateAlreadyExists(string name);
    error InvalidConfig();

    constructor() Ownable() {
        _registerDefaults();
    }

    /**
     * @dev Register built-in governance templates.
     *      Conservative: 7 day voting, high quorum, long timelock
     *      Balanced: 5 day voting, moderate quorum, medium timelock
     *      Flexible: 3 day voting, low quorum, short timelock
     */
    function _registerDefaults() internal {
        // Conservative: ~7 days (50400 blocks at 12s/block)
        _templates["Conservative"] = GovernanceConfig({
            votingDelay: 7200,
            votingPeriod: 50400,
            proposalThreshold: 1_000_000 * 10**18,
            quorumFraction: 10,
            timelockDelay: 2 days
        });
        _exists["Conservative"] = true;
        _templateNames.push("Conservative");

        // Balanced: ~5 days (36000 blocks)
        _templates["Balanced"] = GovernanceConfig({
            votingDelay: 3600,
            votingPeriod: 36000,
            proposalThreshold: 100_000 * 10**18,
            quorumFraction: 4,
            timelockDelay: 1 days
        });
        _exists["Balanced"] = true;
        _templateNames.push("Balanced");

        // Flexible: ~3 days (21600 blocks)
        _templates["Flexible"] = GovernanceConfig({
            votingDelay: 1800,
            votingPeriod: 21600,
            proposalThreshold: 10_000 * 10**18,
            quorumFraction: 2,
            timelockDelay: 12 hours
        });
        _exists["Flexible"] = true;
        _templateNames.push("Flexible");
    }

    /**
     * @inheritdoc IGovernanceTemplateFactory
     */
    function getTemplate(string memory name) external view override returns (GovernanceConfig memory) {
        if (!_exists[name]) {
            revert TemplateNotFound(name);
        }
        return _templates[name];
    }

    /**
     * @inheritdoc IGovernanceTemplateFactory
     */
    function registerTemplate(
        string memory name,
        GovernanceConfig calldata config
    ) external override onlyOwner {
        if (_exists[name]) {
            revert TemplateAlreadyExists(name);
        }
        _validateConfig(config);
        _templates[name] = config;
        _exists[name] = true;
        _templateNames.push(name);
        emit TemplateRegistered(name, config);
    }

    /**
     * @inheritdoc IGovernanceTemplateFactory
     */
    function removeTemplate(string memory name) external override onlyOwner {
        if (!_exists[name]) {
            revert TemplateNotFound(name);
        }
        delete _templates[name];
        _exists[name] = false;

        // Remove from _templateNames array
        for (uint256 i = 0; i < _templateNames.length; i++) {
            if (keccak256(bytes(_templateNames[i])) == keccak256(bytes(name))) {
                _templateNames[i] = _templateNames[_templateNames.length - 1];
                _templateNames.pop();
                break;
            }
        }

        emit TemplateRemoved(name);
    }

    /**
     * @dev Check if a template exists.
     */
    function templateExists(string memory name) external view override returns (bool) {
        return _exists[name];
    }

    /**
     * @dev Get all registered template names.
     * @return Array of template names
     */
    function getTemplateNames() external view returns (string[] memory) {
        return _templateNames;
    }

    /**
     * @dev Validate governance configuration parameters.
     */
    function _validateConfig(GovernanceConfig calldata config) internal pure {
        if (config.votingPeriod == 0) {
            revert InvalidConfig();
        }
        if (config.quorumFraction == 0 || config.quorumFraction > 100) {
            revert InvalidConfig();
        }
    }
}
