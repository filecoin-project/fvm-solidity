// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {RESOLVE_ADDRESS} from "./FVMPrecompiles.sol";
import {FVMAddress} from "./FVMAddress.sol";

library FVMActor {
    error ActorNotFound(bytes filAddress);
    error EVMActorNotFound(address addr);

    /// @dev Prefix for masked ID addresses: 0xff followed by 11 zero bytes (top 96 bits of address)
    uint160 private constant MASKED_ID_PREFIX = 0xff0000000000000000000000;

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
    /// @dev Handles both f410 (delegated) and masked ID addresses (0xff + 11 zeros + 8-byte actor ID).
    function tryGetActorId(address addr) internal view returns (bool exists, uint64 actorId) {
        uint160 addrInt = uint160(addr);

        // Check for masked ID address: 0xff + 11 zero bytes + 8-byte actor ID
        if (addrInt >> 64 == MASKED_ID_PREFIX) {
            return tryGetActorId(FVMAddress.f0(uint64(addrInt)));
        }

        // f410 path: Converts address to f410 in scratch memory (no allocation)
        assembly ("memory-safe") {
            mstore(20, addr) // Address bytes at [32,52)
            mstore(0x00, 0x040a) // f410 protocol, EVM namespace (0x0a)

            // Call Precompile (RESOLVE_ADDRESS)
            // Input: scratch [30,52)
            // Output: scratch 0x00, length 32 (reuse scratch space)
            let success := staticcall(gas(), RESOLVE_ADDRESS, 30, 22, 0x00, 32)

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
        require(exists, EVMActorNotFound(addr));
    }
}
