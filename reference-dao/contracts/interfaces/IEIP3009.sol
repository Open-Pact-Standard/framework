// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

/**
 * @title IEIP3009
 * @dev Interface for EIP-3009: Transfer With Authorization
 *      Enables gasless token transfers via signed authorizations.
 *      Native on Flare via USD₮0 (`0xe7cd86e13AC4309349F30B3435a9d337750fC82D`).
 */
interface IEIP3009 {
    /**
     * @dev Emitted when a transfer with authorization is executed
     */
    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);

    /**
     * @dev Emitted when an authorization is canceled
     */
    event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);

    /**
     * @dev Authorization structure for EIP-3009 transferWithAuthorization
     */
    struct TransferAuthorization {
        address from;
        address to;
        uint256 value;
        uint256 validAfter;
        uint256 validBefore;
        bytes32 nonce;
    }

    /**
     * @dev Transfer tokens using a signed authorization
     * @param from Payer address (authorization signer)
     * @param to Recipient address
     * @param value Amount to transfer
     * @param validAfter Timestamp after which the authorization is valid
     * @param validBefore Timestamp before which the authorization is valid
     * @param nonce Unique nonce to prevent replay
     * @param v Signature v value (27 or 28)
     * @param r Signature r value
     * @param s Signature s value
     */
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @dev Receive tokens using a signed authorization (receiver-initiated)
     * @param from Payer address
     * @param to Receiver address (must be msg.sender)
     * @param value Amount to transfer
     * @param validAfter Timestamp after which the authorization is valid
     * @param validBefore Timestamp before which the authorization is valid
     * @param nonce Unique nonce to prevent replay
     * @param v Signature v value
     * @param r Signature r value
     * @param s Signature s value
     */
    function receiveWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @dev Cancel an authorization (prevents replay of unused authorizations)
     * @param authorizer Address that signed the authorization
     * @param nonce Nonce of the authorization to cancel
     * @param v Signature v value
     * @param r Signature r value
     * @param s Signature s value
     */
    function cancelAuthorization(
        address authorizer,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @dev Check if an authorization has been used
     * @param authorizer Address that signed the authorization
     * @param nonce Nonce to check
     * @return Whether the authorization has been used
     */
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool);
}
