// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {CBOR_CODEC} from "../FVMCodec.sol";
import {USR_ILLEGAL_ARGUMENT, USR_NOT_FOUND, USR_UNHANDLED_MESSAGE} from "../FVMErrors.sol";
import {SECTOR_CONTENT_CHANGED, VALIDATE_SECTOR_STATUS} from "../FVMMethod.sol";
import {
    FVMSectorContentChanged,
    SectorContentChangedParams,
    SectorContentChangedReturn
} from "../FVMSectorContentChanged.sol";

/// @notice FIP-0112 sector status codes. Matches builtin-actors SectorStatusCode wire order (Dead=0).
enum SectorStatus {
    Dead, // 0 – terminated or never committed
    Active, // 1 – not terminated, not faulty
    Faulty // 2 – live but currently faulty

}

/// @notice FIP-0112 sector location: deadline and partition indices within the miner state.
///         NO_DEADLINE / NO_PARTITION (-1) signals the sector is absent from the AMT (compacted).
struct SectorLocation {
    int64 deadline;
    int64 partition;
}

int64 constant NO_DEADLINE = -1;
int64 constant NO_PARTITION = -1;

/// @notice Mock miner actor for testing FIP-0109 SectorContentChanged notifications
/// @dev Etch this contract's code at a miner's masked ID address (0xff + 11 zeros + actorId)
/// via MockFVMTest.mockMiner(actorId). When it calls handle_filecoin_method on the target,
/// msg.sender will be the masked ID address, passing the receiver's isMinerActor() check.
contract FVMMinerActor {
    /// @notice Fallback for unknown ABI selectors.
    /// @dev The real miner is a native actor: it returns USR_UNHANDLED_MESSAGE for InvokeContract
    ///      (the method the EVM CALL opcode uses) rather than reverting.
    fallback() external {
        bytes memory response = abi.encode(uint32(USR_UNHANDLED_MESSAGE), uint64(0), bytes(""));
        assembly ("memory-safe") {
            return(add(response, 0x20), mload(response))
        }
    }

    // -------------------------------------------------------------------------
    // Mock state for ValidateSectorStatus (FIP-0112)
    // -------------------------------------------------------------------------

    /// @notice Mock sector statuses. Defaults to SectorStatus.Dead (0) for unmocked sectors.
    mapping(uint64 => SectorStatus) public sectorStatus;

    /// @notice Registered partition locations for Active/Faulty sectors.
    mapping(uint64 => SectorLocation) private _sectorLocation;
    mapping(uint64 => bool) private _hasLocation;

    /// @notice Set the mock status for a sector.
    function mockSectorStatus(uint64 sector, SectorStatus status) external {
        sectorStatus[sector] = status;
    }

    /// @notice Register the partition location for a sector (required for Active/Faulty sectors).
    function mockSectorLocation(uint64 sector, int64 deadline, int64 partition) external {
        _sectorLocation[sector] = SectorLocation(deadline, partition);
        _hasLocation[sector] = true;
    }

    // -------------------------------------------------------------------------
    // handle_filecoin_method — receives calls routed from FVMCallActorById.
    // Returns (exitCode, codec, data); never reverts for actor-level errors.
    // Matching the real FVM: CALL_ACTOR_BY_ID returns success=true with a
    // non-zero exit code on actor error, not a revert.
    // -------------------------------------------------------------------------

    function handle_filecoin_method(uint64 method, uint64 codec, bytes calldata params)
        external
        view
        returns (uint32, uint64, bytes memory)
    {
        if (method == VALIDATE_SECTOR_STATUS) {
            return _handleValidateSectorStatus(codec, params);
        }
        return (USR_UNHANDLED_MESSAGE, 0, "");
    }

    function _handleValidateSectorStatus(uint64 codec, bytes calldata params)
        internal
        view
        returns (uint32, uint64, bytes memory)
    {
        if (codec != CBOR_CODEC) return (USR_ILLEGAL_ARGUMENT, 0, "");
        // Params CBOR: [sector_number (uint64), status (uint8 0-2), aux_data (bytes)]
        if (params.length < 3 || uint8(params[0]) != 0x83) return (USR_ILLEGAL_ARGUMENT, 0, "");

        uint256 off;
        uint64 sector;
        (sector, off) = _decodeCborUint64(params, 1);

        // Status is an inline CBOR uint (0x00=Dead, 0x01=Active, 0x02=Faulty)
        uint8 statusByte = uint8(params[off++]);
        if (statusByte > 2) return (USR_ILLEGAL_ARGUMENT, 0, "");
        SectorStatus requested = SectorStatus(statusByte);

        // aux_data is a CBOR bytes field containing a CBOR-encoded SectorLocation tuple [deadline, partition]
        // _decodeAuxData may revert on truly malformed CBOR — that revert is caught by _handleMiner
        // and converted to USR_ILLEGAL_ARGUMENT.
        SectorLocation memory loc;
        (loc,) = _decodeAuxData(params, off);

        // Mixed NO/non-NO location is always an illegal argument
        bool noDeadline = loc.deadline == NO_DEADLINE;
        bool noPartition = loc.partition == NO_PARTITION;
        if (noDeadline != noPartition) return (USR_ILLEGAL_ARGUMENT, 0, "");

        SectorStatus current = sectorStatus[sector];

        if (noDeadline) {
            // (NO_DEADLINE, NO_PARTITION): valid only for sectors absent from the AMT (Dead).
            // Active/Faulty sectors are in the AMT — cannot determine status without a real location.
            if (current != SectorStatus.Dead) return (USR_NOT_FOUND, 0, "");
        } else {
            // Normal location: sector must be registered at (deadline, partition).
            if (!_hasLocation[sector]) return (USR_NOT_FOUND, 0, "");
            SectorLocation storage registered = _sectorLocation[sector];
            if (registered.deadline != loc.deadline || registered.partition != loc.partition) {
                return (USR_NOT_FOUND, 0, "");
            }
        }

        bool valid = current == requested;
        bytes memory retCbor = abi.encodePacked(valid ? uint8(0xf5) : uint8(0xf4));
        return (0, CBOR_CODEC, retCbor);
    }

    // -------------------------------------------------------------------------
    // CBOR helpers — these revert on malformed input (programming errors in tests)
    // -------------------------------------------------------------------------

    /// @dev Decode a CBOR bytes field from `data` at `offset`, then parse its content as
    ///      a 2-element SectorLocation tuple [deadline: i64, partition: i64].
    function _decodeAuxData(bytes calldata data, uint256 offset)
        private
        pure
        returns (SectorLocation memory loc, uint256 newOffset)
    {
        // Consume the CBOR bytes header to get the inner bytes slice
        uint8 b = uint8(data[offset++]);
        require((b >> 5) == 2, "FVMMinerActor: aux_data: expected CBOR bytes");
        uint8 info = b & 0x1f;
        uint256 len;
        if (info <= 23) {
            len = info;
        } else if (info == 24) {
            len = uint8(data[offset++]);
        } else if (info == 25) {
            len = (uint256(uint8(data[offset])) << 8) | uint256(uint8(data[offset + 1]));
            offset += 2;
        } else {
            revert("FVMMinerActor: aux_data: bytes too long");
        }
        newOffset = offset + len;
        bytes calldata inner = data[offset:offset + len];

        // Parse inner CBOR: [deadline: i64, partition: i64]
        require(inner.length >= 3 && uint8(inner[0]) == 0x82, "FVMMinerActor: aux_data: expected 2-element array");
        uint256 innerOff;
        (loc.deadline, innerOff) = _decodeCborInt64(inner, 1);
        (loc.partition,) = _decodeCborInt64(inner, innerOff);
    }

    /// @dev Decode a CBOR-encoded signed int64 from `data` at `offset` (major type 0 or 1).
    function _decodeCborInt64(bytes calldata data, uint256 offset) private pure returns (int64 v, uint256 newOffset) {
        uint8 b = uint8(data[offset++]);
        uint8 major = b >> 5;
        require(major <= 1, "FVMMinerActor: expected CBOR int");
        uint8 info = b & 0x1f;
        uint64 raw;
        if (info <= 23) {
            raw = uint64(info);
            newOffset = offset;
        } else if (info == 24) {
            raw = uint64(uint8(data[offset]));
            newOffset = offset + 1;
        } else if (info == 25) {
            raw = (uint64(uint8(data[offset])) << 8) | uint64(uint8(data[offset + 1]));
            newOffset = offset + 2;
        } else if (info == 26) {
            raw = (uint64(uint8(data[offset])) << 24) | (uint64(uint8(data[offset + 1])) << 16)
                | (uint64(uint8(data[offset + 2])) << 8) | uint64(uint8(data[offset + 3]));
            newOffset = offset + 4;
        } else if (info == 27) {
            for (uint256 i = 0; i < 8; i++) {
                raw = (raw << 8) | uint64(uint8(data[offset + i]));
            }
            newOffset = offset + 8;
        } else {
            revert("FVMMinerActor: int too large");
        }
        v = major == 0 ? int64(raw) : -1 - int64(raw);
    }

    /// @dev Decode a CBOR-encoded uint64 from calldata at `offset`
    function _decodeCborUint64(bytes calldata data, uint256 offset)
        private
        pure
        returns (uint64 v, uint256 newOffset)
    {
        uint8 b = uint8(data[offset++]);
        require((b >> 5) == 0, "FVMMinerActor: expected CBOR uint");
        uint8 info = b & 0x1f;
        if (info <= 23) return (uint64(info), offset);
        if (info == 24) return (uint64(uint8(data[offset])), offset + 1);
        if (info == 25) {
            v = (uint64(uint8(data[offset])) << 8) | uint64(uint8(data[offset + 1]));
            return (v, offset + 2);
        }
        if (info == 26) {
            v = (uint64(uint8(data[offset])) << 24) | (uint64(uint8(data[offset + 1])) << 16)
                | (uint64(uint8(data[offset + 2])) << 8) | uint64(uint8(data[offset + 3]));
            return (v, offset + 4);
        }
        if (info == 27) {
            for (uint256 i = 0; i < 8; i++) {
                v = (v << 8) | uint64(uint8(data[offset + i]));
            }
            return (v, offset + 8);
        }
        revert("FVMMinerActor: uint64 too large");
    }

    // -------------------------------------------------------------------------
    // callSectorContentChanged — simulate the miner actor calling handle_filecoin_method on the target contract
    // -------------------------------------------------------------------------

    /// @param target The contract implementing handle_filecoin_method
    /// @param params The notification parameters
    /// @return ret The decoded return value from the target contract
    function callSectorContentChanged(address target, SectorContentChangedParams memory params)
        external
        returns (SectorContentChangedReturn memory ret)
    {
        bytes memory encoded = FVMSectorContentChanged.encodeParams(params);

        (bool success, bytes memory returnData) = target.call(
            abi.encodeWithSignature(
                "handle_filecoin_method(uint64,uint64,bytes)", SECTOR_CONTENT_CHANGED, CBOR_CODEC, encoded
            )
        );
        require(success, "FVMMinerActor: handle_filecoin_method reverted");

        (uint32 exitCode,, bytes memory retData) = abi.decode(returnData, (uint32, uint64, bytes));
        require(exitCode == 0, "FVMMinerActor: non-zero exit code");

        if (retData.length > 0) {
            ret = FVMSectorContentChanged.decodeReturn(retData);
        }
    }
}
