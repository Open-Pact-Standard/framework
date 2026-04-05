// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IValidationRegistry.sol";

/**
 * @title ValidationRegistry
 * @dev Validation checks for agents per EIP-8004 specification.
 *      Open validation network where anyone can become a validator.
 */
contract ValidationRegistry is IValidationRegistry, Ownable {
    /// @notice Default threshold for validation (number of validators needed)
    uint256 public constant DEFAULT_VALIDATION_THRESHOLD = 1;
    
    /// @notice Mapping from address to whether it's a validator
    mapping(address => bool) private _validators;
    
    /// @notice List of all validator addresses
    address[] private _validatorList;
    
    /// @notice Mapping from agent ID to validation count (number of validators who approved)
    mapping(uint256 => uint256) private _validationCounts;
    
    /// @notice Mapping from agent ID to whether agent is validated
    mapping(uint256 => bool) private _validatedAgents;

    /// @notice List of all validated agent IDs (for threshold recalculation)
    uint256[] private _agentIds;
    
    /// @notice Mapping from (agentId, validator) to whether validator approved
    mapping(uint256 => mapping(address => bool)) private _validatorApprovals;
    
    /// @notice Required number of validators to mark agent as validated
    uint256 public validationThreshold;

    constructor() Ownable() {
        validationThreshold = DEFAULT_VALIDATION_THRESHOLD;
    }

    /**
     * @notice Register as a validator
     *      Anyone can become a validator (open validation per EIP-8004)
     */
    function registerValidator() external override {
        require(!_validators[msg.sender], "ValidationRegistry: already a validator");
        
        _validators[msg.sender] = true;
        _validatorList.push(msg.sender);
        
        emit ValidatorRegistered(msg.sender);
    }

    /**
     * @notice Validate or invalidate an agent
     * @param agentId The ID of the agent
     * @param status True to validate, false to invalidate
     */
    function validateAgent(uint256 agentId, bool status) external override {
        require(_validators[msg.sender], "ValidationRegistry: not a validator");
        require(agentId > 0, "ValidationRegistry: invalid agent ID");
        
        // Check current approval status
        bool previouslyApproved = _validatorApprovals[agentId][msg.sender];
        
        // If status is true and wasn't previously approved
        if (status && !previouslyApproved) {
            _validatorApprovals[agentId][msg.sender] = true;
            _validationCounts[agentId]++;

            // Track agent ID on first approval for threshold recalculation
            if (_validationCounts[agentId] == 1) {
                _agentIds.push(agentId);
            }

            // Check if threshold now met
            if (_validationCounts[agentId] >= validationThreshold && !_validatedAgents[agentId]) {
                _validatedAgents[agentId] = true;
            }
        }
        // If status is false and was previously approved
        else if (!status && previouslyApproved) {
            _validatorApprovals[agentId][msg.sender] = false;
            if (_validationCounts[agentId] > 0) {
                _validationCounts[agentId]--;
            }
            
            // If threshold no longer met, mark as not validated
            if (_validationCounts[agentId] < validationThreshold && _validatedAgents[agentId]) {
                _validatedAgents[agentId] = false;
            }
        }
        
        emit AgentValidated(agentId, msg.sender, status);
    }

    /**
     * @notice Check if an agent is validated
     * @param agentId The agent ID to query
     * @return True if the agent has passed validation
     */
    function isAgentValidated(uint256 agentId) external view override returns (bool) {
        return _validatedAgents[agentId];
    }

    /**
     * @notice Get the validation count for an agent
     * @param agentId The agent ID to query
     * @return The number of validators who approved
     */
    function getValidationCount(uint256 agentId) external view override returns (uint256) {
        return _validationCounts[agentId];
    }

    /**
     * @notice Get the required validator threshold
     * @return The number of validators required
     */
    function getValidationThreshold() external view override returns (uint256) {
        return validationThreshold;
    }

    /**
     * @notice Set the validation threshold
     * @param newThreshold The new threshold value
     */
    function setValidationThreshold(uint256 newThreshold) external onlyOwner {
        require(newThreshold > 0, "ValidationRegistry: threshold must be positive");
        
        // Update validation status for all agents based on new threshold
        validationThreshold = newThreshold;

        // Recalculate validation status for all tracked agents
        uint256 len = _agentIds.length;
        for (uint256 i = 0; i < len; i++) {
            uint256 agentId = _agentIds[i];
            bool shouldBeValidated = _validationCounts[agentId] >= newThreshold;
            if (_validatedAgents[agentId] != shouldBeValidated) {
                _validatedAgents[agentId] = shouldBeValidated;
            }
        }
        
        emit ValidationThresholdChanged(newThreshold);
    }

    /**
     * @notice Check if an address is a registered validator
     * @param validator The address to check
     * @return True if registered as validator
     */
    function isValidator(address validator) external view override returns (bool) {
        return _validators[validator];
    }

    /**
     * @notice Get the total number of registered validators
     * @return The validator count
     */
    function getValidatorCount() external view returns (uint256) {
        return _validatorList.length;
    }

    /**
     * @notice Check if a specific validator has validated an agent
     * @param agentId The agent ID
     * @param validator The validator address
     * @return True if the validator has approved this agent
     */
    function hasValidatorApproved(uint256 agentId, address validator) external view override returns (bool) {
        return _validatorApprovals[agentId][validator];
    }

    /**
     * @notice Get validator at index
     * @param index The validator index
     * @return The validator address
     */
    function getValidator(uint256 index) external view returns (address) {
        require(index < _validatorList.length, "ValidationRegistry: invalid index");
        return _validatorList[index];
    }
}
