// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {NOT_FOUND} from "../src/FVMErrors.sol";
import {CALL_ACTOR_BY_ID} from "../src/FVMPrecompiles.sol";

contract CallActorByIdTest is MockFVMTest {
    // -------------------------------------------------------------------------
    // Precompile routing
    // -------------------------------------------------------------------------

    // Actor ID that is not burn, power, or a registered miner: no actor in mock state.
    // Real FVM: send_raw returns ErrorNumber::NotFound → success=true, exit code NOT_FOUND (-6).
    function testUnknownActor_ReturnsNotFound() public {
        bytes memory callData = abi.encode(uint64(0), uint256(0), uint64(0), uint64(0), bytes(""), uint64(7777));
        (bool success, bytes memory ret) = CALL_ACTOR_BY_ID.call(callData);
        assertTrue(success);
        (int256 exitCode,,) = abi.decode(ret, (int256, uint64, bytes));
        assertEq(exitCode, NOT_FOUND);
    }
}
