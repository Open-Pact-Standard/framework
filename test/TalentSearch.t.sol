// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/search/TalentSearch.sol";
import "../contracts/search/SkillBadge.sol";
import "../contracts/interfaces/ISkillBadge.sol";
import "../contracts/interfaces/ITalentSearch.sol";
import "../contracts/agents/IdentityRegistry.sol";
import "../contracts/agents/ReputationRegistry.sol";
import "../contracts/agents/ValidationRegistry.sol";

/**
 * @title TalentSearchTest
 * @dev Test suite for TalentSearch contract
 */
contract TalentSearchTest is Test {
    TalentSearch talentSearch;
    SkillBadge skillBadge;
    IdentityRegistry identityRegistry;
    ReputationRegistry reputationRegistry;
    ValidationRegistry validationRegistry;

    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    address charlie = address(0x4);

    uint256 aliceAgentId;
    uint256 bobAgentId;
    uint256 charlieAgentId;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy core registries
        identityRegistry = new IdentityRegistry();
        reputationRegistry = new ReputationRegistry();
        validationRegistry = new ValidationRegistry();

        // Deploy SkillBadge
        skillBadge = new SkillBadge(
            "ipfs://QmTest/",
            address(identityRegistry),
            address(validationRegistry)
        );

        // Deploy TalentSearch
        talentSearch = new TalentSearch(
            address(identityRegistry),
            address(reputationRegistry),
            address(validationRegistry),
            address(skillBadge)
        );

        // Register validators
        validationRegistry.registerValidator();

        vm.stopPrank();

        // Register agents
        vm.prank(alice);
        aliceAgentId = identityRegistry.register("ipfs://alice");

        vm.prank(bob);
        bobAgentId = identityRegistry.register("ipfs://bob");

        vm.prank(charlie);
        charlieAgentId = identityRegistry.register("ipfs://charlie");

        // Record registrations in TalentSearch (must be called by agentRegistry)
        vm.prank(address(identityRegistry));
        talentSearch.recordRegistration(aliceAgentId);
        vm.prank(address(identityRegistry));
        talentSearch.recordRegistration(bobAgentId);
        vm.prank(address(identityRegistry));
        talentSearch.recordRegistration(charlieAgentId);
    }

    function testInitialState() public {
        assertEq(address(talentSearch.agentRegistry()), address(identityRegistry));
        assertEq(address(talentSearch.reputationRegistry()), address(reputationRegistry));
        assertEq(address(talentSearch.validationRegistry()), address(validationRegistry));
        assertEq(address(talentSearch.skillBadge()), address(skillBadge));
    }

    function testGetTopAgents() public {
        // Add reputation
        vm.prank(alice);
        reputationRegistry.submitReview(bobAgentId, 5, "Great work");

        vm.prank(bob);
        reputationRegistry.submitReview(aliceAgentId, 8, "Excellent");

        uint256[] memory topAgents = talentSearch.getTopAgents(5);

        assertTrue(topAgents.length > 0);
        // Charlie should be last (no reviews)
        assertEq(topAgents[topAgents.length - 1], charlieAgentId);
    }

    function testGetTopAgentsBySkill() public {
        // Claim skills
        vm.prank(alice);
        skillBadge.claimSkill(1); // Solidity

        vm.prank(bob);
        skillBadge.claimSkill(1);

        vm.prank(owner);
        skillBadge.verifySkill(bobAgentId, 1, ISkillBadge.VerificationLevel.Verified);

        uint256[] memory topAgents = talentSearch.getTopAgentsBySkill(1, uint256(ISkillBadge.VerificationLevel.Self), 5);

        assertEq(topAgents.length, 2);
        // Both agents should be in the list
        assertTrue(topAgents[0] == aliceAgentId || topAgents[0] == bobAgentId);
        assertTrue(topAgents[1] == aliceAgentId || topAgents[1] == bobAgentId);
    }

    function testGetAgentsByCategory() public {
        vm.startPrank(alice);
        skillBadge.claimSkill(1); // Blockchain
        skillBadge.claimSkill(2); // Blockchain
        vm.stopPrank();

        vm.prank(bob);
        skillBadge.claimSkill(6); // AI (LLM Fine-tuning)

        uint256[] memory blockchainAgents = talentSearch.getAgentsByCategory("Blockchain", 10);
        uint256[] memory aiAgents = talentSearch.getAgentsByCategory("AI", 10);

        assertTrue(blockchainAgents.length >= 1);
        assertTrue(aiAgents.length >= 1);
    }

    function testGetRecommendedAgents() public {
        // Alice has skills 1, 2, 3
        vm.startPrank(alice);
        skillBadge.claimSkill(1);
        skillBadge.claimSkill(2);
        skillBadge.claimSkill(3);
        vm.stopPrank();

        // Bob has skills 1, 2
        vm.startPrank(bob);
        skillBadge.claimSkill(1);
        skillBadge.claimSkill(2);
        vm.stopPrank();

        uint256[] memory requiredSkills = new uint256[](2);
        requiredSkills[0] = 1;
        requiredSkills[1] = 2;

        uint256[] memory minLevels = new uint256[](2);
        minLevels[0] = uint256(ISkillBadge.VerificationLevel.Self);
        minLevels[1] = uint256(ISkillBadge.VerificationLevel.Self);

        uint256[] memory recommended = talentSearch.getRecommendedAgents(requiredSkills, minLevels, 10);

        assertEq(recommended.length, 2);
        assertEq(recommended[0], aliceAgentId); // Alice has both skills
        assertEq(recommended[1], bobAgentId);
    }

    function testGetRecommendedAgentsRequiresAllSkills() public {
        // Alice has skill 1 only
        vm.prank(alice);
        skillBadge.claimSkill(1);

        // Bob has skill 2 only
        vm.prank(bob);
        skillBadge.claimSkill(2);

        uint256[] memory requiredSkills = new uint256[](2);
        requiredSkills[0] = 1;
        requiredSkills[1] = 2;

        uint256[] memory minLevels = new uint256[](2);
        minLevels[0] = uint256(ISkillBadge.VerificationLevel.Self);
        minLevels[1] = uint256(ISkillBadge.VerificationLevel.Self);

        uint256[] memory recommended = talentSearch.getRecommendedAgents(requiredSkills, minLevels, 10);

        // No one has both skills
        assertEq(recommended.length, 0);
    }

    function testGetAgentProfile() public {
        vm.prank(alice);
        reputationRegistry.submitReview(bobAgentId, 5, "Good");

        vm.prank(owner);
        validationRegistry.validateAgent(bobAgentId, true);

        vm.prank(bob);
        skillBadge.claimSkill(1);

        ITalentSearch.AgentProfile memory profile = talentSearch.getAgentProfile(bobAgentId);

        assertEq(profile.agentId, bobAgentId);
        assertEq(profile.wallet, bob);
        assertEq(profile.reputation, 5);
        assertEq(profile.reviewCount, 1);
        assertTrue(profile.isValidated);
        assertEq(profile.skillIds.length, 1);
        assertEq(profile.skillIds[0], 1);
    }

    function testSearchAgentsByReputation() public {
        // Setup different reputations
        vm.prank(alice);
        reputationRegistry.submitReview(bobAgentId, 8, "Excellent");

        vm.prank(charlie);
        reputationRegistry.submitReview(bobAgentId, 9, "Amazing");

        vm.prank(bob);
        reputationRegistry.submitReview(aliceAgentId, 3, "Okay");

        ITalentSearch.SearchParams memory params = ITalentSearch.SearchParams({
            keywords: new string[](0),
            skillIds: new uint256[](0),
            skillLevels: new uint256[](0),
            minReputation: 5,
            maxReputation: 10,
            mustBeValidated: false,
            minCompletedJobs: 0,
            maxResults: 10,
            sortBy: ITalentSearch.SortBy.Reputation,
            ascending: false
        });

        ITalentSearch.AgentResult[] memory results = talentSearch.searchAgents(params);

        // Bob should be in results (has reputation ~8.5)
        assertTrue(results.length > 0);
    }

    function testSearchAgentsByValidation() public {
        vm.prank(owner);
        validationRegistry.validateAgent(aliceAgentId, true);

        ITalentSearch.SearchParams memory params = ITalentSearch.SearchParams({
            keywords: new string[](0),
            skillIds: new uint256[](0),
            skillLevels: new uint256[](0),
            minReputation: -10,
            maxReputation: 10,
            mustBeValidated: true,
            minCompletedJobs: 0,
            maxResults: 10,
            sortBy: ITalentSearch.SortBy.Relevance,
            ascending: false
        });

        ITalentSearch.AgentResult[] memory results = talentSearch.searchAgents(params);

        assertEq(results.length, 1);
        assertEq(results[0].agentId, aliceAgentId);
        assertTrue(results[0].isValidated);
    }

    function testSearchAgentsBySkill() public {
        vm.prank(alice);
        skillBadge.claimSkill(1);

        vm.prank(bob);
        skillBadge.claimSkill(2);

        uint256[] memory skillIds = new uint256[](1);
        skillIds[0] = 1;

        uint256[] memory skillLevels = new uint256[](1);
        skillLevels[0] = uint256(ISkillBadge.VerificationLevel.Self);

        ITalentSearch.SearchParams memory params = ITalentSearch.SearchParams({
            keywords: new string[](0),
            skillIds: skillIds,
            skillLevels: skillLevels,
            minReputation: -10,
            maxReputation: 10,
            mustBeValidated: false,
            minCompletedJobs: 0,
            maxResults: 10,
            sortBy: ITalentSearch.SortBy.Relevance,
            ascending: false
        });

        ITalentSearch.AgentResult[] memory results = talentSearch.searchAgents(params);

        assertEq(results.length, 1);
        assertEq(results[0].agentId, aliceAgentId);
    }

    function testAgentMatches() public {
        vm.prank(alice);
        skillBadge.claimSkill(1);

        uint256[] memory skillIds = new uint256[](1);
        skillIds[0] = 1;

        uint256[] memory skillLevels = new uint256[](1);
        skillLevels[0] = uint256(ISkillBadge.VerificationLevel.Self);

        ITalentSearch.SearchParams memory params = ITalentSearch.SearchParams({
            keywords: new string[](0),
            skillIds: skillIds,
            skillLevels: skillLevels,
            minReputation: -10,
            maxReputation: 10,
            mustBeValidated: false,
            minCompletedJobs: 0,
            maxResults: 10,
            sortBy: ITalentSearch.SortBy.Relevance,
            ascending: false
        });

        assertTrue(talentSearch.agentMatches(aliceAgentId, params));
        assertFalse(talentSearch.agentMatches(bobAgentId, params));
    }

    function testUpdateMetadataCache() public {
        string memory newURI = "ipfs://QmNewMetadata/";

        vm.prank(alice);
        talentSearch.updateMetadataCache(aliceAgentId, newURI);

        ITalentSearch.AgentProfile memory profile = talentSearch.getAgentProfile(aliceAgentId);
        assertEq(profile.metadataURI, newURI);
    }

    function testCannotUpdateOtherAgentMetadata() public {
        string memory newURI = "ipfs://QmFake/";

        vm.prank(bob);
        vm.expectRevert();
        talentSearch.updateMetadataCache(aliceAgentId, newURI);
    }

    function testMaxResultsEnforced() public {
        vm.expectRevert(ITalentSearch.SearchLimitExceeded.selector);
        talentSearch.getTopAgents(101);
    }

    function testGetAgentProfileNotFound() public {
        vm.expectRevert(abi.encodeWithSelector(ITalentSearch.AgentNotFound.selector, 999));
        talentSearch.getAgentProfile(999);
    }

    function testFuzzSearchByReputationRange(int256 minRep, int256 maxRep) public {
        // Bound to valid range
        minRep = bound(minRep, -10, 10);
        maxRep = bound(maxRep, -10, 10);

        // Ensure min <= max
        if (minRep > maxRep) {
            (minRep, maxRep) = (maxRep, minRep);
        }

        // Add some reputation
        vm.prank(alice);
        reputationRegistry.submitReview(bobAgentId, 5, "Good");

        ITalentSearch.SearchParams memory params = ITalentSearch.SearchParams({
            keywords: new string[](0),
            skillIds: new uint256[](0),
            skillLevels: new uint256[](0),
            minReputation: minRep,
            maxReputation: maxRep,
            mustBeValidated: false,
            minCompletedJobs: 0,
            maxResults: 10,
            sortBy: ITalentSearch.SortBy.Reputation,
            ascending: false
        });

        ITalentSearch.AgentResult[] memory results = talentSearch.searchAgents(params);

        // If range includes 5, should have results
        if (minRep <= 5 && maxRep >= 5) {
            assertTrue(results.length >= 1);
        }
    }
}
