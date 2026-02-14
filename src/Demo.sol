// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {FVMPay} from "./FVMPay.sol";
import {FVMRandom} from "./FVMRandom.sol";
import {FVMActor} from "./FVMActor.sol";
import {FVMAddress} from "./FVMAddress.sol";

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

    // resolve address
    using FVMActor for bytes;
    using FVMActor for address;

    /// @notice Try to get the actor ID for a Filecoin address
    function tryGetActorId(bytes calldata filAddress) external view returns (bool exists, uint64 actorId) {
        return filAddress.tryGetActorId();
    }

    /// @notice Get the actor ID for a Filecoin address, requiring the actor exists
    function getActorId(bytes calldata filAddress) external view returns (uint64 actorId) {
        return filAddress.getActorId();
    }

    /// @notice Try to get the actor ID for a Solidity address
    function tryGetActorId(address addr) external view returns (bool exists, uint64 actorId) {
        return addr.tryGetActorId();
    }

    /// @notice Get the actor ID for a Solidity address, requiring the actor exists
    function getActorId(address addr) external view returns (uint64 actorId) {
        return addr.getActorId();
    }

    // address encoding
    using FVMAddress for uint64;
    using FVMAddress for address;

    /// @notice Encode an actor ID as an f0 address
    function toF0(uint64 actorId) external pure returns (bytes memory) {
        return actorId.f0();
    }

    /// @notice Encode a Solidity address as an f410 address (EVM namespace)
    function toF410(address addr) external pure returns (bytes memory) {
        return addr.f410();
    }

    /// @notice Encode a subaddress as an f410 address with a given namespace
    function toF4(uint8 namespace, bytes20 subaddress) external pure returns (bytes memory) {
        return FVMAddress.f4(namespace, subaddress);
    }
}
