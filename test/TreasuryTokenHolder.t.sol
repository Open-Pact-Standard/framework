// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {TreasuryTokenHolder} from "contracts/treasury/TreasuryTokenHolder.sol";
import "test/mocks/MockERC20.sol";

contract TreasuryTokenHolderTest is Test {
    TreasuryTokenHolder public holder;
    MockERC20 public token1;
    MockERC20 public token2;

    address public owner;
    address public user1;
    address public user2;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        token1 = new MockERC20("Token1", "T1", 18);
        token2 = new MockERC20("Token2", "T2", 6);

        address[] memory initialTokens = new address[](1);
        initialTokens[0] = address(token1);
        holder = new TreasuryTokenHolder(initialTokens);
    }

    // ============ Deployment Tests ============

    function testDeployment() public {
        assertTrue(holder.isTokenSupported(address(token1)));
        assertEq(holder.getSupportedTokenCount(), 1);
    }

    function testDeploymentMultipleTokens() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        TreasuryTokenHolder multiHolder = new TreasuryTokenHolder(tokens);

        assertTrue(multiHolder.isTokenSupported(address(token1)));
        assertTrue(multiHolder.isTokenSupported(address(token2)));
        assertEq(multiHolder.getSupportedTokenCount(), 2);
    }

    // ============ Deposit Tests ============

    function testDeposit() public {
        token1.mint(user1, 1000);

        vm.prank(user1);
        token1.approve(address(holder), 1000);

        vm.prank(user1);
        holder.deposit(address(token1), 500);

        assertEq(holder.getTokenBalance(address(token1)), 500);
        assertEq(token1.balanceOf(address(holder)), 500);
    }

    function testDepositEmitsEvent() public {
        token1.mint(user1, 1000);
        vm.prank(user1);
        token1.approve(address(holder), 1000);

        vm.prank(user1);
        vm.expectEmit(true, true, true, false);
        emit TreasuryTokenHolder.Deposited(address(token1), user1, 500);
        holder.deposit(address(token1), 500);
    }

    function testDepositAutoAddsTokenByOwner() public {
        token2.mint(owner, 1000);
        vm.prank(owner);
        token2.approve(address(holder), 1000);

        assertFalse(holder.isTokenSupported(address(token2)));

        vm.prank(owner);
        holder.deposit(address(token2), 500);

        assertTrue(holder.isTokenSupported(address(token2)));
    }

    function testCannotDepositUnsupportedTokenAsNonOwner() public {
        token2.mint(user1, 1000);
        vm.prank(user1);
        token2.approve(address(holder), 1000);

        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSignature("TokenNotSupported(address)", address(token2))
        );
        holder.deposit(address(token2), 500);
    }

    function testCannotDepositZero() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        holder.deposit(address(token1), 0);
    }

    function testCannotDepositZeroAddress() public {
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        holder.deposit(address(0), 100);
    }

    // ============ Withdraw Tests ============

    function testWithdraw() public {
        // Deposit tokens first to set up tracked balance
        token1.mint(user1, 1000);
        vm.prank(user1);
        token1.approve(address(holder), 1000);
        vm.prank(user1);
        holder.deposit(address(token1), 1000);

        vm.prank(owner);
        holder.withdraw(address(token1), user2, 500);

        assertEq(token1.balanceOf(user2), 500);
        assertEq(holder.getTokenBalance(address(token1)), 500);
    }

    function testWithdrawEmitsEvent() public {
        token1.mint(user1, 1000);
        vm.prank(user1);
        token1.approve(address(holder), 1000);
        vm.prank(user1);
        holder.deposit(address(token1), 1000);

        vm.prank(owner);
        vm.expectEmit(true, true, true, false);
        emit TreasuryTokenHolder.Withdrawn(address(token1), user2, 500);
        holder.withdraw(address(token1), user2, 500);
    }

    function testOnlyOwnerCanWithdraw() public {
        token1.mint(address(holder), 1000);

        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        holder.withdraw(address(token1), user1, 500);
    }

    function testCannotWithdrawInsufficientBalance() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSignature(
                "InsufficientBalance(address,uint256,uint256)",
                address(token1),
                1000,
                0
            )
        );
        holder.withdraw(address(token1), user1, 1000);
    }

    function testCannotWithdrawZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        holder.withdraw(address(token1), user1, 0);
    }

    // ============ Approval Tests ============

    function testApproveTokens() public {
        vm.prank(owner);
        holder.approveTokens(address(token1), user2, 1000);

        assertEq(token1.allowance(address(holder), user2), 1000);
    }

    function testApproveEmitsEvent() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, false);
        emit TreasuryTokenHolder.Approved(address(token1), user2, 1000);
        holder.approveTokens(address(token1), user2, 1000);
    }

    function testOnlyOwnerCanApprove() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        holder.approveTokens(address(token1), user2, 1000);
    }

    // ============ View Function Tests ============

    function testGetTokenBalance() public {
        assertEq(holder.getTokenBalance(address(token1)), 0);

        token1.mint(address(holder), 500);
        // Balance tracking is through deposit, not direct transfer
    }

    function testGetSupportedTokens() public {
        address[] memory tokens = holder.getSupportedTokens();
        assertEq(tokens.length, 1);
        assertEq(tokens[0], address(token1));
    }

    function testIsTokenSupported() public {
        assertTrue(holder.isTokenSupported(address(token1)));
        assertFalse(holder.isTokenSupported(address(token2)));
    }

    // ============ Native Token Tests ============

    function testReceiveNative() public {
        payable(address(holder)).call{value: 1 ether}("");
        assertEq(address(holder).balance, 1 ether);
    }

    function testSweepNative() public {
        // Deploy a holder with user1 as owner (who can receive native tokens)
        address[] memory tokens = new address[](0);
        vm.prank(user1);
        TreasuryTokenHolder userHolder = new TreasuryTokenHolder(tokens);

        payable(address(userHolder)).call{value: 1 ether}("");
        assertEq(address(userHolder).balance, 1 ether);

        vm.prank(user1);
        userHolder.sweepNative(0.5 ether);

        assertEq(address(userHolder).balance, 0.5 ether);
    }

    function testCannotSweepZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("ZeroAmount()"));
        holder.sweepNative(0);
    }

    // ============ Recovery Tests ============

    function testRecoverToken() public {
        // Send token2 directly (not through deposit)
        token2.mint(address(holder), 100);

        vm.prank(owner);
        holder.recoverToken(address(token2), user1, 100);

        assertEq(token2.balanceOf(user1), 100);
    }

    function testCannotRecoverSupportedTokenWithBalance() public {
        token1.mint(user1, 1000);
        vm.prank(user1);
        token1.approve(address(holder), 1000);
        vm.prank(user1);
        holder.deposit(address(token1), 500);

        // token1 is supported and has tracked balance - recovery should fail
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSignature("TokenNotSupported(address)", address(token1))
        );
        holder.recoverToken(address(token1), user1, 100);
    }
}
