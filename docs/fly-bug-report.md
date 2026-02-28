# Fly.io Bug Report — Managed Postgres Connection Failure After Deploy (UPDATED)

**App**: `blockster-v2`
**Organization**: `adam-todd` (personal)
**MPG Cluster**: `z23750vxk45r96d1` (`blockster-v2-pg`)
**Region**: `ord`
**Date**: February 25-26, 2026
**Severity**: Production down — app has been down for hours
**Status**: App running with database DISABLED (serving 500 errors)

---

## Summary

After deploying a routine code change to `blockster-v2`, the Ecto Repo (Postgrex connection pool) crashes silently during application startup, causing the supervisor to exceed max_restarts and shut down the app. We have spent 24 hours systematically isolating the problem and can now confirm:

1. **DNS resolution WORKS** — IPv6 resolves correctly from the running machine
2. **TCP connectivity WORKS** — `gen_tcp.connect` to PgBouncer succeeds
3. **Direct Postgrex WORKS** — `Postgrex.start_link` with the same config connects and queries
4. **The Ecto Repo pool crashes silently** — zero error logs from Postgrex despite `show_sensitive_data_on_connection_error: true` and `log: :debug`
5. **The app is stable WITHOUT the Repo** — we disabled the Repo and the app has been running for 2+ minutes serving HTTP requests (500s due to no DB)

The Repo's DBConnection pool supervisor crashes so rapidly it exhausts 500 max_restarts in under 30 seconds, with **no diagnostic output whatsoever**.

---

## Systematic Isolation Tests (Feb 26)

### Test 1: Confirm Repo is the sole crash source
- Removed `BlocksterV2.Repo` from the supervision tree entirely
- **Result**: App runs stable for 2+ minutes, endpoint serves HTTP requests
- **Conclusion**: The Repo is the ONLY thing crashing the app

### Test 2: Minimal supervision tree
- Stripped supervision tree to ONLY: Telemetry, Repo, DNSCluster, PubSub, Endpoint
- No Oban, no GenServers, no Mnesia — nothing else
- **Result**: App STILL crashes in 0.7 seconds
- **Conclusion**: It's not Oban's crash cascade causing the problem — the Repo itself is the crash source

### Test 3: Explicit hostname (bypass URL parsing)
- Changed from `url: database_url` to explicit params parsed from DATABASE_URL:
```elixir
db_uri = URI.parse(database_url)
config :blockster_v2, BlocksterV2.Repo,
  hostname: db_uri.host,
  username: db_username,
  password: db_password,
  database: db_name,
  port: db_port,
  socket_options: [:inet6, :keepalive],
  ...
```
- **Result**: Same crash. URL parsing was NOT the issue.

### Test 4: Verified config at runtime
Via `flyctl ssh console` RPC on the running app (with Repo disabled):
```elixir
Application.get_env(:blockster_v2, BlocksterV2.Repo)
# => [hostname: "pgbouncer.z23750vxk45r96d1.flympg.net",
#     socket_options: [:inet6, :keepalive],
#     pool_size: 5,
#     prepare: :unnamed,
#     ...]
```
Config is correct. `:inet6` is present. Hostname is correct.

### Test 5: DNS resolution from running machine
```elixir
:inet.getaddr(~c"pgbouncer.z23750vxk45r96d1.flympg.net", :inet6)
# => {:ok, {64682, 0, 40136, 0, 1, 0, 0, 16}}
# (fdaa:0:9cc8:0:1::10)
```
DNS resolves correctly via IPv6.

### Test 6: TCP connectivity from running machine
```elixir
:gen_tcp.connect(~c"pgbouncer.z23750vxk45r96d1.flympg.net", 5432, [:inet6, :binary, active: false], 5000)
# => {:ok, #Port<0.15>}
```
TCP connection to PgBouncer succeeds.

### Test 7: Direct Postgrex from eval session (earlier test)
```elixir
Postgrex.start_link(
  hostname: "fdaa:0:9cc8:0:1::e",
  database: "...", username: "...", password: "...",
  port: 5432, socket_options: [:inet6]
)
# => {:ok, #PID<...>}

Postgrex.query!(pid, "SELECT 1", [])
# => %Postgrex.Result{rows: [[1]]}
```
Direct Postgrex with the same config works perfectly.

### Test 8: Repo.start_link in eval isolation (earlier test)
```elixir
config = Application.get_env(:blockster_v2, BlocksterV2.Repo)
BlocksterV2.Repo.start_link(config)
# => {:ok, #PID<...>}

BlocksterV2.Repo.query("SELECT 1")
# => {:ok, %Postgrex.Result{rows: [[1]]}}
```
The Repo WORKS when started manually in eval. But it crashes when started by the supervision tree in a release.

### Test 9: Supervisor child inspection during crash loop
```elixir
Supervisor.which_children(BlocksterV2.Supervisor)
# Repo shows as ALIVE (pid exists)

Process.whereis(BlocksterV2.Repo)
# => nil
```
The Repo process exists in the supervisor but is NOT registered — it's in a rapid crash-restart cycle where it dies before registering its name.

### Test 10: No error logs
Despite configuring:
- `show_sensitive_data_on_connection_error: true`
- `log: :debug` (Postgrex option)
- `backoff_type: :rand_exp, backoff_min: 1_000, backoff_max: 15_000`

**ZERO Postgrex connection error messages appear in `flyctl logs`.** The pool crashes silently with no diagnostic output whatsoever. The only errors visible are from Oban trying to use the Repo and getting `"could not lookup Ecto repo BlocksterV2.Repo because it was not started or it does not exist"`.

---

## Current State

- **Machine**: 1x `performance-2x` (4GB) — `17817e62f16438`
- **Status**: Running stable (2+ min uptime) with Repo DISABLED
- **Second machine**: Destroyed (scaled to 1 for debugging)
- **Supervision tree**: Full (all GenServers, Oban, etc.) but no Repo
- **max_restarts**: 500 in 30 seconds (to survive Oban crashing without Repo)

### Current runtime.exs configuration (deployed)
```elixir
# Parse DATABASE_URL into explicit components
db_uri = URI.parse(database_url)
[db_username, db_password] = String.split(db_uri.userinfo || ":", ":", parts: 2)
db_name = String.trim_leading(db_uri.path || "/", "/")
db_hostname = db_uri.host
db_port = db_uri.port || 5432

config :blockster_v2, BlocksterV2.Repo,
  hostname: db_hostname,
  username: db_username,
  password: db_password,
  database: db_name,
  port: db_port,
  pool_size: 5,
  prepare: :unnamed,
  show_sensitive_data_on_connection_error: true,
  backoff_type: :rand_exp,
  backoff_min: 1_000,
  backoff_max: 15_000,
  queue_target: 50,
  queue_interval: 1000,
  timeout: 15000,
  connect_timeout: 15000,
  handshake_timeout: 15000,
  disconnect_on_error_codes: [:fatal],
  socket_options: [:inet6, :keepalive]
```

### Current application.ex (supervision tree)
```elixir
base_children = [
  BlocksterV2Web.Telemetry,
  # BlocksterV2.Repo,  # DISABLED — pool crashes silently
  {DNSCluster, query: ...},
  {Phoenix.PubSub, name: BlocksterV2.PubSub}
]

opts = [strategy: :one_for_one, name: BlocksterV2.Supervisor,
        max_restarts: 500, max_seconds: 30]
```

---

## The Core Mystery

Everything works in isolation:
- DNS resolves ✓
- TCP connects ✓
- Direct Postgrex connects and queries ✓
- Repo.start_link in eval connects and queries ✓

But when the Repo starts as part of the OTP supervision tree in the release:
- The pool crashes immediately with NO error output
- It dies and restarts so fast that `Process.whereis` returns nil
- Even with `backoff_min: 1_000` (1 second), 500 restarts are exhausted in under 30 seconds
- No Postgrex error messages appear despite debug configuration

**This suggests the crash is happening BEFORE Postgrex even attempts a TCP connection** — possibly during process initialization, ETS table creation, or some OTP registration step that fails silently.

---

## Questions for Fly.io Team

### 1. Is there a known issue with Ecto/Postgrex pool initialization on Fly machines?

The pool crashes before it can log anything. This is not a connection timeout or DNS issue — those would produce error logs. The crash happens during process startup itself.

### 2. When did MPG PgBouncer hostnames become IPv6-only?

The app ran without `:inet6` socket options from Feb 23 to Feb 25 with no issues. The PgBouncer hostname `pgbouncer.z23750vxk45r96d1.flympg.net` previously resolved via IPv4. It now only has AAAA records. Was there a DNS change?

### 3. Could there be a resource limit or memory issue during pool initialization?

The machine is `performance-2x` (4GB RAM, 2 CPUs). The pool_size is 5. Could there be a cgroup, ulimit, or file descriptor issue that prevents the pool supervisor from starting its child connections?

### 4. Is there anything different about the BEAM/OTP process environment in a release vs eval?

The key clue: `Repo.start_link(config)` works in an eval session on the SAME machine with the SAME config, but fails when started by the supervision tree in the compiled release. What's different about the process environment?

### 5. Release command ephemeral machine failure

Our `release_command = '/app/bin/migrate'` fails every time — the ephemeral machine crashes within ~1 second with `** (EXIT from #PID<0.98.0>) shutdown`. We have a volume mount at `/data` for Mnesia that the ephemeral machine doesn't receive. Is this expected?

### 6. MPG attachment state inconsistency

`flyctl mpg list` showed `<no attached apps>` for cluster `z23750vxk45r96d1` despite the app being deployed with `DATABASE_URL`. After re-attaching, it appeared. Was the cluster actually detached?

---

## What We've Tried

| Attempt | Result |
|---------|--------|
| Set `ECTO_IPV6=true` | Same crash |
| Hardcode `socket_options: [:inet6, :keepalive]` | Same crash |
| Switch from `url:` to explicit hostname/username/password | Same crash |
| Use direct IPv6 address instead of hostname | Same crash |
| Increase `max_restarts` to 500/30s | App survives longer but Repo still dead |
| Add `backoff_type: :rand_exp, backoff_min: 1_000` | Same crash rate |
| Minimal supervision tree (just Repo + Endpoint) | Crashes in 0.7s |
| Remove Repo entirely | **App stable** |
| DNS readiness check before Repo starts | DNS resolves fine, still crashes |
| `show_sensitive_data_on_connection_error: true` | Zero error output |
| `log: :debug` on Repo | Zero Postgrex logs |
| Deploy with `--no-cache` | Clean build, same crash |
| Re-attach MPG cluster | Same crash |
| Pool size reduced from 10 to 5 | Same crash |

---

## Environment Details

| Component | Version/Detail |
|-----------|---------------|
| Elixir | 1.17.x |
| Ecto | 3.13.2 |
| Postgrex | (bundled with Ecto 3.13.2) |
| Oban | 2.20.3 |
| DBConnection | 2.8.0 |
| Phoenix | 1.7.x |
| Bandit | 1.8.0 |
| flyctl | latest |
| VM Size | performance-2x (4GB, 2 CPUs) |
| MPG Plan | launch |
| MPG Replicas | 1 |
| MPG PgBouncer | pgbouncer.z23750vxk45r96d1.flympg.net |

### fly.toml
```toml
app = 'blockster-v2'
primary_region = 'ord'

[deploy]
  # release_command = '/app/bin/migrate'  # Disabled — ephemeral machine crashes

[env]
  PHX_HOST = 'blockster.com'
  PORT = '8080'
  DNS_CLUSTER_QUERY = 'blockster-v2.internal'

[mounts]
  source = 'mnesia_data'
  destination = '/data'

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = 'off'
  auto_start_machines = true
  min_machines_running = 1

[[vm]]
  size = 'performance-2x'
  memory = '4gb'
  cpus = 2
```

---

## What We Need

1. **Investigation into why the Ecto/Postgrex pool supervisor crashes silently** during release startup — this is the core issue
2. Confirmation of whether MPG PgBouncer DNS was changed to IPv6-only (and when)
3. Any known issues with DBConnection pool initialization on Fly machines
4. Whether release_command machines receive volume mounts
5. Any logs from the MPG PgBouncer side showing connection attempts or rejections from our app machine

The app has been down since ~21:00 UTC on Feb 25 (24+ hours). Any help is greatly appreciated.
