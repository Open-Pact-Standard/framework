// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "contracts/agents/ValidationRegistry.sol";
import "contracts/interfaces/IValidationRegistry.sol";

contract ValidationRegistryTest is Test {
    ValidationRegistry public registry;

    address public validator1;
    address public validator2;
    address public validator3;
    address public nonValidator;

    function setUp() public {
        registry = new ValidationRegistry();

        validator1 = makeAddr("validator1");
        validator2 = makeAddr("validator2");
        validator3 = makeAddr("validator3");
        nonValidator = makeAddr("nonValidator");
    }

    // ============ Registration Tests ============

    function testRegisterValidator() public {
        vm.prank(validator1);
        registry.registerValidator();

        assertTrue(registry.isValidator(validator1));
        assertEq(registry.getValidatorCount(), 1);
        assertEq(registry.getValidator(0), validator1);
    }

    function testRegisterValidatorEmitsEvent() public {
        vm.prank(validator1);
        vm.expectEmit(true, false, false, false);
        emit IValidationRegistry.ValidatorRegistered(validator1);
        registry.registerValidator();
    }

    function testCannotRegisterTwice() public {
        vm.prank(validator1);
        registry.registerValidator();

        vm.prank(validator1);
        vm.expectRevert("ValidationRegistry: already a validator");
        registry.registerValidator();
    }

    function testMultipleValidators() public {
        vm.prank(validator1);
        registry.registerValidator();

        vm.prank(validator2);
        registry.registerValidator();

        vm.prank(validator3);
        registry.registerValidator();

        assertEq(registry.getValidatorCount(), 3);
    }

    // ============ Validation Tests ============

    function testValidateAgent() public {
        vm.prank(validator1);
        registry.registerValidator();

        vm.prank(validator1);
        registry.validateAgent(1, true);

        assertTrue(registry.isAgentValidated(1));
        assertEq(registry.getValidationCount(1), 1);
        assertTrue(registry.hasValidatorApproved(1, validator1));
    }

    function testValidateAgentEmitsEvent() public {
        vm.prank(validator1);
        registry.registerValidator();

        vm.prank(validator1);
        vm.expectEmit(true, true, false, false);
        emit IValidationRegistry.AgentValidated(1, validator1, true);
        registry.validateAgent(1, true);
    }

    function testInvalidateAgent() public {
        vm.prank(validator1);
        registry.registerValidator();

        vm.prank(validator1);
        registry.validateAgent(1, true);
        assertTrue(registry.isAgentValidated(1));

        vm.prank(validator1);
        registry.validateAgent(1, false);
        assertFalse(registry.isAgentValidated(1));
        assertEq(registry.getValidationCount(1), 0);
        assertFalse(registry.hasValidatorApproved(1, validator1));
    }

    function testCannotValidateIfNotValidator() public {
        vm.prank(nonValidator);
        vm.expectRevert("ValidationRegistry: not a validator");
        registry.validateAgent(1, true);
    }

    function testCannotValidateAgentZero() public {
        vm.prank(validator1);
        registry.registerValidator();

        vm.prank(validator1);
        vm.expectRevert("ValidationRegistry: invalid agent ID");
        registry.validateAgent(0, true);
    }

    // ============ Threshold Tests ============

    function testDefaultThreshold() public view {
        assertEq(registry.getValidationThreshold(), 1);
    }

    function testSetValidationThreshold() public {
        registry.setValidationThreshold(3);
        assertEq(registry.getValidationThreshold(), 3);
    }

    function testSetThresholdEmitsEvent() public {
        vm.expectEmit(false, false, false, false);
        emit IValidationRegistry.ValidationThresholdChanged(3);
        registry.setValidationThreshold(3);
    }

    function testCannotSetZeroThreshold() public {
        vm.expectRevert("ValidationRegistry: threshold must be positive");
        registry.setValidationThreshold(0);
    }

    function testOnlyOwnerCanSetThreshold() public {
        vm.prank(validator1);
        vm.expectRevert("Ownable: caller is not the owner");
        registry.setValidationThreshold(3);
    }

    function testMultiValidatorThreshold() public {
        registry.setValidationThreshold(2);

        vm.prank(validator1);
        registry.registerValidator();

        vm.prank(validator2);
        registry.registerValidator();

        // First validator approves - threshold not met
        vm.prank(validator1);
        registry.validateAgent(1, true);
        assertFalse(registry.isAgentValidated(1));
        assertEq(registry.getValidationCount(1), 1);

        // Second validator approves - threshold met
        vm.prank(validator2);
        registry.validateAgent(1, true);
        assertTrue(registry.isAgentValidated(1));
        assertEq(registry.getValidationCount(1), 2);
    }

    function testThresholdDropsValidation() public {
        registry.setValidationThreshold(2);

        vm.prank(validator1);
        registry.registerValidator();

        vm.prank(validator2);
        registry.registerValidator();

        vm.prank(validator1);
        registry.validateAgent(1, true);
        vm.prank(validator2);
        registry.validateAgent(1, true);
        assertTrue(registry.isAgentValidated(1));

        // Validator2 withdraws - threshold no longer met
        vm.prank(validator2);
        registry.validateAgent(1, false);
        assertFalse(registry.isAgentValidated(1));
    }

    // ============ Idempotency Tests ============

    function testDoubleApprovalIsIdempotent() public {
        vm.prank(validator1);
        registry.registerValidator();

        vm.prank(validator1);
        registry.validateAgent(1, true);
        assertEq(registry.getValidationCount(1), 1);

        // Approving again should not increment
        vm.prank(validator1);
        registry.validateAgent(1, true);
        assertEq(registry.getValidationCount(1), 1);
    }

    function testDoubleInvalidateIsIdempotent() public {
        vm.prank(validator1);
        registry.registerValidator();

        vm.prank(validator1);
        registry.validateAgent(1, true);
        vm.prank(validator1);
        registry.validateAgent(1, false);
        assertEq(registry.getValidationCount(1), 0);

        // Invalidating again should not underflow
        vm.prank(validator1);
        registry.validateAgent(1, false);
        assertEq(registry.getValidationCount(1), 0);
    }

    // ============ View Function Tests ============

    function testGetValidatorRevertsOnInvalidIndex() public {
        vm.expectRevert("ValidationRegistry: invalid index");
        registry.getValidator(0);
    }

    // ============ Threshold Recalculation Tests ============

    function testThresholdRecalculationValidatesAgents() public {
        // Set threshold to 2
        registry.setValidationThreshold(2);

        vm.prank(validator1);
        registry.registerValidator();
        vm.prank(validator2);
        registry.registerValidator();

        // Only validator1 approves - threshold not met
        vm.prank(validator1);
        registry.validateAgent(1, true);
        assertFalse(registry.isAgentValidated(1));

        // Lower threshold to 1 - agent should now be validated
        registry.setValidationThreshold(1);
        assertTrue(registry.isAgentValidated(1));
    }

    function testThresholdRecalculationInvalidatesAgents() public {
        // Threshold is 1 by default, agent gets validated with 1 approval
        vm.prank(validator1);
        registry.registerValidator();
        vm.prank(validator2);
        registry.registerValidator();

        vm.prank(validator1);
        registry.validateAgent(1, true);
        assertTrue(registry.isAgentValidated(1));

        // Raise threshold to 2 - agent should no longer be validated
        registry.setValidationThreshold(2);
        assertFalse(registry.isAgentValidated(1));
    }

    function testThresholdRecalculationDoesNotAffectUntrackedAgents() public {
        // Set threshold to 1, validate agent
        vm.prank(validator1);
        registry.registerValidator();
        vm.prank(validator1);
        registry.validateAgent(1, true);
        assertTrue(registry.isAgentValidated(1));

        // Raise threshold - agent 1 was tracked so it should be recalculated
        registry.setValidationThreshold(3);
        assertFalse(registry.isAgentValidated(1));

        // Agent 2 was never validated so it stays false
        assertFalse(registry.isAgentValidated(2));
    }
}
