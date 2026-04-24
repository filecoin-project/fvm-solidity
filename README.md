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

### FVMActor - LookupDelegatedAddress
Look up the delegated (f4 / f410) address associated with an actor ID on the FEVM.

```solidity
import {FVMActor} from "fvm-solidity/FVMActor.sol";

contract BigBrain {
    using FVMActor for uint64;

    // Try lookup without reverting (EVM address)
    function tryLookup(uint64 actorId) external view returns (bool exists, address addr) {
        return actorId.tryLookupDelegatedAddress();
    }

    // Strict lookup (reverts if not found)
    function lookup(uint64 actorId) external view returns (address) {
        return actorId.lookupDelegatedAddress();
    }

    // Raw f4 / f410 encoded address bytes
    function tryLookupBytes(uint64 actorId) external view returns (bool exists, bytes memory delegated) {
        return actorId.tryLookupDelegatedAddressBytes();
    }

    function lookupBytes(uint64 actorId) external view returns (bytes memory delegated) {
        return actorId.lookupDelegatedAddressBytes();
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
    using FVMActor for uint64;

    function setUp() public override {
        // Mock the FVM precompiles for forge test
        super.setUp();
        /* ... */
    }

    function test_resolveAddress() public {
        uint64 actorId = 1234;
        bytes memory filAddress = actorId.f0();
        RESOLVE_ADDRESS_PRECOMPILE.mockResolveAddress(filAddress, actorId);

        (bool exists, uint64 resolved) = filAddress.tryGetActorId();
        assertTrue(exists);
        assertEq(resolved, actorId);
    }

    function test_lookupDelegatedAddress() public {
        uint64 actorId = 1234;
        address ethAddr = address(0x1234567890123456789012345678901234567890);
        LOOKUP_DELEGATED_ADDRESS_PRECOMPILE.mockLookupDelegatedAddress(actorId, ethAddr);

        (bool exists, address addr) = actorId.tryLookupDelegatedAddress();
        assertTrue(exists);
        assertEq(addr, ethAddr);
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

## Support

Additional FVM support can be found in the [filecoin-solidity library](https://github.com/filecoin-project/filecoin-solidity).

### Precompiles

| Supported | Name | Address |
| :-------: | :--- | :------ |
| ✅ | ResolveAddress | `0xfe00000000000000000000000000000000000001` |
| ✅ | LookupDelegatedAddress | `0xfe00000000000000000000000000000000000002` |
| ✅ | CallActorByAddress | `0xfe00000000000000000000000000000000000003` |
| ✅ | CallActorById | `0xfe00000000000000000000000000000000000005` |
| ✅ | GetBeaconRandomness | `0xfe00000000000000000000000000000000000006` |

### Methods

| Supported | Name | Number |
| :-------: | :--- | :----- |
| ✅ | Send | 0 |
| ❌ | Constructor | 1 |

### Demo Deployment

You can deploy the demo contract using the helper script:

```sh
./tools/deploy-demo.sh
```
