// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

/// @notice Blake2b using the EIP-152 blake2f precompile (address 9).
/// @dev For use in tests. Lets you sign messages the Filecoin way:
///      `vm.sign(key, FVMBlake2b.hash(message))` produces signatures that
///      a real f1 account actor would accept via AuthenticateMessage.
///
///      `hash20` computes the blake2b-20 digest used to derive Filecoin f1 address payloads:
///      `f1Payload = hash20(abi.encodePacked(uint8(0x04), wallet.publicKeyX, wallet.publicKeyY))`
library FVMBlake2b {
    // Initial h state for blake2b with no key.
    // h[0] = IV[0] XOR parameter_block_word_0  (only byte 0 of h[0] LE varies by digest length).
    // h[1..7] = IV[1..7] unchanged across variants.
    //
    // Parameter word 0 as LE uint64: [digest_len, 0, 1, 1, 0, 0, 0, 0]
    //   blake2b-256: digest_len=0x20 → h[0]=0x6A09E667F2BDC928 → LE: 28C9BDF267E6096A
    //   blake2b-20:  digest_len=0x14 → h[0]=0x6A09E667F2BDC91C → LE: 1CC9BDF267E6096A
    uint256 private constant H_LO = 0x28C9BDF267E6096A3BA7CA8485AE67BB2BF894FE72F36E3CF1361D5F3AF54FA5;
    uint256 private constant H_LO_20 = 0x1CC9BDF267E6096A3BA7CA8485AE67BB2BF894FE72F36E3CF1361D5F3AF54FA5;
    uint256 private constant H_HI = 0xD182E6AD7F520E511F6C3E2B8C68059B6BBD41FBABD9831F79217E1319CDE05B;

    /// @notice Compute the blake2b-256 digest of `data`.
    function hash(bytes memory data) internal view returns (bytes32 digest) {
        digest = _hash(data, H_LO, H_HI);
    }

    /// @notice Compute the blake2b-20 digest of `data`.
    /// @dev Used to derive Filecoin f1 address payloads from secp256k1 public keys.
    function hash20(bytes memory data) internal view returns (bytes20 digest) {
        digest = bytes20(_hash(data, H_LO_20, H_HI));
    }

    function _hash(bytes memory data, uint256 initHLo, uint256 initHHi) private view returns (bytes32 result) {
        assembly ("memory-safe") {
            let len := mload(data)
            let src := add(data, 0x20)

            let hLo := initHLo
            let hHi := initHHi

            // 256-byte scratch buffer; 213 bytes consumed by the precompile, 64 returned.
            let ptr := mload(0x40)
            mstore(0x40, add(ptr, 256))

            let offset := 0

            // Process all complete non-final 128-byte blocks.
            for {} gt(sub(len, offset), 128) {} {
                mstore(ptr, shl(224, 12)) // rounds = 12 (big-endian uint32)
                mstore(add(ptr, 4), hLo) // h[0..3] in LE
                mstore(add(ptr, 36), hHi) // h[4..7] in LE
                // Copy 128 bytes of message as four 32-byte words.
                mstore(add(ptr, 68), mload(add(src, offset)))
                mstore(add(ptr, 100), mload(add(src, add(offset, 32))))
                mstore(add(ptr, 132), mload(add(src, add(offset, 64))))
                mstore(add(ptr, 164), mload(add(src, add(offset, 96))))

                offset := add(offset, 128)

                // Byte-swap offset (uint64) into little-endian for the t[0] counter field.
                let c := offset
                c := or(shr(8, and(c, 0xff00ff00ff00ff00)), shl(8, and(c, 0x00ff00ff00ff00ff)))
                c := or(shr(16, and(c, 0xffff0000ffff0000)), shl(16, and(c, 0x0000ffff0000ffff)))
                c := or(shr(32, c), shl(32, and(c, 0x00000000ffffffff)))

                mstore(add(ptr, 196), shl(192, c)) // t[0] LE at bytes 196-203
                mstore(add(ptr, 204), 0) // t[1]=0, final=0 at bytes 204-235

                if iszero(staticcall(gas(), 9, ptr, 213, ptr, 64)) { revert(0, 0) }

                hLo := mload(ptr)
                hHi := mload(add(ptr, 32))
            }

            // Final block: zero-pad to 128 bytes, then copy remaining input bytes.
            mstore(ptr, shl(224, 12))
            mstore(add(ptr, 4), hLo)
            mstore(add(ptr, 36), hHi)
            mstore(add(ptr, 68), 0)
            mstore(add(ptr, 100), 0)
            mstore(add(ptr, 132), 0)
            mstore(add(ptr, 164), 0)

            let blockLen := sub(len, offset)
            let dstBase := add(ptr, 68)
            let srcBase := add(src, offset)
            // Copy complete 32-byte words.
            let i := 0
            for {} lt(i, and(blockLen, not(31))) { i := add(i, 32) } { mstore(add(dstBase, i), mload(add(srcBase, i))) }
            // Copy partial last word (mask out bytes beyond blockLen).
            if lt(i, blockLen) {
                let remaining := sub(blockLen, i)
                mstore(add(dstBase, i), and(mload(add(srcBase, i)), shl(mul(8, sub(32, remaining)), not(0))))
            }

            // Counter = total message bytes (len), byte-swapped to little-endian uint64.
            let c := len
            c := or(shr(8, and(c, 0xff00ff00ff00ff00)), shl(8, and(c, 0x00ff00ff00ff00ff)))
            c := or(shr(16, and(c, 0xffff0000ffff0000)), shl(16, and(c, 0x0000ffff0000ffff)))
            c := or(shr(32, c), shl(32, and(c, 0x00000000ffffffff)))

            mstore(add(ptr, 196), shl(192, c))
            mstore(add(ptr, 204), 0)
            mstore8(add(ptr, 212), 1) // final flag

            if iszero(staticcall(gas(), 9, ptr, 213, ptr, 64)) { revert(0, 0) }

            // Return first 32 bytes of updated h state.
            // For hash20, the caller takes bytes20(...) which reads the first 20 bytes.
            result := mload(ptr)
        }
    }
}
