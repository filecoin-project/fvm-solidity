#!/bin/bash
set -euo pipefail

# Load environment variables from .env if it exists
if [ -f .env ]; then
  set -a          # auto-export
  source .env
  set +a
fi

: "${PRIVATE_KEY:?PRIVATE_KEY not set}"
: "${ETH_RPC_URL:?ETH_RPC_URL not set}"
: "${CHAIN_ID:?CHAIN_ID not set}"

CONTRACT="src/Demo.sol:Demo"

echo "Deploying $CONTRACT ..."

OUTPUT=$(forge create \
  --private-key "$PRIVATE_KEY" \
  --broadcast \
  "$CONTRACT"
)

echo "$OUTPUT"

# Extract deployed address
DEPLOYED_ADDRESS=$(echo "$OUTPUT" | awk '/Deployed to:/ { print $3 }')

if [ -z "$DEPLOYED_ADDRESS" ]; then
  echo "Failed to extract deployed address"
  exit 1
fi

echo "Deployed at: $DEPLOYED_ADDRESS"
echo "Verifying on Sourcify (chain $CHAIN_ID)..."

# Verify on Sourcify
forge verify-contract \
  "$DEPLOYED_ADDRESS" \
  "$CONTRACT" \
  --chain-id "$CHAIN_ID" \
  --verifier sourcify

echo "Verification submitted for $DEPLOYED_ADDRESS"