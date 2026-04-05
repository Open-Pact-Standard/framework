// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {DAOTokenV2} from "contracts/dao-maker/DAOTokenV2.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DAOTokenV2Test is Test {
    DAOTokenV2 public token;
    address public holder;

    function setUp() public {
        holder = makeAddr("holder");
        token = new DAOTokenV2("Test Token", "TST", holder, 1_000_000 * 10**18);
    }

    function testDeployment() public view {
        assertEq(token.name(), "Test Token");
        assertEq(token.symbol(), "TST");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1_000_000 * 10**18);
        assertEq(token.balanceOf(holder), 1_000_000 * 10**18);
        assertEq(token.MAX_SUPPLY(), 1_000_000_000 * 10**18);
    }

    function testZeroInitialSupply() public {
        DAOTokenV2 t = new DAOTokenV2("Zero", "ZRO", holder, 0);
        assertEq(t.totalSupply(), 0);
        assertEq(t.balanceOf(holder), 0);
    }

    function testRevertZeroHolder() public {
        vm.expectRevert(DAOTokenV2.InvalidParameters.selector);
        new DAOTokenV2("Bad", "BAD", address(0), 100);
    }

    function testRevertExceedMaxSupply() public {
        uint256 overMax = 1_000_000_001 * 10**18;
        vm.expectRevert(
            abi.encodeWithSelector(DAOTokenV2.SupplyExceeded.selector, overMax, 1_000_000_000 * 10**18)
        );
        new DAOTokenV2("Bad", "BAD", holder, overMax);
    }

    function testMaxSupplyMint() public {
        DAOTokenV2 t = new DAOTokenV2("Max", "MAX", holder, 1_000_000_000 * 10**18);
        assertEq(t.totalSupply(), 1_000_000_000 * 10**18);
        assertEq(t.balanceOf(holder), 1_000_000_000 * 10**18);
    }

    function testTransfer() public {
        address receiver = makeAddr("receiver");
        vm.prank(holder);
        token.transfer(receiver, 100 * 10**18);
        assertEq(token.balanceOf(receiver), 100 * 10**18);
    }

    function testBurn() public {
        vm.prank(holder);
        token.burn(500 * 10**18);
        assertEq(token.totalSupply(), 999_500 * 10**18);
    }

    function testDelegate() public {
        address delegatee = makeAddr("delegatee");
        vm.prank(holder);
        token.delegate(delegatee);
        assertEq(token.delegates(holder), delegatee);
        assertGt(token.getVotes(delegatee), 0);
    }

    function testGetPastVotes() public {
        // Delegate to activate voting power checkpoints
        vm.prank(holder);
        token.delegate(holder);
        
        // Record block after delegation (before any transfer)
        uint256 blockAfterDelegate = block.number;
        
        // Roll to next block to separate delegation from transfer
        vm.roll(block.number + 1);
        
        // Transfer some tokens
        vm.prank(holder);
        token.transfer(makeAddr("someone"), 100);
        
        // Warp to next block
        vm.roll(block.number + 1);
        
        // Query past votes at block right after delegation (before transfer)
        uint256 pastVotes = token.getPastVotes(holder, blockAfterDelegate);
        assertEq(pastVotes, 1_000_000 * 10**18);
    }
}
