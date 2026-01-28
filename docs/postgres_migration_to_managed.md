# Migration Guide: Unmanaged to Managed Postgres on Fly.io

**Date Created**: January 27, 2026
**Current Database**: `blockster-db` (Unmanaged Postgres 14.6)
**Target**: Fly Managed Postgres (MPG)
**Estimated Downtime**: 10-30 minutes (depending on database size)

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Pre-Migration Checklist](#pre-migration-checklist)
3. [Backup Procedures](#backup-procedures)
4. [Create Managed Postgres Cluster](#create-managed-postgres-cluster)
5. [Data Migration](#data-migration)
6. [Update Application Configuration](#update-application-configuration)
7. [Testing & Validation](#testing--validation)
8. [Cutover Process](#cutover-process)
9. [Rollback Procedures](#rollback-procedures)
10. [Post-Migration Tasks](#post-migration-tasks)
11. [Troubleshooting](#troubleshooting)

---

## Prerequisites

### Required Tools
- `flyctl` CLI installed and authenticated
- `pg_dump` and `pg_restore` (Postgres client tools)
- `psql` for database access
- SSH access to Fly.io machines

### Permissions Needed
- Owner/admin access to Fly.io organization
- Database superuser credentials for `blockster-db`

### Current State Documentation
```bash
# Document current database state
flyctl status --app blockster-db > migration-logs/pre-migration-status.txt
flyctl postgres config show --app blockster-db > migration-logs/current-config.txt
flyctl postgres db list --app blockster-db > migration-logs/current-databases.txt
flyctl postgres users list --app blockster-db > migration-logs/current-users.txt
```

---

## Pre-Migration Checklist

### 1. Create Migration Working Directory
```bash
mkdir -p ~/blockster-migration
cd ~/blockster-migration
mkdir -p backups logs verification
```

### 2. Check Current Database Size
```bash
flyctl postgres connect --app blockster-db

# Inside psql:
SELECT pg_size_pretty(pg_database_size('blockster_v2_prod'));
\l+ blockster_v2_prod
\dt+
\q
```

Document the size for planning the managed Postgres tier.

### 3. Check Active Connections
```bash
flyctl postgres connect --app blockster-db

# Inside psql:
SELECT count(*) as active_connections,
       usename,
       application_name
FROM pg_stat_activity
WHERE datname = 'blockster_v2_prod'
GROUP BY usename, application_name;
\q
```

### 4. Identify Critical Tables
```bash
# Get table row counts
flyctl postgres connect --app blockster-db

# Inside psql:
SELECT schemaname, tablename,
       n_live_tup as row_count,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC;
\q
```

Save this output to `logs/table-inventory.txt` for verification after migration.

### 5. Document Environment Variables
```bash
# Get current DATABASE_URL
flyctl secrets list --app blockster-v2 | grep DATABASE

# Save connection string format (mask password)
flyctl postgres config show --app blockster-db > logs/connection-config.txt
```

---

## Backup Procedures

### Method 1: Full Database Dump (Recommended)

#### Step 1: Create Dump Using pg_dump
```bash
# Connect to database and create full dump
flyctl postgres connect --app blockster-db --database blockster_v2_prod --command "pg_dump -Fc -v" > backups/blockster_v2_prod_$(date +%Y%m%d_%H%M%S).dump

# Alternative: SSH into the database machine and dump locally
flyctl ssh console --app blockster-db --select

# Inside the database machine:
pg_dump -Fc -v -U postgres blockster_v2_prod > /data/backups/full_backup_$(date +%Y%m%d_%H%M%S).dump

# Exit and copy backup to local machine
flyctl ssh sftp get /data/backups/full_backup_*.dump backups/
```

**Backup File Formats:**
- `-Fc` = Custom format (compressed, best for pg_restore)
- `-Fp` = Plain SQL format (human-readable)
- `-Fd` = Directory format (parallel dump/restore)

#### Step 2: Verify Backup Integrity
```bash
# Check backup file size (should be > 0 bytes)
ls -lh backups/

# Test backup validity
pg_restore --list backups/blockster_v2_prod_*.dump | head -20

# Count objects in backup
pg_restore --list backups/blockster_v2_prod_*.dump | wc -l
```

#### Step 3: Create Plain SQL Backup (for manual inspection)
```bash
flyctl postgres connect --app blockster-db --database blockster_v2_prod --command "pg_dump -v --inserts" > backups/blockster_v2_prod_$(date +%Y%m%d_%H%M%S).sql

# Compress for storage
gzip backups/blockster_v2_prod_*.sql
```

### Method 2: Fly.io Snapshot (Additional Layer)

```bash
# Create snapshot of database volume
flyctl volumes list --app blockster-db

# Take snapshot of each volume
flyctl volumes snapshots create <volume-id> --app blockster-db

# List snapshots to verify
flyctl volumes snapshots list <volume-id> --app blockster-db
```

**Important**: Snapshots are infrastructure-level backups. Always create logical backups (pg_dump) as well.

### Method 3: Per-Table Backup (for critical tables)

```bash
# Backup specific critical tables
flyctl postgres connect --app blockster-db --database blockster_v2_prod --command "pg_dump -t users -t sessions -t posts -Fc" > backups/critical_tables_$(date +%Y%m%d_%H%M%S).dump

# Backup Mnesia-related tables (if stored in Postgres)
flyctl postgres connect --app blockster-db --database blockster_v2_prod --command "pg_dump -t user_fingerprints -Fc" > backups/fingerprints_$(date +%Y%m%d_%H%M%S).dump
```

### Backup Verification Checklist

- [ ] Full database dump created and > 0 bytes
- [ ] Backup file passes `pg_restore --list` test
- [ ] Plain SQL backup created for emergency manual recovery
- [ ] Fly volume snapshot created
- [ ] Critical tables backed up separately
- [ ] All backup files stored in at least 2 locations (local + S3/cloud storage)
- [ ] Backup creation date/time documented in `logs/backup-manifest.txt`

### Upload Backups to Safe Storage

```bash
# Upload to S3 (if configured)
aws s3 cp backups/ s3://blockster-backups/postgres-migration-$(date +%Y%m%d)/ --recursive

# Or copy to another secure location
rsync -av backups/ user@backup-server:/secure-backups/blockster-postgres/
```

---

## Create Managed Postgres Cluster

### Step 1: Choose MPG Configuration

**Recommended Configuration for Blockster:**
- **Tier**: Development-1 (1x shared-cpu-1x, 256MB RAM) for testing
- **Tier**: Production-1 (1x shared-cpu-1x, 1GB RAM) or Production-4 (1x shared-cpu-1x, 4GB RAM) for production
- **Region**: `dfw` (same as current database)
- **HA**: Yes (2 machines minimum for production)

**Pricing Estimates** (as of Jan 2026):
- Development-1: ~$15/month
- Production-1: ~$29/month
- Production-4: ~$74/month

### Step 2: Create Managed Postgres App

```bash
# Create new managed Postgres cluster
flyctl postgres create \
  --name blockster-mpg \
  --region dfw \
  --vm-size shared-cpu-1x \
  --volume-size 10 \
  --initial-cluster-size 2

# IMPORTANT: Save the generated password and connection details!
# Output will include:
# - Username: postgres
# - Password: <generated-password>
# - Hostname: blockster-mpg.internal
# - Database: postgres (default)
```

**Save Connection Details**:
```bash
cat > logs/mpg-connection-details.txt <<EOF
Cluster Name: blockster-mpg
Region: dfw
Created: $(date)
Admin User: postgres
Admin Password: <SAVE THIS>
Internal Hostname: blockster-mpg.internal
Public Hostname: blockster-mpg.flycast
Database: postgres (default)
Connection String: postgres://postgres:<password>@blockster-mpg.internal:5432/postgres
EOF
```

### Step 3: Create Application Database

```bash
# Connect to new managed Postgres
flyctl postgres connect --app blockster-mpg

# Inside psql:
CREATE DATABASE blockster_v2_prod;
CREATE USER blockster_app WITH PASSWORD '<generate-strong-password>';
GRANT ALL PRIVILEGES ON DATABASE blockster_v2_prod TO blockster_app;

\c blockster_v2_prod
GRANT ALL ON SCHEMA public TO blockster_app;

\q
```

**Save App User Credentials**:
```bash
cat > logs/app-user-credentials.txt <<EOF
Application Database User
Username: blockster_app
Password: <SAVE THIS>
Database: blockster_v2_prod
Connection String: postgres://blockster_app:<password>@blockster-mpg.internal:5432/blockster_v2_prod
EOF
```

### Step 4: Configure Connection Pooling (PgBouncer)

Managed Postgres includes PgBouncer automatically. Configure pool settings:

```bash
flyctl postgres config update --app blockster-mpg \
  --max-client-conn 100 \
  --default-pool-size 20 \
  --min-pool-size 5
```

---

## Data Migration

### Method 1: Direct pg_restore (Recommended for < 10GB)

```bash
# Restore from custom format dump
flyctl postgres connect --app blockster-mpg --database blockster_v2_prod

# Use pg_restore in parallel mode for faster restore
pg_restore -v -j 4 -d blockster_v2_prod backups/blockster_v2_prod_*.dump

# Monitor progress in another terminal
flyctl logs --app blockster-mpg
```

**Flags Explained**:
- `-v`: Verbose output
- `-j 4`: Use 4 parallel jobs (adjust based on CPU cores)
- `-d blockster_v2_prod`: Target database

### Method 2: psql Restore (for plain SQL dumps)

```bash
# Decompress if needed
gunzip backups/blockster_v2_prod_*.sql.gz

# Restore via psql
flyctl postgres connect --app blockster-mpg --database blockster_v2_prod < backups/blockster_v2_prod_*.sql

# Monitor for errors
grep -i "error\|failed" logs/restore-output.log
```

### Method 3: Flyctl Migration Command (Experimental)

```bash
# Fly provides a migration helper (may not work for all versions)
flyctl postgres migrate \
  --source blockster-db \
  --target blockster-mpg \
  --database blockster_v2_prod
```

**Note**: This is experimental. Always verify data after migration.

### Monitor Migration Progress

```bash
# In separate terminal, watch logs
flyctl logs --app blockster-mpg -f

# Check restore progress (from psql session)
SELECT schemaname, tablename, n_live_tup
FROM pg_stat_user_tables
ORDER BY n_live_tup DESC;
```

---

## Update Application Configuration

### Step 1: Get New Database Connection String

```bash
flyctl postgres connect --app blockster-mpg --database blockster_v2_prod

# Note the connection details
# Internal hostname: blockster-mpg.internal
# Port: 5432
# Database: blockster_v2_prod
# User: blockster_app (or postgres for now)
```

### Step 2: Format New DATABASE_URL

```bash
# Format: postgres://user:password@hostname:5432/database

# For internal Fly.io connection (recommended):
DATABASE_URL="postgres://blockster_app:<password>@blockster-mpg.internal:5432/blockster_v2_prod?sslmode=disable"

# Or use PgBouncer port (6543) for connection pooling:
DATABASE_URL="postgres://blockster_app:<password>@blockster-mpg.internal:6543/blockster_v2_prod?sslmode=disable"
```

**Connection Pooling Note**:
- Port `5432` = Direct Postgres connection
- Port `6543` = PgBouncer pooled connection (recommended for web apps)

### Step 3: Update Fly Secrets (DO NOT DEPLOY YET)

```bash
# Set new DATABASE_URL secret
flyctl secrets set DATABASE_URL="postgres://blockster_app:<password>@blockster-mpg.internal:6543/blockster_v2_prod?sslmode=disable" --app blockster-v2 --stage

# Verify secret is staged but not deployed
flyctl secrets list --app blockster-v2
```

**Important**: Using `--stage` flag sets the secret but does NOT restart the app.

---

## Testing & Validation

### Step 1: Verify Data Integrity

#### Row Count Comparison
```bash
# On OLD database (blockster-db):
flyctl postgres connect --app blockster-db --database blockster_v2_prod

SELECT schemaname, tablename, n_live_tup
FROM pg_stat_user_tables
ORDER BY tablename;

\q

# On NEW database (blockster-mpg):
flyctl postgres connect --app blockster-mpg --database blockster_v2_prod

SELECT schemaname, tablename, n_live_tup
FROM pg_stat_user_tables
ORDER BY tablename;

\q

# Compare outputs - they should match!
```

Save both outputs and diff them:
```bash
diff verification/old-db-counts.txt verification/new-db-counts.txt
```

#### Schema Comparison
```bash
# Dump schema only from both databases
flyctl postgres connect --app blockster-db --command "pg_dump --schema-only blockster_v2_prod" > verification/old-schema.sql
flyctl postgres connect --app blockster-mpg --command "pg_dump --schema-only blockster_v2_prod" > verification/new-schema.sql

# Compare
diff verification/old-schema.sql verification/new-schema.sql
```

#### Critical Data Spot Checks
```bash
# Connect to NEW database
flyctl postgres connect --app blockster-mpg --database blockster_v2_prod

-- Check recent users
SELECT id, email, inserted_at FROM users ORDER BY inserted_at DESC LIMIT 10;

-- Check recent posts
SELECT id, title, slug, published_at FROM posts WHERE published_at IS NOT NULL ORDER BY published_at DESC LIMIT 10;

-- Check sessions count
SELECT count(*) FROM sessions WHERE expires_at > NOW();

-- Check critical constraints
SELECT conname, conrelid::regclass AS table_name
FROM pg_constraint
WHERE contype = 'f';

\q
```

### Step 2: Test Application Connection (Without Cutover)

#### Local Test with New DATABASE_URL
```bash
cd ~/Projects/blockster_v2

# Set new DATABASE_URL locally
export DATABASE_URL="postgres://blockster_app:<password>@blockster-mpg.flycast:6543/blockster_v2_prod?sslmode=disable"

# Run migrations (should show "Already up")
mix ecto.migrate

# Test database connection
iex -S mix

# In IEx:
BlocksterV2.Repo.query("SELECT count(*) FROM users")
BlocksterV2.Accounts.list_users() |> Enum.take(5)
exit()
```

#### Staging Environment Test (if available)
```bash
# Deploy to staging with new DATABASE_URL
flyctl secrets set DATABASE_URL="postgres://blockster_app:<password>@blockster-mpg.internal:6543/blockster_v2_prod?sslmode=disable" --app blockster-v2-staging

# Monitor logs
flyctl logs --app blockster-v2-staging -f

# Test critical flows:
# - User login
# - Post creation
# - Token operations (Mnesia + Postgres)
```

### Step 3: Performance Testing

```bash
# Run pgbench against new database
flyctl ssh console --app blockster-mpg

# Inside MPG machine:
pgbench -i blockster_v2_prod
pgbench -c 10 -j 2 -t 1000 blockster_v2_prod

# Compare results with old database baseline
```

---

## Cutover Process

### Pre-Cutover Checklist

- [ ] All backups verified and stored safely
- [ ] New managed Postgres cluster created and tested
- [ ] Data migration completed successfully
- [ ] Row counts match between old and new databases
- [ ] Schema comparison shows no unexpected differences
- [ ] Application connection tested locally
- [ ] Staging environment tested (if available)
- [ ] Rollback plan reviewed and understood
- [ ] Team notified of maintenance window
- [ ] Monitoring dashboard ready

### Cutover Steps (Planned Downtime)

**Maintenance Window**: Schedule during low-traffic period (e.g., 3 AM UTC)

#### Step 1: Enable Maintenance Mode (5-10 minutes before cutover)

```bash
# Scale down app to prevent new writes
flyctl scale count 0 --app blockster-v2

# Verify app is stopped
flyctl status --app blockster-v2
```

**Alternative**: Deploy a maintenance page:
```bash
# Deploy static maintenance HTML
flyctl deploy --app blockster-v2 --build-arg MAINTENANCE_MODE=true
```

#### Step 2: Final Database Sync (if data changed during testing)

```bash
# Take final incremental backup from old database
flyctl postgres connect --app blockster-db --database blockster_v2_prod --command "pg_dump -Fc -v" > backups/final_sync_$(date +%Y%m%d_%H%M%S).dump

# Restore only new data to managed Postgres
# This depends on your data - may need custom SQL for incremental sync
```

#### Step 3: Swap DATABASE_URL

```bash
# Remove staged secret and set it live
flyctl secrets set DATABASE_URL="postgres://blockster_app:<password>@blockster-mpg.internal:6543/blockster_v2_prod?sslmode=disable" --app blockster-v2

# This will trigger a rolling restart
# Monitor logs:
flyctl logs --app blockster-v2 -f
```

#### Step 4: Scale Up Application

```bash
# Scale back to normal capacity (2 machines)
flyctl scale count 2 --app blockster-v2

# Verify both machines started successfully
flyctl status --app blockster-v2
```

#### Step 5: Health Checks

```bash
# Check app health endpoint
curl https://v2.blockster.com/health

# Check database connectivity from app logs
flyctl logs --app blockster-v2 | grep -i "database\|postgres\|ecto"

# Test critical functionality:
# - User login
# - Browse posts
# - Token balances loading
# - BUX Booster (if Mnesia syncs properly)
```

#### Step 6: Monitor Production

```bash
# Watch logs for 15-30 minutes
flyctl logs --app blockster-v2 -f

# Watch for errors:
# - Connection errors
# - Timeout errors
# - Postgrex protocol violations
# - Failed queries

# Monitor database connections
flyctl postgres connect --app blockster-mpg --database blockster_v2_prod

SELECT count(*), state, usename
FROM pg_stat_activity
WHERE datname = 'blockster_v2_prod'
GROUP BY state, usename;

\q
```

### Success Criteria

- [ ] Application started successfully on both machines
- [ ] No database connection errors in logs (15+ minutes)
- [ ] Users can log in successfully
- [ ] Posts load correctly
- [ ] Token balances display properly
- [ ] BUX Booster game functions
- [ ] No black screen issues
- [ ] Database connection count stable (not growing unbounded)

---

## Rollback Procedures

**If migration fails, rollback immediately using this process:**

### Rollback Steps

#### 1. Stop Application (Prevent Data Loss)
```bash
flyctl scale count 0 --app blockster-v2
```

#### 2. Restore Old DATABASE_URL
```bash
# Get old connection string from backup
cat logs/connection-config.txt

# Set old DATABASE_URL back
flyctl secrets set DATABASE_URL="postgres://postgres:<old-password>@blockster-db.internal:5432/blockster_v2_prod" --app blockster-v2
```

#### 3. Scale Application Back Up
```bash
flyctl scale count 2 --app blockster-v2

# Verify app connects to old database
flyctl logs --app blockster-v2 | grep "Ecto"
```

#### 4. Verify Rollback Success
```bash
# Test application
curl https://v2.blockster.com/health

# Check database connectivity
flyctl logs --app blockster-v2 | grep -i "database"
```

#### 5. Investigate Migration Failure
```bash
# Review logs from failed migration
flyctl logs --app blockster-v2 > logs/failed-migration-logs.txt
flyctl logs --app blockster-mpg > logs/mpg-failure-logs.txt

# Check for specific error patterns
grep -i "error\|timeout\|crash" logs/*.txt
```

### Common Rollback Scenarios

**Scenario 1: Connection Timeout Errors**
- Symptoms: App can't connect to new database
- Solution: Check DATABASE_URL format, verify internal hostname, check security groups

**Scenario 2: Missing Data/Schema Issues**
- Symptoms: Queries fail, tables not found
- Solution: Rollback and re-run pg_restore with verbose logging

**Scenario 3: Performance Degradation**
- Symptoms: Slow queries, high CPU on database
- Solution: Rollback, analyze query plans, consider larger MPG tier

---

## Post-Migration Tasks

### Immediate (Day 1)

#### 1. Update Documentation
```bash
# Update CLAUDE.md with new database details
```

Update the "Deployment" section with new managed Postgres info.

#### 2. Remove Old DATABASE_URL References
```bash
# Search for hardcoded connection strings
grep -r "blockster-db" ~/Projects/blockster_v2/config/
grep -r "blockster-db" ~/Projects/blockster_v2/lib/
```

#### 3. Configure Monitoring

```bash
# Set up alerts for database issues
flyctl postgres monitor --app blockster-mpg

# Configure alerts via Fly.io dashboard:
# - High connection count (> 80% of max)
# - Query latency > 1 second
# - Disk usage > 80%
# - CPU usage > 80%
```

#### 4. Document New Backup Strategy

```bash
# Managed Postgres has automatic backups
# Configure backup retention
flyctl postgres config update --app blockster-mpg --backup-retention 7

# Document backup schedule
cat > docs/backup-schedule.md <<EOF
# Backup Schedule

**Automatic Backups** (Managed Postgres):
- Daily full backups at 3 AM UTC
- Retention: 7 days
- Point-in-time recovery: Last 7 days

**Manual Backups**:
- Before major deployments
- Before schema migrations
- Weekly full export to S3

**Backup Command**:
flyctl postgres backup create --app blockster-mpg
EOF
```

### Week 1

#### 1. Performance Tuning

```bash
# Analyze query performance
flyctl postgres connect --app blockster-mpg --database blockster_v2_prod

-- Enable query stats extension
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;

-- Check slowest queries
SELECT query, calls, total_time, mean_time
FROM pg_stat_statements
ORDER BY mean_time DESC
LIMIT 10;

\q
```

#### 2. Optimize Indexes

```bash
# Check for missing indexes
flyctl postgres connect --app blockster-mpg --database blockster_v2_prod

-- Find sequential scans on large tables
SELECT schemaname, tablename, seq_scan, seq_tup_read, idx_scan, idx_tup_fetch
FROM pg_stat_user_tables
WHERE seq_scan > 0
ORDER BY seq_tup_read DESC;

-- Create recommended indexes based on query patterns
\q
```

#### 3. Review Connection Pool Settings

```bash
# Check actual connection usage
flyctl postgres connect --app blockster-mpg --database blockster_v2_prod

SELECT count(*), state
FROM pg_stat_activity
WHERE datname = 'blockster_v2_prod'
GROUP BY state;

\q

# Adjust pool_size in runtime.exs if needed
```

### Week 2-4

#### 1. Decommission Old Database

**WARNING**: Only after confirming managed Postgres is stable!

```bash
# Final backup of old database (paranoid safety)
flyctl postgres connect --app blockster-db --database blockster_v2_prod --command "pg_dump -Fc -v" > backups/final_old_db_$(date +%Y%m%d).dump

# Destroy old database cluster
flyctl apps destroy blockster-db

# Confirm with team first!
```

#### 2. Cost Analysis

```bash
# Compare costs
flyctl billing show

# Document savings/increase in monthly budget
```

#### 3. Update Disaster Recovery Plan

Update disaster recovery documentation with:
- New backup locations
- New restore procedures
- New escalation contacts for Fly.io support

---

## Troubleshooting

### Issue 1: Connection Pool Exhausted

**Symptoms**:
```
[error] Postgrex.Protocol (#PID<0.2294.0>) disconnected
** (DBConnection.ConnectionError) connection not available
```

**Solutions**:
```bash
# Option 1: Increase pool_size in runtime.exs
pool_size: String.to_integer(System.get_env("POOL_SIZE") || "20")

# Option 2: Use PgBouncer port (6543 instead of 5432)
DATABASE_URL="postgres://user:pass@blockster-mpg.internal:6543/db"

# Option 3: Increase max_connections on MPG
flyctl postgres config update --app blockster-mpg --max-client-conn 200
```

### Issue 2: Slow Queries After Migration

**Symptoms**: Queries that were fast on old database are slow on new database.

**Solutions**:
```bash
# Analyze query plans
flyctl postgres connect --app blockster-mpg --database blockster_v2_prod

EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'test@example.com';

-- Update statistics
ANALYZE;

-- Rebuild indexes
REINDEX DATABASE blockster_v2_prod;

\q
```

### Issue 3: SSL/TLS Connection Errors

**Symptoms**:
```
[error] SSL connection error: certificate verify failed
```

**Solutions**:
```bash
# Add sslmode parameter to DATABASE_URL
DATABASE_URL="postgres://user:pass@host:5432/db?sslmode=disable"

# Or for production (with SSL):
DATABASE_URL="postgres://user:pass@host:5432/db?sslmode=require"
```

### Issue 4: Data Inconsistency After Migration

**Symptoms**: Row counts don't match, missing records.

**Solutions**:
```bash
# Identify missing records
flyctl postgres connect --app blockster-db --database blockster_v2_prod

-- Get max ID from old database
SELECT MAX(id) FROM users;

\q

flyctl postgres connect --app blockster-mpg --database blockster_v2_prod

-- Compare with new database
SELECT MAX(id) FROM users;

\q

# If data is missing, restore from backup and re-migrate
pg_restore -v --data-only -t users backups/blockster_v2_prod_*.dump
```

### Issue 5: PgBouncer Connection Issues

**Symptoms**: Intermittent connection drops, "server conn crashed" errors.

**Solutions**:
```bash
# Configure PgBouncer settings
flyctl postgres config update --app blockster-mpg \
  --pool-mode transaction \
  --default-pool-size 25 \
  --min-pool-size 10 \
  --reserve-pool-size 5

# Or switch to direct connection (port 5432) instead of PgBouncer (6543)
```

---

## Emergency Contacts

**Fly.io Support**:
- Email: support@fly.io
- Community Forum: https://community.fly.io
- Discord: https://fly.io/discord

**Escalation**:
- Fly.io Priority Support (if subscribed)
- PostgreSQL DBA consultant (if needed)

---

## Migration Checklist Summary

### Pre-Migration
- [ ] All backups created and verified
- [ ] New managed Postgres cluster provisioned
- [ ] Team notified of maintenance window
- [ ] Rollback plan reviewed

### Migration
- [ ] Application scaled down
- [ ] Data migrated via pg_restore
- [ ] Data integrity verified
- [ ] DATABASE_URL updated
- [ ] Application scaled back up
- [ ] Health checks passing

### Post-Migration
- [ ] Monitoring configured
- [ ] Performance baseline established
- [ ] Documentation updated
- [ ] Old database scheduled for decommission
- [ ] Team trained on new procedures

---

## Notes

- This migration guide is specific to Blockster's infrastructure as of January 2026
- Postgres version: Old = 14.6, New = Latest managed version
- Always test in staging before production migration
- Keep old database running for 2-4 weeks before decommissioning
- Budget 2-4 hours for full migration process

**Document Version**: 1.0
**Last Updated**: January 27, 2026
**Author**: Claude Sonnet 4.5
