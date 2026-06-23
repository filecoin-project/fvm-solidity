// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import {CALL_ACTOR_BY_ADDRESS, CALL_ACTOR_BY_ID, GET_BEACON_RANDOMNESS, RESOLVE_ADDRESS} from "../FVMPrecompiles.sol";
import {STORAGE_POWER_ACTOR_ADDRESS} from "../FVMActors.sol";
import {FVMAddress} from "../FVMAddress.sol";
import {FVMCallActorByAddress} from "./FVMCallActorByAddress.sol";
import {FVMCallActorById} from "./FVMCallActorById.sol";
import {FVMGetBeaconRandomness} from "./FVMGetBeaconRandomness.sol";
import {FVMActor} from "./FVMActor.sol";
import {FVMAccountActor} from "./FVMAccountActor.sol";
import {FVMMinerActor} from "./FVMMinerActor.sol";
import {FVMStoragePowerActor} from "./FVMStoragePowerActor.sol";

/// @notice Mocks the FVM precompiles for forge test
contract MockFVMTest is Test {
    using FVMAddress for uint64;

    FVMGetBeaconRandomness public constant RANDOMNESS_PRECOMPILE = FVMGetBeaconRandomness(GET_BEACON_RANDOMNESS);
    FVMActor public constant ACTOR_PRECOMPILE = FVMActor(RESOLVE_ADDRESS);

    function setUp() public virtual {
        vm.etch(CALL_ACTOR_BY_ADDRESS, address(new FVMCallActorByAddress()).code);
        vm.etch(CALL_ACTOR_BY_ID, address(new FVMCallActorById()).code);
        vm.etch(GET_BEACON_RANDOMNESS, address(new FVMGetBeaconRandomness()).code);
        vm.etch(STORAGE_POWER_ACTOR_ADDRESS, address(new FVMStoragePowerActor()).code);

        address deployed = address(new FVMActor());
        vm.etch(RESOLVE_ADDRESS, deployed.code);
        vm.copyStorage(deployed, RESOLVE_ADDRESS);
    }

    /// @notice Set up a mock miner actor at the given actor ID's masked address.
    /// @dev Etches FVMMinerActor code at the masked ID address. PowerAPI verification
    ///      detects the miner via extcodesize at the masked address — no separate registry needed.
    function mockMiner(uint64 actorId) internal returns (FVMMinerActor) {
        address maskedAddr = actorId.maskedAddress();
        vm.etch(maskedAddr, address(new FVMMinerActor()).code);
        return FVMMinerActor(maskedAddr);
    }

    /// @notice Set up a mock ECDSA account actor at the given actor ID's masked address.
    /// @dev Etches FVMAccountActor code, then writes accountAddress into its storage directly,
    ///      matching the mockMiner pattern (no copyStorage needed — no constructor state).
    function mockAccount(uint64 actorId, address accountAddress) internal returns (FVMAccountActor) {
        address maskedAddr = actorId.maskedAddress();
        vm.etch(maskedAddr, address(new FVMAccountActor()).code);
        FVMAccountActor(maskedAddr).mockAddress(accountAddress);
        ACTOR_PRECOMPILE.mockResolveAddress(accountAddress, actorId);
        return FVMAccountActor(maskedAddr);
    }

    /// @notice Set up a mock f1 (secp256k1) account actor from a forge Wallet.
    /// @dev Uses wallet.addr (the f4/Ethereum address) for ecrecover verification — the same
    ///      private key that produces the f1 address payload (blake2b-20 of the uncompressed
    ///      public key) also produces wallet.addr, ensuring the mock validates exactly the key
    ///      pair that corresponds to the f1 account. Compute the f1 payload with:
    ///      FVMBlake2b.hash20(abi.encodePacked(uint8(0x04), wallet.publicKeyX, wallet.publicKeyY))
    function mockF1Account(uint64 actorId, VmSafe.Wallet memory wallet) internal returns (FVMAccountActor) {
        return mockAccount(actorId, wallet.addr);
    }
}
