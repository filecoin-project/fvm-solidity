// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {FVMAddress} from "../src/FVMAddress.sol";

contract AddressTest is MockFVMTest {
    function testLookupDelegatedAddressNotFound() public {
        uint64 fakeActorId = 99999;
        (bool success, bytes memory delegatedAddress) = FVMAddress.lookupDelegatedAddress(fakeActorId);
        assertTrue(success);
        assertEq(delegatedAddress.length, 0);
    }

    function testLookupDelegatedAddressMocked() public {
        uint64 testActorId = 54321;
        bytes memory expectedAddress = hex"040a1234567890abcdef1234567890abcdef12345678";

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(testActorId, expectedAddress);

        (bool success, bytes memory delegatedAddress) = FVMAddress.lookupDelegatedAddress(testActorId);
        assertTrue(success);
        assertEq(delegatedAddress, expectedAddress);
    }

    function testActorIdToEthAddress() public {
        uint64 testActorId = 11111;
        address expectedEthAddress = address(0x1234567890AbcdEF1234567890aBcdef12345678);

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockActorIdToEthAddress(testActorId, expectedEthAddress);

        (bool success, address ethAddress) = FVMAddress.actorIdToEthAddress(testActorId);
        assertTrue(success);
        assertEq(ethAddress, expectedEthAddress);
    }

    function testActorIdToEthAddressNotFound() public {
        uint64 fakeActorId = 99999;
        (bool success, address ethAddress) = FVMAddress.actorIdToEthAddress(fakeActorId);
        assertFalse(success);
        assertEq(ethAddress, address(0));
    }

    function testActorIdToEthAddressInvalidPrefix() public {
        uint64 testActorId = 22222;
        bytes memory invalidAddress = hex"ff0a1234567890abcdef1234567890abcdef12345678";

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(testActorId, invalidAddress);

        (bool success, address ethAddress) = FVMAddress.actorIdToEthAddress(testActorId);
        assertFalse(success);
        assertEq(ethAddress, address(0));
    }

    function testActorIdToEthAddressWrongLength() public {
        uint64 testActorId = 33333;
        bytes memory shortAddress = hex"040a12345678";

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(testActorId, shortAddress);

        (bool success, address ethAddress) = FVMAddress.actorIdToEthAddress(testActorId);
        assertFalse(success);
        assertEq(ethAddress, address(0));
    }

    function testActorIdToEthAddressZeroAddress() public {
        uint64 testActorId = 44444;
        address expectedEthAddress = address(0);

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockActorIdToEthAddress(testActorId, expectedEthAddress);

        (bool success, address ethAddress) = FVMAddress.actorIdToEthAddress(testActorId);
        assertTrue(success);
        assertEq(ethAddress, expectedEthAddress);
    }

    function testActorIdToEthAddressMaxAddress() public {
        uint64 testActorId = 55555;
        address expectedEthAddress = address(0xFFfFfFffFFfffFFfFFfFFFFFffFFFffffFfFFFfF);

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockActorIdToEthAddress(testActorId, expectedEthAddress);

        (bool success, address ethAddress) = FVMAddress.actorIdToEthAddress(testActorId);
        assertTrue(success);
        assertEq(ethAddress, expectedEthAddress);
    }

    function testActorIdToEthAddressInvalidSecondByte() public {
        uint64 testActorId = 66666;
        bytes memory invalidAddress = hex"04001234567890abcdef1234567890abcdef12345678";

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(testActorId, invalidAddress);

        (bool success, address ethAddress) = FVMAddress.actorIdToEthAddress(testActorId);
        assertFalse(success);
        assertEq(ethAddress, address(0));
    }

    function testActorIdToEthAddressTooLong() public {
        uint64 testActorId = 77777;
        bytes memory longAddress = hex"040a1234567890abcdef1234567890abcdef12345678ff";

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(testActorId, longAddress);

        (bool success, address ethAddress) = FVMAddress.actorIdToEthAddress(testActorId);
        assertFalse(success);
        assertEq(ethAddress, address(0));
    }

    function testActorIdToEthAddressPrecompileFailure() public {
        uint64 testActorId = 88888;

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddressFailure(testActorId);

        (bool success, address ethAddress) = FVMAddress.actorIdToEthAddress(testActorId);
        assertFalse(success);
        assertEq(ethAddress, address(0));
    }
}
