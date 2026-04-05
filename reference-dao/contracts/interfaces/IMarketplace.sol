// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "./IPaymentVerifier.sol";

/**
 * @title IMarketplace
 * @dev Interface for the agent marketplace contract.
 *      Supports service listings (pay-to-use) and bounty listings
 *      (post-work, claim, complete, get paid).
 *      Integrates with PaymentVerifier, IdentityRegistry, ReputationRegistry,
 *      and ValidationRegistry.
 */
interface IMarketplace {
    /**
     * @dev Listing type
     */
    enum ListingType {
        Service,    // Pay-to-use: buyer pays seller
        Bounty      // Post work: agent claims, completes, gets paid
    }

    /**
     * @dev Listing status
     */
    enum ListingStatus {
        Active,
        Completed,
        Canceled
    }

    /**
     * @dev Bounty claim status
     */
    enum BountyStatus {
        Open,
        Claimed,
        Completed,
        Paid
    }

    /**
     * @dev Service listing structure
     */
    struct Listing {
        uint256 listingId;
        uint256 agentId;
        address seller;
        ListingType listingType;
        ListingStatus status;
        address token;
        uint256 price;
        string metadata;
        uint256 createdAt;
        uint256 updatedAt;
    }

    /**
     * @dev Bounty listing structure
     */
    struct Bounty {
        uint256 listingId;
        uint256 agentId;
        address creator;
        BountyStatus bountyStatus;
        address token;
        uint256 reward;
        uint256 claimerAgentId;
        address claimer;
        string metadata;
        uint256 createdAt;
        uint256 claimedAt;
        uint256 completedAt;
        uint256 claimTimeout;
        uint256 claimDeadline;
    }

    // -- Events --

    event ListingCreated(uint256 indexed listingId, uint256 indexed agentId, address indexed seller, ListingType listingType, address token, uint256 price);
    event ListingUpdated(uint256 indexed listingId, uint256 price, string metadata);
    event ListingCanceled(uint256 indexed listingId);
    event ListingPurchased(uint256 indexed listingId, address indexed buyer, address indexed seller, uint256 amount, uint256 platformFee);
    event BountyClaimed(uint256 indexed listingId, uint256 indexed claimerAgentId, address indexed claimer);
    event BountyCompleted(uint256 indexed listingId, uint256 indexed claimerAgentId);
    event BountyPaid(uint256 indexed listingId, uint256 indexed claimerAgentId, uint256 amount);
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event EscrowThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event TokenSupported(address indexed token);
    event TokenRemoved(address indexed token);
    event BountyUnclaimed(uint256 indexed listingId, address indexed claimer);
    event EscrowReleased(uint256 indexed listingId, uint256 indexed escrowId);

    // -- Errors --

    error NotAgent();
    error NotListingOwner(uint256 listingId);
    error ListingNotActive(uint256 listingId);
    error ListingNotFound(uint256 listingId);
    error InvalidPrice();
    error InvalidToken();
    error CannotBuyOwnListing();
    error BountyNotOpen(uint256 listingId);
    error BountyNotClaimed(uint256 listingId);
    error BountyNotCompleted(uint256 listingId);
    error NotClaimer(uint256 listingId);
    error InsufficientPayment(uint256 required, uint256 provided);
    error TransferFailed(bytes reason);
    error ZeroAddress();
    error InvalidFee();
    error ClaimDeadlineNotExpired(uint256 listingId);
    error NoEscrowForListing(uint256 listingId);
    error NotListingSeller(uint256 listingId);

    // -- Service Listing Functions --

    /**
     * @dev Create a new service listing
     * @param token Payment token address
     * @param price Listing price in token units
     * @param metadata IPFS or HTTPS URI pointing to listing metadata
     * @return listingId The created listing ID
     */
    function createListing(address token, uint256 price, string calldata metadata) external returns (uint256);

    /**
     * @dev Update an existing service listing
     * @param listingId Listing to update
     * @param price New price
     * @param metadata New metadata
     */
    function updateListing(uint256 listingId, uint256 price, string calldata metadata) external;

    /**
     * @dev Cancel a listing
     * @param listingId Listing to cancel
     */
    function cancelListing(uint256 listingId) external;

    /**
     * @dev Purchase a service listing using EIP-3009 authorization
     * @param listingId Listing to purchase
     * @param params Payment parameters (from IPaymentVerifier.PaymentParams)
     * @return paymentId Payment ID in the ledger
     */
    function purchaseListing(uint256 listingId, IPaymentVerifier.PaymentParams calldata params) external returns (uint256);

    // -- Bounty Listing Functions --

    /**
     * @dev Create a bounty listing
     * @param token Reward token address
     * @param reward Reward amount
     * @param metadata Bounty metadata
     * @return listingId The created bounty listing ID
     */
    function createBounty(address token, uint256 reward, string calldata metadata) external returns (uint256);

    /**
     * @dev Claim a bounty
     * @param listingId Bounty to claim
     */
    function claimBounty(uint256 listingId) external;

    /**
     * @dev Unclaim a bounty (creator can unclaim after deadline, or claimer can release)
     * @param listingId Bounty to unclaim
     */
    function unclaimBounty(uint256 listingId) external;

    /**
     * @dev Mark a bounty as completed (claimer calls this)
     * @param listingId Bounty to complete
     */
    function completeBounty(uint256 listingId) external;

    /**
     * @dev Pay out a completed bounty
     * @param listingId Bounty to pay
     * @return paymentId Payment ID in the ledger
     */
    function payBounty(uint256 listingId) external returns (uint256);

    // -- View Functions --

    function getListing(uint256 listingId) external view returns (Listing memory);
    function getBounty(uint256 listingId) external view returns (Bounty memory);
    function getListingCount() external view returns (uint256);
    function getPlatformFeeBps() external view returns (uint256);
    function getEscrowContract() external view returns (address);
    function getEscrowThreshold() external view returns (uint256);
    function isSupportedToken(address token) external view returns (bool);

    /**
     * @dev Release escrowed funds for a listing (seller confirms delivery)
     * @param listingId Listing to release escrow for
     */
    function releaseEscrow(uint256 listingId) external;

    // -- Admin Functions --

    /**
     * @dev Add a supported payment token
     * @param token Token address to support
     */
    function addSupportedToken(address token) external;

    /**
     * @dev Remove a supported payment token
     * @param token Token address to remove
     */
    function removeSupportedToken(address token) external;

    /**
     * @dev Update platform fee
     * @param newFeeBps New fee in basis points
     */
    function setPlatformFee(uint256 newFeeBps) external;

    /**
     * @dev Update fee recipient address
     * @param newRecipient New fee recipient address
     */
    function setFeeRecipient(address newRecipient) external;

    /**
     * @dev Update escrow threshold
     * @param newThreshold New threshold amount
     */
    function setEscrowThreshold(uint256 newThreshold) external;
}
