// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

library FVMAddress {
    error NotMaskedIdAddress(address addr);
    error InvalidF0Address(bytes f0Address);

    /// @notice Creates an f0 (ID) address in bytes using unsigned LEB128 encoding
    /// @param id Actor ID to encode
    function f0(uint64 id) internal pure returns (bytes memory buffer) {
        // Max size: 1 protocol byte + 10 bytes for uint64 LEB128 encoding
        buffer = new bytes(11);
        buffer[0] = 0x00; // Protocol byte for f0

        uint256 i = 1;

        do {
            uint8 byteVal = uint8(id & 0x7F); // Take 7 bits
            id >>= 7; // Shift right by 7 bits
            if (id != 0) {
                byteVal |= 0x80; // Set MSB if more bytes follow
            }
            buffer[i++] = bytes1(byteVal);
        } while (id != 0);

        assembly ("memory-safe") {
            mstore(buffer, i) // Set the correct length of the bytes array
        }
    }

    /// @notice Decodes the actor ID of an f0 (ID) address, the inverse of `f0`
    /// @dev Reverts unless the address is the canonical encoding: protocol byte 0x00 followed by exactly one
    ///      minimal unsigned LEB128 varint that fits in a uint64.
    function actorId(bytes memory f0Address) internal pure returns (uint64) {
        uint256 length = f0Address.length;
        require(length >= 2 && length <= 11 && uint8(f0Address[0]) == 0x00, InvalidF0Address(f0Address));

        uint256 id;
        for (uint256 i = 1; i < length; ++i) {
            uint8 byteVal = uint8(f0Address[i]);
            // Only the last byte clears the continuation bit
            require((byteVal & 0x80 == 0) == (i == length - 1), InvalidF0Address(f0Address));
            id |= uint256(byteVal & 0x7F) << (7 * (i - 1));
        }
        // A zero final byte after the first is a non-minimal encoding
        require(length == 2 || uint8(f0Address[length - 1]) != 0, InvalidF0Address(f0Address));
        require(id <= type(uint64).max, InvalidF0Address(f0Address));
        return uint64(id);
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

    /// @notice Creates a masked ID address (the EVM encoding of an f0 actor ID)
    /// @dev Format: 0xff + 11 zero bytes + big-endian uint64 actor ID (20 bytes total)
    /// @param id Actor ID to encode
    function maskedAddress(uint64 id) internal pure returns (address maskedAddr) {
        assembly ("memory-safe") {
            maskedAddr := or(id, 0xff00000000000000000000000000000000000000)
        }
    }

    /// @notice Extracts the actor ID from a masked ID address without prefix validation
    /// @dev Only call when the address is known to have the 0xff000...000 prefix
    function actorId(address maskedAddr) internal pure returns (uint64) {
        return uint64(uint160(maskedAddr));
    }

    /// @notice Extracts the actor ID from a masked ID address, reverting if the prefix is wrong
    /// @dev Use FVMActor.tryGetActorId to test if the actorId is valid
    function safeActorId(address maskedAddr) internal pure returns (uint64) {
        require(uint160(maskedAddr) >> 64 == 0xff0000000000000000000000, NotMaskedIdAddress(maskedAddr));
        return actorId(maskedAddr);
    }
}
