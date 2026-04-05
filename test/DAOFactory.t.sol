// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import {DAOFactory} from "contracts/dao-maker/DAOFactory.sol";
import {IDAOFactory} from "contracts/interfaces/IDAOFactory.sol";
import {TokenDeployer} from "contracts/dao-maker/TokenDeployer.sol";
import {TimelockDeployer} from "contracts/dao-maker/TimelockDeployer.sol";
import {GovernorDeployer} from "contracts/dao-maker/GovernorDeployer.sol";
import {GovernanceTemplateFactory} from "contracts/dao-maker/GovernanceTemplateFactory.sol";
import {DAOTokenV2} from "contracts/dao-maker/DAOTokenV2.sol";
import {DAOGovernor} from "contracts/governance/DAOGovernor.sol";
import {Treasury} from "contracts/treasury/Treasury.sol";
import {RevenueSharing} from "contracts/dao-maker/RevenueSharing.sol";
import {PayoutDistributor} from "contracts/dao-maker/PayoutDistributor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DAOFactoryTest is Test {
    DAOFactory public factory;
    TokenDeployer public tokenDeployer;
    TimelockDeployer public timelockDeployer;
    GovernorDeployer public governorDeployer;
    GovernanceTemplateFactory public templateFactory;

    address public owner;
    address public daoCreator;
    address public signer1;
    address public signer2;

    function setUp() public {
        owner = address(this);
        daoCreator = makeAddr("daoCreator");
        signer1 = makeAddr("signer1");
        signer2 = makeAddr("signer2");

        tokenDeployer = new TokenDeployer();
        timelockDeployer = new TimelockDeployer();
        governorDeployer = new GovernorDeployer();
        templateFactory = new GovernanceTemplateFactory();

        // Use mock registries (just non-zero addresses)
        address mockIdentity = makeAddr("identity");
        address mockReputation = makeAddr("reputation");
        address mockValidation = makeAddr("validation");

        factory = new DAOFactory(
            mockIdentity,
            mockReputation,
            mockValidation,
            tokenDeployer,
            timelockDeployer,
            governorDeployer,
            templateFactory
        );
    }

    function testCreateDAO() public {
        address[] memory signers = new address[](2);
        signers[0] = signer1;
        signers[1] = signer2;

        IDAOFactory.DAOParams memory params = IDAOFactory.DAOParams({
            name: "TestDAO",
            symbol: "TDAO",
            initialSupply: 1_000_000 * 10**18,
            votingDelay: 1,
            votingPeriod: 100,
            proposalThreshold: 0,
            quorumFraction: 4,
            timelockDelay: 0,
            signers: signers,
            treasuryThreshold: 2
        });

        vm.prank(daoCreator);
        IDAOFactory.DAODeployment memory deployment = factory.createDAO(params);

        // Verify all addresses are set
        assertTrue(deployment.token != address(0));
        assertTrue(deployment.governor != address(0));
        assertTrue(deployment.timelock != address(0));
        assertTrue(deployment.treasury != address(0));
        assertEq(deployment.creator, daoCreator);

        // Verify token
        DAOTokenV2 token = DAOTokenV2(deployment.token);
        assertEq(token.name(), "TestDAO");
        assertEq(token.symbol(), "TDAO");
        assertEq(token.balanceOf(daoCreator), 1_000_000 * 10**18);

        // Verify governor
        DAOGovernor governor = DAOGovernor(payable(deployment.governor));
        assertEq(governor.votingDelay(), 1);
        assertEq(governor.votingPeriod(), 100);
        assertEq(governor.proposalThreshold(), 0);

        // Verify treasury
        Treasury treasury = Treasury(payable(deployment.treasury));
        assertEq(treasury.getThreshold(), 2);
        assertEq(treasury.getSigners().length, 2);
        assertTrue(treasury.isSigner(signer1));
        assertTrue(treasury.isSigner(signer2));

        // Verify DAO is stored
        assertEq(factory.getDAOCount(), 1);
        IDAOFactory.DAODeployment memory stored = factory.getDAO("TestDAO");
        assertEq(stored.token, deployment.token);
    }

    function testCreateDAOFromTemplate() public {
        address[] memory signers = new address[](2);
        signers[0] = signer1;
        signers[1] = signer2;

        vm.prank(daoCreator);
        IDAOFactory.DAODeployment memory deployment = factory.createDAOFromTemplate(
            "BalancedDAO",
            "BDAO",
            1_000_000 * 10**18,
            "Balanced",
            signers,
            2
        );

        assertTrue(deployment.token != address(0));

        // Verify balanced template was applied
        DAOGovernor governor = DAOGovernor(payable(deployment.governor));
        assertEq(governor.votingDelay(), 3600);
        assertEq(governor.votingPeriod(), 36000);
    }

    function testRevertEmptyName() public {
        address[] memory signers = new address[](1);
        signers[0] = signer1;

        IDAOFactory.DAOParams memory params = IDAOFactory.DAOParams({
            name: "",
            symbol: "TDAO",
            initialSupply: 1_000_000 * 10**18,
            votingDelay: 1,
            votingPeriod: 100,
            proposalThreshold: 0,
            quorumFraction: 4,
            timelockDelay: 0,
            signers: signers,
            treasuryThreshold: 1
        });

        vm.prank(daoCreator);
        vm.expectRevert(DAOFactory.EmptyName.selector);
        factory.createDAO(params);
    }

    function testRevertDuplicateName() public {
        address[] memory signers = new address[](1);
        signers[0] = signer1;

        IDAOFactory.DAOParams memory params = IDAOFactory.DAOParams({
            name: "DuplicateDAO",
            symbol: "DDAO",
            initialSupply: 1_000_000 * 10**18,
            votingDelay: 1,
            votingPeriod: 100,
            proposalThreshold: 0,
            quorumFraction: 4,
            timelockDelay: 0,
            signers: signers,
            treasuryThreshold: 1
        });

        vm.prank(daoCreator);
        factory.createDAO(params);

        vm.prank(daoCreator);
        vm.expectRevert(
            abi.encodeWithSelector(DAOFactory.DAOAlreadyExists.selector, "DuplicateDAO")
        );
        factory.createDAO(params);
    }

    function testRevertNonExistentTemplate() public {
        address[] memory signers = new address[](1);
        signers[0] = signer1;

        vm.prank(daoCreator);
        vm.expectRevert(
            abi.encodeWithSelector(DAOFactory.TemplateNotFound.selector, "NonExistent")
        );
        factory.createDAOFromTemplate(
            "BadDAO",
            "BDAO",
            1_000_000 * 10**18,
            "NonExistent",
            signers,
            1
        );
    }

    function testMultipleDAOs() public {
        address[] memory signers = new address[](1);
        signers[0] = signer1;

        IDAOFactory.DAOParams memory params1 = IDAOFactory.DAOParams({
            name: "DAO1",
            symbol: "D1",
            initialSupply: 100 * 10**18,
            votingDelay: 1,
            votingPeriod: 100,
            proposalThreshold: 0,
            quorumFraction: 4,
            timelockDelay: 0,
            signers: signers,
            treasuryThreshold: 1
        });

        IDAOFactory.DAOParams memory params2 = IDAOFactory.DAOParams({
            name: "DAO2",
            symbol: "D2",
            initialSupply: 200 * 10**18,
            votingDelay: 1,
            votingPeriod: 200,
            proposalThreshold: 0,
            quorumFraction: 4,
            timelockDelay: 0,
            signers: signers,
            treasuryThreshold: 1
        });

        vm.prank(daoCreator);
        factory.createDAO(params1);

        vm.prank(daoCreator);
        factory.createDAO(params2);

        assertEq(factory.getDAOCount(), 2);
        assertNotEq(factory.getDAO("DAO1").token, factory.getDAO("DAO2").token);
    }

    function testGetDAONames() public {
        address[] memory signers = new address[](1);
        signers[0] = signer1;

        IDAOFactory.DAOParams memory params = IDAOFactory.DAOParams({
            name: "NamedDAO",
            symbol: "NDAO",
            initialSupply: 100 * 10**18,
            votingDelay: 1,
            votingPeriod: 100,
            proposalThreshold: 0,
            quorumFraction: 4,
            timelockDelay: 0,
            signers: signers,
            treasuryThreshold: 1
        });

        vm.prank(daoCreator);
        factory.createDAO(params);

        string[] memory names = factory.getDAONames();
        assertEq(names.length, 1);
        assertEq(names[0], "NamedDAO");
    }

    function testRevenueSharingOwnership() public {
        address[] memory signers = new address[](1);
        signers[0] = signer1;

        IDAOFactory.DAOParams memory params = IDAOFactory.DAOParams({
            name: "RevDAO",
            symbol: "RDAO",
            initialSupply: 100 * 10**18,
            votingDelay: 1,
            votingPeriod: 100,
            proposalThreshold: 0,
            quorumFraction: 4,
            timelockDelay: 0,
            signers: signers,
            treasuryThreshold: 1
        });

        vm.prank(daoCreator);
        IDAOFactory.DAODeployment memory deployment = factory.createDAO(params);

        // RevenueSharing should be owned by timelock, not factory
        // (can verify by checking that factory can't call owner functions)
    }
}
