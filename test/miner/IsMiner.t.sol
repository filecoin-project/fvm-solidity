// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../../src/mocks/MockFVMTest.sol";
import {FVMMiner} from "../../src/FVMMiner.sol";
import {CALL_ACTOR_BY_ID} from "../../src/FVMPrecompiles.sol";
import {EMPTY_CODEC} from "../../src/FVMCodec.sol";
import {USR_ILLEGAL_STATE} from "../../src/FVMErrors.sol";

/// @dev External wrapper so vm.expectRevert targets the outer call, not the
///      internal delegatecall to CALL_ACTOR_BY_ID inside the library.
contract IsMinerCaller {
    function isMiner(uint64 actorId) external returns (bool) {
        return FVMMiner.isMiner(actorId);
    }
}

contract IsMinerTest is MockFVMTest {
    uint64 constant MINER_ID = 1234;
    uint64 constant OTHER_ID = 5678;

    IsMinerCaller caller;

    function setUp() public override {
        super.setUp();
        caller = new IsMinerCaller();
    }

    function testIsMiner_RegisteredMiner_ReturnsTrue() public {
        mockMiner(MINER_ID);
        assertTrue(FVMMiner.isMiner(MINER_ID));
    }

    function testIsMiner_UnregisteredActor_ReturnsFalse() public {
        assertFalse(FVMMiner.isMiner(MINER_ID));
    }

    function testIsMiner_OtherMinerUnaffected() public {
        mockMiner(MINER_ID);
        assertFalse(FVMMiner.isMiner(OTHER_ID));
    }

    function testIsMiner_MultipleMockMiners() public {
        mockMiner(MINER_ID);
        mockMiner(OTHER_ID);
        assertTrue(FVMMiner.isMiner(MINER_ID));
        assertTrue(FVMMiner.isMiner(OTHER_ID));
    }

    // Inject an unexpected exit code via vm.mockCall to exercise the IsMinerFailed revert path.
    function testIsMiner_UnexpectedExitCode_Reverts() public {
        bytes memory fakeRet = abi.encode(int256(uint256(USR_ILLEGAL_STATE)), uint64(EMPTY_CODEC), bytes(""));
        vm.mockCall(CALL_ACTOR_BY_ID, bytes(""), fakeRet);
        vm.expectRevert(abi.encodeWithSelector(FVMMiner.IsMinerFailed.selector, int256(uint256(USR_ILLEGAL_STATE))));
        caller.isMiner(MINER_ID);
    }

    function testIsMiner_FuzzActorId(uint64 actorId) public {
        assertFalse(FVMMiner.isMiner(actorId));
    }
}
