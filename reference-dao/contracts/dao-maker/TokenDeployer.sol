// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "./DAOTokenV2.sol";

/**
 * @title TokenDeployer
 * @dev Deploys DAOTokenV2 contracts.
 *      Deploy with address(0) to allow anyone, then call setFactory()
 *      to restrict to DAOFactory only.
 */
contract TokenDeployer {
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
     * @dev Deploy a DAOTokenV2 contract.
     */
    function deploy(
        string memory name,
        string memory symbol,
        address initialHolder,
        uint256 initialSupply
    ) external onlyFactory returns (address) {
        return address(new DAOTokenV2(name, symbol, initialHolder, initialSupply));
    }
}
