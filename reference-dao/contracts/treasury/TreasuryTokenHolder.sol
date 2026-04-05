// SPDX-License-Identifier: OPL-1.0
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title TreasuryTokenHolder
 * @dev ERC20 token management for treasury operations
 * @notice Handles deposits, withdrawals, and approvals for multiple ERC20 tokens
 */
contract TreasuryTokenHolder is Ownable, Pausable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Storage
    mapping(address => uint256) private _tokenBalances;
    mapping(address => bool) private _tokenSupported;
    address[] private _supportedTokens;

    // Events
    event Deposited(address indexed token, address indexed from, uint256 amount);
    event Withdrawn(address indexed token, address indexed to, uint256 amount);
    event Approved(address indexed token, address indexed spender, uint256 amount);
    event TokenAdded(address indexed token);

    // Errors
    error ZeroAddress();
    error ZeroAmount();
    error TokenNotSupported(address token);
    error TokenAlreadySupported(address token);
    error InsufficientBalance(address token, uint256 requested, uint256 available);
    error ApprovalFailed(address token);
    error TransferFailed();

    /**
     * @dev Constructor
     * @param initialTokens Array of supported ERC20 token addresses
     */
    constructor(address[] memory initialTokens) Ownable() {
        for (uint256 i = 0; i < initialTokens.length; i++) {
            if (initialTokens[i] == address(0)) {
                revert ZeroAddress();
            }
            _supportedTokens.push(initialTokens[i]);
            _tokenSupported[initialTokens[i]] = true;
            emit TokenAdded(initialTokens[i]);
        }
    }

    /**
     * @dev Deposit ERC20 tokens into treasury
     * @param token Address of the ERC20 token
     * @param amount Amount to deposit
     */
    function deposit(address token, uint256 amount) external nonReentrant whenNotPaused {
        if (token == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        // Add token to supported list if not already (owner only)
        if (!_isTokenSupported(token)) {
            if (msg.sender != owner()) {
                revert TokenNotSupported(token);
            }
            _supportedTokens.push(token);
            _tokenSupported[token] = true;
            emit TokenAdded(token);
        }

        // Transfer tokens from sender
        IERC20 erc20 = IERC20(token);
        uint256 balanceBefore = erc20.balanceOf(address(this));
        erc20.safeTransferFrom(msg.sender, address(this), amount);
        uint256 actualReceived = erc20.balanceOf(address(this)) - balanceBefore;

        _tokenBalances[token] += actualReceived;

        emit Deposited(token, msg.sender, actualReceived);
    }

    /**
     * @dev Withdraw ERC20 tokens from treasury
     * @param token Address of the ERC20 token
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function withdraw(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant whenNotPaused {
        if (token == address(0) || to == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (!_isTokenSupported(token)) {
            revert TokenNotSupported(token);
        }
        if (_tokenBalances[token] < amount) {
            revert InsufficientBalance(token, amount, _tokenBalances[token]);
        }

        _tokenBalances[token] -= amount;

        IERC20(token).safeTransfer(to, amount);

        emit Withdrawn(token, to, amount);
    }

    /**
     * @dev Approve tokens for DeFi interactions
     * @param token Address of the ERC20 token
     * @param spender Address to approve
     * @param amount Amount to approve
     */
    function approveTokens(
        address token,
        address spender,
        uint256 amount
    ) external onlyOwner nonReentrant whenNotPaused {
        if (token == address(0) || spender == address(0)) {
            revert ZeroAddress();
        }
        if (!_isTokenSupported(token)) {
            revert TokenNotSupported(token);
        }

        IERC20(token).safeApprove(spender, amount);

        emit Approved(token, spender, amount);
    }

    /**
     * @dev Get balance of a specific token
     * @param token Address of the ERC20 token
     * @return Balance of the token
     */
    function getTokenBalance(address token) external view returns (uint256) {
        return _tokenBalances[token];
    }

    /**
     * @dev Get all supported tokens
     * @return Array of supported token addresses
     */
    function getSupportedTokens() external view returns (address[] memory) {
        return _supportedTokens;
    }

    /**
     * @dev Check if a token is supported
     * @param token Address to check
     * @return Whether the token is supported
     */
    function isTokenSupported(address token) external view returns (bool) {
        return _isTokenSupported(token);
    }

    /**
     * @dev Internal function to check if token is supported
     */
    function _isTokenSupported(address token) internal view returns (bool) {
        return _tokenSupported[token];
    }

    /**
     * @dev Get total number of supported tokens
     */
    function getSupportedTokenCount() external view returns (uint256) {
        return _supportedTokens.length;
    }

    /**
     * @dev Sweep native tokens (ETH/FLR) to owner
     * @param amount Amount to sweep
     */
    function sweepNative(uint256 amount) external onlyOwner nonReentrant whenNotPaused {
        if (amount == 0) {
            revert ZeroAmount();
        }
        if (address(this).balance < amount) {
            revert InsufficientBalance(address(0), amount, address(this).balance);
        }

        address owner_ = owner();

        // Use call instead of transfer to avoid gas stipend issues
        (bool success, ) = payable(owner_).call{value: amount}("");
        if (!success) {
            revert TransferFailed();
        }

        emit Withdrawn(address(0), owner_, amount);
    }

    /**
     * @dev Emergency function to recover accidentally sent tokens
     * @param token Address of token to recover
     * @param to Recipient address
     * @param amount Amount to recover
     */
    function recoverToken(
        address token,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant whenNotPaused {
        if (token == address(0) || to == address(0)) {
            revert ZeroAddress();
        }
        if (amount == 0) {
            revert ZeroAmount();
        }

        // Don't allow recovering tokens that are part of the treasury tracking
        if (_isTokenSupported(token) && _tokenBalances[token] > 0) {
            revert TokenNotSupported(token);
        }

        IERC20(token).safeTransfer(to, amount);
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

    // Receive native tokens
    receive() external payable {
        // Accept native token deposits
    }
}
