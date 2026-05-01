// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {CalldataSlice, CalldataUtils, WrongAddressLength, WrongUint64Length} from "../src/CalldataUtils.sol";

/// @notice Wraps a calldata bytes parameter in a CalldataSlice for testing
contract CalldataUtilsHarness {
    function load(bytes calldata data) external pure returns (bytes memory result) {
        CalldataSlice memory s;
        assembly ("memory-safe") {
            mstore(s, data.offset)
            mstore(add(s, 0x20), data.length)
        }
        result = CalldataUtils.load(s);
    }

    function toAddress(bytes calldata data) external pure returns (address result) {
        CalldataSlice memory s;
        assembly ("memory-safe") {
            mstore(s, data.offset)
            mstore(add(s, 0x20), data.length)
        }
        result = CalldataUtils.toAddress(s);
    }

    function toUint64(bytes calldata data) external pure returns (uint64 result) {
        CalldataSlice memory s;
        assembly ("memory-safe") {
            mstore(s, data.offset)
            mstore(add(s, 0x20), data.length)
        }
        result = CalldataUtils.toUint64(s);
    }

    function keccak(bytes calldata data) external pure returns (bytes32 result) {
        CalldataSlice memory s;
        assembly ("memory-safe") {
            mstore(s, data.offset)
            mstore(add(s, 0x20), data.length)
        }
        result = CalldataUtils.keccak(s);
    }
}

contract CalldataUtilsTest is Test {
    CalldataUtilsHarness harness;

    function setUp() public {
        harness = new CalldataUtilsHarness();
    }

    function testLoadRoundtrip() public view {
        bytes memory data = hex"deadbeefcafe";
        assertEq(harness.load(data), data);
    }

    function testLoadEmpty() public view {
        assertEq(harness.load(bytes("")), bytes(""));
    }

    function testLoadFuzz(bytes calldata data) public view {
        assertEq(harness.load(data), data);
    }

    function testToAddress() public view {
        address expected = 0xDeaDbeefdEAdbeefdEadbEEFdeadbeEFdEaDbeeF;
        assertEq(harness.toAddress(abi.encodePacked(expected)), expected);
    }

    function testToAddressWrongLength() public {
        vm.expectRevert(abi.encodeWithSelector(WrongAddressLength.selector, 19));
        harness.toAddress(hex"deadbeefdeadbeefdeadbeefdeadbeefdeadbe");
    }

    function testToAddressWrongLengthFuzz(bytes calldata data) public {
        vm.assume(data.length != 20);
        vm.expectRevert(abi.encodeWithSelector(WrongAddressLength.selector, data.length));
        harness.toAddress(data);
    }

    function testToUint64() public view {
        assertEq(harness.toUint64(abi.encodePacked(uint64(0xdeadbeefcafe1234))), 0xdeadbeefcafe1234);
    }

    function testToUint64Zero() public view {
        assertEq(harness.toUint64(abi.encodePacked(uint64(0))), 0);
    }

    function testToUint64Max() public view {
        assertEq(harness.toUint64(abi.encodePacked(type(uint64).max)), type(uint64).max);
    }

    function testToUint64WrongLength() public {
        vm.expectRevert(abi.encodeWithSelector(WrongUint64Length.selector, 7));
        harness.toUint64(hex"deadbeefcafe12");
    }

    function testToUint64WrongLengthFuzz(bytes calldata data) public {
        vm.assume(data.length != 8);
        vm.expectRevert(abi.encodeWithSelector(WrongUint64Length.selector, data.length));
        harness.toUint64(data);
    }

    function testToUint64Fuzz(uint64 value) public view {
        assertEq(harness.toUint64(abi.encodePacked(value)), value);
    }

    function testKeccakMatchesBuiltin() public view {
        bytes memory data = hex"deadbeefcafe";
        assertEq(harness.keccak(data), keccak256(data));
    }

    function testKeccakEmptyMatchesBuiltin() public view {
        assertEq(harness.keccak(bytes("")), keccak256(bytes("")));
    }

    function testKeccakFuzz(bytes calldata data) public view {
        assertEq(harness.keccak(data), keccak256(data));
    }
}
