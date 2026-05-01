// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {USR_UNHANDLED_MESSAGE} from "../FVMErrors.sol";

/// @notice Mock for the Filecoin Storage Power actor etched at its masked ID address
///         (actor ID 4, 0xFf00000000000000000000000000000000000004).
/// @dev The real power actor is a native actor: it does not handle InvokeContract (the method
///      the EVM CALL opcode sends), so direct EVM CALL to its masked address fails with
///      USR_UNHANDLED_MESSAGE rather than succeeding like an account actor would.
///      Calls via the CALL_ACTOR_BY_ID precompile with specific method numbers (e.g. MinerPower)
///      are handled by FVMCallActorById._handlePower, not by this contract.
contract FVMStoragePowerActor {
    fallback() external {
        bytes memory response = abi.encode(uint32(USR_UNHANDLED_MESSAGE), uint64(0), bytes(""));
        assembly ("memory-safe") {
            return(add(response, 0x20), mload(response))
        }
    }
}
