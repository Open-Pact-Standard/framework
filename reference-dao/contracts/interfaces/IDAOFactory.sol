// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

/**
 * @title IDAOFactory
 * @dev Interface for DAO factory deploying complete DAO stacks.
 */
interface IDAOFactory {
    struct DAOParams {
        string name;
        string symbol;
        uint256 initialSupply;
        uint256 votingDelay;
        uint256 votingPeriod;
        uint256 proposalThreshold;
        uint8 quorumFraction;
        uint256 timelockDelay;
        address[] signers;
        uint256 treasuryThreshold;
    }

    struct DAODeployment {
        address token;
        address governor;
        address timelock;
        address treasury;
        address creator;
        address revenueSharing;
        address payoutDistributor;
    }

    event DAOCreated(
        string indexed name,
        address indexed creator,
        address token,
        address governor,
        address timelock,
        address treasury,
        address revenueSharing,
        address payoutDistributor
    );

    /**
     * @dev Deploy a complete DAO stack.
     * @param params Configuration parameters for the DAO
     * @return deployment Addresses of all deployed contracts
     */
    function createDAO(DAOParams calldata params) external returns (DAODeployment memory);

    /**
     * @dev Get deployment details for a DAO by name.
     * @param name DAO name
     * @return The deployment record
     */
    function getDAO(string memory name) external view returns (DAODeployment memory);

    /**
     * @dev Get total number of DAOs created.
     * @return DAO count
     */
    function getDAOCount() external view returns (uint256);
}
