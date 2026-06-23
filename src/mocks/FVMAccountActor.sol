// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {CBOR_CODEC} from "../FVMCodec.sol";
import {USR_ILLEGAL_ARGUMENT, USR_UNHANDLED_MESSAGE} from "../FVMErrors.sol";
import {AUTHENTICATE_MESSAGE} from "../FVMMethod.sol";
import {FVMBlake2b} from "./FVMBlake2b.sol";

/// @notice Mock secp256k1 account actor for testing AuthenticateMessage (method 2643134072).
/// @dev Etch at an actor's masked ID address via MockFVMTest.mockAccount(actorId, addr).
///
/// Wire format (from ref-fvm): 65-byte compact secp256k1 signature: r (32) ‖ s (32) ‖ v (1)
/// where v is the raw recovery ID (0 or 1). This matches ecrecover convention after normalization.
///
/// Approximation vs. mainnet: the real account actor creates a Filecoin f1 address from the
/// recovered pubkey (blake2b-20 of the 65-byte uncompressed key). The EVM's ecrecover returns
/// an Ethereum address instead (keccak256 of pubkey[1:], last 20 bytes). This mock therefore
/// verifies against an Ethereum address — sufficient for forge-based tests using vm.sign().
contract FVMAccountActor {
    address internal _accountAddress;

    /// @notice Marker so FVMCallActorById can distinguish account mocks from other etched actors.
    function isMockAccount() external pure returns (bool) {
        return true;
    }

    /// @notice Set the Ethereum address AuthenticateMessage verifies signatures against.
    function mockAddress(address addr) external {
        _accountAddress = addr;
    }

    fallback() external {
        bytes memory response = abi.encode(uint32(USR_UNHANDLED_MESSAGE), uint64(0), bytes(""));
        assembly ("memory-safe") {
            return(add(response, 0x20), mload(response))
        }
    }

    function handle_filecoin_method(uint64 method, uint64 codec, bytes calldata params)
        external
        view
        returns (uint32, uint64, bytes memory)
    {
        if (method != AUTHENTICATE_MESSAGE) return (USR_UNHANDLED_MESSAGE, 0, "");
        if (codec != CBOR_CODEC) return (USR_ILLEGAL_ARGUMENT, 0, "");

        (bytes memory sig, bytes memory message) = _decodeCborParams(params);

        if (sig.length != 65) return (USR_ILLEGAL_ARGUMENT, 0, "");

        bytes32 msgHash = FVMBlake2b.hash(message);
        bytes32 r;
        bytes32 s;
        uint8 v;
        // Compact layout: sig[0:32]=r, sig[32:64]=s, sig[64]=v (recovery ID 0 or 1).
        assembly ("memory-safe") {
            r := mload(add(sig, 0x20))
            s := mload(add(sig, 0x40))
            v := byte(0, mload(add(sig, 0x60)))
        }
        // Normalize raw recovery ID (0/1) to Ethereum convention (27/28).
        if (v < 27) v += 27;

        address recovered = ecrecover(msgHash, v, r, s);
        if (recovered == address(0) || recovered != _accountAddress) {
            return (USR_ILLEGAL_ARGUMENT, 0, "");
        }

        return (0, CBOR_CODEC, abi.encodePacked(uint8(0xf5))); // CBOR true
    }

    function _decodeCborParams(bytes calldata data) private pure returns (bytes memory sig, bytes memory message) {
        require(data.length >= 1 && uint8(data[0]) == 0x82, "FVMAccountActor: expected array(2)");
        uint256 off = 1;
        (sig, off) = _decodeCborBytes(data, off);
        (message,) = _decodeCborBytes(data, off);
    }

    function _decodeCborBytes(bytes calldata data, uint256 off)
        private
        pure
        returns (bytes memory result, uint256 newOff)
    {
        uint8 b = uint8(data[off++]);
        require((b >> 5) == 2, "FVMAccountActor: expected CBOR bytes");
        uint8 info = b & 0x1f;
        uint256 len;
        if (info <= 23) {
            len = info;
        } else if (info == 24) {
            len = uint8(data[off++]);
        } else if (info == 25) {
            len = (uint256(uint8(data[off])) << 8) | uint256(uint8(data[off + 1]));
            off += 2;
        } else {
            revert("FVMAccountActor: bytes field too large");
        }
        result = bytes(data[off:off + len]);
        newOff = off + len;
    }
}
