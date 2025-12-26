# Mnesia Database Setup for BlocksterV2

## Overview

BlocksterV2 uses Mnesia, Erlang's built-in distributed database, for storing user BUX points and other data that benefits from:
- **Fast in-memory access** with optional disk persistence
- **Distributed replication** across multiple nodes
- **Ordered sets** for efficient range queries (e.g., leaderboards)
- **Atomic transactions** without external database overhead

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Fly.io Production                         │
│  ┌─────────────────────┐       ┌─────────────────────────┐      │
│  │     Node 1          │       │      Node 2             │      │
│  │  blockster@node1    │◄─────►│   blockster@node2       │      │
│  │                     │  DNS  │                         │      │
│  │  ┌───────────────┐  │Cluster│  ┌───────────────┐      │      │
│  │  │    Mnesia     │  │       │  │    Mnesia     │      │      │
│  │  │  disc_copies  │◄─┼───────┼─►│  disc_copies  │      │      │
│  │  └───────────────┘  │       │  └───────────────┘      │      │
│  │         │           │       │         │               │      │
│  │  /data/mnesia/node1 │       │  /data/mnesia/node2     │      │
│  │  (persistent vol)   │       │  (persistent vol)       │      │
│  └─────────────────────┘       └─────────────────────────┘      │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### 1. MnesiaInitializer GenServer

**File:** `lib/blockster_v2/mnesia_initializer.ex`

This GenServer handles all Mnesia initialization on application startup:

```elixir
{BlocksterV2.MnesiaInitializer, []}
```

#### Initialization Flow

```
Application Start
       │
       ▼
┌──────────────────┐
│ Check node()     │
│ == :nonode@nohost│
└────────┬─────────┘
         │
    ┌────┴────┐
    │         │
    ▼         ▼
  Yes        No
    │         │
    ▼         ▼
┌────────┐  ┌─────────────────┐
│RAM-only│  │With Persistence │
│ tables │  │                 │
└────────┘  └────────┬────────┘
                     │
                     ▼
            ┌────────────────┐
            │ Create schema  │
            │ on this node   │
            └────────┬───────┘
                     │
                     ▼
            ┌────────────────┐
            │ Start Mnesia   │
            └────────┬───────┘
                     │
                     ▼
            ┌────────────────┐
            │ In production? │
            └────────┬───────┘
                     │
                ┌────┴────┐
                │         │
                ▼         ▼
              Yes        No
                │         │
                ▼         │
         ┌────────────┐   │
         │Connect to  │   │
         │cluster via │   │
         │libcluster  │   │
         └─────┬──────┘   │
               │          │
               ▼          │
         ┌────────────┐   │
         │Sync schema │   │
         │with other  │   │
         │nodes       │   │
         └─────┬──────┘   │
               │          │
               └────┬─────┘
                    │
                    ▼
            ┌────────────────┐
            │ Create tables  │
            │ (if not exist) │
            └────────┬───────┘
                     │
                     ▼
            ┌────────────────┐
            │ Wait for       │
            │ tables ready   │
            └────────────────┘
```

### 2. DNSCluster Integration

**File:** `lib/blockster_v2/application.ex`

The supervision tree order is critical:

```elixir
children = [
  BlocksterV2Web.Telemetry,
  BlocksterV2.Repo,
  # 1. DNSCluster connects nodes first
  {DNSCluster, query: Application.get_env(:blockster_v2, :dns_cluster_query) || :ignore},
  {Phoenix.PubSub, name: BlocksterV2.PubSub},
  # 2. MnesiaInitializer runs AFTER nodes are connected
  {BlocksterV2.MnesiaInitializer, []},
  # 3. Other services
  {BlocksterV2.TimeTracker, %{}},
  BlocksterV2Web.Endpoint
]
```

**Why this order matters:**
- DNSCluster uses DNS SRV records to discover other Fly.io nodes
- It connects to them using Erlang's distributed protocol
- MnesiaInitializer then sees these nodes via `Node.list()`
- It can sync Mnesia schema and data across all connected nodes

### 3. Configuration

**File:** `config/runtime.exs`

```elixir
# Mnesia directory configuration
mnesia_dir =
  if config_env() == :prod do
    # Production: Use Fly.io persistent volume with STATIC path
    # IMPORTANT: Use "blockster" not node() to persist data across deployments
    # (node() includes machine ID which changes on each deploy)
    "/data/mnesia/blockster"
  else
    # Development: Use project directory per node for multi-node testing
    node_name = node() |> Atom.to_string() |> String.split("@") |> List.first()
    Path.join(["priv", "mnesia", node_name])
  end

config :mnesia, dir: String.to_charlist(mnesia_dir)

# DNS cluster query for Fly.io
config :blockster_v2, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
```

## Table Schemas

All table definitions are centralized in `@tables` module attribute in `MnesiaInitializer`:

```elixir
# Access table definitions programmatically
BlocksterV2.MnesiaInitializer.tables()
BlocksterV2.MnesiaInitializer.table_names()
```

### user_bux_points

Tracks BUX points for users.

| Field | Type | Description |
|-------|------|-------------|
| user_id | any | Primary key |
| user_smart_wallet | string | User's smart wallet address |
| bux_balance | integer | Current BUX balance (indexed) |
| extra_field1-4 | any | Reserved for future use |
| created_at | DateTime | Creation timestamp |
| updated_at | DateTime | Last update (indexed) |

### post_bux_points

Tracks BUX rewards and deposits for posts.

| Field | Type | Description |
|-------|------|-------------|
| post_id | any | Primary key |
| reward | integer | BUX reward for reading |
| read_time | integer | Required read time in seconds |
| bux_balance | integer | Available BUX balance (indexed) |
| bux_deposited | integer | Total BUX deposited |
| extra_field1-4 | any | Reserved for future use |
| created_at | DateTime | Creation timestamp |
| updated_at | DateTime | Last update (indexed) |

**Why `ordered_set`?**
- Records are stored sorted by primary key
- Efficient for range queries
- Perfect for leaderboards: "Get top 100 users by bux_balance"

**Why `disc_copies`?**
- Data is kept in RAM for fast access
- Also written to disk for persistence
- Survives node restarts

## Running Locally

### Option 1: Multi-node Local Testing (Recommended)

This is the recommended way to test Mnesia locally as it mirrors production behavior.

**Terminal 1:**
```bash
elixir --sname node1 -S mix phx.server
```

**Terminal 2:**
```bash
PORT=4001 elixir --sname node2 -S mix phx.server
```

Then connect the nodes. In Terminal 2's IEx shell (or a third terminal):
```elixir
Node.connect(:node1@<your-hostname>)
```

Replace `<your-hostname>` with your machine's hostname (run `hostname` in terminal to find it).

This setup:
1. Runs two Phoenix servers on ports 4000 and 4001
2. Both use `disc_copies` for persistence
3. Data replicates between nodes automatically
4. You can test failover by stopping one node

### Option 2: Single Node with Persistence

```bash
elixir --sname blockster -S mix phx.server
```

This:
1. Starts Erlang in distributed mode with short name `blockster@hostname`
2. Creates schema in `priv/mnesia/dev/`
3. Creates tables with `disc_copies`
4. Data persists across restarts

### Option 3: RAM-only (no persistence)

```bash
mix phx.server
```

You'll see these warnings:
```
[warning] [MnesiaInitializer] Running without distributed Erlang. Mnesia will use ram_copies only.
[warning] [MnesiaInitializer] For persistent storage, start with: elixir --sname blockster -S mix phx.server
```

Data is lost when you stop the server. Use this only for quick testing when persistence doesn't matter.

## Production on Fly.io

### How It Works

1. **Fly.io assigns unique node names** to each machine (e.g., `blockster@fdaa:0:xxxx::2`)

2. **DNS_CLUSTER_QUERY** environment variable is set by Fly:
   ```
   DNS_CLUSTER_QUERY=blockster-v2.internal
   ```

3. **DNSCluster** queries this DNS and discovers all running instances

4. **Erlang connects nodes** automatically using the internal Fly network

5. **MnesiaInitializer** detects other nodes and:
   - Adds them as `extra_db_nodes`
   - Copies schema to local node
   - Creates tables with `disc_copies` on each node

### Fly.io Configuration

**fly.toml** should include:
```toml
[env]
  DNS_CLUSTER_QUERY = "blockster-v2.internal"

# Persistent volume for Mnesia data
[mounts]
  source = "mnesia_data"
  destination = "/data"
```

Create the volume:
```bash
fly volumes create mnesia_data --region ord --size 1
fly volumes create mnesia_data --region ord --size 1  # For second node
```

### Node Discovery Flow

```
┌──────────────────────────────────────────────────────────────┐
│                     Fly.io Internal DNS                       │
│                                                              │
│   blockster-v2.internal                                      │
│   ├── fdaa:0:xxxx::2  (Node 1)                              │
│   └── fdaa:0:xxxx::3  (Node 2)                              │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                        DNSCluster                            │
│                                                              │
│   1. Query DNS for "blockster-v2.internal"                   │
│   2. Get list of IP addresses                                │
│   3. Connect to each node via Node.connect/1                 │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                     MnesiaInitializer                        │
│                                                              │
│   1. Call Node.list() to get connected nodes                 │
│   2. Call :mnesia.change_config(:extra_db_nodes, nodes)      │
│   3. Schema syncs automatically                              │
│   4. Tables replicated to all nodes                          │
└──────────────────────────────────────────────────────────────┘
```

### Data Replication

With `disc_copies` on both nodes:

```
Write to Node 1
       │
       ▼
┌──────────────┐
│ Mnesia Node 1│───────────────────┐
│              │  Replicate write  │
│  disc_copies │                   │
└──────────────┘                   │
                                   ▼
                           ┌──────────────┐
                           │ Mnesia Node 2│
                           │              │
                           │  disc_copies │
                           └──────────────┘
```

Reads can happen from any node (local RAM access).
Writes are replicated to all nodes with copies.

## Working with the Table

### Insert/Update a Record

```elixir
:mnesia.transaction(fn ->
  now = DateTime.utc_now()
  :mnesia.write({:user_bux_points,
    user_id,           # Primary key
    "0x1234...",       # Smart wallet
    1000,              # BUX balance
    nil, nil, nil, nil, # Extra fields
    now,               # created_at
    now                # updated_at
  })
end)
```

### Read a Record

```elixir
:mnesia.transaction(fn ->
  :mnesia.read({:user_bux_points, user_id})
end)
```

### Get Top 10 by Balance (Leaderboard)

```elixir
:mnesia.transaction(fn ->
  # Use index on :bux_balance
  :mnesia.index_read(:user_bux_points, :bux_balance, :bux_balance)
  |> Enum.sort_by(fn {_, _, _, balance, _, _, _, _, _, _} -> balance end, :desc)
  |> Enum.take(10)
end)
```

### Dirty Reads (No Transaction, Faster)

```elixir
# Only use when consistency isn't critical
:mnesia.dirty_read({:user_bux_points, user_id})
```

## Troubleshooting

### "Mnesia not running" errors

Check if Mnesia started:
```elixir
:mnesia.system_info(:is_running)
# Should return :yes
```

### Tables not syncing between nodes

1. Check nodes are connected:
   ```elixir
   Node.list()
   ```

2. Check Mnesia sees the nodes:
   ```elixir
   :mnesia.system_info(:db_nodes)
   :mnesia.system_info(:running_db_nodes)
   ```

3. Force sync:
   ```elixir
   :mnesia.change_config(:extra_db_nodes, Node.list())
   ```

### Schema mismatch errors

If you get schema conflicts, you may need to:
```elixir
# On the node with wrong schema
:mnesia.stop()
:mnesia.delete_schema([node()])
# Then restart the app
```

### Check table info

```elixir
:mnesia.table_info(:user_bux_points, :all)
# Returns: type, disc_copies, ram_copies, size, memory, etc.
```

## Adding New Tables

1. Add a function in `MnesiaInitializer`:

```elixir
defp create_my_new_table do
  case :mnesia.create_table(:my_new_table,
    type: :set,
    disc_copies: [node()],
    attributes: [:id, :field1, :field2]
  ) do
    {:atomic, :ok} -> :ok
    {:aborted, {:already_exists, _}} -> :ok
    {:aborted, reason} -> Logger.error("Failed: #{inspect(reason)}")
  end
end
```

2. Call it from `create_tables/0`:

```elixir
defp create_tables do
  create_user_bux_points_table()
  create_my_new_table()  # Add here
end
```

3. Add to `wait_for_tables/0`:

```elixir
defp wait_for_tables do
  tables = [:user_bux_points, :my_new_table]  # Add here
  :mnesia.wait_for_tables(tables, 30_000)
end
```

4. If using RAM-only mode, also add to `create_ram_tables/0`.

## Performance Considerations

| Operation | Speed | Notes |
|-----------|-------|-------|
| dirty_read | ~1μs | No transaction overhead |
| transaction read | ~10μs | ACID guarantees |
| dirty_write | ~10μs | No replication wait |
| transaction write | ~100μs | Waits for replication |
| index lookup | ~10μs | Uses secondary index |

For high-throughput scenarios:
- Use `dirty_*` operations when eventual consistency is acceptable
- Batch writes in single transactions
- Consider `ram_copies` for frequently-changing, non-critical data

---

## Schema Migrations (CRITICAL FOR PRODUCTION)

### The Problem: Adding Fields to Existing Tables

When you add new fields to a Mnesia table schema, existing records in the database have the OLD number of fields. When your code tries to write records with the NEW number of fields, Mnesia throws a `{:bad_type, ...}` error because the tuple sizes don't match.

**Example scenario:**
```
OLD schema: {:bux_booster_games, game_id, user_id, token_type, ..., created_at}  # 12 fields
NEW schema: {:bux_booster_games, game_id, user_id, token_type, ..., created_at, server_seed, server_seed_hash, nonce}  # 15 fields

Error: {:aborted, {:bad_type, {:bux_booster_games, "game_123", ...}}}
```

### Automatic Migration System (Implemented)

The `MnesiaInitializer` module now includes automatic schema migration for **compatible changes** (adding fields at the end). Here's how it works:

#### Detection
When a table exists but has different attributes than expected:
```elixir
defp create_table(%{name: table_name, attributes: attributes, ...}, copy_type) do
  case table_exists?(table_name) do
    true ->
      existing_attrs = :mnesia.table_info(table_name, :attributes)
      if existing_attrs != attributes do
        # Trigger migration
        migrate_table_schema(table_name, existing_attrs, attributes)
      end
    # ...
  end
end
```

#### Migration Flow
```
┌──────────────────────────────────────────────────────────────┐
│                  Schema Mismatch Detected                     │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│                  Check Table Status                           │
│   - Has reachable copies? → Migrate directly                 │
│   - Has unreachable copies? → Force load, then migrate       │
│   - No copies (zombie)? → Recreate table                     │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│               Validate Migration Type                         │
│   - New fields at end only? → Safe migration                 │
│   - Fields removed? → Warning only (manual fix needed)       │
│   - Fields reordered? → Error (incompatible)                 │
└──────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌──────────────────────────────────────────────────────────────┐
│            Perform transform_table                            │
│   - Uses transform function to add nil values for new fields │
│   - Handles {:not_active, ...} by removing dead nodes        │
│   - Falls back to delete+recreate if transform fails         │
└──────────────────────────────────────────────────────────────┘
```

#### Table-Specific Defaults

For tables that need specific default values (not just `nil`), define them in `get_migration_defaults/2`:

```elixir
defp get_migration_defaults(:bux_booster_games, 3) do
  # Adding 3 fields: server_seed, server_seed_hash, nonce
  # All nil for old games (they weren't provably fair)
  [nil, nil, nil]
end

defp get_migration_defaults(_table_name, field_count) do
  # Default: add nil for each new field
  List.duplicate(nil, field_count)
end
```

### The Danger: Dead Nodes and Data Loss

**THIS IS THE CRITICAL ISSUE FOR PRODUCTION**

Mnesia is designed for distributed systems and has strong safeguards against split-brain scenarios. The problem: **Mnesia refuses to modify tables that have copies on offline nodes**.

#### What Can Go Wrong

1. **Rolling Deploy Scenario**:
   ```
   Before deploy: node1 and node2 both running with table copies
   During deploy: node1 stops, node2 still running
   Deploy fails: node2 can't modify table because node1 is "expected" but offline
   ```

2. **Node Name Change Scenario**:
   ```
   Before: node1@machine-abc has table copies
   After deploy: node1@machine-xyz (new machine ID)
   Result: "node1@machine-abc" is in schema but will never come back
   ```

3. **Schema Corruption Scenario**:
   ```
   Table exists in schema but has no active copies
   transform_table fails with {:no_exists, table_name}
   Cannot delete table: {:not_active, "All replicas on diskfull nodes are not active"}
   Result: STUCK - can't migrate, can't delete, can't recreate
   ```

#### The Nuclear Option (Last Resort)

When all else fails, the system falls back to **delete and recreate**:

```elixir
defp delete_and_recreate_table(table_name, _new_attrs) do
  # Find table definition
  table_def = Enum.find(@tables, fn t -> t.name == table_name end)

  # Try to delete (may fail due to dead nodes)
  case :mnesia.delete_table(table_name) do
    {:atomic, :ok} -> create_fresh_table(table_def)
    {:aborted, _} ->
      # Force remove from schema and recreate
      force_delete_table_from_schema(table_name)
      create_fresh_table(table_def)
  end
end
```

**⚠️ THIS LOSES ALL DATA IN THAT TABLE ⚠️**

---

## PRODUCTION SAFETY PROCEDURES

### Before Deploying Schema Changes

**Step 1: Backup Mnesia Data**

SSH into production and export critical data:

```bash
# Connect to production
flyctl ssh console -a blockster-v2

# In IEx, export data to JSON/CSV
iex> games = :mnesia.dirty_match_object({:bux_booster_games, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_})
iex> File.write!("/tmp/bux_booster_backup.json", Jason.encode!(games))

# Download the backup
flyctl ssh sftp get /tmp/bux_booster_backup.json ./backups/
```

Or create an export script that runs before deploy:

```elixir
# lib/blockster_v2/mnesia_backup.ex
defmodule BlocksterV2.MnesiaBackup do
  def export_table(table_name, path) do
    records = :mnesia.dirty_match_object({table_name, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_})
    data = Enum.map(records, &Tuple.to_list/1)
    File.write!(path, :erlang.term_to_binary(data))
  end

  def import_table(table_name, path) do
    data = File.read!(path) |> :erlang.binary_to_term()
    Enum.each(data, fn record_list ->
      :mnesia.dirty_write(List.to_tuple(record_list))
    end)
  end
end
```

**Step 2: Test Migration Locally**

1. Export production schema to local dev:
   ```bash
   # Copy production Mnesia files (or recreate structure)
   ```

2. Run with old schema, insert test data
3. Update code with new schema
4. Restart and verify migration succeeds
5. Verify old data has correct default values for new fields

**Step 3: Single-Node Deploy First**

```bash
# Scale to 1 node before deploying schema changes
flyctl scale count 1 -a blockster-v2

# Deploy
flyctl deploy -a blockster-v2

# Verify migration succeeded in logs
flyctl logs -a blockster-v2 | grep -i "mnesia\|migrat"

# Scale back up
flyctl scale count 2 -a blockster-v2
```

### Recovery Procedures

#### Scenario 1: Migration Failed, Data Still Exists

Check logs for the specific error:
```bash
flyctl logs -a blockster-v2 | grep -i "failed to migrate\|aborted"
```

If it's a `{:not_active, ...}` error with dead nodes:

```bash
# SSH into production
flyctl ssh console -a blockster-v2

# In IEx, check what nodes are in the schema
iex> :mnesia.table_info(:bux_booster_games, :disc_copies)
# Returns: [:"old_dead_node@machine-abc", :"current_node@machine-xyz"]

# Remove the dead node from all tables
iex> :mnesia.del_table_copy(:schema, :"old_dead_node@machine-abc")

# Restart the app to retry migration
```

#### Scenario 2: Table is Corrupted/Stuck

If the table is in a "zombie" state (exists in schema, no copies):

```bash
# SSH into production
flyctl ssh console -a blockster-v2

# In IEx, try to force load
iex> :mnesia.force_load_table(:bux_booster_games)

# If that fails, check if data exists on disk
iex> File.ls("/data/mnesia/blockster")
# Look for bux_booster_games.DCD file

# If DCD file exists, data might be recoverable
# If not, the table truly has no data
```

#### Scenario 3: Complete Data Loss Required

If migration is impossible and table must be recreated:

```bash
# 1. First, backup any recoverable data from .DCD files
# 2. Then in IEx:

iex> :mnesia.stop()
iex> :mnesia.delete_table(:bux_booster_games)  # May fail
iex> :mnesia.start()

# If delete fails, manually remove from schema:
iex> :mnesia.transaction(fn -> :mnesia.delete({:schema, :bux_booster_games}) end)

# Restart the application - it will create fresh table
```

#### Scenario 4: Restore From Backup

```elixir
# After table is recreated with new schema
iex> backup_data = File.read!("/path/to/backup.bin") |> :erlang.binary_to_term()
iex> Enum.each(backup_data, fn old_record ->
  # Transform old record to new format
  new_record = old_record ++ [nil, nil, nil]  # Add default values for new fields
  :mnesia.dirty_write(List.to_tuple([:bux_booster_games | new_record]))
end)
```

---

## Best Practices for Schema Changes

### DO:

1. **Only add fields at the END of the attribute list**
   ```elixir
   # Good: Adding to the end
   attributes: [:id, :name, :old_field, :new_field1, :new_field2]
   ```

2. **Always provide migration defaults**
   ```elixir
   defp get_migration_defaults(:my_table, 2) do
     [default_value_1, default_value_2]
   end
   ```

3. **Test migrations locally before production**

4. **Deploy schema changes to single node first**

5. **Have backups before ANY schema change**

6. **Use feature flags to deploy code before schema changes**
   ```elixir
   # First deploy: Code handles both old and new schema
   defp read_record(record) do
     if tuple_size(record) > 12 do
       # New schema with extra fields
     else
       # Old schema
     end
   end

   # Second deploy: Migration runs, all records have new schema
   ```

### DON'T:

1. **Never reorder existing fields**
   ```elixir
   # BAD: This breaks everything
   # Old: [:id, :name, :balance]
   # New: [:id, :balance, :name]  # WRONG!
   ```

2. **Never remove fields without manual migration**
   ```elixir
   # BAD: Removing fields
   # Old: [:id, :name, :old_unused_field, :balance]
   # New: [:id, :name, :balance]  # Data loss!
   ```

3. **Never rename fields**
   ```elixir
   # BAD: This is equivalent to remove + add
   # Old: [:id, :user_balance]
   # New: [:id, :bux_balance]  # Looks like new field!
   ```

4. **Never change field types without transform function**

5. **Never deploy schema changes during high traffic**

---

## Monitoring Mnesia Health

### Log Patterns to Watch

```bash
# Successful migration
[info] [MnesiaInitializer] Migrating bux_booster_games: adding fields [:server_seed, :server_seed_hash, :nonce]
[info] [MnesiaInitializer] Successfully migrated bux_booster_games from 12 to 15 fields

# Warning signs
[warning] [MnesiaInitializer] Table bux_booster_games exists with different schema
[warning] [MnesiaInitializer] Table bux_booster_games timed out, attempting force load
[warning] [MnesiaInitializer] Inactive nodes for bux_booster_games: [:"dead_node@machine"]

# Critical errors
[error] [MnesiaInitializer] Failed to migrate bux_booster_games: {:not_active, ...}
[error] [MnesiaInitializer] Retry failed for bux_booster_games
[warning] [MnesiaInitializer] Falling back to recreate table  # DATA LOSS INCOMING
```

### Health Check Query

```elixir
def mnesia_health do
  %{
    running: :mnesia.system_info(:is_running),
    db_nodes: :mnesia.system_info(:db_nodes),
    running_db_nodes: :mnesia.system_info(:running_db_nodes),
    tables: :mnesia.system_info(:tables),
    local_tables: :mnesia.system_info(:local_tables)
  }
end
```

### Alerting Recommendations

Set up alerts for:
1. `[error] [MnesiaInitializer] Failed to migrate` - Immediate investigation needed
2. `Falling back to recreate table` - Data loss occurred
3. Mnesia not running after deploy
4. Table size suddenly drops to 0

---

## Quick Reference: Schema Change Deployment Checklist

```
□ BEFORE DEPLOY
  □ Backup all Mnesia tables (especially the one being changed)
  □ Test migration locally with realistic data
  □ Verify new fields are added at END of attributes list
  □ Add get_migration_defaults/2 clause for the table
  □ Code handles both old and new record formats

□ DEPLOY PROCEDURE
  □ Scale to single node: flyctl scale count 1
  □ Deploy: flyctl deploy
  □ Check logs for migration success: flyctl logs | grep -i migrat
  □ Verify table has data: flyctl ssh console, then :mnesia.table_info(:table, :size)
  □ Scale back up: flyctl scale count 2

□ IF MIGRATION FAILS
  □ Check error type in logs
  □ If {:not_active, ...}: Remove dead nodes from schema
  □ If {:no_exists, ...}: Force load table, retry
  □ If all else fails: Restore from backup

□ POST-DEPLOY
  □ Monitor for {:bad_type, ...} errors (schema mismatch)
  □ Verify old records have correct default values
  □ Check table replication across nodes
```

---

## Files Modified for Schema Migration System

The automatic migration system was added in these locations:

### lib/blockster_v2/mnesia_initializer.ex

Key functions added:
- `migrate_table_schema/3` - Entry point for migration
- `do_migrate_table_schema/3` - Performs the actual transform_table
- `ensure_table_loaded/1` - Force loads tables before migration
- `remove_inactive_node_copies/2` - Removes dead node references
- `remove_dead_node_from_schema/1` - Cleans up completely dead nodes
- `delete_and_recreate_table/2` - Nuclear option when migration fails
- `create_fresh_table/1` - Creates table with new schema
- `get_migration_defaults/2` - Table-specific default values
- `build_transform_function/3` - Creates the tuple transformation function

### Migration System Limitations

1. **Only supports adding fields at the end** - Cannot reorder or remove fields
2. **Cannot migrate during rolling deploy** - All nodes must be stopped or running
3. **Dead nodes block migration** - Must manually remove dead nodes from schema
4. **Falls back to data loss** - If all migration attempts fail, table is recreated empty
5. **No automatic backups** - Must manually backup before schema changes
