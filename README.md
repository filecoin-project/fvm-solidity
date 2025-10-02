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

### Testing
```solidity
import {BURN_ADDRESS} from "fvm-solidity/FVMActors.sol";
import {MockFVMTest} from "fvm-solidity/mocks/MockFVMTest.sol";

// MockFVMTest is Test
contract BigBrainTest is MockFVMTest {
    function setUp() public override {
        // Mock the FVM precompiles for forge test
        super.setUp();
        /* ... */
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
| ❌ | ResolveAddress | `0xfe00000000000000000000000000000000000001` |
| ❌ | LookupDelegatedAddress | `0xfe00000000000000000000000000000000000002` |
| ✅ | CallActorByAddress | `0xfe00000000000000000000000000000000000003` |
| ❌ | GetActorType | `0xfe00000000000000000000000000000000000004` |
| ✅ | CallActorById | `0xfe00000000000000000000000000000000000005` |
| ✅ | GetBeaconRandomness | `0xfe00000000000000000000000000000000000006` |

### Methods

| Supported | Name | Number |
| :-------: | :--- | :----- |
| ✅ | Send | 0 |
| ❌ | Constructor | 1 |
