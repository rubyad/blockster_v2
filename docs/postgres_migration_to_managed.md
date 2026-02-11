# Migration Guide: Postgres Flex to Fly Managed Postgres (MPG)

**Date Created**: February 11, 2026
**Current Database**: `fragrant-flower-8144-db` (Postgres Flex 17.2, `ord` region)
**Target**: Fly Managed Postgres (MPG) — Fly's fully-managed service built on Percona/Kubernetes
**Application**: `blockster-v2` (Phoenix/Elixir, `ord` region)
**Estimated Downtime**: 10-30 minutes

---

## Table of Contents

1. [Current Infrastructure](#current-infrastructure)
2. [Target Infrastructure](#target-infrastructure)
3. [Pre-Migration: Backup Everything](#pre-migration-backup-everything)
4. [Create MPG Cluster](#create-mpg-cluster)
5. [Data Migration](#data-migration)
6. [Phoenix/Ecto Configuration Changes](#phoenixecto-configuration-changes)
7. [Cutover Process](#cutover-process)
8. [Verification & Health Checks](#verification--health-checks)
9. [Rollback Plan](#rollback-plan)
10. [Post-Migration Tasks](#post-migration-tasks)
11. [Troubleshooting](#troubleshooting)
12. [Decommission Old Database](#decommission-old-database)

---

## Current Infrastructure

### fragrant-flower-8144-db (Postgres Flex)

| Property | Value |
|----------|-------|
| App name | `fragrant-flower-8144-db` |
| Type | Fly Postgres Flex (self-managed) |
| Postgres version | 17.2 |
| Region | `ord` (Chicago) |
| Machine | `d894ed5a696d58` — **shared-cpu-1x, 256MB RAM** |
| Machines | **1 (no HA, no standby)** |
| Volume | `vol_r63zzmp36e21j51r` — **1 GB**, encrypted |
| Database name | `fragrant_flower_8144` |
| Max connections | 300 |
| Image | `flyio/postgres-flex:17.2` (v0.0.66) |
| Created | November 1, 2025 |
| Image update available | v0.0.66 → v0.1.0 |

### blockster-v2 (Application)

| Property | Value |
|----------|-------|
| Region | `ord` (Chicago) — same as database |
| Machine | `performance-2x`, 4096MB RAM |
| Machines | 1 |
| Secrets | `DATABASE_URL` configured |

### Problems with Current Setup
- **No HA** — single machine, any failure = downtime
- **Tiny resources** — 256MB RAM, shared CPU backing a 4GB app server
- **No automatic backups** — Postgres Flex is self-managed
- **No connection pooling** — no PgBouncer
- **1GB storage** — very tight

---

## Target Infrastructure

### Fly Managed Postgres (MPG)

Fly MPG is their fully-managed Postgres built on Percona's Kubernetes operator. Every plan includes:
- **2-node HA cluster** (primary + automatic failover standby)
- **2 PGBouncer nodes** for connection pooling
- **Automatic backups** (daily full, 6-hour differential, hourly incremental)
- **10-day backup retention**
- **Support portal access**

### Recommended Plan: Launch

| Property | Value |
|----------|-------|
| Plan | **Launch** |
| CPU | Performance-2x (dedicated) |
| Memory | **8GB** per node |
| Nodes | **2** (primary + standby, automatic failover) |
| PgBouncer | 2 nodes (included) |
| Storage | **20GB** (expandable to 1TB) |
| Region | **`ord`** (Chicago — same as app, zero latency) |
| Postgres version | 17 |
| Monthly cost | ~$282 + $5.60 storage = **~$288/month** |

### Why Launch Plan?

| Plan | CPU | Memory | Price/mo | Notes |
|------|-----|--------|----------|-------|
| Basic | Shared-2x | 1GB | $38 | Too small — less than current app server |
| Starter | Shared-2x | 2GB | $72 | Shared CPU, not ideal for heavy load |
| **Launch** | **Performance-2x** | **8GB** | **$282** | **Dedicated CPU, 8GB RAM — handles heavy load** |
| Scale | Performance-4x | 32GB | $962 | Overkill for current scale |
| Performance | Performance-8x | 64GB | $1,922 | Enterprise-level |

The Launch plan gives you dedicated CPU cores and 8GB RAM per node — plenty of headroom for heavy query loads. With 2 nodes (primary + standby), you get automatic failover. This is a significant upgrade from the current 256MB shared-CPU single machine.

**Storage pricing**: $0.28/GB/month. 20GB = $5.60/month.

### Important MPG Limitations
- **No read replicas** — the standby handles failover only, not read traffic
- **Single-region only** — no cross-region replicas
- **Max storage** — 500GB at creation, expandable to 1TB
- **Backup retention** — 10 days (not configurable)
- **PGBouncer transaction mode** — requires `prepare: :unnamed` in Ecto config

---

## Pre-Migration: Backup Everything

### Step 1: Create Working Directory

```bash
mkdir -p ~/blockster-migration/{backups,logs,verification}
cd ~/blockster-migration
```

### Step 2: Document Current State

```bash
# Save current database state
flyctl status --app fragrant-flower-8144-db > logs/pre-migration-status.txt
flyctl postgres config show --app fragrant-flower-8144-db > logs/current-config.txt
flyctl postgres db list --app fragrant-flower-8144-db > logs/current-databases.txt
flyctl postgres users list --app fragrant-flower-8144-db > logs/current-users.txt
flyctl machine list --app fragrant-flower-8144-db > logs/current-machines.txt
flyctl volumes list --app fragrant-flower-8144-db > logs/current-volumes.txt
```

### Step 3: Check Database Size

```bash
flyctl postgres connect --app fragrant-flower-8144-db --database fragrant_flower_8144

# Inside psql:
SELECT pg_size_pretty(pg_database_size('fragrant_flower_8144'));
\l+ fragrant_flower_8144

# Get table sizes and row counts
SELECT schemaname, tablename,
       n_live_tup as row_count,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

\q
```

Save this output to `logs/table-inventory.txt` — you'll compare against it after migration.

### Step 4: Full Database Backup (pg_dump)

```bash
# Method A: Proxy-based dump (recommended)
# Open proxy to Postgres Flex in one terminal:
flyctl proxy 15432:5432 --app fragrant-flower-8144-db

# In another terminal, dump through proxy:
pg_dump "postgres://postgres:<password>@localhost:15432/fragrant_flower_8144" \
  -Fc -v -f backups/fragrant_flower_$(date +%Y%m%d_%H%M%S).dump

# Method B: Plain SQL backup (human-readable, for emergency manual recovery)
pg_dump "postgres://postgres:<password>@localhost:15432/fragrant_flower_8144" \
  -v --inserts -f backups/fragrant_flower_$(date +%Y%m%d_%H%M%S).sql
gzip backups/fragrant_flower_*.sql
```

**Getting the password**: Check `DATABASE_URL` secret value, or use:
```bash
flyctl ssh console --app fragrant-flower-8144-db -C "printenv DATABASE_URL"
```

### Step 5: Verify Backup Integrity

```bash
# Check file size (must be > 0)
ls -lh backups/

# Verify backup is valid
pg_restore --list backups/fragrant_flower_*.dump | head -20

# Count objects in backup
pg_restore --list backups/fragrant_flower_*.dump | wc -l
```

### Step 6: Volume Snapshot (Infrastructure-Level Backup)

```bash
# Create snapshot of the Postgres Flex volume
flyctl volumes snapshots create vol_r63zzmp36e21j51r --app fragrant-flower-8144-db

# Verify snapshot created
flyctl volumes snapshots list vol_r63zzmp36e21j51r --app fragrant-flower-8144-db
```

### Step 7: Upload Backups to Safe Storage

```bash
# Upload to S3
aws s3 cp backups/ s3://blockster-backups/postgres-migration-$(date +%Y%m%d)/ --recursive

# Or any other safe location — do NOT rely solely on local copies
```

### Backup Verification Checklist

- [ ] Full pg_dump backup created (custom format `.dump`)
- [ ] Plain SQL backup created and gzipped
- [ ] Backup passes `pg_restore --list` validation
- [ ] Fly volume snapshot created
- [ ] Backups uploaded to external storage (S3 or similar)
- [ ] Backup file sizes documented in `logs/backup-manifest.txt`

---

## Create MPG Cluster

### Step 1: Create the Managed Postgres Cluster

```bash
fly mpg create \
  --name blockster-mpg \
  --region ord \
  --plan launch \
  --volume-size 20 \
  --pg-major-version 17 \
  --org personal
```

**IMPORTANT**: Save ALL output from this command — it contains your connection credentials.

Save the output:
```bash
cat > logs/mpg-connection-details.txt <<'EOF'
Cluster Name: blockster-mpg
Region: ord
Plan: launch
Created: <date>
Connection Details: <SAVE EVERYTHING FROM THE OUTPUT>
EOF
```

### Step 2: Verify Cluster is Running

```bash
# Check cluster status
fly mpg status <CLUSTER_ID>

# Connect to verify
fly mpg connect
```

The cluster ID is returned during creation. You can also find it with:
```bash
fly mpg list
```

### Step 3: Create a Manual Backup Immediately

```bash
# Create first backup of the empty MPG cluster (baseline)
fly mpg backup create <CLUSTER_ID>

# Verify backups are working
fly mpg backup list <CLUSTER_ID>
```

At this point, automatic backups are already enabled:
- **Daily full backup** at 1:00 AM UTC
- **Differential backup** every 6 hours
- **Incremental backup** every hour
- **10-day retention**

---

## Data Migration

### Step 1: Open Proxy to MPG Cluster

```bash
# Start MPG proxy (runs on localhost:16380 by default)
fly mpg proxy
```

Keep this terminal open — the proxy must stay running during migration.

### Step 2: Get Connection Details

From the `fly mpg create` output, you'll have a connection string like:
```
postgresql://fly-user:<password>@pgbouncer.<hash>.flympg.net/fly-db
```

For local proxy access, replace the host with `localhost:16380`:
```
postgresql://fly-user:<password>@localhost:16380/fly-db
```

### Step 3: Restore Data

```bash
# Restore from the custom format dump through the proxy
pg_restore -v \
  -d "postgresql://fly-user:<password>@localhost:16380/fly-db" \
  backups/fragrant_flower_*.dump

# Watch for errors — some non-critical warnings about roles are expected
```

**Alternative — pipe method** (for plain SQL dumps):
```bash
pg_dump "postgres://postgres:<old_pass>@localhost:15432/fragrant_flower_8144" | \
  psql "postgresql://fly-user:<new_pass>@localhost:16380/fly-db"
```

### Step 4: Verify Row Counts

```bash
# Connect to NEW database
psql "postgresql://fly-user:<password>@localhost:16380/fly-db"

# Compare against logs/table-inventory.txt
SELECT schemaname, tablename,
       n_live_tup as row_count,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_stat_user_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

\q
```

Save this output and diff against the pre-migration inventory:
```bash
diff logs/table-inventory.txt verification/new-table-inventory.txt
```

### Step 5: Spot-Check Critical Data

```bash
psql "postgresql://fly-user:<password>@localhost:16380/fly-db"

-- Recent users
SELECT id, email, inserted_at FROM users ORDER BY inserted_at DESC LIMIT 5;

-- Recent posts
SELECT id, title, slug, published_at FROM posts
WHERE published_at IS NOT NULL ORDER BY published_at DESC LIMIT 5;

-- Check constraints are intact
SELECT conname, conrelid::regclass AS table_name
FROM pg_constraint WHERE contype = 'f' LIMIT 20;

-- Check indexes migrated
SELECT indexname, tablename FROM pg_indexes
WHERE schemaname = 'public' ORDER BY tablename;

\q
```

### Step 6: Update Statistics

```bash
psql "postgresql://fly-user:<password>@localhost:16380/fly-db"

-- Update all table statistics for query optimizer
ANALYZE;

\q
```

---

## Phoenix/Ecto Configuration Changes

### PGBouncer Transaction Mode Requirement

MPG includes PGBouncer in **transaction mode** by default. This requires one critical Ecto change.

### Update config/runtime.exs

In `config/runtime.exs`, ensure the Repo config includes `prepare: :unnamed`:

```elixir
config :blockster_v2, BlocksterV2.Repo,
  url: database_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  socket_options: maybe_ipv6,
  prepare: :unnamed  # REQUIRED for PGBouncer transaction mode
```

**Why?** PGBouncer in transaction mode doesn't support named prepared statements. Without this, you'll get `Postgrex.Error: prepared statement ... does not exist` errors.

### Migrations Need Direct URL

PGBouncer doesn't support advisory locks (used by Ecto migrations). Migrations must use the **direct** connection URL (bypasses PGBouncer).

MPG provides two connection URLs:
- **Pooled**: `postgresql://fly-user:<pass>@pgbouncer.<hash>.flympg.net/fly-db` — for app queries
- **Direct**: `postgresql://fly-user:<pass>@direct.<hash>.flympg.net/fly-db` — for migrations

Update `fly.toml` release command:

```toml
[deploy]
  release_command = "/bin/sh -lc 'DATABASE_URL=$DIRECT_DATABASE_URL bin/migrate'"
```

Or in `config/runtime.exs`, handle migration URL:

```elixir
# For migrations (using direct connection, no PGBouncer)
if config_env() == :prod do
  direct_url = System.get_env("DIRECT_DATABASE_URL")
  if direct_url do
    config :blockster_v2, BlocksterV2.Repo,
      migration_url: direct_url
  end
end
```

### Oban Consideration

If you use Oban (job processing), it relies on LISTEN/NOTIFY which doesn't work through PGBouncer in transaction mode. Configure the PG notifier instead:

```elixir
config :blockster_v2, Oban,
  notifier: Oban.Notifiers.PG  # Uses Distributed Erlang, not Postgres LISTEN/NOTIFY
```

---

## Cutover Process

### Pre-Cutover Checklist

- [ ] Full backup of current database verified
- [ ] MPG cluster created and running in `ord`
- [ ] Data migrated and row counts match
- [ ] Schema comparison shows no differences
- [ ] `prepare: :unnamed` added to Ecto config
- [ ] `DIRECT_DATABASE_URL` handling configured for migrations
- [ ] Migration release command updated in `fly.toml` (if needed)
- [ ] Rollback plan reviewed

### Step 1: Scale Down Application (Start Downtime)

```bash
# Stop the app to prevent writes during final sync
flyctl scale count 0 --app blockster-v2

# Verify app is stopped
flyctl status --app blockster-v2
```

### Step 2: Final Data Sync

Since the app was still running after the initial migration, there may be new data:

```bash
# Open proxy to OLD database
flyctl proxy 15432:5432 --app fragrant-flower-8144-db

# Take final dump
pg_dump "postgres://postgres:<password>@localhost:15432/fragrant_flower_8144" \
  -Fc -v -f backups/final_sync_$(date +%Y%m%d_%H%M%S).dump

# Open proxy to NEW database (different terminal)
fly mpg proxy

# Restore final dump (drop and recreate to get clean state)
# WARNING: This replaces all data in MPG with the final backup
pg_restore -v --clean --if-exists \
  -d "postgresql://fly-user:<password>@localhost:16380/fly-db" \
  backups/final_sync_*.dump
```

### Step 3: Attach MPG to Application

```bash
# This sets DATABASE_URL automatically
fly mpg attach <CLUSTER_ID> -a blockster-v2
```

### Step 4: Set Direct URL for Migrations

```bash
# Set the direct URL secret (bypasses PGBouncer for migrations)
flyctl secrets set DIRECT_DATABASE_URL="postgresql://fly-user:<pass>@direct.<hash>.flympg.net/fly-db" --app blockster-v2
```

### Step 5: Deploy with Configuration Changes

```bash
# Deploy the app with prepare: :unnamed and migration URL changes
flyctl deploy --app blockster-v2
```

This will:
1. Build with the new Ecto config
2. Run release migrations via direct URL
3. Start the app connecting through PGBouncer

### Step 6: Scale Back Up (End Downtime)

```bash
# Scale to desired machine count
flyctl scale count 2 --app blockster-v2

# Monitor startup
flyctl logs --app blockster-v2 -f
```

---

## Verification & Health Checks

### Immediate Checks (First 5 Minutes)

```bash
# Check app is healthy
flyctl status --app blockster-v2

# Watch logs for database errors
flyctl logs --app blockster-v2 | grep -i "error\|postgrex\|ecto\|database"

# Test the site
curl -s -o /dev/null -w "%{http_code}" https://v2.blockster.com
```

### Database Connection Health

```bash
fly mpg connect

-- Check active connections
SELECT count(*), state, usename, application_name
FROM pg_stat_activity
WHERE datname = 'fly-db'
GROUP BY state, usename, application_name;

-- Check for long-running queries
SELECT pid, now() - pg_stat_activity.query_start AS duration, query
FROM pg_stat_activity
WHERE state != 'idle' AND query_start IS NOT NULL
ORDER BY duration DESC LIMIT 5;

\q
```

### Functional Testing

Test these critical flows manually:
- [ ] User login works
- [ ] Posts load and display correctly
- [ ] Shop products display with images
- [ ] BUX Booster game loads (Mnesia + Postgres data)
- [ ] Token balances display correctly
- [ ] New post creation works
- [ ] Search works (full-text search uses Postgres)

### Monitor for 30 Minutes

```bash
# Keep watching logs
flyctl logs --app blockster-v2 -f

# Look for:
# - Connection timeout errors
# - Postgrex protocol violations
# - Ecto query errors
# - Pool checkout timeouts
```

### Success Criteria

- [ ] App started on all machines with no database errors
- [ ] No connection errors for 30+ minutes
- [ ] All functional tests pass
- [ ] Database connections stable (not growing unbounded)
- [ ] Query latency acceptable (check via app responsiveness)

---

## Rollback Plan

**If anything goes wrong, rollback immediately.**

### Step 1: Stop Application

```bash
flyctl scale count 0 --app blockster-v2
```

### Step 2: Get Old DATABASE_URL

The old `DATABASE_URL` was overwritten by `fly mpg attach`. You need the original:
```
postgres://<user>:<password>@fragrant-flower-8144-db.flycast:5432/fragrant_flower_8144
```

If you saved it in `logs/` before cutover, use that. Otherwise:
```bash
flyctl ssh console --app fragrant-flower-8144-db -C "printenv DATABASE_URL"
```

### Step 3: Restore Old Connection

```bash
# Point back to old Postgres Flex
flyctl secrets set DATABASE_URL="postgres://<user>:<password>@fragrant-flower-8144-db.flycast:5432/fragrant_flower_8144" --app blockster-v2

# Remove direct URL (not needed for Flex)
flyctl secrets unset DIRECT_DATABASE_URL --app blockster-v2
```

### Step 4: Revert Code Changes

Remove `prepare: :unnamed` from `config/runtime.exs` if it causes issues with Postgres Flex.

### Step 5: Scale Back Up

```bash
flyctl scale count 2 --app blockster-v2
flyctl logs --app blockster-v2 -f
```

### Step 6: Verify Rollback

```bash
curl -s -o /dev/null -w "%{http_code}" https://v2.blockster.com
```

**Keep the old `fragrant-flower-8144-db` running for at least 2-4 weeks after successful migration.**

---

## Post-Migration Tasks

### Day 1

#### 1. Verify Automatic Backups

```bash
# Check that automatic backups are running
fly mpg backup list <CLUSTER_ID>

# Create an additional manual backup
fly mpg backup create <CLUSTER_ID>
```

Automatic backup schedule (included with all MPG plans):
| Type | Frequency | Description |
|------|-----------|-------------|
| Full | Daily at 1:00 AM UTC | Complete database snapshot |
| Differential | Every 6 hours | Changes since last full backup |
| Incremental | Every hour | WAL-based, hourly RPO |
| Retention | 10 days | All backup types |

#### 2. Run ANALYZE

```bash
fly mpg connect

-- Update statistics after migration for optimal query plans
ANALYZE;

\q
```

#### 3. Enable pg_stat_statements

```bash
fly mpg connect

-- Enable query performance tracking
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Verify
SELECT * FROM pg_stat_statements LIMIT 1;

\q
```

#### 4. Save Old DATABASE_URL

Document the old connection string somewhere safe in case you need to rollback:
```bash
echo "OLD DATABASE_URL: postgres://...:5432/fragrant_flower_8144" >> logs/rollback-info.txt
```

### Week 1

#### 1. Monitor Query Performance

```bash
fly mpg connect

-- Top 10 slowest queries
SELECT query, calls, mean_exec_time, total_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;

-- Tables with most sequential scans (may need indexes)
SELECT schemaname, tablename, seq_scan, seq_tup_read, idx_scan
FROM pg_stat_user_tables
WHERE seq_scan > 100
ORDER BY seq_tup_read DESC;

\q
```

#### 2. Check Connection Pool Usage

```bash
fly mpg connect

SELECT count(*), state
FROM pg_stat_activity
GROUP BY state;

\q
```

If connections are frequently at capacity, increase `pool_size` in `runtime.exs`.

### Week 2-4

#### 1. Performance Baseline

Document query latency, connection counts, and backup status as your baseline.

#### 2. Update CLAUDE.md

Update the project documentation with:
- New database app name (`blockster-mpg`)
- New connection URL format
- Backup schedule information
- MPG-specific commands

---

## Troubleshooting

### Issue: "prepared statement does not exist"

**Cause**: Missing `prepare: :unnamed` in Ecto config.

**Fix**: Add to `config/runtime.exs`:
```elixir
prepare: :unnamed
```

### Issue: Migration fails with "cannot obtain advisory lock"

**Cause**: Migrations running through PGBouncer (which doesn't support advisory locks).

**Fix**: Use direct URL for migrations:
```bash
flyctl secrets set DIRECT_DATABASE_URL="postgresql://fly-user:<pass>@direct.<hash>.flympg.net/fly-db" --app blockster-v2
```

And ensure `fly.toml` uses it:
```toml
[deploy]
  release_command = "/bin/sh -lc 'DATABASE_URL=$DIRECT_DATABASE_URL bin/migrate'"
```

### Issue: Connection pool exhausted

**Symptoms**: `DBConnection.ConnectionError: connection not available`

**Fix**: Adjust pool size in `runtime.exs`:
```elixir
pool_size: String.to_integer(System.get_env("POOL_SIZE") || "15")
```

### Issue: Slow queries after migration

**Fix**:
```bash
fly mpg connect

-- Rebuild statistics
ANALYZE;

-- Rebuild indexes if needed
REINDEX DATABASE "fly-db";

\q
```

### Issue: LISTEN/NOTIFY not working

**Cause**: PGBouncer in transaction mode doesn't support LISTEN/NOTIFY.

**Fix**: If using Oban, switch to PG notifier:
```elixir
config :blockster_v2, Oban,
  notifier: Oban.Notifiers.PG
```

For Phoenix PubSub, it already uses Distributed Erlang (not Postgres), so no change needed.

### Issue: "database fly-db does not exist" during restore

**Cause**: MPG creates a default database called `fly-db`. Your dump may try to connect to a different database name.

**Fix**: Explicitly specify the target database:
```bash
pg_restore -v -d "postgresql://fly-user:<pass>@localhost:16380/fly-db" backup.dump
```

---

## Decommission Old Database

**ONLY do this after 2-4 weeks of stable operation on MPG.**

### Step 1: Final Backup of Old Database

```bash
flyctl proxy 15432:5432 --app fragrant-flower-8144-db

pg_dump "postgres://postgres:<pass>@localhost:15432/fragrant_flower_8144" \
  -Fc -v -f backups/final_old_db_$(date +%Y%m%d).dump

# Upload to S3
aws s3 cp backups/final_old_db_*.dump s3://blockster-backups/decommission/
```

### Step 2: Destroy Old Database App

```bash
# DANGER: This is irreversible!
flyctl apps destroy fragrant-flower-8144-db
```

### Step 3: Clean Up Secrets

```bash
# Remove any references to old database
flyctl secrets list --app blockster-v2
# If any old connection strings remain, remove them
```

---

## MPG CLI Quick Reference

```bash
# Cluster management
fly mpg list                         # List all MPG clusters
fly mpg status <CLUSTER_ID>         # Cluster status and details
fly mpg create                       # Create new cluster (interactive)
fly mpg destroy <CLUSTER_ID>        # Destroy cluster

# Connections
fly mpg connect                      # Interactive psql session
fly mpg proxy                        # Local proxy (localhost:16380)

# App integration
fly mpg attach <CLUSTER_ID> -a <APP>   # Attach to app (sets DATABASE_URL)
fly mpg detach <CLUSTER_ID> -a <APP>   # Detach from app

# Backups
fly mpg backup list <CLUSTER_ID>       # List all backups
fly mpg backup create <CLUSTER_ID>     # Create manual backup
fly mpg restore <CLUSTER_ID> --backup-id <ID>  # Restore from backup

# Users & databases
fly mpg users create                    # Create user (roles: schema_admin, writer, reader)
fly mpg databases create                # Create additional database
```

---

## Cost Summary

| Component | Current (Postgres Flex) | New (MPG Launch) |
|-----------|------------------------|-------------------|
| Plan | Self-managed | Fully managed |
| Compute | shared-cpu-1x, 256MB | Performance-2x, 8GB |
| Nodes | 1 (no HA) | 2 (primary + standby) |
| PgBouncer | None | 2 nodes (included) |
| Storage | 1 GB | 20 GB |
| Backups | None (manual only) | Automatic (hourly/daily) |
| Failover | None | Automatic |
| Monthly cost | ~$4 | **~$288** |

The cost increase is significant but justified by:
- **Automatic HA** — no more single-point-of-failure downtime
- **8GB RAM** — 32x more memory for query caching and performance
- **Dedicated CPU** — no noisy-neighbor performance issues
- **Automatic backups** — hourly incremental with 10-day retention
- **Connection pooling** — PGBouncer included
- **Zero operational overhead** — Fly manages upgrades, patching, failover

---

**Document Version**: 2.0
**Last Updated**: February 11, 2026
