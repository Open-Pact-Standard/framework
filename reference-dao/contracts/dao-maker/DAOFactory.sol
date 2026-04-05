// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./TokenDeployer.sol";
import "./TimelockDeployer.sol";
import "./GovernorDeployer.sol";
import "./RevenueSharing.sol";
import "./PayoutDistributor.sol";
import "./GovernanceTemplateFactory.sol";
import {DAOTimelockController as DAOTimelock} from "../governance/TimelockController.sol";
import "../treasury/Treasury.sol";
import "../interfaces/IDAOFactory.sol";
import "../interfaces/IDAOToken.sol";
import "../interfaces/IReputationRegistry.sol";
import "../interfaces/IAgentRegistry.sol";
import "../interfaces/IGovernanceTemplateFactory.sol";

/**
 * @title DAOFactory
 * @dev Deploys complete DAO stacks in one transaction.
 *      Uses specialized deployer contracts to stay within EVM size limits.
 */
contract DAOFactory is IDAOFactory, Ownable, ReentrancyGuard {
    mapping(string => DAODeployment) private _daos;
    string[] private _daoNames;

    address public immutable identityRegistry;
    address public immutable reputationRegistry;
    address public immutable validationRegistry;

    TokenDeployer public immutable tokenDeployer;
    TimelockDeployer public immutable timelockDeployer;
    GovernorDeployer public immutable governorDeployer;
    GovernanceTemplateFactory public templateFactory;

    error DAOAlreadyExists(string name);
    error EmptyName();
    error ZeroAddress();
    error TemplateNotFound(string name);

    constructor(
        address identityRegistry_,
        address reputationRegistry_,
        address validationRegistry_,
        TokenDeployer tokenDeployer_,
        TimelockDeployer timelockDeployer_,
        GovernorDeployer governorDeployer_,
        GovernanceTemplateFactory templateFactory_
    ) Ownable() {
        if (
            identityRegistry_ == address(0) ||
            reputationRegistry_ == address(0) ||
            validationRegistry_ == address(0) ||
            address(templateFactory_) == address(0)
        ) {
            revert ZeroAddress();
        }
        identityRegistry = identityRegistry_;
        reputationRegistry = reputationRegistry_;
        validationRegistry = validationRegistry_;
        tokenDeployer = tokenDeployer_;
        timelockDeployer = timelockDeployer_;
        governorDeployer = governorDeployer_;
        templateFactory = templateFactory_;
    }

    /**
     * @inheritdoc IDAOFactory
     */
    function createDAO(DAOParams calldata params) external override nonReentrant returns (DAODeployment memory) {
        return _deployDAO(params, msg.sender);
    }

    /**
     * @dev Create a DAO using a predefined governance template.
     */
    function createDAOFromTemplate(
        string calldata name,
        string calldata symbol,
        uint256 initialSupply,
        string calldata templateName,
        address[] calldata signers,
        uint256 treasuryThreshold
    ) external nonReentrant returns (DAODeployment memory) {
        if (!templateFactory.templateExists(templateName)) {
            revert TemplateNotFound(templateName);
        }

        IGovernanceTemplateFactory.GovernanceConfig memory config = templateFactory.getTemplate(
            templateName
        );

        DAOParams memory params = DAOParams({
            name: name,
            symbol: symbol,
            initialSupply: initialSupply,
            votingDelay: config.votingDelay,
            votingPeriod: config.votingPeriod,
            proposalThreshold: config.proposalThreshold,
            quorumFraction: config.quorumFraction,
            timelockDelay: config.timelockDelay,
            signers: signers,
            treasuryThreshold: treasuryThreshold
        });

        return _deployDAO(params, msg.sender);
    }

    /**
     * @inheritdoc IDAOFactory
     */
    function getDAO(string memory name) external view override returns (DAODeployment memory) {
        return _daos[name];
    }

    /**
     * @inheritdoc IDAOFactory
     */
    function getDAOCount() external view override returns (uint256) {
        return _daoNames.length;
    }

    /**
     * @dev Get all DAO names.
     */
    function getDAONames() external view returns (string[] memory) {
        return _daoNames;
    }

    function _deployDAO(
        DAOParams memory params,
        address creator
    ) internal returns (DAODeployment memory deployment) {
        if (bytes(params.name).length == 0) {
            revert EmptyName();
        }
        if (_daos[params.name].creator != address(0)) {
            revert DAOAlreadyExists(params.name);
        }

        // Deploy token via specialized deployer
        address token = tokenDeployer.deploy(
            params.name,
            params.symbol,
            creator,
            params.initialSupply
        );

        // Deploy timelock via specialized deployer
        address timelock = timelockDeployer.deploy(
            params.timelockDelay,
            address(this)
        );

        // Deploy governor via specialized deployer
        address governor = governorDeployer.deploy(
            token,
            timelock,
            string(abi.encodePacked(params.name, " Governor")),
            params.votingDelay,
            params.votingPeriod,
            params.proposalThreshold,
            params.quorumFraction
        );

        // Wire timelock roles — factory is timelock admin
        DAOTimelock tc = DAOTimelock(payable(timelock));
        tc.grantRole(tc.PROPOSER_ROLE(), governor);
        tc.grantRole(tc.CANCELLER_ROLE(), governor);
        tc.revokeRole(tc.TIMELOCK_ADMIN_ROLE(), address(this));

        // Deploy treasury directly (small contract)
        address treasury = address(new Treasury(params.signers, params.treasuryThreshold));

        // Deploy RevenueSharing and PayoutDistributor directly
        RevenueSharing revenueSharing = new RevenueSharing();
        PayoutDistributor payoutDistributor = new PayoutDistributor(
            IDAOToken(token),
            IReputationRegistry(reputationRegistry),
            IAgentRegistry(identityRegistry),
            new address[](0)
        );

        // Transfer ownership to timelock
        revenueSharing.transferOwnership(timelock);
        payoutDistributor.transferOwnership(timelock);

        deployment = DAODeployment({
            token: token,
            governor: governor,
            timelock: timelock,
            treasury: treasury,
            creator: creator,
            revenueSharing: address(revenueSharing),
            payoutDistributor: address(payoutDistributor)
        });

        _daos[params.name] = deployment;
        _daoNames.push(params.name);

        emit DAOCreated(
            params.name,
            creator,
            token,
            governor,
            timelock,
            treasury,
            address(revenueSharing),
            address(payoutDistributor)
        );
    }
}
