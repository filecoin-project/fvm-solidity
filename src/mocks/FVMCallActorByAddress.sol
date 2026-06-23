// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {Vm} from "forge-std/Vm.sol";

import {CALL_ACTOR_BY_ADDRESS} from "../FVMPrecompiles.sol";
import {EMPTY_CODEC} from "../FVMCodec.sol";
import {EXIT_SUCCESS, INSUFFICIENT_FUNDS} from "../FVMErrors.sol";
import {NO_FLAGS} from "../FVMFlags.sol";
import {SEND} from "../FVMMethod.sol";

contract FVMCallActorByAddress {
    Vm private immutable VM;

    constructor(Vm _vm) {
        VM = _vm;
    }

    fallback() external payable {
        // Real precompile requires delegatecall; call/staticcall returns CallForbidden → (0, empty).
        if (address(this) == CALL_ACTOR_BY_ADDRESS) {
            assembly ("memory-safe") {
                revert(0, 0)
            }
        }
        (uint64 method, uint256 value, uint64 flags, uint64 codec, bytes memory params, bytes memory filAddress) =
            abi.decode(msg.data, (uint64, uint256, uint64, uint64, bytes, bytes));

        // Verify this is a burn operation (actor ID 99, method 0)
        require(filAddress.length > 2, "FVMCallActorByAddress: Invalid short address");
        require(filAddress[0] == 0x04, "FVMCallActorByAddress: Only f4 addresses supported");
        require(filAddress[1] == 0x0a, "FVMCallActorByAddress: Only f410 addresses supported");
        require(filAddress.length == 22, "FVMCallActorByAddress: Invalid f410 address length");

        require(method == SEND, "FVMCallActorByAddress: Only method 0 (send) supported");
        require(flags == NO_FLAGS, "FVMCallActorByAddress: Only non-readonly calls supported");
        require(codec == EMPTY_CODEC, "FVMCallActorByAddress: Only no-codec calls supported");
        require(params.length == 0, "FVMCallActorByAddress: No params expected");

        address recipient;
        assembly ("memory-safe") {
            recipient := mload(add(22, filAddress))
        }

        // Perform the transfer by adjusting balances directly, avoiding calls into the receiver.
        bytes memory response;
        if (address(this).balance >= value) {
            VM.deal(address(this), address(this).balance - value);
            VM.deal(recipient, recipient.balance + value);
            response = abi.encode(EXIT_SUCCESS, EMPTY_CODEC, bytes(""));
        } else {
            response = abi.encode(INSUFFICIENT_FUNDS, EMPTY_CODEC, bytes(""));
        }

        // Return the response using assembly to properly handle delegatecall return
        assembly ("memory-safe") {
            return(add(response, 0x20), mload(response))
        }
    }
}
