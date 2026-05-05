# Mnesia Disaster Recovery — Snapshot-Based Restore

> **Read this BEFORE running the split-brain recovery from Claude's memory** (`project_mnesia_split_brain_open.md`). That runbook has a documented blindspot that will silently destroy data in some configurations. This doc explains the blindspot and how to recover from it if it has already destroyed data.

---

## Contents

1. [The blindspot — what the split-brain runbook destroys silently](#1-the-blindspot--what-the-split-brain-runbook-destroys-silently)
2. [Pre-recovery check — must run before the split-brain runbook](#2-pre-recovery-check--must-run-before-the-split-brain-runbook)
3. [Snapshot-based recovery — used 2026-05-04](#3-snapshot-based-recovery--used-2026-05-04)
4. [Permanent fix path](#4-permanent-fix-path)

---

## 1. The blindspot — what the split-brain runbook destroys silently

The runbook in `project_mnesia_split_brain_open.md` does:

```elixir
ghost = :"blockster-v2@<old_ip>"
other = :"blockster-v2@<live_peer_ip>"
self_node = node()

:mnesia.del_table_copy(:schema, ghost)

# Drop every local copy on the recovered node:
for t <- :mnesia.system_info(:tables) |> Enum.reject(& &1 == :schema),
    self_node in :mnesia.table_info(t, :disc_copies) do
  :mnesia.delete_table(t)
end

:mnesia.change_config(:extra_db_nodes, [other])
```

**The trap:** for any table whose `disc_copies` list is `[ghost, self_node]` (no copy on `other`), the recovery wipes the table from the cluster:

1. `del_table_copy(:schema, ghost)` removes the ghost as a holder.
2. `delete_table(t)` removes the local copy on `self_node`.
3. The table now has zero replicas → gone from the schema entirely.
4. After the next deploy, `MnesiaInitializer.create_table/2` recreates it **empty**, losing all historical rows.

This is **not** what the runbook documents. Memory says reads "work via remote (~2ms vs 50µs local)" — that assumes `other` holds a replica. For tables where it doesn't, the recovery is catastrophic.

**Tables affected during the 2026-05-04 incident** (had `disc_copies = [ghost, c889]`, no `e770` replica):

- `:coin_flip_games` — bet history (425 rows lost)
- `:lp_price_history` — chart points (11,973 rows lost)
- `:pool_activities` — deposit/withdraw log (30 rows lost)
- `:user_pool_positions` — cost basis (13 rows lost)
- `:unified_multipliers_v2` — multiplier records (47 rows lost on top of 1008 preserved on `other`)
- `:user_solana_balances` — balance cache (540 rows lost)
- `:widget_rt_chart_cache`, `:widget_selections`, `:widget_rt_bots_cache`, `:widget_fs_feed_cache` — widget caches

User-facing impact: `/pool/sol` and `/pool/bux` showed all zeros; activity tabs were blank; charts were flat.

---

## 2. Pre-recovery check — must run before the split-brain runbook

**Before running the split-brain recovery, list every table the recovery will touch and confirm `other` holds a replica.** Skip this step at your peril.

```elixir
# Run on the broken machine (the one in split-brain) BEFORE running recovery:

self_node = node()
other = :"blockster-v2@fdaa:0:9cc8:a7b:e770:82b0:7db3:2"

at_risk =
  for t <- :mnesia.system_info(:tables) |> Enum.reject(& &1 == :schema),
      self_node in :mnesia.table_info(t, :disc_copies),
      not (other in :mnesia.table_info(t, :disc_copies)) do
    {t, :mnesia.table_info(t, :disc_copies)}
  end

if at_risk == [] do
  IO.puts("Safe to run recovery — every local copy is replicated on `other`.")
else
  IO.puts("DO NOT RUN RECOVERY — these tables would be destroyed:")
  Enum.each(at_risk, fn {t, copies} -> IO.puts("  #{t}  disc_copies=#{inspect(copies)}") end)
end
```

**If `at_risk` is non-empty:** before running the runbook, add a copy of each at-risk table on `other`:

```elixir
# Run on the broken machine, BEFORE :mnesia.del_table_copy(:schema, ghost):
for {t, _} <- at_risk do
  case :mnesia.add_table_copy(t, other, :disc_copies) do
    {:atomic, :ok} -> IO.puts("added copy of #{t} on `other`")
    err -> IO.puts("FAILED to add copy of #{t}: #{inspect(err)}  STOP — investigate")
  end
end
```

After every `add_table_copy` succeeds, the standard runbook is safe to run.

If `add_table_copy` fails on any table, **do not proceed**. The table is already in a state where the runbook will destroy it. Fall through to [§3 Snapshot-based recovery](#3-snapshot-based-recovery--used-2026-05-04) preemptively — fork a snapshot, save the data, then run the runbook.

---

## 3. Snapshot-based recovery — used 2026-05-04

If the split-brain runbook has already destroyed tables (symptom: pool stats are all zero, activity tabs are blank, charts are flat), restore from a Fly volume snapshot. **This whole procedure is read-only on the live cluster until the very last merge step.**

### Prerequisites

- The lost tables had `disc_copies` on the broken machine (e.g. `c889` in 2026-05-04). That machine's volume has a Fly auto-snapshot from before the recovery.
- Fly retains snapshots for 5 days by default.

### Step 1 — Find a snapshot from before the recovery

```bash
flyctl volumes list --app blockster-v2
# Find the volume attached to the broken machine (e.g. machine 865d14f7225508)

flyctl volumes snapshots list <broken_machine_volume_id> --app blockster-v2
# Pick the most recent snapshot whose timestamp predates the recovery action.
# Note its snapshot ID (e.g. vs_D7VYVoe82KBf9z0PBVNklZG).
```

### Step 2 — Fork the snapshot to a new volume

```bash
flyctl volumes create mnesia_recovery \
  --snapshot-id vs_<snapshot_id> \
  --app blockster-v2 \
  --region ord \
  --size 1 \
  --yes
# Note the new volume ID returned (e.g. vol_4y856ow9el9m8m1r).
```

### Step 3 — Boot a temp machine with the forked volume + `sleep infinity`

The `--override-cmd "sleep infinity"` is **critical**. It prevents the app from booting, which prevents libcluster/DNSCluster from joining. The temp machine sits in the app's namespace but is operationally inert — no risk of any cluster interaction.

```bash
flyctl machine clone <any_existing_machine_id> \
  --app blockster-v2 \
  --attach-volume <forked_volume_id>:/data \
  --override-cmd "sleep infinity" \
  --name mnesia-recovery-temp \
  --region ord
# Note the new machine ID returned (e.g. e2862614c91638).
```

### Step 4 — Verify Mnesia loads standalone on the temp machine

```bash
flyctl ssh console --app blockster-v2 --machine <temp_machine_id> \
  -C "/app/bin/blockster_v2 eval ':mnesia.start() |> IO.inspect(label: :start); :mnesia.system_info(:running_db_nodes) |> IO.inspect(label: :running)'"
```

Expected:
- `start: :ok`
- `running: [:nonode@nohost]` ← single-node, no distribution. Safe.

If `running` shows anything other than `[:nonode@nohost]`, **stop**. The temp machine is somehow connected — destroy it and restart with a different override-cmd or different node-name override.

### Step 5 — Read the lost tables directly from `.DCD`/`.DCL` via `:disk_log`

The snapshot's schema may or may not reference the lost tables (depends on which point-in-time the snapshot was taken). The data files (`.DCD`/`.DCL`) exist on disk regardless — read them directly with `:disk_log`, bypassing Mnesia's schema.

DCD entries are raw record tuples. DCL entries are wrapped: `{{table, key}, record, :write}` for inserts, `{{table, key}, record, :delete_object}` / `{{table, key}, _, :delete}` for deletes.

```bash
flyctl ssh console --app blockster-v2 --machine <temp_machine_id> \
  -C "/app/bin/blockster_v2 eval '
defmodule Dump do
  def read_log(file) do
    case :disk_log.open(name: :tmp_log, file: String.to_charlist(file), repair: true, mode: :read_only) do
      {:ok, _} ->
        ets = :ets.new(:rec, [:set])
        read_all(:start, ets)
        :disk_log.close(:tmp_log)
        list = :ets.tab2list(ets) |> Enum.map(fn {_k, r} -> r end) |> Enum.reject(&is_nil/1)
        :ets.delete(ets)
        {:ok, list}
      err -> err
    end
  end

  defp read_all(cont, ets) do
    case :disk_log.chunk(:tmp_log, cont) do
      :eof -> :ok
      {next, terms} ->
        Enum.each(terms, fn term -> handle(term, ets) end)
        read_all(next, ets)
      _ -> :ok
    end
  end

  defp handle({:log_header, _, _, _, _, _}, _ets), do: :ok
  defp handle({{_table, key}, record, :write}, ets) when is_tuple(record), do: :ets.insert(ets, {key, record})
  defp handle({{_table, key}, _record, :delete_object}, ets), do: :ets.insert(ets, {key, nil})
  defp handle({{_table, key}, _record, :delete}, ets), do: :ets.insert(ets, {key, nil})
  defp handle(record, ets) when is_tuple(record) and tuple_size(record) >= 2 do
    :ets.insert(ets, {elem(record, 1), record})
  end
  defp handle(_, _), do: :ok

  def merge_dcd_dcl(table_name) do
    base = \"/data/mnesia/blockster/\" <> Atom.to_string(table_name)
    dcd = case File.exists?(base <> \".DCD\") do
      true -> case read_log(base <> \".DCD\") do
        {:ok, r} -> r
        _ -> []
      end
      _ -> []
    end
    dcl = case File.exists?(base <> \".DCL\") do
      true -> case read_log(base <> \".DCL\") do
        {:ok, r} -> r
        _ -> []
      end
      _ -> []
    end
    merged_ets = :ets.new(:m, [:set])
    Enum.each(dcd ++ dcl, fn r -> :ets.insert(merged_ets, {elem(r, 1), r}) end)
    list = :ets.tab2list(merged_ets) |> Enum.map(fn {_, r} -> r end)
    :ets.delete(merged_ets)
    list
  end
end

tables = [:coin_flip_games, :pool_activities, :user_pool_positions, :lp_price_history, :unified_multipliers_v2, :user_solana_balances, :widget_rt_chart_cache, :widget_selections, :widget_rt_bots_cache, :widget_fs_feed_cache]
results = for t <- tables do
  recs = Dump.merge_dcd_dcl(t)
  IO.puts(to_string(t) <> \"  rows=\" <> to_string(length(recs)))
  {t, recs}
end

bin = :erlang.term_to_binary(Map.new(results), [:compressed])
File.write!(\"/tmp/snapshot_dump.bin\", bin)
IO.puts(\"wrote /tmp/snapshot_dump.bin  bytes=\" <> to_string(byte_size(bin)))
'"
```

Expected output: each table prints a row count. The full dump is written to `/tmp/snapshot_dump.bin` on the temp machine. Tweak the `tables = [...]` list to include only the tables you've identified as lost.

### Step 6 — Download to local disk + upload to a live machine

```bash
# Download from temp machine to your laptop
flyctl ssh sftp shell --app blockster-v2 --machine <temp_machine_id> <<EOF
get /tmp/snapshot_dump.bin /Users/<you>/snapshot_dump.bin
EOF

# Upload to a live machine (pick the healthy one — e770 in the 2026-05-04 incident)
flyctl ssh sftp shell --app blockster-v2 --machine <live_machine_id> <<EOF
put /Users/<you>/snapshot_dump.bin /tmp/snapshot_dump.bin
EOF
```

### Step 7 — Dry-run the merge (no writes)

```bash
flyctl ssh console --app blockster-v2 --machine <live_machine_id> -C "/app/bin/blockster_v2 rpc '
data = File.read!(\"/tmp/snapshot_dump.bin\") |> :erlang.binary_to_term()

for {table, recs} <- data do
  live_arity = case :mnesia.system_info(:tables) |> Enum.member?(table) do
    true -> length(:mnesia.table_info(table, :attributes)) + 1
    false -> :missing_table
  end

  {would_insert, would_skip, arity_mismatch} = Enum.reduce(recs, {0, 0, 0}, fn record, {i, s, m} ->
    cond do
      live_arity == :missing_table -> {i, s, m + 1}
      tuple_size(record) != live_arity -> {i, s, m + 1}
      true ->
        case :mnesia.dirty_read({table, elem(record, 1)}) do
          [] -> {i + 1, s, m}
          _ -> {i, s + 1, m}
        end
    end
  end)

  IO.puts(to_string(table) <> \"  would_insert=\" <> to_string(would_insert) <> \"  already_present=\" <> to_string(would_skip) <> \"  arity_mismatch=\" <> to_string(arity_mismatch) <> \"  /  total=\" <> to_string(length(recs)))
end
'"
```

**Read the output carefully:**
- `arity_mismatch` should be **0**. If it's non-zero, the snapshot's record shape differs from the live schema — either the snapshot is too old (schema migrated) or the parser missed a DCL operation. **Do not proceed**; investigate first. (In the 2026-05-04 incident, an early version of the parser had this bug — fixed by handling DCL `{{table, key}, record, :write}` wrapper format. See `Dump.handle/2` clauses above.)
- `already_present` is fine — those rows have post-recovery activity that wins.
- `would_insert` is what gets written.

### Step 8 — Run the actual merge (no-clobber)

Same script as the dry-run but with `:mnesia.dirty_write(record)` after the empty `dirty_read`. The merge **never overwrites** an existing live row.

```bash
flyctl ssh console --app blockster-v2 --machine <live_machine_id> -C "/app/bin/blockster_v2 rpc '
data = File.read!(\"/tmp/snapshot_dump.bin\") |> :erlang.binary_to_term()

for {table, recs} <- data, length(recs) > 0 do
  live_arity = length(:mnesia.table_info(table, :attributes)) + 1

  {ins, skp, err} = Enum.reduce(recs, {0, 0, 0}, fn record, {i, s, e} ->
    cond do
      tuple_size(record) != live_arity -> {i, s, e + 1}
      true ->
        case :mnesia.dirty_read({table, elem(record, 1)}) do
          [] ->
            try do
              :mnesia.dirty_write(record)
              {i + 1, s, e}
            rescue
              _ -> {i, s, e + 1}
            catch
              :exit, _ -> {i, s, e + 1}
            end
          _ -> {i, s + 1, e}
        end
    end
  end)
  IO.puts(to_string(table) <> \"  inserted=\" <> to_string(ins) <> \"  skipped=\" <> to_string(skp) <> \"  errors=\" <> to_string(err))
end
'"
```

The numbers should match the dry-run exactly. `errors` should be 0. If anything diverges, **stop and investigate** — the live cluster has been partially mutated and you need to know whether that's safe.

### Step 9 — Verify

For the 2026-05-04 incident, the verification was:

```elixir
BlocksterV2.CoinFlipGame.period_stats(:sol)            # all-time
BlocksterV2.CoinFlipGame.period_stats(:sol, 86400)     # 24h
BlocksterV2.LpPriceHistory.get_price_history("sol", "24H") |> length()
length(:mnesia.dirty_all_keys(:pool_activities))
```

Confirm numbers match expectations. The 24h window may genuinely be empty if there was no recent activity in that vault — that's not a bug.

### Step 10 — Tear down

```bash
flyctl machine stop <temp_machine_id> --app blockster-v2
flyctl machine destroy <temp_machine_id> --app blockster-v2 --force
flyctl volumes destroy <forked_volume_id> --yes
rm /Users/<you>/snapshot_dump.bin
```

Local dump and forked volume are destroyed. Live cluster is unchanged from the merge state.

---

## 4. Permanent fix path

The root cause is in `lib/blockster_v2/mnesia_initializer.ex` — `initialize_mnesia_for_joining_node/0` doesn't call `:mnesia.change_config(:extra_db_nodes, alive_nodes)` after libcluster has populated `Node.list/0`. So when a node boots with a stale schema (the recovery's after-effect), it stays in split-brain because Mnesia auto-discovery doesn't fire.

The sketched fix (from `project_mnesia_split_brain_open.md`, **unverified**, not shipped):

```elixir
defp initialize_mnesia_for_joining_node do
  alive_nodes = wait_for_cluster_nodes(timeout: 10_000)

  case :mnesia.change_config(:extra_db_nodes, alive_nodes) do
    {:ok, _} -> :ok
    {:error, {:merge_schema_failed, _details}} ->
      drop_conflicting_local_tables()  # tables with cookie != cluster cookie
      :mnesia.change_config(:extra_db_nodes, alive_nodes)
  end

  initialize_with_persistence()
end
```

In addition, **the deploy itself should not require this manual recovery**. A correctly-rejoining boot would skip the runbook entirely. Until that ships, treat the runbook as the *fallback* and prefer keeping cluster topology stable across deploys.

**Equally important — fix the disc_copies imbalance.** The reason the 2026-05-04 recovery destroyed data is that several tables had `disc_copies = [ghost, c889]` only, with no copy on `e770`. That imbalance has been a latent bug since whenever those tables were created. After the merge, run an audit:

```elixir
two_node_target = [:"blockster-v2@<machine_a_ip>", :"blockster-v2@<machine_b_ip>"]
for t <- :mnesia.system_info(:tables), t != :schema do
  copies = :mnesia.table_info(t, :disc_copies)
  if length(copies) < 2 do
    IO.puts("#{t}  disc_copies=#{inspect(copies)}  ← needs second replica")
  end
end
```

For each one-replica table, run `:mnesia.add_table_copy/3` to bring it to two replicas. After both nodes have copies of every table, the standard runbook becomes safe.

---

## Cross-references

- `project_mnesia_split_brain_open.md` (Claude memory) — the original split-brain runbook (with the documented blindspot warning)
- `feedback_mnesia_runbook_blindspot.md` (Claude memory) — short rule that flags the blindspot in future sessions
- [session_learnings.md "Mnesia disaster recovery via volume snapshots"](session_learnings.md) — narrative of the 2026-05-04 incident
- [CLAUDE.md "Database / Mnesia"](../CLAUDE.md) — links here from the critical rules
