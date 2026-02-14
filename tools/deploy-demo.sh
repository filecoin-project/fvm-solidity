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

# Sanity check 
echo "Sanity-checking deployed bytecode..."

[ "$(cast code "$DEPLOYED_ADDRESS")" = "$(forge inspect "$CONTRACT" deployedBytecode)" ] || {
  echo "On-chain bytecode does not match local build"
  exit 1
}

for verifier in sourcify blockscout; do
  if [ "$verifier" = "blockscout" ]; then
    forge verify-contract \
      "$DEPLOYED_ADDRESS" \
      "$CONTRACT" \
      --verifier blockscout \
      --verifier-url https://filecoin-testnet.blockscout.com/api || \
      echo "Blockscout verification failed (continuing)"
  else
    forge verify-contract \
      "$DEPLOYED_ADDRESS" \
      "$CONTRACT" \
      --verifier "$verifier"
  fi
done


echo "Verification submitted for $DEPLOYED_ADDRESS"