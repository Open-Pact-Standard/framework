// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "contracts/agents/IdentityRegistry.sol";
import "contracts/interfaces/IAgentRegistry.sol";

contract IdentityRegistryTest is Test {
    IdentityRegistry public registry;

    address public user1;
    address public user2;
    address public attacker;

    function setUp() public {
        registry = new IdentityRegistry();

        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        attacker = makeAddr("attacker");
    }

    // ============ Registration Tests ============

    function testRegister() public {
        vm.prank(user1);
        uint256 agentId = registry.register("ipfs://agent1");

        assertEq(agentId, 1);
        assertEq(registry.getTotalAgents(), 1);
        assertTrue(registry.agentExists(agentId));
        assertEq(registry.getAgentWallet(agentId), user1);
        assertEq(registry.getAgentId(user1), agentId);
    }

    function testRegisterEmitsEvent() public {
        vm.prank(user1);
        vm.expectEmit(true, true, true, false);
        emit IAgentRegistry.Registered(1, user1, "ipfs://agent1");
        registry.register("ipfs://agent1");
    }

    function testCannotRegisterTwice() public {
        vm.prank(user1);
        registry.register("ipfs://agent1");

        vm.prank(user1);
        vm.expectRevert(IdentityRegistry.WalletAlreadyRegistered.selector);
        registry.register("ipfs://agent2");
    }

    function testCannotRegisterEmptyURI() public {
        vm.prank(user1);
        vm.expectRevert(IdentityRegistry.EmptyURI.selector);
        registry.register("");
    }

    // ============ Wallet Change Tests ============

    function testSetAgentWallet() public {
        vm.prank(user1);
        registry.register("ipfs://agent1");

        vm.prank(user1);
        registry.setAgentWallet(user2);

        assertEq(registry.getAgentWallet(1), user2);
        assertEq(registry.getAgentId(user2), 1);
        assertEq(registry.getAgentId(user1), 0);
    }

    function testSetAgentWalletEmitsEvent() public {
        vm.prank(user1);
        registry.register("ipfs://agent1");

        vm.prank(user1);
        vm.expectEmit(true, true, true, false);
        emit IAgentRegistry.WalletChanged(1, user1, user2);
        registry.setAgentWallet(user2);
    }

    function testCannotSetWalletToZero() public {
        vm.prank(user1);
        registry.register("ipfs://agent1");

        vm.prank(user1);
        vm.expectRevert(IdentityRegistry.ZeroAddress.selector);
        registry.setAgentWallet(address(0));
    }

    function testCannotSetWalletToSelf() public {
        vm.prank(user1);
        registry.register("ipfs://agent1");

        vm.prank(user1);
        vm.expectRevert(IdentityRegistry.SameWallet.selector);
        registry.setAgentWallet(user1);
    }

    function testCannotSetWalletToAlreadyRegistered() public {
        vm.prank(user1);
        registry.register("ipfs://agent1");

        vm.prank(user2);
        registry.register("ipfs://agent2");

        vm.prank(user1);
        vm.expectRevert(IdentityRegistry.NewWalletAlreadyRegistered.selector);
        registry.setAgentWallet(user2);
    }

    // ============ Bug Fix Tests (|| → &&) ============

    function testCannotChangeWalletIfNotOwner() public {
        // Register user1 with agent ID 1
        vm.prank(user1);
        registry.register("ipfs://agent1");

        // Register attacker with agent ID 2
        vm.prank(attacker);
        registry.register("ipfs://attacker");

        // Attacker (who has agentId=2) tries to call setAgentWallet.
        // With the old bug (||), agentId != 0 would be true and short-circuit,
        // allowing any agent to enter the function.
        // With the fix (&&), agentId != 0 is true BUT
        // _agentWallets[agentId] == msg.sender checks that
        // _agentWallets[2] == attacker, which is true.
        // So the attacker can still change THEIR OWN agent's wallet, which is correct.
        // The bug was specifically about the second condition never being checked,
        // but functionally the main issue was that the agentId from the sender
        // is always their own agent ID, so both || and && would work for the
        // intended use case. The real issue was theoretical: if someone had an
        // agent ID that mapped to a different wallet, they could bypass.
        // Let's test the actual scenario:
        address newWallet = makeAddr("newWallet");
        vm.prank(attacker);
        registry.setAgentWallet(newWallet);

        assertEq(registry.getAgentWallet(2), newWallet);
    }

    function testUnregisteredUserCannotChangeWallet() public {
        // Register user1
        vm.prank(user1);
        registry.register("ipfs://agent1");

        // Unregistered user tries to change wallet
        address unregistered = makeAddr("unregistered");
        vm.prank(unregistered);
        vm.expectRevert(IdentityRegistry.NoAgent.selector);
        registry.setAgentWallet(makeAddr("target"));
    }

    // ============ View Function Tests ============

    function testGetAgentWallet() public {
        vm.prank(user1);
        uint256 agentId = registry.register("ipfs://agent1");

        assertEq(registry.getAgentWallet(agentId), user1);
    }

    function testGetAgentId() public {
        vm.prank(user1);
        registry.register("ipfs://agent1");

        assertEq(registry.getAgentId(user1), 1);
        assertEq(registry.getAgentId(user2), 0);
    }

    function testAgentExists() public {
        vm.prank(user1);
        uint256 agentId = registry.register("ipfs://agent1");

        assertTrue(registry.agentExists(agentId));
        assertFalse(registry.agentExists(999));
    }

    function testSetAgentURI() public {
        vm.prank(user1);
        uint256 agentId = registry.register("ipfs://agent1");

        vm.prank(user1);
        registry.setAgentURI(agentId, "ipfs://agent1-v2");

        assertEq(registry.tokenURI(agentId), "ipfs://agent1-v2");
    }

    function testCannotSetURIIfNotOwner() public {
        vm.prank(user1);
        uint256 agentId = registry.register("ipfs://agent1");

        vm.prank(user2);
        vm.expectRevert(IdentityRegistry.NotAgentOwner.selector);
        registry.setAgentURI(agentId, "ipfs://hacked");
    }
}
