// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {CBOR_CODEC, EMPTY_CODEC} from "./FVMCodec.sol";
import {EXIT_SUCCESS, USR_NOT_FOUND} from "./FVMErrors.sol";
import {READONLY_FLAG} from "./FVMFlags.sol";
import {GET_OWNER, MINER_POWER} from "./FVMMethod.sol";
import {CALL_ACTOR_BY_ID} from "./FVMPrecompiles.sol";
import {STORAGE_POWER_ACTOR_ID} from "./FVMActors.sol";

library FVMMiner {
    /// @dev The miner actor returned a non-zero exit code for GetOwner.
    error GetOwnerFailed(int256 exitCode);

    /// @dev The storage power actor returned an unexpected exit code for MinerPower.
    error IsMinerFailed(int256 exitCode);

    /// @notice Queries the storage power actor to determine if actorId is a registered miner.
    /// @dev Miners with zero power are still registered; returns true for them.
    ///      Reverts with IsMinerFailed for any exit code other than 0 or USR_NOT_FOUND:
    ///      - USR_SERIALIZATION (21): power actor could not decode params (our encoding is always valid)
    ///      - USR_ILLEGAL_STATE (20): power actor state or claims HAMT is corrupt
    ///      - USR_ASSERTION_FAILED (24): HAMT key encoding failed, or a kernel error was wrapped
    /// @param actorId The actor ID to check
    /// @return Whether actorId is a registered miner actor
    function isMiner(uint64 actorId) internal view returns (bool) {
        int256 exitCode = _queryMinerPower(actorId);
        if (exitCode == EXIT_SUCCESS) return true;
        require(exitCode == int256(uint256(USR_NOT_FOUND)), IsMinerFailed(exitCode));
        return false;
    }

    /// @dev Calls MinerPower on the storage power actor and returns only the exit code.
    ///      Encodes params as CBOR [actorId] using the 8-byte uint form (always valid CBOR).
    function _queryMinerPower(uint64 actorId) private view returns (int256 exitCode) {
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(fmp, MINER_POWER)
            mstore(add(fmp, 0x20), 0)
            mstore(add(fmp, 0x40), READONLY_FLAG)
            mstore(add(fmp, 0x60), CBOR_CODEC)
            mstore(add(fmp, 0x80), 0xc0) // params ABI offset (6 * 0x20)
            mstore(add(fmp, 0xa0), STORAGE_POWER_ACTOR_ID)
            mstore(add(fmp, 0xc0), 10) // params length = 10 bytes
            // CBOR: 0x81 (array-1) + 0x1b (uint64 8-byte) + actorId big-endian
            mstore(add(fmp, 0xe0), or(shl(240, 0x811b), shl(176, actorId)))

            exitCode := not(0) // precompile failure sentinel

            if and(gt(returndatasize(), 0x1f), staticcall(gas(), CALL_ACTOR_BY_ID, fmp, 0x100, 0, 0x20)) {
                exitCode := mload(0)
            }
        }
    }

    /// @notice Calls GetOwner on a miner actor without reverting on actor error.
    /// @param minerId The miner actor ID
    /// @return ok Whether the call succeeded (exit code 0)
    /// @return owner Raw Filecoin address bytes of the current owner; empty if ok is false
    function tryGetOwner(uint64 minerId) internal view returns (bool ok, bytes memory owner) {
        int256 exitCode;
        (exitCode, owner) = _getOwner(minerId);
        ok = exitCode == EXIT_SUCCESS;
    }

    /// @notice Calls GetOwner on a miner actor, reverting on actor error.
    /// @param minerId The miner actor ID
    /// @return owner Raw Filecoin address bytes of the current owner
    function getOwner(uint64 minerId) internal view returns (bytes memory owner) {
        int256 exitCode;
        (exitCode, owner) = _getOwner(minerId);
        require(exitCode == EXIT_SUCCESS, GetOwnerFailed(exitCode));
    }

    /// @dev Calls GetOwner via CALL_ACTOR_BY_ID and decodes the owner address bytes directly
    ///      from returndata without an intermediate CBOR buffer allocation.
    function _getOwner(uint64 minerId) private view returns (int256 exitCode, bytes memory owner) {
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(fmp, GET_OWNER)
            mstore(add(fmp, 0x20), 0) // value
            mstore(add(fmp, 0x40), READONLY_FLAG)
            mstore(add(fmp, 0x60), EMPTY_CODEC)
            mstore(add(fmp, 0x80), 0xc0) // params ABI offset
            mstore(add(fmp, 0xa0), minerId)
            mstore(add(fmp, 0xc0), 0) // params length = 0

            exitCode := not(0) // precompile failure

            if and(gt(returndatasize(), 0x1f), staticcall(gas(), CALL_ACTOR_BY_ID, fmp, 0xe0, 0, 0x20)) {
                exitCode := mload(0)
                if iszero(exitCode) {
                    // returndata layout:
                    //   0x00: exitCode  0x20: codec  0x40: bytes ABI offset  0x60: bytes length
                    //   0x80: CBOR data — byte 0: 0x82 array header
                    //                    byte 1: CBOR bytes header (0x40 | addrLen, inline ≤ 23)
                    //                    byte 2+: f0 address bytes
                    returndatacopy(31, 0x81, 0x01)
                    let addrLen := and(mload(0), 0x1f)
                    if addrLen {
                        // Reuse fmp for the owner bytes allocation (call input consumed).
                        owner := fmp
                        mstore(owner, addrLen)
                        returndatacopy(add(owner, 0x20), 0x82, addrLen)
                        mstore(0x40, add(add(owner, 0x20), and(add(addrLen, 0x1f), not(0x1f))))
                    }
                }
            }
        }
    }

    /// @notice Calls GetOwner and returns the owner's actor ID.
    /// @param minerId The miner actor ID
    /// @return ok Whether the call succeeded (exit code 0)
    /// @return ownerId The actor ID of the current owner; 0 if ok is false
    function tryGetOwnerActorId(uint64 minerId) internal view returns (bool ok, uint64 ownerId) {
        int256 exitCode;
        (exitCode, ownerId) = _getOwnerActorId(minerId);
        ok = exitCode == EXIT_SUCCESS;
    }

    /// @notice Calls GetOwner and returns the owner's actor ID.
    /// @param minerId The miner actor ID
    /// @return ownerId The actor ID of the current owner
    function getOwnerActorId(uint64 minerId) internal view returns (uint64 ownerId) {
        int256 exitCode;
        (exitCode, ownerId) = _getOwnerActorId(minerId);
        require(exitCode == EXIT_SUCCESS, GetOwnerFailed(exitCode));
    }

    /// @notice Calls GetOwner and decodes the f0 owner address to a masked ID address.
    /// @param minerId The miner actor ID
    /// @return ok Whether the call succeeded (exit code 0)
    /// @return owner The masked ID address of the current owner; address(0) if ok is false
    function tryGetOwnerAddress(uint64 minerId) internal view returns (bool ok, address owner) {
        int256 exitCode;
        uint64 ownerId;
        (exitCode, ownerId) = _getOwnerActorId(minerId);
        ok = exitCode == EXIT_SUCCESS;
        assembly ("memory-safe") {
            if ok { owner := or(ownerId, 0xff00000000000000000000000000000000000000) }
        }
    }

    /// @notice Calls GetOwner and decodes the f0 owner address to a masked ID address.
    /// @param minerId The miner actor ID
    /// @return owner The masked ID address of the current owner
    function getOwnerAddress(uint64 minerId) internal view returns (address owner) {
        int256 exitCode;
        uint64 ownerId;
        (exitCode, ownerId) = _getOwnerActorId(minerId);
        require(exitCode == EXIT_SUCCESS, GetOwnerFailed(exitCode));
        assembly ("memory-safe") {
            owner := or(ownerId, 0xff00000000000000000000000000000000000000)
        }
    }

    function _getOwnerActorId(uint64 minerId) private view returns (int256 exitCode, uint64 ownerId) {
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(fmp, GET_OWNER)
            mstore(add(fmp, 0x20), 0)
            mstore(add(fmp, 0x40), READONLY_FLAG)
            mstore(add(fmp, 0x60), EMPTY_CODEC)
            mstore(add(fmp, 0x80), 0xc0)
            mstore(add(fmp, 0xa0), minerId)
            mstore(add(fmp, 0xc0), 0)

            exitCode := not(0) // precompile failure sentinel

            if and(gt(returndatasize(), 0x1f), staticcall(gas(), CALL_ACTOR_BY_ID, fmp, 0xe0, 0, 0x20)) {
                exitCode := mload(0)
                if iszero(exitCode) {
                    returndatacopy(fmp, 0x80, sub(returndatasize(), 0x80))

                    // Layout in the copied buffer (all within the first 32 bytes):
                    //   byte 0: 0x82 (2-element CBOR array)
                    //   byte 1: CBOR bytes header (inline length, f0 ≤ 11 bytes)
                    //   byte 2: 0x00 (f0 protocol byte)
                    //   byte 3+: ULEB128-encoded actor ID
                    // The ULEB128 continuation bit (high bit) signals end-of-value.
                    let word := mload(fmp)
                    let shift := 0
                    for { let i := 3 } 1 { i := add(i, 1) } {
                        let b := byte(i, word)
                        ownerId := or(ownerId, shl(shift, and(b, 0x7f)))
                        if iszero(and(b, 0x80)) { break }
                        shift := add(shift, 7)
                    }
                }
            }
        }
    }
}
