// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import { IBountyEscrow } from "./interfaces/IBountyEscrow.sol";

/**
 * @title BountyEscrow
 * @dev Secure payment holding for bounties
 *
 *      Features:
 *      - Hold payments in escrow until bounty completion
 *      - Platform fee collection
 *      - Dispute resolution with split payments
 *      - Auto-refund on deadline expiry
 *      - Platform claim after extended timeout
 */
contract BountyEscrow is IBountyEscrow, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Native ETH address (0x0)
    address private constant NATIVE_TOKEN = address(0);

    /// @notice Escrow ID counter
    uint256 private _escrowIdCounter;

    /// @notice Escrow ID => Escrow data
    mapping(uint256 => Escrow) private _escrows;

    /// @notice Bounty ID => Escrow ID
    mapping(uint256 => uint256) private _bountyToEscrow;

    /// @notice Token => Platform accumulated fees
    mapping(address => uint256) private _platformFees;

    /// @notice Platform fee in basis points (250 = 2.5%)
    uint256 public platformFeeBps = 250;

    /// @notice Max platform fee (1000 = 10%)
    uint256 public constant MAX_PLATFORM_FEE_BPS = 1000;

    /// @notice Dispute resolution period (7 days)
    uint256 public constant DISPUTE_PERIOD = 7 days;

    /// @notice Platform claim timeout (30 days after dispute period)
    uint256 public constant PLATFORM_CLAIM_TIMEOUT = 30 days;

    // ============ Custom Errors ============

    error EscrowNotFound();
    error InvalidAmount();
    error InvalidToken();
    error NotAuthorized();
    error EscrowNotActive();
    error EscrowAlreadyReleased();
    error EscrowNotRefundable();
    error NotDisputable();
    error DisputePeriodActive();
    error InvalidPercentage();
    error InsufficientBalance();

    // ============ Constructor ============

    constructor() Ownable() {}

    // ============ Escrow Management ============

    /**
     * @notice Create a new escrow for a bounty
     */
    function createEscrow(
        uint256 bountyId,
        address paymentToken,
        uint256 amount,
        uint256 releaseDeadline
    ) external payable returns (uint256 escrowId) {
        if (amount == 0) revert InvalidAmount();

        _escrowIdCounter++;
        escrowId = _escrowIdCounter;

        uint256 netAmount;
        uint256 platformFee;

        if (paymentToken == NATIVE_TOKEN) {
            if (msg.value < amount) revert InvalidAmount();
            netAmount = amount;
            platformFee = (amount * platformFeeBps) / 10000;
            // Keep platform fee separate
            _platformFees[NATIVE_TOKEN] += platformFee;
        } else {
            if (msg.value != 0) revert InvalidToken();
            platformFee = (amount * platformFeeBps) / 10000;
            netAmount = amount - platformFee;
            _platformFees[paymentToken] += platformFee;

            IERC20(paymentToken).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
        }

        uint256 disputeDeadline = block.timestamp + DISPUTE_PERIOD;
        uint256 platformClaimDeadline = disputeDeadline + PLATFORM_CLAIM_TIMEOUT;

        _escrows[escrowId] = Escrow({
            id: escrowId,
            bountyId: bountyId,
            poster: msg.sender,
            worker: address(0),
            paymentToken: paymentToken,
            amount: netAmount,
            platformFee: platformFee,
            netAmount: netAmount,
            status: EscrowStatus.Active,
            createdAt: block.timestamp,
            releaseDeadline: releaseDeadline,
            disputeDeadline: platformClaimDeadline,
            isDisputable: true
        });

        _bountyToEscrow[bountyId] = escrowId;

        emit EscrowCreated(escrowId, bountyId, msg.sender, paymentToken, netAmount);
        emit PlatformFeeCollected(escrowId, platformFee);

        return escrowId;
    }

    /**
     * @notice Fund additional amount to escrow
     */
    function fundEscrow(uint256 escrowId, uint256 amount) external payable {
        Escrow storage escrow = _escrows[escrowId];

        if (escrow.id != escrowId) revert EscrowNotFound();
        if (escrow.status != EscrowStatus.Active) revert EscrowNotActive();
        if (amount == 0) revert InvalidAmount();

        uint256 platformFee = (amount * platformFeeBps) / 10000;
        uint256 netAmount = amount - platformFee;

        if (escrow.paymentToken == NATIVE_TOKEN) {
            if (msg.value < amount) revert InvalidAmount();
            _platformFees[NATIVE_TOKEN] += platformFee;
        } else {
            if (msg.value != 0) revert InvalidToken();
            _platformFees[escrow.paymentToken] += platformFee;

            IERC20(escrow.paymentToken).safeTransferFrom(
                msg.sender,
                address(this),
                amount
            );
        }

        escrow.amount += netAmount;
        escrow.platformFee += platformFee;
        escrow.netAmount += netAmount;

        emit EscrowFunded(escrowId, netAmount);
        emit PlatformFeeCollected(escrowId, platformFee);
    }

    /**
     * @notice Release payment to worker
     */
    function releaseToWorker(uint256 escrowId) external {
        Escrow storage escrow = _escrows[escrowId];

        if (escrow.id != escrowId) revert EscrowNotFound();
        if (escrow.status != EscrowStatus.Active) revert EscrowNotActive();
        if (escrow.worker == address(0)) revert NotAuthorized();

        // Only poster or worker can trigger release
        if (msg.sender != escrow.poster && msg.sender != escrow.worker) {
            revert NotAuthorized();
        }

        escrow.status = EscrowStatus.Released;
        escrow.isDisputable = false;

        uint256 amount = escrow.amount;

        if (escrow.paymentToken == NATIVE_TOKEN) {
            (bool success, ) = escrow.worker.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(escrow.paymentToken).safeTransfer(escrow.worker, amount);
        }

        emit EscrowReleased(escrowId, escrow.worker, amount);
    }

    /**
     * @notice Refund payment to poster (cancelled/expired bounty)
     */
    function refundToPoster(uint256 escrowId) external {
        Escrow storage escrow = _escrows[escrowId];

        if (escrow.id != escrowId) revert EscrowNotFound();
        if (escrow.status != EscrowStatus.Active) revert EscrowNotActive();
        if (msg.sender != escrow.poster) revert NotAuthorized();

        // Can refund if deadline passed or no worker assigned
        if (escrow.worker != address(0) && block.timestamp < escrow.releaseDeadline) {
            revert EscrowNotRefundable();
        }

        escrow.status = EscrowStatus.Refunded;
        escrow.isDisputable = false;

        uint256 amount = escrow.amount;

        if (escrow.paymentToken == NATIVE_TOKEN) {
            (bool success, ) = escrow.poster.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(escrow.paymentToken).safeTransfer(escrow.poster, amount);
        }

        emit EscrowRefunded(escrowId, escrow.poster, amount);
    }

    /**
     * @notice Raise a dispute
     */
    function raiseDispute(uint256 escrowId, string calldata reason) external {
        Escrow storage escrow = _escrows[escrowId];

        if (escrow.id != escrowId) revert EscrowNotFound();
        if (escrow.status != EscrowStatus.Active) revert EscrowNotActive();
        if (!escrow.isDisputable) revert NotDisputable();

        // Only poster or worker can raise dispute
        if (msg.sender != escrow.poster && msg.sender != escrow.worker) {
            revert NotAuthorized();
        }

        escrow.status = EscrowStatus.Disputed;
        escrow.isDisputable = false;

        emit DisputeRaised(escrowId, msg.sender, reason);
    }

    /**
     * @notice Resolve a dispute (admin only)
     */
    function resolveDispute(
        uint256 escrowId,
        address winner,
        uint256 workerPercentage
    ) external onlyOwner {
        Escrow storage escrow = _escrows[escrowId];

        if (escrow.id != escrowId) revert EscrowNotFound();
        if (escrow.status != EscrowStatus.Disputed) revert EscrowNotActive();
        if (workerPercentage > 10000) revert InvalidPercentage();

        escrow.status = EscrowStatus.Released;

        uint256 totalAmount = escrow.amount;
        uint256 workerAmount = (totalAmount * workerPercentage) / 10000;
        uint256 posterAmount = totalAmount - workerAmount;

        if (winner == escrow.worker) {
            if (escrow.paymentToken == NATIVE_TOKEN) {
                (bool success, ) = escrow.worker.call{value: workerAmount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(escrow.paymentToken).safeTransfer(escrow.worker, workerAmount);
            }
        }

        // Poster gets remainder
        if (posterAmount > 0) {
            if (escrow.paymentToken == NATIVE_TOKEN) {
                (bool success, ) = escrow.poster.call{value: posterAmount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(escrow.paymentToken).safeTransfer(escrow.poster, posterAmount);
            }
        }

        emit DisputeResolved(escrowId, winner, workerPercentage);
        emit EscrowReleased(escrowId, winner, workerAmount);
    }

    /**
     * @notice Claim timed-out escrow (platform only)
     */
    function claimTimedOut(uint256 escrowId) external onlyOwner {
        Escrow storage escrow = _escrows[escrowId];

        if (escrow.id != escrowId) revert EscrowNotFound();
        if (escrow.status != EscrowStatus.Disputed) revert EscrowNotActive();

        // Must be past dispute deadline
        if (block.timestamp < escrow.disputeDeadline) revert DisputePeriodActive();

        escrow.status = EscrowStatus.ClaimedByPlatform;

        uint256 amount = escrow.amount;

        if (escrow.paymentToken == NATIVE_TOKEN) {
            (bool success, ) = owner().call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(escrow.paymentToken).safeTransfer(owner(), amount);
        }

        emit EscrowReleased(escrowId, owner(), amount);
    }

    // ============ View Functions ============

    /**
     * @notice Get escrow details
     */
    function getEscrow(uint256 escrowId)
        external
        view
        returns (Escrow memory)
    {
        Escrow storage escrow = _escrows[escrowId];
        if (escrow.id != escrowId) revert EscrowNotFound();
        return escrow;
    }

    /**
     * @notice Get escrow ID by bounty ID
     */
    function getEscrowByBounty(uint256 bountyId)
        external
        view
        returns (uint256 escrowId)
    {
        return _bountyToEscrow[bountyId];
    }

    /**
     * @notice Check if escrow can be released
     */
    function canRelease(uint256 escrowId)
        external
        view
        returns (bool)
    {
        Escrow storage escrow = _escrows[escrowId];
        return escrow.id == escrowId &&
               escrow.status == EscrowStatus.Active &&
               escrow.worker != address(0);
    }

    /**
     * @notice Check if escrow can be refunded
     */
    function canRefund(uint256 escrowId)
        external
        view
        returns (bool)
    {
        Escrow storage escrow = _escrows[escrowId];
        return escrow.id == escrowId &&
               escrow.status == EscrowStatus.Active &&
               (escrow.worker == address(0) || block.timestamp >= escrow.releaseDeadline);
    }

    /**
     * @notice Check if escrow is disputable
     */
    function isDisputable(uint256 escrowId)
        external
        view
        returns (bool)
    {
        Escrow storage escrow = _escrows[escrowId];
        return escrow.id == escrowId && escrow.isDisputable;
    }

    /**
     * @notice Calculate platform fee for an amount
     */
    function getPlatformFee(uint256 amount)
        external
        view
        returns (uint256 fee)
    {
        return (amount * platformFeeBps) / 10000;
    }

    /**
     * @notice Get current platform fee basis points
     */
    function getPlatformFeeBps()
        external
        view
        returns (uint256)
    {
        return platformFeeBps;
    }

    // ============ Platform Management ============

    /**
     * @notice Set platform fee
     */
    function setPlatformFeeBps(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_PLATFORM_FEE_BPS) revert InvalidPercentage();

        uint256 oldFee = platformFeeBps;
        platformFeeBps = newFeeBps;

        emit PlatformFeeUpdated(oldFee, newFeeBps);
    }

    /**
     * @notice Withdraw accumulated platform fees
     */
    function withdrawPlatformFees(address token, uint256 amount) external onlyOwner {
        if (_platformFees[token] < amount) revert InsufficientBalance();

        _platformFees[token] -= amount;

        if (token == NATIVE_TOKEN) {
            (bool success, ) = owner().call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }

        emit PlatformFeesWithdrawn(token, amount);
    }

    /**
     * @notice Get platform balance for a token
     */
    function getPlatformBalance(address token)
        external
        view
        returns (uint256)
    {
        return _platformFees[token];
    }

    /**
     * @notice Set worker for escrow (called by BountyBoard)
     */
    function setWorker(uint256 escrowId, address worker) external {
        Escrow storage escrow = _escrows[escrowId];

        if (escrow.id != escrowId) revert EscrowNotFound();
        if (escrow.status != EscrowStatus.Active) revert EscrowNotActive();

        escrow.worker = worker;
    }

    /**
     * @notice Allow contract to receive ETH
     */
    receive() external payable {}
}
