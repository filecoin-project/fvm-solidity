#!/bin/bash

RPC_URL=https://api.calibration.node.glif.io/rpc/v1

# Demo.sol
ADDRESS=0x1Ff1ceFcf1739d1b6aD4B2Cd27FB970A3214d174

estimateGas() {
    curl -H "Content-Type: application/json" -X POST --data "{\"id\": 1, \"method\": \"eth_estimateGas\", \"params\": [{\"to\": \"$ADDRESS\", \"data\": \"$1\", \"value\": \"$2\"}, \"latest\"]}" $RPC_URL
}

call() {
    curl -H "Content-Type: application/json" -X POST --data "{\"id\": 1, \"method\": \"eth_call\", \"params\": [{\"to\": \"$ADDRESS\", \"data\": \"$1\", \"value\": \"$2\"}, \"latest\"]}" $RPC_URL
}

echo "send(address)"
estimateGas 0x3e58c58c0000000000000000000000004a6f6b9ff1fc974096f9063a45fd12bd5b928ad1 0x1

echo "transfer(address)"
estimateGas 0x1a6952300000000000000000000000004a6f6b9ff1fc974096f9063a45fd12bd5b928ad1 0x1

echo "pay(address)"
estimateGas 0x0c11dedd0000000000000000000000004a6f6b9ff1fc974096f9063a45fd12bd5b928ad1 0x1

echo "pay(uint64)"
estimateGas 0x68f165f0000000000000000000000000000000000000000000000000000000000002a9a2 0x1

echo "burn()"
estimateGas 0x44df8e70 0x1

echo "prev()"
estimateGas 0x479c9254 0x0

echo "curr()"
estimateGas 0x8103aa45 0x0

echo "next() (reverts)"
estimateGas 0x4c8fe526 0x0
