// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {LOOKUP_DELEGATED_ADDRESS} from "./FVMPrecompiles.sol";

library FVMAddress {
    function lookupDelegatedAddress(uint64 actorId) internal view returns (bool success, bytes memory delegatedAddress) {
        (success, delegatedAddress) = LOOKUP_DELEGATED_ADDRESS.staticcall(abi.encode(uint256(actorId)));
    }

    function actorIdToEthAddress(uint64 actorId) internal view returns (bool success, address ethAddress) {
        bytes memory delegatedAddress;
        (success, delegatedAddress) = lookupDelegatedAddress(actorId);

        if (!success || delegatedAddress.length != 22) {
            return (false, address(0));
        }

        uint16 prefix;
        assembly ("memory-safe") {
            prefix := shr(240, mload(add(delegatedAddress, 32)))
        }

        if (prefix != 0x040a) {
            return (false, address(0));
        }

        uint160 addr;
        for (uint256 i = 2; i < 22; i++) {
            addr = (addr << 8) | uint8(delegatedAddress[i]);
        }

        ethAddress = address(addr);
        return (true, ethAddress);
    }
}
