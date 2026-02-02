// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {RESOLVE_ADDRESS} from "./FVMPrecompiles.sol";

library FVMResolveAddress {
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

            // Prepare output destination (Free memory Pointer)
            let fmt := mload(0x40)

            // Call the precompile
            // args: gas, address, input offset, input size, output offset, output size
            let success := staticcall(gas(), RESOLVE_ADDRESS, dataPtr, len, fmt, 32)

            // Handle execution failure (invalid address format)
            if iszero(success) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }

            // Check return data size to determine existence
            let returnSize := returndatasize()

            switch returnSize
            case 0 {
                // Case A: Actor does not exist (Valid format, but no ID found)
                exists := 0
                actorId := 0
            }
            case 32 {
                // Case B: Actor exists (Returns ABI-encoded uint64)
                exists := 1
                actorId := mload(fmt)
            }
            default {
                // Case C: Unexpected return length (Protocol violation/Update)
                // Revert to avoid silent failure or misinterpretation
                // We use a generic revert here, equivalent to "Invalid Return Size"
                revert(0, 0)
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
        require(exists, "FVMResolveAddress: actor not found");
    }
}
