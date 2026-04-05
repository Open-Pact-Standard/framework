// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

/**
 * @title IMarketplaceEscrow
 * @dev Interface for hybrid escrow contract.
 *      Holds funds for large marketplace payments until released.
 *      Small payments go direct; large payments go through escrow.
 */
interface IMarketplaceEscrow {
    /**
     * @dev Escrow entry status
     */
    enum EscrowStatus {
        Pending,
        Released,
        Refunded
    }

    /**
     * @dev Escrow entry structure
     */
    struct EscrowEntry {
        uint256 listingId;
        address buyer;
        address seller;
        address token;
        uint256 amount;
        uint256 platformFee;
        EscrowStatus status;
        uint256 createdAt;
        uint256 expiresAt;
    }

    // -- Events --

    event EscrowFunded(uint256 indexed escrowId, uint256 indexed listingId, address indexed buyer, address seller, uint256 amount);
    event EscrowReleased(uint256 indexed escrowId, uint256 indexed listingId, address indexed seller, uint256 amount);
    event EscrowRefunded(uint256 indexed escrowId, uint256 indexed listingId, address indexed buyer, uint256 amount);
    event MarketplaceUpdated(address indexed oldMarketplace, address indexed newMarketplace);

    // -- Errors --

    error NotMarketplace();
    error EscrowNotFound(uint256 escrowId);
    error EscrowNotPending(uint256 escrowId);
    error EscrowNotExpired(uint256 escrowId);
    error ZeroAddress();
    error ZeroAmount();
    error TransferFailed(bytes reason);

    // -- Functions --

    /**
     * @dev Fund an escrow (called by marketplace for large payments)
     * @param listingId Associated listing ID
     * @param buyer Buyer address
     * @param seller Seller address
     * @param token Payment token
     * @param amount Total amount (including platform fee)
     * @param platformFee Platform fee portion
     * @return escrowId Escrow entry ID
     */
    function fund(
        uint256 listingId,
        address buyer,
        address seller,
        address token,
        uint256 amount,
        uint256 platformFee
    ) external returns (uint256);

    /**
     * @dev Release escrowed funds to seller (called by marketplace)
     * @param escrowId Escrow entry to release
     * @param feeRecipient Address receiving the platform fee portion
     */
    function release(uint256 escrowId, address feeRecipient) external;

    /**
     * @dev Refund escrowed funds to buyer after timeout (called by marketplace)
     * @param escrowId Escrow entry to refund
     */
    function refund(uint256 escrowId) external;

    /**
     * @dev Set the authorized marketplace address
     * @param marketplace Marketplace contract address
     */
    function setMarketplace(address marketplace) external;

    // -- View Functions --

    function getEscrow(uint256 escrowId) external view returns (EscrowEntry memory);
    function getEscrowCount() external view returns (uint256);
    function getMarketplace() external view returns (address);
    function getEscrowTimeout() external view returns (uint256);
    function balanceOf(address token, address account) external view returns (uint256);
}
