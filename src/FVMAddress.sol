// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {LOOKUP_DELEGATED_ADDRESS} from "./FVMPrecompiles.sol";

library FVMAddress {
    function lookupDelegatedAddress(uint64 actorId) internal view returns (bool success, bytes memory delegatedAddress) {
        (success, delegatedAddress) = address(LOOKUP_DELEGATED_ADDRESS).staticcall(abi.encode(uint256(actorId)));
    }

    function actorIdToEthAddress(uint64 actorId) internal view returns (bool success, address ethAddress) {
        bytes memory delegatedAddress;
        (success, delegatedAddress) = lookupDelegatedAddress(actorId);

        if (success && delegatedAddress.length == 22) {
            if (delegatedAddress[0] == 0x04 && delegatedAddress[1] == 0x0a) {
                assembly ("memory-safe") {
                    ethAddress := mload(add(delegatedAddress, 22))
                }
                return (true, ethAddress);
            }
        }
        return (false, address(0));
    }
}
