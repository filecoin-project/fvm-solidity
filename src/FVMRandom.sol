// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {GET_DRAND_BY_EPOCH} from "./FVMPrecompiles.sol";

library FVMRandom {
    // the precompile will assert and consume all gas if epoch > block.number
    function drand(uint256 epoch) internal view returns (uint256 randomness) {
        assembly ("memory-safe") {
            let fmp := mload(0x40)
            mstore(fmp, epoch)
            pop(staticcall(gas(), GET_DRAND_BY_EPOCH, fmp, 32, fmp, 32))
            randomness := mload(fmp)
        }
    }
}
