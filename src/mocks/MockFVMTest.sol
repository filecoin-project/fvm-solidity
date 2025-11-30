// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {
    CALL_ACTOR_BY_ADDRESS,
    CALL_ACTOR_BY_ID,
    GET_BEACON_RANDOMNESS,
    LOOKUP_DELEGATED_ADDRESS
} from "../FVMPrecompiles.sol";
import {FVMCallActorByAddress} from "./FVMCallActorByAddress.sol";
import {FVMCallActorById} from "./FVMCallActorById.sol";
import {FVMGetBeaconRandomness} from "./FVMGetBeaconRandomness.sol";
import {FVMLookupDelegatedAddress} from "./FVMLookupDelegatedAddress.sol";

contract MockFVMTest is Test {
    FVMGetBeaconRandomness public constant RANDOMNESS_PRECOMPILE = FVMGetBeaconRandomness(GET_BEACON_RANDOMNESS);
    FVMLookupDelegatedAddress public constant LOOKUP_DELEGATED_ADDRESS_PRECOMPILE =
        FVMLookupDelegatedAddress(LOOKUP_DELEGATED_ADDRESS);

    function setUp() public virtual {
        vm.etch(CALL_ACTOR_BY_ADDRESS, address(new FVMCallActorByAddress()).code);
        vm.etch(CALL_ACTOR_BY_ID, address(new FVMCallActorById()).code);
        vm.etch(GET_BEACON_RANDOMNESS, address(new FVMGetBeaconRandomness()).code);
        vm.etch(LOOKUP_DELEGATED_ADDRESS, address(new FVMLookupDelegatedAddress()).code);
    }
}
