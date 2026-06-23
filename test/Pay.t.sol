// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {FVMPay} from "../src/FVMPay.sol";

contract PayTest is MockFVMTest {
    using FVMPay for address;
    using FVMPay for address payable;

    function testPayAddress() public {
        address recipient = vm.addr(1);
        uint256 senderBefore = address(this).balance;
        assertEq(recipient.balance, 0);
        address(recipient).pay(10 ether);
        assertEq(recipient.balance, 10 ether);
        assertEq(address(this).balance, senderBefore - 10 ether);
    }

    function testPayPayable() public {
        address payable recipient = payable(vm.addr(1));
        uint256 senderBefore = address(this).balance;
        assertEq(recipient.balance, 0);
        recipient.pay(10 ether);
        assertEq(recipient.balance, 10 ether);
        assertEq(address(this).balance, senderBefore - 10 ether);
    }
}
