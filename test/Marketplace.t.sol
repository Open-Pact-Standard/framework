// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "contracts/payments/PaymentLedger.sol";
import "contracts/payments/PaymentVerifier.sol";
import "contracts/payments/Marketplace.sol";
import "contracts/payments/MarketplaceEscrow.sol";
import "contracts/interfaces/IMarketplace.sol";
import "contracts/interfaces/IMarketplaceEscrow.sol";
import "contracts/interfaces/IPaymentLedger.sol";
import "contracts/interfaces/IPaymentVerifier.sol";
import "contracts/interfaces/IEIP3009.sol";
import "contracts/interfaces/IAgentRegistry.sol";
import "contracts/interfaces/IReputationRegistry.sol";
import "contracts/interfaces/IValidationRegistry.sol";
import "contracts/interfaces/IRevenueSharing.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// ============ Mock Contracts ============

/**
 * @dev Mock EIP-3009 token (same as in PaymentVerifier.t.sol)
 */
contract MockEIP3009Token is IEIP3009, Ownable {
    string public constant name = "USDT0";
    string public constant symbol = "USDT0";
    uint8 public constant decimals = 6;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => mapping(bytes32 => bool)) private _authorizationStates;

    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    bytes32 public DOMAIN_SEPARATOR;

    constructor() Ownable() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(name)),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(_balances[msg.sender] >= amount, "Insufficient balance");
        _balances[msg.sender] -= amount;
        _balances[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(_balances[from] >= amount, "Insufficient balance");
        if (msg.sender != from) {
            require(_allowances[from][msg.sender] >= amount, "Insufficient allowance");
            _allowances[from][msg.sender] -= amount;
        }
        _balances[from] -= amount;
        _balances[to] += amount;
        return true;
    }

    function allowance(address owner_, address spender) external view returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }

    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(block.timestamp >= validAfter, "Authorization not yet valid");
        require(block.timestamp < validBefore, "Authorization expired");
        require(!_authorizationStates[from][nonce], "Authorization already used");

        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
                from,
                to,
                value,
                validAfter,
                validBefore,
                nonce
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );

        address recovered = ecrecover(digest, v, r, s);
        require(recovered == from, "Invalid signature");

        _authorizationStates[from][nonce] = true;
        _balances[from] -= value;
        _balances[to] += value;

        emit AuthorizationUsed(from, nonce);
    }

    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(msg.sender == to, "Receiver must be msg.sender");
        this.transferWithAuthorization(from, to, value, validAfter, validBefore, nonce, v, r, s);
    }

    function cancelAuthorization(
        address authorizer,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external override {
        require(!_authorizationStates[authorizer][nonce], "Already used");

        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("CancelAuthorization(address authorizer,bytes32 nonce)"),
                authorizer,
                nonce
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );

        address recovered = ecrecover(digest, v, r, s);
        require(recovered == authorizer, "Invalid signature");

        _authorizationStates[authorizer][nonce] = true;
        emit AuthorizationCanceled(authorizer, nonce);
    }

    function authorizationState(address authorizer, bytes32 nonce) external view override returns (bool) {
        return _authorizationStates[authorizer][nonce];
    }
}

/**
 * @dev Mock IdentityRegistry - registers agents by wallet
 */
contract MockIdentityRegistry is IAgentRegistry {
    uint256 private _nextId = 1;
    mapping(uint256 => address) private _wallets;
    mapping(address => uint256) private _walletToAgent;

    function registerAgent(address wallet, string memory) public returns (uint256) {
        require(_walletToAgent[wallet] == 0, "Already registered");
        uint256 agentId = _nextId++;
        _wallets[agentId] = wallet;
        _walletToAgent[wallet] = agentId;
        return agentId;
    }

    function register(string memory) external override returns (uint256) {
        return registerAgent(msg.sender, "");
    }

    function setAgentWallet(address) external override {}
    function getAgentWallet(uint256 agentId) external view override returns (address) {
        return _wallets[agentId];
    }
    function getAgentId(address wallet) external view override returns (uint256) {
        return _walletToAgent[wallet];
    }
    function getTotalAgents() external view override returns (uint256) { return _nextId - 1; }
    function agentExists(uint256 agentId) external view override returns (bool) {
        return _wallets[agentId] != address(0);
    }
}

/**
 * @dev Mock ReputationRegistry
 */
contract MockReputationRegistry is IReputationRegistry {
    mapping(uint256 => int256) private _scores;
    mapping(uint256 => uint256) private _reviewCounts;

    function setReputation(uint256 agentId, int256 score) external {
        _scores[agentId] = score;
    }

    function submitReview(uint256, int256, string memory) external override {}
    function getReputation(uint256 agentId) external view override returns (int256) {
        return _scores[agentId];
    }
    function getReviewCount(uint256 agentId) external view override returns (uint256) {
        return _reviewCounts[agentId];
    }
    function getLastReviewTime(uint256, address) external view override returns (uint256) { return 0; }
}

/**
 * @dev Mock ValidationRegistry
 */
contract MockValidationRegistry is IValidationRegistry {
    mapping(uint256 => bool) private _validated;

    function setValidated(uint256 agentId, bool status) external {
        _validated[agentId] = status;
    }

    function registerValidator() external override {}
    function validateAgent(uint256, bool) external override {}
    function isAgentValidated(uint256 agentId) external view override returns (bool) {
        return _validated[agentId];
    }
    function getValidationCount(uint256) external view override returns (uint256) { return 0; }
    function getValidationThreshold() external view override returns (uint256) { return 1; }
    function isValidator(address) external view override returns (bool) { return true; }
    function hasValidatorApproved(uint256, address) external view override returns (bool) { return false; }
}

/**
 * @dev Mock RevenueSharing - just accepts deposits
 */
contract MockRevenueSharing is IRevenueSharing {
    mapping(address => uint256) public totalDeposited;

    function depositNative() external payable override {}
    function depositToken(address token, uint256 amount) external override {
        totalDeposited[token] += amount;
    }
    function claim(address) external override {}
    function setShareholders(address[] calldata, uint256[] calldata) external override {}
    function addShareholder(address, uint256) external override {}
    function removeShareholder(address) external override {}
    function updateShare(address, uint256) external override {}
    function getPendingAmount(address, address) external view override returns (uint256) { return 0; }
    function getShare(address) external view override returns (uint256) { return 10000; }
}

// ============ Test Contract ============

contract MarketplaceTest is Test {
    // Contracts
    PaymentLedger public ledger;
    PaymentVerifier public verifier;
    MockEIP3009Token public token;
    MockIdentityRegistry public identityRegistry;
    MockReputationRegistry public reputationRegistry;
    MockValidationRegistry public validationRegistry;
    MockRevenueSharing public revenueSharing;
    MarketplaceEscrow public escrow;
    Marketplace public marketplace;

    // Addresses
    address public owner;
    address public seller;
    address public buyer;
    address public agent1;
    address public feeRecipient;

    // Private keys
    uint256 public sellerPrivateKey;
    uint256 public buyerPrivateKey;
    uint256 public agent1PrivateKey;

    // Constants
    uint256 constant PLATFORM_FEE_BPS = 250; // 2.5%
    uint256 constant ESCROW_THRESHOLD = 10_000e6; // $10,000
    uint256 constant ESCROW_TIMEOUT = 7 days;

    function setUp() public {
        owner = address(this);

        sellerPrivateKey = 0xA11CE;
        seller = vm.addr(sellerPrivateKey);

        buyerPrivateKey = 0xB0B;
        buyer = vm.addr(buyerPrivateKey);

        agent1PrivateKey = 0xCAFE;
        agent1 = vm.addr(agent1PrivateKey);

        feeRecipient = makeAddr("feeRecipient");

        // Deploy mock contracts
        identityRegistry = new MockIdentityRegistry();
        reputationRegistry = new MockReputationRegistry();
        validationRegistry = new MockValidationRegistry();
        revenueSharing = new MockRevenueSharing();
        token = new MockEIP3009Token();

        // Deploy payment infrastructure
        ledger = new PaymentLedger();
        address[] memory supportedTokens = new address[](1);
        supportedTokens[0] = address(token);
        verifier = new PaymentVerifier(
            address(ledger),
            supportedTokens,
            type(uint256).max,
            100_000_000e6,
            10_000_000e6,
            5_000_000e6,
            90_000_000e6
        );

        // Authorize verifier on ledger
        ledger.addVerifier(address(verifier));

        // Deploy escrow
        escrow = new MarketplaceEscrow(ESCROW_TIMEOUT);

        // Deploy marketplace
        marketplace = new Marketplace(
            address(verifier),
            address(ledger),
            address(identityRegistry),
            address(reputationRegistry),
            address(validationRegistry),
            address(revenueSharing),
            address(escrow),
            feeRecipient,
            PLATFORM_FEE_BPS,
            ESCROW_THRESHOLD
        );

        // Configure: marketplace as facilitator on verifier
        verifier.setFacilitator(address(marketplace), true);

        // Configure: marketplace as verifier on ledger
        ledger.addVerifier(address(marketplace));

        // Configure: marketplace authorized on escrow
        escrow.setMarketplace(address(marketplace));

        // Register agents
        identityRegistry.registerAgent(seller, "");
        identityRegistry.registerAgent(buyer, "");
        identityRegistry.registerAgent(agent1, "");

        // Add supported token to marketplace
        marketplace.addSupportedToken(address(token));

        // Mint tokens
        token.mint(buyer, 1_000_000e6);
        token.mint(seller, 1_000_000e6);
        token.mint(agent1, 1_000_000e6);

        // Approve marketplace to spend tokens (for safeTransferFrom)
        vm.prank(buyer);
        token.approve(address(marketplace), type(uint256).max);
        vm.prank(seller);
        token.approve(address(marketplace), type(uint256).max);
        vm.prank(agent1);
        token.approve(address(marketplace), type(uint256).max);
    }

    // ============ Deployment Tests ============

    function testDeployment() public {
        assertEq(address(marketplace.verifier()), address(verifier));
        assertEq(address(marketplace.ledger()), address(ledger));
        assertEq(address(marketplace.identityRegistry()), address(identityRegistry));
        assertEq(marketplace.platformFeeBps(), PLATFORM_FEE_BPS);
        assertEq(marketplace.feeRecipient(), feeRecipient);
        assertEq(marketplace.escrowThreshold(), ESCROW_THRESHOLD);
        assertTrue(marketplace.isSupportedToken(address(token)));
    }

    function testCannotDeployWithZeroAddresses() public {
        vm.expectRevert();
        new Marketplace(
            address(0), address(ledger), address(identityRegistry),
            address(reputationRegistry), address(validationRegistry),
            address(revenueSharing), address(escrow), feeRecipient,
            PLATFORM_FEE_BPS, ESCROW_THRESHOLD
        );
    }

    function testCannotDeployWithInvalidFee() public {
        vm.expectRevert();
        new Marketplace(
            address(verifier), address(ledger), address(identityRegistry),
            address(reputationRegistry), address(validationRegistry),
            address(revenueSharing), address(escrow), feeRecipient,
            10001, ESCROW_THRESHOLD
        );
    }

    // ============ Service Listing CRUD Tests ============

    function testCreateListing() public {
        uint256 price = 100e6;
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(token), price, "ipfs://listing");

        assertEq(listingId, 0);
        assertEq(marketplace.getListingCount(), 1);

        IMarketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(listing.seller, seller);
        assertEq(listing.price, price);
        assertEq(listing.token, address(token));
        assertEq(uint256(listing.status), uint256(IMarketplace.ListingStatus.Active));
        assertEq(uint256(listing.listingType), uint256(IMarketplace.ListingType.Service));
    }

    function testCreateListingEmitsEvent() public {
        vm.prank(seller);
        vm.expectEmit(true, true, true, false);
        emit IMarketplace.ListingCreated(0, 1, seller, IMarketplace.ListingType.Service, address(token), 100e6);
        marketplace.createListing(address(token), 100e6, "ipfs://listing");
    }

    function testCannotCreateListingIfNotAgent() public {
        address nonAgent = makeAddr("nonAgent");
        vm.prank(nonAgent);
        vm.expectRevert(abi.encodeWithSignature("NotAgent()"));
        marketplace.createListing(address(token), 100e6, "ipfs://listing");
    }

    function testCannotCreateListingWithInvalidToken() public {
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSignature("InvalidToken()"));
        marketplace.createListing(makeAddr("badToken"), 100e6, "ipfs://listing");
    }

    function testCannotCreateListingWithZeroPrice() public {
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSignature("InvalidPrice()"));
        marketplace.createListing(address(token), 0, "ipfs://listing");
    }

    function testUpdateListing() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(token), 100e6, "ipfs://listing");

        vm.prank(seller);
        marketplace.updateListing(listingId, 200e6, "ipfs://listing-v2");

        IMarketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(listing.price, 200e6);
    }

    function testCannotUpdateIfNotOwner() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(token), 100e6, "ipfs://listing");

        vm.prank(agent1);
        vm.expectRevert(abi.encodeWithSignature("NotListingOwner(uint256)", listingId));
        marketplace.updateListing(listingId, 200e6, "ipfs://listing-v2");
    }

    function testCancelListing() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(token), 100e6, "ipfs://listing");

        vm.prank(seller);
        marketplace.cancelListing(listingId);

        IMarketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(uint256(listing.status), uint256(IMarketplace.ListingStatus.Canceled));
    }

    function testCannotCancelIfNotOwner() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(token), 100e6, "ipfs://listing");

        vm.prank(agent1);
        vm.expectRevert(abi.encodeWithSignature("NotListingOwner(uint256)", listingId));
        marketplace.cancelListing(listingId);
    }

    function testCannotUpdateCanceledListing() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(token), 100e6, "ipfs://listing");

        vm.prank(seller);
        marketplace.cancelListing(listingId);

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSignature("ListingNotActive(uint256)", listingId));
        marketplace.updateListing(listingId, 200e6, "ipfs://listing-v2");
    }

    // ============ Service Purchase Tests ============

    function testPurchaseListingDirect() public {
        uint256 price = 100e6; // Below escrow threshold
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(token), price, "ipfs://listing");

        // Sign authorization for seller payment (listing.price)
        uint256 validAfter = block.timestamp;
        uint256 validBefore = block.timestamp + 3600;
        bytes32 nonce = keccak256("purchase-nonce");

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuthorization(
            buyerPrivateKey, seller, price, validAfter, validBefore, nonce
        );

        IPaymentVerifier.PaymentParams memory params = IPaymentVerifier.PaymentParams({
            payer: buyer,
            recipient: seller,
            token: address(token),
            amount: price,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            v: v,
            r: r,
            s: s
        });

        uint256 sellerBalBefore = token.balanceOf(seller);

        vm.prank(buyer);
        marketplace.purchaseListing(listingId, params);

        // Seller received listing price
        assertEq(token.balanceOf(seller), sellerBalBefore + price);

        // Listing is completed
        IMarketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(uint256(listing.status), uint256(IMarketplace.ListingStatus.Completed));

        // Counters updated
        assertEq(marketplace.totalPurchases(), 1);
        assertEq(marketplace.totalVolume(), price);
    }

    function testCannotBuyOwnListing() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(token), 100e6, "ipfs://listing");

        // Seller tries to buy own listing
        uint256 privateKey = sellerPrivateKey;
        address sellerAddr = seller;

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuthorization(
            privateKey, sellerAddr, 100e6, block.timestamp, block.timestamp + 3600, keccak256("own")
        );

        IPaymentVerifier.PaymentParams memory params = IPaymentVerifier.PaymentParams({
            payer: seller,
            recipient: seller,
            token: address(token),
            amount: 100e6,
            validAfter: block.timestamp,
            validBefore: block.timestamp + 3600,
            nonce: keccak256("own"),
            v: v,
            r: r,
            s: s
        });

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSignature("CannotBuyOwnListing()"));
        marketplace.purchaseListing(listingId, params);
    }

    function testCannotPurchaseInactiveListing() public {
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(token), 100e6, "ipfs://listing");
        vm.prank(seller);
        marketplace.cancelListing(listingId);

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuthorization(
            buyerPrivateKey, seller, 100e6, block.timestamp, block.timestamp + 3600, keccak256("inactive")
        );

        IPaymentVerifier.PaymentParams memory params = IPaymentVerifier.PaymentParams({
            payer: buyer,
            recipient: seller,
            token: address(token),
            amount: 100e6,
            validAfter: block.timestamp,
            validBefore: block.timestamp + 3600,
            nonce: keccak256("inactive"),
            v: v,
            r: r,
            s: s
        });

        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSignature("ListingNotActive(uint256)", listingId));
        marketplace.purchaseListing(listingId, params);
    }

    // ============ Bounty Tests ============

    function testCreateBounty() public {
        uint256 reward = 500e6;
        uint256 fee = (reward * PLATFORM_FEE_BPS) / 10000;

        vm.prank(agent1);
        uint256 listingId = marketplace.createBounty(address(token), reward, "ipfs://bounty");

        IMarketplace.Bounty memory bounty = marketplace.getBounty(listingId);
        assertEq(bounty.creator, agent1);
        assertEq(bounty.reward, reward);
        assertEq(uint256(bounty.bountyStatus), uint256(IMarketplace.BountyStatus.Open));

        // Fee was sent to fee recipient
        // (tokens were minted to agent1 in setUp, fee goes to feeRecipient)
    }

    function testBountyFullLifecycle() public {
        uint256 reward = 500e6;

        // Create bounty
        vm.prank(agent1);
        uint256 listingId = marketplace.createBounty(address(token), reward, "ipfs://bounty");

        // Claim bounty (as seller)
        vm.prank(seller);
        marketplace.claimBounty(listingId);

        IMarketplace.Bounty memory bounty = marketplace.getBounty(listingId);
        assertEq(uint256(bounty.bountyStatus), uint256(IMarketplace.BountyStatus.Claimed));
        assertEq(bounty.claimer, seller);

        // Complete bounty (as claimer)
        vm.prank(seller);
        marketplace.completeBounty(listingId);

        bounty = marketplace.getBounty(listingId);
        assertEq(uint256(bounty.bountyStatus), uint256(IMarketplace.BountyStatus.Completed));

        // Pay bounty
        uint256 claimerBalBefore = token.balanceOf(seller);
        marketplace.payBounty(listingId);

        bounty = marketplace.getBounty(listingId);
        assertEq(uint256(bounty.bountyStatus), uint256(IMarketplace.BountyStatus.Paid));
        assertEq(token.balanceOf(seller), claimerBalBefore + reward);
        assertEq(marketplace.totalBountiesPaid(), 1);
    }

    function testCannotClaimNonOpenBounty() public {
        uint256 reward = 500e6;
        vm.prank(agent1);
        uint256 listingId = marketplace.createBounty(address(token), reward, "ipfs://bounty");

        // First claim succeeds
        vm.prank(seller);
        marketplace.claimBounty(listingId);

        // Second claim fails
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSignature("BountyNotOpen(uint256)", listingId));
        marketplace.claimBounty(listingId);
    }

    function testCannotCompleteIfNotClaimer() public {
        uint256 reward = 500e6;
        vm.prank(agent1);
        uint256 listingId = marketplace.createBounty(address(token), reward, "ipfs://bounty");

        vm.prank(seller);
        marketplace.claimBounty(listingId);

        // Different user tries to complete
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSignature("NotClaimer(uint256)", listingId));
        marketplace.completeBounty(listingId);
    }

    function testCannotPayIncompleteBounty() public {
        uint256 reward = 500e6;
        vm.prank(agent1);
        uint256 listingId = marketplace.createBounty(address(token), reward, "ipfs://bounty");

        vm.prank(seller);
        marketplace.claimBounty(listingId);

        // Try to pay without completing
        vm.expectRevert(abi.encodeWithSignature("BountyNotCompleted(uint256)", listingId));
        marketplace.payBounty(listingId);
    }

    // ============ Admin Tests ============

    function testSetPlatformFee() public {
        marketplace.setPlatformFee(500); // 5%
        assertEq(marketplace.platformFeeBps(), 500);
    }

    function testCannotSetInvalidFee() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidFee()"));
        marketplace.setPlatformFee(10001);
    }

    function testSetFeeRecipient() public {
        address newRecipient = makeAddr("newRecipient");
        marketplace.setFeeRecipient(newRecipient);
        assertEq(marketplace.feeRecipient(), newRecipient);
    }

    function testSetEscrowThreshold() public {
        marketplace.setEscrowThreshold(50_000e6);
        assertEq(marketplace.escrowThreshold(), 50_000e6);
    }

    function testAddRemoveSupportedToken() public {
        address newToken = makeAddr("newToken");
        assertFalse(marketplace.isSupportedToken(newToken));

        marketplace.addSupportedToken(newToken);
        assertTrue(marketplace.isSupportedToken(newToken));

        marketplace.removeSupportedToken(newToken);
        assertFalse(marketplace.isSupportedToken(newToken));
    }

    function testOnlyOwnerCanAdmin() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        marketplace.setPlatformFee(500);
    }

    // ============ Escrow Purchase Tests ============

    function testPurchaseListingEscrow() public {
        // Price above escrow threshold -> escrow path
        uint256 price = 20_000e6; // Above $10,000 threshold
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(token), price, "ipfs://listing");

        uint256 fee = (price * PLATFORM_FEE_BPS) / 10000;
        uint256 totalCost = price + fee;

        // Sign authorization for total cost to escrow
        uint256 validAfter = block.timestamp;
        uint256 validBefore = block.timestamp + 3600;
        bytes32 nonce = keccak256("escrow-purchase");

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuthorization(
            buyerPrivateKey, address(escrow), totalCost, validAfter, validBefore, nonce
        );

        IPaymentVerifier.PaymentParams memory params = IPaymentVerifier.PaymentParams({
            payer: buyer,
            recipient: address(escrow),
            token: address(token),
            amount: totalCost,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            v: v,
            r: r,
            s: s
        });

        vm.prank(buyer);
        marketplace.purchaseListing(listingId, params);

        // Listing is completed
        IMarketplace.Listing memory listing = marketplace.getListing(listingId);
        assertEq(uint256(listing.status), uint256(IMarketplace.ListingStatus.Completed));

        // Escrow was funded
        assertEq(escrow.getEscrowCount(), 1);
    }

    // ============ Event Emission Tests ============

    function testBountyClaimedEmitsEvent() public {
        uint256 reward = 500e6;

        vm.prank(agent1);
        uint256 listingId = marketplace.createBounty(address(token), reward, "ipfs://bounty");

        vm.prank(seller);
        vm.expectEmit(true, true, true, false);
        emit IMarketplace.BountyClaimed(listingId, 1, seller);
        marketplace.claimBounty(listingId);
    }

    function testBountyCompletedEmitsEvent() public {
        uint256 reward = 500e6;

        vm.prank(agent1);
        uint256 listingId = marketplace.createBounty(address(token), reward, "ipfs://bounty");

        vm.prank(seller);
        marketplace.claimBounty(listingId);

        vm.prank(seller);
        vm.expectEmit(true, true, false, false);
        emit IMarketplace.BountyCompleted(listingId, 1);
        marketplace.completeBounty(listingId);
    }

    function testBountyPaidEmitsEvent() public {
        uint256 reward = 500e6;

        vm.prank(agent1);
        uint256 listingId = marketplace.createBounty(address(token), reward, "ipfs://bounty");

        vm.prank(seller);
        marketplace.claimBounty(listingId);

        vm.prank(seller);
        marketplace.completeBounty(listingId);

        vm.expectEmit(true, true, false, false);
        emit IMarketplace.BountyPaid(listingId, 1, reward);
        marketplace.payBounty(listingId);
    }

    function testPlatformFeeUpdatedEmitsEvent() public {
        vm.expectEmit(false, false, false, false);
        emit IMarketplace.PlatformFeeUpdated(PLATFORM_FEE_BPS, 500);
        marketplace.setPlatformFee(500);
    }

    function testFeeRecipientUpdatedEmitsEvent() public {
        address newRecipient = makeAddr("newRecipient");
        vm.expectEmit(true, true, false, false);
        emit IMarketplace.FeeRecipientUpdated(feeRecipient, newRecipient);
        marketplace.setFeeRecipient(newRecipient);
    }

    function testEscrowThresholdUpdatedEmitsEvent() public {
        vm.expectEmit(false, false, false, false);
        emit IMarketplace.EscrowThresholdUpdated(ESCROW_THRESHOLD, 50_000e6);
        marketplace.setEscrowThreshold(50_000e6);
    }

    function testTokenSupportedEmitsEvent() public {
        address newToken = makeAddr("newToken");
        vm.expectEmit(true, false, false, false);
        emit IMarketplace.TokenSupported(newToken);
        marketplace.addSupportedToken(newToken);
    }

    function testTokenRemovedEmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit IMarketplace.TokenRemoved(address(token));
        marketplace.removeSupportedToken(address(token));
    }

    // ============ Access Control Negative Tests ============

    function testOnlyOwnerCanPause() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        marketplace.pause();
    }

    function testOnlyOwnerCanUnpause() public {
        marketplace.pause();
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        marketplace.unpause();
    }

    function testOnlyOwnerCanSetEscrowThreshold() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        marketplace.setEscrowThreshold(50_000e6);
    }

    function testOnlyOwnerCanSetFeeRecipient() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        marketplace.setFeeRecipient(makeAddr("new"));
    }

    function testOnlyOwnerCanAddSupportedToken() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        marketplace.addSupportedToken(makeAddr("new"));
    }

    function testOnlyOwnerCanRemoveSupportedToken() public {
        vm.prank(makeAddr("notOwner"));
        vm.expectRevert("Ownable: caller is not the owner");
        marketplace.removeSupportedToken(address(token));
    }

    // ============ Bounty Unclaim Tests ============

    function testClaimerCanUnclaim() public {
        uint256 reward = 500e6;

        vm.prank(agent1);
        uint256 listingId = marketplace.createBounty(address(token), reward, "ipfs://bounty");

        vm.prank(seller);
        marketplace.claimBounty(listingId);

        // Claimer voluntarily unclaims
        vm.prank(seller);
        marketplace.unclaimBounty(listingId);

        IMarketplace.Bounty memory bounty = marketplace.getBounty(listingId);
        assertEq(uint256(bounty.bountyStatus), uint256(IMarketplace.BountyStatus.Open));
        assertEq(bounty.claimer, address(0));
    }

    function testCreatorCanUnclaimAfterDeadline() public {
        uint256 reward = 500e6;

        vm.prank(agent1);
        uint256 listingId = marketplace.createBounty(address(token), reward, "ipfs://bounty");

        vm.prank(seller);
        marketplace.claimBounty(listingId);

        // Warp past claim deadline (7 days)
        vm.warp(block.timestamp + 8 days);

        // Creator unclaims after deadline
        vm.prank(agent1);
        marketplace.unclaimBounty(listingId);

        IMarketplace.Bounty memory bounty = marketplace.getBounty(listingId);
        assertEq(uint256(bounty.bountyStatus), uint256(IMarketplace.BountyStatus.Open));
    }

    function testCreatorCannotUnclaimBeforeDeadline() public {
        uint256 reward = 500e6;

        vm.prank(agent1);
        uint256 listingId = marketplace.createBounty(address(token), reward, "ipfs://bounty");

        vm.prank(seller);
        marketplace.claimBounty(listingId);

        // Creator tries to unclaim immediately
        vm.prank(agent1);
        vm.expectRevert(abi.encodeWithSignature("ClaimDeadlineNotExpired(uint256)", listingId));
        marketplace.unclaimBounty(listingId);
    }

    function testNonClaimerNonCreatorCannotUnclaim() public {
        uint256 reward = 500e6;

        vm.prank(agent1);
        uint256 listingId = marketplace.createBounty(address(token), reward, "ipfs://bounty");

        vm.prank(seller);
        marketplace.claimBounty(listingId);

        // Random user tries to unclaim
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSignature("NotClaimer(uint256)", listingId));
        marketplace.unclaimBounty(listingId);
    }

    function testBountyUnclaimedEmitsEvent() public {
        uint256 reward = 500e6;

        vm.prank(agent1);
        uint256 listingId = marketplace.createBounty(address(token), reward, "ipfs://bounty");

        vm.prank(seller);
        marketplace.claimBounty(listingId);

        vm.prank(seller);
        vm.expectEmit(true, true, false, false);
        emit IMarketplace.BountyUnclaimed(listingId, seller);
        marketplace.unclaimBounty(listingId);
    }

    // ============ No Double Fee Tests ============

    function testDirectPurchaseNoDoubleFee() public {
        uint256 price = 100e6;
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(token), price, "ipfs://listing");

        uint256 fee = (price * PLATFORM_FEE_BPS) / 10000;

        uint256 validAfter = block.timestamp;
        uint256 validBefore = block.timestamp + 3600;
        bytes32 nonce = keccak256("no-double-fee");

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuthorization(
            buyerPrivateKey, seller, price, validAfter, validBefore, nonce
        );

        IPaymentVerifier.PaymentParams memory params = IPaymentVerifier.PaymentParams({
            payer: buyer,
            recipient: seller,
            token: address(token),
            amount: price,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            v: v,
            r: r,
            s: s
        });

        uint256 buyerBalBefore = token.balanceOf(buyer);
        vm.prank(buyer);
        marketplace.purchaseListing(listingId, params);

        // Buyer should pay: price (to seller via EIP-3009) + fee (to feeRecipient)
        // NOT price + 2*fee
        uint256 buyerBalAfter = token.balanceOf(buyer);
        assertEq(buyerBalBefore - buyerBalAfter, price + fee);
    }

    // ============ Escrow Release Tests ============

    function testSellerCanReleaseEscrow() public {
        uint256 price = 20_000e6; // Above escrow threshold
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(token), price, "ipfs://listing");

        uint256 fee = (price * PLATFORM_FEE_BPS) / 10000;
        uint256 totalCost = price + fee;

        uint256 validAfter = block.timestamp;
        uint256 validBefore = block.timestamp + 3600;
        bytes32 nonce = keccak256("escrow-release");

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuthorization(
            buyerPrivateKey, address(escrow), totalCost, validAfter, validBefore, nonce
        );

        IPaymentVerifier.PaymentParams memory params = IPaymentVerifier.PaymentParams({
            payer: buyer,
            recipient: address(escrow),
            token: address(token),
            amount: totalCost,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            v: v,
            r: r,
            s: s
        });

        vm.prank(buyer);
        marketplace.purchaseListing(listingId, params);

        // Seller releases escrow
        uint256 sellerBalBefore = token.balanceOf(seller);
        vm.prank(seller);
        marketplace.releaseEscrow(listingId);

        // Seller received net amount
        assertGt(token.balanceOf(seller), sellerBalBefore);
    }

    function testOnlySellerCanReleaseEscrow() public {
        uint256 price = 20_000e6;
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(token), price, "ipfs://listing");

        uint256 fee = (price * PLATFORM_FEE_BPS) / 10000;
        uint256 totalCost = price + fee;

        uint256 validAfter = block.timestamp;
        uint256 validBefore = block.timestamp + 3600;
        bytes32 nonce = keccak256("escrow-auth");

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuthorization(
            buyerPrivateKey, address(escrow), totalCost, validAfter, validBefore, nonce
        );

        IPaymentVerifier.PaymentParams memory params = IPaymentVerifier.PaymentParams({
            payer: buyer,
            recipient: address(escrow),
            token: address(token),
            amount: totalCost,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            v: v,
            r: r,
            s: s
        });

        vm.prank(buyer);
        marketplace.purchaseListing(listingId, params);

        // Non-seller cannot release
        vm.prank(buyer);
        vm.expectRevert(abi.encodeWithSignature("NotListingSeller(uint256)", listingId));
        marketplace.releaseEscrow(listingId);
    }

    // ============ Helpers ============

    function testEscrowCleanedUpAfterRelease() public {
        uint256 price = 20_000e6;
        vm.prank(seller);
        uint256 listingId = marketplace.createListing(address(token), price, "ipfs://listing");

        uint256 fee = (price * PLATFORM_FEE_BPS) / 10000;
        uint256 totalCost = price + fee;

        uint256 validAfter = block.timestamp;
        uint256 validBefore = block.timestamp + 3600;
        bytes32 nonce = keccak256("escrow-cleanup");

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuthorization(
            buyerPrivateKey, address(escrow), totalCost, validAfter, validBefore, nonce
        );

        IPaymentVerifier.PaymentParams memory params = IPaymentVerifier.PaymentParams({
            payer: buyer,
            recipient: address(escrow),
            token: address(token),
            amount: totalCost,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            v: v,
            r: r,
            s: s
        });

        vm.prank(buyer);
        marketplace.purchaseListing(listingId, params);

        // Release escrow
        vm.prank(seller);
        marketplace.releaseEscrow(listingId);

        // Trying to release again should revert with NoEscrowForListing
        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSignature("NoEscrowForListing(uint256)", listingId));
        marketplace.releaseEscrow(listingId);
    }

    function _signTransferAuthorization(
        uint256 privateKey,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(
                token.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                vm.addr(privateKey),
                to,
                value,
                validAfter,
                validBefore,
                nonce
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                structHash
            )
        );

        (v, r, s) = vm.sign(privateKey, digest);
    }
}
