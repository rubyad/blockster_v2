#!/bin/bash
set -ex  # Enable verbose mode to see exactly what's happening

echo "=== Starting Rundler v0.9.2 Deployment ==="
echo "Rundler version:"
rundler --version || echo "Warning: Could not get rundler version"

# Start Caddy in the background (will proxy port 3000 to Rundler on 3001 with CORS headers)
caddy run --config /app/Caddyfile &
CADDY_PID=$!
echo "Started Caddy with PID: $CADDY_PID"

# Give Caddy a moment to start
sleep 2

# Check if BUILDER_PRIVATE_KEY is set
if [ -z "$BUILDER_PRIVATE_KEY" ]; then
  echo "ERROR: BUILDER_PRIVATE_KEY environment variable is not set!"
  exit 1
fi

# MAINNET BUNDLER CONFIGURATION
# This bundler is for Rogue mainnet (Chain ID: 560013)
echo "=== ROGUE MAINNET BUNDLER ==="
NODE_RPC="https://rpc.roguechain.io/rpc"
CHAIN_SPEC="/app/chain-spec-mainnet.json"

echo "Chain: Rogue Mainnet (560013)"
echo "Node RPC: $NODE_RPC"
echo "Chain Spec: $CHAIN_SPEC"

# Start Rundler on port 3001 (Caddy will proxy from 3000)
# Disable v0.7 entry point since we only have one private key and only need v0.6
# Enable trace logging to see simulation failures
# Increase mempool limits for unstaked entities to allow testing
export RUST_LOG=rundler_pool=trace,rundler_sim=trace,rundler_builder=trace,debug
echo "=== Launching Rundler ==="
echo "RUST_LOG=$RUST_LOG"

exec rundler node \
  --node_http "$NODE_RPC" \
  --chain_spec "$CHAIN_SPEC" \
  --signer.private_keys "$BUILDER_PRIVATE_KEY" \
  --rpc.port 3001 \
  --rpc.host "0.0.0.0" \
  --disable_entry_point_v0_7 \
  --pool.same_sender_mempool_count 100 \
  --pool.throttled_entity_mempool_count 100 \
  --pool.throttled_entity_live_blocks 100 \
  --builder.max_bundle_size 1 \
  --unsafe
