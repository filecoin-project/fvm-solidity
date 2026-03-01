// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

library FVMAddress {
    /// @notice Invalid delegated address format
    error InvalidDelegatedAddress();

    /// @notice Creates an f0 (ID) address in bytes using unsigned LEB128 encoding
    function f0(uint64 actorId) internal pure returns (bytes memory buffer) {
        // Max size: 1 protocol byte + 10 bytes for uint64 LEB128 encoding
        buffer = new bytes(11);
        buffer[0] = 0x00; // Protocol byte for f0

        uint256 i = 1;

        do {
            uint8 byteVal = uint8(actorId & 0x7F); // Take 7 bits
            actorId >>= 7; // Shift right by 7 bits
            if (actorId != 0) {
                byteVal |= 0x80; // Set MSB if more bytes follow
            }
            buffer[i++] = bytes1(byteVal);
        } while (actorId != 0);

        assembly ("memory-safe") {
            mstore(buffer, i) // Set the correct length of the bytes array
        }
    }

    /// @notice Creates an f4 (delegated) address in bytes
    /// @dev NOTE: Only supports namespaces < 128 (single byte varint).
    function f4(uint8 namespace, bytes20 subaddress) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0x04), namespace, subaddress);
    }

    /// @notice Creates an f410 address for a Solidity address
    function f410(address addr) internal pure returns (bytes memory) {
        return f4(0x0a, bytes20(addr));
    }

    /// @notice Extracts the Ethereum-style address from a delegated address
    /// @dev Validates that the address is 22 bytes and starts with 0x040a
    /// @param delegatedAddress The delegated address (f410 format)
    /// @return ethAddress The Ethereum-style address (last 20 bytes)
    function toEthAddress(bytes memory delegatedAddress) internal pure returns (address ethAddress) {
        if (delegatedAddress.length != 22) revert InvalidDelegatedAddress();

        assembly ("memory-safe") {
            // DelegatedAddress points to the length (32 bytes).
            // add(delegatedAddress, 0x20) points to the actual data (the f4 address)
            // Load the first 32 bytes of data (Prefix + Address + some junk)
            let firstWord := mload(add(delegatedAddress, 0x20))

            // Check 0x040a prefix (protocol 0x04, namespace 0x0a)
            // Shift right 240 bits (30 bytes) to get first 2 bytes
            if iszero(eq(shr(240, firstWord), 0x040a)) {
                mstore(0, 0x8eb60a41) // InvalidDelegatedAddress.selector
                revert(28, 4)
            }

            // Extract the last 20 bytes as address
            // Offset: delegatedAddress + 32 (length) + 2 (0x040a prefix) = 34
            // mload loads 32 bytes from this offset. The 20-byte address will be in
            // the high bits. Shift right by 96 bits (12 bytes) to align it for the address type.
            ethAddress := shr(96, mload(add(delegatedAddress, 34)))
        }
    }
}
