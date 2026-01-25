// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

contract FVMLookupDelegatedAddress {
    // Mapping from actor ID to delegated address
    mapping(uint64 => bytes) public delegatedAddressMocks;

    /// @notice Mock a delegated address lookup
    /// @param actorId The actor ID
    /// @param delegatedAddress The delegated address to return (empty bytes means no delegated address)
    function mockLookupDelegatedAddress(uint64 actorId, bytes memory delegatedAddress) external {
        delegatedAddressMocks[actorId] = delegatedAddress;
    }

    fallback() external {
        // Input: ABI-encoded uint256 (u64 encoded as u256)
        // Expected input size: 32 bytes
        require(msg.data.length == 32, "Invalid input: expected 32 bytes");

        // Decode the actor ID from the input
        uint256 actorIdFull = abi.decode(msg.data, (uint256));

        // Validate that actor ID fits in u64 (max u64 = 2^64 - 1)
        require(actorIdFull <= type(uint64).max, "Invalid actor ID: exceeds max u64");

        uint64 actorId = uint64(actorIdFull);

        // Look up mocked delegated address
        bytes memory delegatedAddress = delegatedAddressMocks[actorId];

        // Return the delegated address as raw bytes
        // If empty (length 0), return nothing (success with no data)
        assembly ("memory-safe") {
            return(add(delegatedAddress, 0x20), mload(delegatedAddress))
        }
    }
}
