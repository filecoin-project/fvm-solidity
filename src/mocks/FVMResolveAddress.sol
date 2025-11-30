// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

contract FVMResolveAddress {
    mapping(bytes32 => uint64) public addressMocks;
    mapping(bytes32 => bool) public addressExists;

    function mockResolveAddress(bytes memory filAddress, uint64 actorId) external {
        bytes32 hash = keccak256(filAddress);
        addressMocks[hash] = actorId;
        addressExists[hash] = true;
    }

    fallback() external {
        bytes32 addressHash = keccak256(msg.data);

        if (addressExists[addressHash]) {
            uint64 actorId = addressMocks[addressHash];
            assembly ("memory-safe") {
                mstore(0, actorId)
                return(0, 32)
            }
        }

        assembly ("memory-safe") {
            return(0, 0)
        }
    }
}
