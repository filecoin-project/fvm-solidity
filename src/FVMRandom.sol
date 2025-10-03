// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {GET_BEACON_RANDOMNESS} from "./FVMPrecompiles.sol";

library FVMRandom {
    // Performs the get_beacon_randomness syscall via the GET_BEACON_RANDOMNESS precompile
    // The precompile will assert and consume all gas if epoch > block.number
    // This error cannot be caught even if you supply less gas to the staticcall
    // The entire transaction will fail with out of gas
    function getBeaconRandomness(uint256 epoch) internal view returns (uint256 randomness) {
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(fmp, epoch)
            pop(staticcall(gas(), GET_BEACON_RANDOMNESS, fmp, 32, fmp, 32))
            randomness := mload(fmp)
        }
    }
}
