#!/bin/bash

RPC_URL=https://api.calibration.node.glif.io/rpc/v1
forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast src/Demo.sol:Demo
