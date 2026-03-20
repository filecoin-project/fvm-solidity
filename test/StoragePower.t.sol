// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {STORAGE_POWER_ACTOR_ID, STORAGE_POWER_ACTOR_ADDRESS} from "../src/FVMActors.sol";
import {CALL_ACTOR_BY_ID} from "../src/FVMPrecompiles.sol";
import {CBOR_CODEC} from "../src/FVMCodec.sol";
import {USR_NOT_FOUND, USR_UNHANDLED_MESSAGE} from "../src/FVMErrors.sol";
import {NO_FLAGS, READONLY_FLAG} from "../src/FVMFlags.sol";
import {MINER_POWER} from "../src/FVMMethod.sol";

contract StoragePowerTest is MockFVMTest {
    uint64 constant MINER_ID = 1234;

    // -------------------------------------------------------------------------
    // PowerAPI — minerPower via CALL_ACTOR_BY_ID
    // -------------------------------------------------------------------------

    // Registered miner: exit code 0, CBOR payload with has_min_power=true
    function testPowerAPI_RegisteredMiner_ReturnsPower() public {
        mockMiner(MINER_ID);
        (bool success, bytes memory ret) = _callPower(MINER_ID, READONLY_FLAG);
        assertTrue(success);
        (int256 exitCode, uint64 codec, bytes memory retData) = abi.decode(ret, (int256, uint64, bytes));
        assertEq(exitCode, 0);
        assertEq(codec, CBOR_CODEC);
        // retData: CBOR array(3) = [miner_claim, total_claim, has_min_power]
        assertEq(uint8(retData[0]), 0x83, "expected 3-element array");
        assertEq(uint8(retData[retData.length - 1]), 0xf5, "expected has_min_power=true");
    }

    // Both READONLY_FLAG and NO_FLAGS are accepted
    function testPowerAPI_NoFlags_AlsoAccepted() public {
        mockMiner(MINER_ID);
        (bool success, bytes memory ret) = _callPower(MINER_ID, NO_FLAGS);
        assertTrue(success);
        (int256 exitCode,,) = abi.decode(ret, (int256, uint64, bytes));
        assertEq(exitCode, 0);
    }

    // Unregistered miner: power actor returns actor_error!(not_found) → USR_NOT_FOUND (+14)
    function testPowerAPI_UnregisteredMiner_ReturnsNotFound() public {
        (bool success, bytes memory ret) = _callPower(MINER_ID, READONLY_FLAG);
        assertTrue(success);
        (int256 exitCode,,) = abi.decode(ret, (int256, uint64, bytes));
        assertEq(exitCode, int256(uint256(USR_NOT_FOUND)));
    }

    // -------------------------------------------------------------------------
    // Direct EVM CALL to StoragePower masked address
    // -------------------------------------------------------------------------

    // Real FVM: native actor (not an account actor) does not handle InvokeContract.
    // Un-etched address would return (true, "") like an account; etched mock returns USR_UNHANDLED_MESSAGE.
    function testDirectCall_ReturnsUnhandledMessage() public {
        (bool success, bytes memory ret) = STORAGE_POWER_ACTOR_ADDRESS.call(hex"deadbeef");
        assertTrue(success);
        (uint32 exitCode,,) = abi.decode(ret, (uint32, uint64, bytes));
        assertEq(exitCode, USR_UNHANDLED_MESSAGE);
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _callPower(uint64 minerId, uint64 flags) internal returns (bool, bytes memory) {
        bytes memory params = abi.encodePacked(uint8(0x81), _cborUint64(minerId));
        bytes memory callData = abi.encode(
            uint64(MINER_POWER), uint256(0), flags, uint64(CBOR_CODEC), params, uint64(STORAGE_POWER_ACTOR_ID)
        );
        return CALL_ACTOR_BY_ID.call(callData);
    }

    function _cborUint64(uint64 v) internal pure returns (bytes memory) {
        if (v <= 23) return abi.encodePacked(uint8(v));
        if (v <= 0xff) return abi.encodePacked(uint8(0x18), uint8(v));
        if (v <= 0xffff) return abi.encodePacked(uint8(0x19), uint16(v));
        if (v <= 0xffffffff) return abi.encodePacked(uint8(0x1a), uint32(v));
        return abi.encodePacked(uint8(0x1b), v);
    }
}
