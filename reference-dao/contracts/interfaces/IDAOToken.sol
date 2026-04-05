// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IDAOToken
 * @dev Interface for DAO governance token with voting capabilities.
 */
interface IDAOToken is IERC20 {
    /**
     * @dev Delegate voting rights to a specific address.
     * @param delegatee The address to delegate voting power to
     */
    function delegate(address delegatee) external;

    /**
     * @dev Get the current voting power of an account.
     * @param account The account to query
     * @return The current voting power
     */
    function getVotes(address account) external view returns (uint256);

    /**
     * @dev Get the nonce for signature-based delegation.
     * @param owner The token holder
     * @return The current nonce
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @dev Get the delegatee of an account.
     * @param account The account to query
     * @return The delegatee address
     */
    function delegates(address account) external view returns (address);

    /**
     * @dev Get the past voting power of an account at a specific block.
     * @param account The account to query
     * @param blockNumber The block number to query
     * @return The voting power at that block
     */
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);

    /**
     * @dev Get the total supply at a specific block.
     * @param blockNumber The block number to query
     * @return The total supply at that block
     */
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256);

    /**
     * @notice Maximum supply of tokens (1 billion with 18 decimals)
     */
    function MAX_SUPPLY() external view returns (uint256);
}
