// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {CALL_ACTOR_BY_ID} from "./FVMPrecompiles.sol";
import {FVMActor} from "./FVMActor.sol";
import {CBOR_CODEC} from "./FVMCodec.sol";
import {READONLY_FLAG} from "./FVMFlags.sol";
import {AUTHENTICATE_MESSAGE} from "./FVMMethod.sol";
import {EXIT_SUCCESS, NOT_FOUND} from "./FVMErrors.sol";

library FVMAccount {
    error ActorNotFound(uint64 actorId);
    error AuthenticationFailed(uint64 actorId, int256 exitCode);

    // =============================================================
    //                        BY ACTOR ID
    // =============================================================

    /// @notice Try to authenticate a message with an account actor.
    /// @param actorId The FVM actor ID of the account
    /// @param signature ECDSA signature bytes (65 bytes: r‖s‖v, v=27/28 or 0/1)
    /// @param message The signed message (pre-image, not a digest)
    /// @return exists False if the actor does not exist
    /// @return exitCode 0 on success; USR_ILLEGAL_ARGUMENT (16) if the signature is invalid
    function tryAuthenticateMessage(uint64 actorId, bytes memory signature, bytes memory message)
        internal
        returns (bool exists, int256 exitCode)
    {
        assembly ("memory-safe") {
            // ----------------------------------------------------------------
            // Build the CALL_ACTOR_BY_ID ABI payload in scratch memory.
            //
            // abi.encode layout (6 dynamic/static words + params bytes):
            //   [0x00]  method    (uint64 → padded to 32)
            //   [0x20]  value     (uint256)
            //   [0x40]  flags     (uint64 → padded to 32)
            //   [0x60]  codec     (uint64 → padded to 32)
            //   [0x80]  offset of params bytes  → points to [0xc0]
            //   [0xa0]  actorId   (uint64 → padded to 32)
            //   [0xc0]  params length
            //   [0xe0]  params data  (CBOR: 0x82 + sig bytes + msg bytes)
            //
            // CBOR for AuthenticateMessageParams = [signature, message] where
            // both are CBOR byte strings (major type 2).
            // ----------------------------------------------------------------

            let sigLen := mload(signature)
            let msgLen := mload(message)

            // Compute CBOR header sizes for each field.
            // Bytes header: 1 byte if len ≤ 23, 2 bytes if len ≤ 0xff, 3 bytes if len ≤ 0xffff.
            let sigHdrSize := add(1, mul(gt(sigLen, 23), add(1, gt(sigLen, 0xff))))
            let msgHdrSize := add(1, mul(gt(msgLen, 23), add(1, gt(msgLen, 0xff))))

            // Total CBOR params length: 1 (array header) + headers + payloads.
            let paramsLen := add(add(1, add(sigHdrSize, sigLen)), add(msgHdrSize, msgLen))

            // Pad paramsLen to 32-byte boundary for ABI encoding.
            let paramsPadded := and(add(paramsLen, 31), not(31))

            // Total calldata size: 7 words (0xe0) + paramsLen padded.
            let totalSize := add(0xe0, paramsPadded)

            let fmp := mload(0x40)

            mstore(fmp, AUTHENTICATE_MESSAGE) // method
            mstore(add(fmp, 0x20), 0) // value = 0
            mstore(add(fmp, 0x40), READONLY_FLAG) // flags
            mstore(add(fmp, 0x60), CBOR_CODEC) // codec
            mstore(add(fmp, 0x80), 0xc0) // offset of params bytes (relative to start)
            mstore(add(fmp, 0xa0), actorId) // actorId
            mstore(add(fmp, 0xc0), paramsLen) // params byte length

            // Write CBOR array(2) header.
            let cur := add(fmp, 0xe0)
            mstore8(cur, 0x82)
            cur := add(cur, 1)

            // Write CBOR bytes header for signature.
            switch sigHdrSize
            case 1 { mstore8(cur, or(0x40, sigLen)) }
            case 2 {
                mstore8(cur, 0x58)
                mstore8(add(cur, 1), sigLen)
            }
            default {
                mstore8(cur, 0x59)
                mstore8(add(cur, 1), shr(8, sigLen))
                mstore8(add(cur, 2), and(sigLen, 0xff))
            }
            cur := add(cur, sigHdrSize)

            // Copy signature payload.
            let srcSig := add(signature, 0x20)
            let i := 0
            for {} lt(i, sigLen) { i := add(i, 0x20) } { mstore(add(cur, i), mload(add(srcSig, i))) }
            cur := add(cur, sigLen)

            // Write CBOR bytes header for message.
            switch msgHdrSize
            case 1 { mstore8(cur, or(0x40, msgLen)) }
            case 2 {
                mstore8(cur, 0x58)
                mstore8(add(cur, 1), msgLen)
            }
            default {
                mstore8(cur, 0x59)
                mstore8(add(cur, 1), shr(8, msgLen))
                mstore8(add(cur, 2), and(msgLen, 0xff))
            }
            cur := add(cur, msgHdrSize)

            // Copy message payload.
            let srcMsg := add(message, 0x20)
            i := 0
            for {} lt(i, msgLen) { i := add(i, 0x20) } { mstore(add(cur, i), mload(add(srcMsg, i))) }

            // Delegatecall into CALL_ACTOR_BY_ID. Reuse fmp as output buffer.
            // A precompile revert signals a malformed call (bad flags, reserved method, etc.);
            // propagate it directly rather than wrapping in a typed error.
            if iszero(delegatecall(gas(), CALL_ACTOR_BY_ID, fmp, totalSize, fmp, 0x60)) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
            exitCode := mload(fmp)
        }
        exists = exitCode != NOT_FOUND;
    }

    /// @notice Authenticate a message, reverting if the actor does not exist or the signature is invalid.
    function authenticateMessage(uint64 actorId, bytes memory signature, bytes memory message) internal {
        (bool exists, int256 exitCode) = tryAuthenticateMessage(actorId, signature, message);
        require(exists, ActorNotFound(actorId));
        require(exitCode == EXIT_SUCCESS, AuthenticationFailed(actorId, exitCode));
    }

    // =============================================================
    //                      BY EVM ADDRESS
    // =============================================================

    /// @notice Try to authenticate a message with the account actor at the given EVM address.
    /// @dev Resolves the f410 address to an actor ID via the RESOLVE_ADDRESS precompile.
    function tryAuthenticateMessage(address addr, bytes memory signature, bytes memory message)
        internal
        returns (bool exists, int256 exitCode)
    {
        (bool resolved, uint64 actorId) = FVMActor.tryGetActorId(addr);
        if (!resolved) return (false, NOT_FOUND);
        return tryAuthenticateMessage(actorId, signature, message);
    }

    /// @notice Authenticate a message, reverting if the address cannot be resolved or the signature is invalid.
    function authenticateMessage(address addr, bytes memory signature, bytes memory message) internal {
        (bool exists, uint64 actorId) = FVMActor.tryGetActorId(addr);
        require(exists, FVMActor.EVMActorNotFound(addr));
        authenticateMessage(actorId, signature, message);
    }
}
