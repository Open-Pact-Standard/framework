// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "contracts/interfaces/IAgentRegistry.sol";
import "contracts/interfaces/IReputationRegistry.sol";
import "contracts/interfaces/IValidationRegistry.sol";
import "contracts/interfaces/IRevenueSharing.sol";

contract MockIdentityRegistry is IAgentRegistry {
    uint256 private _nextId = 1;
    mapping(uint256 => address) private _wallets;
    mapping(address => uint256) private _walletToAgent;

    function registerAgent(address wallet, string memory) public returns (uint256) {
        require(_walletToAgent[wallet] == 0, "Already registered");
        uint256 agentId = _nextId++;
        _wallets[agentId] = wallet;
        _walletToAgent[wallet] = agentId;
        return agentId;
    }

    function register(string memory) external override returns (uint256) {
        return registerAgent(msg.sender, "");
    }

    function setAgentWallet(address) external override {}
    function getAgentWallet(uint256 agentId) external view override returns (address) {
        return _wallets[agentId];
    }
    function getAgentId(address wallet) external view override returns (uint256) {
        return _walletToAgent[wallet];
    }
    function getTotalAgents() external view override returns (uint256) { return _nextId - 1; }
    function agentExists(uint256 agentId) external view override returns (bool) {
        return _wallets[agentId] != address(0);
    }
}

contract MockReputationRegistry is IReputationRegistry {
    mapping(uint256 => int256) private _scores;
    mapping(uint256 => uint256) private _reviewCounts;

    function setReputation(uint256 agentId, int256 score) external {
        _scores[agentId] = score;
    }

    function submitReview(uint256, int256, string memory) external override {}
    function getReputation(uint256 agentId) external view override returns (int256) {
        return _scores[agentId];
    }
    function getReviewCount(uint256 agentId) external view override returns (uint256) {
        return _reviewCounts[agentId];
    }
    function getLastReviewTime(uint256, address) external view override returns (uint256) { return 0; }
}

contract MockValidationRegistry is IValidationRegistry {
    mapping(uint256 => bool) private _validated;

    function setValidated(uint256 agentId, bool status) external {
        _validated[agentId] = status;
    }

    function registerValidator() external override {}
    function validateAgent(uint256, bool) external override {}
    function isAgentValidated(uint256 agentId) external view override returns (bool) {
        return _validated[agentId];
    }
    function getValidationCount(uint256) external view override returns (uint256) { return 0; }
    function getValidationThreshold() external view override returns (uint256) { return 1; }
    function isValidator(address) external view override returns (bool) { return true; }
    function hasValidatorApproved(uint256, address) external view override returns (bool) { return false; }
}

contract MockRevenueSharing is IRevenueSharing {
    mapping(address => uint256) public totalDeposited;

    function depositNative() external payable override {}
    function depositToken(address token, uint256 amount) external override {
        totalDeposited[token] += amount;
    }
    function claim(address) external override {}
    function setShareholders(address[] calldata, uint256[] calldata) external override {}
    function addShareholder(address, uint256) external override {}
    function removeShareholder(address) external override {}
    function updateShare(address, uint256) external override {}
    function getPendingAmount(address, address) external view override returns (uint256) { return 0; }
    function getShare(address) external view override returns (uint256) { return 10000; }
}
