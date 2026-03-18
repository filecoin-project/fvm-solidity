// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {FVMMinerActor} from "../src/mocks/FVMMinerActor.sol";
import {FVMAddress} from "../src/FVMAddress.sol";
import {CBOR_CODEC} from "../src/FVMCodec.sol";
import {SECTOR_CONTENT_CHANGED} from "../src/FVMMethod.sol";
import {
    FVMSectorContentChanged,
    CalldataSlice,
    PieceChange,
    PieceChangeIter,
    PieceReturn,
    SectorChanges,
    SectorChangesHeader,
    SectorContentChangedParams,
    SectorContentChangedReturn,
    SectorReturn
} from "../src/FVMSectorContentChanged.sol";

// =============================================================
//              BENCHMARK RECEIVER CONTRACT
// =============================================================

/// @notice Iterator-path benchmark: calldata iterator → validate digest → abi.decode payload → encodeReturn
contract BenchIteratorReceiver {
    function handle_filecoin_method(uint64, uint64, bytes calldata) external returns (uint32, uint64, bytes memory) {
        uint256 numSectors;
        uint256 off;
        (numSectors, off) = FVMSectorContentChanged.readParamsHeader();

        SectorContentChangedReturn memory ret;
        ret.sectors = new SectorReturn[](numSectors);
        SectorChangesHeader memory header;
        PieceChangeIter memory piece;
        for (uint256 i = 0; i < numSectors; i++) {
            off = FVMSectorContentChanged.readSectorHeader(off, header);
            ret.sectors[i].added = new PieceReturn[](header.numPieces);
            for (uint256 j = 0; j < header.numPieces; j++) {
                off = FVMSectorContentChanged.readPiece(off, piece);
                // Materialise and validate: CID prefix was already stripped, so digest is 36 bytes
                bytes memory digest = FVMSectorContentChanged.loadSlice(piece.digest);
                require(digest.length == 36);
                // Decode and validate the allocation ID
                uint64 allocationId = abi.decode(FVMSectorContentChanged.loadSlice(piece.payload), (uint64));
                require(allocationId > 0);
                ret.sectors[i].added[j].accepted = true;
            }
        }
        return (0, CBOR_CODEC, FVMSectorContentChanged.encodeReturn(ret));
    }
}

// =============================================================
//          CALLDATA ITERATOR RECEIVER CONTRACT
// =============================================================

/// @notice Receiver that uses the zero-copy calldata iterator instead of decodeParams
contract IteratorReceiver {
    address public lastCaller;
    uint256 public numSectors;
    uint64 public lastSector;
    int64 public lastMinEpoch;
    uint256 public lastNumPieces;
    bytes public lastDigest;
    uint64 public lastPaddedSize;
    bytes public lastPayload;

    function handle_filecoin_method(uint64 method, uint64 codec, bytes calldata)
        external
        returns (uint32, uint64, bytes memory)
    {
        require(method == SECTOR_CONTENT_CHANGED, "wrong method");
        require(codec == CBOR_CODEC, "wrong codec");

        lastCaller = msg.sender;

        uint256 off;
        (numSectors, off) = FVMSectorContentChanged.readParamsHeader();

        SectorChangesHeader memory header;
        PieceChangeIter memory piece;
        for (uint256 i = 0; i < numSectors; i++) {
            off = FVMSectorContentChanged.readSectorHeader(off, header);
            lastSector = header.sector;
            lastMinEpoch = header.minimumCommitmentEpoch;
            lastNumPieces = header.numPieces;

            for (uint256 j = 0; j < header.numPieces; j++) {
                off = FVMSectorContentChanged.readPiece(off, piece);
                lastPaddedSize = piece.paddedSize;
                lastDigest = FVMSectorContentChanged.loadSlice(piece.digest);
                lastPayload = FVMSectorContentChanged.loadSlice(piece.payload);
            }
        }

        // Accept everything
        SectorContentChangedReturn memory ret;
        // (simplified: only handles last sector's piece count)
        ret.sectors = new SectorReturn[](numSectors);
        for (uint256 i = 0; i < numSectors; i++) {
            ret.sectors[i].added = new PieceReturn[](lastNumPieces);
            for (uint256 j = 0; j < lastNumPieces; j++) {
                ret.sectors[i].added[j].accepted = true;
            }
        }
        return (0, CBOR_CODEC, FVMSectorContentChanged.encodeReturn(ret));
    }
}

// =============================================================
//                          TESTS
// =============================================================

contract SectorContentChangedTest is MockFVMTest {
    using FVMAddress for uint64;

    IteratorReceiver iterReceiver;
    BenchIteratorReceiver benchIterator;

    // CommP CID (41 bytes): CIDv1 / raw / sha2-256-trunc254-padded / 36-byte digest
    bytes constant COMMP_CID = hex"0155912024cdf33e17483f8397390b0a963ded6e34a18f2fce6daa671716057f905f645b367a49ce18";
    // Just the 36-byte digest portion (skipping the 5-byte prefix 01 55 91 20 24)
    bytes constant COMMP_DIGEST = hex"cdf33e17483f8397390b0a963ded6e34a18f2fce6daa671716057f905f645b367a49ce18";
    bytes constant COMMP_CID2 = hex"0155912024cdf33e1783f2ff8261e66f95858ff85f976bbc0bf05ce8476d3e360832165cd0e480121d";
    bytes constant COMMP_DIGEST2 = hex"cdf33e1783f2ff8261e66f95858ff85f976bbc0bf05ce8476d3e360832165cd0e480121d";

    function setUp() public override {
        super.setUp();
        iterReceiver = new IteratorReceiver();
        benchIterator = new BenchIteratorReceiver();
    }

    function testReturnRoundtrip() public pure {
        SectorReturn[] memory sectorRets = new SectorReturn[](1);
        sectorRets[0].added = new PieceReturn[](2);
        sectorRets[0].added[0].accepted = true;
        sectorRets[0].added[1].accepted = false;

        SectorContentChangedReturn memory ret = SectorContentChangedReturn({sectors: sectorRets});

        bytes memory encoded = FVMSectorContentChanged.encodeReturn(ret);
        SectorContentChangedReturn memory decoded = FVMSectorContentChanged.decodeReturn(encoded);

        assertEq(decoded.sectors.length, 1);
        assertEq(decoded.sectors[0].added.length, 2);
        assertTrue(decoded.sectors[0].added[0].accepted);
        assertFalse(decoded.sectors[0].added[1].accepted);
    }

    // -------------------------
    // Mock miner
    // -------------------------

    function _buildParams(uint64 sector, bytes memory cid) internal pure returns (SectorContentChangedParams memory) {
        PieceChange[] memory pieces = new PieceChange[](1);
        pieces[0] = PieceChange({data: cid, size: 1024, payload: bytes("")});
        SectorChanges[] memory sectors = new SectorChanges[](1);
        sectors[0] = SectorChanges({sector: sector, minimumCommitmentEpoch: 0, added: pieces});
        return SectorContentChangedParams({sectors: sectors});
    }

    function testMockMinerMsgSenderIsMaskedAddress() public {
        uint64 minerActorId = 5678;
        FVMMinerActor miner = mockMiner(minerActorId);

        miner.callSectorContentChanged(address(iterReceiver), _buildParams(1, COMMP_CID));

        assertEq(iterReceiver.lastCaller(), minerActorId.maskedAddress());
    }

    function testMultipleMinersHaveDifferentMaskedAddresses() public {
        FVMMinerActor miner1 = mockMiner(100);
        FVMMinerActor miner2 = mockMiner(200);

        miner1.callSectorContentChanged(address(iterReceiver), _buildParams(1, COMMP_CID));
        assertEq(iterReceiver.lastCaller(), uint64(100).maskedAddress());

        miner2.callSectorContentChanged(address(iterReceiver), _buildParams(1, COMMP_CID2));
        assertEq(iterReceiver.lastCaller(), uint64(200).maskedAddress());
    }

    function testMockMinerRegistersForPowerAPI() public {
        assertFalse(CALL_ACTOR_BY_ID_PRECOMPILE.mockMiners(9999));
        mockMiner(9999);
        assertTrue(CALL_ACTOR_BY_ID_PRECOMPILE.mockMiners(9999));
    }

    // -------------------------
    // Calldata iterator
    // -------------------------

    function testIteratorDecodesCommPCid() public {
        FVMMinerActor miner = mockMiner(1234);

        PieceChange[] memory pieces = new PieceChange[](1);
        pieces[0] = PieceChange({data: COMMP_CID, size: 2048, payload: hex"deadbeef"});
        SectorChanges[] memory sectors = new SectorChanges[](1);
        sectors[0] = SectorChanges({sector: 77, minimumCommitmentEpoch: -5, added: pieces});
        SectorContentChangedParams memory params = SectorContentChangedParams({sectors: sectors});

        miner.callSectorContentChanged(address(iterReceiver), params);

        assertEq(iterReceiver.numSectors(), 1);
        assertEq(iterReceiver.lastSector(), 77);
        assertEq(iterReceiver.lastMinEpoch(), -5);
        assertEq(iterReceiver.lastNumPieces(), 1);
        assertEq(iterReceiver.lastPaddedSize(), 2048);
        assertEq(iterReceiver.lastDigest(), COMMP_DIGEST);
        assertEq(iterReceiver.lastPayload(), hex"deadbeef");
    }

    function testIteratorMultipleSectors() public {
        FVMMinerActor miner = mockMiner(5678);

        PieceChange[] memory pieces0 = new PieceChange[](1);
        pieces0[0] = PieceChange({data: COMMP_CID, size: 1024, payload: bytes("")});
        PieceChange[] memory pieces1 = new PieceChange[](1);
        pieces1[0] = PieceChange({data: COMMP_CID2, size: 4096, payload: hex"cafe"});

        SectorChanges[] memory sectors = new SectorChanges[](2);
        sectors[0] = SectorChanges({sector: 10, minimumCommitmentEpoch: 0, added: pieces0});
        sectors[1] = SectorChanges({sector: 20, minimumCommitmentEpoch: 999, added: pieces1});

        SectorContentChangedParams memory params = SectorContentChangedParams({sectors: sectors});
        miner.callSectorContentChanged(address(iterReceiver), params);

        // lastSector/lastDigest hold values from the final sector
        assertEq(iterReceiver.numSectors(), 2);
        assertEq(iterReceiver.lastSector(), 20);
        assertEq(iterReceiver.lastDigest(), COMMP_DIGEST2);
        assertEq(iterReceiver.lastPayload(), hex"cafe");
    }

    // -------------------------
    // Gas benchmarks (3 sectors × 3 pieces, CommP CIDs, abi.encoded allocation IDs)
    // -------------------------

    function _buildBenchParams() internal pure returns (SectorContentChangedParams memory) {
        SectorChanges[] memory sectors = new SectorChanges[](3);
        uint64 allocId = 1;
        bytes[2] memory cids = [COMMP_CID, COMMP_CID2];
        for (uint256 i = 0; i < 3; i++) {
            PieceChange[] memory pieces = new PieceChange[](3);
            for (uint256 j = 0; j < 3; j++) {
                pieces[j] =
                    PieceChange({data: cids[(i + j) % 2], size: uint64(2048 << j), payload: abi.encode(allocId++)});
            }
            sectors[i] = SectorChanges({
                sector: uint64(100 + i * 100), minimumCommitmentEpoch: int64(int256(i) * 1000), added: pieces
            });
        }
        return SectorContentChangedParams({sectors: sectors});
    }

    function testGasBenchIteratorPath() public {
        FVMMinerActor miner = mockMiner(9002);
        miner.callSectorContentChanged(address(benchIterator), _buildBenchParams());
    }
}
