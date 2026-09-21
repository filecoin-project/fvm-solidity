// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {FVMActor} from "../src/FVMActor.sol";
import {FVMAddress} from "../src/FVMAddress.sol";
import {CALL_ACTOR_BY_ID} from "../src/FVMPrecompiles.sol";

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
        uint64[10] memory knownActors = [uint64(0), 1, 2, 3, 4, 5, 6, 7, 10, 99];

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
        bytes memory f0Actor8 = unknownActors[0].f0();
        bytes memory f0Actor9 = unknownActors[1].f0();

        (bool exists8,) = f0Actor8.tryGetActorId();
        (bool exists9,) = f0Actor9.tryGetActorId();

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

    function testTryGetActorIdDoesNotExists() public view {
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
        vm.expectRevert(abi.encodeWithSelector(FVMActor.ActorNotFound.selector, filAddress));
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

    function testTryGetActorIdAddressDoesNotExist() public view {
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

        vm.expectRevert(abi.encodeWithSelector(FVMActor.EVMActorNotFound.selector, addr));
        this._getActorIdAddress(addr);
    }

    // =============================================================
    //                  MASKED ID ADDRESS TESTS
    // =============================================================

    function testMaskedIdAddressBurnActor() public {
        // Burn actor: f099 -> 0xff + 11 zeros + actor ID
        uint64 expectedActorId = 99;
        address maskedBurnActor = address(bytes20(abi.encodePacked(hex"ff", bytes11(0), expectedActorId)));

        // Mock the f0 address for actor 99
        ACTOR_PRECOMPILE.mockResolveAddress(expectedActorId.f0(), expectedActorId);

        (bool exists, uint64 actorId) = maskedBurnActor.tryGetActorId();

        assertTrue(exists, "Burn actor should exist");
        assertEq(actorId, expectedActorId, "Actor ID should be 99");
    }

    function testMaskedIdAddressSystemActor() public view {
        // System actor: f00 -> 0xff + 11 zeros + actor ID
        uint64 expectedActorId = 0;
        address maskedSystemActor = address(bytes20(abi.encodePacked(hex"ff", bytes11(0), expectedActorId)));

        // The system actor's f0 address is mocked by the FVMActor constructor
        (bool exists, uint64 actorId) = maskedSystemActor.tryGetActorId();

        assertTrue(exists, "System actor should exist");
        assertEq(actorId, expectedActorId, "Actor ID should be 0");
    }

    function testMaskedIdAddressArbitraryId() public {
        // Arbitrary actor: f01234 -> 0xff + 11 zeros + actor ID
        uint64 expectedActorId = 1234;
        address maskedAddr = address(bytes20(abi.encodePacked(hex"ff", bytes11(0), expectedActorId)));

        // Mock the f0 address for actor 1234
        ACTOR_PRECOMPILE.mockResolveAddress(expectedActorId.f0(), expectedActorId);

        (bool exists, uint64 actorId) = maskedAddr.tryGetActorId();

        assertTrue(exists, "Actor 1234 should exist");
        assertEq(actorId, expectedActorId, "Actor ID should be 1234");
    }

    function testMaskedIdAddressDoesNotExist() public view {
        // Masked ID for non-existent actor
        address maskedAddr = address(bytes20(abi.encodePacked(hex"ff", bytes11(0), uint64(0x9999))));

        (bool exists, uint64 actorId) = maskedAddr.tryGetActorId();

        assertFalse(exists, "Non-existent masked ID actor should not exist");
        assertEq(actorId, 0, "Actor ID should be 0");
    }

    function testMaskedIdAddressGetActorIdReverts() public {
        // Masked ID for non-existent actor
        address maskedAddr = address(bytes20(abi.encodePacked(hex"ff", bytes11(0), uint64(0x9999))));

        vm.expectRevert(abi.encodeWithSelector(FVMActor.EVMActorNotFound.selector, maskedAddr));
        this._getActorIdAddress(maskedAddr);
    }

    function testNonMaskedIdAddressStillUsesF410() public {
        // Regular address (not 0xff-prefixed) should use f410 path
        address regularAddr = address(0x1234567890123456789012345678901234567890);
        uint64 expectedActorId = 5678;

        // Mock as f410, not f0
        ACTOR_PRECOMPILE.mockResolveAddress(regularAddr, expectedActorId);

        (bool exists, uint64 actorId) = regularAddr.tryGetActorId();

        assertTrue(exists, "Regular address should resolve via f410");
        assertEq(actorId, expectedActorId, "Actor ID should match");
    }

    // =============================================================
    //                  EXISTS (ACTOR ID) TESTS
    // =============================================================

    function testExistsSystemActors() public {
        uint64[10] memory systemActors = [uint64(0), 1, 2, 3, 4, 5, 6, 7, 10, 99];

        for (uint256 i = 0; i < systemActors.length; i++) {
            assertTrue(FVMActor.exists(systemActors[i]), "System actor should exist");
        }
    }

    function testExistsMockedActor() public {
        uint64 actorId = 1234;
        ACTOR_PRECOMPILE.mockResolveAddress(address(0x1234567890123456789012345678901234567890), actorId);

        assertTrue(FVMActor.exists(actorId), "Mocked actor should exist");
    }

    function testExistsMockedF0Actor() public {
        uint64 actorId = 1234;
        ACTOR_PRECOMPILE.mockResolveAddress(actorId.f0(), actorId);

        assertTrue(FVMActor.exists(actorId), "Mocked f0 actor should exist");
    }

    function testExistsUnknownActor() public {
        assertFalse(FVMActor.exists(2500), "Unmocked actor should not exist");
    }

    function testExistsUnknownActorBetweenSystemActors() public {
        // Actor IDs 8 and 9 are not pre-mocked
        assertFalse(FVMActor.exists(8), "Actor 8 should not exist");
        assertFalse(FVMActor.exists(9), "Actor 9 should not exist");
    }

    function testExistsIsUnaffectedByOtherActors() public {
        ACTOR_PRECOMPILE.mockResolveAddress(address(0x1234567890123456789012345678901234567890), 1234);

        assertFalse(FVMActor.exists(1233), "Neighboring actor ID should not exist");
        assertFalse(FVMActor.exists(1235), "Neighboring actor ID should not exist");
    }

    function testExistsMaskedIdMiner() public {
        uint64 minerId = 1234;
        assertFalse(FVMActor.exists(minerId), "Miner should not exist before it is mocked");

        mockMiner(minerId);

        assertTrue(FVMActor.exists(minerId), "Mocked miner should exist");
    }

    function testExistsMiner() public {
        uint64 minerId = 1234;
        assertFalse(FVMActor.exists(minerId), "Miner should not exist before it is mocked");

        mockMiner(minerId);

        assertTrue(FVMActor.exists(minerId), "Mocked miner should exist");
    }

    function testMockedMinerResolves() public {
        uint64 minerId = 1234;
        address maskedAddr = minerId.maskedAddress();

        mockMiner(minerId);

        (bool exists, uint64 actorId) = minerId.f0().tryGetActorId();
        assertTrue(exists, "Miner f0 address should resolve");
        assertEq(actorId, minerId, "Actor ID should match");

        (exists, actorId) = maskedAddr.tryGetActorId();
        assertTrue(exists, "Miner masked address should resolve");
        assertEq(actorId, minerId, "Actor ID should match");
    }

    function testExistsDoesNotMoveValue() public {
        uint64 actorId = 1234;
        address actorAddress = address(0x1234567890123456789012345678901234567890);
        ACTOR_PRECOMPILE.mockResolveAddress(actorAddress, actorId);
        vm.deal(address(this), 10 ether);

        assertTrue(FVMActor.exists(actorId));

        assertEq(address(this).balance, 10 ether, "Caller balance should be unchanged");
        assertEq(actorAddress.balance, 0, "Actor balance should be unchanged");
    }

    function testExistsIsFalseWithoutPrecompile() public {
        // Off Filecoin there is no code at the precompile address, so the call returns no data
        uint64 actorId = 1234;
        ACTOR_PRECOMPILE.mockResolveAddress(address(0x1234567890123456789012345678901234567890), actorId);
        vm.etch(CALL_ACTOR_BY_ID, "");

        assertFalse(FVMActor.exists(actorId), "Should not exist without the precompile");
    }

    function testExistsIsFalseAfterPrecompileReverts() public {
        // The real precompile reverts on invalid input; that must read as "does not exist", not bubble up
        uint64 actorId = 1234;
        ACTOR_PRECOMPILE.mockResolveAddress(address(0x1234567890123456789012345678901234567890), actorId);
        vm.etch(CALL_ACTOR_BY_ID, hex"5f5ffd");

        assertFalse(FVMActor.exists(actorId), "Should not exist when the precompile reverts");
    }

    function testFuzzExistsMocked(uint64 actorId) public {
        actorId = uint64(bound(actorId, 100, type(uint64).max));
        address actorAddress = address(uint160(uint256(keccak256(abi.encode(actorId)))));
        vm.assume(actorAddress.code.length == 0);
        ACTOR_PRECOMPILE.mockResolveAddress(actorAddress, actorId);

        assertTrue(FVMActor.exists(actorId), "Mocked actor should exist");
    }

    function testFuzzExistsUnmocked(uint64 actorId) public {
        actorId = uint64(bound(actorId, 100, type(uint64).max));

        assertFalse(FVMActor.exists(actorId), "Unmocked actor should not exist");
    }
}
