// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

uint64 constant SEND = 0;
uint64 constant CONSTRUCT = 1;

// Storage power actor methods
uint64 constant MINER_POWER = 36284446;

// FRC-0042 hashed method numbers (https://github.com/filecoin-project/FIPs/blob/master/FRCs/frc-0042.md)
uint64 constant AUTHENTICATE_MESSAGE = 2643134072;
uint64 constant UNIVERSAL_RECEIVER_HOOK = 118350608;
uint64 constant RECEIVE = 3726118371;
uint64 constant MARKET_NOTIFY_DEAL = 4186741094;
uint64 constant SECTOR_CONTENT_CHANGED = 2034386435;
uint64 constant INVOKE_EVM = 3844450837;

// FIP-0112 miner actor methods
uint64 constant VALIDATE_SECTOR_STATUS = 3092458564;
uint64 constant GENERATE_SECTOR_LOCATION = 1321604665;
uint64 constant GET_NOMINAL_SECTOR_EXPIRATION = 3010055991;
