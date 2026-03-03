// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {
    SYSTEM_ACTOR_ID,
    INIT_ACTOR_ID,
    REWARD_ACTOR_ID,
    CRON_ACTOR_ID,
    STORAGE_POWER_ACTOR_ID,
    STORAGE_MARKET_ACTOR_ID,
    VERIFIED_REGISTRY_ACTOR_ID,
    DATACAP_TOKEN_ACTOR_ID,
    EAM_ACTOR_ID,
    BURN_ACTOR_ID
} from "../FVMActors.sol";
import {FVMAddress} from "../FVMAddress.sol";
import {RESOLVE_ADDRESS, LOOKUP_DELEGATED_ADDRESS} from "../FVMPrecompiles.sol";

contract FVMActor {
    using FVMAddress for uint64;

    /// @dev keccak256 of f0(0) = keccak256(hex"0000") — protocol byte 0x00 + ULEB128(0) = 0x00
    bytes32 constant SYSTEM_ACTOR_HASH = keccak256(hex"0000");

    // Mapping from Filecoin address bytes to actor ID
    mapping(bytes32 => uint64) public addressMocks;

    // Mapping from actor ID to delegated address
    mapping(uint64 => bytes) public delegatedAddressMocks;

    constructor() {
        // Protocol 0 (f0) mappings for system singleton actors
        _mockf0(SYSTEM_ACTOR_ID);
        _mockf0(INIT_ACTOR_ID);
        _mockf0(REWARD_ACTOR_ID);
        _mockf0(CRON_ACTOR_ID);
        _mockf0(STORAGE_POWER_ACTOR_ID);
        _mockf0(STORAGE_MARKET_ACTOR_ID);
        _mockf0(VERIFIED_REGISTRY_ACTOR_ID);
        _mockf0(DATACAP_TOKEN_ACTOR_ID);
        _mockf0(EAM_ACTOR_ID);
        _mockf0(BURN_ACTOR_ID);
    }

    /**
     * @notice Mocks an ID-based address (f0)
     * @dev NOTE: This simple encoding only works for actorId <= 127.
     * Filecoin uses LEB128 Varint encoding for ID addresses. For values <= 127,
     * the Varint is a single byte. For values > 127, the Varint expands to
     * multiple bytes, and this 2-byte packing [0x00, id] would be invalid.
     */
    function _mockf0(uint64 actorId) internal {
        // Protocol 0 address = protocol byte (0x00) + actor ID
        bytes memory filAddress = actorId.f0();
        addressMocks[keccak256(filAddress)] = actorId;
    }

    /// @notice Mock a Filecoin address resolution
    /// @param filAddress The Filecoin address bytes
    /// @param actorId The actor ID to return (0 means doesn't exist)
    function mockResolveAddress(bytes memory filAddress, uint64 actorId) external {
        addressMocks[keccak256(filAddress)] = actorId;
    }

    /// @notice Mock a Solidity address resolution
    /// @param addr The Solidity address
    /// @param actorId The actor ID to return (0 means doesn't exist)
    function mockResolveAddress(address addr, uint64 actorId) external {
        bytes memory filAddress = abi.encodePacked(uint8(0x04), uint8(0x0a), addr);
        addressMocks[keccak256(filAddress)] = actorId;
    }

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
        uint64 actorId;
        if (address(this) == LOOKUP_DELEGATED_ADDRESS) {
            // ---- lookupDelegatedAddress ----
            // Decode the actor ID from the input
            uint256 actorIdFull = abi.decode(msg.data, (uint256));

            // Validate that actor ID fits in u64 (max u64 = 2^64 - 1)
            require(actorIdFull <= type(uint64).max, "Invalid actor ID: exceeds max u64");

            actorId = uint64(actorIdFull);

            // Look up mocked delegated address
            bytes memory delegatedAddress = delegatedAddressMocks[actorId];

            // Return the delegated address as raw bytes
            // If empty (length 0), return nothing (success with no data)
            assembly ("memory-safe") {
                return(add(delegatedAddress, 0x20), mload(delegatedAddress))
            }
        } else if (address(this) == RESOLVE_ADDRESS) {
            // ---- resolveAddress ----
            bytes memory filAddress = msg.data;

            // Basic validation:  address must be non-empty
            require(filAddress.length > 0, "Invalid address:  empty");

            // Check first byte for valid protocol
            // f0 = 0x00, f1 = 0x01, f2 = 0x02, f3 = 0x03, f4 = 0x04
            uint8 protocol = uint8(filAddress[0]);
            require(protocol <= 0x04, "Invalid address: unknown protocol");

            bytes32 key;
            // Equivalent to `keccak256(filAddress)`.
            // Hash the data section of `bytes memory` directly:
            // length at offset 0x00, data at 0x20.
            assembly {
                key := keccak256(add(filAddress, 0x20), mload(filAddress))
            }

            // Look up mocked actor ID
            actorId = addressMocks[key];

            // If actor exists (actorId > 0), return it as ABI-encoded uint64
            // Special case: SYSTEM_ACTOR_ID is 0, but we want to allow it to be mocked and returned
            if (actorId > 0 || key == SYSTEM_ACTOR_HASH) {
                bytes memory response = abi.encode(uint256(actorId));
                assembly ("memory-safe") {
                    return(add(response, 0x20), 32)
                }
            }

            // If actor doesn't exist (actorId == 0), return empty
            assembly ("memory-safe") {
                stop()
            }
        }
    }
}
