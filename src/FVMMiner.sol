// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {EMPTY_CODEC, CBOR_CODEC} from "./FVMCodec.sol";
import {EXIT_SUCCESS} from "./FVMErrors.sol";
import {READONLY_FLAG} from "./FVMFlags.sol";
import {GET_OWNER} from "./FVMMethod.sol";
import {CALL_ACTOR_BY_ID} from "./FVMPrecompiles.sol";
import {FVMAddress} from "./FVMAddress.sol";

library FVMMiner {
    /// @dev The miner actor returned a non-zero exit code for GetOwner.
    error GetOwnerFailed(int256 exitCode);

    /// @notice Calls GetOwner on a miner actor without reverting on actor error.
    /// @param minerId The miner actor ID
    /// @return ok Whether the call succeeded (exit code 0)
    /// @return owner Raw Filecoin address bytes of the current owner; empty if ok is false
    function tryGetOwner(uint64 minerId) internal returns (bool ok, bytes memory owner) {
        int256 exitCode;
        (exitCode, owner) = _getOwner(minerId);
        ok = exitCode == EXIT_SUCCESS;
    }

    /// @notice Calls GetOwner on a miner actor, reverting on actor error.
    /// @param minerId The miner actor ID
    /// @return owner Raw Filecoin address bytes of the current owner
    function getOwner(uint64 minerId) internal returns (bytes memory owner) {
        int256 exitCode;
        (exitCode, owner) = _getOwner(minerId);
        require(exitCode == EXIT_SUCCESS, GetOwnerFailed(exitCode));
    }

    /// @dev Calls GetOwner via CALL_ACTOR_BY_ID and decodes the CBOR response.
    function _getOwner(uint64 minerId) private returns (int256 exitCode, bytes memory owner) {
        bytes memory cborData;
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

            if and(gt(returndatasize(), 0x1f), call(gas(), CALL_ACTOR_BY_ID, 0, fmp, 0xe0, 0, 0x20)) {
                exitCode := mload(0)
                if iszero(exitCode) {
                    // Read CBOR data length from returndata offset 0x60
                    returndatacopy(0, 0x60, 0x20)
                    let dataLen := mload(0)
                    if and(gt(dataLen, 0), not(lt(returndatasize(), add(0x80, dataLen)))) {
                        // Reuse fmp as the cborData bytes value (input was already consumed).
                        cborData := fmp
                        mstore(cborData, dataLen)
                        returndatacopy(add(cborData, 0x20), 0x80, dataLen)
                        mstore(0x40, add(add(cborData, 0x20), and(add(dataLen, 0x1f), not(0x1f))))
                    }
                }
            }
        }
        if (exitCode == EXIT_SUCCESS && cborData.length > 0) {
            owner = _decodeOwnerReturn(cborData);
        }
    }

    /// @dev Decode the owner field from a CBOR-encoded GetOwnerReturn: array(2) [owner_bytes, ...].
    function _decodeOwnerReturn(bytes memory data) private pure returns (bytes memory owner) {
        (owner,) = _decodeCborBytes(data, 1);
    }

    /// @notice Calls GetOwner and returns the owner's actor ID.
    /// @param minerId The miner actor ID
    /// @return ok Whether the call succeeded (exit code 0)
    /// @return ownerId The actor ID of the current owner; 0 if ok is false
    function tryGetOwnerActorId(uint64 minerId) internal returns (bool ok, uint64 ownerId) {
        int256 exitCode;
        (exitCode, ownerId) = _getOwnerActorId(minerId);
        ok = exitCode == EXIT_SUCCESS;
    }

    /// @notice Calls GetOwner and returns the owner's actor ID.
    /// @param minerId The miner actor ID
    /// @return ownerId The actor ID of the current owner
    function getOwnerActorId(uint64 minerId) internal returns (uint64 ownerId) {
        int256 exitCode;
        (exitCode, ownerId) = _getOwnerActorId(minerId);
        require(exitCode == EXIT_SUCCESS, GetOwnerFailed(exitCode));
    }

    /// @notice Calls GetOwner and decodes the f0 owner address to a masked ID address.
    /// @param minerId The miner actor ID
    /// @return ok Whether the call succeeded (exit code 0)
    /// @return owner The masked ID address of the current owner; address(0) if ok is false
    function tryGetOwnerAddress(uint64 minerId) internal returns (bool ok, address owner) {
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
    function getOwnerAddress(uint64 minerId) internal returns (address owner) {
        int256 exitCode;
        uint64 ownerId;
        (exitCode, ownerId) = _getOwnerActorId(minerId);
        require(exitCode == EXIT_SUCCESS, GetOwnerFailed(exitCode));
        assembly ("memory-safe") {
            owner := or(ownerId, 0xff00000000000000000000000000000000000000)
        }
    }

    function _getOwnerActorId(uint64 minerId) private returns (int256 exitCode, uint64 ownerId) {
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

            if and(gt(returndatasize(), 0x1f), call(gas(), CALL_ACTOR_BY_ID, 0, fmp, 0xe0, 0, 0x20)) {
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

    /// @dev Decode a CBOR byte string (major type 2) at `off` within `data`.
    function _decodeCborBytes(bytes memory data, uint256 off)
        private
        pure
        returns (bytes memory result, uint256 newOff)
    {
        uint256 len = uint8(data[off++]) & 0x1f;
        result = new bytes(len);
        for (uint256 i; i < len; i++) {
            result[i] = data[off + i];
        }
        newOff = off + len;
    }
}
