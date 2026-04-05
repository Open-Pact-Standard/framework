// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import {DAOTimelockController as DAOTimelock} from "../governance/TimelockController.sol";

/**
 * @title TimelockDeployer
 * @dev Deploys DAOTimelockController contracts.
 *      Deploy with address(0) to allow anyone, then call setFactory()
 *      to restrict to DAOFactory only.
 */
contract TimelockDeployer {
    address public factory;
    address public owner;

    error NotFactory(address caller);
    error NotOwner(address caller);
    error ZeroAddress();
    error FactoryAlreadySet();

    constructor() {
        owner = msg.sender;
    }

    modifier onlyFactory() {
        if (factory != address(0)) {
            if (msg.sender != factory) {
                revert NotFactory(msg.sender);
            }
        }
        _;
    }

    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert NotOwner(msg.sender);
        }
        _;
    }

    /**
     * @dev Set the factory address (one-time initialization).
     */
    function setFactory(address _factory) external onlyOwner {
        if (_factory == address(0)) {
            revert ZeroAddress();
        }
        if (factory != address(0)) {
            revert FactoryAlreadySet();
        }
        factory = _factory;
    }

    /**
     * @dev Deploy a DAOTimelockController contract.
     *      msg.sender (factory) receives PROPOSER_ROLE and TIMELOCK_ADMIN_ROLE.
     */
    function deploy(
        uint256 minDelay,
        address factory_
    ) external onlyFactory returns (address) {
        address[] memory proposers = new address[](1);
        proposers[0] = factory_;
        address[] memory executors = new address[](1);
        executors[0] = factory_;
        return address(new DAOTimelock(
            minDelay,
            proposers,
            executors,
            factory_
        ));
    }
}
