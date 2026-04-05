// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title IRevenueSharing
 * @dev Interface for pull-based revenue distribution across multiple tokens.
 */
interface IRevenueSharing {
    event Deposited(address indexed token, address indexed from, uint256 amount);
    event Claimed(address indexed shareholder, address indexed token, uint256 amount);
    event ShareholdersUpdated(uint256 count);
    event ShareholderAdded(address indexed shareholder, uint256 shares);
    event ShareholderRemoved(address indexed shareholder);
    event ShareUpdated(address indexed shareholder, uint256 oldShares, uint256 newShares);

    /**
     * @dev Deposit native tokens (FLR/ETH) for distribution.
     */
    function depositNative() external payable;

    /**
     * @dev Deposit ERC-20 tokens for distribution.
     * @param token The token address
     * @param amount The amount to deposit
     */
    function depositToken(address token, uint256 amount) external;

    /**
     * @dev Claim all pending distributions for a token.
     * @param token The token to claim (address(0) for native)
     */
    function claim(address token) external;

    /**
     * @dev Set shareholder list with share ratios (basis points, must total 10000).
     * @param shareholders Array of shareholder addresses
     * @param shares Array of share ratios in basis points
     */
    function setShareholders(
        address[] calldata shareholders,
        uint256[] calldata shares
    ) external;

    /**
     * @dev Add a single shareholder.
     * @param shareholder Address to add
     * @param shares Share ratio in basis points
     */
    function addShareholder(address shareholder, uint256 shares) external;

    /**
     * @dev Remove a shareholder.
     * @param shareholder Address to remove
     */
    function removeShareholder(address shareholder) external;

    /**
     * @dev Update a shareholder's share ratio.
     * @param shareholder Address to update
     * @param shares New share ratio in basis points
     */
    function updateShare(address shareholder, uint256 shares) external;

    /**
     * @dev Get the pending claimable amount for a shareholder and token.
     * @param shareholder The shareholder address
     * @param token The token address (address(0) for native)
     * @return The claimable amount
     */
    function getPendingAmount(
        address shareholder,
        address token
    ) external view returns (uint256);

    /**
     * @dev Get shareholder share ratio in basis points.
     * @param shareholder The shareholder address
     * @return The share ratio in basis points
     */
    function getShare(address shareholder) external view returns (uint256);
}
