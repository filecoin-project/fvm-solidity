// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {CALL_ACTOR_BY_ID} from "../FVMPrecompiles.sol";
import {FVMCallActorById} from "./FVMCallActorById.sol";

contract MockFVMTest is Test {
    function setUp() public {
        vm.etch(CALL_ACTOR_BY_ID, address(new FVMCallActorById()).code);
    }
}
