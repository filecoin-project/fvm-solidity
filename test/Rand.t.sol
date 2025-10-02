// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {FVMRandom} from "../src/FVMRandom.sol";

contract RandTest is MockFVMTest {
    using FVMRandom for uint256;

    function testNextRandom() public {
        vm.expectRevert();
        (vm.getBlockNumber() + 1).getBeaconRandomness();
    }

    function testUnmockedRandom() public view {
        assertEq(vm.getBlockNumber().getBeaconRandomness(), 4);
    }

    function testMockRandom() public {
        uint256 expectedRandomness = 0x0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef;
        RANDOMNESS_PRECOMPILE.mockBeaconRandomness(vm.getBlockNumber(), expectedRandomness);
        assertEq(vm.getBlockNumber().getBeaconRandomness(), expectedRandomness);
    }
}
