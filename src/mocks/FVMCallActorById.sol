// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {BURN_ACTOR_ID, BURN_ADDRESS, STORAGE_POWER_ACTOR_ID} from "../FVMActors.sol";
import {CBOR_CODEC, EMPTY_CODEC} from "../FVMCodec.sol";
import {EXIT_SUCCESS, INSUFFICIENT_FUNDS, NOT_FOUND, USR_NOT_FOUND, USR_ILLEGAL_ARGUMENT} from "../FVMErrors.sol";
import {NO_FLAGS, READONLY_FLAG} from "../FVMFlags.sol";
import {SEND, MINER_POWER} from "../FVMMethod.sol";
import {FVMAddress} from "../FVMAddress.sol";

contract FVMCallActorById {
    /// @notice Registry of mock miner actor IDs for PowerAPI verification
    mapping(uint64 => bool) public mockMiners;

    /// @notice Register an actor ID as a valid miner for PowerAPI calls
    function mockMiner(uint64 actorId) external {
        mockMiners[actorId] = true;
    }

    fallback() external payable {
        (uint64 method, uint256 value, uint64 flags, uint64 codec, bytes memory params, uint64 actorId) =
            abi.decode(msg.data, (uint64, uint256, uint64, uint64, bytes, uint64));

        if (actorId == BURN_ACTOR_ID) {
            _handleBurn(method, value, flags, codec, params);
        } else if (actorId == STORAGE_POWER_ACTOR_ID) {
            _handlePower(method, flags, codec, params);
        } else if (mockMiners[actorId]) {
            _handleMiner(actorId, method, value, flags, codec, params);
        } else {
            // Unknown actor: no actor at this ID in our mock state.
            // Matches real FVM: send_raw returns ErrorNumber::NotFound → negative exit code, success=true.
            bytes memory response = abi.encode(NOT_FOUND, uint64(0), bytes(""));
            assembly ("memory-safe") {
                return(add(response, 0x20), mload(response))
            }
        }
    }

    function _handleBurn(uint64 method, uint256 value, uint64 flags, uint64 codec, bytes memory params) internal {
        require(method == SEND, "FVMCallActorById: Only method 0 (send) supported");
        require(flags == NO_FLAGS, "FVMCallActorById: Only non-readonly calls supported");
        require(codec == EMPTY_CODEC, "FVMCallActorById: Only no-codec calls supported");
        require(params.length == 0, "FVMCallActorById: No params expected");

        (bool success,) = BURN_ADDRESS.call{value: value}("");
        bytes memory response = success
            ? abi.encode(EXIT_SUCCESS, EMPTY_CODEC, bytes(""))
            : abi.encode(INSUFFICIENT_FUNDS, EMPTY_CODEC, bytes(""));
        assembly ("memory-safe") {
            return(add(response, 0x20), mload(response))
        }
    }

    /// @notice Handle storage power actor calls (PowerAPI.minerPower)
    /// @dev Returns success with dummy non-zero power for registered mock miners
    function _handlePower(uint64 method, uint64 flags, uint64 codec, bytes memory params) internal view {
        require(method == MINER_POWER, "FVMCallActorById: unsupported power actor method");
        require(flags == READONLY_FLAG || flags == NO_FLAGS, "FVMCallActorById: invalid flags");
        require(codec == CBOR_CODEC, "FVMCallActorById: expected CBOR params");

        // Decode CBOR params: [actorId] (1-element array containing uint64)
        require(params.length >= 2, "FVMCallActorById: params too short");
        require(uint8(params[0]) == 0x81, "FVMCallActorById: expected 1-element array");
        (uint64 queryActorId,) = _decodeCborUint64(params, 1);

        bytes memory response;
        if (mockMiners[queryActorId]) {
            // Encode MinerPowerReturn = [miner_claim, total_claim, has_min_power]
            // Claim = [raw_byte_power, quality_adj_power] where power = CBOR bytes (bigint)
            // Using 1 byte power (0x01) as a dummy non-zero value
            bytes memory powerBytes = abi.encodePacked(uint8(0x41), uint8(0x01)); // bytes(1) = 0x01
            bytes memory claim = abi.encodePacked(uint8(0x82), powerBytes, powerBytes); // [raw, qa]
            bytes memory retCbor = abi.encodePacked(
                uint8(0x83), // array(3): [miner_claim, total_claim, has_min_power]
                claim,
                claim,
                uint8(0xf5) // true
            );
            response = abi.encode(EXIT_SUCCESS, CBOR_CODEC, retCbor);
        } else {
            // Power actor returns actor_error!(not_found) → USR_NOT_FOUND (+14), not a syscall error.
            response = abi.encode(int256(uint256(USR_NOT_FOUND)), EMPTY_CODEC, bytes(""));
        }
        assembly ("memory-safe") {
            return(add(response, 0x20), mload(response))
        }
    }

    /// @notice Forward a call to the mock miner at its masked ID address via handle_filecoin_method.
    /// @dev Matching real FVM behaviour: actor errors are returned as non-zero exit codes, not reverts.
    ///      If the miner reverts (e.g. catastrophic CBOR parse failure), convert to USR_ILLEGAL_ARGUMENT.
    function _handleMiner(uint64 actorId, uint64 method, uint256, uint64 flags, uint64 codec, bytes memory params)
        internal
    {
        require(flags == READONLY_FLAG || flags == NO_FLAGS, "FVMCallActorById: invalid flags");
        address minerAddr = FVMAddress.maskedAddress(actorId);
        (bool success, bytes memory ret) = minerAddr.call(
            abi.encodeWithSignature("handle_filecoin_method(uint64,uint64,bytes)", method, codec, params)
        );
        if (!success) {
            bytes memory errResponse = abi.encode(uint32(USR_ILLEGAL_ARGUMENT), uint64(0), bytes(""));
            assembly ("memory-safe") {
                return(add(errResponse, 0x20), mload(errResponse))
            }
        }
        assembly ("memory-safe") {
            return(add(ret, 0x20), mload(ret))
        }
    }

    /// @dev Decode a CBOR-encoded uint64 from `data` at `offset`
    function _decodeCborUint64(bytes memory data, uint256 offset) private pure returns (uint64 v, uint256 newOffset) {
        uint8 b = uint8(data[offset++]);
        require((b >> 5) == 0, "FVMCallActorById: expected CBOR uint");
        uint8 info = b & 0x1f;
        if (info <= 23) return (uint64(info), offset);
        if (info == 24) return (uint64(uint8(data[offset])), offset + 1);
        if (info == 25) {
            v = (uint64(uint8(data[offset])) << 8) | uint64(uint8(data[offset + 1]));
            return (v, offset + 2);
        }
        if (info == 26) {
            v = (uint64(uint8(data[offset])) << 24) | (uint64(uint8(data[offset + 1])) << 16)
                | (uint64(uint8(data[offset + 2])) << 8) | uint64(uint8(data[offset + 3]));
            return (v, offset + 4);
        }
        if (info == 27) {
            for (uint256 i = 0; i < 8; i++) {
                v = (v << 8) | uint64(uint8(data[offset + i]));
            }
            return (v, offset + 8);
        }
        revert("FVMCallActorById: uint64 too large");
    }
}
