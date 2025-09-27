// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {BURN_ACTOR_ID} from "./FVMActors.sol";
import {EMPTY_CODEC} from "./FVMCodec.sol";
import {NO_FLAGS} from "./FVMFlags.sol";
import {BARE_VALUE_TRANSFER} from "./FVMMethod.sol";
import {EXIT_SUCCESS} from "./FVMErrors.sol";
import {CALL_ACTOR_BY_ADDRESS, CALL_ACTOR_BY_ID} from "./FVMPrecompiles.sol";

library FVMPay {
    /// @notice Pay FEVM address with CallActorByAddress precompile
    /// @param to The recipient address
    /// @param amount Paid value (attoFIL)
    /// @return success Whether the payment completed
    function pay(address to, uint256 amount) internal returns (bool success) {
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(fmp, BARE_VALUE_TRANSFER) // method 0
            mstore(add(32, fmp), amount) // value
            mstore(add(64, fmp), NO_FLAGS) // flags
            mstore(add(96, fmp), EMPTY_CODEC) // codec
            mstore(add(128, fmp), 0) // params
            mstore(add(160, fmp), 192) // address offset
            mstore(add(214, fmp), or(0x040a0000000000000000000000000000000000000000, to)) // address
            mstore(add(192, fmp), 22) // address size
            success :=
                and(
                    and(gt(returndatasize(), 31), eq(mload(fmp), EXIT_SUCCESS)),
                    delegatecall(gas(), CALL_ACTOR_BY_ADDRESS, fmp, 256, fmp, 256)
                )
        }
    }

    /// @notice Pay FEVM actor with CallActorById precompile
    /// @param actorId The FVM actor ID
    /// @param amount Paid value (attoFIL)
    /// @return success Whether the payment completed
    function pay(uint64 actorId, uint256 amount) internal returns (bool success) {
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(fmp, BARE_VALUE_TRANSFER) // method 0
            mstore(add(32, fmp), amount) // value
            mstore(add(64, fmp), NO_FLAGS) // flags
            mstore(add(96, fmp), EMPTY_CODEC) // codec
            mstore(add(128, fmp), 0) // params
            mstore(add(160, fmp), actorId) // actor ID
            success :=
                and(
                    and(gt(returndatasize(), 31), eq(mload(fmp), EXIT_SUCCESS)),
                    delegatecall(gas(), CALL_ACTOR_BY_ID, fmp, 192, fmp, 192)
                )
        }
    }

    /// @notice Destroy FIL with CallActorById precompile
    /// @param amount Destroyed value (attoFIL)
    /// @return success Whether the burn completed
    function burn(uint256 amount) internal returns (bool success) {
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(fmp, BARE_VALUE_TRANSFER) // method 0
            mstore(add(32, fmp), amount) // value
            mstore(add(64, fmp), NO_FLAGS) // flags
            mstore(add(96, fmp), EMPTY_CODEC) // codec
            mstore(add(128, fmp), 0) // params
            mstore(add(160, fmp), BURN_ACTOR_ID) // actor ID
            success :=
                and(
                    and(gt(returndatasize(), 31), eq(mload(fmp), EXIT_SUCCESS)),
                    delegatecall(gas(), CALL_ACTOR_BY_ID, fmp, 192, fmp, 192)
                )
        }
    }
}
