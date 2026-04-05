// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import { IBountyBoard } from "./interfaces/IBountyBoard.sol";
import { IBountyEscrow } from "./interfaces/IBountyEscrow.sol";
import { IProfileRegistry } from "../profiles/interfaces/IProfileRegistry.sol";

/**
 * @title BountyBoard
 * @dev Core bounty posting and management contract
 *
 *      Features:
 *      - Post bounties with escrowed payment
 *      - Apply for bounties
 *      - Assign workers
 *      - Submit and review work
 *      - Multiple bounty types (open, server-only, role-only, etc.)
 *      - Reputation-based filtering
 */
contract BountyBoard is IBountyBoard, Ownable {
    /// @notice Escrow contract
    IBountyEscrow public immutable escrowContract;

    /// @notice Profile registry for reputation checks
    IProfileRegistry public immutable profileRegistry;

    /// @notice Server registry (optional, for server-based bounties)
    address public serverRegistry;

    /// @notice Bounty ID counter
    uint256 private _bountyIdCounter;

    /// @notice Application ID counter
    uint256 private _applicationIdCounter;

    /// @notice Submission ID counter
    uint256 private _submissionIdCounter;

    /// @notice Bounty ID => Bounty data
    mapping(uint256 => Bounty) private _bounties;

    /// @notice Application ID => Application data
    mapping(uint256 => Application) private _applications;

    /// @notice Submission ID => Submission data
    mapping(uint256 => Submission) private _submissions;

    /// @notice Bounty ID => Application IDs
    mapping(uint256 => uint256[]) private _bountyApplications;

    /// @notice Applicant => Application IDs
    mapping(address => uint256[]) private _userApplications;

    /// @notice Bounty ID => Submission IDs
    mapping(uint256 => uint256[]) private _bountySubmissions;

    /// @notice All active bounty IDs
    uint256[] private _activeBounties;

    /// @notice Bounty ID => Index in _activeBounties
    mapping(uint256 => uint256) private _activeBountyIndex;

    /// @notice Max bounty title length
    uint256 public constant MAX_TITLE_LENGTH = 100;

    /// @notice Max bounty description length
    uint256 public constant MAX_DESCRIPTION_LENGTH = 10000;

    /// @notice Max applications per bounty
    uint256 public constant MAX_APPLICATIONS_PER_BOUNTY = 100;

    /// @notice Default bounty deadline (30 days from creation)
    uint256 public constant DEFAULT_DEADLINE = 30 days;

    // ============ Custom Errors ============

    error BountyNotFound();
    error ApplicationNotFound();
    error SubmissionNotFound();
    error InvalidInput();
    error NotAuthorized();
    error BountyNotOpen();
    error BountyClosed();
    error MaxApplicationsReached();
    error ReputationTooLow();
    error AlreadyApplied();
    error NotAssignee();
    error NotPoster();
    error InvalidEscrow();

    // ============ Constructor ============

    constructor(
        address escrowContract_,
        address profileRegistry_
    ) Ownable() {
        if (escrowContract_ == address(0)) revert InvalidInput();
        if (profileRegistry_ == address(0)) revert InvalidInput();

        escrowContract = IBountyEscrow(escrowContract_);
        profileRegistry = IProfileRegistry(profileRegistry_);
    }

    /**
     * @notice Set server registry address
     */
    function setServerRegistry(address serverRegistry_) external onlyOwner {
        serverRegistry = serverRegistry_;
    }

    // ============ Bounty Management ============

    /**
     * @notice Post a new bounty
     */
    function postBounty(
        uint256 serverId,
        string calldata title,
        string calldata description,
        address paymentToken,
        uint256 reward,
        uint256 deadline,
        uint256[] calldata requiredSkills,
        uint8 minReputation,
        BountyType bountyType,
        uint256 maxApplicants
    ) external payable returns (uint256 bountyId) {
        if (bytes(title).length == 0 || bytes(title).length > MAX_TITLE_LENGTH) revert InvalidInput();
        if (bytes(description).length == 0 || bytes(description).length > MAX_DESCRIPTION_LENGTH) revert InvalidInput();
        if (reward == 0) revert InvalidInput();
        if (deadline <= block.timestamp) revert InvalidInput();

        _bountyIdCounter++;
        bountyId = _bountyIdCounter;

        // Create escrow
        uint256 releaseDeadline = deadline + 7 days;
        uint256 escrowId = escrowContract.createEscrow{value: msg.value}(
            bountyId,
            paymentToken,
            reward,
            releaseDeadline
        );

        // Create bounty directly in storage to avoid stack too deep
        Bounty storage bounty = _bounties[bountyId];
        bounty.id = bountyId;
        bounty.serverId = serverId;
        bounty.poster = msg.sender;
        bounty.title = title;
        bounty.description = description;
        bounty.paymentToken = paymentToken;
        bounty.reward = reward;
        bounty.escrowId = escrowId;
        bounty.bountyType = bountyType;
        bounty.minReputation = minReputation;
        bounty.requiredSkills = requiredSkills;
        bounty.deadline = deadline;
        bounty.maxApplicants = maxApplicants == 0 ? MAX_APPLICATIONS_PER_BOUNTY : maxApplicants;
        bounty.status = BountyStatus.Open;
        bounty.assignee = address(0);
        bounty.applicationCount = 0;
        bounty.createdAt = block.timestamp;
        bounty.updatedAt = block.timestamp;
        bounty.isActive = true;

        _activeBounties.push(bountyId);
        _activeBountyIndex[bountyId] = _activeBounties.length - 1;

        emit BountyPosted(bountyId, serverId, msg.sender, title, reward);
        return bountyId;
    }

    /**
     * @notice Update bounty details
     */
    function updateBounty(
        uint256 bountyId,
        string calldata title,
        string calldata description,
        uint256 deadline
    ) external {
        Bounty storage bounty = _bounties[bountyId];

        if (bounty.id != bountyId || !bounty.isActive) revert BountyNotFound();
        if (bounty.poster != msg.sender) revert NotAuthorized();
        if (bounty.status != BountyStatus.Open) revert BountyNotOpen();

        if (bytes(title).length != 0) {
            bounty.title = title;
        }
        if (bytes(description).length != 0) {
            bounty.description = description;
        }
        if (deadline != 0 && deadline > block.timestamp) {
            bounty.deadline = deadline;
        }

        bounty.updatedAt = block.timestamp;

        emit BountyUpdated(bountyId, bounty.title);
    }

    /**
     * @notice Cancel a bounty
     */
    function cancelBounty(uint256 bountyId) external {
        Bounty storage bounty = _bounties[bountyId];

        if (bounty.id != bountyId || !bounty.isActive) revert BountyNotFound();
        if (bounty.poster != msg.sender) revert NotAuthorized();
        if (bounty.status != BountyStatus.Open) revert BountyNotOpen();

        bounty.status = BountyStatus.Cancelled;
        bounty.updatedAt = block.timestamp;

        // Refund escrow
        escrowContract.refundToPoster(bounty.escrowId);

        // Remove from active bounties
        _removeFromActiveBounties(bountyId);

        emit BountyCancelled(bountyId);
    }

    // ============ Applications ============

    /**
     * @notice Apply for a bounty
     */
    function applyForBounty(
        uint256 bountyId,
        string calldata proposal,
        uint256 askedPrice
    ) external returns (uint256 applicationId) {
        Bounty storage bounty = _bounties[bountyId];

        if (bounty.id != bountyId || !bounty.isActive) revert BountyNotFound();
        if (bounty.status != BountyStatus.Open) revert BountyNotOpen();

        // Check if can apply
        if (!canApplyForBounty(bountyId, msg.sender)) revert NotAuthorized();

        // Check if already applied
        for (uint256 i = 0; i < _bountyApplications[bountyId].length; i++) {
            if (_applications[_bountyApplications[bountyId][i]].applicant == msg.sender) {
                revert AlreadyApplied();
            }
        }

        // Check max applications
        if (bounty.applicationCount >= bounty.maxApplicants) revert MaxApplicationsReached();

        _applicationIdCounter++;
        applicationId = _applicationIdCounter;

        _applications[applicationId] = Application({
            id: applicationId,
            bountyId: bountyId,
            applicant: msg.sender,
            proposal: proposal,
            askedPrice: askedPrice,
            status: ApplicationStatus.Pending,
            appliedAt: block.timestamp,
            respondedAt: 0
        });

        _bountyApplications[bountyId].push(applicationId);
        _userApplications[msg.sender].push(applicationId);
        bounty.applicationCount++;
        bounty.updatedAt = block.timestamp;

        emit ApplicationSubmitted(applicationId, bountyId, msg.sender);
        return applicationId;
    }

    /**
     * @notice Accept an application
     */
    function acceptApplication(uint256 bountyId, uint256 applicationId) external {
        Bounty storage bounty = _bounties[bountyId];

        if (bounty.id != bountyId || !bounty.isActive) revert BountyNotFound();
        if (bounty.poster != msg.sender) revert NotAuthorized();
        if (bounty.status != BountyStatus.Open) revert BountyNotOpen();

        Application storage application = _applications[applicationId];

        if (application.id != applicationId) revert ApplicationNotFound();
        if (application.bountyId != bountyId) revert InvalidInput();
        if (application.status != ApplicationStatus.Pending) revert InvalidInput();

        // Set worker in escrow
        escrowContract.setWorker(bounty.escrowId, application.applicant);

        // Update bounty
        bounty.status = BountyStatus.InProgress;
        bounty.assignee = application.applicant;
        bounty.updatedAt = block.timestamp;

        // Update application
        application.status = ApplicationStatus.Accepted;
        application.respondedAt = block.timestamp;

        // Reject all other pending applications
        for (uint256 i = 0; i < _bountyApplications[bountyId].length; i++) {
            uint256 appId = _bountyApplications[bountyId][i];
            if (appId != applicationId) {
                Application storage app = _applications[appId];
                if (app.status == ApplicationStatus.Pending) {
                    app.status = ApplicationStatus.Rejected;
                    app.respondedAt = block.timestamp;
                    emit ApplicationRejected(appId, bountyId);
                }
            }
        }

        // Remove from active bounties (no longer open)
        _removeFromActiveBounties(bountyId);

        emit ApplicationAccepted(applicationId, bountyId);
    }

    /**
     * @notice Reject an application
     */
    function rejectApplication(uint256 bountyId, uint256 applicationId, string calldata reason) external {
        Bounty storage bounty = _bounties[bountyId];

        if (bounty.id != bountyId || !bounty.isActive) revert BountyNotFound();
        if (bounty.poster != msg.sender) revert NotAuthorized();
        if (bounty.status != BountyStatus.Open) revert BountyNotOpen();

        Application storage application = _applications[applicationId];

        if (application.id != applicationId) revert ApplicationNotFound();
        if (application.bountyId != bountyId) revert InvalidInput();
        if (application.status != ApplicationStatus.Pending) revert InvalidInput();

        application.status = ApplicationStatus.Rejected;
        application.respondedAt = block.timestamp;

        bounty.applicationCount--;
        bounty.updatedAt = block.timestamp;

        emit ApplicationRejected(applicationId, bountyId);
    }

    /**
     * @notice Withdraw application
     */
    function withdrawApplication(uint256 applicationId) external {
        Application storage application = _applications[applicationId];

        if (application.id != applicationId) revert ApplicationNotFound();
        if (application.applicant != msg.sender) revert NotAuthorized();
        if (application.status != ApplicationStatus.Pending) revert InvalidInput();

        application.status = ApplicationStatus.Withdrawn;

        Bounty storage bounty = _bounties[application.bountyId];
        bounty.applicationCount--;
        bounty.updatedAt = block.timestamp;

        emit ApplicationWithdrawn(applicationId);
    }

    // ============ Work Submission ============

    /**
     * @notice Submit work for a bounty
     */
    function submitWork(
        uint256 bountyId,
        string calldata proof,
        string calldata notes
    ) external returns (uint256 submissionId) {
        Bounty storage bounty = _bounties[bountyId];

        if (bounty.id != bountyId || !bounty.isActive) revert BountyNotFound();
        if (bounty.assignee != msg.sender) revert NotAssignee();
        if (bounty.status != BountyStatus.InProgress) revert InvalidInput();

        _submissionIdCounter++;
        submissionId = _submissionIdCounter;

        _submissions[submissionId] = Submission({
            id: submissionId,
            bountyId: bountyId,
            submitter: msg.sender,
            proof: proof,
            notes: notes,
            submittedAt: block.timestamp,
            isApproved: false
        });

        _bountySubmissions[bountyId].push(submissionId);

        bounty.status = BountyStatus.UnderReview;
        bounty.updatedAt = block.timestamp;

        emit WorkSubmitted(submissionId, bountyId, msg.sender);
        return submissionId;
    }

    /**
     * @notice Approve submitted work
     */
    function approveWork(uint256 bountyId) external {
        Bounty storage bounty = _bounties[bountyId];

        if (bounty.id != bountyId || !bounty.isActive) revert BountyNotFound();
        if (bounty.poster != msg.sender) revert NotPoster();
        if (bounty.status != BountyStatus.UnderReview) revert InvalidInput();

        bounty.status = BountyStatus.Completed;
        bounty.updatedAt = block.timestamp;

        // Mark latest submission as approved
        uint256[] storage submissions = _bountySubmissions[bountyId];
        if (submissions.length > 0) {
            _submissions[submissions[submissions.length - 1]].isApproved = true;
        }

        // Release escrow payment
        escrowContract.releaseToWorker(bounty.escrowId);

        emit WorkApproved(bountyId, bounty.assignee);
        emit BountyCompleted(bountyId, bounty.reward);
    }

    /**
     * @notice Reject submitted work
     */
    function rejectWork(uint256 bountyId, string calldata reason) external {
        Bounty storage bounty = _bounties[bountyId];

        if (bounty.id != bountyId || !bounty.isActive) revert BountyNotFound();
        if (bounty.poster != msg.sender) revert NotPoster();
        if (bounty.status != BountyStatus.UnderReview) revert InvalidInput();

        bounty.status = BountyStatus.InProgress;
        bounty.updatedAt = block.timestamp;

        emit WorkRejected(bountyId, reason);
    }

    // ============ View Functions ============

    /**
     * @notice Get bounty details
     */
    function getBounty(uint256 bountyId)
        external
        view
        returns (Bounty memory)
    {
        Bounty storage bounty = _bounties[bountyId];
        if (!bounty.isActive) revert BountyNotFound();
        return bounty;
    }

    /**
     * @notice Get application details
     */
    function getApplication(uint256 applicationId)
        external
        view
        returns (Application memory)
    {
        Application storage application = _applications[applicationId];
        if (application.id != applicationId) revert ApplicationNotFound();
        return application;
    }

    /**
     * @notice Get all applications for a bounty
     */
    function getBountyApplications(uint256 bountyId)
        external
        view
        returns (Application[] memory)
    {
        uint256[] memory appIds = _bountyApplications[bountyId];
        Application[] memory applications = new Application[](appIds.length);

        for (uint256 i = 0; i < appIds.length; i++) {
            applications[i] = _applications[appIds[i]];
        }

        return applications;
    }

    /**
     * @notice Get open bounties (paginated)
     */
    function getOpenBounties(uint256 offset, uint256 limit)
        external
        view
        returns (Bounty[] memory)
    {
        return _getActiveBounties(offset, limit);
    }

    /**
     * @notice Get bounties by status (requires off-chain indexing in production)
     */
    function getBountiesByStatus(BountyStatus status, uint256 offset, uint256 limit)
        external
        view
        returns (Bounty[] memory)
    {
        // For simplicity, return active bounties
        // In production, maintain status-based arrays
        if (status == BountyStatus.Open) {
            return _getActiveBounties(offset, limit);
        }

        return new Bounty[](0);
    }

    /**
     * @notice Get bounties by server
     */
    function getBountiesByServer(uint256 serverId, uint256 offset, uint256 limit)
        external
        view
        returns (Bounty[] memory)
    {
        // In production, maintain server => bounties mapping
        // For now, return empty
        return new Bounty[](0);
    }

    /**
     * @notice Get bounties where user is applicant
     */
    function getBountiesByApplicant(address applicant, uint256 offset, uint256 limit)
        external
        view
        returns (Bounty[] memory)
    {
        uint256[] memory appIds = _userApplications[applicant];

        uint256 start = offset;
        uint256 end = offset + limit;
        if (end > appIds.length) end = appIds.length;

        Bounty[] memory bounties = new Bounty[](end - start);

        uint256 index = 0;
        for (uint256 i = start; i < end; i++) {
            Application storage app = _applications[appIds[i]];
            bounties[index++] = _bounties[app.bountyId];
        }

        return bounties;
    }

    /**
     * @notice Get user's application IDs
     */
    function getUserApplications(address applicant)
        external
        view
        returns (uint256[] memory)
    {
        return _userApplications[applicant];
    }

    /**
     * @notice Check if user can apply for bounty
     */
    function canApplyForBounty(uint256 bountyId, address applicant)
        public
        view
        returns (bool)
    {
        Bounty storage bounty = _bounties[bountyId];

        if (!bounty.isActive) return false;
        if (bounty.status != BountyStatus.Open) return false;
        if (applicant == bounty.poster) return false;

        // Check reputation requirement
        if (bounty.minReputation > 0) {
            uint256 reputation = profileRegistry.getReputationScore(applicant);
            if (reputation < bounty.minReputation) return false;
        }

        // Check bounty type restrictions
        if (bounty.bountyType == BountyType.ServerOnly) {
            // Would check server membership if serverRegistry is set
            if (serverRegistry == address(0)) return true;
        }

        return true;
    }

    // ============ Internal Functions ============

    function _getActiveBounties(uint256 offset, uint256 limit)
        internal
        view
        returns (Bounty[] memory)
    {
        uint256 total = _activeBounties.length;

        if (offset >= total) return new Bounty[](0);

        uint256 end = offset + limit;
        if (end > total) end = total;

        Bounty[] memory bounties = new Bounty[](end - offset);

        for (uint256 i = offset; i < end; i++) {
            uint256 bountyId = _activeBounties[i];
            bounties[i - offset] = _bounties[bountyId];
        }

        return bounties;
    }

    function _removeFromActiveBounties(uint256 bountyId) internal {
        uint256 index = _activeBountyIndex[bountyId];

        if (index >= _activeBounties.length) return;
        if (_activeBounties[index] != bountyId) return;

        uint256 lastIndex = _activeBounties.length - 1;

        if (index != lastIndex) {
            uint256 lastBountyId = _activeBounties[lastIndex];
            _activeBounties[index] = lastBountyId;
            _activeBountyIndex[lastBountyId] = index;
        }

        _activeBounties.pop();
        delete _activeBountyIndex[bountyId];
    }

    /**
     * @notice Allow contract to receive ETH
     */
    receive() external payable {}
}
