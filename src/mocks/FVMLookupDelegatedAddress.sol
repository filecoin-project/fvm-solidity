// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

contract FVMLookupDelegatedAddress {
    mapping(uint64 => bytes) public delegatedAddressMocks;

    function mockLookupDelegatedAddress(uint64 actorId, bytes memory delegatedAddress) external {
        delegatedAddressMocks[actorId] = delegatedAddress;
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
