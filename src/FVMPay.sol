// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

library FVMPay {
    address private constant CALL_ACTOR_BY_ADDRESS = 0xfe00000000000000000000000000000000000003;
    address private constant CALL_ACTOR_BY_ID = 0xfe00000000000000000000000000000000000005;
    uint64 private constant BURN_ACTOR_ID = 99;

    function pay(address to, uint256 amount) internal returns (bool success) {
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(fmp, 0) // method 0
            mstore(add(32, fmp), amount) // value
            mstore(add(64, fmp), 0) // flags
            mstore(add(96, fmp), 0) // codec
            mstore(add(128, fmp), 0) // params
            mstore(add(160, fmp), 192) // address offset
            mstore(add(214, fmp), or(0x040a0000000000000000000000000000000000000000, to)) // address
            mstore(add(192, fmp), 22) // address size
            success :=
                and(
                    and(gt(returndatasize(), 31), eq(mload(fmp), 0)),
                    delegatecall(gas(), CALL_ACTOR_BY_ADDRESS, fmp, 256, fmp, 256)
                )
        }
    }

    function pay(uint64 actorId, uint256 amount) internal returns (bool success) {
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(fmp, 0) // method 0
            mstore(add(32, fmp), amount) // value
            mstore(add(64, fmp), 0) // flags
            mstore(add(96, fmp), 0) // codec
            mstore(add(128, fmp), 0) // params
            mstore(add(160, fmp), actorId) // actor ID
            success :=
                and(
                    and(gt(returndatasize(), 31), eq(mload(fmp), 0)),
                    delegatecall(gas(), CALL_ACTOR_BY_ID, fmp, 192, fmp, 192)
                )
        }
    }

    function burn(uint256 amount) internal returns (bool success) {
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(fmp, 0) // method 0
            mstore(add(32, fmp), amount) // value
            mstore(add(64, fmp), 0) // flags
            mstore(add(96, fmp), 0) // codec
            mstore(add(128, fmp), 0) // params
            mstore(add(160, fmp), BURN_ACTOR_ID) // actor ID
            success :=
                and(
                    and(gt(returndatasize(), 31), eq(mload(fmp), 0)),
                    delegatecall(gas(), CALL_ACTOR_BY_ID, fmp, 192, fmp, 192)
                )
        }
    }
}
