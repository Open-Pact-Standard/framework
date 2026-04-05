// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "../governance/DAOGovernor.sol";

/**
 * @title GovernorDeployer
 * @dev Deploys DAOGovernor contracts.
 *      Deploy with address(0) to allow anyone, then call setFactory()
 *      to restrict to DAOFactory only.
 */
contract GovernorDeployer {
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
     * @dev Deploy a DAOGovernor contract.
     */
    function deploy(
        address token,
        address timelock,
        string memory name,
        uint256 votingDelay,
        uint256 votingPeriod,
        uint256 proposalThreshold,
        uint8 quorumFraction
    ) external onlyFactory returns (address) {
        return address(new DAOGovernor(
            IVotes(token),
            TimelockController(payable(timelock)),
            name,
            votingDelay,
            votingPeriod,
            proposalThreshold,
            quorumFraction
        ));
    }
}
