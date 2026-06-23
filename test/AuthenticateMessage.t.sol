// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {MockFVMTest} from "../src/mocks/MockFVMTest.sol";
import {FVMAccountActor} from "../src/mocks/FVMAccountActor.sol";
import {FVMActor} from "../src/FVMActor.sol";
import {FVMAddress} from "../src/FVMAddress.sol";
import {CBOR_CODEC, EMPTY_CODEC} from "../src/FVMCodec.sol";
import {EXIT_SUCCESS, NOT_FOUND, USR_ILLEGAL_ARGUMENT, USR_UNHANDLED_MESSAGE} from "../src/FVMErrors.sol";
import {READONLY_FLAG} from "../src/FVMFlags.sol";
import {AUTHENTICATE_MESSAGE} from "../src/FVMMethod.sol";
import {CALL_ACTOR_BY_ID} from "../src/FVMPrecompiles.sol";
import {FVMAccount} from "../src/FVMAccount.sol";
import {FVMBlake2b} from "../src/mocks/FVMBlake2b.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @dev External wrapper so vm.expectRevert can intercept the full authenticateMessage call,
///      not just the delegatecall to the precompile inside it.
contract FVMAccountCaller {
    function byId(uint64 actorId, bytes memory sig, bytes memory message) external {
        FVMAccount.authenticateMessage(actorId, sig, message);
    }

    function byAddress(address addr, bytes memory sig, bytes memory message) external {
        FVMAccount.authenticateMessage(addr, sig, message);
    }
}

contract AuthenticateMessageTest is MockFVMTest {
    using FVMAddress for uint64;

    // Foundry default account 0
    uint256 constant SIGNER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address constant SIGNER_ADDR = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    // Foundry default account 1 (wrong signer)
    uint256 constant OTHER_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;

    uint64 constant ACTOR_ID = 1234;
    uint64 constant UNKNOWN_ID = 9999;

    FVMAccountActor account;
    FVMAccountCaller caller;

    function setUp() public override {
        super.setUp();
        account = mockAccount(ACTOR_ID, SIGNER_ADDR);
        caller = new FVMAccountCaller();
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _sign(uint256 key, bytes memory message) internal view returns (bytes memory sig) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, FVMBlake2b.hash(message));
        sig = abi.encodePacked(r, s, v);
    }

    /// @dev CBOR-encode bytes: major type 2 with length prefix.
    function _cborBytes(bytes memory data) internal pure returns (bytes memory) {
        uint256 len = data.length;
        if (len <= 23) return abi.encodePacked(uint8(0x40 | len), data);
        if (len <= 0xff) return abi.encodePacked(uint8(0x58), uint8(len), data);
        return abi.encodePacked(uint8(0x59), uint16(len), data);
    }

    function _cborParams(bytes memory sig, bytes memory message) internal pure returns (bytes memory) {
        return abi.encodePacked(uint8(0x82), _cborBytes(sig), _cborBytes(message));
    }

    function _callActor(uint64 actorId, uint64 method, uint256 value, uint64 flags, uint64 codec, bytes memory params)
        internal
        returns (bool success, bytes memory ret)
    {
        bytes memory callData = abi.encode(method, value, flags, codec, params, actorId);
        (success, ret) = CALL_ACTOR_BY_ID.delegatecall(callData);
    }

    // =========================================================================
    // Mock actor: handle_filecoin_method directly
    // =========================================================================

    function testDirect_ValidSignature() public view {
        bytes memory message = "hello world";
        bytes memory sig = _sign(SIGNER_KEY, message);
        (uint32 exitCode, uint64 codec, bytes memory data) =
            account.handle_filecoin_method(AUTHENTICATE_MESSAGE, CBOR_CODEC, _cborParams(sig, message));
        assertEq(exitCode, 0);
        assertEq(codec, CBOR_CODEC);
        assertEq(data.length, 1);
        assertEq(uint8(data[0]), 0xf5); // CBOR true
    }

    function testDirect_VRawRecoveryId() public view {
        // v = 0 or 1 (raw secp256k1 recovery ID) must also verify.
        bytes memory message = "hello world";
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(SIGNER_KEY, FVMBlake2b.hash(message));
        bytes memory sig = abi.encodePacked(r, s, uint8(v - 27)); // strip Ethereum offset
        (uint32 exitCode,,) =
            account.handle_filecoin_method(AUTHENTICATE_MESSAGE, CBOR_CODEC, _cborParams(sig, message));
        assertEq(exitCode, 0);
    }

    function testDirect_WrongSigner() public view {
        bytes memory message = "hello world";
        bytes memory sig = _sign(OTHER_KEY, message);
        (uint32 exitCode,,) =
            account.handle_filecoin_method(AUTHENTICATE_MESSAGE, CBOR_CODEC, _cborParams(sig, message));
        assertEq(exitCode, USR_ILLEGAL_ARGUMENT);
    }

    function testDirect_WrongMessage() public view {
        bytes memory message = "hello world";
        bytes memory sig = _sign(SIGNER_KEY, message);
        (uint32 exitCode,,) =
            account.handle_filecoin_method(AUTHENTICATE_MESSAGE, CBOR_CODEC, _cborParams(sig, "hello world!"));
        assertEq(exitCode, USR_ILLEGAL_ARGUMENT);
    }

    function testDirect_ZeroSignature() public view {
        // ecrecover of an all-zero signature returns address(0), which must be rejected.
        bytes memory sig = new bytes(65);
        sig[64] = 0x1b; // v = 27
        (uint32 exitCode,,) =
            account.handle_filecoin_method(AUTHENTICATE_MESSAGE, CBOR_CODEC, _cborParams(sig, "hello"));
        assertEq(exitCode, USR_ILLEGAL_ARGUMENT);
    }

    function testDirect_ShortSignature() public view {
        bytes memory sig = hex"deadbeef"; // not 65 bytes
        (uint32 exitCode,,) =
            account.handle_filecoin_method(AUTHENTICATE_MESSAGE, CBOR_CODEC, _cborParams(sig, "hello"));
        assertEq(exitCode, USR_ILLEGAL_ARGUMENT);
    }

    function testDirect_WrongCodec() public view {
        bytes memory message = "hello world";
        bytes memory sig = _sign(SIGNER_KEY, message);
        (uint32 exitCode,,) =
            account.handle_filecoin_method(AUTHENTICATE_MESSAGE, EMPTY_CODEC, _cborParams(sig, message));
        assertEq(exitCode, USR_ILLEGAL_ARGUMENT);
    }

    function testDirect_UnhandledMethod() public view {
        (uint32 exitCode,,) = account.handle_filecoin_method(1, CBOR_CODEC, "");
        assertEq(exitCode, USR_UNHANDLED_MESSAGE);
    }

    // =========================================================================
    // Mock dispatch: via CALL_ACTOR_BY_ID
    // =========================================================================

    function testDispatch_ValidSignature() public {
        bytes memory message = "hello filecoin";
        bytes memory sig = _sign(SIGNER_KEY, message);
        (bool success, bytes memory ret) =
            _callActor(ACTOR_ID, AUTHENTICATE_MESSAGE, 0, READONLY_FLAG, CBOR_CODEC, _cborParams(sig, message));
        assertTrue(success);
        (int256 exitCode, uint64 codec, bytes memory data) = abi.decode(ret, (int256, uint64, bytes));
        assertEq(exitCode, EXIT_SUCCESS);
        assertEq(codec, CBOR_CODEC);
        assertEq(uint8(data[0]), 0xf5);
    }

    function testDispatch_UnknownActor() public {
        bytes memory message = "hello";
        bytes memory sig = _sign(SIGNER_KEY, message);
        (bool success, bytes memory ret) =
            _callActor(UNKNOWN_ID, AUTHENTICATE_MESSAGE, 0, READONLY_FLAG, CBOR_CODEC, _cborParams(sig, message));
        assertTrue(success); // precompile itself succeeded
        (int256 exitCode,,) = abi.decode(ret, (int256, uint64, bytes));
        assertEq(exitCode, NOT_FOUND);
    }

    function testDispatch_WrongSigner() public {
        bytes memory message = "hello";
        bytes memory sig = _sign(OTHER_KEY, message);
        (bool success, bytes memory ret) =
            _callActor(ACTOR_ID, AUTHENTICATE_MESSAGE, 0, READONLY_FLAG, CBOR_CODEC, _cborParams(sig, message));
        assertTrue(success);
        (int256 exitCode,,) = abi.decode(ret, (int256, uint64, bytes));
        assertEq(exitCode, int256(uint256(USR_ILLEGAL_ARGUMENT)));
    }

    // Resolve address precompile maps SIGNER_ADDR → ACTOR_ID after mockAccount.
    function testResolveAddress_RegisteredByMockAccount() public view {
        (bool exists, uint64 actorId) = FVMActor.tryGetActorId(SIGNER_ADDR);
        assertTrue(exists);
        assertEq(actorId, ACTOR_ID);
    }

    // =========================================================================
    // FVMAccount library — by actor ID
    // =========================================================================

    function testLib_ValidSignature() public {
        bytes memory message = "hello filecoin";
        bytes memory sig = _sign(SIGNER_KEY, message);
        (bool exists, int256 exitCode) = FVMAccount.tryAuthenticateMessage(ACTOR_ID, sig, message);
        assertTrue(exists);
        assertEq(exitCode, EXIT_SUCCESS);
    }

    function testLib_WrongSigner() public {
        bytes memory message = "hello filecoin";
        bytes memory sig = _sign(OTHER_KEY, message);
        (bool exists, int256 exitCode) = FVMAccount.tryAuthenticateMessage(ACTOR_ID, sig, message);
        assertTrue(exists);
        assertEq(exitCode, int256(uint256(USR_ILLEGAL_ARGUMENT)));
    }

    function testLib_UnknownActor() public {
        bytes memory message = "hello";
        bytes memory sig = _sign(SIGNER_KEY, message);
        (bool exists,) = FVMAccount.tryAuthenticateMessage(UNKNOWN_ID, sig, message);
        assertFalse(exists);
    }

    function testLib_Strict_ValidSignature() public {
        bytes memory message = "hello filecoin";
        bytes memory sig = _sign(SIGNER_KEY, message);
        caller.byId(ACTOR_ID, sig, message);
    }

    function testLib_Strict_UnknownActor_Reverts() public {
        bytes memory message = "hello";
        bytes memory sig = _sign(SIGNER_KEY, message);
        vm.expectRevert(abi.encodeWithSelector(FVMAccount.ActorNotFound.selector, UNKNOWN_ID));
        caller.byId(UNKNOWN_ID, sig, message);
    }

    function testLib_Strict_WrongSigner_Reverts() public {
        bytes memory message = "hello";
        bytes memory sig = _sign(OTHER_KEY, message);
        vm.expectRevert(
            abi.encodeWithSelector(
                FVMAccount.AuthenticationFailed.selector, ACTOR_ID, int256(uint256(USR_ILLEGAL_ARGUMENT))
            )
        );
        caller.byId(ACTOR_ID, sig, message);
    }

    // =========================================================================
    // FVMAccount library — by EVM address
    // =========================================================================

    function testLib_ByAddress_ValidSignature() public {
        bytes memory message = "hello filecoin";
        bytes memory sig = _sign(SIGNER_KEY, message);
        (bool exists, int256 exitCode) = FVMAccount.tryAuthenticateMessage(SIGNER_ADDR, sig, message);
        assertTrue(exists);
        assertEq(exitCode, EXIT_SUCCESS);
    }

    function testLib_ByAddress_UnknownAddress() public {
        address unknown = address(0xdead);
        bytes memory message = "hello";
        bytes memory sig = _sign(SIGNER_KEY, message);
        (bool exists,) = FVMAccount.tryAuthenticateMessage(unknown, sig, message);
        assertFalse(exists);
    }

    function testLib_ByAddress_Strict_ValidSignature() public {
        bytes memory message = "hello filecoin";
        bytes memory sig = _sign(SIGNER_KEY, message);
        caller.byAddress(SIGNER_ADDR, sig, message);
    }

    function testLib_ByAddress_Strict_UnknownAddress_Reverts() public {
        address unknown = address(0xdead);
        bytes memory message = "hello";
        bytes memory sig = _sign(SIGNER_KEY, message);
        vm.expectRevert(abi.encodeWithSelector(FVMActor.EVMActorNotFound.selector, unknown));
        caller.byAddress(unknown, sig, message);
    }

    // =========================================================================
    // f1 (secp256k1) account mock via mockF1Account
    // =========================================================================

    // wallet.addr == vm.addr(key), so the f4 and f1 key pair are always in sync.
    function testF1_WalletAddrMatchesSignerAddr() public {
        VmSafe.Wallet memory wallet = vm.createWallet(SIGNER_KEY);
        assertEq(wallet.addr, SIGNER_ADDR);
    }

    function testF1_ValidSignature() public {
        uint64 f1ActorId = 5678;
        VmSafe.Wallet memory wallet = vm.createWallet(SIGNER_KEY);
        mockF1Account(f1ActorId, wallet);
        bytes memory message = "hello f1";
        (bool exists, int256 exitCode) =
            FVMAccount.tryAuthenticateMessage(f1ActorId, _sign(SIGNER_KEY, message), message);
        assertTrue(exists);
        assertEq(exitCode, EXIT_SUCCESS);
    }

    function testF1_WrongSigner() public {
        uint64 f1ActorId = 5678;
        VmSafe.Wallet memory wallet = vm.createWallet(SIGNER_KEY);
        mockF1Account(f1ActorId, wallet);
        bytes memory message = "hello f1";
        (bool exists, int256 exitCode) =
            FVMAccount.tryAuthenticateMessage(f1ActorId, _sign(OTHER_KEY, message), message);
        assertTrue(exists);
        assertEq(exitCode, int256(uint256(USR_ILLEGAL_ARGUMENT)));
    }

    function testF1_AddressPayload_Deterministic() public {
        VmSafe.Wallet memory wallet = vm.createWallet(SIGNER_KEY);
        bytes memory pubKey = abi.encodePacked(uint8(0x04), wallet.publicKeyX, wallet.publicKeyY);
        assertEq(pubKey.length, 65);
        bytes20 f1Payload = FVMBlake2b.hash20(pubKey);
        assertTrue(f1Payload != bytes20(0));
        assertEq(FVMBlake2b.hash20(pubKey), f1Payload);
    }
}
