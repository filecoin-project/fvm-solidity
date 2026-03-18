// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {FVMMinerActor} from "../src/mocks/FVMMinerActor.sol";
import {FVMAddress} from "../src/FVMAddress.sol";
import {CBOR_CODEC} from "../src/FVMCodec.sol";
import {SECTOR_CONTENT_CHANGED} from "../src/FVMMethod.sol";
import {
    FVMSectorContentChanged,
    PieceChange,
    PieceReturn,
    SectorChanges,
    SectorContentChangedParams,
    SectorContentChangedReturn,
    SectorReturn
} from "../src/FVMSectorContentChanged.sol";

// =============================================================
//              EXAMPLE RECEIVER CONTRACT
// =============================================================

/// @notice Minimal example of a contract that handles SectorContentChanged
contract SectorContentChangedReceiver {
    address public lastCaller;

    function handle_filecoin_method(uint64 method, uint64 codec, bytes calldata params)
        external
        returns (uint32, uint64, bytes memory)
    {
        require(method == SECTOR_CONTENT_CHANGED, "wrong method");
        require(codec == CBOR_CODEC, "wrong codec");

        lastCaller = msg.sender;

        SectorContentChangedParams memory p = FVMSectorContentChanged.decodeParams(params);

        SectorContentChangedReturn memory ret;
        ret.sectors = new SectorReturn[](p.sectors.length);
        for (uint256 i = 0; i < p.sectors.length; i++) {
            ret.sectors[i].added = new PieceReturn[](p.sectors[i].added.length);
            for (uint256 j = 0; j < p.sectors[i].added.length; j++) {
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

    SectorContentChangedReceiver receiver;

    function setUp() public override {
        super.setUp();
        receiver = new SectorContentChangedReceiver();
    }

    // -------------------------
    // CBOR roundtrip
    // -------------------------

    function testCborRoundtripSinglePiece() public pure {
        PieceChange[] memory pieces = new PieceChange[](1);
        pieces[0] = PieceChange({
            data: hex"0155122012209e0a8f7b83c06a2d28a08d7b4b2b5a70c47e6a97f56d",
            size: 2048,
            payload: abi.encodePacked(uint64(42))
        });

        SectorChanges[] memory sectors = new SectorChanges[](1);
        sectors[0] = SectorChanges({sector: 100, minimumCommitmentEpoch: 5000, added: pieces});

        SectorContentChangedParams memory params = SectorContentChangedParams({sectors: sectors});

        bytes memory encoded = FVMSectorContentChanged.encodeParams(params);
        SectorContentChangedParams memory decoded = FVMSectorContentChanged.decodeParams(encoded);

        assertEq(decoded.sectors.length, 1);
        assertEq(decoded.sectors[0].sector, 100);
        assertEq(decoded.sectors[0].minimumCommitmentEpoch, 5000);
        assertEq(decoded.sectors[0].added.length, 1);
        assertEq(decoded.sectors[0].added[0].data, pieces[0].data);
        assertEq(decoded.sectors[0].added[0].size, 2048);
        assertEq(decoded.sectors[0].added[0].payload, abi.encodePacked(uint64(42)));
    }

    function testCborRoundtripNegativeEpoch() public pure {
        PieceChange[] memory pieces = new PieceChange[](1);
        pieces[0] = PieceChange({data: hex"01", size: 512, payload: bytes("")});

        SectorChanges[] memory sectors = new SectorChanges[](1);
        sectors[0] = SectorChanges({sector: 1, minimumCommitmentEpoch: -100, added: pieces});

        SectorContentChangedParams memory params = SectorContentChangedParams({sectors: sectors});

        bytes memory encoded = FVMSectorContentChanged.encodeParams(params);
        SectorContentChangedParams memory decoded = FVMSectorContentChanged.decodeParams(encoded);

        assertEq(decoded.sectors[0].minimumCommitmentEpoch, -100);
    }

    function testCborRoundtripMultipleSectorsAndPieces() public pure {
        PieceChange[] memory pieces0 = new PieceChange[](2);
        pieces0[0] = PieceChange({data: hex"aabb", size: 1024, payload: bytes("")});
        pieces0[1] = PieceChange({data: hex"ccdd", size: 2048, payload: hex"0102"});

        PieceChange[] memory pieces1 = new PieceChange[](1);
        pieces1[0] = PieceChange({data: hex"eeff", size: 4096, payload: bytes("")});

        SectorChanges[] memory sectors = new SectorChanges[](2);
        sectors[0] = SectorChanges({sector: 10, minimumCommitmentEpoch: 0, added: pieces0});
        sectors[1] = SectorChanges({sector: 20, minimumCommitmentEpoch: 1000, added: pieces1});

        SectorContentChangedParams memory params = SectorContentChangedParams({sectors: sectors});

        bytes memory encoded = FVMSectorContentChanged.encodeParams(params);
        SectorContentChangedParams memory decoded = FVMSectorContentChanged.decodeParams(encoded);

        assertEq(decoded.sectors.length, 2);
        assertEq(decoded.sectors[0].added.length, 2);
        assertEq(decoded.sectors[1].added.length, 1);
        assertEq(decoded.sectors[0].added[1].data, hex"ccdd");
        assertEq(decoded.sectors[1].added[0].size, 4096);
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

    function testMockMinerCallsHandleFilecoinMethod() public {
        FVMMinerActor miner = mockMiner(1234);
        SectorContentChangedParams memory params = _buildParams(42, hex"deadbeef");

        vm.expectCall(address(receiver), abi.encodeWithSelector(receiver.handle_filecoin_method.selector));
        miner.callSectorContentChanged(address(receiver), params);
    }

    function testMockMinerMsgSenderIsMaskedAddress() public {
        uint64 minerActorId = 5678;
        FVMMinerActor miner = mockMiner(minerActorId);

        miner.callSectorContentChanged(address(receiver), _buildParams(1, hex"01"));

        assertEq(receiver.lastCaller(), minerActorId.maskedAddress());
    }

    function testMockMinerReturnIsDecoded() public {
        FVMMinerActor miner = mockMiner(1234);
        SectorContentChangedReturn memory ret =
            miner.callSectorContentChanged(address(receiver), _buildParams(42, hex"deadbeef"));

        assertTrue(ret.sectors[0].added[0].accepted);
    }

    function testMultipleMinersHaveDifferentMaskedAddresses() public {
        FVMMinerActor miner1 = mockMiner(100);
        FVMMinerActor miner2 = mockMiner(200);

        miner1.callSectorContentChanged(address(receiver), _buildParams(1, hex"aa"));
        assertEq(receiver.lastCaller(), uint64(100).maskedAddress());

        miner2.callSectorContentChanged(address(receiver), _buildParams(1, hex"bb"));
        assertEq(receiver.lastCaller(), uint64(200).maskedAddress());
    }

    function testMockMinerRegistersForPowerAPI() public {
        assertFalse(CALL_ACTOR_BY_ID_PRECOMPILE.mockMiners(9999));
        mockMiner(9999);
        assertTrue(CALL_ACTOR_BY_ID_PRECOMPILE.mockMiners(9999));
    }
}
