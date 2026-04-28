# FVM Solidity

Solidity libraries for using the FVM precompiles

## Installation

### Forge

```sh
forge install filecoin-project/fvm-solidity
```

### Git

```sh
git submodule add https://github.com/filecoin-project/fvm-solidity lib/fvm-solidity
```

## Usage

### FVMPay

```solidity
import { FVMPay } from "fvm-solidity/FVMPay.sol";

contract BigBrain {
    using FVMPay for address;

    function payEfficiently(address recipient) external payable {
        recipient.pay(msg.value);
    }

    using FVMPay for uint256;

    function burnEfficiently() external payable {
        msg.value.burn();
    }
}
```

### FVMActor - ResolveAddress

Resolve Filecoin or EVM (f410 / masked ID) addresses to their on-chain actor ID.

```solidity
import { FVMActor } from "fvm-solidity/FVMActor.sol";

contract BigBrain {
    using FVMActor for bytes;
    using FVMActor for address;

    // Resolve a Filecoin byte address
    function resolveFilAddress(bytes calldata filAddress) external view returns (uint64 actorId) {
        return filAddress.getActorId(); // reverts with ActorNotFound if not found
    }

    // Safely attempt to resolve (no revert on missing actor)
    function tryResolveFilAddress(bytes calldata filAddress) external view returns (bool exists, uint64 actorId) {
        return filAddress.tryGetActorId();
    }

    // Resolve an EVM address (f410 delegated) or masked ID (0xff) address
    function resolveEvmAddress(address addr) external view returns (bool exists, uint64 actorId) {
        return addr.tryGetActorId();
    }
}
```

### FVMSector

```solidity
import {FVMSector, SectorStatus} from "fvm-solidity/FVMSector.sol";

contract BigBrainValidator {
    error SectorNotFaulty(uint64 sectorId);

    function sectorFaulty(uint64 minerId, uint64 sectorId, int64 deadline, int64 partition) external {
        require(
            FVMSector.validateSectorStatus(minerId, sectorId, SectorStatus.Faulty, deadline, partition),
            SectorNotFaulty(sectorId)
        );
    }
}
```

### FVMSectorContentChanged

```solidity
import {CalldataUtils, CalldataSlice} from "fvm-solidity/CalldataUtils.sol";
import {FVMAddress} from "fvm-solidity/FVMAddress.sol";
import {CBOR_CODEC} from "fvm-solidity/FVMCodec.sol";
import {SECTOR_CONTENT_CHANGED} from "fvm-solidity/FVMMethod.sol";
import {FVMMiner} from "fvm-solidity/FVMMiner.sol";
import {
    FVMSectorContentChanged,
    PieceChangeIter,
    SectorChangesHeader,
    SectorContentChangedReturn,
    SectorReturn
} from "fvm-solidity/FVMSectorContentChanged.sol";

contract BigBrainStorageService {
    using FVMAddress for address;
    using FVMMiner for uint64;
    using FVMSectorContentChanged for uint256;
    using CalldataUtils for CalldataSlice;

    error ForbiddenMethod(uint64 method);
    error NotMiner(uint64 provider);

    function handle_filecoin_method(uint64 method, uint64 /*codec*/, bytes calldata)
        public
        returns (uint32 exitCode, uint64 returnDataCodec, bytes memory returnData)
    {
        require(method == SECTOR_CONTENT_CHANGED, ForbiddenMethod(method));
        uint64 minerActor = msg.sender.safeActorId();
        require(minerActor.isMiner(), NotMiner(minerActor));

        uint256 numSectors;
        uint256 iter;
        (numSectors, iter) = FVMSectorContentChanged.readParamsHeader();

        SectorContentChangedReturn memory ret;
        ret.sectors = new SectorReturn[](numSectors);
        SectorChangesHeader memory header;
        PieceChangeIter memory piece;
        for (uint256 i = 0; i < numSectors; i++) {
            iter = iter.readSectorHeader(header);
            // header.sector uint64
            // header.minimumCommitmentEpoch int64
            FVMSectorContentChanged.initSectorReturn(ret.sectors[i], header.numPieces);
            for (uint256 j = 0; j < header.numPieces; j++) {
                iter = iter.readPiece(piece);
                // piece.digest bytes32
                // piece.paddedSize uint64

                // optionally, retrieve the payload:
                // piece.payload.load() // bytes memory
                // piece.payload.toAddress() // address
                // piece.payload.toUint64() // uint64
                // piece.payload.keccak() // bytes32
                FVMSectorContentChanged.accept(ret.sectors[i], j);
            }
        }
        return (0, CBOR_CODEC, FVMSectorContentChanged.encodeReturn(ret));
    }
}
```

### Testing

```solidity
import {MockFVMTest} from "fvm-solidity/mocks/MockFVMTest.sol";
import {FVMActor} from "fvm-solidity/FVMActor.sol";
import {FVMAddress} from "fvm-solidity/FVMAddress.sol";

// MockFVMTest is Test
contract BigBrainTest is MockFVMTest {
    using FVMAddress for uint64;
    using FVMActor for bytes;

    function setUp() public override {
        // Mock the FVM precompiles for forge test
        super.setUp();
        /* ... */
    }

    function test_resolveAddress() public {
        uint64 actorId = 1234;
        bytes memory filAddress = actorId.f0();
        ACTOR_PRECOMPILE.mockResolveAddress(filAddress, actorId);

        (bool exists, uint64 resolved) = filAddress.tryGetActorId();
        assertTrue(exists);
        assertEq(resolved, actorId);
    }
}
```

## Gas Profiling

These measurements were performed on the [Demo](./src/Demo.sol) contract with the [gas-profile](./tools/gas-profile.sh) script.
Note that gas costs [are roughly 444x higher in the FEVM](https://docs.filecoin.io/smart-contracts/filecoin-evm-runtime/difference-with-ethereum#gas-costs) compared to the EVM.

| Method | Demo.sol estimateGas |
| :----- | -------------------: |
| Soldity payable.send(uint256) | 5383103 |
| Solidity payable.transfer(uint256) | 5379173 |
| FVMPay address.pay(uint256) | 4856475 |
| FVMPay uint64.pay(uint256) | 4847666 |
| FVMPay uint256.burn() | 3561540 |

The `.gas-snapshot` reflects the EVM gas cost of running the tests with the mocks, and not the FEVM gas.

## Support

Additional FVM support can be found in the [filecoin-solidity library](https://github.com/filecoin-project/filecoin-solidity).

### Precompiles

| Supported | Name | Address |
| :-------: | :--- | :------ |
| ✅ | ResolveAddress | `0xfe00000000000000000000000000000000000001` |
| ❌ | LookupDelegatedAddress | `0xfe00000000000000000000000000000000000002` |
| ✅ | CallActorByAddress | `0xfe00000000000000000000000000000000000003` |
| ✅ | CallActorById | `0xfe00000000000000000000000000000000000005` |
| ✅ | GetBeaconRandomness | `0xfe00000000000000000000000000000000000006` |

### Methods

```sol
import {SEND} from "fvm-solidity/FVMMethod.sol";
```

| Actor | Supported | Name | Number |
| :---: | :-------: | :--- | :----- |
| Any | ✅ | Send | 0 |
| Many | ❌ | Constructor | 1 |
| Power | ✅ | MinerPower | 36284446 |
| Miner | ✅ | GetOwner | 3275365574 |
| Miner | ✅ | ValidateSectorStatus | 3092458564 |
