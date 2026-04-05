// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IMarketplaceEscrow.sol";

/**
 * @title MarketplaceEscrow
 * @dev Hybrid escrow contract for large marketplace payments.
 *      Holds tokens until released by marketplace or refunded after timeout.
 *
 *      Flow:
 *      1. Marketplace calls fund() after PaymentVerifier sends tokens here
 *      2. On completion: marketplace calls release() -> seller gets net, fee to platform
 *      3. On timeout: marketplace calls refund() -> buyer gets funds back
 *
 *      Post-deployment: call setMarketplace(marketplace) to authorize the marketplace.
 */
contract MarketplaceEscrow is IMarketplaceEscrow, Ownable2Step, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Storage
    address private _marketplace;
    uint256 private _escrowCount;
    uint256 public immutable escrowTimeout;

    mapping(uint256 => EscrowEntry) private _entries;

    // Track token balances per account (for view functions)
    mapping(address => mapping(address => uint256)) private _balances;

    /**
     * @dev Constructor
     * @param _escrowTimeout Timeout in seconds for escrow refund eligibility
     */
    constructor(uint256 _escrowTimeout) Ownable() {
        escrowTimeout = _escrowTimeout;
    }

    modifier onlyMarketplace() {
        if (msg.sender != _marketplace && msg.sender != owner()) {
            revert NotMarketplace();
        }
        _;
    }

    /**
     * @inheritdoc IMarketplaceEscrow
     */
    function fund(
        uint256 listingId,
        address buyer,
        address seller,
        address token,
        uint256 amount,
        uint256 platformFee
    ) external override onlyMarketplace nonReentrant whenNotPaused returns (uint256) {
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (buyer == address(0) || seller == address(0) || token == address(0)) {
            revert ZeroAddress();
        }

        uint256 escrowId = _escrowCount;
        _escrowCount++;

        _entries[escrowId] = EscrowEntry({
            listingId: listingId,
            buyer: buyer,
            seller: seller,
            token: token,
            amount: amount,
            platformFee: platformFee,
            status: EscrowStatus.Pending,
            createdAt: block.timestamp,
            expiresAt: block.timestamp + escrowTimeout
        });

        emit EscrowFunded(escrowId, listingId, buyer, seller, amount);

        return escrowId;
    }

    /**
     * @inheritdoc IMarketplaceEscrow
     */
    function release(uint256 escrowId, address feeRecipient) external override onlyMarketplace nonReentrant whenNotPaused {
        EscrowEntry storage entry = _entries[escrowId];
        if (escrowId >= _escrowCount) {
            revert EscrowNotFound(escrowId);
        }
        if (entry.status != EscrowStatus.Pending) {
            revert EscrowNotPending(escrowId);
        }

        entry.status = EscrowStatus.Released;

        // Transfer platform fee if applicable
        if (entry.platformFee > 0 && feeRecipient != address(0)) {
            IERC20(entry.token).safeTransfer(feeRecipient, entry.platformFee);
        }

        // Transfer net amount to seller
        uint256 netAmount = entry.amount - entry.platformFee;
        if (entry.seller != address(0) && netAmount > 0) {
            IERC20(entry.token).safeTransfer(entry.seller, netAmount);
        }

        emit EscrowReleased(escrowId, entry.listingId, entry.seller, netAmount);
    }

    /**
     * @inheritdoc IMarketplaceEscrow
     */
    function refund(uint256 escrowId) external override onlyMarketplace nonReentrant whenNotPaused {
        EscrowEntry storage entry = _entries[escrowId];
        if (escrowId >= _escrowCount) {
            revert EscrowNotFound(escrowId);
        }
        if (entry.status != EscrowStatus.Pending) {
            revert EscrowNotPending(escrowId);
        }
        if (block.timestamp < entry.expiresAt) {
            revert EscrowNotExpired(escrowId);
        }

        entry.status = EscrowStatus.Refunded;

        // Refund full amount to buyer
        IERC20(entry.token).safeTransfer(entry.buyer, entry.amount);

        emit EscrowRefunded(escrowId, entry.listingId, entry.buyer, entry.amount);
    }

    /**
     * @inheritdoc IMarketplaceEscrow
     */
    function setMarketplace(address marketplace) external override onlyOwner {
        if (marketplace == address(0)) {
            revert ZeroAddress();
        }
        address oldMarketplace = _marketplace;
        _marketplace = marketplace;
        emit MarketplaceUpdated(oldMarketplace, marketplace);
    }

    // ============ View Functions ============

    /**
     * @inheritdoc IMarketplaceEscrow
     */
    function getEscrow(uint256 escrowId) external view override returns (EscrowEntry memory) {
        return _entries[escrowId];
    }

    /**
     * @inheritdoc IMarketplaceEscrow
     */
    function getEscrowCount() external view override returns (uint256) {
        return _escrowCount;
    }

    /**
     * @inheritdoc IMarketplaceEscrow
     */
    function getMarketplace() external view override returns (address) {
        return _marketplace;
    }

    /**
     * @inheritdoc IMarketplaceEscrow
     */
    function getEscrowTimeout() external view override returns (uint256) {
        return escrowTimeout;
    }

    /**
     * @inheritdoc IMarketplaceEscrow
     */
    function balanceOf(address token, address account) external view override returns (uint256) {
        return IERC20(token).balanceOf(account);
    }

    /**
     * @dev Pause the contract (owner only)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract (owner only)
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
