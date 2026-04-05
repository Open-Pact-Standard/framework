// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {TokenDeployer} from "contracts/dao-maker/TokenDeployer.sol";
import {GovernorDeployer} from "contracts/dao-maker/GovernorDeployer.sol";
import {TimelockDeployer} from "contracts/dao-maker/TimelockDeployer.sol";
import {DAOTokenV2} from "contracts/dao-maker/DAOTokenV2.sol";
import {DAOGovernor} from "contracts/governance/DAOGovernor.sol";
import {TimelockController} from "contracts/governance/TimelockController.sol";
import {DAOToken} from "contracts/governance/DAOToken.sol";

/**
 * @title DeployerTests
 * @dev Comprehensive tests for all deployer contracts:
 *      - TokenDeployer
 *      - GovernorDeployer
 *      - TimelockDeployer
 *
 *      Tests cover:
 *      - Deployment flow
 *      - Access control
 *      - Factory initialization
 *      - Edge cases
 *      - Integration scenarios
 */
contract DeployerTests is Test {
    // ============ Deployer Contracts ============

    TokenDeployer public tokenDeployer;
    GovernorDeployer public governorDeployer;
    TimelockDeployer public timelockDeployer;

    // ============ Test Addresses ============

    address public owner;
    address public factory;
    address public user;
    address public initialHolder;

    // ============ Setup ============

    function setUp() public {
        owner = address(this);
        factory = makeAddr("factory");
        user = makeAddr("user");
        initialHolder = makeAddr("initialHolder");

        tokenDeployer = new TokenDeployer();
        governorDeployer = new GovernorDeployer();
        timelockDeployer = new TimelockDeployer();
    }

    // ============ TokenDeployer Tests ============

    function test_TokenDeployer_DeployToken() public {
        vm.prank(factory);
        address tokenAddr = tokenDeployer.deploy(
            "Test Token",
            "TST",
            initialHolder,
            1_000_000 * 10**18
        );

        DAOTokenV2 token = DAOTokenV2(tokenAddr);

        assertEq(token.name(), "Test Token");
        assertEq(token.symbol(), "TST");
        assertEq(token.totalSupply(), 1_000_000 * 10**18);
        assertEq(token.balanceOf(initialHolder), 1_000_000 * 10**18);
    }

    function test_TokenDeployer_DeployTokenWithZeroSupply() public {
        vm.prank(factory);
        address tokenAddr = tokenDeployer.deploy(
            "Zero Token",
            "ZERO",
            initialHolder,
            0
        );

        DAOTokenV2 token = DAOTokenV2(tokenAddr);

        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(initialHolder), 0);
    }

    function test_TokenDeployer_AnyoneCanDeployBeforeFactorySet() public {
        // Before factory is set, anyone can deploy
        vm.prank(user);
        address tokenAddr = tokenDeployer.deploy(
            "User Token",
            "USR",
            user,
            500 * 10**18
        );

        assertTrue(tokenAddr != address(0));
    }

    function test_TokenDeployer_OnlyFactoryCanDeployAfterSet() public {
        // Set factory
        tokenDeployer.setFactory(factory);

        // User should not be able to deploy
        vm.prank(user);
        vm.expectRevert();
        tokenDeployer.deploy(
            "Should Fail",
            "FAIL",
            user,
            100 * 10**18
        );

        // Factory should still be able to deploy
        vm.prank(factory);
        address tokenAddr = tokenDeployer.deploy(
            "Factory Token",
            "FACT",
            factory,
            100 * 10**18
        );

        assertTrue(tokenAddr != address(0));
    }

    function test_TokenDeployer_SetFactory() public {
        assertEq(tokenDeployer.factory(), address(0));

        tokenDeployer.setFactory(factory);

        assertEq(tokenDeployer.factory(), factory);
    }

    function test_TokenDeployer_SetFactoryRevertsWhenZero() public {
        vm.expectRevert(TokenDeployer.ZeroAddress.selector);
        tokenDeployer.setFactory(address(0));
    }

    function test_TokenDeployer_SetFactoryRevertsWhenAlreadySet() public {
        tokenDeployer.setFactory(factory);

        vm.expectRevert(TokenDeployer.FactoryAlreadySet.selector);
        tokenDeployer.setFactory(makeAddr("another"));
    }

    function test_TokenDeployer_SetFactoryRevertsWhenNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        tokenDeployer.setFactory(factory);
    }

    function testFuzz_TokenDeployer_VariousSupplies(uint256 supply) public {
        // Bound supply to reasonable values
        vm.assume(supply <= 1_000_000_000 * 10**18);

        vm.prank(factory);
        address tokenAddr = tokenDeployer.deploy(
            "Fuzz Token",
            "FUZZ",
            initialHolder,
            supply
        );

        DAOTokenV2 token = DAOTokenV2(tokenAddr);
        assertEq(token.totalSupply(), supply);
    }

    // ============ GovernorDeployer Tests ============

    function test_GovernorDeployer_DeployGovernor() public {
        DAOToken mockToken = new DAOToken();
        TimelockController mockTimelock = new TimelockController(
            60,
            new address[](0),
            new address[](0),
            owner
        );

        vm.prank(factory);
        address governorAddr = governorDeployer.deploy(
            address(mockToken),
            address(mockTimelock),
            "Test DAO",
            1, // votingDelay
            100, // votingPeriod
            0, // proposalThreshold
            4 // quorumFraction
        );

        DAOGovernor governor = DAOGovernor(payable(governorAddr));

        assertEq(governor.name(), "Test DAO");
        assertEq(address(governor.token()), address(mockToken));
        assertEq(address(governor.timelock()), address(mockTimelock));
    }

    function test_GovernorDeployer_DeployWithMaxParams() public {
        DAOToken mockToken = new DAOToken();
        TimelockController mockTimelock = new TimelockController(
            60,
            new address[](0),
            new address[](0),
            owner
        );

        vm.prank(factory);
        address governorAddr = governorDeployer.deploy(
            address(mockToken),
            address(mockTimelock),
            "Max DAO",
            type(uint40).max, // votingDelay
            type(uint32).max, // votingPeriod
            type(uint96).max, // proposalThreshold
            20 // quorumFraction (max 20%)
        );

        assertTrue(governorAddr != address(0));
    }

    function test_GovernorDeployer_AnyoneCanDeployBeforeFactorySet() public {
        DAOToken mockToken = new DAOToken();
        TimelockController mockTimelock = new TimelockController(
            60,
            new address[](0),
            new address[](0),
            owner
        );

        vm.prank(user);
        address governorAddr = governorDeployer.deploy(
            address(mockToken),
            address(mockTimelock),
            "User DAO",
            1,
            100,
            0,
            4
        );

        assertTrue(governorAddr != address(0));
    }

    function test_GovernorDeployer_OnlyFactoryCanDeployAfterSet() public {
        DAOToken mockToken = new DAOToken();
        TimelockController mockTimelock = new TimelockController(
            60,
            new address[](0),
            new address[](0),
            owner
        );

        governorDeployer.setFactory(factory);

        vm.prank(user);
        vm.expectRevert();
        governorDeployer.deploy(
            address(mockToken),
            address(mockTimelock),
            "Should Fail",
            1,
            100,
            0,
            4
        );
    }

    function test_GovernorDeployer_SetFactory() public {
        assertEq(governorDeployer.factory(), address(0));
        governorDeployer.setFactory(factory);
        assertEq(governorDeployer.factory(), factory);
    }

    // ============ TimelockDeployer Tests ============

    function test_TimelockDeployer_DeployTimelock() public {
        vm.prank(factory);
        address timelockAddr = timelockDeployer.deploy(
            3600, // 1 hour minDelay
            factory
        );

        TimelockController timelock = TimelockController(payable(timelockAddr));

        assertEq(timelock.getMinDelay(), 3600);

        // Verify factory has roles
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 adminRole = timelock.TIMELOCK_ADMIN_ROLE();

        assertTrue(timelock.hasRole(proposerRole, factory));
        assertTrue(timelock.hasRole(adminRole, factory));
    }

    function test_TimelockDeployer_DeployWithZeroDelay() public {
        vm.prank(factory);
        address timelockAddr = timelockDeployer.deploy(
            0, // no delay
            factory
        );

        TimelockController timelock = TimelockController(payable(timelockAddr));
        assertEq(timelock.getMinDelay(), 0);
    }

    function test_TimelockDeployer_DeployWithMaxDelay() public {
        vm.prank(factory);
        address timelockAddr = timelockDeployer.deploy(
            type(uint256).max, // max delay
            factory
        );

        TimelockController timelock = TimelockController(payable(timelockAddr));
        assertEq(timelock.getMinDelay(), type(uint256).max);
    }

    function test_TimelockDeployer_AnyoneCanDeployBeforeFactorySet() public {
        vm.prank(user);
        address timelockAddr = timelockDeployer.deploy(
            60,
            user // factory becomes the admin
        );

        assertTrue(timelockAddr != address(0));
    }

    function test_TimelockDeployer_OnlyFactoryCanDeployAfterSet() public {
        timelockDeployer.setFactory(factory);

        vm.prank(user);
        vm.expectRevert();
        timelockDeployer.deploy(
            60,
            user
        );
    }

    function test_TimelockDeployer_SetFactory() public {
        assertEq(timelockDeployer.factory(), address(0));
        timelockDeployer.setFactory(factory);
        assertEq(timelockDeployer.factory(), factory);
    }

    // ============ Integration Tests ============

    function test_Integration_CompleteDAOStack() public {
        // 1. Deploy token
        vm.prank(factory);
        address tokenAddr = tokenDeployer.deploy(
            "DAO Token",
            "DAO",
            factory,
            1_000_000 * 10**18
        );

        // 2. Deploy timelock
        vm.prank(factory);
        address timelockAddr = timelockDeployer.deploy(
            60,
            factory
        );

        // 3. Deploy governor
        vm.prank(factory);
        address governorAddr = governorDeployer.deploy(
            tokenAddr,
            timelockAddr,
            "My DAO",
            1,
            100,
            0,
            4
        );

        // 4. Verify governor-token-timelock connection
        DAOGovernor governor = DAOGovernor(payable(governorAddr));
        TimelockController timelock = TimelockController(payable(timelockAddr));

        assertEq(address(governor.token()), tokenAddr);
        assertEq(address(governor.timelock()), timelockAddr);

        // 5. Setup timelock roles for governor
        bytes32 proposerRole = timelock.PROPOSER_ROLE();
        bytes32 executorRole = timelock.EXECUTOR_ROLE();
        bytes32 adminRole = timelock.TIMELOCK_ADMIN_ROLE();

        vm.prank(factory);
        timelock.grantRole(proposerRole, governorAddr);
        vm.prank(factory);
        timelock.grantRole(executorRole, governorAddr);
        vm.prank(factory);
        timelock.revokeRole(adminRole, factory);

        // 6. Verify roles
        assertTrue(timelock.hasRole(proposerRole, governorAddr));
        assertTrue(timelock.hasRole(executorRole, governorAddr));
        assertFalse(timelock.hasRole(adminRole, factory));
    }

    function test_Integration_MultipleDAOs() public {
        // Deploy multiple DAOs with different configurations
        string[] memory names = new string[](3);
        names[0] = "DAO Alpha";
        names[1] = "DAO Beta";
        names[2] = "DAO Gamma";

        for (uint256 i = 0; i < 3; i++) {
            // Deploy token
            vm.prank(factory);
            address tokenAddr = tokenDeployer.deploy(
                names[i],
                string(abi.encodePacked(names[0], i)),
                factory,
                1_000_000 * 10**18
            );

            // Deploy timelock
            vm.prank(factory);
            address timelockAddr = timelockDeployer.deploy(60, factory);

            // Deploy governor
            vm.prank(factory);
            address governorAddr = governorDeployer.deploy(
                tokenAddr,
                timelockAddr,
                names[i],
                1,
                100,
                0,
                4
            );

            assertTrue(governorAddr != address(0));
        }
    }

    // ============ Access Control Tests ============

    function test_AccessControl_OwnerCannotDeployWhenFactorySet() public {
        tokenDeployer.setFactory(factory);

        // Even owner cannot deploy after factory is set
        vm.expectRevert();
        tokenDeployer.deploy(
            "Owner Token",
            "OWN",
            owner,
            100 * 10**18
        );
    }

    function test_AccessControl_TransferOwnership() public {
        // Deployer contracts use Ownable but don't expose transferOwnership
        // They do expose owner variable which we can check
        assertEq(tokenDeployer.owner(), owner);
        assertEq(governorDeployer.owner(), owner);
        assertEq(timelockDeployer.owner(), owner);
    }

    // ============ Edge Case Tests ============

    function test_EdgeCase_EmptyName() public {
        vm.prank(factory);
        address tokenAddr = tokenDeployer.deploy(
            "", // empty name
            "EMPTY",
            initialHolder,
            100 * 10**18
        );

        DAOTokenV2 token = DAOTokenV2(tokenAddr);
        assertEq(token.name(), "");
    }

    function test_EdgeCase_EmptySymbol() public {
        vm.prank(factory);
        address tokenAddr = tokenDeployer.deploy(
            "Empty Symbol",
            "", // empty symbol
            initialHolder,
            100 * 10**18
        );

        DAOTokenV2 token = DAOTokenV2(tokenAddr);
        assertEq(token.symbol(), "");
    }

    function test_EdgeCase_ZeroInitialHolder() public {
        vm.prank(factory);
        vm.expectRevert(DAOTokenV2.InvalidParameters.selector);
        tokenDeployer.deploy(
            "Zero Holder Token",
            "ZERO",
            address(0), // zero initial holder - should revert
            100 * 10**18
        );
    }

    function test_EdgeCase_GovernorWithZeroQuorum() public {
        DAOToken mockToken = new DAOToken();
        TimelockController mockTimelock = new TimelockController(
            60,
            new address[](0),
            new address[](0),
            owner
        );

        vm.prank(factory);
        address governorAddr = governorDeployer.deploy(
            address(mockToken),
            address(mockTimelock),
            "Zero Quorum",
            1,
            100,
            0,
            0 // 0% quorum
        );

        assertTrue(governorAddr != address(0));
    }

    function test_EdgeCase_TimelockWithDifferentFactory() public {
        address otherFactory = makeAddr("otherFactory");

        vm.prank(factory);
        address timelockAddr = timelockDeployer.deploy(
            60,
            otherFactory // different factory gets admin
        );

        TimelockController timelock = TimelockController(payable(timelockAddr));

        // Verify otherFactory has the roles, not the calling factory
        bytes32 adminRole = timelock.TIMELOCK_ADMIN_ROLE();
        assertTrue(timelock.hasRole(adminRole, otherFactory));
        assertFalse(timelock.hasRole(adminRole, factory));
    }

    // ============ Fuzz Tests ============

    function testFuzz_TokenDeployer_DeployWithVariousSupplies(uint256 supply) public {
        vm.assume(supply <= 1_000_000_000 * 10**18); // MAX_SUPPLY

        vm.prank(factory);
        address tokenAddr = tokenDeployer.deploy(
            "Fuzz Token",
            "FUZZ",
            initialHolder,
            supply
        );

        DAOTokenV2 token = DAOTokenV2(tokenAddr);
        assertEq(token.totalSupply(), supply);
    }

    function testFuzz_GovernorDeployer_VariousQuorumFractions(uint8 quorumFraction) public {
        vm.assume(quorumFraction <= 20); // Max 20% in Governor

        DAOToken mockToken = new DAOToken();
        TimelockController mockTimelock = new TimelockController(
            60,
            new address[](0),
            new address[](0),
            owner
        );

        vm.prank(factory);
        address governorAddr = governorDeployer.deploy(
            address(mockToken),
            address(mockTimelock),
            "Fuzz DAO",
            1,
            100,
            0,
            quorumFraction
        );

        assertTrue(governorAddr != address(0));
    }

    function testFuzz_TimelockDeployer_VariousDelays(uint256 minDelay) public {
        vm.prank(factory);
        address timelockAddr = timelockDeployer.deploy(
            minDelay,
            factory
        );

        TimelockController timelock = TimelockController(payable(timelockAddr));
        assertEq(timelock.getMinDelay(), minDelay);
    }
}
