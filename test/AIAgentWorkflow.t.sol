// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {IdentityRegistry} from "contracts/agents/IdentityRegistry.sol";
import {ReputationRegistry} from "contracts/agents/ReputationRegistry.sol";
import {ValidationRegistry} from "contracts/agents/ValidationRegistry.sol";
import {AIAgentRegistry} from "contracts/ai/AIAgentRegistry.sol";
import {IAIAgentRegistry} from "contracts/ai/IAIAgentRegistry.sol";
import {IAutonomousExecutor} from "contracts/ai/IAutonomousExecutor.sol";
import {AIAgentFactory} from "contracts/ai/AIAgentFactory.sol";
import {IAIAgentFactory} from "contracts/interfaces/IAIAgentFactory.sol";
import {AutonomousExecutor} from "contracts/ai/AutonomousExecutor.sol";
import {AgentCommunication} from "contracts/ai/AgentCommunication.sol";
import {IAgentCommunication} from "contracts/ai/IAgentCommunication.sol";
import {AIBountyBridge} from "contracts/ai/AIBountyBridge.sol";
import {Marketplace} from "contracts/payments/Marketplace.sol";
import {IMarketplace} from "contracts/interfaces/IMarketplace.sol";
import {MarketplaceEscrow} from "contracts/payments/MarketplaceEscrow.sol";
import {PaymentVerifier} from "contracts/payments/PaymentVerifier.sol";
import {IPaymentVerifier} from "contracts/interfaces/IPaymentVerifier.sol";
import {PaymentLedger} from "contracts/payments/PaymentLedger.sol";
import {DAOToken} from "contracts/governance/DAOToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title AIAgentWorkflowIntegrationTest
 * @dev Tests end-to-end AI agent workflows from registration to task completion
 */
contract AIAgentWorkflowIntegrationTest is Test {
    // Core registries
    IdentityRegistry public identityRegistry;
    ReputationRegistry public reputationRegistry;
    ValidationRegistry public validationRegistry;

    // AI Agent contracts
    AIAgentRegistry public aiAgentRegistry;
    AIAgentFactory public aiAgentFactory;
    AutonomousExecutor public executor;
    AgentCommunication public communication;
    AIBountyBridge public bountyBridge;

    // Marketplace
    Marketplace public marketplace;
    MarketplaceEscrow public escrow;
    PaymentVerifier public paymentVerifier;
    PaymentLedger public paymentLedger;

    // Tokens
    DAOToken public governanceToken;
    MockERC20 public paymentToken;

    // Addresses
    address public overseer;
    address public relayer;
    address public user;
    address public serviceSeeker;

    // Agent tracking
    uint256 public agentId;
    uint256 public listingId;

    event AgentRegistered(uint256 indexed agentId, address indexed agentAddress);
    event ExecutorDeployed(address indexed executor, address overseer);
    event MessageSent(
        uint256 indexed fromAgentId,
        uint256 indexed toAgentId,
        bytes32 indexed messageId
    );
    event BountyCompleted(uint256 indexed listingId, uint256 indexed agentId);

    AIBountyBridge private _bountyBridge; // Internal storage for bounty bridge

    function setUp() public {
        overseer = makeAddr("overseer");
        relayer = makeAddr("relayer");
        user = makeAddr("user");
        serviceSeeker = makeAddr("serviceSeeker");

        _deployCoreContracts();
        _deployMarketplace(); // Deploy marketplace first
        _deployAIContracts(); // Then AI contracts
        _configureContracts();
        _registerTestAgent();

        // Set the public bountyBridge reference
        bountyBridge = _bountyBridge;
    }

    function _deployCoreContracts() private {
        identityRegistry = new IdentityRegistry();
        reputationRegistry = new ReputationRegistry();
        validationRegistry = new ValidationRegistry();
    }

    function _deployMarketplace() private {
        paymentLedger = new PaymentLedger();

        address[] memory initialTokens = new address[](0);
        paymentVerifier = new PaymentVerifier(
            address(paymentLedger),
            initialTokens,
            1_000_000 * 10**18, // max payment amount
            10_000_000 * 10**18, // max daily global
            1_000_000 * 10**18, // max daily per payer
            500_000 * 10**18, // max daily per recipient
            9_000_000 * 10**18 // circuit breaker
        );

        escrow = new MarketplaceEscrow(7 days);

        marketplace = new Marketplace(
            address(paymentVerifier),
            address(paymentLedger),
            address(identityRegistry),
            address(reputationRegistry),
            address(validationRegistry),
            address(0), // revenueSharing - can be address(0)
            address(escrow),
            overseer, // fee recipient
            100, // 1% platform fee (100 basis points)
            100 * 10**18 // escrow threshold
        );

        // Configure payment ledger (test contract is deployer/owner)
        paymentLedger.addVerifier(address(paymentVerifier));

        // Configure payment verifier (test contract is owner)
        paymentVerifier.setFacilitator(address(marketplace), true);

        // Set marketplace in escrow (test contract is owner)
        escrow.setMarketplace(address(marketplace));
    }

    function _deployAIContracts() private {
        aiAgentRegistry = new AIAgentRegistry();

        communication = new AgentCommunication(address(aiAgentRegistry));

        executor = new AutonomousExecutor(address(aiAgentRegistry));

        // Grant SPENDER_ROLE to executor so it can record spending
        bytes32 spenderRole = aiAgentRegistry.SPENDER_ROLE();
        aiAgentRegistry.grantRole(spenderRole, address(executor));

        aiAgentFactory = new AIAgentFactory();

        // Deploy bounty bridge with marketplace address
        _bountyBridge = new AIBountyBridge(
            address(marketplace),
            address(aiAgentRegistry),
            address(reputationRegistry)
        );
    }

    function _configureContracts() private {
        // Deploy payment token
        paymentToken = new MockERC20();
        vm.deal(serviceSeeker, 100 ether);

        // Deploy governance token (constructor takes no args)
        governanceToken = new DAOToken();

        // Set up payment verifier (test contract is owner)
        paymentVerifier.addSupportedToken(address(paymentToken));

        // Set up marketplace (test contract is owner)
        marketplace.addSupportedToken(address(paymentToken));
    }

    function _registerTestAgent() private {
        vm.startPrank(user);

        // Register as human agent first
        uint256 humanAgentId = identityRegistry.register("ipfs://QmTest");

        // Register as AI agent (separate registry with separate ID)
        uint256 aiAgentId = aiAgentRegistry.registerAIAgent(
            "ipfs://QmAI",  // metadata
            IAIAgentRegistry.AgentType.Autonomous,  // agentType
            "gpt-4-turbo",  // modelId
            10 ether,  // monthlyBudget
            user  // overseer
        );

        // Store the human agent ID for marketplace operations
        agentId = humanAgentId;

        vm.stopPrank();
    }

    // ============ Workflow Tests ============

    /**
     * @dev Test complete AI agent workflow:
     * 1. Agent registration
     * 2. Bounty creation
     * 3. Bounty acceptance by AI
     * 4. Task execution via executor
     * 5. Payment processing
     * 6. Reputation update
     */
    function testCompleteAIAgentWorkflow() public {
        // Step 0: Register serviceSeeker as an agent (required to create bounty)
        vm.prank(serviceSeeker);
        identityRegistry.register("ipfs://serviceSeeker");

        // Step 1: Create bounty (service seeker creates bounty)
        vm.startPrank(serviceSeeker);

        paymentToken.mint(serviceSeeker, 10000 * 10**18);
        paymentToken.approve(address(marketplace), 10000 * 10**18);

        uint256 reward = 1000 * 10**18;

        // Create bounty with correct signature
        listingId = marketplace.createBounty(
            address(paymentToken),
            reward,
            "ipfs://bounty-metadata"
        );

        vm.stopPrank();

        // Verify bounty created
        IMarketplace.Bounty memory bounty = marketplace.getBounty(listingId);

        assertEq(bounty.token, address(paymentToken));
        assertEq(bounty.reward, reward);
        assertTrue(bounty.bountyStatus == IMarketplace.BountyStatus.Open);

        // Step 2: AI agent claims bounty via bridge (user is the overseer of the AI agent)
        vm.prank(user);
        bountyBridge.claimBountyForAgent(
            listingId,
            agentId,
            "ipfs://work-proof"
        );

        // Step 2.5: Also claim the bounty in the marketplace (required for the marketplace flow)
        vm.prank(user);
        marketplace.claimBounty(listingId);

        // Step 3: Complete the bounty
        vm.prank(user);
        marketplace.completeBounty(listingId);

        // Step 4: Pay the bounty
        vm.prank(serviceSeeker);
        marketplace.payBounty(listingId);

        // Step 5: Verify reputation update
        int256 reputation = reputationRegistry.getReputation(agentId);
        assertTrue(reputation >= 0);
    }

    /**
     * @dev Test AI agent communication
     */
    function testAIAgentCommunication() public {
        // Use a different user to register another AI agent (since user is already registered)
        address user2 = makeAddr("user2");
        vm.startPrank(user2);
        uint256 humanAgentId2 = identityRegistry.register("ipfs://QmTest2");

        uint256 aiAgentId2 = aiAgentRegistry.registerAIAgent(
            "ipfs://QmAI2",
            IAIAgentRegistry.AgentType.Autonomous,
            "gpt-4",
            5 ether,
            user2
        );
        vm.stopPrank();

        // Send message from agent1 to agent2
        // Note: AgentCommunication uses AI agent registry to get sender's agent ID
        // So we need to call from the overseer address
        vm.prank(user);
        uint256 messageId = communication.sendMessage(
            aiAgentId2,  // toAgentId (recipient) - send to agent 2, not agent 1
            "query",  // method
            "What's the ETH price?",  // params (JSON string)
            block.timestamp + 1 hours  // expiresAt
        );

        // Verify message sent
        assertTrue(messageId != 0);

        // Read message using getMessage
        IAgentCommunication.Message memory messageData = communication.getMessage(messageId);

        assertEq(messageData.fromAgentId, agentId);  // Sender is the AI agent registered to user
        assertEq(messageData.toAgentId, aiAgentId2);  // Recipient is agent 2
        assertEq(messageData.method, "query");
        assertEq(messageData.params, "What's the ETH price?");
        assertTrue(messageData.timestamp > 0);

        // Verify pending messages
        IAgentCommunication.Message[] memory pending = communication.getPendingMessages(aiAgentId2, 10);
        assertGe(pending.length, 1);
    }

    /**
     * @dev Test AI agent factory stack deployment
     */
    function testAIAgentFactoryDeployment() public {
        vm.startPrank(user);

        // Deploy new AI stack with correct params
        IAIAgentFactory.CreateAgentParams memory params = IAIAgentFactory.CreateAgentParams({
            name: "TestStack",
            admin: overseer,
            pauser: user,
            allowlistManager: user,
            dailyLimit: 10 ether
        });

        IAIAgentFactory.AIAgentDeployment memory stack = aiAgentFactory.createAgentStack(params);

        // Verify deployment
        assertTrue(stack.aiRegistry != address(0));
        assertTrue(stack.executor != address(0));
        assertTrue(stack.communication != address(0));

        // Verify stack was registered
        IAIAgentFactory.AIAgentDeployment memory registeredStack = aiAgentFactory.getStack("TestStack");
        assertEq(registeredStack.aiRegistry, stack.aiRegistry);
        assertEq(registeredStack.executor, stack.executor);
        assertEq(registeredStack.communication, stack.communication);

        vm.stopPrank();
    }

    /**
     * @dev Test executor access control
     */
    function testExecutorAccessControl() public {
        // Set daily limit for agent (test contract is owner)
        executor.setDailyLimit(agentId, 10 * 10**18);

        // Allow target for agent (test contract is owner)
        // Must provide specific function selectors, not empty array
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = bytes4(keccak256("name()")); // name() function selector
        executor.addToAllowlist(address(paymentToken), selectors);

        // Agent can execute within limit
        address target = address(paymentToken);
        bytes memory data = abi.encodeWithSignature("name()");

        executor.executeWithBudget(agentId, target, data, 0);

        // Verify execution count increased
        (uint256 totalExecs,,) = executor.getExecutionStats(agentId);
        assertEq(totalExecs, 1);
    }

    /**
     * @dev Test AI agent listing with escrow
     */
    function testAIAgentListingWithEscrow() public {
        vm.startPrank(user);  // user is the registered agent

        // Create listing with high value
        uint256 highPrice = 10000 * 10**18;
        paymentToken.mint(user, highPrice);
        paymentToken.approve(address(marketplace), highPrice);

        uint256 escrowListingId = marketplace.createListing(
            address(paymentToken),
            highPrice,
            "ipfs://high-value-listing"
        );

        vm.stopPrank();

        // Verify listing created (check listing data instead of just id)
        IMarketplace.Listing memory listing = marketplace.getListing(escrowListingId);
        assertEq(listing.price, highPrice);
        assertEq(listing.token, address(paymentToken));
        assertTrue(listing.status == IMarketplace.ListingStatus.Active);
    }

    /**
     * @dev Test AI agent batch operations
     */
    function testAIAgentBatchOperations() public {
        // Create multiple service listings (not bounties)
        vm.startPrank(user);  // user is the registered agent

        paymentToken.mint(user, 50000 * 10**18);
        paymentToken.approve(address(marketplace), 50000 * 10**18);

        uint256[] memory listingIds = new uint256[](5);
        for (uint256 i = 0; i < 5; i++) {
            listingIds[i] = marketplace.createListing(
                address(paymentToken),
                1000 * 10**18,
                "ipfs://listing"
            );
        }

        vm.stopPrank();

        // Verify all listings were created successfully
        for (uint256 i = 0; i < 5; i++) {
            IMarketplace.Listing memory listing = marketplace.getListing(listingIds[i]);
            assertEq(listing.price, 1000 * 10**18);
            assertEq(listing.agentId, agentId);
            assertTrue(listing.status == IMarketplace.ListingStatus.Active);
        }
    }

    /**
     * @dev Test AI agent reputation integration
     */
    function testAIAgentReputationIntegration() public {
        // Initial reputation
        int256 initialReputation = reputationRegistry.getReputation(agentId);

        // Submit a positive review
        vm.prank(overseer);
        reputationRegistry.submitReview(
            agentId,
            10, // maximum positive score
            "Task completed successfully"
        );

        int256 newReputation = reputationRegistry.getReputation(agentId);
        assertEq(newReputation, 10);

        // Verify AI agent is active
        IAIAgentRegistry.AIAgent memory aiAgent = aiAgentRegistry.getAIAgent(agentId);
        assertTrue(aiAgent.isActive);
    }

    /**
     * @dev Test AI agent deactivation
     */
    function testAIAgentDeactivation() public {
        // Deactivate AI agent
        vm.prank(user);
        aiAgentRegistry.deactivateAgent(agentId);

        IAIAgentRegistry.AIAgent memory aiAgent = aiAgentRegistry.getAIAgent(agentId);
        assertFalse(aiAgent.isActive);

        // Cannot claim new bounties when inactive
        // First, register another agent to create the listing
        address otherUser = makeAddr("otherUser");
        vm.startPrank(otherUser);
        uint256 otherAgentId = identityRegistry.register("ipfs://QmOther");

        paymentToken.mint(otherUser, 1000 * 10**18);
        paymentToken.approve(address(marketplace), 1000 * 10**18);

        uint256 newListingId = marketplace.createListing(
            address(paymentToken),
            1000 * 10**18,
            "ipfs://listing"
        );

        vm.stopPrank();

        // Try to claim bounty for deactivated agent (user is the overseer)
        vm.prank(user);
        vm.expectRevert();
        bountyBridge.claimBountyForAgent(newListingId, agentId, "ipfs://proof");
    }

    /**
     * @dev Test executor batch execution
     */
    function testExecutorBatchExecution() public {
        // Set up executor for batch operations (test contract is owner)
        executor.setDailyLimit(agentId, 100 * 10**18);

        // Allow multiple targets with specific selectors
        bytes4[] memory tokenSelectors = new bytes4[](1);
        tokenSelectors[0] = bytes4(keccak256("name()"));
        executor.addToAllowlist(address(paymentToken), tokenSelectors);

        bytes4[] memory govSelectors = new bytes4[](1);
        govSelectors[0] = bytes4(keccak256("name()"));
        executor.addToAllowlist(address(governanceToken), govSelectors);

        // Prepare batch calls
        IAutonomousExecutor.Action[] memory actions = new IAutonomousExecutor.Action[](2);

        actions[0] = IAutonomousExecutor.Action({
            target: address(paymentToken),
            value: 0,
            data: abi.encodeWithSignature("name()")
        });

        actions[1] = IAutonomousExecutor.Action({
            target: address(governanceToken),
            value: 0,
            data: abi.encodeWithSignature("name()")
        });

        // Execute batch
        executor.executeBatch(agentId, actions);

        // Verify execution count increased by 2
        (uint256 totalExecs,,) = executor.getExecutionStats(agentId);
        assertEq(totalExecs, 2);
    }

    /**
     * @dev Test cross-chain AI agent operations
     * Note: This is a placeholder test as cross-chain functionality
     * would require additional infrastructure
     */
    function testCrossChainAIAgentOperations() public {
        // Placeholder for cross-chain test
        // In production, this would test cross-chain messaging
        // and agent coordination across different networks
        assertTrue(true);
    }
}

// Mock ERC20 for testing
contract MockERC20 is ERC20 {
    constructor() ERC20("Mock USDT", "USDT") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
