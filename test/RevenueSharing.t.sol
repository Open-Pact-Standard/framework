// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {RevenueSharing} from "contracts/dao-maker/RevenueSharing.sol";
import {IRevenueSharing} from "contracts/interfaces/IRevenueSharing.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract RevenueSharingTest is Test {
    RevenueSharing public sharing;
    MockERC20 public token;
    address public owner;
    address public shareholder1;
    address public shareholder2;
    address public shareholder3;

    function setUp() public {
        owner = address(this);
        shareholder1 = makeAddr("shareholder1");
        shareholder2 = makeAddr("shareholder2");
        shareholder3 = makeAddr("shareholder3");

        sharing = new RevenueSharing();
        token = new MockERC20("Mock", "MCK");

        // Set up shareholders: 50%, 30%, 20%
        address[] memory shareholders = new address[](3);
        shareholders[0] = shareholder1;
        shareholders[1] = shareholder2;
        shareholders[2] = shareholder3;
        uint256[] memory shares = new uint256[](3);
        shares[0] = 5000;
        shares[1] = 3000;
        shares[2] = 2000;
        sharing.setShareholders(shareholders, shares);
    }

    function testSetShareholders() public view {
        assertEq(sharing.getShare(shareholder1), 5000);
        assertEq(sharing.getShare(shareholder2), 3000);
        assertEq(sharing.getShare(shareholder3), 2000);
        assertEq(sharing.getShareholderCount(), 3);
    }

    function testDepositNative() public {
        vm.deal(address(this), 10 ether);
        sharing.depositNative{value: 5 ether}();
        assertEq(address(sharing).balance, 5 ether);
    }

    function testDepositToken() public {
        token.mint(address(this), 1000);
        token.approve(address(sharing), 1000);
        sharing.depositToken(address(token), 1000);
        assertEq(token.balanceOf(address(sharing)), 1000);
    }

    function testClaimNative() public {
        vm.deal(address(this), 10 ether);
        sharing.depositNative{value: 10 ether}();

        // shareholder1 has 50% share
        uint256 pending = sharing.getPendingAmount(shareholder1, address(0));
        assertEq(pending, 5 ether);

        vm.prank(shareholder1);
        sharing.claim(address(0));
        assertEq(payable(shareholder1).balance, 5 ether);
    }

    function testClaimToken() public {
        token.mint(address(this), 1000);
        token.approve(address(sharing), 1000);
        sharing.depositToken(address(token), 1000);

        // shareholder2 has 30% share
        uint256 pending = sharing.getPendingAmount(shareholder2, address(token));
        assertEq(pending, 300);

        vm.prank(shareholder2);
        sharing.claim(address(token));
        assertEq(token.balanceOf(shareholder2), 300);
    }

    function testClaimAllShareholders() public {
        vm.deal(address(this), 10 ether);
        sharing.depositNative{value: 10 ether}();

        vm.prank(shareholder1);
        sharing.claim(address(0));

        vm.prank(shareholder2);
        sharing.claim(address(0));

        vm.prank(shareholder3);
        sharing.claim(address(0));

        assertEq(payable(shareholder1).balance, 5 ether);
        assertEq(payable(shareholder2).balance, 3 ether);
        assertEq(payable(shareholder3).balance, 2 ether);
    }

    function testMultipleDeposits() public {
        vm.deal(address(this), 20 ether);
        
        sharing.depositNative{value: 10 ether}();
        sharing.depositNative{value: 10 ether}();

        uint256 pending = sharing.getPendingAmount(shareholder1, address(0));
        assertEq(pending, 10 ether); // 50% of 20 ether
    }

    function testRevertClaimNonShareholder() public {
        address nonShareholder = makeAddr("nonShareholder");
        vm.deal(address(this), 10 ether);
        sharing.depositNative{value: 10 ether}();

        vm.prank(nonShareholder);
        vm.expectRevert(RevenueSharing.NoSharesToClaim.selector);
        sharing.claim(address(0));
    }

    function testRevertClaimTwice() public {
        vm.deal(address(this), 10 ether);
        sharing.depositNative{value: 10 ether}();

        vm.prank(shareholder1);
        sharing.claim(address(0));

        vm.prank(shareholder1);
        vm.expectRevert(RevenueSharing.NoSharesToClaim.selector);
        sharing.claim(address(0));
    }

    function testRevertInvalidRatio() public {
        address[] memory shareholders = new address[](1);
        shareholders[0] = shareholder1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 5000; // Only 50%, not 100%

        vm.expectRevert(
            abi.encodeWithSelector(RevenueSharing.InvalidRatio.selector, uint256(5000))
        );
        sharing.setShareholders(shareholders, shares);
    }

    function testRevertZeroAddress() public {
        address[] memory shareholders = new address[](1);
        shareholders[0] = address(0);
        uint256[] memory shares = new uint256[](1);
        shares[0] = 10000;

        vm.expectRevert(RevenueSharing.ZeroAddress.selector);
        sharing.setShareholders(shareholders, shares);
    }

    function testRevertDepositZeroNative() public {
        vm.expectRevert(RevenueSharing.ZeroShares.selector);
        sharing.depositNative{value: 0}();
    }

    function testRevertDepositZeroToken() public {
        token.mint(address(this), 1000);
        token.approve(address(sharing), 1000);
        vm.expectRevert(RevenueSharing.ZeroShares.selector);
        sharing.depositToken(address(token), 0);
    }

    function testReceiveNative() public {
        vm.deal(address(this), 10 ether);
        (bool success, ) = payable(address(sharing)).call{value: 5 ether}("");
        assertTrue(success);
        assertEq(address(sharing).balance, 5 ether);
    }

    function testUpdateShareholders() public {
        // Update to 60/40 split
        address[] memory shareholders = new address[](2);
        shareholders[0] = shareholder1;
        shareholders[1] = shareholder2;
        uint256[] memory shares = new uint256[](2);
        shares[0] = 6000;
        shares[1] = 4000;
        sharing.setShareholders(shareholders, shares);

        assertEq(sharing.getShare(shareholder1), 6000);
        assertEq(sharing.getShare(shareholder2), 4000);
        assertEq(sharing.getShare(shareholder3), 0); // Removed
    }

    function testSetShareholdersValidateThenMutate() public {
        // Original state: 50/30/20
        assertEq(sharing.getShare(shareholder1), 5000);
        assertEq(sharing.getShare(shareholder2), 3000);
        assertEq(sharing.getShare(shareholder3), 2000);

        // Try to set invalid shareholders (zero address in the list)
        address[] memory badShareholders = new address[](3);
        badShareholders[0] = shareholder1;
        badShareholders[1] = address(0); // invalid
        badShareholders[2] = shareholder3;
        uint256[] memory badShares = new uint256[](3);
        badShares[0] = 5000;
        badShares[1] = 3000;
        badShares[2] = 2000;

        vm.expectRevert(RevenueSharing.ZeroAddress.selector);
        sharing.setShareholders(badShareholders, badShares);

        // Verify original state is preserved
        assertEq(sharing.getShare(shareholder1), 5000);
        assertEq(sharing.getShare(shareholder2), 3000);
        assertEq(sharing.getShare(shareholder3), 2000);
        assertEq(sharing.getShareholderCount(), 3);
    }

    function testSetShareholdersInvalidRatioPreservesState() public {
        // Deposit some funds first
        vm.deal(address(this), 10 ether);
        sharing.depositNative{value: 10 ether}();

        // shareholder1 has pending claims
        assertEq(sharing.getPendingAmount(shareholder1, address(0)), 5 ether);

        // Try invalid ratio
        address[] memory shareholders = new address[](1);
        shareholders[0] = shareholder1;
        uint256[] memory shares = new uint256[](1);
        shares[0] = 5000;

        vm.expectRevert();
        sharing.setShareholders(shareholders, shares);

        // Verify state unchanged - can still claim
        assertEq(sharing.getShare(shareholder1), 5000);
        assertEq(sharing.getPendingAmount(shareholder1, address(0)), 5 ether);

        vm.prank(shareholder1);
        sharing.claim(address(0));
        assertEq(payable(shareholder1).balance, 5 ether);
    }

    // ============ Individual Shareholder Management Tests ============

    function testAddShareholder() public {
        // Remove one existing shareholder first to free up shares
        sharing.removeShareholder(shareholder3);
        address newSh = makeAddr("newSh");
        sharing.addShareholder(newSh, 2000);
        assertEq(sharing.getShare(newSh), 2000);
    }

    function testAddShareholderEmitsEvent() public {
        sharing.removeShareholder(shareholder3);
        address newSh = makeAddr("newSh");
        vm.expectEmit(true, false, false, false);
        emit IRevenueSharing.ShareholderAdded(newSh, 2000);
        sharing.addShareholder(newSh, 2000);
    }

    function testCannotAddZeroAddress() public {
        vm.expectRevert(RevenueSharing.ZeroAddress.selector);
        sharing.addShareholder(address(0), 2000);
    }

    function testCannotAddExistingShareholder() public {
        vm.expectRevert();
        sharing.addShareholder(shareholder1, 1000);
    }

    function testCannotAddExceedingTotalRatio() public {
        vm.expectRevert();
        sharing.addShareholder(makeAddr("new"), 2000);
    }

    function testRemoveShareholder() public {
        sharing.removeShareholder(shareholder1);
        assertEq(sharing.getShare(shareholder1), 0);
    }

    function testRemoveShareholderEmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit IRevenueSharing.ShareholderRemoved(shareholder1);
        sharing.removeShareholder(shareholder1);
    }

    function testUpdateShare() public {
        // Adjust shareholder3 first to make room
        sharing.updateShare(shareholder3, 1000);
        sharing.updateShare(shareholder2, 4000);
        assertEq(sharing.getShare(shareholder2), 4000);
        assertEq(sharing.getShare(shareholder3), 1000);
    }

    function testUpdateShareEmitsEvent() public {
        sharing.updateShare(shareholder3, 1000);
        vm.expectEmit(true, false, false, false);
        emit IRevenueSharing.ShareUpdated(shareholder2, 3000, 4000);
        sharing.updateShare(shareholder2, 4000);
    }

    function testUpdateShareRevertsWhenExceedingTotal() public {
        // Updating shareholder2 to 4000 with others unchanged gives 11000
        vm.expectRevert();
        sharing.updateShare(shareholder2, 4000);
    }

    function testOnlyOwnerCanAddShareholder() public {
        vm.prank(shareholder1);
        vm.expectRevert("Ownable: caller is not the owner");
        sharing.addShareholder(makeAddr("new"), 1000);
    }

    function testOnlyOwnerCanRemoveShareholder() public {
        vm.prank(shareholder1);
        vm.expectRevert("Ownable: caller is not the owner");
        sharing.removeShareholder(shareholder2);
    }

    function testOnlyOwnerCanUpdateShare() public {
        vm.prank(shareholder1);
        vm.expectRevert("Ownable: caller is not the owner");
        sharing.updateShare(shareholder1, 6000);
    }
}
