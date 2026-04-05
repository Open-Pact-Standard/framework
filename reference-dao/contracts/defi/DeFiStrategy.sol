// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IDeFiStrategy.sol";

/**
 * @title DeFiStrategy
 * @dev Base contract for DeFi yield-generating strategies.
 *      Provides common storage, modifiers, and helpers.
 */
abstract contract DeFiStrategy is IDeFiStrategy, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable treasury;
    address public immutable token;
    mapping(address => uint256) public strategyBalances;

    error ZeroAddress();
    error NotTreasury(address caller);

    modifier onlyTreasury() {
        if (msg.sender != treasury) {
            revert NotTreasury(msg.sender);
        }
        _;
    }

    /**
     * @dev Initialize the strategy base.
     * @param _treasury Authorized treasury address
     * @param _token Token this strategy manages
     */
    constructor(address _treasury, address _token) {
        if (_treasury == address(0) || _token == address(0)) {
            revert ZeroAddress();
        }
        treasury = _treasury;
        token = _token;
    }

    /**
     * @inheritdoc IDeFiStrategy
     */
    function getTreasury() external view override returns (address) {
        return treasury;
    }

    /**
     * @inheritdoc IDeFiStrategy
     */
    function getToken() external view override returns (address) {
        return token;
    }

    /**
     * @dev Transfer tokens from treasury to this contract.
     * @param amount Amount to pull
     */
    function _pullTokens(uint256 amount) internal {
        IERC20(token).safeTransferFrom(treasury, address(this), amount);
    }

    /**
     * @dev Transfer tokens from this contract to treasury.
     * @param amount Amount to push
     */
    function _pushTokens(uint256 amount) internal {
        IERC20(token).safeTransfer(treasury, amount);
    }
}
