// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {LOOKUP_DELEGATED_ADDRESS} from "./FVMPrecompiles.sol";

library FVMLookupDelegatedAddress {
    /// @notice Precompile call failed (e.g., actor ID > max u64)
    error PrecompileCallFailed();

    /// @notice Actor has no delegated address
    error NoDelegatedAddress();

    /// @notice Invalid delegated address format
    error InvalidDelegatedAddress();

    /// @notice Looks up the delegated address (f4 address) of an actor by ID
    /// @dev Returns empty bytes if actor doesn't exist or has no delegated address
    /// @param actorId The actor ID (uint64)
    /// @return delegatedAddress The delegated address as raw bytes (empty if not found)
    function lookupDelegatedAddress(uint64 actorId) internal view returns (bytes memory delegatedAddress) {
        bytes4 errorSelector = PrecompileCallFailed.selector;

        assembly ("memory-safe") {
            let fmp := mload(0x40)

            // Encode actorId as ABI uint256 (u64 encoded as u256)
            mstore(fmp, actorId)

            // Call precompile
            // staticcall(gas, address, argsOffset, argsSize, retOffset, retSize)
            // We don't know return size ahead of time, so use 0 for retSize
            let success := staticcall(gas(), LOOKUP_DELEGATED_ADDRESS, fmp, 32, 0, 0)

            // Handle execution failure
            if iszero(success) {
                mstore(0, errorSelector)
                revert(0, 4)
            }

            // Get return data size
            let returnSize := returndatasize()

            // Allocate memory for the bytes return value
            delegatedAddress := fmp

            // Store the length
            mstore(delegatedAddress, returnSize)

            // Copy the raw bytes from returndata
            returndatacopy(add(delegatedAddress, 0x20), 0, returnSize)

            // Update free memory pointer
            // Round up to nearest 32-byte boundary
            let newFmp := add(add(delegatedAddress, 0x20), and(add(returnSize, 0x1f), not(0x1f)))
            mstore(0x40, newFmp)
        }
    }

    /// @notice Looks up the delegated address and requires it exists
    /// @dev Reverts if the actor has no delegated address
    /// @param actorId The actor ID (uint64)
    /// @return delegatedAddress The delegated address as raw bytes
    function lookupDelegatedAddressStrict(uint64 actorId) internal view returns (bytes memory delegatedAddress) {
        delegatedAddress = lookupDelegatedAddress(actorId);
        if (delegatedAddress.length == 0) revert NoDelegatedAddress();
    }

    /// @notice Extracts the Ethereum-style address from a delegated address
    /// @dev Validates that the address is 22 bytes and starts with 0x040a
    /// @param delegatedAddress The delegated address (f410 format)
    /// @return ethAddress The Ethereum-style address (last 20 bytes)
    function toEthAddress(bytes memory delegatedAddress) internal pure returns (address ethAddress) {
        // Check length first (cheaper to do outside assembly)
        if (delegatedAddress.length != 22) revert InvalidDelegatedAddress();

        bytes4 errorSelector = InvalidDelegatedAddress.selector;

        assembly ("memory-safe") {
            // DelegatedAddress points to the length (32 bytes).
            // add(delegatedAddress, 0x20) points to the actual data (the f4 address)
            // Load the first 32 bytes of data (Prefix + Address + some junk)
            let firstWord := mload(add(delegatedAddress, 0x20))

            // Check 0x040a prefix (protocol 0x04, namespace 0x0a)
            // Shift right 240 bits (30 bytes) to get first 2 bytes
            if iszero(eq(shr(240, firstWord), 0x040a)) {
                mstore(0, errorSelector)
                revert(0, 4)
            }

            // Extract the last 20 bytes as address
            // Offset: delegatedAddress + 32 (length) + 2 (0x040a prefix) = 34
            // mload loads 32 bytes from this offset. The 20-byte address will be in
            // the high bits. Shift right by 96 bits (12 bytes) to align it for the address type.
            let data := mload(add(delegatedAddress, 34))
            ethAddress := shr(96, data)
        }
    }
}
