// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {USR_UNHANDLED_MESSAGE} from "../src/FVMErrors.sol";
import {FVMAddress} from "../src/FVMAddress.sol";

contract MinerTest is MockFVMTest {
    uint64 constant MINER_ID = 1234;

    // -------------------------------------------------------------------------
    // Direct EVM CALL to miner masked address
    // -------------------------------------------------------------------------

    // Real FVM: native actor returns USR_UNHANDLED_MESSAGE for InvokeContract (EVM CALL method).
    // Without a fallback, Solidity would revert; the mock returns USR_UNHANDLED_MESSAGE instead.
    function testDirectCall_ReturnsUnhandledMessage() public {
        mockMiner(MINER_ID);
        address minerAddr = FVMAddress.maskedAddress(MINER_ID);
        (bool success, bytes memory ret) = minerAddr.call(hex"deadbeef");
        assertTrue(success);
        (uint32 exitCode,,) = abi.decode(ret, (uint32, uint64, bytes));
        assertEq(exitCode, USR_UNHANDLED_MESSAGE);
    }
}
