// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/payments/PaymentVerifier.sol";
import "../contracts/payments/PaymentLedger.sol";

// Mock EIP-3009 token for testing
contract MockEIP3009Token {
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public nonces;
    mapping(bytes32 => bool) public usedAuthorizations;

    string public constant name = "Mock USDt";
    string public constant symbol = "USDT";
    uint8 public constant decimals = 6;
    uint256 public totalSupply;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 value) external returns (bool) {
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256,
        uint256,
        bytes32 nonce,
        uint8,
        bytes32,
        bytes32
    ) external {
        require(!usedAuthorizations[nonce], "Authorization used");
        require(balanceOf[from] >= value, "Insufficient balance");

        usedAuthorizations[nonce] = true;
        nonces[from]++;

        balanceOf[from] -= value;
        balanceOf[to] += value;

        emit AuthorizationUsed(from, nonce);
        emit Transfer(from, to, value);
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
    ) external {
        revert("Not implemented");
    }

    function cancelAuthorization(
        address authorizer,
        bytes32 nonce,
        uint8,
        bytes32,
        bytes32
    ) external {
        require(!usedAuthorizations[nonce], "Authorization used");
        require(msg.sender == authorizer, "Not authorizer");
        usedAuthorizations[nonce] = true;
        emit AuthorizationUsed(authorizer, nonce);
    }

    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool) {
        return usedAuthorizations[nonce];
    }
}

/**
 * @title PaymentVerifierRateLimitTest
 * @dev Tests for PaymentVerifier rate limiting functionality
 */
contract PaymentVerifierRateLimitTest is Test {
    PaymentVerifier verifier;
    PaymentLedger ledger;
    MockEIP3009Token token;

    address owner = address(0x1);
    address facilitator = address(0x2);
    address payer1 = address(0x3);
    address payer2 = address(0x4);
    address payer3 = address(0x5);
    address recipient1 = address(0x10);
    address recipient2 = address(0x11);

    uint256 constant MAX_PAYMENT = 10_000_000 * 1e6;
    uint256 constant MAX_DAILY_GLOBAL = 1_000_000 * 1e6;
    uint256 constant MAX_DAILY_PAYER = 100_000 * 1e6;
    uint256 constant MAX_DAILY_RECIPIENT = 50_000 * 1e6;
    uint256 constant CIRCUIT_BREAKER = 900_000 * 1e6;

    function setUp() public {
        vm.startPrank(owner);

        ledger = new PaymentLedger();
        token = new MockEIP3009Token();

        address[] memory tokens = new address[](1);
        tokens[0] = address(token);

        verifier = new PaymentVerifier(
            address(ledger),
            tokens,
            MAX_PAYMENT,
            MAX_DAILY_GLOBAL,
            MAX_DAILY_PAYER,
            MAX_DAILY_RECIPIENT,
            CIRCUIT_BREAKER
        );

        ledger.addVerifier(address(verifier));
        verifier.setFacilitator(facilitator, true);

        token.mint(payer1, 1_000_000 * 1e6);
        token.mint(payer2, 1_000_000 * 1e6);
        token.mint(payer3, 1_000_000 * 1e6);

        vm.stopPrank();
    }

    function testRateLimit_PayerLimit() public {
        uint256 paymentAmount = 20_000 * 1e6;

        vm.prank(facilitator);
        verifier.processPayment(
            IPaymentVerifier.PaymentParams({
                token: address(token),
                payer: payer1,
                recipient: recipient1,
                amount: paymentAmount,
                validAfter: 0,
                validBefore: type(uint256).max,
                nonce: keccak256("nonce1"),
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            })
        );

        vm.prank(facilitator);
        verifier.processPayment(
            IPaymentVerifier.PaymentParams({
                token: address(token),
                payer: payer1,
                recipient: recipient2,
                amount: paymentAmount,
                validAfter: 0,
                validBefore: type(uint256).max,
                nonce: keccak256("nonce2"),
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            })
        );

        vm.prank(facilitator);
        address recipient3 = vm.addr(300);
        verifier.processPayment(
            IPaymentVerifier.PaymentParams({
                token: address(token),
                payer: payer1,
                recipient: recipient3,
                amount: paymentAmount,
                validAfter: 0,
                validBefore: type(uint256).max,
                nonce: keccak256("nonce3"),
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            })
        );

        vm.prank(facilitator);
        address recipient4 = vm.addr(400);
        verifier.processPayment(
            IPaymentVerifier.PaymentParams({
                token: address(token),
                payer: payer1,
                recipient: recipient4,
                amount: paymentAmount,
                validAfter: 0,
                validBefore: type(uint256).max,
                nonce: keccak256("nonce4"),
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            })
        );

        paymentAmount = 25_000 * 1e6;

        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentVerifier.DailyLimitExceeded.selector,
                105000000000,
                100000000000,
                "payer"
            )
        );

        vm.prank(facilitator);
        verifier.processPayment(
            IPaymentVerifier.PaymentParams({
                token: address(token),
                payer: payer1,
                recipient: recipient1,
                amount: paymentAmount,
                validAfter: 0,
                validBefore: type(uint256).max,
                nonce: keccak256("nonce5"),
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            })
        );
    }

    function testRateLimit_RecipientLimit() public {
        uint256 paymentAmount = 15_000 * 1e6; // $15k

        vm.prank(facilitator);
        verifier.processPayment(
            IPaymentVerifier.PaymentParams({
                token: address(token),
                payer: payer1,
                recipient: recipient1,
                amount: paymentAmount,
                validAfter: 0,
                validBefore: type(uint256).max,
                nonce: keccak256("nonce1"),
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            })
        );

        vm.prank(facilitator);
        verifier.processPayment(
            IPaymentVerifier.PaymentParams({
                token: address(token),
                payer: payer2,
                recipient: recipient1,
                amount: paymentAmount,
                validAfter: 0,
                validBefore: type(uint256).max,
                nonce: keccak256("nonce2"),
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            })
        );

        vm.prank(facilitator);
        verifier.processPayment(
            IPaymentVerifier.PaymentParams({
                token: address(token),
                payer: payer3,
                recipient: recipient1,
                amount: paymentAmount,
                validAfter: 0,
                validBefore: type(uint256).max,
                nonce: keccak256("nonce3"),
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            })
        );

        // 4th payment would exceed recipient limit ($45k + $15k = $60k > $50k)
        paymentAmount = 15_000 * 1e6;

        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentVerifier.DailyLimitExceeded.selector,
                60000000000,
                50000000000,
                "recipient"
            )
        );

        vm.prank(facilitator);
        verifier.processPayment(
            IPaymentVerifier.PaymentParams({
                token: address(token),
                payer: payer1,
                recipient: recipient1,
                amount: paymentAmount,
                validAfter: 0,
                validBefore: type(uint256).max,
                nonce: keccak256("nonce4"),
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            })
        );
    }

    function testRateLimit_GlobalLimit() public {
        uint256 paymentAmount = MAX_DAILY_GLOBAL + 1;

        vm.expectRevert(
            abi.encodeWithSelector(
                PaymentVerifier.DailyLimitExceeded.selector,
                paymentAmount,
                MAX_DAILY_GLOBAL,
                "global"
            )
        );

        vm.prank(facilitator);
        verifier.processPayment(
            IPaymentVerifier.PaymentParams({
                token: address(token),
                payer: payer1,
                recipient: recipient1,
                amount: paymentAmount,
                validAfter: 0,
                validBefore: type(uint256).max,
                nonce: keccak256("nonce1"),
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            })
        );
    }

    function testCircuitBreaker() public {
        // Use 18 different payers, each sending $50k to different recipients
        // This will trigger the circuit breaker at $900k
        for (uint256 i = 0; i < 18; i++) {
            address payer = vm.addr(100 + i);
            address recipient = vm.addr(200 + i);
            vm.prank(owner);
            token.mint(payer, 100_000 * 1e6);
        }

        for (uint256 i = 0; i < 18; i++) {
            address payer = vm.addr(100 + i);
            address recipient = vm.addr(200 + i);
            vm.prank(facilitator);
            verifier.processPayment(
                IPaymentVerifier.PaymentParams({
                    token: address(token),
                    payer: payer,
                    recipient: recipient,
                    amount: 50_000 * 1e6,  // Within $50k recipient limit
                    validAfter: 0,
                    validBefore: type(uint256).max,
                    nonce: keccak256(abi.encodePacked("nonce", i)),
                    v: 0,
                    r: bytes32(0),
                    s: bytes32(0)
                })
            );
        }

        assertTrue(verifier.circuitBreakerTriggered());

        vm.expectRevert(
            abi.encodeWithSelector(PaymentVerifier.CircuitBreakerActive.selector)
        );

        vm.prank(facilitator);
        verifier.processPayment(
            IPaymentVerifier.PaymentParams({
                token: address(token),
                payer: payer1,
                recipient: recipient1,
                amount: 1000,
                validAfter: 0,
                validBefore: type(uint256).max,
                nonce: keccak256("nonce_final"),
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            })
        );
    }

    function testCircuitBreakerReset() public {
        // Use 18 different payers, each sending $50k to different recipients
        for (uint256 i = 0; i < 18; i++) {
            address payer = vm.addr(100 + i);
            address recipient = vm.addr(200 + i);
            vm.prank(owner);
            token.mint(payer, 100_000 * 1e6);
        }

        for (uint256 i = 0; i < 18; i++) {
            address payer = vm.addr(100 + i);
            address recipient = vm.addr(200 + i);
            vm.prank(facilitator);
            verifier.processPayment(
                IPaymentVerifier.PaymentParams({
                    token: address(token),
                    payer: payer,
                    recipient: recipient,
                    amount: 50_000 * 1e6,
                    validAfter: 0,
                    validBefore: type(uint256).max,
                    nonce: keccak256(abi.encodePacked("nonce", i)),
                    v: 0,
                    r: bytes32(0),
                    s: bytes32(0)
                })
            );
        }

        assertTrue(verifier.circuitBreakerTriggered());

        vm.prank(owner);
        verifier.resetCircuitBreaker();

        assertFalse(verifier.circuitBreakerTriggered());

        vm.prank(facilitator);
        verifier.processPayment(
            IPaymentVerifier.PaymentParams({
                token: address(token),
                payer: payer1,
                recipient: recipient1,
                amount: 1000,
                validAfter: 0,
                validBefore: type(uint256).max,
                nonce: keccak256("nonce_after_reset"),
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            })
        );
    }

    function testDayReset() public {
        uint256 paymentAmount = 50_000 * 1e6;

        vm.prank(facilitator);
        verifier.processPayment(
            IPaymentVerifier.PaymentParams({
                token: address(token),
                payer: payer1,
                recipient: recipient1,
                amount: paymentAmount,
                validAfter: 0,
                validBefore: type(uint256).max,
                nonce: keccak256("nonce1"),
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            })
        );

        vm.warp(block.timestamp + 1 days + 1);

        vm.prank(facilitator);
        verifier.processPayment(
            IPaymentVerifier.PaymentParams({
                token: address(token),
                payer: payer1,
                recipient: recipient1,
                amount: paymentAmount,
                validAfter: 0,
                validBefore: type(uint256).max,
                nonce: keccak256("nonce2"),
                v: 0,
                r: bytes32(0),
                s: bytes32(0)
            })
        );
    }

    function testGetRateLimitStatus() public view {
        (
            uint256 globalRemaining,
            uint256 payerRemaining,
            uint256 recipientRemaining,
            ,
            uint256 secondsUntilReset
        ) = verifier.getRateLimitStatus(payer1, recipient1);

        assertEq(globalRemaining, MAX_DAILY_GLOBAL);
        assertEq(payerRemaining, MAX_DAILY_PAYER);
        assertEq(recipientRemaining, MAX_DAILY_RECIPIENT);
        assertGt(secondsUntilReset, 0);
        assertLt(secondsUntilReset, 1 days);
    }

    function testSetRateLimits() public {
        vm.prank(owner);
        verifier.setRateLimits(
            2_000_000 * 1e6,
            200_000 * 1e6,
            100_000 * 1e6,
            0
        );

        assertEq(verifier.maxDailyVolumeGlobal(), 2_000_000 * 1e6);
        assertEq(verifier.maxDailyVolumePerPayer(), 200_000 * 1e6);
        assertEq(verifier.maxDailyVolumePerRecipient(), 100_000 * 1e6);
        assertEq(verifier.circuitBreakerThreshold(), 0);
    }

    function testSetRateLimitsOnlyOwner() public {
        vm.expectRevert();
        verifier.setRateLimits(1, 1, 1, 0);
    }

    function testSetRateLimitsRejectsZero() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(PaymentVerifier.InvalidLimits.selector)
        );
        verifier.setRateLimits(0, 1, 1, 0);
    }
}
