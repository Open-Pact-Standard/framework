// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "contracts/agents/ReputationRegistry.sol";
import "contracts/interfaces/IReputationRegistry.sol";

contract ReputationRegistryTest is Test {
    ReputationRegistry public registry;

    address public reviewer1;
    address public reviewer2;

    function setUp() public {
        registry = new ReputationRegistry();

        reviewer1 = makeAddr("reviewer1");
        reviewer2 = makeAddr("reviewer2");
    }

    // ============ Submit Review Tests ============

    function testSubmitReview() public {
        vm.prank(reviewer1);
        registry.submitReview(1, 8, "Great agent");

        assertEq(registry.getReviewCount(1), 1);
        assertEq(registry.getReputation(1), 8);
        assertEq(registry.getTotalScore(1), 8);
    }

    function testSubmitReviewEmitsEvent() public {
        vm.prank(reviewer1);
        vm.expectEmit(true, true, false, false);
        emit IReputationRegistry.ReviewSubmitted(1, reviewer1, 8, "Great agent");
        registry.submitReview(1, 8, "Great agent");
    }

    function testReputationUpdatedEmitsEvent() public {
        vm.prank(reviewer1);
        vm.expectEmit(true, false, false, false);
        emit IReputationRegistry.ReputationUpdated(1, 8, 1);
        registry.submitReview(1, 8, "Great agent");
    }

    function testMultipleReviewsAverageScore() public {
        vm.prank(reviewer1);
        registry.submitReview(1, 10, "Excellent");

        vm.prank(reviewer2);
        registry.submitReview(1, -5, "Poor");

        // Average: (10 + (-5)) / 2 = 2
        assertEq(registry.getReputation(1), 2);
        assertEq(registry.getReviewCount(1), 2);
        assertEq(registry.getTotalScore(1), 5);
    }

    function testCannotReviewAgentZero() public {
        vm.expectRevert(ReputationRegistry.InvalidAgentId.selector);
        registry.submitReview(0, 5, "Review");
    }

    function testScoreOutOfRangePositive() public {
        vm.expectRevert(ReputationRegistry.ScoreOutOfRange.selector);
        registry.submitReview(1, 11, "Too high");
    }

    function testScoreOutOfRangeNegative() public {
        vm.expectRevert(ReputationRegistry.ScoreOutOfRange.selector);
        registry.submitReview(1, -11, "Too low");
    }

    function testCannotSubmitEmptyReview() public {
        vm.expectRevert(ReputationRegistry.EmptyReview.selector);
        registry.submitReview(1, 5, "");
    }

    // ============ Cooldown Tests ============

    function testCooldownPeriod() public {
        vm.prank(reviewer1);
        registry.submitReview(1, 5, "First review");

        // Same reviewer tries to review same agent immediately
        vm.prank(reviewer1);
        vm.expectRevert(ReputationRegistry.CooldownActive.selector);
        registry.submitReview(1, 8, "Too soon");
    }

    function testCooldownExpiresAfterDay() public {
        vm.prank(reviewer1);
        registry.submitReview(1, 5, "First review");

        // Warp forward 1 day
        vm.warp(block.timestamp + 1 days);

        // Should succeed now
        vm.prank(reviewer1);
        registry.submitReview(1, 8, "After cooldown");

        assertEq(registry.getReviewCount(1), 2);
    }

    function testDifferentReviewersNoCooldown() public {
        vm.prank(reviewer1);
        registry.submitReview(1, 5, "Review 1");

        // Different reviewer, no cooldown
        vm.prank(reviewer2);
        registry.submitReview(1, 8, "Review 2");

        assertEq(registry.getReviewCount(1), 2);
    }

    function testSameReviewerDifferentAgent() public {
        vm.prank(reviewer1);
        registry.submitReview(1, 5, "Agent 1 review");

        // Same reviewer, different agent, no cooldown
        vm.prank(reviewer1);
        registry.submitReview(2, 8, "Agent 2 review");

        assertEq(registry.getReviewCount(1), 1);
        assertEq(registry.getReviewCount(2), 1);
    }

    // ============ View Function Tests ============

    function testCanReview() public {
        assertTrue(registry.canReview(1, reviewer1));

        vm.prank(reviewer1);
        registry.submitReview(1, 5, "Review");

        assertFalse(registry.canReview(1, reviewer1));
    }

    function testGetLastReviewTime() public {
        assertEq(registry.getLastReviewTime(1, reviewer1), 0);

        vm.prank(reviewer1);
        registry.submitReview(1, 5, "Review");

        assertGt(registry.getLastReviewTime(1, reviewer1), 0);
    }

    function testGetReputationNoReviews() public {
        assertEq(registry.getReputation(1), 0);
    }

    function testGetReview() public {
        vm.prank(reviewer1);
        registry.submitReview(1, 8, "Test review");

        (int256 score, string memory text, uint256 timestamp) = registry.getReview(1, 0);
        assertEq(score, 8);
        assertEq(text, "Test review");
        assertGt(timestamp, 0);
    }

    function testGetReviewRevertsOnInvalidIndex() public {
        vm.expectRevert(ReputationRegistry.InvalidIndex.selector);
        registry.getReview(1, 0);
    }

    // ============ Boundary Tests ============

    function testMinScore() public {
        vm.prank(reviewer1);
        registry.submitReview(1, -10, "Min score");
        assertEq(registry.getReputation(1), -10);
    }

    function testMaxScore() public {
        vm.prank(reviewer1);
        registry.submitReview(1, 10, "Max score");
        assertEq(registry.getReputation(1), 10);
    }
}
