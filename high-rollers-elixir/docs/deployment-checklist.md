# High Rollers Elixir - Deployment Checklist

## Prerequisites

- Fly.io CLI installed (`flyctl`)
- Authenticated with Fly.io (`flyctl auth login`)
- Local hr1 node running with current Mnesia data

## How Seeding Works

Mnesia data is exported to `priv/mnesia_seed/*.etf` files and bundled with the release. On first deploy, MnesiaInitializer automatically seeds empty tables from these files. No manual import step needed.

## First-Time Deployment

### 1. Export Current Mnesia Data

```bash
# Make sure hr1 is running
elixir --sname hr1 -S mix phx.server

# In another terminal, export to seed files
cd high-rollers-elixir
elixir --sname exporter$RANDOM scripts/export_to_json.exs
```

This creates `priv/mnesia_seed/*.etf` files (bundled in the release).

### 2. Create the Fly App

```bash
flyctl apps create high-rollers-elixir
```

### 3. Create Persistent Volume

```bash
flyctl volumes create high_rollers_data --region fra --size 1
```

### 4. Set Required Secrets

```bash
# Generate a secret key for Phoenix sessions
flyctl secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)

# Add any other required secrets
# flyctl secrets set SOME_API_KEY=your_key_here
```

### 5. Deploy

```bash
flyctl deploy
```

On first deploy:
1. Docker image is built with seed files in `priv/mnesia_seed/`
2. Machine starts with empty Mnesia volume at `/data`
3. MnesiaInitializer creates tables and seeds from bundled files
4. App is ready with all data

## Subsequent Deployments

### Code Changes Only

```bash
flyctl deploy
```

Mnesia data persists on the volume - tables already exist, no seeding happens.

### Data Changes (Re-seed)

If you need to update production data from local:

```bash
# 1. Export fresh data locally
elixir --sname exporter$RANDOM scripts/export_to_json.exs

# 2. Delete the Mnesia volume to force re-seed
flyctl volumes delete high_rollers_data

# 3. Create a new volume
flyctl volumes create high_rollers_data --region fra --size 1

# 4. Deploy (will seed from new export)
flyctl deploy
```

**Warning**: This deletes all production Mnesia data. Only do this to reset from local.

## Verification

```bash
# Check logs for seeding
flyctl logs | grep MnesiaInitializer

# SSH and check table sizes
flyctl ssh console -C "/app/bin/high_rollers remote"

# In IEx:
:mnesia.table_info(:hr_nfts, :size)
:mnesia.table_info(:hr_stats, :size)
```

## Useful Commands

```bash
# View logs
flyctl logs

# SSH into machine
flyctl ssh console

# Open IEx remote console
flyctl ssh console -C "/app/bin/high_rollers remote"

# Restart app
flyctl apps restart high-rollers-elixir

# Check app status
flyctl status

# List secrets (names only)
flyctl secrets list

# Scale resources
flyctl scale memory 2048
```

## Troubleshooting

### Tables Not Seeding

Check that seed files exist in the release:

```bash
flyctl ssh console
ls -la /app/lib/high_rollers-*/priv/mnesia_seed/
```

### Out of Memory

```bash
flyctl scale memory 4096
```

### Volume Full

```bash
flyctl ssh console
df -h /data

# Extend if needed
flyctl volumes extend <volume-id> --size 2
```
