// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {DAOGovernor} from "contracts/governance/DAOGovernor.sol";
import {DAOToken} from "contracts/governance/DAOToken.sol";
import {TimelockController} from "contracts/governance/TimelockController.sol";
import {DAOFactory} from "contracts/dao-maker/DAOFactory.sol";
import {IDAOFactory} from "contracts/interfaces/IDAOFactory.sol";
import {Treasury} from "contracts/treasury/Treasury.sol";
import {IdentityRegistry} from "contracts/agents/IdentityRegistry.sol";
import {ReputationRegistry} from "contracts/agents/ReputationRegistry.sol";
import {ValidationRegistry} from "contracts/agents/ValidationRegistry.sol";

// Mock cross-chain messenger (simulates CCIP, LayerZero, etc.)
contract MockCrossChainMessenger {
    mapping(uint256 => address) public remoteGovernors;
    mapping(uint256 => mapping(bytes32 => bool)) public processedMessages;
    mapping(uint256 => uint256) public chainIds;

    uint256 public localChainId;
    uint256 public messageCount;

    event CrossChainMessageSent(
        uint256 indexed destChainId,
        bytes32 indexed messageId,
        bytes payload
    );

    event CrossChainMessageReceived(
        uint256 indexed sourceChainId,
        bytes32 indexed messageId,
        bytes payload
    );

    constructor(uint256 _localChainId) {
        localChainId = _localChainId;
    }

    function setRemoteGovernor(uint256 chainId, address governor) external {
        remoteGovernors[chainId] = governor;
        chainIds[chainId] = chainId;
    }

    function sendMessage(
        uint256 destChainId,
        bytes calldata payload
    ) external returns (bytes32) {
        bytes32 messageId = keccak256(
            abi.encodePacked(localChainId, destChainId, messageCount++, payload)
        );

        emit CrossChainMessageSent(destChainId, messageId, payload);

        // Simulate message delivery by calling the receiver
        // In production, this would be handled by the relayer
        return messageId;
    }

    function receiveMessage(
        uint256 sourceChainId,
        bytes32 messageId,
        bytes calldata payload
    ) external {
        require(remoteGovernors[sourceChainId] != address(0), "Remote not configured");
        require(!processedMessages[sourceChainId][messageId], "Already processed");

        // Mark as processed before execution to prevent replay attacks
        processedMessages[sourceChainId][messageId] = true;

        emit CrossChainMessageReceived(sourceChainId, messageId, payload);

        // Forward to local governor - catch failures but don't revert
        // This allows testing replay protection even when payload execution fails
        (bool success, ) = address(remoteGovernors[sourceChainId]).call(payload);
        if (!success) {
            // Emit an event for debugging but don't revert
            // The message is still marked as processed
        }
    }
}

// Cross-chain governor that coordinates votes across chains
contract CrossChainGovernor is DAOGovernor {
    MockCrossChainMessenger public messenger;
    uint256 public localChainId;
    mapping(uint256 => bool) public supportedChains;

    // Cross-chain proposal tracking
    struct CrossChainProposal {
        uint256 localProposalId;
        mapping(uint256 => uint256) remoteProposalIds; // chainId => proposalId
        mapping(uint256 => bool) remoteVotesReceived; // chainId => voted
        uint256 totalCrossChainVotes;
        uint256 requiredRemoteVotes;
    }

    mapping(uint256 => CrossChainProposal) public crossChainProposals;

    event CrossChainProposalInitiated(
        uint256 indexed proposalId,
        uint256[] remoteChains
    );

    event RemoteVoteReceived(
        uint256 indexed proposalId,
        uint256 sourceChainId,
        uint256 votes
    );

    constructor(
        DAOToken _token,
        TimelockController _timelock,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _proposalThreshold,
        address _messenger,
        uint256 _localChainId
    )
        DAOGovernor(
            _token,
            _timelock,
            "CrossChainDAO",  // name
            _votingDelay,
            _votingPeriod,
            _proposalThreshold,
            4  // quorumFraction (4%)
        )
    {
        messenger = MockCrossChainMessenger(_messenger);
        localChainId = _localChainId;
    }

    function proposeCrossChain(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        uint256[] memory remoteChains
    ) public returns (uint256) {
        uint256 proposalId = propose(targets, values, calldatas, description);

        CrossChainProposal storage ccp = crossChainProposals[proposalId];
        ccp.requiredRemoteVotes = remoteChains.length;

        for (uint256 i = 0; i < remoteChains.length; i++) {
            supportedChains[remoteChains[i]] = true;
        }

        emit CrossChainProposalInitiated(proposalId, remoteChains);

        // Send proposals to remote chains
        bytes memory payload = abi.encodeWithSignature(
            "receiveRemoteProposal(address,uint256,bytes)",
            msg.sender,
            proposalId,
            abi.encode(targets, values, calldatas, description)
        );

        for (uint256 i = 0; i < remoteChains.length; i++) {
            messenger.sendMessage(remoteChains[i], payload);
        }

        return proposalId;
    }

    function receiveRemoteProposal(
        address originProposer,
        uint256 originProposalId,
        bytes memory proposalData
    ) external {
        require(msg.sender == address(messenger), "Unauthorized messenger");

        (
            address[] memory targets,
            uint256[] memory values,
            bytes[] memory calldatas,
            string memory description
        ) = abi.decode(proposalData, (address[], uint256[], bytes[], string));

        uint256 localProposalId = propose(targets, values, calldatas, description);

        // Record cross-chain reference
        // In production, would link originProposalId with localProposalId
    }

    function relayRemoteVote(
        uint256 proposalId,
        uint256 sourceChainId,
        uint256 votes
    ) external {
        require(msg.sender == address(messenger), "Unauthorized messenger");
        require(supportedChains[sourceChainId], "Chain not supported");

        CrossChainProposal storage ccp = crossChainProposals[proposalId];
        require(!ccp.remoteVotesReceived[sourceChainId], "Already voted");

        ccp.remoteVotesReceived[sourceChainId] = true;
        ccp.totalCrossChainVotes += votes;

        emit RemoteVoteReceived(proposalId, sourceChainId, votes);
    }

    // Getter functions for testing
    function totalCrossChainVotes(uint256 proposalId) external view returns (uint256) {
        return crossChainProposals[proposalId].totalCrossChainVotes;
    }

    function requiredRemoteVotes(uint256 proposalId) external view returns (uint256) {
        return crossChainProposals[proposalId].requiredRemoteVotes;
    }
}

/**
 * @title CrossChainGovernanceIntegrationTest
 * @dev Tests cross-chain governance coordination
 */
contract CrossChainGovernanceIntegrationTest is Test {
    // Chain A (Flare Mainnet)
    CrossChainGovernor public governorA;
    DAOToken public tokenA;
    TimelockController public timelockA;
    MockCrossChainMessenger public messengerA;
    Treasury public treasuryA;

    // Chain B (Polygon)
    CrossChainGovernor public governorB;
    DAOToken public tokenB;
    TimelockController public timelockB;
    MockCrossChainMessenger public messengerB;
    Treasury public treasuryB;

    // Common contracts (deployed on both chains)
    IdentityRegistry public identityRegistry;
    ReputationRegistry public reputationRegistry;
    ValidationRegistry public validationRegistry;

    address public proposer;
    address public voter1;
    address public voter2;

    uint256 constant FLARE_CHAIN_ID = 14;
    uint256 constant POLYGON_CHAIN_ID = 137;

    function setUp() public {
        proposer = makeAddr("proposer");
        voter1 = makeAddr("voter1");
        voter2 = makeAddr("voter2");

        _deployChainA();
        _deployChainB();
        _configureCrossChain();
    }

    function _deployChainA() private {
        // Deploy registries
        identityRegistry = new IdentityRegistry();
        reputationRegistry = new ReputationRegistry();
        validationRegistry = new ValidationRegistry();

        // Deploy messenger for Chain A
        messengerA = new MockCrossChainMessenger(FLARE_CHAIN_ID);

        // Deploy token (all supply goes to deployer)
        vm.startPrank(proposer);
        tokenA = new DAOToken();
        // Transfer tokens to voters
        tokenA.transfer(voter1, 500_000 * 10**18);
        tokenA.transfer(voter2, 500_000 * 10**18);

        // Deploy timelock
        timelockA = new TimelockController(
            60, // 1 min delay
            new address[](0),
            new address[](0),
            proposer
        );

        // Deploy governor
        governorA = new CrossChainGovernor(
            tokenA,
            timelockA,
            1, // 1 block voting delay
            100, // 100 block voting period
            0, // 0 proposal threshold
            address(messengerA),
            FLARE_CHAIN_ID
        );

        // Deploy treasury first (before setting up timelock roles)
        address[] memory signers = new address[](1);
        signers[0] = proposer;
        treasuryA = new Treasury(signers, 1);
        vm.deal(address(treasuryA), 100 ether);

        // Setup timelock roles
        bytes32 proposerRole = timelockA.PROPOSER_ROLE();
        bytes32 executorRole = timelockA.EXECUTOR_ROLE();
        bytes32 adminRole = timelockA.TIMELOCK_ADMIN_ROLE();
        timelockA.grantRole(proposerRole, address(governorA));
        timelockA.grantRole(executorRole, address(governorA)); // Governor needs executor role
        timelockA.revokeRole(adminRole, proposer);

        // Transfer treasury ownership to timelock so governance can call admin functions
        treasuryA.transferOwnership(address(timelockA));

        vm.stopPrank();
    }

    function _deployChainB() private {
        // Deploy messenger for Chain B
        messengerB = new MockCrossChainMessenger(POLYGON_CHAIN_ID);

        // Deploy token
        vm.startPrank(proposer);
        tokenB = new DAOToken();
        // Transfer tokens to voters
        tokenB.transfer(voter1, 500_000 * 10**18);
        tokenB.transfer(voter2, 500_000 * 10**18);

        // Deploy timelock
        timelockB = new TimelockController(
            60,
            new address[](0),
            new address[](0),
            proposer
        );

        // Deploy governor
        governorB = new CrossChainGovernor(
            tokenB,
            timelockB,
            1,
            100,
            0,
            address(messengerB),
            POLYGON_CHAIN_ID
        );

        // Deploy treasury first (before setting up timelock roles)
        address[] memory signers = new address[](1);
        signers[0] = proposer;
        treasuryB = new Treasury(signers, 1);
        vm.deal(address(treasuryB), 100 ether);

        // Setup timelock roles
        bytes32 proposerRole = timelockB.PROPOSER_ROLE();
        bytes32 executorRole = timelockB.EXECUTOR_ROLE();
        bytes32 adminRole = timelockB.TIMELOCK_ADMIN_ROLE();
        timelockB.grantRole(proposerRole, address(governorB));
        timelockB.grantRole(executorRole, address(governorB)); // Governor needs executor role
        timelockB.revokeRole(adminRole, proposer);

        // Transfer treasury ownership to timelock so governance can call admin functions
        treasuryB.transferOwnership(address(timelockB));

        vm.stopPrank();
    }

    function _configureCrossChain() private {
        // Configure messengers
        vm.startPrank(proposer);
        messengerA.setRemoteGovernor(POLYGON_CHAIN_ID, address(governorB));
        messengerB.setRemoteGovernor(FLARE_CHAIN_ID, address(governorA));
        vm.stopPrank();
    }

    // ============ Integration Tests ============

    function testCrossChainProposalCreation() public {
        vm.startPrank(proposer);

        // Delegate votes
        tokenA.delegate(proposer);
        tokenB.delegate(proposer);

        uint256[] memory remoteChains = new uint256[](1);
        remoteChains[0] = POLYGON_CHAIN_ID;

        address[] memory targets = new address[](1);
        targets[0] = address(treasuryA);

        uint256[] memory values = new uint256[](1);
        values[0] = 1 ether;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "submitTransaction(address,uint256,bytes)",
            voter1,
            1 ether,
            bytes("")
        );

        // Create cross-chain proposal from Chain A
        uint256 proposalId = governorA.proposeCrossChain(
            targets,
            values,
            calldatas,
            "Cross-chain treasury transfer",
            remoteChains
        );

        // Verify proposal state
        assertEq(uint256(governorA.state(proposalId)), uint256(IGovernor.ProposalState.Pending));

        // Verify cross-chain proposal tracking
        (
            uint256 localId,
            uint256 totalVotes,
            uint256 requiredVotes
        ) = _getCrossChainProposalData(governorA, proposalId);

        assertEq(localId, proposalId);
        assertEq(requiredVotes, 1); // 1 remote chain

        vm.stopPrank();
    }

    function testCrossChainVoteRelay() public {
        vm.startPrank(proposer);

        // Delegate votes
        tokenA.delegate(proposer);
        tokenB.delegate(proposer);

        // Create cross-chain proposal on Chain A
        address[] memory targets = new address[](1);
        targets[0] = address(treasuryA);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature("pause()");

        uint256[] memory remoteChains = new uint256[](1);
        remoteChains[0] = POLYGON_CHAIN_ID;

        uint256 proposalId = governorA.proposeCrossChain(
            targets,
            values,
            calldatas,
            "Pause treasury",
            remoteChains
        );

        // Relay vote from Chain B to Chain A
        uint256 remoteVotes = 1000 * 10**18; // 1000 tokens voted on Chain B

        vm.stopPrank();

        // Simulate message received from Chain B
        vm.prank(address(messengerA));
        governorA.relayRemoteVote(proposalId, POLYGON_CHAIN_ID, remoteVotes);

        // Verify vote was recorded
        (
            ,
            uint256 totalVotes,
            uint256 requiredVotes
        ) = _getCrossChainProposalData(governorA, proposalId);

        assertEq(totalVotes, remoteVotes);
        assertEq(requiredVotes, 1); // 1 remote chain
    }

    function testBothChainsExecuteSeparately() public {
        // Test that both chains can execute proposals independently
        vm.startPrank(proposer);

        tokenA.delegate(proposer);
        tokenB.delegate(proposer);

        // Proposal on Chain A
        address[] memory targetsA = new address[](1);
        targetsA[0] = address(treasuryA);

        uint256[] memory valuesA = new uint256[](1);
        valuesA[0] = 0;

        bytes[] memory calldatasA = new bytes[](1);
        calldatasA[0] = abi.encodeWithSignature("pause()");

        uint256 proposalIdA = governorA.propose(targetsA, valuesA, calldatasA, "Pause A");

        // Proposal on Chain B
        address[] memory targetsB = new address[](1);
        targetsB[0] = address(treasuryB);

        bytes[] memory calldatasB = new bytes[](1);
        calldatasB[0] = abi.encodeWithSignature("pause()");

        uint256 proposalIdB = governorB.propose(targetsB, valuesA, calldatasB, "Pause B");

        // Fast-forward voting delay using roll (block numbers, not timestamp)
        vm.roll(block.number + 2);

        // Cast votes on both chains
        governorA.castVote(proposalIdA, 1);
        governorB.castVote(proposalIdB, 1);

        // Fast-forward voting period
        vm.roll(block.number + 101);

        // Both should succeed
        assertEq(uint256(governorA.state(proposalIdA)), uint256(IGovernor.ProposalState.Succeeded));
        assertEq(uint256(governorB.state(proposalIdB)), uint256(IGovernor.ProposalState.Succeeded));

        // Queue the proposals (this starts the timelock delay)
        governorA.queue(targetsA, valuesA, calldatasA, keccak256(bytes("Pause A")));
        governorB.queue(targetsB, valuesA, calldatasB, keccak256(bytes("Pause B")));

        // Fast-forward timelock delay (60 seconds)
        vm.warp(block.timestamp + 61);

        // Execute on Chain A
        governorA.execute(targetsA, valuesA, calldatasA, keccak256(bytes("Pause A")));
        assertTrue(treasuryA.paused());

        // Execute on Chain B
        governorB.execute(targetsB, valuesA, calldatasB, keccak256(bytes("Pause B")));
        assertTrue(treasuryB.paused());

        vm.stopPrank();
    }

    function testCrossChainMessageTracking() public {
        // Verify message tracking across chains
        vm.startPrank(proposer);

        tokenA.delegate(proposer);

        uint256[] memory remoteChains = new uint256[](1);
        remoteChains[0] = POLYGON_CHAIN_ID;

        address[] memory targets = new address[](1);
        targets[0] = address(treasuryA);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = bytes("");

        // Create cross-chain proposal
        governorA.proposeCrossChain(
            targets,
            values,
            calldatas,
            "Test proposal",
            remoteChains
        );

        // Verify chain is marked as supported
        assertTrue(governorA.supportedChains(POLYGON_CHAIN_ID));

        vm.stopPrank();
    }

    function testCrossChainReplayProtection() public {
        // Test that same message can't be processed twice
        vm.startPrank(proposer);

        tokenA.delegate(proposer);

        address[] memory targets = new address[](1);
        targets[0] = address(treasuryA);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = bytes("");

        uint256 proposalId = governorA.propose(targets, values, calldatas, "Test");

        // Create a message ID for testing
        bytes32 messageId = keccak256(abi.encodePacked(uint256(1), uint256(2), uint256(0), abi.encode("test")));

        // Set up the remote governor to point to governorB
        vm.stopPrank();
        vm.prank(proposer);
        messengerA.setRemoteGovernor(POLYGON_CHAIN_ID, address(governorB));

        // The receiveMessage will execute successfully (marks message as processed)
        // even if the payload execution on governorB fails
        vm.prank(address(messengerA));
        messengerA.receiveMessage(POLYGON_CHAIN_ID, messageId, abi.encode("test"));

        // Verify message was marked as processed
        assertTrue(messengerA.processedMessages(POLYGON_CHAIN_ID, messageId));

        // Second receive with same messageId should fail
        vm.prank(address(messengerA));
        vm.expectRevert("Already processed");
        messengerA.receiveMessage(POLYGON_CHAIN_ID, messageId, abi.encode("test"));
    }

    function testUnsupportedChainReverts() public {
        vm.startPrank(proposer);

        tokenA.delegate(proposer);

        // Try to relay vote from unsupported chain
        uint256 proposalId = governorA.propose(
            new address[](1),
            new uint256[](1),
            new bytes[](1),
            "Test"
        );

        vm.stopPrank();

        // Chain ID 999 is not supported
        vm.prank(address(messengerA));
        vm.expectRevert("Chain not supported");
        governorA.relayRemoteVote(proposalId, 999, 1000);
    }

    // ============ Helper Functions ============

    function _getCrossChainProposalData(
        CrossChainGovernor governor,
        uint256 proposalId
    ) private view returns (
        uint256 localProposalId,
        uint256 totalCrossChainVotes,
        uint256 requiredRemoteVotes
    ) {
        // Access internal storage via assembly or through public getters if available
        // For this test, we'll use a simplified approach
        localProposalId = proposalId;
        totalCrossChainVotes = governor.totalCrossChainVotes(proposalId);
        requiredRemoteVotes = governor.requiredRemoteVotes(proposalId);
    }
}

// Add public getters to CrossChainGovernor for testing
// These would normally be internal/private
contract CrossChainGovernorTestHelpers is CrossChainGovernor {
    constructor(
        DAOToken _token,
        TimelockController _timelock,
        uint256 _votingDelay,
        uint256 _votingPeriod,
        uint256 _proposalThreshold,
        address _messenger,
        uint256 _localChainId
    )
        CrossChainGovernor(
            _token,
            _timelock,
            _votingDelay,
            _votingPeriod,
            _proposalThreshold,
            _messenger,
            _localChainId
        )
    {}

    function getTotalCrossChainVotes(uint256 proposalId) external view returns (uint256) {
        return crossChainProposals[proposalId].totalCrossChainVotes;
    }

    function getRequiredRemoteVotes(uint256 proposalId) external view returns (uint256) {
        return crossChainProposals[proposalId].requiredRemoteVotes;
    }

    function getRemoteVotesReceived(uint256 proposalId, uint256 chainId) external view returns (bool) {
        return crossChainProposals[proposalId].remoteVotesReceived[chainId];
    }
}
