# Mnesia Remote Access Guide

This guide explains how to query and modify Mnesia data on a running Blockster cluster from an external Elixir script.

## Why RPC?

When you run a new Elixir script (e.g., `elixir --sname script /tmp/query.exs`), that process:
- Starts a fresh BEAM VM
- Does NOT have Mnesia tables loaded
- Cannot directly access Mnesia data

The running nodes (node1, node2) have:
- Mnesia initialized with disc copies
- All tables loaded and synced
- Access to all data

**Solution**: Use Erlang's `:rpc` module to execute Mnesia operations on the running node.

## Basic Pattern

```elixir
# /tmp/query_mnesia.exs
# 1. Connect to the running cluster
Node.connect(:"node1@Adams-iMac-Pro")
:timer.sleep(2000)  # Wait for connection to establish

# 2. Execute Mnesia operations via RPC
result = :rpc.call(:"node1@Adams-iMac-Pro", :mnesia, :function_name, [args])

# 3. Process results
if is_list(result) do
  # Success - process data
else
  IO.puts("RPC error: #{inspect(result)}")
end
```

Run with: `elixir --sname query$RANDOM /tmp/query_mnesia.exs`

**Note**: Use `$RANDOM` in the node name to avoid conflicts if running multiple scripts.

## Common Operations

### Get Table Info

```elixir
# Table size (number of records)
:rpc.call(node, :mnesia, :table_info, [:table_name, :size])

# Table arity (number of fields per record)
:rpc.call(node, :mnesia, :table_info, [:table_name, :arity])

# All table info
:rpc.call(node, :mnesia, :table_info, [:table_name, :all])
```

### Read by Key

```elixir
# Returns list (empty if not found)
records = :rpc.call(node, :mnesia, :dirty_read, [:table_name, key])

case records do
  [record] -> IO.puts("Found: #{inspect(record)}")
  [] -> IO.puts("Not found")
end
```

### Match All Records

**CRITICAL**: The match pattern tuple size MUST exactly match the table arity!

```elixir
# First, check the table arity
arity = :rpc.call(node, :mnesia, :table_info, [:table_name, :arity])
IO.puts("Table has #{arity} fields")

# Then create pattern with correct number of wildcards
# For a table with 22 fields:
pattern = {:table_name, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}

records = :rpc.call(node, :mnesia, :dirty_match_object, [pattern])
```

**Wrong tuple size returns empty list with no error!** This is a common gotcha.

### Match with Specific Value

```elixir
# Match where field 7 (status) is :placed
# Pattern: {:table_name, :_, :_, :_, :_, :_, :_, :placed, :_, ...rest of wildcards...}
pattern = {:bux_booster_onchain_games, :_, :_, :_, :_, :_, :_, :placed, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}

placed_bets = :rpc.call(node, :mnesia, :dirty_match_object, [pattern])
```

### Write/Update Record

```elixir
# Read existing record
[record] = :rpc.call(node, :mnesia, :dirty_read, [:table_name, key])

# Modify a field (e.g., change status at index 7)
updated = put_elem(record, 7, :new_status)

# Write back
:rpc.call(node, :mnesia, :dirty_write, [updated])
```

### Delete Record

```elixir
:rpc.call(node, :mnesia, :dirty_delete, [:table_name, key])
```

### Iterate Keys

```elixir
# Get first key
first_key = :rpc.call(node, :mnesia, :dirty_first, [:table_name])

# Get next key
next_key = :rpc.call(node, :mnesia, :dirty_next, [:table_name, current_key])

# End of table indicated by :"$end_of_table"
```

## Real-World Examples

### Query All ROGUE Bets

```elixir
Node.connect(:"node1@Adams-iMac-Pro")
:timer.sleep(2000)

# Match pattern for 22-field table
games = :rpc.call(:"node1@Adams-iMac-Pro", :mnesia, :dirty_match_object,
  [{:bux_booster_onchain_games, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}])

# Filter to ROGUE bets (token is at index 9)
rogue_games = Enum.filter(games, fn g -> elem(g, 9) == "ROGUE" end)

IO.puts("Found #{length(rogue_games)} ROGUE games")

for game <- rogue_games do
  status = elem(game, 7)
  won = elem(game, 15)
  bet_amount = elem(game, 10)
  IO.puts("Status: #{status}, Won: #{won}, Amount: #{bet_amount}")
end
```

### Expire Stale Bets

```elixir
Node.connect(:"node1@Adams-iMac-Pro")
:timer.sleep(2000)

# Find :placed bets older than 1 hour
cutoff = System.system_time(:millisecond) - (60 * 60 * 1000)

games = :rpc.call(:"node1@Adams-iMac-Pro", :mnesia, :dirty_match_object,
  [{:bux_booster_onchain_games, :_, :_, :_, :_, :_, :_, :placed, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}])

stale = Enum.filter(games, fn g ->
  created_at = elem(g, 20)
  created_at != nil and created_at < cutoff
end)

IO.puts("Found #{length(stale)} stale bets to expire")

for game <- stale do
  # Change status from :placed to :expired
  updated = put_elem(game, 7, :expired)
  result = :rpc.call(:"node1@Adams-iMac-Pro", :mnesia, :dirty_write, [updated])
  IO.puts("Expired #{elem(game, 1)}: #{inspect(result)}")
end
```

### Count Games by Status

```elixir
Node.connect(:"node1@Adams-iMac-Pro")
:timer.sleep(2000)

games = :rpc.call(:"node1@Adams-iMac-Pro", :mnesia, :dirty_match_object,
  [{:bux_booster_onchain_games, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}])

by_status = Enum.group_by(games, fn g -> elem(g, 7) end)

IO.puts("Games by status:")
for {status, group} <- by_status do
  IO.puts("  #{inspect(status)}: #{length(group)}")
end
```

## bux_booster_onchain_games Table Schema

| Index | Field | Type | Description |
|-------|-------|------|-------------|
| 0 | :bux_booster_onchain_games | atom | Table name |
| 1 | game_id | string | UUID |
| 2 | user_id | integer | User ID |
| 3 | wallet_address | string | 0x-prefixed address |
| 4 | server_seed | string | 64-char hex |
| 5 | commitment_hash | string | 0x-prefixed hash |
| 6 | nonce | integer | Bet sequence number |
| 7 | status | atom | :pending \| :committed \| :placed \| :settled \| :expired |
| 8 | bet_id | string | On-chain bet ID |
| 9 | token | string | "BUX", "ROGUE", etc. |
| 10 | bet_amount | float | Amount wagered |
| 11 | difficulty | integer | -4 to 4 |
| 12 | predictions | list | [:heads, :tails, ...] |
| 13 | bytes | list | Result bytes [0-255, ...] |
| 14 | results | list | [:heads, :tails, ...] |
| 15 | won | boolean | Win/loss result |
| 16 | payout | float | Amount paid out |
| 17 | commitment_tx | string | TX hash |
| 18 | bet_tx | string | TX hash |
| 19 | settlement_tx | string | TX hash |
| 20 | created_at | integer | Unix timestamp (ms) |
| 21 | settled_at | integer | Unix timestamp (ms) |

## Troubleshooting

### Empty Results from Match

If `dirty_match_object` returns `[]` unexpectedly:
1. Check table arity: `:rpc.call(node, :mnesia, :table_info, [:table_name, :arity])`
2. Ensure your pattern has exactly that many elements
3. Verify the table has data: `:rpc.call(node, :mnesia, :table_info, [:table_name, :size])`

### RPC Returns {:badrpc, :nodedown}

1. Check node is running: `epmd -names`
2. Verify node name spelling (case-sensitive)
3. Increase sleep time after `Node.connect/1`

### Connection Fails

1. Ensure both nodes use same cookie (default in dev)
2. Check hostname matches: `hostname` command
3. Try connecting manually in iex first:
   ```elixir
   iex --sname test
   Node.connect(:"node1@Adams-iMac-Pro")
   Node.list()  # Should show connected nodes
   ```

## Production Access

For production on Fly.io, use `flyctl ssh console`:

```bash
flyctl ssh console -a blockster-v2 -C '/app/bin/blockster_v2 rpc "
  games = :mnesia.dirty_match_object({:bux_booster_onchain_games, :_, ...})
  length(games)
"'
```

Or start a remote IEx session:

```bash
flyctl ssh console -a blockster-v2 -C '/app/bin/blockster_v2 remote'
```
