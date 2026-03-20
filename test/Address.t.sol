// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {FVMAddress} from "../src/FVMAddress.sol";

contract FVMAddressTest is Test {
    // =============================================================
    //                     toEthAddress TESTS
    // =============================================================

    // Helper — lets vm.expectRevert work on a pure function
    function _toEthAddress(bytes memory delegated) public pure returns (address) {
        return FVMAddress.toEthAddress(delegated);
    }

    function testToEthAddressSuccess() public pure {
        address expected = address(0x1234567890123456789012345678901234567890);
        bytes memory delegated = abi.encodePacked(uint8(0x04), uint8(0x0a), expected);

        assertEq(FVMAddress.toEthAddress(delegated), expected);
    }

    function testToEthAddressTooShort() public {
        // 21 bytes — 1 short of the required 22
        bytes memory tooShort = abi.encodePacked(uint8(0x04), uint8(0x0a), bytes19(0));

        vm.expectRevert(FVMAddress.InvalidDelegatedAddress.selector);
        this._toEthAddress(tooShort);
    }

    function testToEthAddressTooLong() public {
        // 23 bytes — 1 extra byte
        bytes memory tooLong = abi.encodePacked(uint8(0x04), uint8(0x0a), address(1), uint8(0x00));

        vm.expectRevert(FVMAddress.InvalidDelegatedAddress.selector);
        this._toEthAddress(tooLong);
    }

    function testToEthAddressWrongProtocol() public {
        // Protocol byte 0x03 (f3) instead of 0x04 (f4)
        bytes memory wrongProtocol = abi.encodePacked(uint8(0x03), uint8(0x0a), address(1));

        vm.expectRevert(FVMAddress.InvalidDelegatedAddress.selector);
        this._toEthAddress(wrongProtocol);
    }

    function testToEthAddressWrongNamespace() public {
        // Correct protocol (0x04) but wrong namespace (0x0b instead of 0x0a)
        bytes memory wrongNamespace = abi.encodePacked(uint8(0x04), uint8(0x0b), address(1));

        vm.expectRevert(FVMAddress.InvalidDelegatedAddress.selector);
        this._toEthAddress(wrongNamespace);
    }

    function testToEthAddressEmpty() public {
        vm.expectRevert(FVMAddress.InvalidDelegatedAddress.selector);
        this._toEthAddress(new bytes(0));
    }

    function testFuzzToEthAddress(address addr) public pure {
        bytes memory delegated = abi.encodePacked(uint8(0x04), uint8(0x0a), addr);

        assertEq(FVMAddress.toEthAddress(delegated), addr);
    }

    // =============================================================
    //                         f0 TESTS
    // =============================================================

    function testF0ActorIdZero() public pure {
        // Protocol byte 0x00 + LEB128(0) = 0x00
        assertEq(FVMAddress.f0(0), hex"0000");
    }

    function testF0ActorId1() public pure {
        assertEq(FVMAddress.f0(1), hex"0001");
    }

    function testF0ActorId127() public pure {
        // 127 fits in a single LEB128 byte
        assertEq(FVMAddress.f0(127), hex"007f");
    }

    function testF0ActorId128MultiByteEncoding() public pure {
        // 128 in LEB128 = 0x80 0x01 (two bytes)
        assertEq(FVMAddress.f0(128), abi.encodePacked(uint8(0x00), uint8(0x80), uint8(0x01)));
    }

    function testF0ActorIdMaxUint64() public pure {
        bytes memory result = FVMAddress.f0(type(uint64).max);

        // Protocol byte + 10 LEB128 bytes for max uint64
        assertEq(result.length, 11);
        assertEq(uint8(result[0]), 0x00);
    }

    // =============================================================
    //                       f4 / f410 TESTS
    // =============================================================

    function testF410Encoding() public pure {
        address addr = address(1);
        bytes memory expected = abi.encodePacked(uint8(0x04), uint8(0x0a), addr);

        assertEq(FVMAddress.f410(addr), expected);
    }

    function testF4Encoding() public pure {
        uint8 namespace = 0x0a;
        bytes20 subaddress = bytes20(address(1));
        bytes memory expected = abi.encodePacked(uint8(0x04), namespace, subaddress);

        assertEq(FVMAddress.f4(namespace, subaddress), expected);
    }

    function testF410RoundTrip() public pure {
        address addr = address(1);

        assertEq(FVMAddress.toEthAddress(FVMAddress.f410(addr)), addr);
    }

    function testFuzzF410RoundTrip(address addr) public pure {
        assertEq(FVMAddress.toEthAddress(FVMAddress.f410(addr)), addr);
    }
}
