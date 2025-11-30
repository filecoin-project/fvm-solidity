// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {CALL_ACTOR_BY_ADDRESS, CALL_ACTOR_BY_ID, GET_BEACON_RANDOMNESS, LOOKUP_DELEGATED_ADDRESS} from "../FVMPrecompiles.sol";
import {FVMCallActorByAddress} from "./FVMCallActorByAddress.sol";
import {FVMCallActorById} from "./FVMCallActorById.sol";
import {FVMGetBeaconRandomness} from "./FVMGetBeaconRandomness.sol";

contract FVMLookupDelegatedAddress {
    mapping(uint64 => bytes) public delegatedAddressMocks;
    mapping(uint64 => bool) public shouldRevert;

    function mockLookupDelegatedAddress(uint64 actorId, bytes memory delegatedAddress) external {
        delegatedAddressMocks[actorId] = delegatedAddress;
    }

    function mockLookupDelegatedAddressFailure(uint64 actorId) external {
        shouldRevert[actorId] = true;
    }

    function mockActorIdToEthAddress(uint64 actorId, address ethAddress) external {
        bytes memory delegatedAddress = new bytes(22);
        delegatedAddress[0] = 0x04;
        delegatedAddress[1] = 0x0a;

        for (uint256 i = 0; i < 20; i++) {
            delegatedAddress[i + 2] = bytes20(ethAddress)[i];
        }

        delegatedAddressMocks[actorId] = delegatedAddress;
    }

    fallback() external {
        uint64 actorId;
        assembly ("memory-safe") {
            actorId := calldataload(0)
        }

        if (shouldRevert[actorId]) {
            revert("Mock precompile failure");
        }

        bytes memory delegatedAddress = delegatedAddressMocks[actorId];

        assembly ("memory-safe") {
            let len := mload(delegatedAddress)
            if len {
                return(add(delegatedAddress, 32), len)
            }
            return(0, 0)
        }
    }
}

contract MockFVMTest is Test {
    FVMGetBeaconRandomness public constant RANDOMNESS_PRECOMPILE = FVMGetBeaconRandomness(GET_BEACON_RANDOMNESS);
    FVMLookupDelegatedAddress public constant LOOKUP_DELEGATED_ADDRESS_PRECOMPILE = FVMLookupDelegatedAddress(LOOKUP_DELEGATED_ADDRESS);

    function setUp() public virtual {
        vm.etch(CALL_ACTOR_BY_ADDRESS, address(new FVMCallActorByAddress()).code);
        vm.etch(CALL_ACTOR_BY_ID, address(new FVMCallActorById()).code);
        vm.etch(GET_BEACON_RANDOMNESS, address(new FVMGetBeaconRandomness()).code);
        vm.etch(LOOKUP_DELEGATED_ADDRESS, address(new FVMLookupDelegatedAddress()).code);
    }
}
