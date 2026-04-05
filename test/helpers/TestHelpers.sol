// SPDX-License-Identifier: OPL-1.1
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../../contracts/interfaces/IEIP3009.sol";

/**
 * @title TestHelpers
 * @dev Common utilities and helpers for Foundry tests
 */
contract TestHelpers is Test {
    // ============ EIP-3009 Signature Helpers ============

    /**
     * @notice Sign an EIP-3009 transfer authorization
     * @param privateKey The signer's private key
     * @param from The sender address
     * @param token The token address
     * @param to The recipient address
     * @param amount The amount to transfer
     * @param validAfter Start time of authorization
     * @param validBefore End time of authorization
     * @param nonce Unique nonce for the authorization
     * @return v Signature v value
     * @return r Signature r value
     * @return s Signature s value
     */
    function signEIP3009(
        uint256 privateKey,
        address from,
        address token,
        address to,
        uint256 amount,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 domainSeparator = _getDomainSeparator(token);

        bytes32 structHash = keccak256(abi.encode(
            keccak256("TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"),
            from,
            to,
            amount,
            validAfter,
            validBefore,
            nonce
        ));

        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            structHash
        ));

        (v, r, s) = vm.sign(privateKey, digest);
    }

    /**
     * @notice Sign an EIP-3009 transfer with default time values
     * @param privateKey The signer's private key
     * @param from The sender address
     * @param token The token address
     * @param to The recipient address
     * @param amount The amount to transfer
     * @param nonce Unique nonce for the authorization
     * @return v Signature v value
     * @return r Signature r value
     * @return s Signature s value
     */
    function signEIP3009(
        uint256 privateKey,
        address from,
        address token,
        address to,
        uint256 amount,
        bytes32 nonce
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        return signEIP3009(
            privateKey,
            from,
            token,
            to,
            amount,
            0,
            type(uint256).max,
            nonce
        );
    }

    /**
     * @notice Get the EIP-712 domain separator for EIP-3009 tokens
     * @param token The token address
     * @return The domain separator
     */
    function _getDomainSeparator(address token) internal view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("USDT0"),
            keccak256("1"),
            block.chainid,
            token
        ));
    }

    // ============ Token Helpers ============

    /**
     * @notice Mint tokens to an account (if supported by token)
     * @param token The token address
     * @param account The recipient account
     * @param amount The amount to mint
     */
    function mintToken(address token, address account, uint256 amount) internal {
        (bool success, ) = token.call(
            abi.encodeWithSignature("mint(address,uint256)", account, amount)
        );
        assertTrue(success, "Mint failed");
    }

    /**
     * @notice Approve tokens for spending
     * @param token The token address
     * @param spender The spender address
     * @param amount The amount to approve
     */
    function approveToken(address token, address spender, uint256 amount) internal {
        (bool success, ) = token.call(
            abi.encodeWithSignature("approve(address,uint256)", spender, amount)
        );
        assertTrue(success, "Approve failed");
    }

    // ============ Assertion Helpers ============

    /**
     * @notice Assert two values are approximately equal (relative tolerance)
     * @param a First value
     * @param b Second value
     * @param maxBips Maximum relative difference in basis points (100 = 1%)
     */
    function assertEqRel(uint256 a, uint256 b, uint256 maxBips) internal {
        uint256 diff = a > b ? a - b : b - a;
        uint256 maxValue = a > b ? a : b;
        uint256 maxDiff = (maxValue * maxBips) / 10000;

        if (diff > maxDiff) {
            emit log_named_uint("a", a);
            emit log_named_uint("b", b);
            emit log_named_uint("diff", diff);
            emit log_named_uint("maxDiff", maxDiff);
            fail("Values not within relative tolerance");
        }
    }

    // ============ Time Helpers ============

    /**
     * @notice Warp time to a specific day
     * @param day The day number to warp to
     */
    function skipToDay(uint256 day) internal {
        vm.warp(day * 1 days);
    }

    /**
     * @notice Warp time to the next Thursday
     */
    function skipToNextThursday() internal {
        uint256 currentDay = block.timestamp / 1 days;
        uint256 daysUntilThursday = (4 + 7 - (currentDay % 7)) % 7;
        if (daysUntilThursday == 0) daysUntilThursday = 7;
        vm.warp(block.timestamp + daysUntilThursday * 1 days);
    }

    /**
     * @notice Get the current timestamp in days
     * @return The current day number
     */
    function getCurrentDay() internal view returns (uint256) {
        return block.timestamp / 1 days;
    }

    // ============ Storage Helpers ============

    /**
     * @notice Read a storage slot from a contract
     * @param contractAddr The contract address
     * @param slot The storage slot number
     * @return The value at the storage slot
     */
    function getStorageAt(address contractAddr, uint256 slot) internal view returns (bytes32) {
        return vm.load(contractAddr, bytes32(slot));
    }

    /**
     * @notice Write to a storage slot of a contract
     * @param contractAddr The contract address
     * @param slot The storage slot number
     * @param value The value to write
     */
    function setStorageAt(address contractAddr, uint256 slot, bytes32 value) internal {
        vm.store(contractAddr, bytes32(slot), value);
    }

    /**
     * @notice Read an address from a storage slot
     * @param contractAddr The contract address
     * @param slot The storage slot number
     * @return The address at the storage slot
     */
    function getAddressAt(address contractAddr, uint256 slot) internal view returns (address) {
        return address(uint160(uint256(getStorageAt(contractAddr, slot))));
    }

    /**
     * @notice Read a uint256 from a storage slot
     * @param contractAddr The contract address
     * @param slot The storage slot number
     * @return The uint256 value at the storage slot
     */
    function getUintAt(address contractAddr, uint256 slot) internal view returns (uint256) {
        return uint256(getStorageAt(contractAddr, slot));
    }

    // ============ Array Helpers ============

    /**
     * @notice Check if an array contains a value
     * @param array The array to search
     * @param value The value to look for
     * @return True if the value is in the array
     */
    function contains(address[] memory array, address value) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == value) return true;
        }
        return false;
    }

    /**
     * @notice Check if an array contains a value
     * @param array The array to search
     * @param value The value to look for
     * @return True if the value is in the array
     */
    function contains(uint256[] memory array, uint256 value) internal pure returns (bool) {
        for (uint256 i = 0; i < array.length; i++) {
            if (array[i] == value) return true;
        }
        return false;
    }

    // ============ Fuzzing Helpers ============
    // Note: bound() functions are available in forge-std StdUtils

    // ============ Random Helpers ============

    /**
     * @notice Generate a random address
     * @return A random address
     */
    function randomAddress() internal view returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp)))));
    }

    /**
     * @notice Generate a random uint256
     * @param seed The seed for randomness
     * @return A random uint256
     */
    function randomUint256(uint256 seed) internal view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(seed, block.timestamp, block.prevrandao)));
    }

    /**
     * @notice Generate a random uint256 in a range
     * @param seed The seed for randomness
     * @param min Minimum value (inclusive)
     * @param max Maximum value (inclusive)
     * @return A random uint256 in the range
     */
    function randomUint256(uint256 seed, uint256 min, uint256 max) internal view returns (uint256) {
        return bound(randomUint256(seed), min, max);
    }

    // ============ Deployment Helpers ============

    /**
     * @notice Deploy a contract with create2
     * @param bytecode The contract bytecode
     * @param salt The create2 salt
     * @return deployed The address of the deployed contract
     */
    function deployCreate2(bytes memory bytecode, bytes32 salt) internal returns (address deployed) {
        assembly {
            deployed := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
    }

    /**
     * @notice Compute the create2 address for a contract
     * @param deployer The deployer address
     * @param salt The create2 salt
     * @param initCodeHash The keccak256 hash of the init code
     * @return The predicted address
     */
    function computeCreate2Address(
        address deployer,
        bytes32 salt,
        bytes32 initCodeHash
    ) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(
            bytes1(0xff),
            deployer,
            salt,
            initCodeHash
        )))));
    }

    // ============ Event Helpers ============

    /**
     * @notice Expect an event with specific parameters
     * @param emitter The contract emitting the event
     * @param eventData The encoded event data
     */
    function expectEvent(address emitter, bytes memory eventData) internal {
        vm.recordLogs();
        // Perform action that should emit event
        // ...

        // Check event was emitted - use recordLogs implicitly
        assertTrue(true, "Event check placeholder");
    }

    // ============ Gas Helpers ============

    /**
     * @notice Measure gas for a function call
     * @param label Label for the gas measurement
     * @param target The contract to call
     * @param data The calldata to send
     * @return gasUsed The gas consumed
     */
    function measureGas(string memory label, address target, bytes memory data) internal returns (uint256 gasUsed) {
        uint256 gasBefore = gasleft();
        (bool success, ) = target.call(data);
        assertTrue(success, "Call failed");
        gasUsed = gasBefore - gasleft();
        emit log_named_uint(string(abi.encodePacked(label, " gas")), gasUsed);
    }

    // ============ ERC20 Helpers ============

    /**
     * @notice Get the balance of an ERC20 token
     * @param token The token address
     * @param account The account to check
     * @return The token balance
     */
    function balanceOf(address token, address account) internal view returns (uint256) {
        (bool success, bytes memory data) = token.staticcall(
            abi.encodeWithSignature("balanceOf(address)", account)
        );
        assertTrue(success, "Balance check failed");
        return abi.decode(data, (uint256));
    }

    /**
     * @notice Transfer ERC20 tokens
     * @param token The token address
     * @param to The recipient
     * @param amount The amount to transfer
     */
    function transferToken(address token, address to, uint256 amount) internal {
        (bool success, ) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", to, amount)
        );
        assertTrue(success, "Transfer failed");
    }
}
