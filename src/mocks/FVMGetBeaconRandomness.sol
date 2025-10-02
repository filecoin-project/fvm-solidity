// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

contract FVMGetBeaconRandomness {
    mapping(uint256 epoch => uint256) public beaconMocks;

    function mockBeaconRandomness(uint256 epoch, uint256 randomness) external {
        beaconMocks[epoch] = randomness;
    }

    fallback() external {
        uint256 epoch;
        assembly ("memory-safe") {
            epoch := calldataload(0)
            if gt(epoch, number()) { invalid() }
        }
        uint256 randomness = beaconMocks[epoch];
        assembly ("memory-safe") {
            if randomness {
                mstore(0, randomness)
                return(0, 32)
            }
            // https://xkcd.com/221/
            mstore(0, 4)
            return(0, 32)
        }
    }
}
