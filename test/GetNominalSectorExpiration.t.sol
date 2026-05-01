// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {FVMMinerActor, SectorStatus} from "../src/mocks/FVMMinerActor.sol";
import {USR_NOT_FOUND} from "../src/FVMErrors.sol";
import {FVMSector} from "../src/FVMSector.sol";

// =============================================================
//                          HELPERS
// =============================================================

/// @dev External wrapper so vm.expectRevert targets the outer call, not the
///      internal `call` opcode to CALL_ACTOR_BY_ID inside the library.
contract GetNominalSectorExpirationCaller {
    function getNominalSectorExpiration(uint64 minerId, uint64 sector) external returns (uint64) {
        return FVMSector.getNominalSectorExpiration(minerId, sector);
    }
}

// =============================================================
//                          TESTS
// =============================================================

/// @notice Tests for FIP-0112 GetNominalSectorExpiration.
///         Spec: https://github.com/filecoin-project/FIPs/blob/master/FIPS/fip-0112.md#getnominalsectorexpiration
contract GetNominalSectorExpirationTest is MockFVMTest {
    using FVMSector for uint64;

    GetNominalSectorExpirationCaller caller;

    uint64 constant MINER_ID = 1234;
    uint64 constant SECTOR = 42;

    FVMMinerActor miner;

    function setUp() public override {
        super.setUp();
        miner = mockMiner(MINER_ID);
        caller = new GetNominalSectorExpirationCaller();
    }

    // -------------------------------------------------------------------------
    // tryGetNominalSectorExpiration
    // -------------------------------------------------------------------------

    // FIP: "GetNominalSectorExpiration retrieves the stable expiration epoch for a specified sector"
    function testTry_KnownSector_ReturnsEpoch() public {
        miner.mockSectorExpiration(SECTOR, 100000);
        (bool ok, uint64 expiration) = MINER_ID.tryGetNominalSectorExpiration(SECTOR);
        assertTrue(ok);
        assertEq(expiration, 100000);
    }

    // FIP: "The method fails when the sector is absent from the sectors AMT"
    function testTry_UnknownSector_NotOk() public {
        (bool ok, uint64 expiration) = MINER_ID.tryGetNominalSectorExpiration(SECTOR);
        assertFalse(ok);
        assertEq(expiration, 0);
    }

    // mockSector convenience: set status + location + expiration in one call
    function testTry_MockSector_ReturnsEpoch() public {
        miner.mockSector(SECTOR, SectorStatus.Active, 3, 7, 999999);
        (bool ok, uint64 expiration) = MINER_ID.tryGetNominalSectorExpiration(SECTOR);
        assertTrue(ok);
        assertEq(expiration, 999999);
    }

    // -------------------------------------------------------------------------
    // getNominalSectorExpiration — strict variant
    // -------------------------------------------------------------------------

    function testGet_KnownSector_ReturnsEpoch() public {
        miner.mockSectorExpiration(SECTOR, 3456789);
        assertEq(MINER_ID.getNominalSectorExpiration(SECTOR), 3456789);
    }

    function testGet_UnknownSector_Reverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(FVMSector.GetNominalSectorExpirationFailed.selector, int256(uint256(USR_NOT_FOUND)))
        );
        caller.getNominalSectorExpiration(MINER_ID, SECTOR);
    }

    // -------------------------------------------------------------------------
    // ChainEpoch CBOR encoding/decoding branch coverage
    // The mock encodes the epoch; the library assembly decodes it.
    // branch 1: epoch ≤ 23           — 1-byte inline
    // branch 2: 24 ≤ epoch ≤ 0xff    — 0x18 + uint8
    // branch 3: epoch ≤ 0xffff       — 0x19 + uint16
    // branch 4: epoch ≤ 0xffffffff   — 0x1a + uint32
    // branch 5: epoch > 0xffffffff   — 0x1b + uint64
    // -------------------------------------------------------------------------

    function _roundtrip(uint64 epoch) internal returns (uint64) {
        miner.mockSectorExpiration(SECTOR, epoch);
        (bool ok, uint64 got) = MINER_ID.tryGetNominalSectorExpiration(SECTOR);
        assertTrue(ok);
        return got;
    }

    function testEpochEncoding_Inline_Zero() public {
        assertEq(_roundtrip(0), 0);
    }

    function testEpochEncoding_Inline_Max() public {
        assertEq(_roundtrip(23), 23);
    }

    function testEpochEncoding_1Byte_Min() public {
        assertEq(_roundtrip(24), 24);
    }

    function testEpochEncoding_1Byte_Max() public {
        assertEq(_roundtrip(0xff), 0xff);
    }

    function testEpochEncoding_2Byte_Min() public {
        assertEq(_roundtrip(0x100), 0x100);
    }

    function testEpochEncoding_2Byte_Max() public {
        assertEq(_roundtrip(0xffff), 0xffff);
    }

    function testEpochEncoding_4Byte_Min() public {
        assertEq(_roundtrip(0x10000), 0x10000);
    }

    function testEpochEncoding_4Byte_Max() public {
        assertEq(_roundtrip(0xffffffff), 0xffffffff);
    }

    function testEpochEncoding_8Byte_Min() public {
        assertEq(_roundtrip(0x100000000), 0x100000000);
    }

    function testEpochEncoding_8Byte_Max() public {
        assertEq(_roundtrip(type(uint64).max), type(uint64).max);
    }
}
