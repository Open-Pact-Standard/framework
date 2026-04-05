// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/royalty/GuildRoyalty.sol";
import "../contracts/royalty/RoyaltyRegistry.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("MockToken", "MTK") {
        _mint(msg.sender, 1_000_000 * 10**18);
    }
}

contract MockPaymentLedger {
    function recordPayment(
        address payer,
        address recipient,
        address token,
        uint256 amount,
        bytes32 authHash,
        string calldata metadata
    ) external pure returns (uint256) {
        return 0;
    }

    function settlePayment(uint256 paymentId, bytes32 txHash) external pure {}
}

contract GuildRoyaltyTest is Test {
    GuildRoyalty public guild;
    RoyaltyRegistry public registry;
    MockPaymentLedger public mockLedger;
    MockToken public token;

    address governor = address(0x1);
    address maintainer = address(0x1);
    address contribA = address(0x2);
    address contribB = address(0x3);
    address company1 = address(0x4);
    address company2 = address(0x5);
    address guildTreasury = address(0x6);

    uint256 projectId;
    bytes32 contentHash = keccak256("guild-test-project");

    function setUp() public {
        vm.startPrank(maintainer);
        mockLedger = new MockPaymentLedger();
        registry = new RoyaltyRegistry(address(mockLedger));
        guild = new GuildRoyalty(address(registry), governor);

        // Register project
        projectId = registry.registerProject(
            "GuildProject",
            contentHash,
            "ipfs://guild-metadata",
            address(0) // native token for this test
        );

        // Add contributors
        registry.addContributor(projectId, maintainer, "maintainer", 5000);
        registry.addContributor(projectId, contribA, "contribA", 3000);
        registry.addContributor(projectId, contribB, "contribB", 2000);

        // Set pricing (native ETH/FLR)
        registry.setTierPricing(projectId, uint8(RoyaltyRegistry.LicenseTier.Micro), 0.01 ether, address(0));
        registry.setTierPricing(projectId, uint8(RoyaltyRegistry.LicenseTier.Small), 0.1 ether, address(0));
        registry.setTierPricing(projectId, uint8(RoyaltyRegistry.LicenseTier.Enterprise), 1 ether, address(0));

        vm.stopPrank();

        // Set up treasury
        vm.prank(governor);
        guild.setGuildTreasury(guildTreasury);

        // Fund companies
        vm.deal(company1, 10 ether);
        vm.deal(company2, 10 ether);
    }

    // ===== Governance Setup Tests =====

    function test_governanceConfig() public view {
        assertTrue(guild.governanceEnabled());
        assertEq(guild.minQuorumBps(), 400);
        assertEq(guild.treasuryShareBps(), 500);
    }

    function test_registryReference() public view {
        assertEq(address(guild.registry()), address(registry));
    }

    function test_setGuildTreasury() public {
        vm.prank(governor);
        guild.setGuildTreasury(address(0xA));

        assertEq(guild.guildTreasury(), address(0xA));
    }

    function test_setTreasuryShare() public {
        vm.prank(governor);
        guild.setTreasuryShare(1000);

        assertEq(guild.treasuryShareBps(), 1000);
    }

    function test_setTreasuryShare_tooHigh() public {
        vm.expectRevert(GuildRoyalty.InvalidShareBps.selector);
        vm.prank(governor);
        guild.setTreasuryShare(3000);
    }

    // ===== Governance Execution Tests =====

    function test_proposeParamChange() public {
        bytes memory params = abi.encodeWithSignature(
            "setTierPricing(uint256,uint8,uint256,address)",
            projectId,
            0, // Micro tier
            0.05 ether,
            address(0)
        );

        vm.prank(governor);
        bytes32 hash = guild.proposeParamChange(params, 1 days);

        assertTrue(hash != bytes32(0));

        GuildRoyalty.PendingParam memory pending = guild.getPendingParam(hash);
        assertTrue(pending.executed);
    }

    // ===== Guild-to-Guild Reciprocity Tests =====

    function test_linkDerivativeGuild() public {
        vm.prank(governor);
        guild.linkDerivativeGuild(projectId, 99 /* derivative */, 1500);

        GuildRoyalty.GuildLink memory link = guild.getGuildLink(0);
        assertEq(link.sourceProjectId, projectId);
        assertEq(link.derivativeProjectId, 99);
        assertEq(link.royaltyShareBps, 1500);
        assertTrue(link.active);
    }

    function test_linkDerivativeGuild_invalidShare() public {
        vm.prank(governor);
        vm.expectRevert(GuildRoyalty.InvalidShareBps.selector);
        guild.linkDerivativeGuild(projectId, 99, 500); // below 10%
    }

    function test_removeGuildLink() public {
        vm.prank(governor);
        guild.linkDerivativeGuild(projectId, 99, 1500);
        vm.prank(governor);
        guild.removeGuildLink(projectId, 99);

        GuildRoyalty.GuildLink memory link = guild.getGuildLink(0);
        assertFalse(link.active);
    }

    // ===== Treasury Tests =====

    function test_setInvalidTreasury() public {
        vm.expectRevert(GuildRoyalty.ZeroAddress.selector);
        vm.prank(governor);
        guild.setGuildTreasury(address(0));
    }

    function test_nonGovernorCannotSetTreasury() public {
        vm.expectRevert(GuildRoyalty.NotGovernor.selector);
        vm.prank(company1);
        guild.setGuildTreasury(address(0xB));
    }

    // ===== Governance Toggle =====

    function test_toggleGovernance() public {
        vm.prank(governor);
        guild.setGovernanceEnabled(false);

        assertFalse(guild.governanceEnabled());

        // Governance-disabled calls should fail
        vm.expectRevert(GuildRoyalty.GovernanceDisabled.selector);
        vm.prank(governor);
        guild.proposeParamChange(abi.encodePacked(uint256(0)), 1 days);
    }

    // ===== View Functions =====

    function test_getRegistry() public view {
        assertEq(guild.getRegistry(), address(registry));
    }

    function test_getLinksBySource() public {
        vm.prank(governor);
        guild.linkDerivativeGuild(projectId, 99, 1500);

        uint256[] memory links = guild.getLinksBySource(projectId);
        assertEq(links.length, 1);
        assertEq(links[0], 0);
    }
}
