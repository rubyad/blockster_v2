#!/usr/bin/env elixir

# Verification script for BUX Booster bet
# Usage: elixir verify_bet.exs <bet_id> <server_seed>

[bet_id_arg, server_seed_arg] = System.argv()

bet_id = bet_id_arg
server_seed = String.trim_leading(server_seed_arg, "0x")

IO.puts("\n=== BUX Booster Bet Verification ===\n")
IO.puts("Bet ID: #{bet_id}")
IO.puts("Server Seed: 0x#{server_seed}")

# Connect to running node
Node.connect(:"node1@Adams-iMac-Pro")

# Get bet details from contract (you'll need to query the blockchain)
# For now, let's verify with the transaction data we know

# From the transaction logs:
# - Player: 0xB6B4cb36ce26D62fE02402EF43cB489183B2A137
# - Results: [1, 1, 1] (all tails)
# - Won: false
# - Payout: 0

IO.puts("\nOn-chain results: [1, 1, 1] (all tails)")
IO.puts("Won: false")
IO.puts("Payout: 0")

IO.puts("\n\nTo complete verification, we need:")
IO.puts("1. Your predictions (heads/tails for each flip)")
IO.puts("2. Bet amount")
IO.puts("3. Token used")
IO.puts("4. Difficulty level")
IO.puts("\nProvide these details to verify the game was fair.")
