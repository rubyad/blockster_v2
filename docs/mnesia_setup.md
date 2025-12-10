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
