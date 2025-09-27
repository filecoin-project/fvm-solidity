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
}
```

## Gas Profiling
Note that gas costs [are roughly 444x higher in the FEVM](https://docs.filecoin.io/smart-contracts/filecoin-evm-runtime/difference-with-ethereum#gas-costs) compared to the EVM.

| Method | Demo.sol estimateGas |
| :----- | -------------------: |
| Soldity payable.send(uint256) | 5383103 |
| Solidity payable.transfer(uint256) | 5379173 |
| FVMPay address.pay(uint256) | 4856475 |
| FVMPay uint64.pay(uint256) | 4847666 |
| FVMPay uint256.burn() | 3561540 |
