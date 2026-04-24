// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../../src/mocks/MockFVMTest.sol";
import {FVMMinerActor} from "../../src/mocks/FVMMinerActor.sol";
import {FVMMiner} from "../../src/FVMMiner.sol";
import {FVMAddress} from "../../src/FVMAddress.sol";
import {USR_NOT_FOUND} from "../../src/FVMErrors.sol";

// =============================================================
//                          HELPERS
// =============================================================

/// @dev External wrapper so vm.expectRevert targets the outer call, not the
///      internal `call` opcode to CALL_ACTOR_BY_ID inside the library.
contract GetOwnerCaller {
    function getOwner(uint64 minerId) external returns (bytes memory owner) {
        return FVMMiner.getOwner(minerId);
    }

    function getOwnerAddress(uint64 minerId) external returns (address owner) {
        return FVMMiner.getOwnerAddress(minerId);
    }
}

// =============================================================
//                          TESTS
// =============================================================

contract GetOwnerTest is MockFVMTest {
    uint64 constant MINER_ID = 1234;

    // f0 ID addresses — the only format a real miner owner can have (resolved at creation/change time)
    uint64 constant OWNER_ID = 1000;
    uint64 constant OTHER_ID = 2000;
    bytes constant OWNER_ADDR = abi.encodePacked(uint8(0x00), uint8(0xe8), uint8(0x07)); // ULEB128(1000)
    bytes constant OTHER_ADDR = abi.encodePacked(uint8(0x00), uint8(0xd0), uint8(0x0f)); // ULEB128(2000)

    FVMMinerActor miner;
    GetOwnerCaller caller;

    function setUp() public override {
        super.setUp();
        miner = mockMiner(MINER_ID);
        caller = new GetOwnerCaller();
    }

    // -------------------------------------------------------------------------
    // tryGetOwner
    // -------------------------------------------------------------------------

    function testTry_MockedOwner_ReturnsOwner() public {
        miner.mockOwner(OWNER_ID);
        (bool ok, bytes memory owner) = FVMMiner.tryGetOwner(MINER_ID);
        assertTrue(ok);
        assertEq(owner, OWNER_ADDR);
        (bool addrOk, address ownerAddr) = FVMMiner.tryGetOwnerAddress(MINER_ID);
        assertTrue(addrOk);
        assertEq(ownerAddr, FVMAddress.maskedAddress(OWNER_ID));
        (bool idOk, uint64 ownerId) = FVMMiner.tryGetOwnerActorId(MINER_ID);
        assertTrue(idOk);
        assertEq(ownerId, OWNER_ID);
    }

    function testTry_WithProposed_ReturnsOwnerOnly() public {
        miner.mockOwnerWithProposed(OWNER_ID, OTHER_ID);
        (bool ok, bytes memory owner) = FVMMiner.tryGetOwner(MINER_ID);
        assertTrue(ok);
        assertEq(owner, OWNER_ADDR);
        (bool addrOk, address ownerAddr) = FVMMiner.tryGetOwnerAddress(MINER_ID);
        assertTrue(addrOk);
        assertEq(ownerAddr, FVMAddress.maskedAddress(OWNER_ID));
        (bool idOk, uint64 ownerId) = FVMMiner.tryGetOwnerActorId(MINER_ID);
        assertTrue(idOk);
        assertEq(ownerId, OWNER_ID);
    }

    function testTry_NoOwnerMocked_NotOk() public {
        (bool ok, bytes memory owner) = FVMMiner.tryGetOwner(MINER_ID);
        assertFalse(ok);
        assertEq(owner.length, 0);
    }

    function testTry_UnregisteredMiner_NotOk() public {
        (bool ok,) = FVMMiner.tryGetOwner(9999);
        assertFalse(ok);
    }

    // -------------------------------------------------------------------------
    // getOwner — strict variant
    // -------------------------------------------------------------------------

    function testGet_MockedOwner_ReturnsOwner() public {
        miner.mockOwner(OWNER_ID);
        bytes memory owner = FVMMiner.getOwner(MINER_ID);
        assertEq(owner, OWNER_ADDR);
        assertEq(FVMMiner.getOwnerAddress(MINER_ID), FVMAddress.maskedAddress(OWNER_ID));
        assertEq(FVMMiner.getOwnerActorId(MINER_ID), OWNER_ID);
    }

    function testGet_WithProposed_ReturnsOwnerOnly() public {
        miner.mockOwnerWithProposed(OWNER_ID, OTHER_ID);
        bytes memory owner = FVMMiner.getOwner(MINER_ID);
        assertEq(owner, OWNER_ADDR);
        assertEq(FVMMiner.getOwnerAddress(MINER_ID), FVMAddress.maskedAddress(OWNER_ID));
        assertEq(FVMMiner.getOwnerActorId(MINER_ID), OWNER_ID);
    }

    function testGet_NoOwnerMocked_Reverts() public {
        vm.expectRevert(abi.encodeWithSelector(FVMMiner.GetOwnerFailed.selector, int256(uint256(USR_NOT_FOUND))));
        caller.getOwner(MINER_ID);
    }

    // -------------------------------------------------------------------------
    // CBOR encoding branch coverage for f0 address sizes
    // -------------------------------------------------------------------------

    function _roundtrip(uint64 actorId) internal returns (bytes memory) {
        miner.mockOwner(actorId);
        (bool ok, bytes memory owner) = FVMMiner.tryGetOwner(MINER_ID);
        assertTrue(ok);
        return owner;
    }

    // f0 actor 1: single-byte ULEB128, inline CBOR length (≤ 23 bytes)
    function testAddressEncoding_Short() public {
        bytes memory got = _roundtrip(1);
        assertEq(got, FVMAddress.f0(1));
        (bool addrOk, address ownerAddr) = FVMMiner.tryGetOwnerAddress(MINER_ID);
        assertTrue(addrOk);
        assertEq(ownerAddr, FVMAddress.maskedAddress(1));
        (bool idOk, uint64 ownerId) = FVMMiner.tryGetOwnerActorId(MINER_ID);
        assertTrue(idOk);
        assertEq(ownerId, 1);
    }
}
