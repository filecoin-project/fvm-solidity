// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

contract FVMDelegatedAddress {
    // Mapping from actor ID to delegated address
    mapping(uint64 => bytes) public delegatedAddressMocks;

    /// @notice Mocks reverse lookup of a delegated (f4) address for an actor ID
    /// @dev Simulates the lookupDelegatedAddress precompile
    /// @param actorId The canonical actor ID
    /// @param delegatedAddress Raw delegated address bytes (empty = no delegated address)
    function mockLookupDelegatedAddress(uint64 actorId, bytes memory delegatedAddress) external {
        delegatedAddressMocks[actorId] = delegatedAddress;
    }

    /// @notice Mocks reverse lookup of a delegated EVM address for an actor ID
    /// @dev Constructs 0x04 || varint(10) || addr and maps it to `actorId`
    /// @param actorId The canonical actor ID
    /// @param addr The 20-byte EVM address
    function mockLookupDelegatedAddress(uint64 actorId, address addr) external {
        bytes memory delegatedAddress = abi.encodePacked(uint8(0x04), uint8(0x0a), addr);
        delegatedAddressMocks[actorId] = delegatedAddress;
    }

    fallback() external {
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
