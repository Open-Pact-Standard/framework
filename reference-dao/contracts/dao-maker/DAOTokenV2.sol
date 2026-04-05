// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title DAOTokenV2
 * @dev Factory-compatible ERC20Votes governance token.
 *      Accepts configurable name, symbol, and initial supply allocation.
 */
contract DAOTokenV2 is ERC20, ERC20Permit, ERC20Burnable, ERC20Votes {
    /// @notice Maximum supply of tokens (1 billion with 18 decimals)
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;

    error InvalidParameters();
    error SupplyExceeded(uint256 requested, uint256 max);

    /**
     * @dev Deploys the governance token with configurable parameters.
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param initialHolder Address receiving initial supply
     * @param initialSupply Amount to mint (must not exceed MAX_SUPPLY)
     */
    constructor(
        string memory name_,
        string memory symbol_,
        address initialHolder,
        uint256 initialSupply
    ) ERC20(name_, symbol_) ERC20Permit(name_) {
        if (initialHolder == address(0)) {
            revert InvalidParameters();
        }
        if (initialSupply > MAX_SUPPLY) {
            revert SupplyExceeded(initialSupply, MAX_SUPPLY);
        }
        if (initialSupply > 0) {
            _mint(initialHolder, initialSupply);
        }
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
