// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

// =============================================================
//                          STRUCTS
// =============================================================

/// @notice A piece being added to a sector, as reported by the miner actor (FIP-0109)
struct PieceChange {
    /// @notice CID of the piece (raw bytes, 0x00 multibase prefix stripped)
    bytes data;
    /// @notice Padded piece size in bytes
    uint64 size;
    /// @notice Receiver-specific payload (e.g. CBOR-encoded allocation ID)
    bytes payload;
}

/// @notice Changes to a single sector, as reported by the miner actor
struct SectorChanges {
    uint64 sector;
    int64 minimumCommitmentEpoch;
    PieceChange[] added;
}

/// @notice Parameters for the SectorContentChanged notification (FIP-0109, method 2034386435)
struct SectorContentChangedParams {
    SectorChanges[] sectors;
}

/// @notice Per-piece response returned by the receiving contract
struct PieceReturn {
    bool accepted;
}

/// @notice Per-sector response returned by the receiving contract
struct SectorReturn {
    PieceReturn[] added;
}

/// @notice Return value for the SectorContentChanged notification
struct SectorContentChangedReturn {
    SectorReturn[] sectors;
}

// =============================================================
//             CALLDATA ITERATOR STRUCTS  (zero-copy)
// =============================================================

/// @notice A reference into calldata by absolute offset and byte length
struct CalldataSlice {
    uint256 offset;
    uint256 length;
}

/// @notice Sector header as decoded by the calldata iterator
struct SectorChangesHeader {
    uint64 sector;
    int64 minimumCommitmentEpoch;
    uint256 numPieces;
}

/// @notice Piece decoded by the calldata iterator; digest and payload are lazy calldata slices
struct PieceChangeIter {
    /// @notice Digest portion of the piece CID (CommP: 36 bytes, sha2-256-trunc254-padded)
    CalldataSlice digest;
    /// @notice Padded piece size in bytes
    uint64 paddedSize;
    /// @notice Receiver-specific payload; materialise on demand with FVMSectorContentChanged.loadSlice
    CalldataSlice payload;
}

// =============================================================
//                          LIBRARY
// =============================================================

library FVMSectorContentChanged {
    /// @dev CBOR major type byte did not match what was expected
    error UnexpectedCborMajorType(uint8 expected, uint8 actual);
    /// @dev CBOR array or byte string length exceeds what this decoder handles
    error CborLengthTooLarge();
    /// @dev A struct tuple array had the wrong number of elements
    error UnexpectedStructLength(uint256 expected, uint256 actual);
    /// @dev A CBOR bool value was neither 0xf4 (false) nor 0xf5 (true)
    error InvalidCborBool(uint8 actual);
    /// @dev CID was not encoded as CBOR tag 42
    error InvalidCidTag();

    // =========================================================
    //              ENCODE RETURN  (production use)
    // =========================================================

    /// @notice Encode SectorContentChangedReturn to CBOR
    /// @dev Receiving contracts call this to build the return value
    function encodeReturn(SectorContentChangedReturn memory ret) internal pure returns (bytes memory result) {
        bytes memory sectorsArr = _cborArrayHeader(ret.sectors.length);
        for (uint256 i = 0; i < ret.sectors.length; i++) {
            SectorReturn memory sr = ret.sectors[i];
            bytes memory piecesArr = _cborArrayHeader(sr.added.length);
            for (uint256 j = 0; j < sr.added.length; j++) {
                // PieceReturn = [accepted]
                piecesArr = abi.encodePacked(
                    piecesArr, _cborArrayHeader(1), sr.added[j].accepted ? bytes1(0xf5) : bytes1(0xf4)
                );
            }
            // SectorReturn = [added_array]
            sectorsArr = abi.encodePacked(sectorsArr, _cborArrayHeader(1), piecesArr);
        }
        // SectorContentChangedReturn = [sectors_array]
        return abi.encodePacked(_cborArrayHeader(1), sectorsArr);
    }

    // =========================================================
    //              ENCODE PARAMS  (test/mock use)
    // =========================================================

    /// @notice Encode SectorContentChangedParams to CBOR
    /// @dev Used by mocks to build the params that a miner actor would send
    function encodeParams(SectorContentChangedParams memory params) internal pure returns (bytes memory) {
        bytes memory sectorsArr = _cborArrayHeader(params.sectors.length);
        for (uint256 i = 0; i < params.sectors.length; i++) {
            sectorsArr = abi.encodePacked(sectorsArr, _encodeSectorChanges(params.sectors[i]));
        }
        return abi.encodePacked(_cborArrayHeader(1), sectorsArr);
    }

    function _encodeSectorChanges(SectorChanges memory sc) private pure returns (bytes memory) {
        bytes memory addedArr = _cborArrayHeader(sc.added.length);
        for (uint256 i = 0; i < sc.added.length; i++) {
            addedArr = abi.encodePacked(addedArr, _encodePieceChange(sc.added[i]));
        }
        return
            abi.encodePacked(
                _cborArrayHeader(3), _cborUint64(sc.sector), _cborInt64(sc.minimumCommitmentEpoch), addedArr
            );
    }

    function _encodePieceChange(PieceChange memory pc) private pure returns (bytes memory) {
        return abi.encodePacked(_cborArrayHeader(3), _cborCid(pc.data), _cborUint64(pc.size), _cborBytes(pc.payload));
    }

    // =========================================================
    //              DECODE RETURN  (test/mock use)
    // =========================================================

    /// @notice Decode CBOR-encoded SectorContentChangedReturn
    /// @dev Used by mocks/tests to parse the return value from a receiving contract
    function decodeReturn(bytes memory data) internal pure returns (SectorContentChangedReturn memory ret) {
        uint256 offset = 0;

        uint256 outerLen;
        (outerLen, offset) = _readArrayHeader(data, offset);
        require(outerLen == 1, UnexpectedStructLength(1, outerLen));

        uint256 numSectors;
        (numSectors, offset) = _readArrayHeader(data, offset);
        ret.sectors = new SectorReturn[](numSectors);
        for (uint256 i = 0; i < numSectors; i++) {
            // SectorReturn = [added_array]
            uint256 sectorRetLen;
            (sectorRetLen, offset) = _readArrayHeader(data, offset);
            require(sectorRetLen == 1, UnexpectedStructLength(1, sectorRetLen));

            uint256 numPieces;
            (numPieces, offset) = _readArrayHeader(data, offset);
            ret.sectors[i].added = new PieceReturn[](numPieces);
            for (uint256 j = 0; j < numPieces; j++) {
                // PieceReturn = [accepted]
                uint256 pieceRetLen;
                (pieceRetLen, offset) = _readArrayHeader(data, offset);
                require(pieceRetLen == 1, UnexpectedStructLength(1, pieceRetLen));

                uint8 b = uint8(data[offset++]);
                require(b == 0xf4 || b == 0xf5, InvalidCborBool(b));
                ret.sectors[i].added[j].accepted = (b == 0xf5);
            }
        }
    }

    // =========================================================
    //          CALLDATA ITERATOR  (zero-copy)
    // =========================================================

    /// @notice Calldata offset where the CBOR params bytes begin in handle_filecoin_method
    /// @dev ABI layout: 4 selector + 32 method + 32 codec + 32 params_offset + 32 params_length = 132
    uint256 private constant PARAMS_START = 132;

    /// @notice Read the outer params wrapper; returns the number of sectors and the offset of
    ///         the first sector's CBOR data within calldata.
    function readParamsHeader() internal pure returns (uint256 numSectors, uint256 nextOffset) {
        uint256 off = PARAMS_START;
        uint256 outerLen;
        (outerLen, off) = _cdReadArrayHeader(off);
        require(outerLen == 1, UnexpectedStructLength(1, outerLen));
        (numSectors, nextOffset) = _cdReadArrayHeader(off);
    }

    /// @notice Read one sector header at `cdOffset`; returns the header and the offset of the
    ///         first piece's CBOR data.
    function readSectorHeader(uint256 cdOffset)
        internal
        pure
        returns (SectorChangesHeader memory header, uint256 nextOffset)
    {
        uint256 len;
        (len, cdOffset) = _cdReadArrayHeader(cdOffset);
        require(len == 3, UnexpectedStructLength(3, len));
        (header.sector, cdOffset) = _cdReadUint64(cdOffset);
        (header.minimumCommitmentEpoch, cdOffset) = _cdReadInt64(cdOffset);
        (header.numPieces, nextOffset) = _cdReadArrayHeader(cdOffset);
    }

    /// @notice Read one piece at `cdOffset`; returns the piece and the offset of the next piece.
    function readPiece(uint256 cdOffset) internal pure returns (PieceChangeIter memory piece, uint256 nextOffset) {
        uint256 len;
        (len, cdOffset) = _cdReadArrayHeader(cdOffset);
        require(len == 3, UnexpectedStructLength(3, len));
        (piece.digest, cdOffset) = _cdReadCidDigest(cdOffset);
        (piece.paddedSize, cdOffset) = _cdReadUint64(cdOffset);
        (piece.payload, nextOffset) = _cdReadBytesSlice(cdOffset);
    }

    /// @notice Materialise a CalldataSlice into a new memory bytes array
    function loadSlice(CalldataSlice memory s) internal pure returns (bytes memory result) {
        uint256 off = s.offset;
        uint256 length = s.length;
        result = new bytes(length);
        assembly ("memory-safe") {
            calldatacopy(add(result, 32), off, length)
        }
    }

    // --- calldata CBOR read primitives ---

    function _cdReadArrayHeader(uint256 offset) private pure returns (uint256 len, uint256 newOffset) {
        uint8 b;
        assembly ("memory-safe") {
            b := byte(0, calldataload(offset))
        }
        offset++;
        require((b >> 5) == 4, UnexpectedCborMajorType(4, b >> 5));
        uint8 info = b & 0x1f;
        if (info <= 23) return (uint256(info), offset);
        if (info == 24) {
            assembly ("memory-safe") {
                len := byte(0, calldataload(offset))
            }
            return (len, offset + 1);
        }
        if (info == 25) {
            assembly ("memory-safe") {
                len := shr(240, calldataload(offset))
            }
            return (len, offset + 2);
        }
        revert CborLengthTooLarge();
    }

    function _cdReadUint64(uint256 offset) private pure returns (uint64 v, uint256 newOffset) {
        uint8 b;
        assembly ("memory-safe") {
            b := byte(0, calldataload(offset))
        }
        offset++;
        require((b >> 5) == 0, UnexpectedCborMajorType(0, b >> 5));
        uint8 info = b & 0x1f;
        if (info <= 23) return (uint64(info), offset);
        if (info == 24) {
            assembly ("memory-safe") {
                v := byte(0, calldataload(offset))
            }
            return (v, offset + 1);
        }
        if (info == 25) {
            assembly ("memory-safe") {
                v := shr(240, calldataload(offset))
            }
            return (v, offset + 2);
        }
        if (info == 26) {
            assembly ("memory-safe") {
                v := shr(224, calldataload(offset))
            }
            return (v, offset + 4);
        }
        if (info == 27) {
            assembly ("memory-safe") {
                v := shr(192, calldataload(offset))
            }
            return (v, offset + 8);
        }
        revert CborLengthTooLarge();
    }

    function _cdReadInt64(uint256 offset) private pure returns (int64 v, uint256 newOffset) {
        uint8 b;
        assembly ("memory-safe") {
            b := byte(0, calldataload(offset))
        }
        uint8 major = b >> 5;
        if (major == 0) {
            uint64 u;
            (u, newOffset) = _cdReadUint64(offset);
            return (int64(u), newOffset);
        }
        require(major == 1, UnexpectedCborMajorType(1, major));
        offset++;
        uint8 info = b & 0x1f;
        uint64 n;
        if (info <= 23) {
            n = uint64(info);
            newOffset = offset;
        } else if (info == 24) {
            assembly ("memory-safe") {
                n := byte(0, calldataload(offset))
            }
            newOffset = offset + 1;
        } else if (info == 25) {
            assembly ("memory-safe") {
                n := shr(240, calldataload(offset))
            }
            newOffset = offset + 2;
        } else {
            revert CborLengthTooLarge();
        }
        v = -1 - int64(n);
    }

    function _cdReadBytesLen(uint256 offset) private pure returns (uint256 len, uint256 newOffset) {
        uint8 b;
        assembly ("memory-safe") {
            b := byte(0, calldataload(offset))
        }
        offset++;
        require((b >> 5) == 2, UnexpectedCborMajorType(2, b >> 5));
        uint8 info = b & 0x1f;
        if (info <= 23) return (uint256(info), offset);
        if (info == 24) {
            assembly ("memory-safe") {
                len := byte(0, calldataload(offset))
            }
            return (len, offset + 1);
        }
        if (info == 25) {
            assembly ("memory-safe") {
                len := shr(240, calldataload(offset))
            }
            return (len, offset + 2);
        }
        revert CborLengthTooLarge();
    }

    function _cdReadBytesSlice(uint256 offset) private pure returns (CalldataSlice memory slice, uint256 newOffset) {
        (slice.length, offset) = _cdReadBytesLen(offset);
        slice.offset = offset;
        newOffset = offset + slice.length;
    }

    /// @notice Read a CBOR tag-42 CID from calldata, strip the 0x00 multibase prefix and the
    ///         5-byte CID header, and return a CalldataSlice pointing at the raw digest bytes.
    /// @dev CommP CID header is always: 01 55 91 20 24 (CIDv1 / raw / sha2-256-trunc254-padded / 36-byte digest)
    function _cdReadCidDigest(uint256 offset) private pure returns (CalldataSlice memory digest, uint256 newOffset) {
        // CBOR tag 42 encodes as two bytes: 0xd8 0x2a
        uint16 tag;
        assembly ("memory-safe") {
            tag := shr(240, calldataload(offset))
        }
        require(tag == 0xd82a, InvalidCidTag());
        offset += 2;

        // Byte-string containing 0x00 multibase prefix + raw CID bytes
        uint256 bytesLen;
        (bytesLen, offset) = _cdReadBytesLen(offset);

        // Strip 0x00 identity multibase prefix
        uint8 multibase;
        assembly ("memory-safe") {
            multibase := byte(0, calldataload(offset))
        }
        require(multibase == 0x00, InvalidCidTag());
        offset++;

        // Skip the 5-byte CID header (version + codec + multihash fn + digest length varints)
        // so the slice starts at the raw digest bytes.
        offset += 5;
        digest.offset = offset;
        digest.length = bytesLen - 1 - 5; // subtract multibase byte and CID header
        newOffset = offset + digest.length;
    }

    // =========================================================
    //                  CBOR WRITE PRIMITIVES
    // =========================================================

    function _cborArrayHeader(uint256 len) private pure returns (bytes memory) {
        if (len <= 23) return abi.encodePacked(uint8(0x80 | uint8(len)));
        if (len <= 0xff) return abi.encodePacked(uint8(0x98), uint8(len));
        if (len <= 0xffff) return abi.encodePacked(uint8(0x99), uint16(len));
        return abi.encodePacked(uint8(0x9a), uint32(len));
    }

    function _cborUint64(uint64 v) private pure returns (bytes memory) {
        if (v <= 23) return abi.encodePacked(uint8(v));
        if (v <= 0xff) return abi.encodePacked(uint8(0x18), uint8(v));
        if (v <= 0xffff) return abi.encodePacked(uint8(0x19), uint16(v));
        if (v <= 0xffffffff) return abi.encodePacked(uint8(0x1a), uint32(v));
        return abi.encodePacked(uint8(0x1b), v);
    }

    function _cborInt64(int64 v) private pure returns (bytes memory) {
        if (v >= 0) return _cborUint64(uint64(v));
        uint64 n = uint64(-1 - v);
        if (n <= 23) return abi.encodePacked(uint8(0x20 | uint8(n)));
        if (n <= 0xff) return abi.encodePacked(uint8(0x38), uint8(n));
        if (n <= 0xffff) return abi.encodePacked(uint8(0x39), uint16(n));
        if (n <= 0xffffffff) return abi.encodePacked(uint8(0x3a), uint32(n));
        return abi.encodePacked(uint8(0x3b), n);
    }

    function _cborBytes(bytes memory b) private pure returns (bytes memory) {
        uint256 len = b.length;
        bytes memory header;
        if (len <= 23) header = abi.encodePacked(uint8(0x40 | uint8(len)));
        else if (len <= 0xff) header = abi.encodePacked(uint8(0x58), uint8(len));
        else if (len <= 0xffff) header = abi.encodePacked(uint8(0x59), uint16(len));
        else header = abi.encodePacked(uint8(0x5a), uint32(len));
        return abi.encodePacked(header, b);
    }

    /// @notice Encode a CID as CBOR tag 42 + bytes(0x00 ++ cid)
    /// @dev `cid` is raw CID bytes without the 0x00 multibase prefix
    function _cborCid(bytes memory cid) private pure returns (bytes memory) {
        return abi.encodePacked(bytes2(0xd82a), _cborBytes(abi.encodePacked(bytes1(0x00), cid)));
    }

    // =========================================================
    //                  CBOR READ PRIMITIVES
    // =========================================================

    function _readArrayHeader(bytes memory data, uint256 offset) private pure returns (uint256 len, uint256 newOffset) {
        uint8 b = uint8(data[offset++]);
        require((b >> 5) == 4, UnexpectedCborMajorType(4, b >> 5));
        uint8 info = b & 0x1f;
        if (info <= 23) return (uint256(info), offset);
        if (info == 24) return (uint256(uint8(data[offset])), offset + 1);
        if (info == 25) {
            len = (uint256(uint8(data[offset])) << 8) | uint256(uint8(data[offset + 1]));
            return (len, offset + 2);
        }
        revert CborLengthTooLarge();
    }

}
