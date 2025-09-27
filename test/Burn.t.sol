// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {BURN_ACTOR_ID, BURN_ADDRESS} from "../src/FVMActors.sol";
import {FVMPay} from "../src/FVMPay.sol";

contract BurnTest is MockFVMTest {
    using FVMPay for uint64;

    function testBurnByActorId() public {
        assertEq(BURN_ADDRESS.balance, 0);
        BURN_ACTOR_ID.pay(50 ether);
        assertEq(BURN_ADDRESS.balance, 50 ether);
    }
}
