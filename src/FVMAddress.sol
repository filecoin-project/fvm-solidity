// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {RESOLVE_ADDRESS} from "./FVMPrecompiles.sol";

library FVMAddress {
    function resolveAddress(bytes memory filAddress) internal view returns (bool success, uint64 actorId) {
        bytes memory result;
        (success, result) = address(RESOLVE_ADDRESS).staticcall(filAddress);

        if (success && result.length == 32) {
            actorId = abi.decode(result, (uint64));
        }
    }

    function toActorId(bytes memory filAddress) internal view returns (uint64 actorId) {
        (bool success, uint64 id) = resolveAddress(filAddress);
        require(success, "FVMAddress: Invalid address format");
        require(id != 0, "FVMAddress: Actor not found");
        return id;
    }
}
