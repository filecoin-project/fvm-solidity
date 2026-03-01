// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {FVMActor} from "../src/FVMActor.sol";
import {FVMAddress} from "../src/FVMAddress.sol";

contract ResolveAddressTest is MockFVMTest {
    using FVMActor for bytes;
    using FVMActor for address;
    using FVMActor for uint64;
    using FVMAddress for uint64;
    using FVMAddress for address;
    using FVMAddress for bytes;

    // Helper function to wrap the library call
    function _getActorIdBytes(bytes memory filAddress) public view returns (uint64) {
        return filAddress.getActorId();
    }

    function _getActorIdAddress(address addr) public view returns (uint64) {
        return addr.getActorId();
    }

    function _lookupDelegatedAddressStrict(uint64 actorId) public view returns (bytes memory) {
        return actorId.lookupDelegatedAddress();
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

    function testMaskedIdAddressSystemActor() public {
        // System actor: f00 -> 0xff + 11 zeros + actor ID
        uint64 expectedActorId = 0;
        address maskedSystemActor = address(bytes20(abi.encodePacked(hex"ff", bytes11(0), expectedActorId)));

        // Mock the f0 address for actor 0
        ACTOR_PRECOMPILE.mockResolveAddress(expectedActorId.f0(), expectedActorId);

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
    //                  DELEGATED ADDRESS TESTS
    // =============================================================

    function testTryLookupDelegatedAddressExists() public {
        uint64 actorId = 1234;
        bytes memory expected = abi.encodePacked(uint8(0x04), uint8(0x0a), address(1));

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(actorId, expected);

        (bool exists, bytes memory result) = actorId.tryLookupDelegatedAddress();

        assertTrue(exists, "Actor should have a delegated address");
        assertEq(result, expected, "Delegated address should match");
    }

    function testTryLookupDelegatedAddressDoesNotExist() public view {
        uint64 actorId = 9999;
        // No mock set — precompile returns empty

        (bool exists, bytes memory result) = actorId.tryLookupDelegatedAddress();

        assertFalse(exists, "Actor should have no delegated address");
        assertEq(result.length, 0, "Should return empty bytes");
    }

    function testLookupDelegatedAddressExists() public {
        uint64 actorId = 42;
        bytes memory expected = abi.encodePacked(uint8(0x04), uint8(0x0a), address(1));

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(actorId, expected);

        bytes memory result = actorId.lookupDelegatedAddress();
        assertEq(result, expected, "Strict lookup should return delegated address");
    }

    function testLookupDelegatedAddressReverts() public {
        uint64 actorId = 9999;

        vm.expectRevert(abi.encodeWithSelector(FVMActor.DelegatedAddressNotFound.selector, actorId));
        this._lookupDelegatedAddressStrict(actorId);
    }

    function testLookupDelegatedAddressActorIdZero() public {
        uint64 actorId = 0;
        bytes memory expected = abi.encodePacked(uint8(0x04), uint8(0x0a), address(1));

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(actorId, expected);

        (bool exists, bytes memory result) = actorId.tryLookupDelegatedAddress();
        assertTrue(exists, "Actor ID 0 should work");
        assertEq(result, expected, "Delegated address should match for actor ID 0");
    }

    function testLookupDelegatedAddressActorIdMaxUint64() public {
        uint64 actorId = type(uint64).max;
        bytes memory expected = abi.encodePacked(uint8(0x04), uint8(0x0a), address(2));

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(actorId, expected);

        (bool exists, bytes memory result) = actorId.tryLookupDelegatedAddress();
        assertTrue(exists, "Max uint64 actor ID should work");
        assertEq(result, expected, "Delegated address should match for max uint64 actor ID");
    }

    function testPrecompileRevertOnLargeId() public {
        // An ID that exceeds u64 should cause the precompile to revert
        uint256 hugeId = uint256(type(uint64).max) + 1;

        (bool success,) = address(LOOKUP_DELEGATED_ADDRESS_PRECOMPILE).staticcall(abi.encode(hugeId));
        assertFalse(success, "Precompile should revert on ID > u64");
    }

    function testMockLookupDelegatedAddressUsingAddress() public {
        uint64 actorId = 100;
        address ethAddr = address(1);

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(actorId, ethAddr);

        (bool exists, bytes memory result) = actorId.tryLookupDelegatedAddress();
        bytes memory expected = abi.encodePacked(uint8(0x04), uint8(0x0a), ethAddr);

        assertTrue(exists, "Actor should have a delegated address");
        assertEq(result, expected, "Delegated address bytes should match f410 encoding");
    }

    function testLookupDelegatedAddressStrictUsingAddress() public {
        uint64 actorId = 100;
        address ethAddr = address(1);

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(actorId, ethAddr);

        bytes memory result = actorId.lookupDelegatedAddress();
        bytes memory expected = abi.encodePacked(uint8(0x04), uint8(0x0a), ethAddr);

        assertEq(result, expected, "Strict lookup via address mock should match f410 encoding");
    }

    function testFuzzTryLookupDelegatedAddress(uint64 actorId, address ethAddr) public {
        bytes memory expected = abi.encodePacked(uint8(0x04), uint8(0x0a), ethAddr);

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(actorId, expected);

        (bool exists, bytes memory result) = actorId.tryLookupDelegatedAddress();
        assertTrue(exists, "Actor should exist");
        assertEq(result, expected, "Fuzzed delegated address should match");
    }

    // =============================================================
    //                     LIFECYCLE TESTS
    // =============================================================

    function testLifecycleEthAddressToActorIdToDelegatedAddress() public {
        // Simulate: ETH address -> actor ID -> delegated address -> back to ETH address
        address ethAddr = address(0x1234567890123456789012345678901234567890);
        uint64 actorId = 1234;

        ACTOR_PRECOMPILE.mockResolveAddress(ethAddr, actorId);
        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(actorId, ethAddr);

        uint64 resolvedId = ethAddr.getActorId();
        address recovered = resolvedId.lookupDelegatedAddress().toEthAddress();

        assertEq(resolvedId, actorId, "Actor ID should match");
        assertEq(recovered, ethAddr, "Recovered ETH address should match original");
    }

    function testLifecycleF410AddressToActorIdToDelegatedAddress() public {
        // Simulate: f410 bytes address -> actor ID -> delegated address -> back to ETH address
        address ethAddr = address(0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF);
        uint64 actorId = 5678;
        bytes memory f410Addr = ethAddr.f410();

        ACTOR_PRECOMPILE.mockResolveAddress(f410Addr, actorId);
        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(actorId, ethAddr);

        uint64 resolvedId = f410Addr.getActorId();
        address recovered = resolvedId.lookupDelegatedAddress().toEthAddress();

        assertEq(resolvedId, actorId, "Actor ID should match");
        assertEq(recovered, ethAddr, "Recovered ETH address should match original");
    }

    function testFuzzLifecycle(uint64 actorId, address ethAddr) public {
        // actorId == 0 is the mock sentinel for "not found".
        // Note: Pre-seeded system actors (IDs 1-7, etc.) do not conflict here
        // because their constructor mocks are keyed by f0 encoding,
        // whereas the mockResolveAddress below keys by f410 encoding.
        vm.assume(actorId != 0);

        ACTOR_PRECOMPILE.mockResolveAddress(ethAddr, actorId);
        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(actorId, ethAddr);

        uint64 resolvedId = ethAddr.getActorId();
        address recovered = resolvedId.lookupDelegatedAddress().toEthAddress();

        assertEq(resolvedId, actorId);
        assertEq(recovered, ethAddr);
    }
}
