// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {INIT_ACTOR_ID} from "../src/FVMActors.sol";
import {FVMAddress} from "../src/FVMAddress.sol";
import {EMPTY_CODEC} from "../src/FVMCodec.sol";
import {EXIT_SUCCESS, NOT_FOUND} from "../src/FVMErrors.sol";
import {NO_FLAGS} from "../src/FVMFlags.sol";
import {SEND} from "../src/FVMMethod.sol";
import {CALL_ACTOR_BY_ID} from "../src/FVMPrecompiles.sol";
import {FVMPay} from "../src/FVMPay.sol";

contract CallActorByIdTest is MockFVMTest {
    using FVMAddress for uint64;
    using FVMPay for uint64;

    // -------------------------------------------------------------------------
    // Precompile routing
    // -------------------------------------------------------------------------

    // Actor ID that is not burn, power, or a registered miner: no actor in mock state.
    // Real FVM: send_raw returns ErrorNumber::NotFound → success=true, exit code NOT_FOUND (-6).
    function testUnknownActor_ReturnsNotFound() public {
        bytes memory callData = abi.encode(uint64(0), uint256(0), uint64(0), uint64(0), bytes(""), uint64(7777));
        (bool success, bytes memory ret) = CALL_ACTOR_BY_ID.delegatecall(callData);
        assertTrue(success);
        (int256 exitCode,,) = abi.decode(ret, (int256, uint64, bytes));
        assertEq(exitCode, NOT_FOUND);
    }

    function _sendExitCode(uint64 actorId) internal returns (int256 exitCode) {
        bytes memory callData = abi.encode(SEND, uint256(0), NO_FLAGS, EMPTY_CODEC, bytes(""), actorId);
        (bool success, bytes memory ret) = CALL_ACTOR_BY_ID.delegatecall(callData);
        assertTrue(success);
        (exitCode,,) = abi.decode(ret, (int256, uint64, bytes));
    }

    // -------------------------------------------------------------------------
    // Actors mocked on RESOLVE_ADDRESS
    // -------------------------------------------------------------------------

    function testMockedAddress_Send_ReturnsSuccess() public {
        assertEq(_sendExitCode(8888), NOT_FOUND);
        ACTOR_PRECOMPILE.mockResolveAddress(vm.addr(1), 8888);
        assertEq(_sendExitCode(8888), EXIT_SUCCESS);
    }

    function testSystemActor_Send_ReturnsSuccess() public {
        assertEq(_sendExitCode(INIT_ACTOR_ID), EXIT_SUCCESS);
    }

    function testMockedAddress_Pay_CreditsMockedAddress() public {
        address recipient = vm.addr(1);
        ACTOR_PRECOMPILE.mockResolveAddress(recipient, 8888);
        uint256 senderBefore = address(this).balance;
        assertTrue(uint64(8888).pay(5 ether));
        assertEq(recipient.balance, 5 ether);
        assertEq(address(this).balance, senderBefore - 5 ether);
    }

    function testMockedF410_Pay_CreditsEmbeddedAddress() public {
        address recipient = vm.addr(1);
        ACTOR_PRECOMPILE.mockResolveAddress(abi.encodePacked(uint8(0x04), uint8(0x0a), recipient), 8888);
        assertTrue(uint64(8888).pay(5 ether));
        assertEq(recipient.balance, 5 ether);
    }

    function testMockedF0_Pay_CreditsMaskedAddress() public {
        address masked = uint64(8888).maskedAddress();
        ACTOR_PRECOMPILE.mockResolveAddress(uint64(8888).f0(), 8888);
        assertTrue(uint64(8888).pay(5 ether));
        assertEq(masked.balance, 5 ether);
    }

    function testMockResolveAddress_ZeroActorId_Reverts() public {
        vm.expectRevert("FVMActor: cannot mock actor ID 0");
        ACTOR_PRECOMPILE.mockResolveAddress(vm.addr(1), 0);
        vm.expectRevert("FVMActor: cannot mock actor ID 0");
        ACTOR_PRECOMPILE.mockResolveAddress(uint64(8888).f0(), 0);
    }

    function testMockResolveAddress_ZeroAddress_Reverts() public {
        vm.expectRevert("FVMActor: cannot mock the zero address");
        ACTOR_PRECOMPILE.mockResolveAddress(address(0), 8888);
        vm.expectRevert("FVMActor: cannot mock the zero address");
        ACTOR_PRECOMPILE.mockResolveAddress(abi.encodePacked(uint8(0x04), uint8(0x0a), address(0)), 8888);
    }
}
