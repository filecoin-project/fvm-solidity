// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {CALL_ACTOR_BY_ID} from "../FVMPrecompiles.sol";
import {BURN_ACTOR_ID, BURN_ADDRESS, DATACAP_TOKEN_ACTOR_ID, STORAGE_POWER_ACTOR_ID} from "../FVMActors.sol";
import {FVMAddress} from "../FVMAddress.sol";
import {CBOR_CODEC, EMPTY_CODEC} from "../FVMCodec.sol";
import {
    EXIT_SUCCESS,
    INSUFFICIENT_FUNDS,
    NOT_FOUND,
    READ_ONLY,
    USR_ILLEGAL_ARGUMENT,
    USR_NOT_FOUND,
    USR_UNHANDLED_MESSAGE
} from "../FVMErrors.sol";
import {NO_FLAGS, READONLY_FLAG} from "../FVMFlags.sol";
import {DATACAP_TRANSFER, SEND, MINER_POWER, FIRST_EXPORTED_METHOD_NUMBER} from "../FVMMethod.sol";

contract FVMCallActorById {
    /// @dev CBOR `TransferReturn` for a single-allocation DataCap -> VerifReg
    /// transfer: [from_balance(empty), to_balance(empty), recipient_data] where
    /// recipient_data is a CBOR `VerifregResponse`:
    /// [allocationResults([1, []]), extensionResults([0, []]), [allocId=66]]
    /// multi-piece flows need a different fixture
    bytes constant DEFAULT_DATACAP_TRANSFER_RETURN = hex"8340404a83820180820080811842";

    struct Message {
        uint64 method;
        uint256 value;
        uint64 flags;
        uint64 codec;
        bytes params;
        uint64 actorId;
    }

    fallback() external payable {
        // Real precompile requires delegatecall; call/staticcall returns CallForbidden → (0, empty).
        if (address(this) == CALL_ACTOR_BY_ID) {
            assembly ("memory-safe") {
                revert(0, 0)
            }
        }
        Message memory m;
        (m.method, m.value, m.flags, m.codec, m.params, m.actorId) =
            abi.decode(msg.data, (uint64, uint256, uint64, uint64, bytes, uint64));

        if (m.actorId == BURN_ACTOR_ID) {
            _handleBurn(m);
        } else if (m.actorId == STORAGE_POWER_ACTOR_ID) {
            _handlePower(m);
        } else if (m.actorId == DATACAP_TOKEN_ACTOR_ID) {
            _handleDataCap(m);
        } else if (_isMockMiner(FVMAddress.maskedAddress(m.actorId))) {
            _handleMiner(m);
        } else if (_isMockAccount(FVMAddress.maskedAddress(m.actorId))) {
            _handleAccount(m);
        } else {
            // Unknown actor: no actor at this ID in our mock state.
            // Matches real FVM: send_raw returns ErrorNumber::NotFound → negative exit code, success=true.
            bytes memory response = abi.encode(NOT_FOUND, uint64(0), bytes(""));
            assembly ("memory-safe") {
                return(add(response, 0x20), mload(response))
            }
        }
    }

    /// @notice Handle storage power actor calls (PowerAPI.minerPower)
    /// @dev Returns success with dummy non-zero power for registered mock miners
    function _handlePower(Message memory m) internal view {
        require(m.method == MINER_POWER, "FVMCallActorById: unsupported power actor method");
        require(m.flags == READONLY_FLAG || m.flags == NO_FLAGS, "FVMCallActorById: invalid flags");
        require(m.codec == CBOR_CODEC, "FVMCallActorById: expected CBOR params");

        // Decode CBOR params: bare uint64 (MinerPowerParams is #[serde(transparent)])
        require(m.params.length >= 1, "FVMCallActorById: params too short");
        (uint64 queryActorId,) = _decodeCborUint64(m.params, 0);

        bytes memory response;
        if (_isMockMiner(FVMAddress.maskedAddress(queryActorId))) {
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
            // Power actor returns actor_error!(not_found) → USR_NOT_FOUND (+17), not a syscall error.
            response = abi.encode(int256(uint256(USR_NOT_FOUND)), EMPTY_CODEC, bytes(""));
        }
        assembly ("memory-safe") {
            return(add(response, 0x20), mload(response))
        }
    }

    function _handleBurn(Message memory m) private returns (bytes memory) {
        // Invalid flag bits: precompile only accepts READONLY_FLAG (bit 0); unknown bits → PrecompileError.
        if (m.flags & ~READONLY_FLAG != 0) {
            assembly ("memory-safe") {
                revert(0, 0)
            }
        }

        // Methods 1–1023 are blocked by the precompile (EVM_MAX_RESERVED_METHOD=1023); method 0 is SEND.
        if (m.method != SEND && m.method <= 1023) {
            assembly ("memory-safe") {
                revert(0, 0)
            }
        }

        // Codec must be CBOR or (empty codec with no params); anything else → PrecompileError.
        if (m.codec != CBOR_CODEC && (m.codec != EMPTY_CODEC || m.params.length != 0)) {
            assembly ("memory-safe") {
                revert(0, 0)
            }
        }

        // Read-only + non-zero value: kernel rejects before invoking the actor.
        if (m.flags == READONLY_FLAG && m.value > 0) {
            bytes memory response = abi.encode(READ_ONLY, EMPTY_CODEC, bytes(""));
            assembly ("memory-safe") {
                return(add(response, 0x20), mload(response))
            }
        }

        // Non-SEND methods >1023: dispatch to account actor fallback.
        // method < FIRST_EXPORTED_METHOD_NUMBER → USR_UNHANDLED_MESSAGE; else → exit 0.
        if (m.method != SEND) {
            bytes memory response = m.method >= FIRST_EXPORTED_METHOD_NUMBER
                ? abi.encode(EXIT_SUCCESS, EMPTY_CODEC, bytes(""))
                : abi.encode(int256(uint256(USR_UNHANDLED_MESSAGE)), EMPTY_CODEC, bytes(""));
            assembly ("memory-safe") {
                return(add(response, 0x20), mload(response))
            }
        }

        // SEND: transfer value. FVM ignores params for method 0.
        (bool ok,) = BURN_ADDRESS.call{value: m.value}("");
        bytes memory resp = ok
            ? abi.encode(EXIT_SUCCESS, EMPTY_CODEC, bytes(""))
            : abi.encode(INSUFFICIENT_FUNDS, EMPTY_CODEC, bytes(""));
        assembly ("memory-safe") {
            return(add(resp, 0x20), mload(resp))
        }
    }

    /// @notice Forward a call to the mock miner at its masked ID address via handle_filecoin_method.
    /// @dev Matching real FVM behaviour: actor errors are returned as non-zero exit codes, not reverts.
    ///      If the miner reverts (e.g. catastrophic CBOR parse failure), convert to USR_ILLEGAL_ARGUMENT.
    function _handleMiner(Message memory m) internal {
        require(m.flags == READONLY_FLAG || m.flags == NO_FLAGS, "FVMCallActorById: invalid flags");
        address minerAddr = FVMAddress.maskedAddress(m.actorId);
        (bool success, bytes memory ret) = minerAddr.call(
            abi.encodeWithSignature("handle_filecoin_method(uint64,uint64,bytes)", m.method, m.codec, m.params)
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

    /// @dev Returns true only for addresses that have FVMMinerActor etched.
    ///      FVMStoragePowerActor's fallback also returns data for any call, but 128 bytes not 32.
    function _isMockMiner(address addr) private view returns (bool) {
        (bool ok, bytes memory data) = addr.staticcall(abi.encodeWithSignature("isMockMiner()"));
        return ok && data.length == 32 && abi.decode(data, (bool));
    }

    function _isMockAccount(address addr) private view returns (bool) {
        (bool ok, bytes memory data) = addr.staticcall(abi.encodeWithSignature("isMockAccount()"));
        return ok && data.length == 32 && abi.decode(data, (bool));
    }

    function _handleAccount(Message memory m) internal {
        require(m.flags == READONLY_FLAG || m.flags == NO_FLAGS, "FVMCallActorById: invalid flags");
        address accountAddr = FVMAddress.maskedAddress(m.actorId);
        (bool success, bytes memory ret) = accountAddr.call(
            abi.encodeWithSignature("handle_filecoin_method(uint64,uint64,bytes)", m.method, m.codec, m.params)
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

    function _handleDataCap(Message memory m) private pure returns (bytes memory) {
        require(m.method == DATACAP_TRANSFER, "FVMCallActorById: DataCap only supports Transfer");
        return abi.encode(EXIT_SUCCESS, CBOR_CODEC, DEFAULT_DATACAP_TRANSFER_RETURN);
    }
}
