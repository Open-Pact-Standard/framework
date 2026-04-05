// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/search/SkillBadge.sol";
import "../contracts/interfaces/ISkillBadge.sol";
import "../contracts/agents/IdentityRegistry.sol";
import "../contracts/agents/ValidationRegistry.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

// Mocks for testing
contract MockAgentRegistry {
    mapping(address => uint256) private _agentIds;
    mapping(uint256 => address) private _wallets;
    uint256 private _counter;

    function register(string memory) external returns (uint256) {
        _counter++;
        _agentIds[msg.sender] = _counter;
        _wallets[_counter] = msg.sender;
        return _counter;
    }

    function getAgentId(address wallet) external view returns (uint256) {
        return _agentIds[wallet];
    }

    function getAgentWallet(uint256 agentId) external view returns (address) {
        return _wallets[agentId];
    }

    function agentExists(uint256 agentId) external view returns (bool) {
        return _wallets[agentId] != address(0);
    }

    function getTotalAgents() external view returns (uint256) {
        return _counter;
    }
}

contract MockValidationRegistry {
    mapping(uint256 => bool) private _validated;
    mapping(address => bool) private _validators;

    function validateAgent(uint256 agentId, bool status) external {
        _validated[agentId] = status;
    }

    function isAgentValidated(uint256 agentId) external view returns (bool) {
        return _validated[agentId];
    }

    function registerValidator() external {
        _validators[msg.sender] = true;
    }

    function isValidator(address validator) external view returns (bool) {
        return _validators[validator];
    }
}

/**
 * @title SkillBadgeTest
 * @dev Test suite for SkillBadge contract
 */
contract SkillBadgeTest is Test, ERC1155Holder {
    SkillBadge skillBadge;
    MockAgentRegistry agentRegistry;
    MockValidationRegistry validationRegistry;

    address owner = address(0x1);
    address alice = address(0x2);
    address bob = address(0x3);
    address charlie = address(0x4);

    uint256 aliceAgentId;
    uint256 bobAgentId;

    function setUp() public {
        // Deploy mocks as owner
        vm.startPrank(owner);
        agentRegistry = new MockAgentRegistry();
        validationRegistry = new MockValidationRegistry();

        // Deploy SkillBadge
        skillBadge = new SkillBadge(
            "ipfs://QmSkillBadgeMetadata/",
            address(agentRegistry),
            address(validationRegistry)
        );

        // Grant engine role to owner for testing recordBountyCompletion
        skillBadge.grantRole(skillBadge.ENGINE_ROLE(), owner);
        vm.stopPrank();

        // Register agents
        vm.prank(alice);
        aliceAgentId = agentRegistry.register("ipfs://alice");

        vm.prank(bob);
        bobAgentId = agentRegistry.register("ipfs://bob");

        // Register this test contract as an agent for testing
        agentRegistry.register("ipfs://test");
    }

    function testInitialState() public {
        assertEq(address(skillBadge.agentRegistry()), address(agentRegistry));
        assertEq(address(skillBadge.validationRegistry()), address(validationRegistry));
        assertTrue(skillBadge.hasRole(skillBadge.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(skillBadge.hasRole(skillBadge.VALIDATOR_ROLE(), owner));
    }

    function testDefaultSkillsRegistered() public {
        // Check that default skills were registered
        ISkillBadge.Skill memory skill1 = skillBadge.getSkill(1);
        assertEq(skill1.name, "Solidity Development");
        assertEq(skill1.category, "Blockchain");
        assertTrue(skill1.active);

        // The AI skills start after the 5 blockchain skills (IDs 6-10)
        ISkillBadge.Skill memory skill2 = skillBadge.getSkill(6);
        assertEq(skill2.name, "LLM Fine-tuning");
        assertEq(skill2.category, "AI");
        assertTrue(skill2.active);
    }

    function testClaimSkill() public {
        vm.prank(alice);
        skillBadge.claimSkill(1);

        ISkillBadge.AgentSkill memory agentSkill = skillBadge.getAgentSkill(aliceAgentId, 1);

        assertEq(agentSkill.skillId, 1);
        assertEq(uint256(agentSkill.level), uint256(ISkillBadge.VerificationLevel.Self));
        assertEq(agentSkill.endorsedCount, 0);
        assertEq(agentSkill.completedBounties, 0);
    }

    function testClaimSkillEmitsEvent() public {
        vm.expectEmit(true, true, false, true);
        emit ISkillBadge.SkillClaimed(aliceAgentId, 1);

        vm.prank(alice);
        skillBadge.claimSkill(1);
    }

    function testCannotClaimInactiveSkill() public {
        vm.prank(owner);
        skillBadge.deactivateSkill(1);

        vm.prank(alice);
        vm.expectRevert(ISkillBadge.InvalidSkillId.selector);
        skillBadge.claimSkill(1);
    }

    function testEndorseSkill() public {
        // Alice claims skill
        vm.prank(alice);
        skillBadge.claimSkill(1);

        // Bob also claims skill so he can endorse
        vm.prank(bob);
        skillBadge.claimSkill(1);

        // Bob endorses Alice
        vm.prank(bob);
        skillBadge.endorseSkill(aliceAgentId, 1);

        ISkillBadge.AgentSkill memory agentSkill = skillBadge.getAgentSkill(aliceAgentId, 1);

        assertEq(uint256(agentSkill.level), uint256(ISkillBadge.VerificationLevel.Self));
        assertEq(agentSkill.endorsedCount, 1);
    }

    function testEndorseSkillUpgradesToPeerLevel() public {
        // Alice claims skill
        vm.prank(alice);
        skillBadge.claimSkill(1);

        // Bob claims skill
        vm.prank(bob);
        skillBadge.claimSkill(1);

        // Charlie registers and claims skill
        vm.startPrank(charlie);
        uint256 charlieAgentId = agentRegistry.register("ipfs://charlie");
        skillBadge.claimSkill(1);
        vm.stopPrank();

        // Three endorsements should upgrade to Peer level
        vm.prank(bob);
        skillBadge.endorseSkill(aliceAgentId, 1);

        vm.prank(charlie);
        skillBadge.endorseSkill(aliceAgentId, 1);

        // Need a third endorser
        address diane = address(0x5);
        vm.startPrank(diane);
        agentRegistry.register("ipfs://diane");
        skillBadge.claimSkill(1);
        vm.stopPrank();

        vm.prank(diane);
        skillBadge.endorseSkill(aliceAgentId, 1);

        ISkillBadge.AgentSkill memory agentSkill = skillBadge.getAgentSkill(aliceAgentId, 1);

        assertEq(uint256(agentSkill.level), uint256(ISkillBadge.VerificationLevel.Peer));
    }

    function testCannotEndorseSelf() public {
        vm.prank(alice);
        vm.expectRevert(ISkillBadge.CannotEndorseSelf.selector);
        skillBadge.endorseSkill(aliceAgentId, 1);
    }

    function testCannotEndorseWithoutSkill() public {
        vm.prank(alice);
        skillBadge.claimSkill(1);

        // Bob hasn't claimed skill, can't endorse
        vm.prank(bob);
        vm.expectRevert(ISkillBadge.NotAuthorized.selector);
        skillBadge.endorseSkill(aliceAgentId, 1);
    }

    function testCannotDoubleEndorse() public {
        vm.prank(alice);
        skillBadge.claimSkill(1);

        vm.prank(bob);
        skillBadge.claimSkill(1);

        vm.prank(bob);
        skillBadge.endorseSkill(aliceAgentId, 1);

        vm.prank(bob);
        vm.expectRevert(ISkillBadge.AlreadyEndorsed.selector);
        skillBadge.endorseSkill(aliceAgentId, 1);
    }

    function testVerifySkill() public {
        vm.prank(alice);
        skillBadge.claimSkill(1);

        vm.prank(owner);
        skillBadge.verifySkill(aliceAgentId, 1, ISkillBadge.VerificationLevel.Verified);

        ISkillBadge.AgentSkill memory agentSkill = skillBadge.getAgentSkill(aliceAgentId, 1);

        assertEq(uint256(agentSkill.level), uint256(ISkillBadge.VerificationLevel.Verified));
    }

    function testVerifySkillRequiresValidator() public {
        vm.prank(alice);
        skillBadge.claimSkill(1);

        vm.prank(bob);
        vm.expectRevert();
        skillBadge.verifySkill(aliceAgentId, 1, ISkillBadge.VerificationLevel.Verified);
    }

    function testGetAgentsBySkill() public {
        vm.prank(alice);
        skillBadge.claimSkill(1);

        vm.prank(bob);
        skillBadge.claimSkill(1);

        uint256[] memory agents = skillBadge.getAgentsBySkill(
            1,
            ISkillBadge.VerificationLevel.Self
        );

        assertEq(agents.length, 2);
        assertEq(agents[0], aliceAgentId);
        assertEq(agents[1], bobAgentId);
    }

    function testGetAgentsBySkillFiltersByLevel() public {
        vm.prank(alice);
        skillBadge.claimSkill(1);

        vm.prank(bob);
        skillBadge.claimSkill(1);

        vm.prank(owner);
        skillBadge.verifySkill(bobAgentId, 1, ISkillBadge.VerificationLevel.Verified);

        uint256[] memory agents = skillBadge.getAgentsBySkill(
            1,
            ISkillBadge.VerificationLevel.Verified
        );

        assertEq(agents.length, 1);
        assertEq(agents[0], bobAgentId);
    }

    function testGetActiveSkills() public {
        uint256[] memory skills = skillBadge.getActiveSkills();

        assertTrue(skills.length > 0);
        assertEq(skills[0], 1); // First default skill
    }

    function testHasSkillLevel() public {
        vm.prank(alice);
        skillBadge.claimSkill(1);

        assertTrue(skillBadge.hasSkillLevel(aliceAgentId, 1, ISkillBadge.VerificationLevel.Self));
        assertFalse(skillBadge.hasSkillLevel(aliceAgentId, 1, ISkillBadge.VerificationLevel.Peer));
    }

    function testRecordBountyCompletion() public {
        vm.prank(alice);
        skillBadge.claimSkill(1);

        vm.prank(owner);
        skillBadge.recordBountyCompletion(aliceAgentId, 1);

        ISkillBadge.AgentSkill memory agentSkill = skillBadge.getAgentSkill(aliceAgentId, 1);

        assertEq(agentSkill.completedBounties, 1);
        assertEq(skillBadge.getAgentCompletedJobs(aliceAgentId), 1);
    }

    function testTenCompletionsUpgradesToMaster() public {
        // Setup: Verified level
        vm.prank(alice);
        skillBadge.claimSkill(1);

        vm.prank(owner);
        skillBadge.verifySkill(aliceAgentId, 1, ISkillBadge.VerificationLevel.Verified);

        // Record 10 bounties
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(owner);
            skillBadge.recordBountyCompletion(aliceAgentId, 1);
        }

        ISkillBadge.AgentSkill memory agentSkill = skillBadge.getAgentSkill(aliceAgentId, 1);

        assertEq(uint256(agentSkill.level), uint256(ISkillBadge.VerificationLevel.Master));
    }

    function testGetAgentSkills() public {
        vm.startPrank(alice);
        skillBadge.claimSkill(1);
        skillBadge.claimSkill(2);
        skillBadge.claimSkill(6); // First AI skill (LLM Fine-tuning)
        vm.stopPrank();

        uint256[] memory skills = skillBadge.getAgentSkills(aliceAgentId);

        assertEq(skills.length, 3);
        assertEq(skills[0], 1);
        assertEq(skills[1], 2);
        assertEq(skills[2], 6);
    }

    function testRegisterNewSkill() public {
        vm.prank(owner);
        uint256 newSkillId = skillBadge.registerSkill("Test Skill", "Test Category");

        ISkillBadge.Skill memory skill = skillBadge.getSkill(newSkillId);

        assertEq(skill.name, "Test Skill");
        assertEq(skill.category, "Test Category");
        assertTrue(skill.active);
    }

    function testDeactivateSkill() public {
        vm.prank(owner);
        skillBadge.deactivateSkill(1);

        ISkillBadge.Skill memory skill = skillBadge.getSkill(1);
        assertFalse(skill.active);
    }

    function testERC1155BalanceOf() public {
        vm.prank(alice);
        skillBadge.claimSkill(1);

        uint256 balance = skillBadge.balanceOf(alice, 1);
        assertEq(balance, 1); // Level 1 = Self
    }

    function testFuzzEndorseMany(uint256 numEndorsers) public {
        // Bound to reasonable values
        numEndorsers = bound(numEndorsers, 0, 20);

        vm.prank(alice);
        skillBadge.claimSkill(1);

        // Create endorsers
        for (uint256 i = 0; i < numEndorsers; i++) {
            address endorser = address(uint160(100 + i));
            vm.prank(endorser);
            agentRegistry.register("ipfs://endorser");
            vm.prank(endorser);
            skillBadge.claimSkill(1);
            vm.prank(endorser);
            skillBadge.endorseSkill(aliceAgentId, 1);
        }

        ISkillBadge.AgentSkill memory agentSkill = skillBadge.getAgentSkill(aliceAgentId, 1);

        assertEq(agentSkill.endorsedCount, numEndorsers);
    }
}
