// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {FVMMinerActor} from "../src/mocks/FVMMinerActor.sol";
import {FVMSector, SectorStatus, NO_DEADLINE, NO_PARTITION} from "../src/FVMSector.sol";
import {USR_NOT_FOUND, USR_ILLEGAL_ARGUMENT} from "../src/FVMErrors.sol";

/// @dev External wrapper so vm.expectRevert targets the outer call, not the
///      internal `call` opcode to CALL_ACTOR_BY_ID inside the library.
contract SectorCaller {
    function validateSectorStatus(uint64 minerId, uint64 sector, SectorStatus status, int64 deadline, int64 partition)
        external
        returns (bool)
    {
        return FVMSector.validateSectorStatus(minerId, sector, status, deadline, partition);
    }
}

contract SectorTest is MockFVMTest {
    using FVMSector for uint64;

    SectorCaller caller;

    uint64 constant MINER_ID = 1234;
    uint64 constant SECTOR = 42;
    int64 constant DEADLINE = 3;
    int64 constant PARTITION = 7;

    FVMMinerActor miner;

    function setUp() public override {
        super.setUp();
        miner = mockMiner(MINER_ID);
        caller = new SectorCaller();
    }

    // -------------------------------------------------------------------------
    // tryValidateSectorStatus — (ok=true, valid=true)
    // -------------------------------------------------------------------------

    function testTry_DeadSector_NoLocation_Dead() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Dead);
        (bool ok, bool valid) = MINER_ID.tryValidateSectorStatus(SECTOR, SectorStatus.Dead, NO_DEADLINE, NO_PARTITION);
        assertTrue(ok);
        assertTrue(valid);
    }

    function testTry_DeadSector_WithLocation_Dead() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Dead);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        (bool ok, bool valid) = MINER_ID.tryValidateSectorStatus(SECTOR, SectorStatus.Dead, DEADLINE, PARTITION);
        assertTrue(ok);
        assertTrue(valid);
    }

    function testTry_ActiveSector_Active() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Active);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        (bool ok, bool valid) = MINER_ID.tryValidateSectorStatus(SECTOR, SectorStatus.Active, DEADLINE, PARTITION);
        assertTrue(ok);
        assertTrue(valid);
    }

    function testTry_FaultySector_Faulty() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Faulty);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        (bool ok, bool valid) = MINER_ID.tryValidateSectorStatus(SECTOR, SectorStatus.Faulty, DEADLINE, PARTITION);
        assertTrue(ok);
        assertTrue(valid);
    }

    // -------------------------------------------------------------------------
    // tryValidateSectorStatus — (ok=true, valid=false) wrong status
    // -------------------------------------------------------------------------

    function testTry_ActiveSector_Dead_False() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Active);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        (bool ok, bool valid) = MINER_ID.tryValidateSectorStatus(SECTOR, SectorStatus.Dead, DEADLINE, PARTITION);
        assertTrue(ok);
        assertFalse(valid);
    }

    function testTry_FaultySector_Active_False() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Faulty);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        (bool ok, bool valid) = MINER_ID.tryValidateSectorStatus(SECTOR, SectorStatus.Active, DEADLINE, PARTITION);
        assertTrue(ok);
        assertFalse(valid);
    }

    function testTry_DeadSector_NoLocation_ActiveRequest_False() public {
        // Sector absent from AMT (Dead) + NO_DEADLINE: returns false for Active/Faulty requests
        (bool ok, bool valid) = MINER_ID.tryValidateSectorStatus(SECTOR, SectorStatus.Active, NO_DEADLINE, NO_PARTITION);
        assertTrue(ok);
        assertFalse(valid);
    }

    // -------------------------------------------------------------------------
    // tryValidateSectorStatus — (ok=false) actor error
    // -------------------------------------------------------------------------

    function testTry_BadLocation_ReturnsNotOk() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Active);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        (bool ok,) = MINER_ID.tryValidateSectorStatus(SECTOR, SectorStatus.Active, DEADLINE + 1, PARTITION);
        assertFalse(ok);
    }

    function testTry_MixedNoLocation_ReturnsNotOk() public {
        (bool ok,) = MINER_ID.tryValidateSectorStatus(SECTOR, SectorStatus.Active, NO_DEADLINE, PARTITION);
        assertFalse(ok);
    }

    function testTry_ActiveSector_NoLocation_ReturnsNotOk() public {
        // Active sector exists in AMT — cannot validate without a real location
        miner.mockSectorStatus(SECTOR, SectorStatus.Active);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        (bool ok,) = MINER_ID.tryValidateSectorStatus(SECTOR, SectorStatus.Active, NO_DEADLINE, NO_PARTITION);
        assertFalse(ok);
    }

    // -------------------------------------------------------------------------
    // validateSectorStatus — success
    // -------------------------------------------------------------------------

    function testValidate_ActiveSector_Active() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Active);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        assertTrue(MINER_ID.validateSectorStatus(SECTOR, SectorStatus.Active, DEADLINE, PARTITION));
    }

    function testValidate_ActiveSector_Dead_False() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Active);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        assertFalse(MINER_ID.validateSectorStatus(SECTOR, SectorStatus.Dead, DEADLINE, PARTITION));
    }

    // -------------------------------------------------------------------------
    // writeCborUint64 branch coverage (sector number drives the encoding)
    // branch 1: v ≤ 23         — 1 byte inline
    // branch 2: 24 ≤ v ≤ 0xff  — 0x18 + uint8   (covered by SECTOR=42 above)
    // branch 3: v ≤ 0xffff     — 0x19 + uint16
    // branch 4: v ≤ 0xffffffff — 0x1a + uint32
    // branch 5: v > 0xffffffff — 0x1b + uint64
    // -------------------------------------------------------------------------

    function _registerAndValidate(uint64 sector) internal {
        miner.mockSectorStatus(sector, SectorStatus.Active);
        miner.mockSectorLocation(sector, DEADLINE, PARTITION);
        (bool ok, bool valid) = MINER_ID.tryValidateSectorStatus(sector, SectorStatus.Active, DEADLINE, PARTITION);
        assertTrue(ok);
        assertTrue(valid);
    }

    function testSectorEncoding_1Byte_Zero() public {
        _registerAndValidate(0);
    }

    function testSectorEncoding_1Byte_Max() public {
        _registerAndValidate(23);
    }

    function testSectorEncoding_3Byte_Min() public {
        _registerAndValidate(256);
    }

    function testSectorEncoding_3Byte_Max() public {
        _registerAndValidate(0xffff);
    }

    function testSectorEncoding_5Byte_Min() public {
        _registerAndValidate(0x10000);
    }

    function testSectorEncoding_5Byte_Max() public {
        _registerAndValidate(0xffffffff);
    }

    function testSectorEncoding_9Byte_Min() public {
        _registerAndValidate(0x100000000);
    }

    function testSectorEncoding_9Byte_Max() public {
        _registerAndValidate(type(uint64).max);
    }

    // -------------------------------------------------------------------------
    // validateSectorStatus — reverts on actor error
    // -------------------------------------------------------------------------

    function testValidate_BadLocation_Reverts() public {
        miner.mockSectorStatus(SECTOR, SectorStatus.Active);
        miner.mockSectorLocation(SECTOR, DEADLINE, PARTITION);
        vm.expectRevert(
            abi.encodeWithSelector(FVMSector.ValidateSectorStatusFailed.selector, int256(uint256(USR_NOT_FOUND)))
        );
        caller.validateSectorStatus(MINER_ID, SECTOR, SectorStatus.Active, DEADLINE + 1, PARTITION);
    }

    function testValidate_MixedNoLocation_Reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(FVMSector.ValidateSectorStatusFailed.selector, int256(uint256(USR_ILLEGAL_ARGUMENT)))
        );
        caller.validateSectorStatus(MINER_ID, SECTOR, SectorStatus.Active, NO_DEADLINE, PARTITION);
    }
}
