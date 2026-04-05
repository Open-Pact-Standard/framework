// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title DAOToken
 * @dev ERC20Votes governance token for DAO governance.
 * Supports delegation of voting power and checkpoint tracking.
 */
contract DAOToken is ERC20, ERC20Permit, ERC20Burnable, ERC20Votes {
    /// @notice Maximum supply of tokens (1 billion with 18 decimals)
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;

    /**
     * @dev Deploys the governance token with maximum supply minted to deployer.
     */
    constructor() ERC20("DAO Token", "DAO") ERC20Permit("DAO Token") {
        _mint(msg.sender, MAX_SUPPLY);
    }

    // The following functions are overrides required by Solidity.

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._mint(to, amount);
    }

    function _burn(address from, uint256 amount)
        internal
        override(ERC20, ERC20Votes)
    {
        super._burn(from, amount);
    }
}
