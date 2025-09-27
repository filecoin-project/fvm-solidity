#!/bin/bash

RPC_URL=https://api.calibration.node.glif.io/rpc/v1

# Demo.sol
ADDRESS=0x91A9f1b2Aa333936A15B1F9D399C3c3b8647De6e

estimateGas() {
    curl -H "Content-Type: application/json" -X POST --data "{\"id\": 1, \"method\": \"eth_estimateGas\", \"params\": [{\"to\": \"$ADDRESS\", \"data\": \"$1\", \"value\": \"0x1\"}, \"latest\"]}" $RPC_URL
}

echo "send(address)"
estimateGas 0x3e58c58c0000000000000000000000004a6f6b9ff1fc974096f9063a45fd12bd5b928ad1

echo "transfer(address)"
estimateGas 0x1a6952300000000000000000000000004a6f6b9ff1fc974096f9063a45fd12bd5b928ad1

echo "pay(address)"
estimateGas 0x0c11dedd0000000000000000000000004a6f6b9ff1fc974096f9063a45fd12bd5b928ad1

echo "pay(uint64)"
estimateGas 0x68f165f0000000000000000000000000000000000000000000000000000000000002a9a2

echo "burn()"
estimateGas 0x44df8e70
