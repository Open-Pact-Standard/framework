// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../core/contracts/canary/CanaryRegistry.sol";
import "../core/contracts/royalty/RoyaltyRegistry.sol";
import "../core/contracts/interfaces/IPaymentLedger.sol";

// Minimal mock for IPaymentLedger
contract MockPaymentLedger is IPaymentLedger {
    function recordPayment(
        address payer,
        address recipient,
        address token,
        uint256 amount,
        string calldata description,
        uint256 projectId
    ) external returns (uint256) {
        return 1;
    }

    function settlePayment(uint256 paymentId) external {}

    function getPayment(uint256 paymentId) external pure returns (
        address payer,
        address recipient,
        address token,
        uint256 amount,
        string memory description,
        uint256 projectId,
        bool settled,
        bool x402,
        uint256 settledAt
    ) {
        return (address(0), address(0), address(0), 0, "", 0, true, false, 0);
    }

    function getPaymentCount() external pure returns (uint256) { return 0; }

    function getPaymentsByPayer(address) external pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](0);
        return result;
    }

    function getPaymentsByRecipient(address) external pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](0);
        return result;
    }

    function getPaymentsByProjectId(uint256) external pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](0);
        return result;
    }

    function getSettledPayments() external pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](0);
        return result;
    }

    function getUnsettledPayments() external pure returns (uint256[] memory) {
        uint256[] memory result = new uint256[](0);
        return result;
    }

    function getTotalVolume() external pure returns (uint256) { return 0; }

    function getVersion() external pure returns (string memory) { return ""; }
}

contract CanaryRegistryTest is Test {
    RoyaltyRegistry public registry;
    MockPaymentLedger public mockLedger;
    CanaryRegistry public canary;

    address public steward = address(0x111);
    address public licensee = address(0x222);
    address public randomUser = address(0x333);
    address public accused = address(0xDEAD);

    uint256 public projectId;
    bytes32 public distributionId = keccak256("dist-001");

    // Merkle tree leaves for testing
    // leaf[i] = keccak256(secret || projectId || distributionId || i)
    bytes32[] public leaves;

    function setUp() public {
        // Deploy mock ledger
        mockLedger = new MockPaymentLedger();

        // Deploy RoyaltyRegistry
        registry = new RoyaltyRegistry(address(mockLedger));

        // Deploy CanaryRegistry
        canary = new CanaryRegistry(address(registry));

        // Register a project
        vm.prank(steward);
        projectId = registry.registerProject(
            "TestProject",
            keccak256("test-content"),
            "https://example.com/test",
            address(0) // native token
        );

        // Build Merkle tree with 4 canary secrets
        leaves = new bytes32[](4);
        leaves[0] = computeLeaf("canary_var_x7f3a", projectId, distributionId, 0);
        leaves[1] = computeLeaf("canary_dead_code_block_92c1", projectId, distributionId, 1);
        leaves[2] = computeLeaf("canary_control_flow_marker_k8", projectId, distributionId, 2);
        leaves[3] = computeLeaf("canary_data_watermark_m44z", projectId, distributionId, 3);
    }

    function computeLeaf(
        string memory secret,
        uint256 _projectId,
        bytes32 _distributionId,
        uint256 leafIndex
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(secret, _projectId, _distributionId, leafIndex));
    }

    bytes32 merkleRoot;

    function buildMerkleRoot() internal returns (bytes32) {
        // Simple 4-leaf Merkle tree
        // Level 1: hash(left0, left1), hash(left2, left3)
        // Level 2: hash(root0, root1)
        bytes32 hash0 = keccak256(abi.encodePacked(leaves[0], leaves[1]));
        bytes32 hash1 = keccak256(abi.encodePacked(leaves[2], leaves[3]));
        merkleRoot = keccak256(abi.encodePacked(hash0, hash1));
        return merkleRoot;
    }

    // ================================================================
    // DISTRIBUTION REGISTRATION TESTS
    // ================================================================

    function test_RegisterDistribution() public {
        buildMerkleRoot();

        vm.prank(steward);
        canary.registerDistribution(projectId, distributionId, merkleRoot, licensee);

        ICanaryRegistry.DistributionCommitment memory dist = canary.getDistribution(distributionId);
        assertEq(dist.merkleRoot, merkleRoot);
        assertEq(dist.projectId, projectId);
        assertEq(dist.distributionId, distributionId);
        assertEq(dist.issuedTo, licensee);
        assertEq(dist.registeredBy, steward);
        assertEq(dist.isReported, false);
        assertTrue(dist.registeredAt > 0);
    }

    function test_RegisterDistributionNonStewardFails() public {
        buildMerkleRoot();

        vm.prank(randomUser);
        vm.expectRevert(abi.encodeWithSelector(ICanaryRegistry.NotAuthorized.selector, randomUser, projectId));
        canary.registerDistribution(projectId, distributionId, merkleRoot, licensee);
    }

    function test_RegisterDistributionDuplicateFails() public {
        buildMerkleRoot();

        vm.prank(steward);
        canary.registerDistribution(projectId, distributionId, merkleRoot, licensee);

        vm.prank(steward);
        vm.expectRevert(abi.encodeWithSelector(ICanaryRegistry.DistributionAlreadyRegistered.selector, distributionId));
        canary.registerDistribution(projectId, distributionId, merkleRoot, licensee);
    }

    function test_RegisterDistributionZeroMerkleRootFails() public {
        vm.prank(steward);
        vm.expectRevert(ICanaryRegistry.ZeroMerkleRoot.selector);
        canary.registerDistribution(projectId, distributionId, bytes32(0), licensee);
    }

    function test_RegisterDistributionInvalidProjectFails() public {
        buildMerkleRoot();

        vm.prank(steward);
        vm.expectRevert(ICanaryRegistry.ProjectNotFound.selector);
        canary.registerDistribution(9999, distributionId, merkleRoot, licensee);
    }

    function test_RegisterDistributionPublic() public {
        buildMerkleRoot();

        vm.prank(steward);
        canary.registerDistribution(projectId, distributionId, merkleRoot, address(0));

        ICanaryRegistry.DistributionCommitment memory dist = canary.getDistribution(distributionId);
        assertEq(dist.issuedTo, address(0));
    }

    // ================================================================
    // CANARY MATCH REPORTING TESTS
    // ================================================================

    function test_ReportCanaryMatch() public {
        buildMerkleRoot();

        // Register distribution
        vm.prank(steward);
        canary.registerDistribution(projectId, distributionId, merkleRoot, licensee);

        // Build Merkle proof for leaf 0
        // Proof: hash of sibling (leaf 1), then hash of sibling (hash1)
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leaves[1];
        proof[1] = keccak256(abi.encodePacked(leaves[2], leaves[3]));

        // Report the matchResult
        vm.prank(steward);
        canary.reportCanaryMatch(
            distributionId,
            "canary_var_x7f3a",
            0,
            proof,
            accused,
            keccak256("evidence-diff-hash")
        );

        // Verify distribution is now reported
        ICanaryRegistry.DistributionCommitment memory dist = canary.getDistribution(distributionId);
        assertEq(dist.isReported, true);
        assertEq(dist.reportedAgainst, accused);
        assertTrue(dist.reportedAt > 0);

        // Verify the matchResult report
        ICanaryRegistry.CanaryMatchReport memory matchResult = canary.getCanaryMatch(distributionId, 0);
        assertEq(matchResult.canarySecret, "canary_var_x7f3a");
        assertEq(matchResult.leafIndex, 0);
        assertEq(matchResult.accusedParty, accused);
        assertEquals(matchResult.evidenceHash, keccak256("evidence-diff-hash"));
    }

    function test_ReportCanaryMatchInvalidProofFails() public {
        buildMerkleRoot();

        vm.prank(steward);
        canary.registerDistribution(projectId, distributionId, merkleRoot, licensee);

        // Wrong Merkle proof
        bytes32[] memory badProof = new bytes32[](2);
        badProof[0] = keccak256("wrong-sibling");
        badProof[1] = keccak256("another-wrong");

        vm.prank(steward);
        vm.expectRevert(ICanaryRegistry.InvalidMerkleProof.selector);
        canary.reportCanaryMatch(
            distributionId,
            "canary_var_x7f3a",
            0,
            badProof,
            accused,
            keccak256("evidence-hash")
        );
    }

    function test_ReportCanaryMatchTwiceFails() public {
        buildMerkleRoot();

        vm.prank(steward);
        canary.registerDistribution(projectId, distributionId, merkleRoot, licensee);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leaves[1];
        proof[1] = keccak256(abi.encodePacked(leaves[2], leaves[3]));

        vm.prank(steward);
        canary.reportCanaryMatch(
            distributionId,
            "canary_var_x7f3a",
            0,
            proof,
            accused,
            keccak256("evidence-hash")
        );

        // Second report of same canary should fail
        vm.prank(steward);
        vm.expectRevert(abi.encodeWithSelector(ICanaryRegistry.AlreadyReported.selector, distributionId, 0));
        canary.reportCanaryMatch(
            distributionId,
            "canary_var_x7f3a",
            0,
            proof,
            accused,
            keccak256("evidence-hash")
        );
    }

    function test_ReportCanaryMatchUnregisteredFails() public {
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leaves[1];
        proof[1] = keccak256(abi.encodePacked(leaves[2], leaves[3]));

        vm.expectRevert(abi.encodeWithSelector(ICanaryRegistry.DistributionNotFound.selector, distributionId));
        canary.reportCanaryMatch(
            distributionId,
            "canary_var_x7f3a",
            0,
            proof,
            accused,
            keccak256("evidence-hash")
        );
    }

    // ================================================================
    // VERIFICATION TESTS
    // ================================================================

    function test_VerifyCanary() public {
        buildMerkleRoot();

        vm.prank(steward);
        canary.registerDistribution(projectId, distributionId, merkleRoot, licensee);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leaves[1];
        proof[1] = keccak256(abi.encodePacked(leaves[2], leaves[3]));

        bool valid = canary.verifyCanary(
            distributionId,
            "canary_var_x7f3a",
            0,
            proof
        );
        assertEq(valid, true);
    }

    function test_VerifyCanaryWrongSecret() public {
        buildMerkleRoot();

        vm.prank(steward);
        canary.registerDistribution(projectId, distributionId, merkleRoot, licensee);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leaves[1];
        proof[1] = keccak256(abi.encodePacked(leaves[2], leaves[3]));

        bool valid = canary.verifyCanary(
            distributionId,
            "wrong_canary_secret",
            0,
            proof
        );
        assertEq(valid, false);
    }

    function test_VerifyCanaryUnregisteredDistribution() public {
        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leaves[1];
        proof[1] = keccak256(abi.encodePacked(leaves[2], leaves[3]));

        bool valid = canary.verifyCanary(
            distributionId,
            "canary_var_x7f3a",
            0,
            proof
        );
        assertEq(valid, false);
    }

    // ================================================================
    // UNREGISTER TESTS
    // ================================================================

    function test_UnregisterDistribution() public {
        buildMerkleRoot();

        vm.prank(steward);
        canary.registerDistribution(projectId, distributionId, merkleRoot, licensee);

        vm.prank(steward);
        canary.unregisterDistribution(distributionId, projectId);

        assertEq(canary.isDistributionRegistered(distributionId), false);
    }

    function test_UnregisterDistributionNonStewardFails() public {
        buildMerkleRoot();

        vm.prank(steward);
        canary.registerDistribution(projectId, distributionId, merkleRoot, licensee);

        vm.prank(randomUser);
        vm.expectRevert(abi.encodeWithSelector(ICanaryRegistry.NotAuthorized.selector, randomUser, projectId));
        canary.unregisterDistribution(distributionId, projectId);
    }

    // ================================================================
    // VIEW FUNCTION TESTS
    // ================================================================

    function test_GetProjectDistributionCount() public {
        buildMerkleRoot();

        assertEq(canary.getProjectDistributionCount(projectId), 0);

        vm.prank(steward);
        canary.registerDistribution(projectId, distributionId, merkleRoot, licensee);

        assertEq(canary.getProjectDistributionCount(projectId), 1);
    }

    function test_GetProjectDistributionHashes() public {
        buildMerkleRoot();

        bytes32 secondDistId = keccak256("dist-002");
        vm.prank(steward);
        canary.registerDistribution(projectId, distributionId, merkleRoot, licensee);
        vm.prank(steward);
        canary.registerDistribution(projectId, secondDistId, merkleRoot, licensee);

        bytes32[] memory dists = canary.getProjectDistributionHashes(projectId);
        assertEq(dists.length, 2);
        assertEq(dists[0], distributionId);
        assertEq(dists[1], secondDistId);
    }

    function test_IsCanaryReported() public {
        buildMerkleRoot();

        vm.prank(steward);
        canary.registerDistribution(projectId, distributionId, merkleRoot, licensee);

        assertEq(canary.isCanaryReported(distributionId, 0), false);

        bytes32[] memory proof = new bytes32[](2);
        proof[0] = leaves[1];
        proof[1] = keccak256(abi.encodePacked(leaves[2], leaves[3]));

        vm.prank(steward);
        canary.reportCanaryMatch(
            distributionId,
            "canary_var_x7f3a",
            0,
            proof,
            accused,
            keccak256("evidence-hash")
        );

        assertEq(canary.isCanaryReported(distributionId, 0), true);
    }

    // ================================================================
    // MULTI-PROJECT TESTS
    // ================================================================

    function test_CanariesForDifferentProjectsHaveDifferentRoots() public {
        // Register a second project
        address steward2 = address(0x444);
        vm.prank(steward2);
        uint256 projectId2 = registry.registerProject(
            "SecondProject",
            keccak256("second-content"),
            "https://example.com/second",
            address(0)
        );

        // Build Merkle tree for project 2
        bytes32[] memory leaves2 = new bytes32[](4);
        leaves2[0] = computeLeaf("canary_var_x7f3a", projectId2, keccak256("dist-002"), 0);
        leaves2[1] = computeLeaf("canary_dead_code_block_92c1", projectId2, keccak256("dist-002"), 1);
        leaves2[2] = computeLeaf("canary_control_flow_marker_k8", projectId2, keccak256("dist-002"), 2);
        leaves2[3] = computeLeaf("canary_data_watermark_m44z", projectId2, keccak256("dist-002"), 3);

        bytes32 root1;
        bytes32 root2;
        {
            bytes32 hash0 = keccak256(abi.encodePacked(leaves[0], leaves[1]));
            bytes32 hash1 = keccak256(abi.encodePacked(leaves[2], leaves[3]));
            root1 = keccak256(abi.encodePacked(hash0, hash1));
        }
        {
            bytes32 hash0 = keccak256(abi.encodePacked(leaves2[0], leaves2[1]));
            bytes32 hash1 = keccak256(abi.encodePacked(leaves2[2], leaves2[3]));
            root2 = keccak256(abi.encodePacked(hash0, hash1));
        }

        assertNotEq(root1, root2);
    }

    function test_OwnerCanRegisterDistribution() public {
        buildMerkleRoot();

        vm.prank(canary.owner());
        canary.registerDistribution(projectId, distributionId, merkleRoot, licensee);

        ICanaryRegistry.DistributionCommitment memory dist = canary.getDistribution(distributionId);
        assertEq(dist.registeredBy, canary.owner());
    }
}
