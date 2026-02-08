// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {FVMActor} from "../src/FVMActor.sol";

contract ResolveAddressTest is MockFVMTest {
    using FVMActor for bytes;
    using FVMActor for address;

    // Helper function to wrap the library call
    function _getActorIdBytes(bytes memory filAddress) public view returns (uint64) {
        return filAddress.getActorId();
    }

    function _getActorIdAddress(address addr) public view returns (uint64) {
        return addr.getActorId();
    }

    function f0(uint64 actorId) internal pure returns (bytes memory) {
        // f0 address = protocol byte (0x00) + big-endian actor ID
        return abi.encodePacked(uint8(0x00), actorId);
    }

    function f410(uint8 namespace, bytes20 subaddress) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0x04), namespace, subaddress);
    }

    function f410(address addr) internal pure returns (bytes memory) {
        return f410(0x0a, bytes20(addr));
    }

    // =============================================================
    //                  CONSTRUCTOR MOCK TESTS
    // =============================================================

    function testConstructorMocksSystemActors() public view {
        // System singleton actors (1-7, 10, 99) should be pre-mocked
        // Note: actor ID 0 (SYSTEM_ACTOR) cannot be tested because the mock
        // uses actorId == 0 as the sentinel for "not found"
        uint64[9] memory knownActors = [uint64(1), 2, 3, 4, 5, 6, 7, 10, 99];

        for (uint256 i = 0; i < knownActors.length; i++) {
            // Use same encoding as _mockf0: protocol byte + uint8 actor ID
            bytes memory filAddress = abi.encodePacked(uint8(0x00), uint8(knownActors[i]));
            (bool exists, uint64 actorId) = filAddress.tryGetActorId();

            assertTrue(exists, "Known actor should exist");
            assertEq(actorId, knownActors[i], "Actor ID should match");
        }
    }

    function testConstructorDoesNotMockUnknownActors() public view {
        // Actor IDs 8 and 9 should NOT be mocked
        bytes memory f0_8 = abi.encodePacked(uint8(0x00), uint8(8));
        bytes memory f0_9 = abi.encodePacked(uint8(0x00), uint8(9));

        (bool exists8,) = f0_8.tryGetActorId();
        (bool exists9,) = f0_9.tryGetActorId();

        assertFalse(exists8, "Actor 8 should not exist");
        assertFalse(exists9, "Actor 9 should not exist");
    }

    // =============================================================
    //                  BYTES TESTS
    // =============================================================

    function testTryGetActorIdExists() public {
        // Mock a Filecoin address (f01234)
        bytes memory filAddress = f0(1234); // f0 protocol + actor ID 1234
        uint64 expectedActorId = 1234;

        ACTOR_PRECOMPILE.mockResolveAddress(filAddress, expectedActorId);

        (bool exists, uint64 actorId) = filAddress.tryGetActorId();

        assertTrue(exists, "Actor should exist");
        assertEq(actorId, expectedActorId, "Actor ID should match");
    }

    function testTryGetActorIdDoesNotExists() public {
        // Mock a Filecoin address that doesn't exist
        bytes memory filAddress = f0(2500);

        // Don't mock it, so it returns 0 (doesn't exist)
        (bool exists, uint64 actorId) = filAddress.tryGetActorId();

        assertFalse(exists, "Actor should not exist");
        assertEq(actorId, 0, "Actor ID should be 0");
    }

    function testGetActorId() public {
        bytes memory filAddress = f0(1234);
        uint64 expectedActorId = 1234;

        ACTOR_PRECOMPILE.mockResolveAddress(filAddress, expectedActorId);

        uint64 actorId = filAddress.getActorId();
        assertEq(actorId, expectedActorId, "Actor ID should match");
    }

    function testGetActorIdReverts() public {
        bytes memory filAddress = f0(2500);

        // Should revert because actor doesn't exist
        vm.expectRevert("FVMActor: actor not found");
        this._getActorIdBytes(filAddress);
    }

    function testResolveInvalidAddress() public {
        // Invalid protocol byte (0x05 doesn't exist)
        bytes memory invalidAddress = hex"0504d2";

        vm.expectRevert("Invalid address: unknown protocol");
        this._getActorIdBytes(invalidAddress);
    }

    function testTryGetActorIdF410() public {
        // f410 address (delegated address format)
        bytes memory f410Address = f410(address(0x1234567890123456789012345678901234567890));
        uint64 expectedActorId = 9999;

        ACTOR_PRECOMPILE.mockResolveAddress(f410Address, expectedActorId);

        (bool exists, uint64 actorId) = f410Address.tryGetActorId();

        assertTrue(exists, "Actor should exist");
        assertEq(actorId, expectedActorId, "Actor ID should match");
    }

    // =============================================================
    //                  ADDRESS (EVM) TESTS
    // =============================================================

    function testTryGetActorIdAddressExists() public {
        address addr = address(0x1234567890123456789012345678901234567890);
        uint64 expectedActorId = 5678;

        ACTOR_PRECOMPILE.mockResolveAddress(addr, expectedActorId);

        (bool exists, uint64 actorId) = addr.tryGetActorId();

        assertTrue(exists, "Actor should exist");
        assertEq(actorId, expectedActorId, "Actor ID should match");
    }

    function testTryGetActorIdAddressDoesNotExist() public {
        address addr = address(0xdead);

        (bool exists, uint64 actorId) = addr.tryGetActorId();

        assertFalse(exists, "Actor should not exist");
        assertEq(actorId, 0, "Actor ID should be 0");
    }

    function testGetActorIdAddress() public {
        address addr = address(0x1234567890123456789012345678901234567890);
        uint64 expectedActorId = 5678;

        ACTOR_PRECOMPILE.mockResolveAddress(addr, expectedActorId);

        uint64 actorId = addr.getActorId();
        assertEq(actorId, expectedActorId, "Actor ID should match");
    }

    function testGetActorIdAddressReverts() public {
        address addr = address(0xdead);

        vm.expectRevert("FVMActor: actor not found");
        this._getActorIdAddress(addr);
    }
}
