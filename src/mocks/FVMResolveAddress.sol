// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

contract FVMResolveAddress {
    // Mapping from Filecoin address bytes to actor ID
    mapping(bytes32 => uint64) public addressMocks;

    /// @notice Mock a Filecoin address resolution
    /// @param filAddress The Filecoin address bytes
    /// @param actorId The actor ID to return (0 means doesn't exist)
    function mockResolveAddress(bytes memory filAddress, uint64 actorId) external {
        addressMocks[keccak256(filAddress)] = actorId;
    }

    fallback() external {
        bytes memory filAddress = msg.data;

        // Basic validation:  address must be non-empty
        require(filAddress.length > 0, "Invalid address:  empty");

        // Check first byte for valid protocol
        // f0 = 0x00, f1 = 0x01, f2 = 0x02, f3 = 0x03, f4 = 0x04
        uint8 protocol = uint8(filAddress[0]);
        require(protocol <= 0x04, "Invalid address: unknown protocol");

        // Look up mocked actor ID
        bytes32 key = keccak256(filAddress);
        uint64 actorId = addressMocks[key];

        // If actor exists (actorId > 0), return it as ABI-encoded uint64
        if (actorId > 0) {
            bytes memory response = abi.encode(uint256(actorId));
            assembly ("memory-safe") {
                return(add(response, 0x20), 32)
            }
        }

        // If actor doesn't exist (actorId == 0), return empty
        assembly ("memory-safe") {
            return(0, 0)
        }
    }
}
