#!/bin/bash

export ETH_RPC_URL=https://api.calibration.node.glif.io/rpc/v1
forge create --private-key $PRIVATE_KEY --broadcast src/Demo.sol:Demo
