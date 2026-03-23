// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

// Syscall errors: filecoin-project/ref-fvm shared/src/error/mod.rs
// Exit codes: https://docs.rs/fvm_shared/latest/fvm_shared/error/struct.ExitCode.html

int256 constant EXIT_SUCCESS = 0;

// Syscall error numbers (negative exit codes, ErrorNumber in ref-fvm)

// @dev A syscall parameters was invalid.
int256 constant ILLEGAL_ARGUMENT = -1;
// @dev The actor is not in the correct state to perform the requested operation.
int256 constant ILLEGAL_OPERATION = -2;
// @dev This syscall would exceed some system limit (memory, lookback, call depth, etc.).
int256 constant LIMIT_EXCEEDED = -3;
// @dev A system-level assertion has failed.
int256 constant ASSERTION_FAILED = -4;
// @dev There were insufficient funds to complete the requested operation.
int256 constant INSUFFICIENT_FUNDS = -5;
// @dev A resource was not found.
int256 constant NOT_FOUND = -6;
// @dev The specified IPLD block handle was invalid.
int256 constant INVALID_HANDLE = -7;
// @dev The requested CID shape (multihash codec, multihash length) isn't supported.
int256 constant ILLEGAL_CID = -8;
// @dev The requested IPLD codec isn't supported.
int256 constant ILLEGAL_CODEC = -9;
// @dev The IPLD block did not match the specified IPLD codec.
int256 constant SERIALIZATION = -10;
// @dev The operation is forbidden.
int256 constant FORBIDDEN = -11;
// @dev The passed buffer is too small.
int256 constant BUFFER_TOO_SMALL = -12;
// @dev The actor is executing in a read-only context.
int256 constant READ_ONLY = -13;

// System exit codes (positive, ExitCode in fvm_shared::error, set by the VM — actors cannot use these)
// @dev The message sender doesn't exist.
uint32 constant SYS_SENDER_INVALID = 1;
// @dev The message sender was not in a valid state (bad nonce or insufficient gas funds).
uint32 constant SYS_SENDER_STATE_INVALID = 2;
// @dev The message receiver trapped (panicked).
uint32 constant SYS_ILLEGAL_INSTRUCTION = 4;
// @dev The receiver doesn't exist and can't be auto-created, or doesn't implement the entrypoint.
uint32 constant SYS_INVALID_RECEIVER = 5;
// @dev The message sender didn't have the requisite funds.
uint32 constant SYS_INSUFFICIENT_FUNDS = 6;
// @dev Message execution (including subcalls) used more gas than the specified limit.
uint32 constant SYS_OUT_OF_GAS = 7;
// @dev The message receiver aborted with a reserved exit code.
uint32 constant SYS_ILLEGAL_EXIT_CODE = 9;
// @dev An internal VM assertion failed.
uint32 constant SYS_ASSERTION_FAILED = 10;
// @dev The actor returned a block handle that doesn't exist.
uint32 constant SYS_MISSING_RETURN = 11;

// Actor user exit codes (positive, ExitCode in fvm_shared::error)
// @dev The method parameters are invalid.
uint32 constant USR_ILLEGAL_ARGUMENT = 16;
// @dev The requested resource does not exist.
uint32 constant USR_NOT_FOUND = 17;
// @dev The requested operation is forbidden.
uint32 constant USR_FORBIDDEN = 18;
// @dev The actor has insufficient funds to perform the requested operation.
uint32 constant USR_INSUFFICIENT_FUNDS = 19;
// @dev The actor's internal state is invalid.
uint32 constant USR_ILLEGAL_STATE = 20;
// @dev There was a de/serialization failure within actor code.
uint32 constant USR_SERIALIZATION = 21;
// @dev The message cannot be handled (usually indicates an unhandled method number).
uint32 constant USR_UNHANDLED_MESSAGE = 22;
// @dev The actor failed with an unspecified error.
uint32 constant USR_UNSPECIFIED = 23;
// @dev The actor failed a user-level assertion.
uint32 constant USR_ASSERTION_FAILED = 24;
// @dev The requested operation cannot be performed in read-only mode.
uint32 constant USR_READ_ONLY = 25;
// @dev The method cannot handle a transfer of value.
uint32 constant USR_NOT_PAYABLE = 26;
