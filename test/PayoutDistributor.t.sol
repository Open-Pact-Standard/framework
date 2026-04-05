// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {PayoutDistributor} from "contracts/dao-maker/PayoutDistributor.sol";
import {IPayoutDistributor} from "contracts/interfaces/IPayoutDistributor.sol";
import {IDAOToken} from "contracts/interfaces/IDAOToken.sol";
import {IReputationRegistry} from "contracts/interfaces/IReputationRegistry.sol";
import {IAgentRegistry} from "contracts/interfaces/IAgentRegistry.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockDAOToken is ERC20, ERC20Permit, ERC20Votes {
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;

    constructor(address holder) ERC20("Mock DAO", "MDAO") ERC20Permit("Mock DAO") {
        _mint(holder, MAX_SUPPLY);
    }

    function _afterTokenTransfer(address from, address to, uint256 amount)
        internal override(ERC20, ERC20Votes) {
        super._afterTokenTransfer(from, to, amount);
    }

    function _mint(address to, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._mint(to, amount);
    }

    function _burn(address from, uint256 amount) internal override(ERC20, ERC20Votes) {
        super._burn(from, amount);
    }
}

contract MockReputationRegistry is IReputationRegistry {
    mapping(uint256 => int256) public reputations;

    function getReputation(uint256 agentId) external view override returns (int256) {
        return reputations[agentId];
    }

    function setReputation(uint256 agentId, int256 score) external {
        reputations[agentId] = score;
    }

    // Unused interface methods
    function submitReview(uint256, int256, string memory) external {}
    function getTotalScore(uint256) external view returns (int256) { return 0; }
    function getReviewCount(uint256) external view returns (uint256) { return 0; }
    function getLastReviewTime(uint256, address) external view returns (uint256) { return 0; }
    function canReview(uint256, address) external view returns (bool) { return false; }
    function getReview(uint256, uint256) external view returns (int256, string memory, uint256) {
        return (0, "", 0);
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockAgentRegistry is IAgentRegistry {
    uint256 private _nextId = 1;
    mapping(uint256 => address) private _wallets;
    mapping(address => uint256) private _walletToAgent;

    function registerAgent(address wallet) external returns (uint256) {
        if (_walletToAgent[wallet] != 0) return _walletToAgent[wallet];
        uint256 agentId = _nextId++;
        _wallets[agentId] = wallet;
        _walletToAgent[wallet] = agentId;
        return agentId;
    }

    function register(string memory) external override returns (uint256) { return 0; }
    function setAgentWallet(address) external override {}
    function getAgentWallet(uint256 agentId) external view override returns (address) { return _wallets[agentId]; }
    function getAgentId(address wallet) external view override returns (uint256) { return _walletToAgent[wallet]; }
    function getTotalAgents() external view override returns (uint256) { return _nextId - 1; }
    function agentExists(uint256 agentId) external view override returns (bool) { return _wallets[agentId] != address(0); }
}

contract PayoutDistributorTest is Test {
    PayoutDistributor public distributor;
    MockDAOToken public daoToken;
    MockReputationRegistry public repRegistry;
    MockAgentRegistry public agentRegistry;
    MockERC20 public payoutToken;
    address public owner;
    address public participant1;
    address public participant2;

    function setUp() public {
        owner = address(this);
        participant1 = makeAddr("participant1");
        participant2 = makeAddr("participant2");

        daoToken = new MockDAOToken(owner);
        repRegistry = new MockReputationRegistry();
        agentRegistry = new MockAgentRegistry();
        payoutToken = new MockERC20("Payout", "PAY");

        // Register participants as agents
        uint256 ownerAgentId = agentRegistry.registerAgent(owner);
        uint256 p1AgentId = agentRegistry.registerAgent(participant1);
        uint256 p2AgentId = agentRegistry.registerAgent(participant2);

        // Set reputations by agentId
        repRegistry.setReputation(ownerAgentId, 5);
        repRegistry.setReputation(p1AgentId, 5);
        repRegistry.setReputation(p2AgentId, 8);

        // Transfer some tokens to participants for stake
        daoToken.transfer(participant1, 300_000_000 * 10**18);
        daoToken.transfer(participant2, 200_000_000 * 10**18);

        // Delegate to activate voting power
        vm.prank(participant1);
        daoToken.delegate(participant1);
        vm.prank(participant2);
        daoToken.delegate(participant2);
        daoToken.delegate(owner);

        address[] memory participants = new address[](3);
        participants[0] = owner;
        participants[1] = participant1;
        participants[2] = participant2;

        distributor = new PayoutDistributor(
            IDAOToken(address(daoToken)),
            IReputationRegistry(address(repRegistry)),
            IAgentRegistry(address(agentRegistry)),
            participants
        );
    }

    function testDeployment() public view {
        assertEq(address(distributor.daoToken()), address(daoToken));
        assertEq(address(distributor.reputationRegistry()), address(repRegistry));
        assertEq(distributor.currentEpoch(), 0);
    }

    function testFundEpochToken() public {
        payoutToken.mint(address(this), 10_000);
        payoutToken.approve(address(distributor), 10_000);
        distributor.fundEpoch(address(payoutToken), 10_000);
        assertEq(payoutToken.balanceOf(address(distributor)), 10_000);
    }

    function testFundEpochNative() public {
        vm.deal(address(this), 10 ether);
        distributor.fundEpochNative{value: 10 ether}();
        assertEq(address(distributor).balance, 10 ether);
    }

    function testRevertFundZeroToken() public {
        vm.expectRevert(PayoutDistributor.NoFunds.selector);
        distributor.fundEpoch(address(payoutToken), 0);
    }

    function testRevertFundZeroNative() public {
        vm.expectRevert(PayoutDistributor.NoFunds.selector);
        distributor.fundEpochNative{value: 0}();
    }

    function testSetEpochConfig() public {
        distributor.setEpochConfig(8000, 2000);
        // Verify by checking event (no getter for individual ratios)
    }

    function testRevertInvalidEpochConfig() public {
        vm.expectRevert(
            abi.encodeWithSelector(PayoutDistributor.InvalidRatio.selector, uint256(8000), uint256(3000))
        );
        distributor.setEpochConfig(8000, 3000);
    }

    function testRevertOnlyOwnerSetConfig() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        distributor.setEpochConfig(8000, 2000);
    }

    function testClaimRevertFutureEpoch() public {
        payoutToken.mint(address(this), 10_000);
        payoutToken.approve(address(distributor), 10_000);
        distributor.fundEpoch(address(payoutToken), 10_000);

        // Can't claim current epoch (still active)
        vm.expectRevert(PayoutDistributor.InvalidEpoch.selector);
        distributor.claim(0, address(payoutToken));
    }

    function testRevertClaimZeroAddress() public {
        vm.expectRevert(PayoutDistributor.ZeroAddress.selector);
        distributor.fundEpoch(address(0), 100);
    }

    function testRevertDuplicateClaim() public {
        // Fund epoch 0
        payoutToken.mint(address(this), 10_000);
        payoutToken.approve(address(distributor), 10_000);
        distributor.fundEpoch(address(payoutToken), 10_000);

        // Initialize epoch 0
        distributor.initializeEpoch(0);

        // Warp past epoch 0
        vm.warp(block.timestamp + 7 days);

        // Fund epoch 1
        payoutToken.mint(address(this), 10_000);
        payoutToken.approve(address(distributor), 10_000);
        distributor.fundEpoch(address(payoutToken), 10_000);

        // Claim epoch 0
        vm.prank(participant1);
        distributor.claim(0, address(payoutToken));

        // Try to claim again
        vm.prank(participant1);
        vm.expectRevert(PayoutDistributor.AlreadyClaimed.selector);
        distributor.claim(0, address(payoutToken));
    }

    function testClaimNative() public {
        vm.deal(address(this), 10 ether);
        distributor.fundEpochNative{value: 10 ether}();

        // Initialize epoch 0
        distributor.initializeEpoch(0);

        // Warp past epoch 0
        vm.warp(block.timestamp + 7 days);

        // Claim should succeed for epoch 0
        uint256 balanceBefore = participant1.balance;
        vm.prank(participant1);
        distributor.claim(0, address(0));
        assertGt(participant1.balance, balanceBefore);
    }

    function testCurrentEpoch() public view {
        assertEq(distributor.currentEpoch(), 0);
    }

    function testEpochProgression() public {
        vm.warp(block.timestamp + 7 days);
        assertEq(distributor.currentEpoch(), 1);
        
        vm.warp(block.timestamp + 7 days);
        assertEq(distributor.currentEpoch(), 2);
    }

    function testClaimERC20Token() public {
        // Fund epoch 0 with ERC20 token
        payoutToken.mint(address(this), 10_000);
        payoutToken.approve(address(distributor), 10_000);
        distributor.fundEpoch(address(payoutToken), 10_000);

        // Initialize epoch 0
        distributor.initializeEpoch(0);

        // Warp past epoch 0
        vm.warp(block.timestamp + 7 days);

        // Claim should succeed for epoch 0 with ERC20 token
        uint256 balanceBefore = payoutToken.balanceOf(participant1);
        vm.prank(participant1);
        distributor.claim(0, address(payoutToken));
        assertGt(payoutToken.balanceOf(participant1), balanceBefore);
    }

    function testOnlyOwnerCanFundEpoch() public {
        payoutToken.mint(address(this), 10_000);
        payoutToken.approve(address(distributor), 10_000);

        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        distributor.fundEpoch(address(payoutToken), 10_000);
    }

    function testOnlyOwnerCanFundEpochNative() public {
        address nonOwner = makeAddr("nonOwner");
        vm.deal(nonOwner, 10 ether);
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        distributor.fundEpochNative{value: 10 ether}();
    }

    function testOnlyOwnerCanPause() public {
        address nonOwner = makeAddr("nonOwner");
        vm.prank(nonOwner);
        vm.expectRevert("Ownable: caller is not the owner");
        distributor.pause();
    }

    // ============ Participant Management Tests ============

    function testAddParticipant() public {
        address newP = makeAddr("newP");
        distributor.addParticipant(newP);
        assertTrue(distributor.isParticipant(newP));
    }

    function testAddParticipantEmitsEvent() public {
        address newP = makeAddr("newP");
        vm.expectEmit(true, false, false, false);
        emit IPayoutDistributor.ParticipantAdded(newP);
        distributor.addParticipant(newP);
    }

    function testCannotAddZeroAddress() public {
        vm.expectRevert(PayoutDistributor.ZeroAddress.selector);
        distributor.addParticipant(address(0));
    }

    function testAddDuplicateParticipantIsNoop() public {
        // participant1 is already added in setUp
        distributor.addParticipant(participant1);
        assertTrue(distributor.isParticipant(participant1));
    }

    function testRemoveParticipant() public {
        distributor.removeParticipant(participant1);
        assertFalse(distributor.isParticipant(participant1));
    }

    function testRemoveParticipantEmitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit IPayoutDistributor.ParticipantRemoved(participant1);
        distributor.removeParticipant(participant1);
    }

    function testRemoveNonExistentParticipantIsNoop() public {
        address nonP = makeAddr("nonP");
        distributor.removeParticipant(nonP);
    }

    function testOnlyOwnerCanAddParticipant() public {
        address newP = makeAddr("newP");
        vm.prank(newP);
        vm.expectRevert("Ownable: caller is not the owner");
        distributor.addParticipant(newP);
    }

    function testOnlyOwnerCanRemoveParticipant() public {
        vm.prank(participant1);
        vm.expectRevert("Ownable: caller is not the owner");
        distributor.removeParticipant(participant1);
    }

    // ============ Initialize Epoch Tests ============

    function testInitializeEpochEmitsEvent() public {
        payoutToken.mint(address(this), 10_000);
        payoutToken.approve(address(distributor), 10_000);
        distributor.fundEpoch(address(payoutToken), 10_000);

        vm.expectEmit(true, false, false, false);
        emit IPayoutDistributor.EpochInitialized(0, 0);
        distributor.initializeEpoch(0);
    }

    function testInitializeEpochIsIdempotent() public {
        payoutToken.mint(address(this), 10_000);
        payoutToken.approve(address(distributor), 10_000);
        distributor.fundEpoch(address(payoutToken), 10_000);

        distributor.initializeEpoch(0);
        distributor.initializeEpoch(0); // Should not revert
    }
}
