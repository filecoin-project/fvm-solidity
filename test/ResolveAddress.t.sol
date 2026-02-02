// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {FVMResolveAddress} from "../src/FVMResolveAddress.sol";

contract ResolveAddressTest is MockFVMTest {
    using FVMResolveAddress for bytes;

    // Helper function to wrap the library call
    function _getActorId(bytes memory filAddress) public view returns (uint64) {
        return filAddress.getActorId();
    }

    function f0(uint64 actorId) internal pure returns (bytes memory) {
        // f0 address = protocol byte (0x00) + big-endian actor ID
        return abi.encodePacked(uint8(0x00), actorId);
    }

    function f410(uint8 namespace, bytes20 subaddress) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0x04), namespace, subaddress);
    }

    function testResolveExistingActor() public {
        // Mock a Filecoin address (f01234)
        bytes memory filAddress = f0(1234); // f0 protocol + actor ID 1234
        uint64 expectedActorId = 1234;

        RESOLVE_ADDRESS_PRECOMPILE.mockResolveAddress(filAddress, expectedActorId);

        (bool exists, uint64 actorId) = filAddress.resolveAddress();

        assertTrue(exists, "Actor should exist");
        assertEq(actorId, expectedActorId, "Actor ID should match");
    }

    function testResolveNonExistentActor() public {
        // Mock a Filecoin address that doesn't exist
        bytes memory filAddress = f0(2500);

        // Don't mock it, so it returns 0 (doesn't exist)
        (bool exists, uint64 actorId) = filAddress.resolveAddress();

        assertFalse(exists, "Actor should not exist");
        assertEq(actorId, 0, "Actor ID should be 0");
    }

    function testGetActorId() public {
        bytes memory filAddress = f0(1234);
        uint64 expectedActorId = 1234;

        RESOLVE_ADDRESS_PRECOMPILE.mockResolveAddress(filAddress, expectedActorId);

        uint64 actorId = filAddress.getActorId();
        assertEq(actorId, expectedActorId, "Actor ID should match");
    }

    function testGetActorIdReverts() public {
        bytes memory filAddress = f0(2500);

        // Should revert because actor doesn't exist
        vm.expectRevert("FVMResolveAddress: actor not found");
        this._getActorId(filAddress);
    }

    function testResolveInvalidAddress() public {
        // Invalid protocol byte (0x05 doesn't exist)
        bytes memory invalidAddress = hex"0504d2";

        vm.expectRevert("Invalid address: unknown protocol");
        this._getActorId(invalidAddress);
    }

    function testResolveF410Address() public {
        // f410 address (delegated address format)
        bytes memory f410Address = f410(0x0a, bytes20(0x1234567890123456789012345678901234567890));
        uint64 expectedActorId = 9999;

        RESOLVE_ADDRESS_PRECOMPILE.mockResolveAddress(f410Address, expectedActorId);

        (bool exists, uint64 actorId) = f410Address.resolveAddress();

        assertTrue(exists, "Actor should exist");
        assertEq(actorId, expectedActorId, "Actor ID should match");
    }
}
