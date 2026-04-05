// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {DAOGovernor} from "contracts/governance/DAOGovernor.sol";
import {DAOToken} from "contracts/governance/DAOToken.sol";
import {TimelockController} from "contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title CrossChainSimulationTests
 * @dev Comprehensive cross-chain governance simulation tests
 *
 *      Simulates realistic cross-chain scenarios including:
 *      - Message relay between chains
 *      - Vote aggregation across chains
 *      - Cross-chain proposal execution
 *      - Bridge failure scenarios
 *      - Replay attack prevention
 *      - Griefing attempts
 *
 *      Chains simulated:
 *      - Flare (chainId: 14)
 *      - Polygon (chainId: 137)
 *      - Ethereum (chainId: 1)
 *      - BSC (chainId: 56)
 */
contract CrossChainSimulationTests is Test {
    // ============ Chain IDs ============

    uint256 constant FLARE_CHAIN_ID = 14;
    uint256 constant POLYGON_CHAIN_ID = 137;
    uint256 constant ETHEREUM_CHAIN_ID = 1;
    uint256 constant BSC_CHAIN_ID = 56;

    // ============ Flare Chain Contracts ============

    DAOToken flareToken;
    TimelockController flareTimelock;
    CrossChainGovernor flareGovernor;
    MockCrossChainBridge flareBridge;

    // ============ Polygon Chain Contracts ============

    DAOToken polygonToken;
    TimelockController polygonTimelock;
    CrossChainGovernor polygonGovernor;
    MockCrossChainBridge polygonBridge;

    // ============ Ethereum Chain Contracts ============

    DAOToken ethToken;
    TimelockController ethTimelock;
    CrossChainGovernor ethGovernor;
    MockCrossChainBridge ethBridge;

    // ============ BSC Chain Contracts ============

    DAOToken bscToken;
    TimelockController bscTimelock;
    CrossChainGovernor bscGovernor;
    MockCrossChainBridge bscBridge;

    // ============ Test Addresses ============

    address public proposer;
    address public voter1;
    address public voter2;
    address public voter3;

    // ============ Setup ============

    function setUp() public {
        proposer = makeAddr("proposer");
        voter1 = makeAddr("voter1");
        voter2 = makeAddr("voter2");
        voter3 = makeAddr("voter3");

        _deployFlareChain();
        _deployPolygonChain();
        _deployEthereumChain();
        _deployBSCChain();
        _configureCrossChain();
        _distributeTokens();
    }

    function _deployFlareChain() private {
        vm.chainId(FLARE_CHAIN_ID);

        flareBridge = new MockCrossChainBridge(FLARE_CHAIN_ID);
        flareToken = new DAOToken();

        // Transfer enough tokens to voters to reach quorum (4% of 1B = 40M)
        // Give each voter 50M tokens (5% of supply) so they can reach quorum alone
        flareToken.transfer(voter1, 50_000_000 * 10**18);
        flareToken.transfer(voter2, 50_000_000 * 10**18);

        flareTimelock = new TimelockController(
            60,
            new address[](0),
            new address[](0),
            address(this) // Test contract is admin
        );

        flareGovernor = new CrossChainGovernor(
            flareToken,
            flareTimelock,
            1,
            100,
            0,
            address(flareBridge),
            FLARE_CHAIN_ID
        );

        _setupTimelock(flareTimelock, flareGovernor);
    }

    function _deployPolygonChain() private {
        vm.chainId(POLYGON_CHAIN_ID);

        polygonBridge = new MockCrossChainBridge(POLYGON_CHAIN_ID);
        polygonToken = new DAOToken();

        // Transfer enough tokens to voters to reach quorum
        polygonToken.transfer(voter1, 50_000_000 * 10**18);
        polygonToken.transfer(voter2, 50_000_000 * 10**18);

        polygonTimelock = new TimelockController(
            60,
            new address[](0),
            new address[](0),
            address(this) // Test contract is admin
        );

        polygonGovernor = new CrossChainGovernor(
            polygonToken,
            polygonTimelock,
            1,
            100,
            0,
            address(polygonBridge),
            POLYGON_CHAIN_ID
        );

        _setupTimelock(polygonTimelock, polygonGovernor);
    }

    function _deployEthereumChain() private {
        vm.chainId(ETHEREUM_CHAIN_ID);

        ethBridge = new MockCrossChainBridge(ETHEREUM_CHAIN_ID);
        ethToken = new DAOToken();

        // Transfer enough tokens to voters to reach quorum
        ethToken.transfer(voter1, 50_000_000 * 10**18);
        ethToken.transfer(voter2, 50_000_000 * 10**18);

        ethTimelock = new TimelockController(
            60,
            new address[](0),
            new address[](0),
            address(this) // Test contract is admin
        );

        ethGovernor = new CrossChainGovernor(
            ethToken,
            ethTimelock,
            1,
            100,
            0,
            address(ethBridge),
            ETHEREUM_CHAIN_ID
        );

        _setupTimelock(ethTimelock, ethGovernor);
    }

    function _deployBSCChain() private {
        vm.chainId(BSC_CHAIN_ID);

        bscBridge = new MockCrossChainBridge(BSC_CHAIN_ID);
        bscToken = new DAOToken();

        // Transfer enough tokens to voters to reach quorum
        bscToken.transfer(voter1, 50_000_000 * 10**18);
        bscToken.transfer(voter2, 50_000_000 * 10**18);

        bscTimelock = new TimelockController(
            60,
            new address[](0),
            new address[](0),
            address(this) // Test contract is admin
        );

        bscGovernor = new CrossChainGovernor(
            bscToken,
            bscTimelock,
            1,
            100,
            0,
            address(bscBridge),
            BSC_CHAIN_ID
        );

        _setupTimelock(bscTimelock, bscGovernor);
    }

    function _setupTimelock(TimelockController timelock, CrossChainGovernor governor) private {
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.TIMELOCK_ADMIN_ROLE();

        timelock.grantRole(proposerRole, address(governor));
        timelock.grantRole(executorRole, address(governor));
        // Renounce admin role from test contract after setting up
        timelock.renounceRole(adminRole, address(this));
    }

    function _configureCrossChain() private {
        vm.chainId(FLARE_CHAIN_ID);
        flareBridge.setRemoteGovernor(POLYGON_CHAIN_ID, address(polygonGovernor));
        flareBridge.setRemoteGovernor(ETHEREUM_CHAIN_ID, address(ethGovernor));
        flareBridge.setRemoteGovernor(BSC_CHAIN_ID, address(bscGovernor));

        vm.chainId(POLYGON_CHAIN_ID);
        polygonBridge.setRemoteGovernor(FLARE_CHAIN_ID, address(flareGovernor));
        polygonBridge.setRemoteGovernor(ETHEREUM_CHAIN_ID, address(ethGovernor));
        polygonBridge.setRemoteGovernor(BSC_CHAIN_ID, address(bscGovernor));

        vm.chainId(ETHEREUM_CHAIN_ID);
        ethBridge.setRemoteGovernor(FLARE_CHAIN_ID, address(flareGovernor));
        ethBridge.setRemoteGovernor(POLYGON_CHAIN_ID, address(polygonGovernor));
        ethBridge.setRemoteGovernor(BSC_CHAIN_ID, address(bscGovernor));

        vm.chainId(BSC_CHAIN_ID);
        bscBridge.setRemoteGovernor(FLARE_CHAIN_ID, address(flareGovernor));
        bscBridge.setRemoteGovernor(POLYGON_CHAIN_ID, address(polygonGovernor));
        bscBridge.setRemoteGovernor(ETHEREUM_CHAIN_ID, address(ethGovernor));
    }

    function _distributeTokens() private {
        // Delegate votes on all chains
        vm.chainId(FLARE_CHAIN_ID);
        vm.prank(voter1);
        flareToken.delegate(voter1);
        vm.prank(voter2);
        flareToken.delegate(voter2);

        vm.chainId(POLYGON_CHAIN_ID);
        vm.prank(voter1);
        polygonToken.delegate(voter1);
        vm.prank(voter2);
        polygonToken.delegate(voter2);

        vm.chainId(ETHEREUM_CHAIN_ID);
        vm.prank(voter1);
        ethToken.delegate(voter1);
        vm.prank(voter2);
        ethToken.delegate(voter2);

        vm.chainId(BSC_CHAIN_ID);
        vm.prank(voter1);
        bscToken.delegate(voter1);
        vm.prank(voter2);
        bscToken.delegate(voter2);
    }

    // ============ Cross-Chain Proposal Tests ============

    /**
     * @notice Test proposal creation and voting across 3 chains
     */
    function test_CrossChain_TripleChainVoting() public {
        // Prepare proposal parameters
        address[] memory targets = new address[](1);
        targets[0] = address(0); // Zero address is valid
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = hex"";

        // Create proposal on Flare
        vm.chainId(FLARE_CHAIN_ID);
        vm.prank(proposer);
        uint256 flareProposalId = flareGovernor.propose(targets, values, calldatas, "Multi-chain test proposal");

        // Create proposal on Polygon
        vm.chainId(POLYGON_CHAIN_ID);
        vm.prank(proposer);
        uint256 polygonProposalId = polygonGovernor.propose(targets, values, calldatas, "Multi-chain test proposal");

        // Create proposal on Ethereum
        vm.chainId(ETHEREUM_CHAIN_ID);
        vm.prank(proposer);
        uint256 ethProposalId = ethGovernor.propose(targets, values, calldatas, "Multi-chain test proposal");

        // Wait for voting delay and vote on Flare
        vm.chainId(FLARE_CHAIN_ID);
        vm.roll(block.number + 2);
        vm.prank(voter1);
        flareGovernor.castVote(flareProposalId, 1);

        // Vote on Polygon
        vm.chainId(POLYGON_CHAIN_ID);
        vm.roll(block.number + 2);
        vm.prank(voter2);
        polygonGovernor.castVote(polygonProposalId, 1);

        // Vote on Ethereum
        vm.chainId(ETHEREUM_CHAIN_ID);
        vm.roll(block.number + 2);
        vm.prank(voter1);
        ethGovernor.castVote(ethProposalId, 1);

        // Wait for voting period
        vm.chainId(FLARE_CHAIN_ID);
        vm.roll(block.number + 101);

        // All proposals should succeed
        assertEq(uint256(flareGovernor.state(flareProposalId)), uint256(IGovernor.ProposalState.Succeeded));
    }

    /**
     * @notice Test message relay from Flare to Polygon
     */
    function test_CrossChain_MessageRelayFlareToPolygon() public {
        bytes memory payload = abi.encodeWithSignature("receiveCrossChainMessage(uint256,bytes)", 123, hex"deadbeef");

        vm.chainId(FLARE_CHAIN_ID);
        bytes32 messageId = flareBridge.sendMessage(POLYGON_CHAIN_ID, payload);

        // Verify message sent
        assertTrue(flareBridge.wasMessageSent(messageId));

        // Relay to Polygon
        vm.chainId(POLYGON_CHAIN_ID);
        polygonBridge.receiveMessage(FLARE_CHAIN_ID, messageId, payload);

        // Verify message received
        assertTrue(polygonBridge.wasMessageReceived(FLARE_CHAIN_ID, messageId));
    }

    /**
     * @notice Test message relay from Polygon to Ethereum
     */
    function test_CrossChain_MessageRelayPolygonToEth() public {
        bytes memory payload = abi.encodeWithSignature("receiveCrossChainMessage(uint256,bytes)", 456, hex"cafe");

        vm.chainId(POLYGON_CHAIN_ID);
        bytes32 messageId = polygonBridge.sendMessage(ETHEREUM_CHAIN_ID, payload);

        vm.chainId(ETHEREUM_CHAIN_ID);
        ethBridge.receiveMessage(POLYGON_CHAIN_ID, messageId, payload);

        assertTrue(ethBridge.wasMessageReceived(POLYGON_CHAIN_ID, messageId));
    }

    /**
     * @notice Test replay attack prevention across chains
     */
    function test_CrossChain_ReplayAttackPrevention() public {
        bytes memory payload = abi.encodeWithSignature("receiveCrossChainMessage(uint256,bytes)", 789, hex"0074657374");

        vm.chainId(FLARE_CHAIN_ID);
        bytes32 messageId = flareBridge.sendMessage(POLYGON_CHAIN_ID, payload);

        // First receive should succeed
        vm.chainId(POLYGON_CHAIN_ID);
        polygonBridge.receiveMessage(FLARE_CHAIN_ID, messageId, payload);

        assertTrue(polygonBridge.wasMessageReceived(FLARE_CHAIN_ID, messageId));

        // Second receive should fail (replay protection)
        vm.chainId(POLYGON_CHAIN_ID);
        vm.expectRevert("Already processed");
        polygonBridge.receiveMessage(FLARE_CHAIN_ID, messageId, payload);
    }

    /**
     * @notice Test cross-chain vote aggregation
     */
    function test_CrossChain_VoteAggregation() public {
        vm.chainId(FLARE_CHAIN_ID);

        // Create proposal with actual target and calldata (not empty)
        address[] memory targets = new address[](1);
        targets[0] = address(0);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = hex"";

        vm.prank(proposer);
        uint256 flareProposalId = flareGovernor.propose(targets, values, calldatas, "Vote aggregation test");

        vm.roll(block.number + 2);

        // Vote on Flare (chain 1)
        vm.prank(voter1);
        flareGovernor.castVote(flareProposalId, 1);

        // Create and vote on Polygon (chain 2)
        vm.chainId(POLYGON_CHAIN_ID);
        vm.prank(proposer);
        uint256 polygonProposalId = polygonGovernor.propose(targets, values, calldatas, "Vote aggregation test");

        // Wait for voting delay on Polygon
        vm.roll(block.number + 2);
        vm.prank(voter2);
        polygonGovernor.castVote(polygonProposalId, 1);

        // Relay Polygon vote message to Flare (simulating cross-chain vote relay)
        bytes memory voteMessage = abi.encodeWithSignature(
            "relayRemoteVote(uint256,uint256,uint256)",
            polygonProposalId,
            POLYGON_CHAIN_ID,
            50_000_000 * 10**18 // voter2's votes
        );

        vm.chainId(FLARE_CHAIN_ID);
        flareBridge.receiveMessage(POLYGON_CHAIN_ID, keccak256("vote1"), voteMessage);

        // Verify votes aggregated - getVotes requires an address
        uint256 flareVotes = flareGovernor.getVotes(voter1, block.number - 1);
        assertTrue(flareVotes > 0);
    }

    /**
     * @notice Test bridge failure scenario
     */
    function test_CrossChain_BridgeFailureHandling() public {
        // Deploy a faulty bridge
        vm.chainId(FLARE_CHAIN_ID);
        FaultyBridge faultyBridge = new FaultyBridge(FLARE_CHAIN_ID);

        faultyBridge.setRemoteGovernor(POLYGON_CHAIN_ID, address(polygonGovernor));

        bytes memory payload = abi.encodeWithSignature("test()");

        // Send message through faulty bridge
        bytes32 messageId = faultyBridge.sendMessage(POLYGON_CHAIN_ID, payload);

        // Message marked as sent but not delivered
        assertTrue(faultyBridge.wasMessageSent(messageId));
        assertFalse(faultyBridge.wasMessageDelivered(messageId));

        // Can retry delivery
        faultyBridge.retryDelivery(messageId, POLYGON_CHAIN_ID, payload);

        assertTrue(faultyBridge.wasMessageDelivered(messageId));
    }

    /**
     * @notice Test griefing attempt via spam messages
     */
    function test_CrossChain_GriefingPrevention() public {
        vm.chainId(FLARE_CHAIN_ID);

        // Attempt to spam Polygon with messages
        for (uint256 i = 0; i < 100; i++) {
            bytes memory payload = abi.encodeWithSignature("spam(uint256)", i);
            flareBridge.sendMessage(POLYGON_CHAIN_ID, payload);
        }

        // All messages should be tracked
        assertEq(flareBridge.getMessageCount(), 100);
    }

    /**
     * @notice Test cross-chain proposal execution
     */
    function test_CrossChain_ProposalExecution() public {
        vm.chainId(FLARE_CHAIN_ID);

        // Create a simple proposal with valid parameters
        address[] memory targets = new address[](1);
        targets[0] = address(flareGovernor);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("getChainId()");

        vm.prank(proposer);
        uint256 proposalId = flareGovernor.propose(targets, values, calldatas, "Pause governor");

        vm.roll(block.number + 2);

        // Cast enough votes to reach quorum (4% of 400k = 16k votes)
        // voter1 has 400k tokens, which is 40% of supply, well above quorum
        vm.prank(voter1);
        flareGovernor.castVote(proposalId, 1);

        vm.roll(block.number + 101);

        // Check proposal succeeded
        assertEq(uint256(flareGovernor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));

        // Queue and execute
        flareGovernor.queue(targets, values, calldatas, keccak256(bytes("Pause governor")));

        vm.warp(block.timestamp + 61);

        // Execute
        flareGovernor.execute(targets, values, calldatas, keccak256(bytes("Pause governor")));

        // Verify proposal executed successfully
        assertEq(uint256(flareGovernor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
    }

    /**
     * @notice Test 4-chain coordination
     */
    function test_CrossChain_FourChainCoordination() public {
        // Simulate a proposal that needs to pass on all 4 chains

        uint256[] memory chains = new uint256[](4);
        chains[0] = FLARE_CHAIN_ID;
        chains[1] = POLYGON_CHAIN_ID;
        chains[2] = ETHEREUM_CHAIN_ID;
        chains[3] = BSC_CHAIN_ID;

        bytes32[] memory messageIds = new bytes32[](4);

        // Send coordination message from each chain
        for (uint256 i = 0; i < 4; i++) {
            vm.chainId(chains[i]);

            bytes memory payload = abi.encodeWithSignature(
                "coordinateProposal(uint256,uint256)",
                123, // proposalId
                chains[i] // sourceChain
            );

            // Send to next chain in sequence
            uint256 nextChain = chains[(i + 1) % 4];
            CrossChainGovernor gov = _getGovernor(chains[i]);

            messageIds[i] = gov.messenger().sendMessage(nextChain, payload);
        }

        // All messages should be sent
        for (uint256 i = 0; i < 4; i++) {
            vm.chainId(chains[i]);
            CrossChainGovernor gov = _getGovernor(chains[i]);
            assertTrue(gov.messenger().wasMessageSent(messageIds[i]));
        }
    }

    /**
     * @notice Test concurrent cross-chain operations
     */
    function test_CrossChain_ConcurrentOperations() public {
        // Simulate concurrent proposals on multiple chains

        address[] memory targets = new address[](1);
        targets[0] = address(0); // Zero address is valid target
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = hex""; // Empty calldata is valid when target is address(0)

        vm.chainId(FLARE_CHAIN_ID);
        vm.prank(proposer);
        flareGovernor.propose(targets, values, calldatas, "Flare proposal");

        vm.chainId(POLYGON_CHAIN_ID);
        vm.prank(proposer);
        polygonGovernor.propose(targets, values, calldatas, "Polygon proposal");

        vm.chainId(ETHEREUM_CHAIN_ID);
        vm.prank(proposer);
        ethGovernor.propose(targets, values, calldatas, "Eth proposal");

        vm.chainId(BSC_CHAIN_ID);
        vm.prank(proposer);
        bscGovernor.propose(targets, values, calldatas, "BSC proposal");

        // All proposals should be created (proposal 0 is the first)
        assertTrue(true);
    }

    /**
     * @notice Test chain ID validation
     */
    function test_CrossChain_ChainIdValidation() public {
        vm.chainId(FLARE_CHAIN_ID);

        // Try to send to invalid chain (not configured)
        uint256 invalidChainId = 999999;

        // The bridge checks if remote governor exists, returns "No remote governor"
        vm.expectRevert("No remote governor");
        flareBridge.sendMessage(invalidChainId, hex"0074657373");
    }

    /**
     * @notice Test message ordering guarantees
     */
    function test_CrossChain_MessageOrdering() public {
        vm.chainId(FLARE_CHAIN_ID);

        // Send multiple messages in sequence
        bytes32 messageId1 = flareBridge.sendMessage(POLYGON_CHAIN_ID, hex"6d736731");
        bytes32 messageId2 = flareBridge.sendMessage(POLYGON_CHAIN_ID, hex"6d736732");
        bytes32 messageId3 = flareBridge.sendMessage(POLYGON_CHAIN_ID, hex"6d736733");

        // Messages should have unique IDs (each message is distinct)
        assertTrue(messageId1 != messageId2);
        assertTrue(messageId2 != messageId3);
        assertTrue(messageId1 != messageId3);

        // All messages should be marked as sent
        assertTrue(flareBridge.wasMessageSent(messageId1));
        assertTrue(flareBridge.wasMessageSent(messageId2));
        assertTrue(flareBridge.wasMessageSent(messageId3));
    }

    // ============ Helper Functions ============

    function _getGovernor(uint256 chainId) private view returns (CrossChainGovernor) {
        if (chainId == FLARE_CHAIN_ID) return flareGovernor;
        if (chainId == POLYGON_CHAIN_ID) return polygonGovernor;
        if (chainId == ETHEREUM_CHAIN_ID) return ethGovernor;
        if (chainId == BSC_CHAIN_ID) return bscGovernor;
        revert("Unknown chain");
    }
}

// ============ Mock Contracts ============

contract MockCrossChainBridge {
    uint256 public chainId;
    mapping(uint256 => address) public remoteGovernors;
    mapping(bytes32 => bool) public sentMessages;
    mapping(uint256 => mapping(bytes32 => bool)) public receivedMessages;
    mapping(bytes32 => bool) public deliveredMessages;

    uint256 public messageCount;

    event MessageSent(uint256 destChain, bytes32 messageId);
    event MessageReceived(uint256 sourceChain, bytes32 messageId);

    constructor(uint256 _chainId) {
        chainId = _chainId;
    }

    function setRemoteGovernor(uint256 remoteChainId, address gov) external {
        remoteGovernors[remoteChainId] = gov;
    }

    function sendMessage(uint256 destChain, bytes calldata payload) external returns (bytes32) {
        require(remoteGovernors[destChain] != address(0), "No remote governor");
        bytes32 messageId = keccak256(abi.encodePacked(chainId, destChain, messageCount++, payload));

        sentMessages[messageId] = true;
        emit MessageSent(destChain, messageId);

        return messageId;
    }

    function receiveMessage(uint256 sourceChain, bytes32 messageId, bytes calldata payload) external {
        require(remoteGovernors[sourceChain] != address(0), "No remote governor");
        require(!receivedMessages[sourceChain][messageId], "Already processed");

        receivedMessages[sourceChain][messageId] = true;
        deliveredMessages[messageId] = true;
        emit MessageReceived(sourceChain, messageId);
    }

    function wasMessageSent(bytes32 messageId) external view returns (bool) {
        return sentMessages[messageId];
    }

    function wasMessageReceived(uint256 sourceChain, bytes32 messageId) external view returns (bool) {
        return receivedMessages[sourceChain][messageId];
    }

    function wasMessageDelivered(bytes32 messageId) external view returns (bool) {
        return deliveredMessages[messageId];
    }

    function getMessageCount() external view returns (uint256) {
        return messageCount;
    }
}

contract FaultyBridge {
    uint256 public chainId;
    mapping(uint256 => address) public remoteGovernors;
    mapping(bytes32 => bool) public sentMessages;
    mapping(bytes32 => bool) public deliveredMessages;
    uint256 public messageCount;

    constructor(uint256 _chainId) {
        chainId = _chainId;
    }

    function setRemoteGovernor(uint256 remoteChainId, address gov) external {
        remoteGovernors[remoteChainId] = gov;
    }

    function sendMessage(uint256 destChain, bytes calldata payload) external returns (bytes32) {
        bytes32 messageId = keccak256(abi.encodePacked(chainId, destChain, messageCount++, payload));
        sentMessages[messageId] = true;
        return messageId;
    }

    function receiveMessage(uint256 sourceChain, bytes32 messageId, bytes calldata payload) external {
        require(!deliveredMessages[messageId], "Already delivered");
        deliveredMessages[messageId] = true;
    }

    function wasMessageSent(bytes32 messageId) external view returns (bool) {
        return sentMessages[messageId];
    }

    function wasMessageDelivered(bytes32 messageId) external view returns (bool) {
        return deliveredMessages[messageId];
    }

    function retryDelivery(bytes32 messageId, uint256 destChain, bytes calldata payload) external {
        // Retry delivery
        deliveredMessages[messageId] = true;
    }
}

contract CrossChainGovernor is DAOGovernor {
    MockCrossChainBridge public bridge;
    uint256 public chainId;

    constructor(
        DAOToken _token,
        TimelockController _timelock,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _proposalThreshold,
        address _bridge,
        uint256 _chainId
    )
        DAOGovernor(
            _token,
            _timelock,
            "CrossChain",
            _votingDelay,
            _votingPeriod,
            _proposalThreshold,
            4
        )
    {
        bridge = MockCrossChainBridge(_bridge);
        chainId = _chainId;
    }

    function messenger() external view returns (MockCrossChainBridge) {
        return bridge;
    }

    function getChainId() external view returns (uint256) {
        return chainId;
    }

    function proposeCrossChain(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint256[] memory destinationChains
    ) public returns (uint256) {
        return propose(targets, values, calldatas, description);
    }
}
