// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IMarketplace.sol";
import "../interfaces/IMarketplaceEscrow.sol";
import "../interfaces/IPaymentVerifier.sol";
import "../interfaces/IPaymentLedger.sol";
import "../interfaces/IAgentRegistry.sol";
import "../interfaces/IReputationRegistry.sol";
import "../interfaces/IValidationRegistry.sol";
import "../interfaces/IRevenueSharing.sol";

/**
 * @title Marketplace
 * @dev Agent marketplace for service listings and bounty postings.
 *      Supports listing CRUD, direct purchases, bounty lifecycle, and
 *      hybrid escrow for large payments.
 *      Integrates with PaymentVerifier, PaymentLedger, IdentityRegistry,
 *      ReputationRegistry, ValidationRegistry, and RevenueSharing.
 *
 *      Post-deployment configuration:
 *      1. ledger.addVerifier(marketplace) - allow ledger writes
 *      2. verifier.setFacilitator(marketplace, true) - allow payment processing
 *      3. escrow.setMarketplace(marketplace) - authorize escrow calls
 */
contract Marketplace is IMarketplace, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Storage
    IPaymentVerifier public immutable verifier;
    IPaymentLedger public immutable ledger;
    IAgentRegistry public immutable identityRegistry;
    IReputationRegistry public immutable reputationRegistry;
    IValidationRegistry public immutable validationRegistry;
    IRevenueSharing public immutable revenueSharing;
    IMarketplaceEscrow public immutable escrow;

    uint256 private _listingCount;
    mapping(uint256 => Listing) private _listings;
    mapping(uint256 => Bounty) private _bounties;
    mapping(uint256 => uint256) private _listingEscrowIds;
    mapping(uint256 => bool) private _hasEscrow;
    mapping(address => bool) private _supportedTokens;
    address[] private _tokenList;

    uint256 public platformFeeBps;
    address public feeRecipient;
    uint256 public escrowThreshold;

    /// @notice Maximum platform fee: 10% (1000 basis points)
    uint256 public constant MAX_PLATFORM_FEE_BPS = 1000;
    /// @notice Default bounty claim timeout: 7 days
    uint256 public constant DEFAULT_CLAIM_TIMEOUT = 7 days;

    // Counters for analytics
    uint256 public totalPurchases;
    uint256 public totalBountiesPaid;
    uint256 public totalVolume;

    /**
     * @dev Constructor
     * @param _verifier PaymentVerifier for x402 payment processing
     * @param _ledger PaymentLedger for audit trail
     * @param _identityRegistry IdentityRegistry for agent verification
     * @param _reputationRegistry ReputationRegistry for reputation scores
     * @param _validationRegistry ValidationRegistry for validation badges
     * @param _revenueSharing RevenueSharing for platform fee deposits
     * @param _escrow MarketplaceEscrow for large payment holding
     * @param _feeRecipient Address receiving platform fees
     * @param _platformFeeBps Platform fee in basis points (250 = 2.5%)
     * @param _escrowThreshold Amount above which payments use escrow
     */
    constructor(
        address _verifier,
        address _ledger,
        address _identityRegistry,
        address _reputationRegistry,
        address _validationRegistry,
        address _revenueSharing,
        address _escrow,
        address _feeRecipient,
        uint256 _platformFeeBps,
        uint256 _escrowThreshold
    ) Ownable() {
        if (
            _verifier == address(0) || _ledger == address(0) ||
            _identityRegistry == address(0) || _reputationRegistry == address(0) ||
            _validationRegistry == address(0) ||
            _escrow == address(0) || _feeRecipient == address(0)
        ) {
            revert ZeroAddress();
        }
        // _revenueSharing can be address(0) if revenue sharing is not used
        if (_revenueSharing == address(0)) {
            _revenueSharing = address(0x0000000000000000000000000000000000001); // dummy address
        }
        if (_platformFeeBps > MAX_PLATFORM_FEE_BPS) {
            revert InvalidFee();
        }

        verifier = IPaymentVerifier(_verifier);
        ledger = IPaymentLedger(_ledger);
        identityRegistry = IAgentRegistry(_identityRegistry);
        reputationRegistry = IReputationRegistry(_reputationRegistry);
        validationRegistry = IValidationRegistry(_validationRegistry);
        revenueSharing = IRevenueSharing(_revenueSharing);
        escrow = IMarketplaceEscrow(_escrow);
        feeRecipient = _feeRecipient;
        platformFeeBps = _platformFeeBps;
        escrowThreshold = _escrowThreshold;
    }

    // ============ Service Listing Functions ============

    /**
     * @inheritdoc IMarketplace
     */
    function createListing(
        address token,
        uint256 price,
        string calldata metadata
    ) external override whenNotPaused returns (uint256) {
        if (!_supportedTokens[token]) {
            revert InvalidToken();
        }
        if (price == 0) {
            revert InvalidPrice();
        }

        uint256 agentId = identityRegistry.getAgentId(msg.sender);
        if (agentId == 0) {
            revert NotAgent();
        }

        uint256 listingId = _listingCount;
        _listingCount++;

        _listings[listingId] = Listing({
            listingId: listingId,
            agentId: agentId,
            seller: msg.sender,
            listingType: ListingType.Service,
            status: ListingStatus.Active,
            token: token,
            price: price,
            metadata: metadata,
            createdAt: block.timestamp,
            updatedAt: block.timestamp
        });

        emit ListingCreated(listingId, agentId, msg.sender, ListingType.Service, token, price);

        return listingId;
    }

    /**
     * @inheritdoc IMarketplace
     */
    function updateListing(
        uint256 listingId,
        uint256 price,
        string calldata metadata
    ) external override whenNotPaused {
        Listing storage listing = _listings[listingId];
        if (listing.listingId != listingId || listing.listingType != ListingType.Service) {
            revert ListingNotFound(listingId);
        }
        if (listing.seller != msg.sender) {
            revert NotListingOwner(listingId);
        }
        if (listing.status != ListingStatus.Active) {
            revert ListingNotActive(listingId);
        }
        if (price == 0) {
            revert InvalidPrice();
        }

        listing.price = price;
        listing.metadata = metadata;
        listing.updatedAt = block.timestamp;

        emit ListingUpdated(listingId, price, metadata);
    }

    /**
     * @inheritdoc IMarketplace
     */
    function cancelListing(uint256 listingId) external override whenNotPaused {
        Listing storage listing = _listings[listingId];
        if (listing.listingId != listingId || listing.listingType != ListingType.Service) {
            revert ListingNotFound(listingId);
        }
        if (listing.seller != msg.sender) {
            revert NotListingOwner(listingId);
        }
        if (listing.status != ListingStatus.Active) {
            revert ListingNotActive(listingId);
        }

        listing.status = ListingStatus.Canceled;
        listing.updatedAt = block.timestamp;

        emit ListingCanceled(listingId);
    }

    /// @inheritdoc IMarketplace
    function purchaseListing(
        uint256 listingId,
        IPaymentVerifier.PaymentParams calldata params
    ) external override nonReentrant whenNotPaused returns (uint256) {
        Listing storage listing = _listings[listingId];
        if (listing.listingId != listingId || listing.listingType != ListingType.Service) {
            revert ListingNotFound(listingId);
        }
        if (listing.status != ListingStatus.Active) {
            revert ListingNotActive(listingId);
        }
        if (listing.seller == msg.sender) {
            revert CannotBuyOwnListing();
        }

        uint256 fee = (listing.price * platformFeeBps) / 10000;
        uint256 paymentId;

        if (listing.price <= escrowThreshold) {
            // Direct: price to seller via PaymentVerifier
            IPaymentVerifier.PaymentParams memory sellerParams = IPaymentVerifier.PaymentParams({
                payer: params.payer,
                recipient: listing.seller,
                token: params.token,
                amount: listing.price,
                validAfter: params.validAfter,
                validBefore: params.validBefore,
                nonce: params.nonce,
                v: params.v,
                r: params.r,
                s: params.s
            });

            paymentId = verifier.processPayment(sellerParams);

            // Platform fee: separate transfer from buyer to feeRecipient
            if (fee > 0) {
                IERC20(params.token).safeTransferFrom(msg.sender, feeRecipient, fee);
            }
        } else {
            // Escrow: full amount (price + fee) to escrow via PaymentVerifier
            uint256 totalCost = listing.price + fee;

            IPaymentVerifier.PaymentParams memory escrowParams = IPaymentVerifier.PaymentParams({
                payer: params.payer,
                recipient: address(escrow),
                token: params.token,
                amount: totalCost,
                validAfter: params.validAfter,
                validBefore: params.validBefore,
                nonce: params.nonce,
                v: params.v,
                r: params.r,
                s: params.s
            });

            paymentId = verifier.processPayment(escrowParams);
            uint256 escrowId = escrow.fund(listingId, msg.sender, listing.seller, params.token, totalCost, fee);
            _listingEscrowIds[listingId] = escrowId;
            _hasEscrow[listingId] = true;
        }

        listing.status = ListingStatus.Completed;
        listing.updatedAt = block.timestamp;

        totalPurchases++;
        totalVolume += listing.price;

        emit ListingPurchased(listingId, msg.sender, listing.seller, listing.price, fee);

        return paymentId;
    }

    // ============ Bounty Listing Functions ============

    /**
     * @dev Create a bounty. Creator pays reward + platform fee.
     *      Fee goes to feeRecipient immediately. Reward held by marketplace.
     */
    function createBounty(
        address token,
        uint256 reward,
        string calldata metadata
    ) external override nonReentrant whenNotPaused returns (uint256) {
        if (!_supportedTokens[token]) {
            revert InvalidToken();
        }
        if (reward == 0) {
            revert InvalidPrice();
        }

        uint256 agentId = identityRegistry.getAgentId(msg.sender);
        if (agentId == 0) {
            revert NotAgent();
        }

        uint256 fee = (reward * platformFeeBps) / 10000;
        uint256 totalCost = reward + fee;

        uint256 listingId = _listingCount;
        _listingCount++;

        // Collect total payment (reward + fee) from creator
        IERC20(token).safeTransferFrom(msg.sender, address(this), totalCost);

        // Send fee to fee recipient immediately
        if (fee > 0) {
            IERC20(token).safeTransfer(feeRecipient, fee);
        }

        _bounties[listingId] = Bounty({
            listingId: listingId,
            agentId: agentId,
            creator: msg.sender,
            bountyStatus: BountyStatus.Open,
            token: token,
            reward: reward,
            claimerAgentId: 0,
            claimer: address(0),
            metadata: metadata,
            createdAt: block.timestamp,
            claimedAt: 0,
            completedAt: 0,
            claimTimeout: DEFAULT_CLAIM_TIMEOUT,
            claimDeadline: 0
        });

        emit ListingCreated(listingId, agentId, msg.sender, ListingType.Bounty, token, reward);

        return listingId;
    }

    /**
     * @inheritdoc IMarketplace
     */
    function claimBounty(uint256 listingId) external override whenNotPaused {
        Bounty storage bounty = _bounties[listingId];
        if (bounty.listingId != listingId) {
            revert ListingNotFound(listingId);
        }
        if (bounty.bountyStatus != BountyStatus.Open) {
            revert BountyNotOpen(listingId);
        }

        uint256 agentId = identityRegistry.getAgentId(msg.sender);
        if (agentId == 0) {
            revert NotAgent();
        }

        bounty.bountyStatus = BountyStatus.Claimed;
        bounty.claimerAgentId = agentId;
        bounty.claimer = msg.sender;
        bounty.claimedAt = block.timestamp;
        bounty.claimDeadline = block.timestamp + bounty.claimTimeout;

        emit BountyClaimed(listingId, agentId, msg.sender);
    }

    /**
     * @inheritdoc IMarketplace
     */
    function completeBounty(uint256 listingId) external override whenNotPaused {
        Bounty storage bounty = _bounties[listingId];
        if (bounty.listingId != listingId) {
            revert ListingNotFound(listingId);
        }
        if (bounty.bountyStatus != BountyStatus.Claimed) {
            revert BountyNotClaimed(listingId);
        }
        if (bounty.claimer != msg.sender) {
            revert NotClaimer(listingId);
        }

        bounty.bountyStatus = BountyStatus.Completed;
        bounty.completedAt = block.timestamp;

        emit BountyCompleted(listingId, bounty.claimerAgentId);
    }

    /**
     * @dev Pay completed bounty reward to claimer.
     */
    function payBounty(uint256 listingId) external override nonReentrant whenNotPaused returns (uint256) {
        Bounty storage bounty = _bounties[listingId];
        if (bounty.listingId != listingId) {
            revert ListingNotFound(listingId);
        }
        if (bounty.bountyStatus != BountyStatus.Completed) {
            revert BountyNotCompleted(listingId);
        }

        bounty.bountyStatus = BountyStatus.Paid;

        // Transfer reward to claimer
        IERC20(bounty.token).safeTransfer(bounty.claimer, bounty.reward);

        totalBountiesPaid++;
        totalVolume += bounty.reward;

        emit BountyPaid(listingId, bounty.claimerAgentId, bounty.reward);

        return listingId;
    }

    /**
     * @inheritdoc IMarketplace
     */
    function unclaimBounty(uint256 listingId) external override whenNotPaused {
        Bounty storage bounty = _bounties[listingId];
        if (bounty.listingId != listingId) {
            revert ListingNotFound(listingId);
        }
        if (bounty.bountyStatus != BountyStatus.Claimed) {
            revert BountyNotClaimed(listingId);
        }

        // Creator can unclaim after deadline, or claimer can release anytime
        if (msg.sender == bounty.claimer) {
            // Claimer voluntarily releases
        } else if (msg.sender == bounty.creator && block.timestamp >= bounty.claimDeadline) {
            // Creator unclaims after deadline expired
        } else if (msg.sender == bounty.creator) {
            revert ClaimDeadlineNotExpired(listingId);
        } else {
            revert NotClaimer(listingId);
        }

        address previousClaimer = bounty.claimer;
        bounty.bountyStatus = BountyStatus.Open;
        bounty.claimerAgentId = 0;
        bounty.claimer = address(0);
        bounty.claimedAt = 0;
        bounty.claimDeadline = 0;

        emit BountyUnclaimed(listingId, previousClaimer);
    }

    /**
     * @inheritdoc IMarketplace
     */
    function releaseEscrow(uint256 listingId) external override nonReentrant whenNotPaused {
        Listing storage listing = _listings[listingId];
        if (listing.listingId != listingId || listing.listingType != ListingType.Service) {
            revert ListingNotFound(listingId);
        }
        if (listing.seller != msg.sender) {
            revert NotListingSeller(listingId);
        }

        uint256 escrowId = _listingEscrowIds[listingId];
        if (!_hasEscrow[listingId]) {
            revert NoEscrowForListing(listingId);
        }

        escrow.release(escrowId, feeRecipient);
        _hasEscrow[listingId] = false;
        emit EscrowReleased(listingId, escrowId);
    }

    // ============ View Functions ============

    /**
     * @inheritdoc IMarketplace
     */
    function getListing(uint256 listingId) external view override returns (Listing memory) {
        return _listings[listingId];
    }

    /**
     * @inheritdoc IMarketplace
     */
    function getBounty(uint256 listingId) external view override returns (Bounty memory) {
        return _bounties[listingId];
    }

    /**
     * @inheritdoc IMarketplace
     */
    function getListingCount() external view override returns (uint256) {
        return _listingCount;
    }

    /**
     * @inheritdoc IMarketplace
     */
    function getPlatformFeeBps() external view override returns (uint256) {
        return platformFeeBps;
    }

    /**
     * @inheritdoc IMarketplace
     */
    function getEscrowContract() external view override returns (address) {
        return address(escrow);
    }

    /**
     * @inheritdoc IMarketplace
     */
    function getEscrowThreshold() external view override returns (uint256) {
        return escrowThreshold;
    }

    /**
     * @inheritdoc IMarketplace
     */
    function isSupportedToken(address token) external view override returns (bool) {
        return _supportedTokens[token];
    }

    // ============ Admin Functions ============

    /**
     * @dev Add a supported payment token
     * @param token Token address to support
     */
    function addSupportedToken(address token) external onlyOwner {
        if (token == address(0)) {
            revert ZeroAddress();
        }
        if (!_supportedTokens[token]) {
            _supportedTokens[token] = true;
            _tokenList.push(token);
            emit TokenSupported(token);
        }
    }

    /**
     * @dev Remove a supported payment token
     * @param token Token address to remove
     */
    function removeSupportedToken(address token) external onlyOwner {
        if (_supportedTokens[token]) {
            _supportedTokens[token] = false;
            emit TokenRemoved(token);
        }
    }

    /**
     * @dev Update platform fee
     * @param newFeeBps New fee in basis points
     */
    function setPlatformFee(uint256 newFeeBps) external onlyOwner {
        if (newFeeBps > MAX_PLATFORM_FEE_BPS) {
            revert InvalidFee();
        }
        uint256 oldFee = platformFeeBps;
        platformFeeBps = newFeeBps;
        emit PlatformFeeUpdated(oldFee, newFeeBps);
    }

    /**
     * @dev Update fee recipient address
     * @param newRecipient New fee recipient address
     */
    function setFeeRecipient(address newRecipient) external onlyOwner {
        if (newRecipient == address(0)) {
            revert ZeroAddress();
        }
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    /**
     * @dev Update escrow threshold
     * @param newThreshold New threshold amount
     */
    function setEscrowThreshold(uint256 newThreshold) external onlyOwner {
        uint256 oldThreshold = escrowThreshold;
        escrowThreshold = newThreshold;
        emit EscrowThresholdUpdated(oldThreshold, newThreshold);
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
