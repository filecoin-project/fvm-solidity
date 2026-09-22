// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {FVMAddress} from "../src/FVMAddress.sol";

contract DecodeF0 {
    function decode(bytes memory f0Address) public pure returns (uint64) {
        return FVMAddress.actorId(f0Address);
    }
}

contract F0AddressTest is Test {
    using FVMAddress for uint64;

    DecodeF0 decoder = new DecodeF0();

    function testDecodeZero() public pure {
        assertEq(FVMAddress.actorId(hex"0000"), 0);
    }

    function testDecodeVarint1Byte() public pure {
        assertEq(FVMAddress.actorId(hex"007f"), 2 ** 7 - 1);
    }

    function testDecodeVarint2Bytes() public pure {
        assertEq(FVMAddress.actorId(hex"00ff7f"), 2 ** 14 - 1);
    }

    function testDecodeVarint3Bytes() public pure {
        assertEq(FVMAddress.actorId(hex"00ffff7f"), 2 ** 21 - 1);
    }

    function testDecodeVarint4Bytes() public pure {
        assertEq(FVMAddress.actorId(hex"00ffffff7f"), 2 ** 28 - 1);
    }

    function testDecodeVarint5Bytes() public pure {
        assertEq(FVMAddress.actorId(hex"00ffffffff7f"), 2 ** 35 - 1);
    }

    function testDecodeVarint6Bytes() public pure {
        assertEq(FVMAddress.actorId(hex"00ffffffffff7f"), 2 ** 42 - 1);
    }

    function testDecodeVarint7Bytes() public pure {
        assertEq(FVMAddress.actorId(hex"00ffffffffffff7f"), 2 ** 49 - 1);
    }

    function testDecodeVarint8Bytes() public pure {
        assertEq(FVMAddress.actorId(hex"00ffffffffffffff7f"), 2 ** 56 - 1);
    }

    function testDecodeVarint9Bytes() public pure {
        assertEq(FVMAddress.actorId(hex"00ffffffffffffffff7f"), 2 ** 63 - 1);
    }

    function testDecodeVarint10Bytes() public pure {
        assertEq(FVMAddress.actorId(hex"00ffffffffffffffffff01"), type(uint64).max);
    }

    function testDecodeRejectsMalformed() public {
        bytes[9] memory malformed = [
            bytes(""), // empty
            hex"00", // no varint
            hex"0100", // not protocol 0
            hex"0080", // truncated varint
            hex"008000", // non-minimal varint
            hex"00ff00", // non-minimal varint
            hex"0080808080808080808002", // overflows uint64
            hex"008080808080808080808001", // too long
            hex"0001ff" // trailing byte
        ];

        for (uint256 i = 0; i < malformed.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(FVMAddress.InvalidF0Address.selector, malformed[i]));
            decoder.decode(malformed[i]);
        }
    }
}
