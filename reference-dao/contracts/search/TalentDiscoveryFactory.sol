// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./SkillBadge.sol";
import "./TalentSearch.sol";
import "./RecommendationEngine.sol";
import "../interfaces/IAgentRegistry.sol";
import "../interfaces/IReputationRegistry.sol";
import "../interfaces/IValidationRegistry.sol";

/**
 * @title TalentDiscoveryFactory
 * @dev Factory contract to deploy the complete talent discovery system
 *      Deploys SkillBadge, TalentSearch, and RecommendationEngine with proper wiring
 *
 *      Usage:
 *      1. Deploy factory with existing registry addresses
 *      2. Call deploy() to get all three contracts
 *      3. Factory owner can set initial skills and configuration
 */
contract TalentDiscoveryFactory is Ownable {
    /// @notice Deployed contracts
    SkillBadge public skillBadge;
    TalentSearch public talentSearch;
    RecommendationEngine public recommendationEngine;

    /// @notice Registry addresses (immutable after deployment)
    address public immutable agentRegistry;
    address public immutable reputationRegistry;
    address public immutable validationRegistry;

    /// @notice Whether the system has been deployed
    bool public deployed;

    /// @notice Base URI for skill badge metadata
    string public baseURI;

    event SystemDeployed(
        address indexed skillBadge,
        address indexed talentSearch,
        address indexed recommendationEngine
    );

    event BaseURIUpdated(string oldURI, string newURI);

    /**
     * @dev Constructor
     * @param baseURI_ The base URI for skill badge metadata (e.g., "ipfs://...")
     * @param agentRegistry_ The identity registry address
     * @param reputationRegistry_ The reputation registry address
     * @param validationRegistry_ The validation registry address
     */
    constructor(
        string memory baseURI_,
        address agentRegistry_,
        address reputationRegistry_,
        address validationRegistry_
    ) Ownable() {
        baseURI = baseURI_;
        agentRegistry = agentRegistry_;
        reputationRegistry = reputationRegistry_;
        validationRegistry = validationRegistry_;
    }

    /**
     * @notice Deploy the complete talent discovery system
     * @return skillBadge_ The skill badge contract address
     * @return talentSearch_ The talent search contract address
     * @return recommendationEngine_ The recommendation engine address
     */
    function deploy()
        external
        onlyOwner
        returns (
            address skillBadge_,
            address talentSearch_,
            address recommendationEngine_
        )
    {
        if (deployed) {
            revert("Already deployed");
        }

        // Deploy SkillBadge
        skillBadge = new SkillBadge(
            baseURI,
            agentRegistry,
            validationRegistry
        );

        // Deploy TalentSearch
        talentSearch = new TalentSearch(
            agentRegistry,
            reputationRegistry,
            validationRegistry,
            address(skillBadge)
        );

        // Deploy RecommendationEngine
        recommendationEngine = new RecommendationEngine(
            agentRegistry,
            reputationRegistry,
            address(skillBadge)
        );

        // Grant roles to RecommendationEngine
        skillBadge.grantRole(skillBadge.ENGINE_ROLE(), address(recommendationEngine));

        // Grant MARKETPLACE_ROLE to marketplace (to be set later)
        recommendationEngine.grantRole(
            recommendationEngine.MARKETPLACE_ROLE(),
            address(this) // Temporarily grant to factory
        );

        // Transfer ownerships to timelock/DAO
        skillBadge.transferOwnership(msg.sender);
        talentSearch.transferOwnership(msg.sender);
        recommendationEngine.transferOwnership(msg.sender);

        deployed = true;

        emit SystemDeployed(address(skillBadge), address(talentSearch), address(recommendationEngine));

        return (address(skillBadge), address(talentSearch), address(recommendationEngine));
    }

    /**
     * @notice Set marketplace role in recommendation engine
     * @param marketplace The marketplace contract address
     */
    function setMarketplaceRole(address marketplace) external onlyOwner {
        recommendationEngine.grantRole(
            recommendationEngine.MARKETPLACE_ROLE(),
            marketplace
        );
    }

    /**
     * @notice Register a new skill via factory
     * @param name The skill name
     * @param category The skill category
     */
    function registerSkill(string calldata name, string calldata category) external onlyOwner {
        skillBadge.registerSkill(name, category);
    }

    /**
     * @notice Update base URI for skill badges
     * @param newURI The new base URI
     */
    function setBaseURI(string calldata newURI) external onlyOwner {
        string memory oldURI = baseURI;
        baseURI = newURI;
        skillBadge.setURI(newURI);
        emit BaseURIUpdated(oldURI, newURI);
    }

    /**
     * @notice Get all deployed contract addresses
     * @return skillBadge_ The skill badge address
     * @return talentSearch_ The talent search address
     * @return recommendationEngine_ The recommendation engine address
     */
    function getContracts()
        external
        view
        returns (
            address skillBadge_,
            address talentSearch_,
            address recommendationEngine_
        )
    {
        return (address(skillBadge), address(talentSearch), address(recommendationEngine));
    }

    /**
     * @notice Check if system is deployed
     * @return True if deployed
     */
    function isDeployed() external view returns (bool) {
        return deployed;
    }
}
