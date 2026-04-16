// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {CalldataSlice, CalldataUtils, WrongAddressLength} from "../src/CalldataUtils.sol";

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
