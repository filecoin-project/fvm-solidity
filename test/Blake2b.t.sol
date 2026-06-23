// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {FVMBlake2b} from "../src/mocks/FVMBlake2b.sol";

contract Blake2bTest is Test {
    function testHash_EmptyString() public view {
        assertEq(
            FVMBlake2b.hash(bytes("")), bytes32(0x0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8)
        );
    }

    function testHash_Abc() public view {
        assertEq(
            FVMBlake2b.hash(bytes("abc")), bytes32(0xbddd813c634239723171ef3fee98579b94964e3bb1cb3e427262c8c068d52319)
        );
    }

    // hash20 produces the blake2b-20 variant (different initial constants, first 20 bytes of output).

    // Public key → f1 address vector from ref-fvm/shared/tests/address_test.rs.
    // pubkey [4,148,2,250,...] → f1 "f15ihq5ibzwki2b4ep2f46avlkrqzhpqgtga7pdrq"
    // Payload (blake2b-20 of the 65-byte uncompressed public key) decoded from the f1 address string.
    function testHash20_FilecoinF1AddressVector() public view {
        bytes memory pubKey =
            hex"049402fac37e6432a416a3a0ca5426b5185ab3b24f6134efa25ce487c82d2e4e13bf452511e0d2245421f8613bc10d72fa216666a96c3bc13920d3ff233fd0bc05";
        assertEq(pubKey.length, 65);
        assertEq(bytes32(FVMBlake2b.hash20(pubKey)), bytes32(hex"ea0f0ea039b291a0f08fd179e0556a8c3277c0d3"));
    }

    function testHash20_DiffersFromHash() public view {
        bytes memory data = bytes("test");
        assertTrue(bytes20(FVMBlake2b.hash(data)) != FVMBlake2b.hash20(data));
    }
}
