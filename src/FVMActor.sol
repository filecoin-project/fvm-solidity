// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {RESOLVE_ADDRESS} from "./FVMPrecompiles.sol";
import {FVMAddress} from "./FVMAddress.sol";

library FVMActor {
    error ActorNotFound(bytes filAddress);

    // =============================================================
    //                    BYTES IMPLEMENTATION
    // =============================================================

    /// @notice Tries to get the actor ID for a Filecoin address
    /// @dev Reverts if the address is invalid.  Returns (false, 0) if actor doesn't exist.
    /// @param filAddress The Filecoin address in bytes representation (e.g., f01, f2abcde)
    /// @return exists Whether the actor exists
    /// @return actorId The actor ID (uint64), valid only if exists is true
    function tryGetActorId(bytes memory filAddress) internal view returns (bool exists, uint64 actorId) {
        assembly ("memory-safe") {
            // Get pointer to the input data and its length
            let len := mload(filAddress)
            let dataPtr := add(filAddress, 0x20)

            // Call the precompile
            // args: gas, address, input offset, input size, output offset, output size
            let success := staticcall(gas(), RESOLVE_ADDRESS, dataPtr, len, 0, 32)

            // Handle execution failure (invalid address format)
            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            // Check return data size to determine existence
            let returnSize := returndatasize()

            // Actor exists if ANY data is returned
            if returnSize {
                exists := 1
                actorId := mload(0)
            }
        }
    }

    /// @notice Gets the actor ID for a Filecoin address, requiring the actor exists
    /// @dev Reverts if the address is invalid or actor doesn't exist
    /// @param filAddress The Filecoin address in bytes representation
    /// @return actorId The actor ID (uint64)
    function getActorId(bytes memory filAddress) internal view returns (uint64 actorId) {
        bool exists;
        (exists, actorId) = tryGetActorId(filAddress);
        if (!exists) revert ActorNotFound(filAddress);
    }

    // =============================================================
    //                  ADDRESS (EVM) IMPLEMENTATION
    // =============================================================

    /// @notice Attempts to resolve a Solidity address to an actor ID
    /// @dev Converts address to f410 in scratch memory (no allocation).
    function tryGetActorId(address addr) internal view returns (bool exists, uint64 actorId) {
        assembly ("memory-safe") {
            mstore8(0x00, 0x04) // f410 protocol
            mstore8(0x01, 0x0a) // EVM namespace (0x0a)
            mstore(0x02, shl(96, addr)) // Address bytes

            // Call Precompile (RESOLVE_ADDRESS)
            // Input: scratch 0x00, length 22
            // Output: scratch 0x00, length 32 (reuse scratch space)
            let success := staticcall(gas(), RESOLVE_ADDRESS, 0x00, 22, 0x00, 32)

            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            if returndatasize() {
                exists := 1
                actorId := mload(0x00)
            }
        }
    }

    /// @notice Resolves a Solidity address to an actor ID, requiring the actor exists
    function getActorId(address addr) internal view returns (uint64 actorId) {
        bool exists;
        (exists, actorId) = tryGetActorId(addr);
        if (!exists) revert ActorNotFound(FVMAddress.f410(addr));
    }
}
