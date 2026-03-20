// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {CALL_ACTOR_BY_ADDRESS, CALL_ACTOR_BY_ID, GET_BEACON_RANDOMNESS, RESOLVE_ADDRESS} from "../FVMPrecompiles.sol";
import {STORAGE_POWER_ACTOR_ADDRESS} from "../FVMActors.sol";
import {FVMAddress} from "../FVMAddress.sol";
import {FVMCallActorByAddress} from "./FVMCallActorByAddress.sol";
import {FVMCallActorById} from "./FVMCallActorById.sol";
import {FVMGetBeaconRandomness} from "./FVMGetBeaconRandomness.sol";
import {FVMActor} from "./FVMActor.sol";
import {FVMMinerActor} from "./FVMMinerActor.sol";
import {FVMStoragePowerActor} from "./FVMStoragePowerActor.sol";

/// @notice Mocks the FVM precompiles for forge test
contract MockFVMTest is Test {
    using FVMAddress for uint64;

    FVMGetBeaconRandomness public constant RANDOMNESS_PRECOMPILE = FVMGetBeaconRandomness(GET_BEACON_RANDOMNESS);
    FVMActor public constant ACTOR_PRECOMPILE = FVMActor(RESOLVE_ADDRESS);
    FVMCallActorById public constant CALL_ACTOR_BY_ID_PRECOMPILE = FVMCallActorById(payable(CALL_ACTOR_BY_ID));

    function setUp() public virtual {
        vm.etch(CALL_ACTOR_BY_ADDRESS, address(new FVMCallActorByAddress()).code);
        vm.etch(CALL_ACTOR_BY_ID, address(new FVMCallActorById()).code);
        vm.etch(GET_BEACON_RANDOMNESS, address(new FVMGetBeaconRandomness()).code);
        vm.etch(STORAGE_POWER_ACTOR_ADDRESS, address(new FVMStoragePowerActor()).code);

        address deployed = address(new FVMActor());
        vm.etch(RESOLVE_ADDRESS, deployed.code);
        vm.copyStorage(deployed, RESOLVE_ADDRESS);
    }

    /// @notice Set up a mock miner actor at the given actor ID's masked address
    /// @dev Etches FVMMinerActor code at the masked ID address and registers the actor ID
    /// for PowerAPI verification. Returns the FVMMinerActor at the miner's masked address.
    function mockMiner(uint64 actorId) internal returns (FVMMinerActor) {
        address maskedAddr = actorId.maskedAddress();
        vm.etch(maskedAddr, address(new FVMMinerActor()).code);
        CALL_ACTOR_BY_ID_PRECOMPILE.mockMiner(actorId);
        return FVMMinerActor(maskedAddr);
    }
}
