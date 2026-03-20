// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.30;

import {CBOR_CODEC} from "../FVMCodec.sol";
import {USR_UNHANDLED_MESSAGE} from "../FVMErrors.sol";
import {SECTOR_CONTENT_CHANGED} from "../FVMMethod.sol";
import {
    FVMSectorContentChanged,
    SectorContentChangedParams,
    SectorContentChangedReturn
} from "../FVMSectorContentChanged.sol";

/// @notice Mock miner actor for testing FIP-0109 SectorContentChanged notifications
/// @dev Etch this contract's code at a miner's masked ID address (0xff + 11 zeros + actorId)
/// via MockFVMTest.mockMiner(actorId). When it calls handle_filecoin_method on the target,
/// msg.sender will be the masked ID address, passing the receiver's isMinerActor() check.
contract FVMMinerActor {
    /// @notice Fallback for unknown ABI selectors.
    /// @dev The real miner is a native actor: it returns USR_UNHANDLED_MESSAGE for InvokeContract
    ///      (the method the EVM CALL opcode uses) rather than reverting.
    fallback() external {
        bytes memory response = abi.encode(uint32(USR_UNHANDLED_MESSAGE), uint64(0), bytes(""));
        assembly ("memory-safe") {
            return(add(response, 0x20), mload(response))
        }
    }

    /// @notice Simulate the miner actor calling handle_filecoin_method on the target contract
    /// @param target The contract implementing handle_filecoin_method
    /// @param params The notification parameters
    /// @return ret The decoded return value from the target contract
    function callSectorContentChanged(address target, SectorContentChangedParams memory params)
        external
        returns (SectorContentChangedReturn memory ret)
    {
        bytes memory encoded = FVMSectorContentChanged.encodeParams(params);

        (bool success, bytes memory returnData) = target.call(
            abi.encodeWithSignature(
                "handle_filecoin_method(uint64,uint64,bytes)", SECTOR_CONTENT_CHANGED, CBOR_CODEC, encoded
            )
        );
        require(success, "FVMMinerActor: handle_filecoin_method reverted");

        (uint32 exitCode,, bytes memory retData) = abi.decode(returnData, (uint32, uint64, bytes));
        require(exitCode == 0, "FVMMinerActor: non-zero exit code");

        if (retData.length > 0) {
            ret = FVMSectorContentChanged.decodeReturn(retData);
        }
    }
}
