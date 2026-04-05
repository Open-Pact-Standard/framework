// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../contracts/ai/AIAgentFactory.sol";
import "../contracts/ai/AIAgentRegistry.sol";
import "../contracts/ai/AutonomousExecutor.sol";
import "../contracts/ai/AgentCommunication.sol";
import "../contracts/ai/IAgentCommunication.sol";
import "../contracts/interfaces/IAIAgentFactory.sol";

/**
 * @title AIAgentFactoryTest
 * @dev Test suite for AIAgentFactory contract
 */
contract AIAgentFactoryTest is Test {
    AIAgentFactory factory;

    address admin = address(0x1);
    address pauser = address(0x2);
    address allowlistManager = address(0x3);
    address user = address(0x4);

    function setUp() public {
        factory = new AIAgentFactory();
    }

    // ============ Initial State Tests ============

    function testInitialState() public {
        assertEq(factory.owner(), address(this));
        assertEq(factory.getStackCount(), 0);
    }

    // ============ Create Stack Tests ============

    function testCreateAgentStack() public {
        IAIAgentFactory.CreateAgentParams memory params = IAIAgentFactory.CreateAgentParams({
            name: "TestDAO",
            admin: admin,
            pauser: pauser,
            allowlistManager: allowlistManager,
            dailyLimit: 10 ether
        });

        IAIAgentFactory.AIAgentDeployment memory deployment = factory.createAgentStack(params);

        // Verify deployment addresses are non-zero
        assertTrue(deployment.aiRegistry != address(0));
        assertTrue(deployment.executor != address(0));
        assertTrue(deployment.communication != address(0));

        // Verify deployment info
        assertEq(deployment.deployer, address(this));
        assertEq(deployment.deployedAt, block.timestamp);

        // Verify stack was registered
        assertTrue(factory.stackExists("TestDAO"));
        assertEq(factory.getStackCount(), 1);
    }

    function testCreateAgentStackEmitsEvent() public {
        IAIAgentFactory.CreateAgentParams memory params = IAIAgentFactory.CreateAgentParams({
            name: "TestDAO",
            admin: admin,
            pauser: pauser,
            allowlistManager: allowlistManager,
            dailyLimit: 10 ether
        });

        // Check event is emitted (only checking name, not addresses)
        vm.expectEmit(true, false, false, false);
        emit IAIAgentFactory.AIAgentStackCreated(
            "TestDAO",
            address(0),
            address(0),
            address(0),
            address(0)
        );

        factory.createAgentStack(params);
    }

    function testCreateMultipleStacks() public {
        IAIAgentFactory.CreateAgentParams memory params1 = IAIAgentFactory.CreateAgentParams({
            name: "DAO1",
            admin: admin,
            pauser: pauser,
            allowlistManager: allowlistManager,
            dailyLimit: 5 ether
        });

        IAIAgentFactory.CreateAgentParams memory params2 = IAIAgentFactory.CreateAgentParams({
            name: "DAO2",
            admin: admin,
            pauser: pauser,
            allowlistManager: allowlistManager,
            dailyLimit: 15 ether
        });

        factory.createAgentStack(params1);
        factory.createAgentStack(params2);

        assertEq(factory.getStackCount(), 2);

        string[] memory names = factory.getStackNames();
        assertEq(names.length, 2);
        assertEq(names[0], "DAO1");
        assertEq(names[1], "DAO2");
    }

    function testCannotCreateWithEmptyName() public {
        IAIAgentFactory.CreateAgentParams memory params = IAIAgentFactory.CreateAgentParams({
            name: "",
            admin: admin,
            pauser: pauser,
            allowlistManager: allowlistManager,
            dailyLimit: 10 ether
        });

        vm.expectRevert(IAIAgentFactory.EmptyName.selector);
        factory.createAgentStack(params);
    }

    function testCannotCreateWithZeroAdmin() public {
        IAIAgentFactory.CreateAgentParams memory params = IAIAgentFactory.CreateAgentParams({
            name: "TestDAO",
            admin: address(0),
            pauser: pauser,
            allowlistManager: allowlistManager,
            dailyLimit: 10 ether
        });

        vm.expectRevert(IAIAgentFactory.ZeroAddress.selector);
        factory.createAgentStack(params);
    }

    function testCannotCreateDuplicateStack() public {
        IAIAgentFactory.CreateAgentParams memory params = IAIAgentFactory.CreateAgentParams({
            name: "TestDAO",
            admin: admin,
            pauser: pauser,
            allowlistManager: allowlistManager,
            dailyLimit: 10 ether
        });

        factory.createAgentStack(params);

        // Expect revert - using generic expectRevert
        vm.expectRevert();
        factory.createAgentStack(params);
    }

    // ============ Registry Setup Tests ============

    function testRegistryHasCorrectRoles() public {
        IAIAgentFactory.CreateAgentParams memory params = IAIAgentFactory.CreateAgentParams({
            name: "TestDAO",
            admin: admin,
            pauser: pauser,
            allowlistManager: allowlistManager,
            dailyLimit: 10 ether
        });

        IAIAgentFactory.AIAgentDeployment memory deployment = factory.createAgentStack(params);
        AIAgentRegistry registry = AIAgentRegistry(deployment.aiRegistry);

        // Check admin has all roles
        assertTrue(registry.hasRole(registry.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(registry.hasRole(registry.SPENDER_ROLE(), admin));
        assertTrue(registry.hasRole(registry.PAUSER_ROLE(), admin));
    }

    // ============ Executor Setup Tests ============

    function testExecutorLinkedToRegistry() public {
        IAIAgentFactory.CreateAgentParams memory params = IAIAgentFactory.CreateAgentParams({
            name: "TestDAO",
            admin: admin,
            pauser: pauser,
            allowlistManager: allowlistManager,
            dailyLimit: 10 ether
        });

        IAIAgentFactory.AIAgentDeployment memory deployment = factory.createAgentStack(params);
        AutonomousExecutor executor = AutonomousExecutor(payable(deployment.executor));

        assertEq(address(executor.aiRegistry()), deployment.aiRegistry);
    }

    function testExecutorHasCorrectRoles() public {
        IAIAgentFactory.CreateAgentParams memory params = IAIAgentFactory.CreateAgentParams({
            name: "TestDAO",
            admin: admin,
            pauser: pauser,
            allowlistManager: allowlistManager,
            dailyLimit: 10 ether
        });

        IAIAgentFactory.AIAgentDeployment memory deployment = factory.createAgentStack(params);
        AutonomousExecutor executor = AutonomousExecutor(payable(deployment.executor));

        // Check admin is the owner (not DEFAULT_ADMIN_ROLE)
        assertEq(executor.owner(), admin);

        // Check pauser has PAUSER_ROLE
        assertTrue(executor.hasRole(executor.PAUSER_ROLE(), pauser));

        // Check allowlistManager has ALLOWLIST_ROLE
        assertTrue(executor.hasRole(executor.ALLOWLIST_ROLE(), allowlistManager));
    }

    function testExecutorHasSpenderRoleOnRegistry() public {
        IAIAgentFactory.CreateAgentParams memory params = IAIAgentFactory.CreateAgentParams({
            name: "TestDAO",
            admin: admin,
            pauser: pauser,
            allowlistManager: allowlistManager,
            dailyLimit: 10 ether
        });

        IAIAgentFactory.AIAgentDeployment memory deployment = factory.createAgentStack(params);
        AIAgentRegistry registry = AIAgentRegistry(deployment.aiRegistry);
        AutonomousExecutor executor = AutonomousExecutor(payable(deployment.executor));

        // Executor should have SPENDER_ROLE on registry
        assertTrue(registry.hasRole(registry.SPENDER_ROLE(), address(executor)));
    }

    function testExecutorWithZeroPauser() public {
        IAIAgentFactory.CreateAgentParams memory params = IAIAgentFactory.CreateAgentParams({
            name: "TestDAO",
            admin: admin,
            pauser: address(0),
            allowlistManager: allowlistManager,
            dailyLimit: 10 ether
        });

        IAIAgentFactory.AIAgentDeployment memory deployment = factory.createAgentStack(params);
        AutonomousExecutor executor = AutonomousExecutor(payable(deployment.executor));

        // Pauser role was NOT granted to pauser (zero address)
        assertFalse(executor.hasRole(executor.PAUSER_ROLE(), pauser));
        // But admin is the owner
        assertEq(executor.owner(), admin);
    }

    // ============ Communication Setup Tests ============

    function testCommunicationLinkedToRegistry() public {
        IAIAgentFactory.CreateAgentParams memory params = IAIAgentFactory.CreateAgentParams({
            name: "TestDAO",
            admin: admin,
            pauser: pauser,
            allowlistManager: allowlistManager,
            dailyLimit: 10 ether
        });

        IAIAgentFactory.AIAgentDeployment memory deployment = factory.createAgentStack(params);
        AgentCommunication comm = AgentCommunication(deployment.communication);

        assertEq(address(comm.aiRegistry()), deployment.aiRegistry);
    }

    function testCommunicationHasCorrectRoles() public {
        IAIAgentFactory.CreateAgentParams memory params = IAIAgentFactory.CreateAgentParams({
            name: "TestDAO",
            admin: admin,
            pauser: pauser,
            allowlistManager: allowlistManager,
            dailyLimit: 10 ether
        });

        IAIAgentFactory.AIAgentDeployment memory deployment = factory.createAgentStack(params);
        AgentCommunication comm = AgentCommunication(deployment.communication);

        // Check admin has all roles
        assertTrue(comm.hasRole(comm.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(comm.hasRole(comm.PROCESSOR_ROLE(), admin));
    }

    // ============ Register Stack Tests ============

    function testRegisterAgentStack() public {
        vm.prank(admin);
        IAIAgentFactory.CreateAgentParams memory params = IAIAgentFactory.CreateAgentParams({
            name: "TestDAO",
            admin: admin,
            pauser: pauser,
            allowlistManager: allowlistManager,
            dailyLimit: 10 ether
        });

        IAIAgentFactory.AIAgentDeployment memory deployment = factory.createAgentStack(params);

        // Create a new factory and register the existing stack
        AIAgentFactory newFactory = new AIAgentFactory();
        assertEq(newFactory.owner(), address(this));

        // Transfer ownership to admin for this test
        newFactory.transferOwnership(admin);

        vm.prank(admin);
        newFactory.registerAgentStack(
            "ExistingDAO",
            deployment.aiRegistry,
            deployment.executor,
            deployment.communication
        );

        assertTrue(newFactory.stackExists("ExistingDAO"));
        assertEq(newFactory.getStackCount(), 1);

        // Clean up - transfer ownership back for cleanup
        vm.prank(admin);
        newFactory.transferOwnership(address(this));
    }

    function testCannotRegisterWithEmptyName() public {
        AIAgentFactory newFactory = new AIAgentFactory();
        newFactory.transferOwnership(admin);

        vm.prank(admin);
        vm.expectRevert();
        newFactory.registerAgentStack("", address(0x1), address(0x2), address(0x3));
    }

    function testCannotRegisterWithZeroAddress() public {
        AIAgentFactory newFactory = new AIAgentFactory();
        newFactory.transferOwnership(admin);

        vm.prank(admin);
        vm.expectRevert();
        newFactory.registerAgentStack("Test", address(0), address(0x1), address(0x2));
    }

    function testCannotRegisterAsNonOwner() public {
        vm.prank(user);
        vm.expectRevert(); // Ownable error
        factory.registerAgentStack("Test", address(0x1), address(0x2), address(0x3));
    }

    function testCannotRegisterDuplicate() public {
        AIAgentFactory localFactory = new AIAgentFactory();
        localFactory.transferOwnership(admin);

        IAIAgentFactory.CreateAgentParams memory params = IAIAgentFactory.CreateAgentParams({
            name: "TestDAO",
            admin: admin,
            pauser: pauser,
            allowlistManager: allowlistManager,
            dailyLimit: 10 ether
        });

        vm.prank(admin);
        localFactory.createAgentStack(params);

        vm.prank(admin);
        vm.expectRevert();
        localFactory.registerAgentStack(
            "TestDAO",
            address(0x1),
            address(0x2),
            address(0x3)
        );
    }

    // ============ Get Stack Tests ============

    function testGetStack() public {
        IAIAgentFactory.CreateAgentParams memory params = IAIAgentFactory.CreateAgentParams({
            name: "TestDAO",
            admin: admin,
            pauser: pauser,
            allowlistManager: allowlistManager,
            dailyLimit: 10 ether
        });

        factory.createAgentStack(params);

        IAIAgentFactory.AIAgentDeployment memory deployment = factory.getStack("TestDAO");

        assertTrue(deployment.aiRegistry != address(0));
        assertTrue(deployment.executor != address(0));
        assertTrue(deployment.communication != address(0));
        assertEq(deployment.deployer, address(this));
    }

    function testGetNonexistentStack() public {
        vm.expectRevert();
        factory.getStack("Nonexistent");
    }

    // ============ Integration Tests ============

    function testFullWorkflow() public {
        // Create stack (not as admin - factory creates it)
        IAIAgentFactory.CreateAgentParams memory params = IAIAgentFactory.CreateAgentParams({
            name: "FullTest",
            admin: admin,
            pauser: pauser,
            allowlistManager: allowlistManager,
            dailyLimit: 10 ether
        });

        IAIAgentFactory.AIAgentDeployment memory deployment = factory.createAgentStack(params);

        // Now interact with the deployed contracts
        AIAgentRegistry registry = AIAgentRegistry(deployment.aiRegistry);
        AutonomousExecutor executor = AutonomousExecutor(payable(deployment.executor));
        AgentCommunication comm = AgentCommunication(deployment.communication);

        // Register first AI agent with admin as overseer
        vm.prank(admin);
        uint256 agentId1 = registry.registerAIAgent(
            "ipfs://test1",
            IAIAgentRegistry.AgentType.LLM,
            "gpt-4",
            100 ether,
            admin
        );

        // Register second AI agent with pauser as overseer (different address)
        vm.prank(pauser);
        uint256 agentId2 = registry.registerAIAgent(
            "ipfs://test2",
            IAIAgentRegistry.AgentType.Autonomous,
            "claude-3",
            50 ether,
            pauser
        );

        // Verify agents were registered
        assertTrue(registry.isAIAgent(agentId1));
        assertTrue(registry.isAIAgent(agentId2));

        // Set daily limit for agentId1 (admin is owner of executor)
        vm.prank(admin);
        executor.setDailyLimit(agentId1, 10 ether);

        (, uint256 limit, ) = executor.getDailySpending(agentId1);
        assertEq(limit, 10 ether);

        // Send a message from agentId1 to agentId2 (called by admin, who is overseer of agentId1)
        vm.prank(admin);
        uint256 messageId = comm.sendMessage(agentId2, "test", "{}", block.timestamp + 1 days);

        // Verify message exists
        IAgentCommunication.Message memory message = comm.getMessage(messageId);
        assertEq(message.fromAgentId, agentId1);
        assertEq(message.toAgentId, agentId2);
    }
}
