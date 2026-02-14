// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {FVMLookupDelegatedAddress} from "../src/FVMLookupDelegatedAddress.sol";

contract LookupDelegatedAddressTest is MockFVMTest {
    using FVMLookupDelegatedAddress for uint64;
    using FVMLookupDelegatedAddress for bytes;

    // Helper to wrap library calls for vm.expectRevert
    function _lookupStrict(uint64 actorId) public view returns (bytes memory) {
        return actorId.lookupDelegatedAddressStrict();
    }

    function _toEthAddress(bytes memory delegated) public pure returns (address) {
        return delegated.toEthAddress();
    }

    function testLookupExistingDelegatedAddress() public {
        uint64 actorId = 1234;
        bytes memory expectedAddress = abi.encodePacked(hex"040a", hex"1234567890123456789012345678901234567890");

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(actorId, expectedAddress);

        bytes memory result = actorId.lookupDelegatedAddress();
        assertEq(result, expectedAddress, "Addresses should match");
    }

    function testLookupNonExistentReturnsEmpty() public {
        uint64 actorId = 999;
        // No mock set, should return empty bytes
        bytes memory result = actorId.lookupDelegatedAddress();
        assertEq(result.length, 0, "Should return empty bytes for non-existent actor");
    }

    function testLookupStrictReverts() public {
        uint64 actorId = 999;
        vm.expectRevert(FVMLookupDelegatedAddress.NoDelegatedAddress.selector);
        this._lookupStrict(actorId);
    }

    function testToEthAddressSuccess() public pure {
        address expected = 0x1234567890123456789012345678901234567890;
        bytes memory delegated = abi.encodePacked(hex"040a", expected);

        address result = delegated.toEthAddress();
        assertEq(result, expected, "Extracted address should match");
    }

    function testToEthAddressInvalidLength() public {
        bytes memory tooShort = hex"040a1234";
        vm.expectRevert(FVMLookupDelegatedAddress.InvalidDelegatedAddress.selector);
        this._toEthAddress(tooShort);
    }

    function testToEthAddressInvalidPrefix() public {
        // Correct length (22) but wrong prefix (040b instead of 040a)
        bytes memory wrongPrefix = abi.encodePacked(hex"040b", hex"1234567890123456789012345678901234567890");
        vm.expectRevert(FVMLookupDelegatedAddress.InvalidDelegatedAddress.selector);
        this._toEthAddress(wrongPrefix);
    }

    function testPrecompileRevertOnLargeId() public {
        // We use a value > u64 to trigger the mock's revert
        uint256 hugeId = uint256(type(uint64).max) + 1;

        // Use low-level call to precompile address to check for revert
        (bool success,) = LOOKUP_ADDR.staticcall(abi.encode(hugeId));
        assertFalse(success, "Precompile should revert on ID > u64");
    }

    function testLookupStrictSuccess() public {
        uint64 actorId = 42;
        bytes memory expectedAddress = abi.encodePacked(hex"040a", address(0xBEEF));

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(actorId, expectedAddress);

        bytes memory result = actorId.lookupDelegatedAddressStrict();
        assertEq(result, expectedAddress, "Strict lookup should return delegated address");
    }

    function testEndToEndLookupAndConvert() public {
        uint64 actorId = 100;
        address expectedEthAddress = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF;
        bytes memory delegated = abi.encodePacked(hex"040a", expectedEthAddress);

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(actorId, delegated);

        // Full workflow: lookup -> convert to ETH address
        bytes memory result = actorId.lookupDelegatedAddress();
        address ethAddr = result.toEthAddress();

        assertEq(ethAddr, expectedEthAddress, "End-to-end address extraction should match");
    }

    function testLookupActorIdZero() public {
        uint64 actorId = 0;
        bytes memory expectedAddress = abi.encodePacked(hex"040a", address(0x1));

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(actorId, expectedAddress);

        bytes memory result = actorId.lookupDelegatedAddress();
        assertEq(result, expectedAddress, "Actor ID 0 should work");
    }

    function testLookupActorIdMaxUint64() public {
        uint64 actorId = type(uint64).max;
        bytes memory expectedAddress = abi.encodePacked(hex"040a", address(0x2));

        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(actorId, expectedAddress);

        bytes memory result = actorId.lookupDelegatedAddress();
        assertEq(result, expectedAddress, "Max uint64 actor ID should work");
    }

    function testFuzzToEthAddress(address addr) public pure {
        bytes memory delegated = abi.encodePacked(hex"040a", addr);

        address result = delegated.toEthAddress();
        assertEq(result, addr, "Fuzzed address extraction should match");
    }

    function testToEthAddressTooLong() public {
        // 23 bytes (1 extra byte)
        bytes memory tooLong = abi.encodePacked(hex"040a", hex"001234567890123456789012345678901234567890");
        vm.expectRevert(FVMLookupDelegatedAddress.InvalidDelegatedAddress.selector);
        this._toEthAddress(tooLong);
    }
}
