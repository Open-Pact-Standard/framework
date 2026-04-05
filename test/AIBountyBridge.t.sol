// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/ai/AIBountyBridge.sol";
import "../contracts/ai/AIAgentRegistry.sol";
import "../contracts/ai/IAIAgentRegistry.sol";
import "../contracts/interfaces/IAIBountyBridge.sol";
import "../contracts/interfaces/IMarketplace.sol";

// Mock Marketplace for testing
contract MockMarketplace {
    mapping(uint256 => IMarketplace.Bounty) private _bounties;

    uint256 private _bountyCount;

    event BountyCreated(uint256 indexed listingId, uint256 reward);

    function createBounty(
        address token,
        uint256 reward,
        string calldata metadata,
        uint256 claimTimeout
    ) external returns (uint256) {
        uint256 listingId = _bountyCount;
        _bountyCount++;

        _bounties[listingId] = IMarketplace.Bounty({
            listingId: listingId,
            agentId: 0,
            creator: msg.sender,
            bountyStatus: IMarketplace.BountyStatus.Open,
            token: token,
            reward: reward,
            claimerAgentId: 0,
            claimer: address(0),
            metadata: metadata,
            createdAt: block.timestamp,
            claimedAt: 0,
            completedAt: 0,
            claimTimeout: claimTimeout,
            claimDeadline: block.timestamp + 30 days
        });

        emit BountyCreated(listingId, reward);
        return listingId;
    }

    function getBounty(uint256 listingId) external view returns (IMarketplace.Bounty memory) {
        return _bounties[listingId];
    }

    function setBountyStatus(uint256 listingId, IMarketplace.BountyStatus status) external {
        _bounties[listingId].bountyStatus = status;
    }
}

// Mock Reputation Registry for testing
contract MockReputationRegistry {
    mapping(uint256 => uint256) private _reputation;

    function getReputation(uint256 agentId) external view returns (
        uint256 reputation,
        uint256 rank,
        uint256 totalValidations
    ) {
        reputation = _reputation[agentId];
        rank = 1;
        totalValidations = 0;
    }

    function setReputation(uint256 agentId, uint256 newReputation) external {
        _reputation[agentId] = newReputation;
    }
}

/**
 * @title AIBountyBridgeTest
 * @dev Test suite for AIBountyBridge contract
 */
contract AIBountyBridgeTest is Test {
    AIBountyBridge bridge;
    AIAgentRegistry aiRegistry;
    MockMarketplace marketplace;
    MockReputationRegistry reputationRegistry;

    address owner = address(0x1);
    address overseer1 = address(0x2);
    address overseer2 = address(0x3);
    address poster = address(0x4);
    address admin = address(0x5);

    uint256 agentId1;
    uint256 agentId2;
    uint256 bountyId;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy AI registry
        aiRegistry = new AIAgentRegistry();

        // Deploy marketplace
        marketplace = new MockMarketplace();

        // Deploy reputation registry
        reputationRegistry = new MockReputationRegistry();

        // Deploy bridge
        bridge = new AIBountyBridge(
            address(marketplace),
            address(aiRegistry),
            address(reputationRegistry)
        );

        // Grant roles
        aiRegistry.grantRole(aiRegistry.SPENDER_ROLE(), address(bridge));
        bridge.grantRole(bridge.DEFAULT_ADMIN_ROLE(), admin);
        bridge.grantRole(bridge.REVIEWER_ROLE(), admin);

        vm.stopPrank();

        // Register AI agents
        vm.prank(overseer1);
        agentId1 = aiRegistry.registerAIAgent(
            "ipfs://agent1",
            IAIAgentRegistry.AgentType.LLM,
            "gpt-4",
            100 ether,
            overseer1
        );

        vm.prank(overseer2);
        agentId2 = aiRegistry.registerAIAgent(
            "ipfs://agent2",
            IAIAgentRegistry.AgentType.Autonomous,
            "claude-3",
            50 ether,
            overseer2
        );

        // Create a bounty
        vm.prank(poster);
        bountyId = marketplace.createBounty(
            address(0), // token placeholder
            10 ether,
            "ipfs://bounty",
            7 days
        );
    }

    // ============ Initial State Tests ============

    function testInitialState() public {
        assertEq(address(bridge.marketplace()), address(marketplace));
        assertEq(address(bridge.aiRegistry()), address(aiRegistry));
        assertEq(address(bridge.reputationRegistry()), address(reputationRegistry));
        assertEq(bridge.reputationMultiplier(), 10000);
    }

    // ============ Claim Bounty Tests ============

    function testClaimBountyForAgent() public {
        vm.prank(overseer1);
        uint256 claimId = bridge.claimBountyForAgent(
            bountyId,
            agentId1,
            "ipfs://proof"
        );

        assertEq(claimId, 1);

        IAIBountyBridge.AIBountyClaim memory claim = bridge.getClaim(claimId);
        assertEq(claim.bountyId, bountyId);
        assertEq(claim.agentId, agentId1);
        assertEq(claim.claimer, overseer1);
        assertEq(claim.workProof, "ipfs://proof");
        assertFalse(claim.approved);
        assertFalse(claim.rejected);
    }

    function testClaimBountyEmitsEvent() public {
        vm.expectEmit(true, true, true, true);
        emit IAIBountyBridge.AIBountyClaimed(
            1,
            bountyId,
            agentId1,
            overseer1,
            "ipfs://proof"
        );

        vm.prank(overseer1);
        bridge.claimBountyForAgent(bountyId, agentId1, "ipfs://proof");
    }

    function testCannotClaimAsNonOverseer() public {
        vm.prank(overseer2);
        vm.expectRevert(IAIBountyBridge.NotOverseer.selector);
        bridge.claimBountyForAgent(bountyId, agentId1, "ipfs://proof");
    }

    function testCannotClaimForNonexistentAgent() public {
        vm.prank(overseer1);
        vm.expectRevert(IAIBountyBridge.NotAIAgent.selector);
        bridge.claimBountyForAgent(bountyId, 999, "ipfs://proof");
    }

    function testCannotClaimForInactiveAgent() public {
        // Deactivate agent
        vm.prank(overseer1);
        aiRegistry.deactivateAgent(agentId1);

        vm.prank(overseer1);
        vm.expectRevert(IAIBountyBridge.NotAIAgent.selector);
        bridge.claimBountyForAgent(bountyId, agentId1, "ipfs://proof");
    }

    function testCannotClaimNonexistentBounty() public {
        vm.prank(overseer1);
        vm.expectRevert(IAIBountyBridge.BountyNotFound.selector);
        bridge.claimBountyForAgent(999, agentId1, "ipfs://proof");
    }

    function testCannotClaimDuplicate() public {
        vm.startPrank(overseer1);
        bridge.claimBountyForAgent(bountyId, agentId1, "ipfs://proof1");

        vm.expectRevert(IAIBountyBridge.ClaimAlreadyExists.selector);
        bridge.claimBountyForAgent(bountyId, agentId1, "ipfs://proof2");
        vm.stopPrank();
    }

    // ============ Approve/Reject Tests ============

    function testApproveClaim() public {
        // Claim the bounty
        vm.prank(overseer1);
        uint256 claimId = bridge.claimBountyForAgent(bountyId, agentId1, "ipfs://proof");

        // Approve as poster
        vm.prank(poster);
        bridge.approveClaim(claimId);

        IAIBountyBridge.AIBountyClaim memory claim = bridge.getClaim(claimId);
        assertTrue(claim.approved);
        assertFalse(claim.rejected);
    }

    function testApproveClaimEmitsEvent() public {
        // Claim the bounty
        vm.prank(overseer1);
        uint256 claimId = bridge.claimBountyForAgent(bountyId, agentId1, "ipfs://proof");

        vm.expectEmit(true, true, true, false);
        emit IAIBountyBridge.AIBountyApproved(claimId, bountyId, agentId1);

        // Approve as poster
        vm.prank(poster);
        bridge.approveClaim(claimId);
    }

    function testRejectClaim() public {
        // Claim the bounty
        vm.prank(overseer1);
        uint256 claimId = bridge.claimBountyForAgent(bountyId, agentId1, "ipfs://proof");

        // Reject as poster
        vm.prank(poster);
        bridge.rejectClaim(claimId, "Insufficient quality");

        IAIBountyBridge.AIBountyClaim memory claim = bridge.getClaim(claimId);
        assertFalse(claim.approved);
        assertTrue(claim.rejected);
    }

    function testRejectClaimEmitsEvent() public {
        // Claim the bounty
        vm.prank(overseer1);
        uint256 claimId = bridge.claimBountyForAgent(bountyId, agentId1, "ipfs://proof");

        vm.expectEmit(true, true, false, true);
        emit IAIBountyBridge.AIBountyRejected(claimId, bountyId, "Insufficient quality");

        // Reject as poster
        vm.prank(poster);
        bridge.rejectClaim(claimId, "Insufficient quality");
    }

    function testCannotApproveAsUnauthorized() public {
        // Claim the bounty
        vm.prank(overseer1);
        uint256 claimId = bridge.claimBountyForAgent(bountyId, agentId1, "ipfs://proof");

        // Try to approve as non-poster, non-admin
        vm.prank(overseer2);
        vm.expectRevert(IAIBountyBridge.Unauthorized.selector);
        bridge.approveClaim(claimId);
    }

    // ============ View Functions Tests ============

    function testGetClaim() public {
        vm.prank(overseer1);
        uint256 claimId = bridge.claimBountyForAgent(bountyId, agentId1, "ipfs://proof");

        IAIBountyBridge.AIBountyClaim memory claim = bridge.getClaim(claimId);
        assertEq(claim.claimId, claimId);
        assertEq(claim.bountyId, bountyId);
        assertEq(claim.agentId, agentId1);
    }

    function testGetClaimNotFound() public {
        vm.expectRevert(IAIBountyBridge.InvalidClaim.selector);
        bridge.getClaim(999);
    }

    function testGetBountyClaims() public {
        vm.prank(overseer1);
        bridge.claimBountyForAgent(bountyId, agentId1, "ipfs://proof");

        vm.prank(overseer2);
        bridge.claimBountyForAgent(bountyId, agentId2, "ipfs://proof");

        uint256[] memory claims = bridge.getBountyClaims(bountyId);
        assertEq(claims.length, 2);
        assertEq(claims[0], 1);
        assertEq(claims[1], 2);
    }

    function testGetAgentClaims() public {
        vm.prank(overseer1);
        bridge.claimBountyForAgent(bountyId, agentId1, "ipfs://proof");

        // Create a second bounty and claim it
        vm.prank(poster);
        uint256 bountyId2 = marketplace.createBounty(
            address(0),
            5 ether,
            "ipfs://bounty2",
            7 days
        );

        vm.prank(overseer1);
        bridge.claimBountyForAgent(bountyId2, agentId1, "ipfs://proof2");

        uint256[] memory claims = bridge.getAgentClaims(agentId1);
        assertEq(claims.length, 2);
    }

    // ============ Reputation Tests ============

    function testSetReputationMultiplier() public {
        vm.prank(owner);
        bridge.setReputationMultiplier(15000); // 1.5x

        assertEq(bridge.reputationMultiplier(), 15000);
    }

    function testCannotSetMultiplierTooLow() public {
        vm.prank(owner);
        vm.expectRevert();
        bridge.setReputationMultiplier(0);
    }

    function testCannotSetMultiplierTooHigh() public {
        vm.prank(owner);
        vm.expectRevert();
        bridge.setReputationMultiplier(20001);
    }

    function testCannotSetMultiplierAsNonOwner() public {
        vm.prank(overseer1);
        vm.expectRevert();
        bridge.setReputationMultiplier(15000);
    }

    function testApproveEmitsReputationEvent() public {
        vm.prank(overseer1);
        uint256 claimId = bridge.claimBountyForAgent(bountyId, agentId1, "ipfs://proof");

        // Set reputation for agent
        reputationRegistry.setReputation(agentId1, 100);

        // Expect both events in order
        vm.expectEmit(true, true, true, true);
        emit IAIBountyBridge.AIBountyApproved(claimId, bountyId, agentId1);

        vm.expectEmit(true, false, false, true);
        emit IAIBountyBridge.AgentReputationUpdated(agentId1, 100, 120); // 100 + 10 + (10 * 10000/10000) = 120

        vm.prank(poster);
        bridge.approveClaim(claimId);
    }

    // ============ Admin Tests ============

    function testAdminHasDefaultAdminRole() public {
        // Verify admin has DEFAULT_ADMIN_ROLE (granted in setUp)
        assertTrue(bridge.hasRole(bridge.DEFAULT_ADMIN_ROLE(), admin), "Admin should have DEFAULT_ADMIN_ROLE");
    }

    function testAdminCanApproveAnyClaim() public {
        // Claim the bounty
        vm.prank(overseer1);
        uint256 claimId = bridge.claimBountyForAgent(bountyId, agentId1, "ipfs://proof");

        // Approve as admin (not poster)
        vm.prank(admin);
        bridge.approveClaim(claimId);

        IAIBountyBridge.AIBountyClaim memory claim = bridge.getClaim(claimId);
        assertTrue(claim.approved);
    }
}
