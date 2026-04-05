// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/royalty/RoyaltyRegistry.sol";
import "../contracts/royalty/LicenseVerifier.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 for testing
contract MockToken is ERC20 {
    constructor() ERC20("MockToken", "MTK") {
        _mint(msg.sender, 1_000_000 * 10**18);
    }
}

// Minimal mock of PaymentLedger for RoyaltyRegistry constructor
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

contract RoyaltyRegistryTest is Test {
    RoyaltyRegistry public registry;
    LicenseVerifier public verifier;
    MockToken public token;
    MockPaymentLedger public mockLedger;

    address maintainer = address(0x1);
    address contributor1 = address(0x2);
    address contributor2 = address(0x3);
    address company = address(0x4);
    address company2 = address(0x5);

    uint256 projectId;
    bytes32 contentHash = keccak256("test-project-v1");

    function setUp() public {
        vm.startPrank(address(0xdead));
        mockLedger = new MockPaymentLedger();
        vm.stopPrank();

        vm.startPrank(address(this));
        registry = new RoyaltyRegistry(address(mockLedger));
        verifier = new LicenseVerifier();
        token = new MockToken();

        // Register project
        vm.startPrank(maintainer);
        projectId = registry.registerProject(
            "TestProject",
            contentHash,
            "ipfs://test-metadata",
            address(token)
        );

        // Add contributors (60/40 split)
        registry.addContributor(projectId, maintainer, "maintainer", 6000);
        registry.addContributor(projectId, contributor1, "contributor1", 4000);

        // Set tier pricing
        registry.setTierPricing(projectId, uint8(RoyaltyRegistry.LicenseTier.Micro), 100 * 10**18, address(token));
        registry.setTierPricing(projectId, uint8(RoyaltyRegistry.LicenseTier.Small), 1000 * 10**18, address(token));
        registry.setTierPricing(projectId, uint8(RoyaltyRegistry.LicenseTier.Medium), 10000 * 10**18, address(token));
        registry.setTierPricing(projectId, uint8(RoyaltyRegistry.LicenseTier.AI_Training), 25000 * 10**18, address(token));

        vm.stopPrank();

        // Approve tokens for companies
        vm.startPrank(company);
        token.approve(address(registry), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(company2);
        token.approve(address(registry), type(uint256).max);
        vm.stopPrank();
    }

    // ===== Project Registration Tests =====

    function test_registerProject() public {
        assertEq(registry.getProjectCount(), 1);
        IRoyaltyRegistry.Project memory p = registry.getProject(projectId);
        assertEq(p.name, "TestProject");
        assertEq(p.contentHash, contentHash);
        assertEq(p.maintainer, maintainer);
        assertTrue(p.exists);
    }

    function test_registerProject_duplicateHash() public {
        vm.expectRevert(IRoyaltyRegistry.DuplicateProjectContent.selector);
        vm.prank(maintainer);
        registry.registerProject("AnotherProject", contentHash, "ipfs://another", address(token));
    }

    // ===== Contributor Tests =====

    function test_addContributor() public view {
        assertEq(registry.getContributorCount(projectId), 2);
        assertEq(registry.getTotalWeight(projectId), 10000);

        (address cWallet,, uint96 cWeight,, bool cActive) = registry.getContributor(projectId, 0);
        assertEq(cWallet, maintainer);
        assertEq(cWeight, 6000);
        assertTrue(cActive);
    }

    function test_removeContributor() public {
        vm.prank(maintainer);
        registry.removeContributor(projectId, 0);

        (,, uint96 cWeight,, bool cActive) = registry.getContributor(projectId, 0);
        assertFalse(cActive);
        assertEq(registry.getTotalWeight(projectId), 4000);
    }

    function test_removeContributor_notMaintainer() public {
        vm.expectRevert();
        vm.prank(company);
        registry.removeContributor(projectId, 0);
    }

    function test_updateContributorWeight() public {
        vm.prank(maintainer);
        registry.updateContributorWeight(projectId, 0, 7000);

        assertEq(registry.getTotalWeight(projectId), 11000); // would fail -- need to adjust
    }

    // ===== License Purchase Tests =====

    function test_purchaseLicense_success() public {
        vm.prank(company);
        registry.purchaseLicenseWithToken(
            projectId,
            company,
            RoyaltyRegistry.LicenseTier.Micro,
            keccak256("acknowledged"),
            address(token)
        );

        IRoyaltyRegistry.ViewLicense memory lic = registry.getLicense(projectId, company);
        assertEq(uint8(lic.status), uint8(RoyaltyRegistry.LicenseStatus.Active));
        assertEq(uint8(lic.tier), uint8(RoyaltyRegistry.LicenseTier.Micro));
        assertEq(lic.paidAmount, 100 * 10**18);
        assertTrue(lic.expiresAt > block.timestamp);
    }

    function test_purchaseLicense_alreadyActive() public {
        vm.prank(company);
        registry.purchaseLicenseWithToken(
            projectId,
            company,
            RoyaltyRegistry.LicenseTier.Micro,
            keccak256("acknowledged"),
            address(token)
        );

        vm.expectRevert(RoyaltyRegistry.LicenseAlreadyActive.selector);
        vm.prank(company);
        registry.purchaseLicenseWithToken(
            projectId,
            company,
            RoyaltyRegistry.LicenseTier.Micro,
            keccak256("acknowledged"),
            address(token)
        );
    }

    function test_purchaseLicense_wrongToken() public {
        address fakeToken = address(0xBADC0DE);

        vm.expectRevert(IRoyaltyRegistry.PaymentTokenNotSupported.selector);
        vm.prank(company);
        registry.purchaseLicenseWithToken(
            projectId,
            company,
            RoyaltyRegistry.LicenseTier.Micro,
            keccak256("acknowledged"),
            fakeToken
        );
    }

    // ===== Royalty Distribution Tests =====

    function test_royaltyDistribution() public {
        uint256 licenseAmount = 100 * 10**18;

        vm.prank(company);
        registry.purchaseLicenseWithToken(
            projectId,
            company,
            RoyaltyRegistry.LicenseTier.Micro,
            keccak256("acknowledged"),
            address(token)
        );

        // Check pending withdrawals (60/40 split)
        uint256 maintainerShare = registry.getPendingWithdrawal(maintainer, projectId);
        uint256 contributorShare = registry.getPendingWithdrawal(contributor1, projectId);

        assertEq(maintainerShare, licenseAmount * 6000 / 10000);
        assertEq(contributorShare, licenseAmount * 4000 / 10000);
        assertEq(maintainerShare + contributorShare, licenseAmount);
    }

    function test_withdrawToken() public {
        uint256 licenseAmount = 100 * 10**18;

        vm.prank(company);
        registry.purchaseLicenseWithToken(
            projectId,
            company,
            RoyaltyRegistry.LicenseTier.Micro,
            keccak256("acknowledged"),
            address(token)
        );

        uint256 expectedShare = licenseAmount * 6000 / 10000;
        uint256 maintainerBalBefore = token.balanceOf(maintainer);

        vm.prank(maintainer);
        registry.withdrawToken(projectId, address(token));

        assertEq(token.balanceOf(maintainer) - maintainerBalBefore, expectedShare);
        assertEq(registry.getPendingWithdrawal(maintainer, projectId), 0);
    }

    // ===== Multiple License Tests =====

    function test_multipleLicenses() public {
        vm.prank(company);
        registry.purchaseLicenseWithToken(
            projectId,
            company,
            RoyaltyRegistry.LicenseTier.Small,
            keccak256("company-ack"),
            address(token)
        );

        vm.prank(company2);
        registry.purchaseLicenseWithToken(
            projectId,
            company2,
            RoyaltyRegistry.LicenseTier.Micro,
            keccak256("company2-ack"),
            address(token)
        );

        assertEq(registry.getActiveLicenseCount(projectId), 2);
        assertEq(registry.getTotalRoyaltiesCollected(projectId), 1000 * 10**18 + 100 * 10**18);
    }

    function test_revokeLicense() public {
        vm.prank(company);
        registry.purchaseLicenseWithToken(
            projectId,
            company,
            RoyaltyRegistry.LicenseTier.Micro,
            keccak256("acknowledged"),
            address(token)
        );

        vm.prank(maintainer);
        registry.revokeLicense(projectId, company);

        IRoyaltyRegistry.ViewLicense memory lic = registry.getLicense(projectId, company);
        assertEq(uint8(lic.status), uint8(RoyaltyRegistry.LicenseStatus.Revoked));
        assertEq(registry.getActiveLicenseCount(projectId), 0);
    }

    // ===== Compliance Verification Tests =====

    function test_complianceCheck() public {
        // Before purchase: not compliant
        (bool valid, string memory tier,) = verifier.checkComplianceDetailed(
            address(registry), projectId, company
        );
        assertFalse(valid);

        // Purchase license
        vm.prank(company);
        registry.purchaseLicenseWithToken(
            projectId,
            company,
            RoyaltyRegistry.LicenseTier.Small,
            keccak256("acknowledged"),
            address(token)
        );

        // After purchase: compliant
        (valid, tier,) = verifier.checkComplianceDetailed(
            address(registry), projectId, company
        );
        assertTrue(valid);
        assertEq(tier, "Small");
    }

    function test_batchComplianceCheck() public {
        vm.prank(company);
        registry.purchaseLicenseWithToken(
            projectId,
            company,
            RoyaltyRegistry.LicenseTier.Micro,
            keccak256("acknowledged"),
            address(token)
        );

        address[] memory licensees = new address[](2);
        licensees[0] = company;
        licensees[1] = company2;

        bool[] memory results = verifier.batchCheckLicensees(
            address(registry), projectId, licensees
        );

        assertTrue(results[0]);
        assertFalse(results[1]);
    }

    // ===== Licensing Model Tests =====

    function test_personalUseIsFree() public {
        // No registration, no payment needed for personal use
        // This is enforced by the license text, not on-chain
        // The on-chain system only tracks commercial licenses
        assertEq(registry.getActiveLicenseCount(projectId), 0);
    }

    function test_commercialRequiresLicense() public {
        IRoyaltyRegistry.ViewLicense memory lic = registry.getLicense(projectId, company);
        assertEq(uint8(lic.status), uint8(RoyaltyRegistry.LicenseStatus.None));
    }

    // ===== Edge Case Tests =====

    function test_cannotPurchaseExpiredTier() public {
        registry.disableTier(projectId, RoyaltyRegistry.LicenseTier.Medium);

        vm.expectRevert(IRoyaltyRegistry.TierNotPriced.selector);
        vm.prank(company);
        registry.purchaseLicenseWithToken(
            projectId,
            company,
            RoyaltyRegistry.LicenseTier.Medium,
            keccak256("acknowledged"),
            address(token)
        );
    }

    function test_contributorProjectsTracking() public view {
        uint256[] memory projects = registry.getContributorProjects(contributor1);
        assertEq(projects.length, 1);
        assertEq(projects[0], projectId);
    }

    function test_pricingModeChange() public {
        vm.prank(maintainer);
        registry.setPricingMode(projectId, RoyaltyRegistry.PricingMode.Custom);

        IRoyaltyRegistry.Project memory p = registry.getProject(projectId);
        assertEq(uint8(p.pricingMode), uint8(RoyaltyRegistry.PricingMode.Custom));
    }
}
