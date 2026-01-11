# Mnesia Data Sync: Local to Production

This document explains how to export Mnesia data from local development and import it into production.

## Overview

The High Rollers Elixir app uses Mnesia for real-time data storage. When deploying to production for the first time (or after wiping the database), you need to populate Mnesia with existing NFT data, earnings, and statistics.

**Key files:**
- `scripts/export_mnesia.exs` - Export script (run locally)
- `lib/high_rollers/mnesia_sync.ex` - Import module (used in production)

## Tables Synced

| Table | Records | Description |
|-------|---------|-------------|
| `hr_nfts` | 2,344 | All NFT data with earnings and time rewards |
| `hr_reward_events` | 53 | Historical RewardReceived events from contract |
| `hr_reward_withdrawals` | 17 | User withdrawal history |
| `hr_users` | 3 | User-affiliate mappings |
| `hr_affiliate_earnings` | 4,681 | Affiliate commission records |
| `hr_stats` | 9 | Global and per-hostess statistics |
| `hr_poller_state` | 2 | Block number tracking for pollers |
| `hr_prices` | 2 | Cached ROGUE/ETH prices |

## Step 1: Export from Local

With hr1 running locally (`elixir --sname hr1 -S mix phx.server`), run the export script:

```bash
cd high-rollers-elixir
elixir --sname export -S mix run --no-start scripts/export_mnesia.exs
```

**Output:**
```
=== Mnesia Export Script ===
Target node: hr1@Adams-iMac-Pro
Output file: /tmp/hr_mnesia_export.etf

Connecting to hr1@Adams-iMac-Pro...
✅ Connected!

Exporting tables: [:hr_nfts, :hr_reward_events, ...]
  hr_nfts: 2344 records
  hr_reward_events: 53 records
  ...

✅ Export complete!
   Total records: 7111
   File size: 117.8 KB
   File: /tmp/hr_mnesia_export.etf
```

## Step 2: Copy to Production

Use Fly's SFTP to upload the export file:

```bash
flyctl ssh sftp shell -a high-rollers-elixir
```

In the SFTP shell:
```
put /tmp/hr_mnesia_export.etf /tmp/hr_mnesia_export.etf
exit
```

## Step 3: Import in Production

Connect to the production app's remote console:

```bash
flyctl ssh console -a high-rollers-elixir -C '/app/bin/high_rollers remote'
```

In the remote IEx console:
```elixir
HighRollers.MnesiaSync.import_all("/tmp/hr_mnesia_export.etf")
```

**Output:**
```
[MnesiaSync] Starting import from /tmp/hr_mnesia_export.etf
[MnesiaSync] Export version: 1
[MnesiaSync] Exported at: 2026-01-11 11:29:54Z
[MnesiaSync] Exported from: hr1@Adams-iMac-Pro
[MnesiaSync] Record counts: %{hr_nfts: 2344, hr_reward_events: 53, ...}
[MnesiaSync] Cleared table hr_nfts
[MnesiaSync] Imported 2344 records into hr_nfts
...
[MnesiaSync] Import complete: 7111 records
{:ok, %{records: 7111, tables: %{...}}}
```

## Dry Run (Preview)

To see what would be imported without making changes:

```elixir
HighRollers.MnesiaSync.import_all("/tmp/hr_mnesia_export.etf", dry_run: true)
```

## Inspect Export File

To see the contents of an export file without importing:

```elixir
HighRollers.MnesiaSync.info("/tmp/hr_mnesia_export.etf")
```

**Output:**
```
=== Mnesia Export Info ===
File: /tmp/hr_mnesia_export.etf
Size: 117.8 KB
Version: 1
Exported at: 2026-01-11 11:29:54Z
Exported from: hr1@Adams-iMac-Pro

Tables:
  hr_nfts: 2344 records
  hr_reward_events: 53 records
  hr_reward_withdrawals: 17 records
  hr_users: 3 records
  hr_affiliate_earnings: 4681 records
  hr_stats: 9 records
  hr_poller_state: 2 records
  hr_prices: 2 records
```

## Import Modes

Tables are imported in one of two modes:

| Mode | Tables | Behavior |
|------|--------|----------|
| **Replace** | `hr_nfts`, `hr_users`, `hr_stats`, `hr_poller_state`, `hr_prices` | Clears table before import |
| **Merge** | `hr_reward_events`, `hr_reward_withdrawals`, `hr_affiliate_earnings` | Adds to existing records |

To override the mode for all tables:

```elixir
HighRollers.MnesiaSync.import_all("/tmp/hr_mnesia_export.etf", mode: :replace)
```

## Quick Reference

```bash
# 1. Export (local - with hr1 running)
elixir --sname export -S mix run --no-start scripts/export_mnesia.exs

# 2. Upload to production
flyctl ssh sftp shell -a high-rollers-elixir
# put /tmp/hr_mnesia_export.etf /tmp/hr_mnesia_export.etf

# 3. Import (production)
flyctl ssh console -a high-rollers-elixir -C '/app/bin/high_rollers remote'
# HighRollers.MnesiaSync.import_all("/tmp/hr_mnesia_export.etf")
```

## Troubleshooting

### Export fails to connect
Make sure hr1 is running:
```bash
elixir --sname hr1 -S mix phx.server
```

### File not found in production
Check the file was uploaded correctly:
```bash
flyctl ssh console -a high-rollers-elixir -C 'ls -la /tmp/*.etf'
```

### Import errors
Check Mnesia is running and tables exist:
```elixir
:mnesia.system_info(:is_running)  # Should be :yes
:mnesia.system_info(:tables)      # Should list all hr_* tables
```

## File Format

The export uses Erlang Term Format (ETF) with compression. Structure:

```elixir
%{
  version: 1,
  exported_at: 1736595594,  # Unix timestamp
  exported_from: :"hr1@Adams-iMac-Pro",
  tables: %{
    hr_nfts: [record1, record2, ...],
    hr_reward_events: [...],
    ...
  },
  record_counts: %{
    hr_nfts: 2344,
    hr_reward_events: 53,
    ...
  }
}
```

To read manually:
```elixir
binary = File.read!("/tmp/hr_mnesia_export.etf")
data = :erlang.binary_to_term(binary)
```
