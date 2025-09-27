// SPDX-Lidense-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {BURN_ACTOR_ID} from "../FVMActors.sol";
import {EMPTY_CODEC} from "../FVMCodec.sol";
import {EXIT_SUCCESS, INSUFFICIENT_FUNDS} from "../FVMErrors.sol";

contract FVMCallActorById {
    address payable private constant BURN_ADDRESS = payable(0xff00000000000000000000000000000000000063);

    fallback() external payable {
        (uint64 method, uint256 value, uint64 flags, uint64 codec, bytes memory params, uint64 actorId) =
            abi.decode(msg.data, (uint64, uint256, uint64, uint64, bytes, uint64));

        // Verify this is a burn operation (actor ID 99, method 0)
        require(actorId == BURN_ACTOR_ID, "FVMCallActorById: Only burn actor (99) supported");
        require(method == 0, "FVMCallActorById: Only method 0 (send) supported");
        require(flags == 0, "FVMCallActorById: Only non-readonly calls supported");
        require(codec == 0, "FVMCallActorById: Only no-codec calls supported");
        require(params.length == 0, "FVMCallActorById: No params expected");

        // Perform the burn by sending to the burn address
        (bool success,) = BURN_ADDRESS.call{value: value}("");

        // Prepare the response in FVM format: exit_code(i256) | codec(u64) | return_value(bytes)
        bytes memory response;
        if (success) {
            // Success: exit code 0
            response = abi.encode(EXIT_SUCCESS, EMPTY_CODEC, bytes(""));
        } else {
            // Failure: exit code -5 (InsufficientFunds)
            response = abi.encode(INSUFFICIENT_FUNDS, EMPTY_CODEC, bytes(""));
        }

        // Return the response using assembly to properly handle delegatecall return
        assembly {
            return(add(response, 0x20), mload(response))
        }
    }
}
