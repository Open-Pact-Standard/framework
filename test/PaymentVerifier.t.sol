// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "contracts/payments/PaymentLedger.sol";
import "contracts/payments/PaymentVerifier.sol";
import "contracts/interfaces/IEIP3009.sol";
import "contracts/interfaces/IPaymentLedger.sol";
import "contracts/interfaces/IPaymentVerifier.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MockEIP3009Token
 * @dev Mock ERC20 with EIP-3009 transferWithAuthorization support.
 *      Uses EIP-712 for signature verification in tests.
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
        // Simplified: delegates to transferWithAuthorization logic
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

    function allowance(address owner_, address spender) external view returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        return true;
    }
}

contract PaymentVerifierTest is Test {
    PaymentLedger public ledger;
    PaymentVerifier public verifier;
    MockEIP3009Token public token;

    address public owner;
    address public facilitator;
    address public payer;
    address public recipient;

    uint256 public payerPrivateKey;

    function setUp() public {
        owner = address(this);
        facilitator = makeAddr("facilitator");
        recipient = makeAddr("recipient");

        // Create payer with known private key for signing
        payerPrivateKey = 0xA11CE;
        payer = vm.addr(payerPrivateKey);

        // Deploy contracts
        ledger = new PaymentLedger();
        token = new MockEIP3009Token();

        // Deploy verifier with token as supported
        address[] memory supportedTokens = new address[](1);
        supportedTokens[0] = address(token);
        verifier = new PaymentVerifier(
            address(ledger),
            supportedTokens,
            1_000_000e6,     // maxPaymentAmount
            10_000_000e6,    // maxDailyVolumeGlobal
            1_000_000e6,     // maxDailyVolumePerPayer
            500_000e6,       // maxDailyVolumePerRecipient
            9_000_000e6      // circuitBreakerThreshold
        );

        // Authorize verifier as ledger verifier
        ledger.addVerifier(address(verifier));

        // Add facilitator
        verifier.setFacilitator(facilitator, true);

        // Mint tokens to payer
        token.mint(payer, 10_000e6);
    }

    // --- Deployment ---

    function testDeployment() public {
        assertEq(verifier.getLedger(), address(ledger));
        assertTrue(verifier.isFacilitator(owner));
        assertTrue(verifier.isFacilitator(facilitator));
        assertTrue(verifier.isTokenSupported(address(token)));
    }

    // --- Process Payment ---

    function testProcessPayment() public {
        uint256 amount = 100e6; // $100
        uint256 validAfter = block.timestamp;
        uint256 validBefore = block.timestamp + 3600;
        bytes32 nonce = keccak256("nonce1");

        // Sign the authorization
        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuthorization(
            payerPrivateKey, recipient, amount, validAfter, validBefore, nonce
        );

        IPaymentVerifier.PaymentParams memory params = IPaymentVerifier.PaymentParams({
            payer: payer,
            recipient: recipient,
            token: address(token),
            amount: amount,
            validAfter: validAfter,
            validBefore: validBefore,
            nonce: nonce,
            v: v,
            r: r,
            s: s
        });

        uint256 payerBalanceBefore = token.balanceOf(payer);

        vm.prank(facilitator);
        uint256 ledgerPaymentId = verifier.processPayment(params);

        assertEq(ledgerPaymentId, 0);
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(payer), payerBalanceBefore - amount);

        // Verify ledger record
        IPaymentLedger.PaymentRecord memory record = ledger.getPayment(ledgerPaymentId);
        assertTrue(record.settled);
        assertEq(record.amount, amount);
        assertEq(uint256(record.paymentType), uint256(IPaymentLedger.PaymentType.X402));
    }

    function testProcessPaymentEmitsEvent() public {
        uint256 amount = 50e6;
        bytes32 nonce = keccak256("nonce-event");

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuthorization(
            payerPrivateKey, recipient, amount, block.timestamp, block.timestamp + 3600, nonce
        );

        IPaymentVerifier.PaymentParams memory params = IPaymentVerifier.PaymentParams({
            payer: payer,
            recipient: recipient,
            token: address(token),
            amount: amount,
            validAfter: block.timestamp,
            validBefore: block.timestamp + 3600,
            nonce: nonce,
            v: v,
            r: r,
            s: s
        });

        vm.expectEmit(true, true, true, false);
        emit IPaymentVerifier.PaymentProcessed(payer, recipient, address(token), amount, 0);

        vm.prank(facilitator);
        verifier.processPayment(params);
    }

    // --- Payment Limits ---

    function testCannotProcessBelowMinimum() public {
        verifier.setPaymentLimits(10e6, type(uint256).max);

        uint256 amount = 5e6; // Below 10e6 minimum
        bytes32 nonce = keccak256("nonce-min");

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuthorization(
            payerPrivateKey, recipient, amount, block.timestamp, block.timestamp + 3600, nonce
        );

        IPaymentVerifier.PaymentParams memory params = IPaymentVerifier.PaymentParams({
            payer: payer, recipient: recipient, token: address(token),
            amount: amount, validAfter: block.timestamp, validBefore: block.timestamp + 3600,
            nonce: nonce, v: v, r: r, s: s
        });

        vm.prank(facilitator);
        vm.expectRevert(); // AmountBelowMinimum
        verifier.processPayment(params);
    }

    function testCannotProcessAboveMaximum() public {
        uint256 amount = 2_000_000e6; // Above 1_000_000e6 maximum
        bytes32 nonce = keccak256("nonce-max");

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuthorization(
            payerPrivateKey, recipient, amount, block.timestamp, block.timestamp + 3600, nonce
        );

        IPaymentVerifier.PaymentParams memory params = IPaymentVerifier.PaymentParams({
            payer: payer, recipient: recipient, token: address(token),
            amount: amount, validAfter: block.timestamp, validBefore: block.timestamp + 3600,
            nonce: nonce, v: v, r: r, s: s
        });

        vm.prank(facilitator);
        vm.expectRevert(); // AmountAboveMaximum
        verifier.processPayment(params);
    }

    // --- Authorization Validation ---

    function testCannotProcessExpiredAuthorization() public {
        uint256 amount = 100e6;
        bytes32 nonce = keccak256("nonce-expired");

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuthorization(
            payerPrivateKey, recipient, amount, block.timestamp, block.timestamp + 1, nonce
        );

        // Warp past validBefore
        vm.warp(block.timestamp + 2);

        IPaymentVerifier.PaymentParams memory params = IPaymentVerifier.PaymentParams({
            payer: payer, recipient: recipient, token: address(token),
            amount: amount, validAfter: 0, validBefore: block.timestamp,
            nonce: nonce, v: v, r: r, s: s
        });

        vm.prank(facilitator);
        vm.expectRevert(); // AuthorizationExpired
        verifier.processPayment(params);
    }

    function testCannotProcessNotYetValid() public {
        uint256 amount = 100e6;
        uint256 futureTime = block.timestamp + 3600;
        bytes32 nonce = keccak256("nonce-future");

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuthorization(
            payerPrivateKey, recipient, amount, futureTime, futureTime + 3600, nonce
        );

        IPaymentVerifier.PaymentParams memory params = IPaymentVerifier.PaymentParams({
            payer: payer, recipient: recipient, token: address(token),
            amount: amount, validAfter: futureTime, validBefore: futureTime + 3600,
            nonce: nonce, v: v, r: r, s: s
        });

        vm.prank(facilitator);
        vm.expectRevert(); // AuthorizationNotYetValid
        verifier.processPayment(params);
    }

    // --- Facilitator Management ---

    function testSetFacilitator() public {
        address newFacilitator = makeAddr("newFacilitator");
        assertFalse(verifier.isFacilitator(newFacilitator));

        verifier.setFacilitator(newFacilitator, true);
        assertTrue(verifier.isFacilitator(newFacilitator));

        verifier.setFacilitator(newFacilitator, false);
        assertFalse(verifier.isFacilitator(newFacilitator));
    }

    function testCannotProcessAsNonFacilitator() public {
        uint256 amount = 100e6;
        bytes32 nonce = keccak256("nonce-auth");

        (uint8 v, bytes32 r, bytes32 s) = _signTransferAuthorization(
            payerPrivateKey, recipient, amount, block.timestamp, block.timestamp + 3600, nonce
        );

        IPaymentVerifier.PaymentParams memory params = IPaymentVerifier.PaymentParams({
            payer: payer, recipient: recipient, token: address(token),
            amount: amount, validAfter: block.timestamp, validBefore: block.timestamp + 3600,
            nonce: nonce, v: v, r: r, s: s
        });

        address unauthorized = makeAddr("unauthorized");
        vm.prank(unauthorized);
        vm.expectRevert(abi.encodeWithSignature("NotFacilitator(address)", unauthorized));
        verifier.processPayment(params);
    }

    // --- Token Management ---

    function testAddSupportedToken() public {
        address newToken = makeAddr("newToken");
        assertFalse(verifier.isTokenSupported(newToken));

        verifier.addSupportedToken(newToken);
        assertTrue(verifier.isTokenSupported(newToken));
    }

    function testRemoveSupportedToken() public {
        assertTrue(verifier.isTokenSupported(address(token)));

        verifier.removeSupportedToken(address(token));
        assertFalse(verifier.isTokenSupported(address(token)));
    }

    // --- Helpers ---

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
