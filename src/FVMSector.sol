// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {CBOR_CODEC} from "./FVMCodec.sol";
import {EXIT_SUCCESS} from "./FVMErrors.sol";
import {READONLY_FLAG} from "./FVMFlags.sol";
import {VALIDATE_SECTOR_STATUS, GET_NOMINAL_SECTOR_EXPIRATION} from "./FVMMethod.sol";
import {CALL_ACTOR_BY_ID} from "./FVMPrecompiles.sol";

/// @notice FIP-0112 SectorStatusCode
enum SectorStatus {
    Dead, // 0 — terminated or never committed
    Active, // 1 — not terminated, not faulty
    Faulty // 2 — live but currently faulty

}

// Sentinel values for (deadline, partition) when a sector is absent from the AMT.
int64 constant NO_DEADLINE = -1;
int64 constant NO_PARTITION = -1;

library FVMSector {
    /// @dev The miner actor returned a non-zero exit code for ValidateSectorStatus.
    error ValidateSectorStatusFailed(int256 exitCode);
    /// @dev The miner actor returned a non-zero exit code for GetNominalSectorExpiration.
    error GetNominalSectorExpirationFailed(int256 exitCode);

    /// @notice Calls ValidateSectorStatus on a miner actor without reverting on actor error.
    /// @param minerId The miner actor ID
    /// @param sector The sector number
    /// @param status The claimed sector status
    /// @param deadline Claimed deadline index, or NO_DEADLINE if sector is absent from the AMT
    /// @param partition Claimed partition index, or NO_PARTITION if sector is absent from the AMT
    /// @return ok Whether the call succeeded (exit code 0)
    /// @return valid Whether the claimed status matches the actual status; false if ok is false
    function tryValidateSectorStatus(
        uint64 minerId,
        uint64 sector,
        SectorStatus status,
        int64 deadline,
        int64 partition
    ) internal returns (bool ok, bool valid) {
        int256 exitCode;
        (exitCode, valid) = _validateSectorStatus(minerId, sector, status, deadline, partition);
        ok = exitCode == EXIT_SUCCESS;
        if (!ok) valid = false;
    }

    /// @notice Calls ValidateSectorStatus on a miner actor, reverting on actor error.
    /// @param minerId The miner actor ID
    /// @param sector The sector number
    /// @param status The claimed sector status
    /// @param deadline Claimed deadline index, or NO_DEADLINE if sector is absent from the AMT
    /// @param partition Claimed partition index, or NO_PARTITION if sector is absent from the AMT
    /// @return valid Whether the claimed status matches the actual status
    function validateSectorStatus(uint64 minerId, uint64 sector, SectorStatus status, int64 deadline, int64 partition)
        internal
        returns (bool valid)
    {
        int256 exitCode;
        (exitCode, valid) = _validateSectorStatus(minerId, sector, status, deadline, partition);
        require(exitCode == EXIT_SUCCESS, ValidateSectorStatusFailed(exitCode));
    }

    /// @notice Calls GetNominalSectorExpiration on a miner actor without reverting on actor error.
    /// @param minerId The miner actor ID
    /// @param sector The sector number
    /// @return ok Whether the call succeeded (exit code 0); false if the sector is absent
    /// @return expiration The nominal expiration epoch; 0 if ok is false
    function tryGetNominalSectorExpiration(uint64 minerId, uint64 sector)
        internal
        returns (bool ok, uint64 expiration)
    {
        int256 exitCode;
        (exitCode, expiration) = _getNominalSectorExpiration(minerId, sector);
        ok = exitCode == EXIT_SUCCESS;
        if (!ok) expiration = 0;
    }

    /// @notice Calls GetNominalSectorExpiration on a miner actor, reverting on actor error.
    /// @param minerId The miner actor ID
    /// @param sector The sector number
    /// @return expiration The nominal expiration epoch
    function getNominalSectorExpiration(uint64 minerId, uint64 sector) internal returns (uint64 expiration) {
        int256 exitCode;
        (exitCode, expiration) = _getNominalSectorExpiration(minerId, sector);
        require(exitCode == EXIT_SUCCESS, GetNominalSectorExpirationFailed(exitCode));
    }

    /// @dev Calls ValidateSectorStatus via CALL_ACTOR_BY_ID without allocating memory.
    function _validateSectorStatus(uint64 minerId, uint64 sector, SectorStatus status, int64 deadline, int64 partition)
        private
        returns (int256 exitCode, bool valid)
    {
        assembly ("memory-safe") {
            function writeCborUint64(ptr, v) -> newPtr {
                if lt(v, 24) {
                    mstore8(ptr, v)
                    newPtr := add(ptr, 1)
                    leave
                }
                if lt(v, 0x100) {
                    mstore(ptr, shl(240, or(0x1800, v))) // [0x18, v] at ptr+0..1
                    newPtr := add(ptr, 2)
                    leave
                }
                if lt(v, 0x10000) {
                    mstore(ptr, shl(232, or(0x190000, v))) // [0x19, hi, lo] at ptr+0..2
                    newPtr := add(ptr, 3)
                    leave
                }
                if lt(v, 0x100000000) {
                    mstore(ptr, shl(216, or(0x1a00000000, v))) // [0x1a, b3..b0] at ptr+0..4
                    newPtr := add(ptr, 5)
                    leave
                }
                // 5-byte form does not exist in CBOR; use 9-byte (1b + 8 bytes big-endian)
                mstore(ptr, or(shl(248, 0x1b), shl(184, v))) // [0x1b, b7..b0] at ptr+0..8
                newPtr := add(ptr, 9)
            }

            // deadline and partition are either non-negative indices or the -1 sentinel (NO_DEADLINE/NO_PARTITION)
            function writeCborInt64(ptr, v) -> newPtr {
                if slt(v, 0) {
                    // negative: only -1 is reachable; CBOR encoding of -1 is 0x20
                    mstore8(ptr, 0x20)
                    newPtr := add(ptr, 1)
                    leave
                }
                newPtr := writeCborUint64(ptr, v)
            }

            // Write call data
            let fmp := mload(0x40)
            mstore(fmp, VALIDATE_SECTOR_STATUS)
            mstore(add(fmp, 0x20), 0)
            mstore(add(fmp, 0x40), READONLY_FLAG)
            mstore(add(fmp, 0x60), CBOR_CODEC)
            mstore(add(fmp, 0x80), 0xc0) // params offset
            mstore(add(fmp, 0xa0), minerId)

            // Encode params CBOR [sector, status, aux_data]
            let p := add(fmp, 0xe0)
            mstore(p, 0) // clear the params slot
            mstore8(p, 0x83) // 3-element array
            p := add(p, 1)
            p := writeCborUint64(p, sector)
            mstore8(p, status)
            p := add(p, 1)
            // Reserve one byte for the CBOR bytes header; write inner array inline
            let bytesHeaderPtr := p
            p := add(p, 1)
            mstore8(p, 0x82) // inner 2-element array [deadline, partition]
            p := add(p, 1)
            p := writeCborInt64(p, deadline)
            p := writeCborInt64(p, partition)
            // Backfill the bytes header: innerLen ≤ 19 (1 + 9 + 9 max), so fits the CBOR 1-byte form (≤ 23)
            mstore8(bytesHeaderPtr, or(0x40, sub(p, add(bytesHeaderPtr, 1))))

            let paramsLen := sub(p, add(fmp, 0xe0))
            mstore(add(fmp, 0xc0), paramsLen)

            let ok := delegatecall(gas(), CALL_ACTOR_BY_ID, fmp, sub(p, fmp), 0, 32)

            exitCode := not(0) // sentinel -1: precompile failure

            if and(ok, gt(returndatasize(), 31)) {
                exitCode := mload(0)
                if iszero(exitCode) {
                    // retData first byte is at returndata offset 0x80 (after exitCode, codec, offset, length words)
                    if gt(returndatasize(), 128) {
                        returndatacopy(fmp, 128, 1)
                        valid := eq(byte(0, mload(fmp)), 0xf5)
                    }
                }
            }
        }
    }

    /// @dev Calls GetNominalSectorExpiration via CALL_ACTOR_BY_ID without allocating memory.
    /// ChainEpoch is i64 in the Filecoin type system but semantically a block height, so it is always non-negative.
    /// Builtin-actors never encodes a negative expiration.
    /// The decoder therefore only handles CBOR major type 0 (unsigned integer).
    function _getNominalSectorExpiration(uint64 minerId, uint64 sector)
        private
        returns (int256 exitCode, uint64 expiration)
    {
        assembly ("memory-safe") {
            function writeCborUint64(ptr, v) -> newPtr {
                if lt(v, 24) {
                    mstore8(ptr, v)
                    newPtr := add(ptr, 1)
                    leave
                }
                if lt(v, 0x100) {
                    mstore(ptr, shl(240, or(0x1800, v)))
                    newPtr := add(ptr, 2)
                    leave
                }
                if lt(v, 0x10000) {
                    mstore(ptr, shl(232, or(0x190000, v)))
                    newPtr := add(ptr, 3)
                    leave
                }
                if lt(v, 0x100000000) {
                    mstore(ptr, shl(216, or(0x1a00000000, v)))
                    newPtr := add(ptr, 5)
                    leave
                }
                mstore(ptr, or(shl(248, 0x1b), shl(184, v)))
                newPtr := add(ptr, 9)
            }

            let fmp := mload(0x40)
            mstore(fmp, GET_NOMINAL_SECTOR_EXPIRATION)
            mstore(add(fmp, 0x20), 0)
            mstore(add(fmp, 0x40), READONLY_FLAG)
            mstore(add(fmp, 0x60), CBOR_CODEC)
            mstore(add(fmp, 0x80), 0xc0) // params offset
            mstore(add(fmp, 0xa0), minerId)

            // Encode params: single CBOR uint64 (sector number)
            let p := add(fmp, 0xe0)
            mstore(p, 0)
            p := writeCborUint64(p, sector)

            let paramsLen := sub(p, add(fmp, 0xe0))
            mstore(add(fmp, 0xc0), paramsLen)

            let ok := delegatecall(gas(), CALL_ACTOR_BY_ID, fmp, sub(p, fmp), 0, 32)

            exitCode := not(0) // precompile failure

            if and(ok, gt(returndatasize(), 31)) {
                exitCode := mload(0)
                if iszero(exitCode) {
                    // retData first byte is at returndata offset 0x80 (after exitCode, codec, offset, length words)
                    if gt(returndatasize(), 128) {
                        returndatacopy(0, 128, 9) // read up to 9 bytes (max CBOR uint64 size)
                        // One load. CBOR is big-endian: data bytes sit immediately after the header.
                        // shl(8, w) discards the header byte, leaving data bytes at the MSB end.
                        // shr then extracts the desired width with no masking needed (shr zero-fills).
                        // ChainEpoch is always a non-negative block height → major type 0 only.
                        let w := mload(0)
                        let info := shr(248, w) // header byte; top 3 bits are 0 for major type 0
                        let data := shl(8, w)
                        let raw := info // inline value for info ≤ 23
                        switch info
                        case 24 { raw := shr(248, data) }
                        case 25 { raw := shr(240, data) }
                        case 26 { raw := shr(224, data) }
                        case 27 { raw := shr(192, data) }
                        expiration := raw
                    }
                }
            }
        }
    }
}
