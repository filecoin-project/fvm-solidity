// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

/// @notice A reference into calldata by absolute offset and byte length
struct CalldataSlice {
    uint256 offset;
    uint256 length;
}

library CalldataUtils {
    /// @notice Materialise a CalldataSlice into a new memory bytes array
    function load(CalldataSlice memory s) internal pure returns (bytes memory result) {
        uint256 off = s.offset;
        uint256 length = s.length;
        result = new bytes(length);
        assembly ("memory-safe") {
            calldatacopy(add(result, 32), off, length)
        }
    }

    /// @notice Compute the keccak256 hash of a CalldataSlice without allocating memory
    /// @dev Uses the free-memory area as a scratch buffer without advancing the free pointer
    function keccak(CalldataSlice memory s) internal pure returns (bytes32 hash) {
        uint256 off = s.offset;
        uint256 length = s.length;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            calldatacopy(ptr, off, length)
            hash := keccak256(ptr, length)
        }
    }
}
