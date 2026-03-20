// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {FVMMinerActor, SectorStatus, NO_DEADLINE, NO_PARTITION} from "../src/mocks/FVMMinerActor.sol";
import {CBOR_CODEC} from "../src/FVMCodec.sol";
import {USR_ILLEGAL_ARGUMENT, USR_NOT_FOUND} from "../src/FVMErrors.sol";
import {READONLY_FLAG} from "../src/FVMFlags.sol";
import {VALIDATE_SECTOR_STATUS} from "../src/FVMMethod.sol";
import {CALL_ACTOR_BY_ID} from "../src/FVMPrecompiles.sol";

// =============================================================
//                          TESTS
// =============================================================

/// @notice Tests for FIP-0112 ValidateSectorStatus mock.
///         Test cases mirror the spec: https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0112.md#test-cases
///
///         All calls go through CALL_ACTOR_BY_ID — matching real FVM behaviour where actor errors
///         are returned as non-zero exit codes (success=true from the precompile), not reverts.
contract ValidateSectorStatusTest is MockFVMTest {
    uint64 constant MINER_ID = 1234;
    uint64 constant SECTOR = 42;
    int64 constant DEADLINE = 3;
    int64 constant PARTITION = 7;

    FVMMinerActor miner;

    function setUp() public override {
        super.setUp();
        miner = mockMiner(MINER_ID);
    }

    // -------------------------------------------------------------------------
    // Happy paths — returns valid=true
    // -------------------------------------------------------------------------

    // FIP: "ValidateSectorStatus returns true when declaring a Dead sector with (NO_DEADLINE, NO_PARTITION) location as Dead"
    function testDeadSector_NoLocation_Dead_True() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Dead);
        assertTrue(_validate(SECTOR, SectorStatus.Dead, NO_DEADLINE, NO_PARTITION));
    }

    // FIP: "ValidateSectorStatus returns true when declaring a Dead sector with a location as true"
    // (Dead sector terminated but not yet compacted — still has a real partition location)
    function testDeadSector_WithLocation_Dead_True() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Dead);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        assertTrue(_validate(SECTOR, SectorStatus.Dead, DEADLINE, PARTITION));
    }

    // FIP: "ValidateSectorStatus returns true when declaring an Active sector as Active"
    function testActiveSector_WithLocation_Active_True() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Active);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        assertTrue(_validate(SECTOR, SectorStatus.Active, DEADLINE, PARTITION));
    }

    // FIP: "ValidateSectorStatus returns true when declaring a Faulty sector Faulty"
    function testFaultySector_WithLocation_Faulty_True() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Faulty);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        assertTrue(_validate(SECTOR, SectorStatus.Faulty, DEADLINE, PARTITION));
    }

    // -------------------------------------------------------------------------
    // Wrong status — returns valid=false (exit code 0, valid=false in payload)
    // -------------------------------------------------------------------------

    // FIP: "ValidateSectorStatus returns false when declaring an Active sector Dead"
    function testActiveSector_Dead_False() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Active);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        assertFalse(_validate(SECTOR, SectorStatus.Dead, DEADLINE, PARTITION));
    }

    // FIP: "ValidateSectorStatus returns false when declaring a Dead sector Active"
    function testDeadSector_Active_False() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Dead);
        assertFalse(_validate(SECTOR, SectorStatus.Active, NO_DEADLINE, NO_PARTITION));
    }

    // FIP: "ValidateSectorStatus returns false when declaring a Faulty sector Active"
    function testFaultySector_Active_False() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Faulty);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        assertFalse(_validate(SECTOR, SectorStatus.Active, DEADLINE, PARTITION));
    }

    // FIP: "ValidateSectorStatus returns false when declaring a Faulty sector Dead"
    function testFaultySector_Dead_False() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Faulty);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        assertFalse(_validate(SECTOR, SectorStatus.Dead, DEADLINE, PARTITION));
    }

    // FIP: "ValidateSectorStatus returns false when declaring a Dead sector Faulty"
    function testDeadSector_Faulty_False() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Dead);
        assertFalse(_validate(SECTOR, SectorStatus.Faulty, NO_DEADLINE, NO_PARTITION));
    }

    // FIP: "ValidateSectorStatus returns false when declaring an Active sector Faulty"
    function testActiveSector_Faulty_False() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Active);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        assertFalse(_validate(SECTOR, SectorStatus.Faulty, DEADLINE, PARTITION));
    }

    // -------------------------------------------------------------------------
    // Error cases — precompile returns success=true but non-zero exit code
    // -------------------------------------------------------------------------

    // FIP: "ValidateSectorStatus fails with bad location" — wrong coordinates
    function testBadLocation_WrongDeadline_ReturnsNotFound() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Active);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        assertEq(_exitCode(SECTOR, SectorStatus.Active, DEADLINE + 1, PARTITION), int256(uint256(USR_NOT_FOUND)));
    }

    // FIP: "ValidateSectorStatus fails with bad location" — no location registered for live sector
    function testBadLocation_NoLocationRegistered_ReturnsNotFound() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Active);
        // no mockSectorLocation called
        assertEq(_exitCode(SECTOR, SectorStatus.Active, DEADLINE, PARTITION), int256(uint256(USR_NOT_FOUND)));
    }

    // Active sector + (NO_DEADLINE, NO_PARTITION): cannot determine status without a location
    function testActiveSector_NoLocation_ReturnsNotFound() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Active);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        assertEq(_exitCode(SECTOR, SectorStatus.Active, NO_DEADLINE, NO_PARTITION), int256(uint256(USR_NOT_FOUND)));
    }

    // Faulty sector + (NO_DEADLINE, NO_PARTITION): likewise an error
    function testFaultySector_NoLocation_ReturnsNotFound() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Faulty);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        assertEq(_exitCode(SECTOR, SectorStatus.Faulty, NO_DEADLINE, NO_PARTITION), int256(uint256(USR_NOT_FOUND)));
    }

    // Mixing NO and non-NO is always an illegal argument
    function testMixedNoLocation_ReturnsIllegalArgument() public {
        assertEq(_exitCode(SECTOR, SectorStatus.Active, NO_DEADLINE, PARTITION), int256(uint256(USR_ILLEGAL_ARGUMENT)));
    }

    // Malformed aux_data (not a CBOR bytes field) — miner reverts; _handleMiner converts to USR_ILLEGAL_ARGUMENT
    function testMalformedAuxData_ReturnsIllegalArgument() public {
        // 0xff is a CBOR break token, not valid as a bytes field header
        bytes memory badParams = _encodeParamsRaw(SECTOR, SectorStatus.Active, hex"ff");
        (bool precompileSuccess, int256 exitCode,) = _callRaw(badParams);
        assertTrue(precompileSuccess, "precompile must not revert on actor errors");
        assertEq(exitCode, int256(uint256(USR_ILLEGAL_ARGUMENT)));
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    /// @dev Call ValidateSectorStatus through the precompile and return (precompileSuccess, exitCode, retData).
    ///      The precompile must always return success=true (matching real FVM — actor errors are exit codes).
    function _callRaw(bytes memory params)
        internal
        returns (bool precompileSuccess, int256 exitCode, bytes memory retData)
    {
        bytes memory callData = abi.encode(
            uint64(VALIDATE_SECTOR_STATUS),
            uint256(0),
            uint64(READONLY_FLAG),
            uint64(CBOR_CODEC),
            params,
            uint64(MINER_ID)
        );
        bytes memory ret;
        (precompileSuccess, ret) = CALL_ACTOR_BY_ID.call(callData);
        if (precompileSuccess && ret.length > 0) {
            (exitCode,, retData) = abi.decode(ret, (int256, uint64, bytes));
        }
    }

    /// @dev Encode params, call through the precompile, assert exit code = 0, return the CBOR bool.
    function _validate(uint64 sector, SectorStatus status, int64 deadline, int64 partition) internal returns (bool) {
        bytes memory params = _encodeParams(sector, status, deadline, partition);
        (bool precompileSuccess, int256 exitCode, bytes memory retData) = _callRaw(params);
        assertTrue(precompileSuccess, "precompile must not revert");
        assertEq(exitCode, 0, "expected success exit code");
        return uint8(retData[0]) == 0xf5;
    }

    /// @dev Encode params, call through the precompile, return the exit code (expects non-zero for error cases).
    function _exitCode(uint64 sector, SectorStatus status, int64 deadline, int64 partition)
        internal
        returns (int256 exitCode)
    {
        bytes memory params = _encodeParams(sector, status, deadline, partition);
        bool precompileSuccess;
        (precompileSuccess, exitCode,) = _callRaw(params);
        assertTrue(precompileSuccess, "precompile must not revert");
    }

    /// @dev CBOR-encode ValidateSectorStatusParams: [sector, status, aux_data_bytes]
    ///      where aux_data_bytes wraps the inner SectorLocation CBOR [deadline, partition].
    function _encodeParams(uint64 sector, SectorStatus status, int64 deadline, int64 partition)
        internal
        pure
        returns (bytes memory)
    {
        bytes memory locCbor = abi.encodePacked(uint8(0x82), _encodeCborInt64(deadline), _encodeCborInt64(partition));
        return _encodeParamsRaw(sector, status, _encodeCborBytes(locCbor));
    }

    /// @dev Build params with a pre-encoded aux_data field (used for error-case testing).
    function _encodeParamsRaw(uint64 sector, SectorStatus status, bytes memory auxDataField)
        internal
        pure
        returns (bytes memory)
    {
        return abi.encodePacked(uint8(0x83), _encodeCborUint64(sector), uint8(uint256(status)), auxDataField);
    }

    function _encodeCborBytes(bytes memory data) internal pure returns (bytes memory) {
        uint256 len = data.length;
        if (len <= 23) return abi.encodePacked(uint8(0x40 | uint8(len)), data);
        if (len <= 0xff) return abi.encodePacked(uint8(0x58), uint8(len), data);
        revert("_encodeCborBytes: too long");
    }

    function _encodeCborUint64(uint64 v) internal pure returns (bytes memory) {
        if (v <= 23) return abi.encodePacked(uint8(v));
        if (v <= 0xff) return abi.encodePacked(uint8(0x18), uint8(v));
        if (v <= 0xffff) return abi.encodePacked(uint8(0x19), uint16(v));
        if (v <= 0xffffffff) return abi.encodePacked(uint8(0x1a), uint32(v));
        return abi.encodePacked(uint8(0x1b), v);
    }

    function _encodeCborInt64(int64 v) internal pure returns (bytes memory) {
        if (v >= 0) return _encodeCborUint64(uint64(v));
        // negative: CBOR major type 1, value = -1 - v
        uint64 raw = uint64(-1 - v);
        if (raw <= 23) return abi.encodePacked(uint8(0x20 | uint8(raw)));
        if (raw <= 0xff) return abi.encodePacked(uint8(0x38), uint8(raw));
        if (raw <= 0xffff) return abi.encodePacked(uint8(0x39), uint16(raw));
        if (raw <= 0xffffffff) return abi.encodePacked(uint8(0x3a), uint32(raw));
        return abi.encodePacked(uint8(0x3b), raw);
    }
}
