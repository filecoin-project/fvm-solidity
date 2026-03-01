// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {
    CALL_ACTOR_BY_ADDRESS,
    CALL_ACTOR_BY_ID,
    GET_BEACON_RANDOMNESS,
    RESOLVE_ADDRESS,
    LOOKUP_DELEGATED_ADDRESS
} from "../FVMPrecompiles.sol";
import {FVMCallActorByAddress} from "./FVMCallActorByAddress.sol";
import {FVMCallActorById} from "./FVMCallActorById.sol";
import {FVMGetBeaconRandomness} from "./FVMGetBeaconRandomness.sol";
import {FVMActor} from "./FVMActor.sol";

/// @notice Mocks the FVM precompiles for forge test
contract MockFVMTest is Test {
    FVMGetBeaconRandomness public constant RANDOMNESS_PRECOMPILE = FVMGetBeaconRandomness(GET_BEACON_RANDOMNESS);
    FVMActor public constant ACTOR_PRECOMPILE = FVMActor(RESOLVE_ADDRESS);
    FVMActor public constant LOOKUP_DELEGATED_ADDRESS_PRECOMPILE = FVMActor(LOOKUP_DELEGATED_ADDRESS);

    function setUp() public virtual {
        vm.etch(CALL_ACTOR_BY_ADDRESS, address(new FVMCallActorByAddress()).code);
        vm.etch(CALL_ACTOR_BY_ID, address(new FVMCallActorById()).code);
        vm.etch(GET_BEACON_RANDOMNESS, address(new FVMGetBeaconRandomness()).code);

        address deployed = address(new FVMActor());

        vm.etch(RESOLVE_ADDRESS, deployed.code);
        vm.etch(LOOKUP_DELEGATED_ADDRESS, deployed.code);

        vm.copyStorage(deployed, RESOLVE_ADDRESS);
        vm.copyStorage(deployed, LOOKUP_DELEGATED_ADDRESS);
    }
}
