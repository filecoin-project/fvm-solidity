// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

uint64 constant SEND = 0;
uint64 constant CONSTRUCT = 1;

// Lowest method number callable by user actors (FRC-0042 / restrict_internal_api threshold).
// Methods 1–(FIRST_EXPORTED_METHOD_NUMBER-1) are reserved for built-in callers only.
uint64 constant FIRST_EXPORTED_METHOD_NUMBER = 1 << 24; // 16777216

// All method numbers below are FRC-0042 hashed (https://github.com/filecoin-project/FIPs/blob/master/FRCs/frc-0042.md)

// Storage power actor methods
uint64 constant CREATE_MINER_POWER = 1173380165;
uint64 constant NETWORK_RAW_POWER = 931722534;
uint64 constant MINER_RAW_POWER = 3753401894;
uint64 constant MINER_COUNT = 1987646258;
uint64 constant MINER_CONSENSUS_COUNT = 196739875;
uint64 constant MINER_POWER = 36284446;

// Cross-actor receiver methods
uint64 constant AUTHENTICATE_MESSAGE = 2643134072;
uint64 constant UNIVERSAL_RECEIVER_HOOK = 118350608;
uint64 constant RECEIVE = 3726118371;
uint64 constant MARKET_NOTIFY_DEAL = 4186741094;
uint64 constant SECTOR_CONTENT_CHANGED = 2034386435;
uint64 constant INVOKE_EVM = 3844450837;

// Miner actor methods
uint64 constant GET_OWNER = 3275365574;
uint64 constant CHANGE_OWNER_ADDRESS = 1010589339;
uint64 constant IS_CONTROLLING_ADDRESS = 348244887;
uint64 constant GET_SECTOR_SIZE = 3858292296;
uint64 constant GET_AVAILABLE_BALANCE = 4026106874;
uint64 constant GET_VESTING_FUNDS = 1726876304;
uint64 constant CHANGE_WORKER_ADDRESS = 3302309124;
uint64 constant CHANGE_PEER_ID = 1236548004;
uint64 constant CHANGE_MULTIADDRS = 1063480576;
uint64 constant CONFIRM_CHANGE_WORKER_ADDRESS = 2354970453;
uint64 constant REPAY_DEBT = 3665352697;
uint64 constant GET_PEER_ID = 2812875329;
uint64 constant GET_MULTIADDRS = 1332909407;
uint64 constant WITHDRAW_BALANCE = 2280458852;
uint64 constant CHANGE_BENEFICIARY = 1570634796;
uint64 constant GET_BENEFICIARY = 4158972569;
uint64 constant MAX_TERMINATION_FEE = 4127382196;
uint64 constant INITIAL_PLEDGE = 3180523767;
uint64 constant VALIDATE_SECTOR_STATUS = 3092458564;
uint64 constant GENERATE_SECTOR_LOCATION = 1321604665;
uint64 constant GET_NOMINAL_SECTOR_EXPIRATION = 3010055991;
