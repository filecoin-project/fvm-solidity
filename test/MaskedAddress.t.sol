// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {FVMAddress} from "../src/FVMAddress.sol";

contract SafeUnmask {
    using FVMAddress for address;

    function unmask(address addr) public pure returns (uint64) {
        return addr.safeActorId();
    }
}

contract MaskedAddressTest is Test {
    using FVMAddress for address;
    using FVMAddress for uint64;

    function testMaskUnamsk() public pure {
        uint64 actorId = 3;
        assertEq(actorId, actorId.maskedAddress().actorId());
        assertEq(actorId, actorId.maskedAddress().safeActorId());
    }

    function testSafeUnmask() public {
        SafeUnmask unmasker = new SafeUnmask();

        address masked = 0xFf00000000000000000000001000000000000000;
        assertEq(masked.actorId(), unmasker.unmask(masked));

        address notMasked = 0xFf00000000000000000000010000000000000000;
        vm.expectRevert(abi.encodeWithSelector(FVMAddress.NotMaskedIdAddress.selector, notMasked));
        unmasker.unmask(notMasked);
    }
}
