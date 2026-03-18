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
//                          LIBRARY
// =============================================================

library FVMSectorContentChanged {
    // =========================================================
    //              DECODE PARAMS  (production use)
    // =========================================================

    /// @notice Decode CBOR-encoded SectorContentChangedParams
    /// @dev Receiving contracts call this to parse the inbound notification
    function decodeParams(bytes memory data) internal pure returns (SectorContentChangedParams memory params) {
        uint256 offset = 0;

        // Outer 1-element tuple (SectorContentChangedParams struct)
        uint256 outerLen;
        (outerLen, offset) = _readArrayHeader(data, offset);
        require(outerLen == 1, "SCC: expected 1-element outer array");

        // Sectors list
        uint256 numSectors;
        (numSectors, offset) = _readArrayHeader(data, offset);
        params.sectors = new SectorChanges[](numSectors);
        for (uint256 i = 0; i < numSectors; i++) {
            (params.sectors[i], offset) = _decodeSectorChanges(data, offset);
        }
    }

    function _decodeSectorChanges(bytes memory data, uint256 offset)
        private
        pure
        returns (SectorChanges memory sc, uint256 newOffset)
    {
        uint256 len;
        (len, offset) = _readArrayHeader(data, offset);
        require(len == 3, "SCC: expected 3-element SectorChanges");

        (sc.sector, offset) = _readUint64(data, offset);
        (sc.minimumCommitmentEpoch, offset) = _readInt64(data, offset);

        uint256 numPieces;
        (numPieces, offset) = _readArrayHeader(data, offset);
        sc.added = new PieceChange[](numPieces);
        for (uint256 i = 0; i < numPieces; i++) {
            (sc.added[i], offset) = _decodePieceChange(data, offset);
        }
        return (sc, offset);
    }

    function _decodePieceChange(bytes memory data, uint256 offset)
        private
        pure
        returns (PieceChange memory pc, uint256 newOffset)
    {
        uint256 len;
        (len, offset) = _readArrayHeader(data, offset);
        require(len == 3, "SCC: expected 3-element PieceChange");

        (pc.data, offset) = _readCid(data, offset); // 0x00 prefix stripped
        (pc.size, offset) = _readUint64(data, offset);
        (pc.payload, offset) = _readBytes(data, offset);
        return (pc, offset);
    }

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
        require(outerLen == 1, "SCC: expected 1-element outer array");

        uint256 numSectors;
        (numSectors, offset) = _readArrayHeader(data, offset);
        ret.sectors = new SectorReturn[](numSectors);
        for (uint256 i = 0; i < numSectors; i++) {
            // SectorReturn = [added_array]
            uint256 sectorRetLen;
            (sectorRetLen, offset) = _readArrayHeader(data, offset);
            require(sectorRetLen == 1, "SCC: expected 1-element SectorReturn");

            uint256 numPieces;
            (numPieces, offset) = _readArrayHeader(data, offset);
            ret.sectors[i].added = new PieceReturn[](numPieces);
            for (uint256 j = 0; j < numPieces; j++) {
                // PieceReturn = [accepted]
                uint256 pieceRetLen;
                (pieceRetLen, offset) = _readArrayHeader(data, offset);
                require(pieceRetLen == 1, "SCC: expected 1-element PieceReturn");

                uint8 b = uint8(data[offset++]);
                require(b == 0xf4 || b == 0xf5, "SCC: expected bool");
                ret.sectors[i].added[j].accepted = (b == 0xf5);
            }
        }
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
        require((b >> 5) == 4, "SCC: expected CBOR array");
        uint8 info = b & 0x1f;
        if (info <= 23) return (uint256(info), offset);
        if (info == 24) return (uint256(uint8(data[offset])), offset + 1);
        if (info == 25) {
            len = (uint256(uint8(data[offset])) << 8) | uint256(uint8(data[offset + 1]));
            return (len, offset + 2);
        }
        revert("SCC: array length too large");
    }

    function _readUint64(bytes memory data, uint256 offset) private pure returns (uint64 v, uint256 newOffset) {
        uint8 b = uint8(data[offset++]);
        require((b >> 5) == 0, "SCC: expected CBOR uint");
        uint8 info = b & 0x1f;
        if (info <= 23) return (uint64(info), offset);
        if (info == 24) return (uint64(uint8(data[offset])), offset + 1);
        if (info == 25) {
            v = (uint64(uint8(data[offset])) << 8) | uint64(uint8(data[offset + 1]));
            return (v, offset + 2);
        }
        if (info == 26) {
            v = (uint64(uint8(data[offset])) << 24) | (uint64(uint8(data[offset + 1])) << 16)
                | (uint64(uint8(data[offset + 2])) << 8) | uint64(uint8(data[offset + 3]));
            return (v, offset + 4);
        }
        if (info == 27) {
            for (uint256 i = 0; i < 8; i++) {
                v = (v << 8) | uint64(uint8(data[offset + i]));
            }
            return (v, offset + 8);
        }
        revert("SCC: uint64 too large");
    }

    function _readInt64(bytes memory data, uint256 offset) private pure returns (int64 v, uint256 newOffset) {
        uint8 b = uint8(data[offset]);
        uint8 major = b >> 5;
        if (major == 0) {
            uint64 u;
            (u, newOffset) = _readUint64(data, offset);
            return (int64(u), newOffset);
        }
        require(major == 1, "SCC: expected CBOR int");
        offset++;
        uint8 info = b & 0x1f;
        uint64 n;
        if (info <= 23) {
            n = uint64(info);
        } else if (info == 24) {
            n = uint64(uint8(data[offset++]));
        } else if (info == 25) {
            n = (uint64(uint8(data[offset])) << 8) | uint64(uint8(data[offset + 1]));
            offset += 2;
        } else {
            revert("SCC: int64 too large");
        }
        return (-1 - int64(n), offset);
    }

    function _readBytes(bytes memory data, uint256 offset)
        private
        pure
        returns (bytes memory result, uint256 newOffset)
    {
        uint8 b = uint8(data[offset++]);
        require((b >> 5) == 2, "SCC: expected CBOR bytes");
        uint8 info = b & 0x1f;
        uint256 len;
        if (info <= 23) {
            len = uint256(info);
        } else if (info == 24) {
            len = uint256(uint8(data[offset++]));
        } else if (info == 25) {
            len = (uint256(uint8(data[offset])) << 8) | uint256(uint8(data[offset + 1]));
            offset += 2;
        } else {
            revert("SCC: bytes too large");
        }
        result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = data[offset + i];
        }
        return (result, offset + len);
    }

    /// @notice Read a CID from CBOR (tag 42 + bytes), stripping the 0x00 multibase prefix
    function _readCid(bytes memory data, uint256 offset) private pure returns (bytes memory cid, uint256 newOffset) {
        require(uint8(data[offset]) == 0xd8, "SCC: expected CBOR tag");
        require(uint8(data[offset + 1]) == 0x2a, "SCC: expected tag 42");
        offset += 2;
        bytes memory raw;
        (raw, newOffset) = _readBytes(data, offset);
        // Strip 0x00 identity multibase prefix
        if (raw.length > 0 && uint8(raw[0]) == 0x00) {
            cid = new bytes(raw.length - 1);
            for (uint256 i = 0; i < cid.length; i++) {
                cid[i] = raw[i + 1];
            }
        } else {
            cid = raw;
        }
    }
}
