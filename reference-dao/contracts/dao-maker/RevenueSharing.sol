// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IRevenueSharing.sol";

/**
 * @title RevenueSharing
 * @dev Pull-based revenue distribution supporting native FLR + ERC-20 tokens.
 *      Share ratios in basis points (10000 = 100%). Governance-adjustable via owner.
 */
contract RevenueSharing is IRevenueSharing, Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant TOTAL_RATIO = 10_000;

    address[] private _shareholders;
    mapping(address => uint256) private _shares;
    mapping(address => mapping(address => uint256)) private _deposited;
    mapping(address => mapping(address => uint256)) private _claimed;

    uint256 private _totalShares;

    error ZeroAddress();
    error ZeroShares();
    error InvalidRatio(uint256 total);
    error NoSharesToClaim();
    error TransferFailed();

    modifier onlyShareholder() {
        if (_shares[msg.sender] == 0) {
            revert NoSharesToClaim();
        }
        _;
    }

    receive() external payable {
        if (msg.value > 0) {
            _deposited[address(0)][address(0)] += msg.value;
            emit Deposited(address(0), msg.sender, msg.value);
        }
    }

    /**
     * @inheritdoc IRevenueSharing
     */
    function depositNative() external payable override nonReentrant whenNotPaused {
        if (msg.value == 0) {
            revert ZeroShares();
        }
        _deposited[address(0)][address(0)] += msg.value;
        emit Deposited(address(0), msg.sender, msg.value);
    }

    /**
     * @inheritdoc IRevenueSharing
     */
    function depositToken(address token, uint256 amount) external override nonReentrant whenNotPaused {
        if (token == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroShares();
        }
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        _deposited[token][address(0)] += amount;
        emit Deposited(token, msg.sender, amount);
    }

    /**
     * @inheritdoc IRevenueSharing
     */
    function claim(address token) external override onlyShareholder nonReentrant whenNotPaused {
        uint256 shareRatio = _shares[msg.sender];
        uint256 totalDeposited = _deposited[token][address(0)];
        uint256 entitled = (totalDeposited * shareRatio) / TOTAL_RATIO;
        uint256 alreadyClaimed = _claimed[token][msg.sender];
        uint256 pending = entitled - alreadyClaimed;

        if (pending == 0) {
            revert NoSharesToClaim();
        }

        _claimed[token][msg.sender] += pending;

        if (token == address(0)) {
            (bool success, ) = payable(msg.sender).call{value: pending}("");
            if (!success) {
                revert TransferFailed();
            }
        } else {
            IERC20(token).safeTransfer(msg.sender, pending);
        }

        emit Claimed(msg.sender, token, pending);
    }

    /**
     * @inheritdoc IRevenueSharing
     */
    function setShareholders(
        address[] calldata shareholders,
        uint256[] calldata shares
    ) external override onlyOwner {
        uint256 len = shareholders.length;
        if (len != shares.length) {
            revert InvalidRatio(0);
        }

        // Validate all inputs before mutating state
        uint256 totalShares;
        for (uint256 i = 0; i < len; i++) {
            if (shareholders[i] == address(0)) {
                revert ZeroAddress();
            }
            if (shares[i] == 0) {
                revert ZeroShares();
            }
            totalShares += shares[i];
        }

        if (totalShares != TOTAL_RATIO) {
            revert InvalidRatio(totalShares);
        }

        // Clear old shareholders
        uint256 oldLen = _shareholders.length;
        for (uint256 i = 0; i < oldLen; i++) {
            _shares[_shareholders[i]] = 0;
        }

        // Set new shareholders
        for (uint256 i = 0; i < len; i++) {
            _shares[shareholders[i]] = shares[i];
        }

        _shareholders = shareholders;
        _totalShares = totalShares;
        emit ShareholdersUpdated(len);
    }

    /**
     * @inheritdoc IRevenueSharing
     */
    function addShareholder(address shareholder, uint256 shares) external override onlyOwner {
        if (shareholder == address(0)) {
            revert ZeroAddress();
        }
        if (shares == 0) {
            revert ZeroShares();
        }
        if (_shares[shareholder] > 0) {
            revert InvalidRatio(_shares[shareholder]);
        }

        // Validate total won't exceed TOTAL_RATIO
        if (_totalShares + shares > TOTAL_RATIO) {
            revert InvalidRatio(_totalShares + shares);
        }

        _shares[shareholder] = shares;
        _totalShares += shares;
        _shareholders.push(shareholder);
        emit ShareholderAdded(shareholder, shares);
    }

    /**
     * @inheritdoc IRevenueSharing
     */
    function removeShareholder(address shareholder) external override onlyOwner {
        if (_shares[shareholder] == 0) {
            revert ZeroShares();
        }

        uint256 removedShares = _shares[shareholder];
        _shares[shareholder] = 0;
        _totalShares -= removedShares;

        // Find and remove by swapping with last element
        for (uint256 i = 0; i < _shareholders.length; i++) {
            if (_shareholders[i] == shareholder) {
                _shareholders[i] = _shareholders[_shareholders.length - 1];
                _shareholders.pop();
                break;
            }
        }
        emit ShareholderRemoved(shareholder);
    }

    /**
     * @inheritdoc IRevenueSharing
     */
    function updateShare(address shareholder, uint256 shares) external override onlyOwner {
        if (_shares[shareholder] == 0) {
            revert ZeroShares();
        }
        if (shares == 0) {
            revert ZeroShares();
        }

        uint256 oldShares = _shares[shareholder];

        if (_totalShares - oldShares + shares > TOTAL_RATIO) {
            revert InvalidRatio(_totalShares - oldShares + shares);
        }

        _shares[shareholder] = shares;
        _totalShares = _totalShares - oldShares + shares;
        emit ShareUpdated(shareholder, oldShares, shares);
    }

    /**
     * @inheritdoc IRevenueSharing
     */
    function getPendingAmount(
        address shareholder,
        address token
    ) external view override returns (uint256) {
        uint256 shareRatio = _shares[shareholder];
        if (shareRatio == 0) {
            return 0;
        }
        uint256 totalDeposited = _deposited[token][address(0)];
        uint256 entitled = (totalDeposited * shareRatio) / TOTAL_RATIO;
        uint256 alreadyClaimed = _claimed[token][shareholder];
        if (entitled <= alreadyClaimed) {
            return 0;
        }
        return entitled - alreadyClaimed;
    }

    /**
     * @inheritdoc IRevenueSharing
     */
    function getShare(address shareholder) external view override returns (uint256) {
        return _shares[shareholder];
    }

    /**
     * @dev Get all shareholders.
     * @return Array of shareholder addresses
     */
    function getShareholders() external view returns (address[] memory) {
        return _shareholders;
    }

    /**
     * @dev Get number of shareholders.
     * @return Shareholder count
     */
    function getShareholderCount() external view returns (uint256) {
        return _shareholders.length;
    }

    /**
     * @dev Pause the contract (owner only)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause the contract (owner only)
     */
    function unpause() external onlyOwner {
        _unpause();
    }
}
