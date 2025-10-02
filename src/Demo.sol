// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {FVMPay} from "./FVMPay.sol";
import {FVMRandom} from "./FVMRandom.sol";

contract Demo {
    // baseline solidity methods using CALL opcode

    function send(address payable who) external payable {
        require(who.send(msg.value));
    }

    function transfer(address payable who) external payable {
        who.transfer(msg.value);
    }

    // pay address using CALL_ACTOR_BY_ADDRESS precompile with method 0 (Send)
    using FVMPay for address;

    function pay(address who) external payable {
        require(who.pay(msg.value));
    }

    // pay actor using CALL_ACTOR_BY_ID precompile with method 0 (Send)
    using FVMPay for uint64;

    function pay(uint64 actorId) external payable {
        require(actorId.pay(msg.value));
    }

    // pay burn actor using CALL_ACTOR_BY_ID precompile with method 0 (Send)
    using FVMPay for uint256;

    function burn() external payable {
        require(msg.value.burn());
    }

    // randomness
    using FVMRandom for uint256;

    function prev() external view returns (uint256 randomness) {
        randomness = (block.number - 1).getBeaconRandomness();
    }

    function curr() external view returns (uint256 randomness) {
        randomness = block.number.getBeaconRandomness();
    }

    function next() external view returns (uint256 randomness) {
        randomness = (block.number + 1).getBeaconRandomness();
    }
}
