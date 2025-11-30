// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {FVMAddress} from "../src/FVMAddress.sol";

contract AddressTest is MockFVMTest {
    using FVMAddress for bytes;

    function testResolveAddressNotFound() public view {
        bytes memory fakeAddress = hex"0102030405060708090a0b0c0d0e0f10";
        (bool success, uint64 actorId) = FVMAddress.resolveAddress(fakeAddress);
        assertTrue(success);
        assertEq(actorId, 0);
    }

    function testResolveAddressMocked() public {
        bytes memory testAddress = hex"01234567";
        uint64 expectedActorId = 12345;

        RESOLVE_ADDRESS_PRECOMPILE.mockResolveAddress(testAddress, expectedActorId);

        (bool success, uint64 actorId) = FVMAddress.resolveAddress(testAddress);
        assertTrue(success);
        assertEq(actorId, expectedActorId);
    }

    function testToActorId() public {
        bytes memory testAddress = hex"0123456789abcdef";
        uint64 expectedActorId = 99999;

        RESOLVE_ADDRESS_PRECOMPILE.mockResolveAddress(testAddress, expectedActorId);

        uint64 actorId = testAddress.toActorId();
        assertEq(actorId, expectedActorId);
    }

    function testMultipleAddressResolutions() public {
        bytes memory addr1 = hex"aabbccdd";
        bytes memory addr2 = hex"11223344";
        uint64 actorId1 = 1111;
        uint64 actorId2 = 2222;

        RESOLVE_ADDRESS_PRECOMPILE.mockResolveAddress(addr1, actorId1);
        RESOLVE_ADDRESS_PRECOMPILE.mockResolveAddress(addr2, actorId2);

        assertEq(addr1.toActorId(), actorId1);
        assertEq(addr2.toActorId(), actorId2);
    }

    function testDifferentAddressFormats() public {
        bytes memory shortAddr = hex"01";
        bytes memory longAddr = hex"0123456789abcdef0123456789abcdef";
        uint64 shortActorId = 100;
        uint64 longActorId = 200;

        RESOLVE_ADDRESS_PRECOMPILE.mockResolveAddress(shortAddr, shortActorId);
        RESOLVE_ADDRESS_PRECOMPILE.mockResolveAddress(longAddr, longActorId);

        (bool success1, uint64 actorId1) = FVMAddress.resolveAddress(shortAddr);
        (bool success2, uint64 actorId2) = FVMAddress.resolveAddress(longAddr);

        assertTrue(success1);
        assertTrue(success2);
        assertEq(actorId1, shortActorId);
        assertEq(actorId2, longActorId);
    }
}
