// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {FVMActor} from "../src/FVMActor.sol";
import {FVMAddress} from "../src/FVMAddress.sol";

contract ResolveAddressTest is MockFVMTest {
    using FVMActor for bytes;
    using FVMActor for address;
    using FVMAddress for uint64;
    using FVMAddress for address;

    // Helper function to wrap the library call
    function _getActorIdBytes(bytes memory filAddress) public view returns (uint64) {
        return filAddress.getActorId();
    }

    function _getActorIdAddress(address addr) public view returns (uint64) {
        return addr.getActorId();
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
            bytes memory filAddress = knownActors[i].f0();
            (bool exists, uint64 actorId) = filAddress.tryGetActorId();

            assertTrue(exists, "Known actor should exist");
            assertEq(actorId, knownActors[i], "Actor ID should match");
        }
    }

    function testConstructorDoesNotMockUnknownActors() public view {
        // Actor IDs 8 and 9 should NOT be mocked
        uint64[2] memory unknownActors = [uint64(8), 9];
        bytes memory f0_8 = unknownActors[0].f0();
        bytes memory f0_9 = unknownActors[1].f0();

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
        uint64 actorIdToMock = 1234;
        bytes memory filAddress = actorIdToMock.f0(); // f0 protocol + actor ID 1234

        ACTOR_PRECOMPILE.mockResolveAddress(filAddress, actorIdToMock);

        (bool exists, uint64 actorId) = filAddress.tryGetActorId();

        assertTrue(exists, "Actor should exist");
        assertEq(actorId, actorIdToMock, "Actor ID should match");
    }

    function testTryGetActorIdDoesNotExists() public {
        // Mock a Filecoin address that doesn't exist
        uint64 actorIdToMock = 2500;
        bytes memory filAddress = actorIdToMock.f0();

        // Don't mock it, so it returns 0 (doesn't exist)
        (bool exists, uint64 actorId) = filAddress.tryGetActorId();

        assertFalse(exists, "Actor should not exist");
        assertEq(actorId, 0, "Actor ID should be 0");
    }

    function testGetActorId() public {
        uint64 actorIdToMock = 1234;
        bytes memory filAddress = actorIdToMock.f0();

        ACTOR_PRECOMPILE.mockResolveAddress(filAddress, actorIdToMock);

        uint64 actorId = filAddress.getActorId();
        assertEq(actorId, actorIdToMock, "Actor ID should match");
    }

    function testGetActorIdReverts() public {
        uint64 actorIdToMock = 2500;
        bytes memory filAddress = actorIdToMock.f0();

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
        bytes memory f410Address = address(0x1234567890123456789012345678901234567890).f410();
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
