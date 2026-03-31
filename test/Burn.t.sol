// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {BURN_ACTOR_ID, BURN_ADDRESS} from "../src/FVMActors.sol";
import {EMPTY_CODEC, RAW_CODEC} from "../src/FVMCodec.sol";
import {READ_ONLY, USR_UNHANDLED_MESSAGE} from "../src/FVMErrors.sol";
import {NO_FLAGS, READONLY_FLAG} from "../src/FVMFlags.sol";
import {SEND, INVOKE_EVM} from "../src/FVMMethod.sol";
import {CALL_ACTOR_BY_ID} from "../src/FVMPrecompiles.sol";
import {FVMPay} from "../src/FVMPay.sol";

contract BurnTest is MockFVMTest {
    using FVMPay for uint64;
    using FVMPay for uint256;
    using FVMPay for address;
    using FVMPay for address payable;

    function testBurn() public {
        assertEq(BURN_ADDRESS.balance, 0);
        uint256 fee = 40 ether;
        fee.burn();
        assertEq(BURN_ADDRESS.balance, 40 ether);
    }

    function testBurnByActorId() public {
        assertEq(BURN_ADDRESS.balance, 0);
        BURN_ACTOR_ID.pay(50 ether);
        assertEq(BURN_ADDRESS.balance, 50 ether);
    }

    function testBurnByAddress() public {
        assertEq(BURN_ADDRESS.balance, 0);
        address(BURN_ADDRESS).pay(60 ether);
        assertEq(BURN_ADDRESS.balance, 60 ether);
    }

    function testBurnByAddressPayable() public {
        assertEq(BURN_ADDRESS.balance, 0);
        BURN_ADDRESS.pay(60 ether);
        assertEq(BURN_ADDRESS.balance, 60 ether);
    }

    // -------------------------------------------------------------------------
    // Error cases via raw CALL_ACTOR_BY_ID calls
    // -------------------------------------------------------------------------

    // READONLY_FLAG + non-zero value: kernel rejects with ErrorNumber::ReadOnly.
    function testBurn_ReadOnly_ReturnsReadOnly() public {
        (bool success, bytes memory ret) = _callBurn(SEND, 1 ether, READONLY_FLAG, EMPTY_CODEC, "");
        assertTrue(success);
        (int256 exitCode,,) = abi.decode(ret, (int256, uint64, bytes));
        assertEq(exitCode, READ_ONLY);
    }

    // Reserved method (1–1023): precompile rejects outright → success=false.
    function testBurn_ReservedMethod_PrecompileError() public {
        (bool success,) = _callBurn(1, 0, NO_FLAGS, EMPTY_CODEC, "");
        assertFalse(success);
    }

    // codec=0 with non-empty params: precompile rejects → success=false.
    function testBurn_EmptyCodecWithParams_PrecompileError() public {
        (bool success,) = _callBurn(SEND, 0, NO_FLAGS, EMPTY_CODEC, hex"deadbeef");
        assertFalse(success);
    }

    // Unknown codec (RAW_CODEC): precompile rejects → success=false.
    function testBurn_UnknownCodec_PrecompileError() public {
        (bool success,) = _callBurn(SEND, 0, NO_FLAGS, RAW_CODEC, "");
        assertFalse(success);
    }

    // Exported method (>= FIRST_EXPORTED_METHOD_NUMBER): account actor fallback returns exit 0.
    function testBurn_ExportedMethod_ReturnsSuccess() public {
        (bool success, bytes memory ret) = _callBurn(INVOKE_EVM, 0, NO_FLAGS, EMPTY_CODEC, "");
        assertTrue(success);
        (int256 exitCode,,) = abi.decode(ret, (int256, uint64, bytes));
        assertEq(exitCode, 0);
    }

    // Internal method (1024 to FIRST_EXPORTED_METHOD_NUMBER-1): account actor fallback → USR_UNHANDLED_MESSAGE.
    function testBurn_InternalMethod_ReturnsUnhandledMessage() public {
        (bool success, bytes memory ret) = _callBurn(1024, 0, NO_FLAGS, EMPTY_CODEC, "");
        assertTrue(success);
        (int256 exitCode,,) = abi.decode(ret, (int256, uint64, bytes));
        assertEq(exitCode, int256(uint256(USR_UNHANDLED_MESSAGE)));
    }

    function _callBurn(uint64 method, uint256 value, uint64 flags, uint64 codec, bytes memory params)
        internal
        returns (bool, bytes memory)
    {
        bytes memory callData = abi.encode(method, value, flags, codec, params, uint64(BURN_ACTOR_ID));
        return CALL_ACTOR_BY_ID.call(callData);
    }
}
