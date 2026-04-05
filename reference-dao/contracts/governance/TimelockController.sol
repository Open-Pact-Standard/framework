// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/governance/TimelockController.sol";

/**
 * @title TimelockController
 * @dev Module that executes proposals after a specified delay.
 * Provides role-based access control for PROPOSER, EXECUTOR, and CANCELLER roles.
 */
contract DAOTimelockController is TimelockController {
    /**
     * @dev Deploy the timelock with specified delay and roles.
     * @param minDelay Initial delay before proposals can be executed
     * @param proposers List of addresses that can propose
     * @param executors List of addresses that can execute
     * @param admin Optional admin address (can be address(0))
     */
    constructor(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(minDelay, proposers, executors, admin) {}
}
