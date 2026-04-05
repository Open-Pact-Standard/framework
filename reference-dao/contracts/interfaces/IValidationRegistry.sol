// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

/**
 * @title IValidationRegistry
 * @dev Interface for EIP-8004 Validation Registry
 *      Provides validator checks (KYC, staking) for agents
 */
interface IValidationRegistry {
    /**
     * @notice Register as a validator
     */
    function registerValidator() external;

    /**
     * @notice Validate or invalidate an agent
     * @param agentId The ID of the agent
     * @param status True to validate, false to invalidate
     */
    function validateAgent(uint256 agentId, bool status) external;

    /**
     * @notice Check if an agent is validated
     * @param agentId The agent ID to query
     * @return True if the agent has passed validation
     */
    function isAgentValidated(uint256 agentId) external view returns (bool);

    /**
     * @notice Get the validation count for an agent (number of validators who approved)
     * @param agentId The agent ID to query
     * @return The number of validators who approved
     */
    function getValidationCount(uint256 agentId) external view returns (uint256);

    /**
     * @notice Get the required validator threshold for validation
     * @return The number of validators required
     */
    function getValidationThreshold() external view returns (uint256);

    /**
     * @notice Check if an address is a registered validator
     * @param validator The address to check
     * @return True if registered as validator
     */
    function isValidator(address validator) external view returns (bool);

    /**
     * @notice Check if a specific validator has validated an agent
     * @param agentId The agent ID
     * @param validator The validator address
     * @return True if the validator has approved this agent
     */
    function hasValidatorApproved(uint256 agentId, address validator) external view returns (bool);

    // Events
    event ValidatorRegistered(address indexed validator);
    event AgentValidated(uint256 indexed agentId, address indexed validator, bool status);
    event ValidationThresholdChanged(uint256 newThreshold);
}
