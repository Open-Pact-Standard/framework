// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/search/RecommendationEngine.sol";
import "../contracts/search/SkillBadge.sol";
import "../contracts/interfaces/ISkillBadge.sol";
import "../contracts/agents/IdentityRegistry.sol";
import "../contracts/agents/ReputationRegistry.sol";
import "../contracts/agents/ValidationRegistry.sol";

/**
 * @title RecommendationEngineTest
 * @dev Test suite for RecommendationEngine contract
 */
contract RecommendationEngineTest is Test {
    RecommendationEngine engine;
    SkillBadge skillBadge;
    IdentityRegistry identityRegistry;
    ReputationRegistry reputationRegistry;

    address owner = address(0x1);
    address marketplace = address(0x2);
    address alice = address(0x3);
    address bob = address(0x4);
    address charlie = address(0x5);

    uint256 aliceAgentId;
    uint256 bobAgentId;
    uint256 charlieAgentId;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy core registries
        identityRegistry = new IdentityRegistry();
        reputationRegistry = new ReputationRegistry();

        // Deploy SkillBadge (needs validation registry, but we can skip for now)
        ValidationRegistry validationRegistry = new ValidationRegistry();
        skillBadge = new SkillBadge(
            "ipfs://QmTest/",
            address(identityRegistry),
            address(validationRegistry)
        );

        // Deploy RecommendationEngine
        engine = new RecommendationEngine(
            address(identityRegistry),
            address(reputationRegistry),
            address(skillBadge)
        );

        // Grant marketplace role
        engine.grantMarketplaceRole(marketplace);

        vm.stopPrank();

        // Register agents
        vm.prank(alice);
        aliceAgentId = identityRegistry.register("ipfs://alice");

        vm.prank(bob);
        bobAgentId = identityRegistry.register("ipfs://bob");

        vm.prank(charlie);
        charlieAgentId = identityRegistry.register("ipfs://charlie");
    }

    function testInitialState() public {
        assertEq(address(engine.agentRegistry()), address(identityRegistry));
        assertEq(address(engine.reputationRegistry()), address(reputationRegistry));
        assertEq(address(engine.skillBadge()), address(skillBadge));
        assertEq(engine.weightSkillMatch(), 4000);
        assertEq(engine.weightReputation(), 2500);
        assertEq(engine.weightAvailability(), 2000);
        assertEq(engine.weightPriceFit(), 1500);
    }

    function testSetAvailability() public {
        vm.prank(alice);
        engine.setAvailability(5, true);

        IRecommendationEngine.AgentAvailability memory avail = engine.getAgentAvailability(aliceAgentId);

        assertEq(avail.capacity, 5);
        assertTrue(avail.isAvailable);
        assertEq(avail.currentBounties, 0);
    }

    function testSetAvailabilityEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit IRecommendationEngine.AvailabilitySet(aliceAgentId, true, 3);

        vm.prank(alice);
        engine.setAvailability(3, true);
    }

    function testSetAvailabilityInvalidCapacity() public {
        vm.prank(alice);
        vm.expectRevert(IRecommendationEngine.InvalidCapacity.selector);
        engine.setAvailability(0, true);

        vm.prank(alice);
        vm.expectRevert(IRecommendationEngine.InvalidCapacity.selector);
        engine.setAvailability(11, true);
    }

    function testGetRecommendations() public {
        // Setup: Alice has Solidity skill
        vm.prank(alice);
        skillBadge.claimSkill(1); // Solidity

        vm.prank(alice);
        engine.setAvailability(3, true);

        // Create bounty requirements
        uint256[] memory requiredSkills = new uint256[](1);
        requiredSkills[0] = 1;

        uint256[] memory minLevels = new uint256[](1);
        minLevels[0] = uint256(ISkillBadge.VerificationLevel.Self);

        IRecommendationEngine.BountyRequirements memory requirements = IRecommendationEngine.BountyRequirements({
            bountyId: 1,
            title: "Smart Contract Audit",
            description: "Audit our DeFi protocol",
            requiredSkills: requiredSkills,
            minLevels: minLevels,
            budget: 1000 ether,
            deadline: block.timestamp + 30 days,
            isActive: true
        });

        IRecommendationEngine.MatchResult[] memory results = engine.getRecommendations(requirements, 10);

        assertEq(results.length, 1);
        assertEq(results[0].agentId, aliceAgentId);
        assertTrue(results[0].score > 0);
    }

    function testGetRecommendationsOnlyAvailableAgents() public {
        // Alice has skill but is unavailable
        vm.prank(alice);
        skillBadge.claimSkill(1);

        vm.prank(alice);
        engine.setAvailability(3, false); // Not available

        uint256[] memory requiredSkills = new uint256[](1);
        requiredSkills[0] = 1;

        uint256[] memory minLevels = new uint256[](1);
        minLevels[0] = uint256(ISkillBadge.VerificationLevel.Self);

        IRecommendationEngine.BountyRequirements memory requirements = IRecommendationEngine.BountyRequirements({
            bountyId: 1,
            title: "Smart Contract Audit",
            description: "Audit our DeFi protocol",
            requiredSkills: requiredSkills,
            minLevels: minLevels,
            budget: 1000 ether,
            deadline: block.timestamp + 30 days,
            isActive: true
        });

        IRecommendationEngine.MatchResult[] memory results = engine.getRecommendations(requirements, 10);

        // No results because Alice is unavailable
        assertEq(results.length, 0);
    }

    function testGetRecommendationsRespectsCapacity() public {
        // Alice has skill and is at capacity
        vm.prank(alice);
        skillBadge.claimSkill(1);

        vm.prank(alice);
        engine.setAvailability(1, true); // Capacity of 1

        // Assign a bounty (simulating marketplace)
        vm.prank(marketplace);
        engine.recordBountyAssignment(aliceAgentId, 999);

        uint256[] memory requiredSkills = new uint256[](1);
        requiredSkills[0] = 1;

        uint256[] memory minLevels = new uint256[](1);
        minLevels[0] = uint256(ISkillBadge.VerificationLevel.Self);

        IRecommendationEngine.BountyRequirements memory requirements = IRecommendationEngine.BountyRequirements({
            bountyId: 1,
            title: "Smart Contract Audit",
            description: "Audit our DeFi protocol",
            requiredSkills: requiredSkills,
            minLevels: minLevels,
            budget: 1000 ether,
            deadline: block.timestamp + 30 days,
            isActive: true
        });

        IRecommendationEngine.MatchResult[] memory results = engine.getRecommendations(requirements, 10);

        // No results because Alice is at capacity
        assertEq(results.length, 0);
    }

    function testCalculateMatchScore() public {
        // Setup: Alice has high reputation
        vm.prank(bob);
        reputationRegistry.submitReview(aliceAgentId, 8, "Great work");

        vm.prank(alice);
        skillBadge.claimSkill(1);

        vm.prank(alice);
        engine.setAvailability(3, true);

        uint256[] memory requiredSkills = new uint256[](1);
        requiredSkills[0] = 1;

        uint256[] memory minLevels = new uint256[](1);
        minLevels[0] = uint256(ISkillBadge.VerificationLevel.Self);

        IRecommendationEngine.BountyRequirements memory requirements = IRecommendationEngine.BountyRequirements({
            bountyId: 1,
            title: "Smart Contract Audit",
            description: "Audit our DeFi protocol",
            requiredSkills: requiredSkills,
            minLevels: minLevels,
            budget: 1000 ether,
            deadline: block.timestamp + 30 days,
            isActive: true
        });

        uint256 score = engine.calculateMatchScore(aliceAgentId, requirements);

        assertTrue(score > 0);
        assertTrue(score <= 10000);
    }

    function testGetScoreBreakdown() public {
        vm.prank(bob);
        reputationRegistry.submitReview(aliceAgentId, 5, "Good");

        vm.prank(alice);
        skillBadge.claimSkill(1);

        vm.prank(alice);
        engine.setAvailability(3, true);

        uint256[] memory requiredSkills = new uint256[](1);
        requiredSkills[0] = 1;

        uint256[] memory minLevels = new uint256[](1);
        minLevels[0] = uint256(ISkillBadge.VerificationLevel.Self);

        IRecommendationEngine.BountyRequirements memory requirements = IRecommendationEngine.BountyRequirements({
            bountyId: 1,
            title: "Smart Contract Audit",
            description: "Audit our DeFi protocol",
            requiredSkills: requiredSkills,
            minLevels: minLevels,
            budget: 1000 ether,
            deadline: block.timestamp + 30 days,
            isActive: true
        });

        (
            uint256 skillMatch,
            uint256 reputation,
            uint256 availability,
            uint256 priceFit
        ) = engine.getScoreBreakdown(aliceAgentId, requirements);

        assertTrue(skillMatch > 0);
        assertTrue(reputation > 0);
        assertTrue(availability > 0);
        assertTrue(priceFit > 0);
    }

    function testRecordBountyAssignment() public {
        vm.prank(alice);
        engine.setAvailability(3, true);

        vm.prank(marketplace);
        engine.recordBountyAssignment(aliceAgentId, 100);

        uint256[] memory activeBounties = engine.getActiveBounties(aliceAgentId);
        assertEq(activeBounties.length, 1);
        assertEq(activeBounties[0], 100);

        assertEq(engine.getBountyAgent(100), aliceAgentId);

        IRecommendationEngine.AgentAvailability memory avail = engine.getAgentAvailability(aliceAgentId);
        assertEq(avail.currentBounties, 1);
    }

    function testRecordBountyCompletion() public {
        vm.prank(alice);
        engine.setAvailability(3, true);

        vm.prank(marketplace);
        engine.recordBountyAssignment(aliceAgentId, 100);

        vm.prank(marketplace);
        engine.recordBountyCompletion(aliceAgentId, 100);

        uint256[] memory activeBounties = engine.getActiveBounties(aliceAgentId);
        assertEq(activeBounties.length, 0);

        assertEq(engine.getBountyAgent(100), 0);
        assertEq(engine.getCompletionCount(aliceAgentId), 1);
    }

    function testRecordBountyAssignmentAlreadyAssigned() public {
        vm.prank(marketplace);
        engine.recordBountyAssignment(aliceAgentId, 100);

        vm.prank(marketplace);
        vm.expectRevert(IRecommendationEngine.BountyAlreadyAssigned.selector);
        engine.recordBountyAssignment(bobAgentId, 100);
    }

    function testRecordBountyCompletionOnlyMarketplace() public {
        vm.prank(owner);
        vm.expectRevert();
        engine.recordBountyCompletion(aliceAgentId, 100);
    }

    function testSetWeights() public {
        vm.prank(owner);
        engine.setWeights(5000, 2000, 2000, 1000);

        assertEq(engine.weightSkillMatch(), 5000);
        assertEq(engine.weightReputation(), 2000);
        assertEq(engine.weightAvailability(), 2000);
        assertEq(engine.weightPriceFit(), 1000);
    }

    function testSetWeightsMustSumTo10000() public {
        vm.prank(owner);
        vm.expectRevert();
        engine.setWeights(5000, 2000, 2000, 2000); // Sum = 11000
    }

    function testSetMaxRecommendations() public {
        vm.prank(owner);
        engine.setMaxRecommendations(50);

        assertEq(engine.maxRecommendations(), 50);
    }

    function testGetRecommendedBounties() public {
        vm.prank(alice);
        skillBadge.claimSkill(1);

        uint256[] memory bountyIds = new uint256[](3);
        bountyIds[0] = 1;
        bountyIds[1] = 2;
        bountyIds[2] = 3;

        uint256[] memory recommended = engine.getRecommendedBounties(aliceAgentId, bountyIds, 10);

        // Should return some ordering (simplified scoring)
        assertEq(recommended.length, 3);
    }

    function testFuzzAvailabilityCapacity(uint256 capacity) public {
        capacity = bound(capacity, 1, 10);

        vm.prank(alice);
        engine.setAvailability(capacity, true);

        IRecommendationEngine.AgentAvailability memory avail = engine.getAgentAvailability(aliceAgentId);

        assertEq(avail.capacity, capacity);
    }

    function testFuzzMultipleAssignments(uint256 numAssignments) public {
        numAssignments = bound(numAssignments, 1, 10);

        vm.prank(alice);
        engine.setAvailability(numAssignments, true);

        // Assign bounties up to capacity
        for (uint256 i = 0; i < numAssignments; i++) {
            vm.prank(marketplace);
            engine.recordBountyAssignment(aliceAgentId, i);
        }

        IRecommendationEngine.AgentAvailability memory avail = engine.getAgentAvailability(aliceAgentId);
        assertEq(avail.currentBounties, numAssignments);

        uint256[] memory activeBounties = engine.getActiveBounties(aliceAgentId);
        assertEq(activeBounties.length, numAssignments);
    }
}
