# Deploy Incident - Feb 25, 2025

## Timeline

### Pre-incident state
- **Production version**: v289, running stable since Feb 23
- **Machines**: 2 machines in `ord` region, both running fine
- **Database**: Fly Managed Postgres (MPG) cluster `z23750vxk45r96d1` with PgBouncer
- **Branch**: `feat/notification-system`

---

### 1. Original Bug Fix (login URL)
**Problem**: Clicking "Subscribe" on hub page when not logged in redirected to `/users/log_in` (dead route). Correct route is `/login`.

**Files changed**:
- `lib/blockster_v2_web/live/hub_live/show.ex` line 149: `/users/log_in` → `~p"/login"`
- `lib/blockster_v2_web/live/post_live/show.html.heex` line 594: same fix

**Committed**: `5e8f6db` on `feat/notification-system`, pushed.

---

### 2. First Deploy Attempt — release_command failure
```
flyctl deploy --app blockster-v2
```
**Result**: Failed. The release_command (`/app/bin/migrate`) runs on an ephemeral machine that crashed every time within ~1 second with `** (EXIT from #PID<0.98.0>) shutdown`. The ephemeral machine has no volume mount (`/data` doesn't exist).

Verified migrations are already up via SSH: "Migrations already up".

**Fix**: Commented out `release_command` in `fly.toml`:
```toml
[deploy]
  # release_command = '/app/bin/migrate'
```

---

### 3. Second Deploy — Oban Notifier crash
**Result**: Deploy succeeded but app crashed immediately with:
```
[error] Oban could not start because: no notifier running for instance Oban
```

**Root cause**: Oban's default `Oban.Notifiers.Postgres` uses PostgreSQL `LISTEN/NOTIFY`. The app uses PgBouncer in transaction mode (`prepare: :unnamed`), which doesn't support `LISTEN/NOTIFY`. This was a **latent bug** — machines hadn't been restarted since Feb 23, so existing Oban processes were still running from before the PgBouncer migration.

**Fix**: Added to `config/config.exs`:
```elixir
config :blockster_v2, Oban,
  repo: BlocksterV2.Repo,
  notifier: Oban.Notifiers.PG,  # Uses Distributed Erlang PG instead of LISTEN/NOTIFY
```
**Committed**: `0d09b8c`

---

### 4. Third Deploy — Oban Peers crash
**Result**: Oban notifier fixed, but `Oban.Peers.Database` crashed with DBConnection checkout failures.

**First attempt**: Changed to `peer: Oban.Peers.PG` — **DOES NOT EXIST** in open-source Oban (Pro-only). Got error: `expected :peer to be one of [:falsy, {:behaviour, Oban.Peer}]`

**Committed bad version**: `496e879`

**Fix**: Changed to `peer: Oban.Peers.Global` (uses Erlang `:global` module).
**Committed**: `e785ba5`

---

### 5. Fourth Deploy — App exits in 35ms
**Result**: Both machines started, endpoint came up, then `Application blockster_v2 exited: shutdown` within 35ms.

**Root cause**: Default supervisor `max_restarts: 3, max_seconds: 5` was too low. Multiple processes crash during startup (Mnesia race condition, DB connection establishment) and exceed the limit.

**Fix**: Increased supervisor tolerance in `application.ex`:
```elixir
opts = [strategy: :one_for_one, name: BlocksterV2.Supervisor, max_restarts: 50, max_seconds: 10]
```
**Committed**: `188cef5`

---

### 6. Fifth Deploy — HubLogoCache crash
**Result**: Machines stayed up longer but crashed with:
```
GenServer BlocksterV2.HubLogoCache terminating
** (ArgumentError) ets.lookup_element(Ecto.Repo.Registry, ...)
```

**Root cause**: HubLogoCache fires `:load_initial` after 100ms delay, but Ecto Repo may not be registered yet.

**Fix** (NOT committed at this point):
- Increased delay from 100ms to 2000ms
- Added try/rescue with retry in `handle_info(:load_initial, ...)`

---

### 7. Mnesia Data Corruption
After 20+ minutes of crash loops, Mnesia disc copies got corrupted. Specifically `user_post_rewards.DCD` showed `invalid continuation` errors during `mnesia_loader.do_get_disc_copy2`.

**Impact**: `user_post_rewards` table (BUX rewards tracking). On-chain balances unaffected.

**Fix**: Deleted corrupted `.DCD` file on both machines via SSH:
```bash
flyctl ssh console --app blockster-v2 -C "rm /data/mnesia/blockster/user_post_rewards.DCD"
```

---

### 8. Mnesia Race Condition (root cause of crash loops)
**Problem**: `MnesiaInitializer.initialize_with_persistence/0` at line 677 called `:mnesia.stop()` "for clean restart" BEFORE waiting 5 seconds for cluster discovery. This destroyed all ETS tables. Other processes (BuxBoosterBetSettler, Oban, etc.) accessing Mnesia tables during this window crashed with `ArgumentError: the table identifier does not refer to an existing ETS table`.

**Fix**: Removed the eager `:mnesia.stop()` call. Mnesia is already running with the correct directory (configured in `runtime.exs`). Only stop Mnesia in the specific code path that requires schema migration (node name mismatch).

**Files changed**:
- `lib/blockster_v2/mnesia_initializer.ex`: Removed `:mnesia.stop()` from `initialize_with_persistence/0`, updated `initialize_as_primary_node/0` to check if Mnesia is already running, updated `join_cluster_fresh/0` and `safe_join_preserving_local_data/0` to use new `ensure_mnesia_running/0` helper, fixed `start_mnesia_and_create_tables/0` to handle `{:error, {:already_started, :mnesia}}`

**Committed**: `5b3725d` (includes HubLogoCache fix, fly.toml release_command disable, and Mnesia fix)

---

### 9. Cached Build Problem
**Result**: First deploy of commit `5b3725d` used Docker layer cache (Depot remote builder). ALL build steps showed `CACHED`, meaning the code changes were NOT included in the image. Deploy used the old broken code.

**Fix**: Redeployed with `--no-cache`:
```bash
flyctl deploy --app blockster-v2 --no-cache
```
This produced a fresh build (v324). Both machines passed health checks during deploy.

---

### 10. Both Machines Crash ~10s After Startup
**Result**: With the fresh build (v324), MnesiaInitializer completed successfully ("All tables ready", "Successfully joined cluster and synced tables"). But both machines crashed simultaneously within milliseconds:
```
Application blockster_v2 exited: shutdown
```

**Key observation**: Both machines crash at the EXACT SAME millisecond. The crash happens right after Mnesia initialization connects the two nodes.

**Hypothesis**: Cluster interaction (Oban.Peers.Global election, Mnesia cross-node sync) triggers cascading failures.

---

### 11. Scale to 1 Machine
**Action**: Scaled to 1 machine to eliminate cluster interactions:
```bash
flyctl scale count 1 --app blockster-v2 --yes
```
Destroyed machine `865d14fe30d228`.

**Result**: STILL CRASHING. Single machine crashes ~16-20 seconds after boot. Same error:
```
GenServer {Oban.Registry, {Oban, Oban.Stager}} terminating
** (stop) exited in: DBConnection.Holder.checkout(...)
    ** (EXIT) killed
```
Followed by:
```
Mnesia: ** ERROR ** :mnesia_controller got unexpected info: {:EXIT, #PID<0.2765.0>, :killed}
Application blockster_v2 exited: shutdown
```

This proved the crash is NOT a cluster issue.

---

### 12. Database DNS Discovery
**Action**: Tested DB connection from inside the machine:
```bash
flyctl ssh console --app blockster-v2 -C 'bin/blockster_v2 eval "..."'
```

**Result**: `nxdomain` — the PgBouncer hostname `pgbouncer.z23750vxk45r96d1.flympg.net` does NOT resolve from inside the machine.

**This is the root cause of the Repo crash**: Postgrex can't connect to the database because DNS doesn't resolve the hostname.

---

### 13. MPG Detachment Investigation
```bash
flyctl mpg list --org personal
```
Showed `<no attached apps>` for the MPG cluster. The app appeared to be detached.

**Actions taken**:
1. Unset DATABASE_URL: `flyctl secrets unset DATABASE_URL` — this redeployed the machine WITHOUT a DATABASE_URL, causing `RuntimeError: environment variable DATABASE_URL is missing`
2. Re-attached: `flyctl mpg attach z23750vxk45r96d1 --app blockster-v2` — set the same URL back, but the secret was `Staged` not `Deployed`
3. Deployed secrets: `flyctl secrets deploy` — deployed the staged secret
4. MPG now shows `blockster-v2` in ATTACHED APPS column

**Result**: STILL CRASHING with same `Ecto.Repo.Registry` lookup error.

---

### 14. Direct IPv6 Address Attempt
**Action**: Set DATABASE_URL to use direct IPv6 address instead of hostname:
```
DATABASE_URL=postgresql://fly-user:...@[fdaa:0:9cc8:0:1::e]:5432/fly-db
```

**Result**: STILL CRASHING. Same error.

---

### 15. ECTO_IPV6 Discovery
**Action**: Checked if `ECTO_IPV6` env var is set — it was NOT.

In `runtime.exs` line 159:
```elixir
maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []
```
Without `ECTO_IPV6=true`, the `socket_options` don't include `:inet6`, so Postgrex tries IPv4 only. But the MPG address is IPv6.

**Action**: Set `ECTO_IPV6=true` via secrets (tried with both hostname and direct IP).

**Result**: STILL CRASHING.

---

### 16. Direct Postgrex Test — SUCCESS
**Action**: Tested direct Postgrex connection from inside the machine:
```elixir
Postgrex.start_link(
  hostname: "fdaa:0:9cc8:0:1::e",
  database: "fly-db",
  username: "fly-user",
  password: "...",
  port: 5432,
  socket_options: [:inet6]
)
```

**Result**: `{:ok, %Postgrex.Result{rows: [[1]]}}` — **DB CONNECTION WORKS**.

But `Repo.query("SELECT 1")` from the running app returns: `could not lookup Ecto repo BlocksterV2.Repo because it was not started or it does not exist`

---

## Current State (as of ~23:45 UTC)

### What's deployed
- **Image**: v324 (fresh build with all fixes)
- **Machine**: 1 machine (`17817e62f16438`), version 330
- **Secrets**: `DATABASE_URL=postgresql://fly-user:...@[fdaa:0:9cc8:0:1::e]:5432/fly-db`, `ECTO_IPV6=true`
- **Machine 865d**: Destroyed (scaled to 1)

### What's committed (on `feat/notification-system`)
- `5e8f6db` — Login URL fix
- `0d09b8c` — Oban PG notifier
- `496e879` — Oban PG peer (broken, then fixed)
- `e785ba5` — Oban.Peers.Global
- `188cef5` — Supervisor max_restarts: 50
- `5b3725d` — Mnesia race condition fix + HubLogoCache retry + fly.toml release_command disabled

### What's NOT committed
- DATABASE_URL and ECTO_IPV6 secrets changes (Fly secrets, not in code)

### The current crash pattern
1. Machine boots, BEAM starts
2. Application supervisor starts children (Repo, PubSub, Mnesia, Oban, etc.)
3. Repo supervision tree starts (pool created) but connections fail silently (lazy connect)
4. Oban.Stager fires `:stage` message, tries DB transaction
5. `Ecto.Repo.Registry.lookup/1` fails — the Repo PID is not in the ETS registry
6. Oban.Stager crashes, other Oban processes crash
7. 50+ crashes in 10 seconds → supervisor gives up → `Application blockster_v2 exited: shutdown`
8. Machine restarts, cycle repeats

### The puzzle
- **Direct Postgrex with `socket_options: [:inet6]` WORKS** from the same machine
- **The Repo does NOT start** even though `ECTO_IPV6=true` is set and `runtime.exs` reads it
- The app worked fine on v289 for 2 days without `ECTO_IPV6` — meaning the hostname used to resolve via IPv4 or something else changed

### Possible explanations
1. **`runtime.exs` is baked into the release at build time** — the `ECTO_IPV6` env var is read when the release boots, but the release was built WITHOUT it. The `--no-cache` build happened before `ECTO_IPV6` was set as a secret. The runtime.exs DOES read env vars at boot (not compile), but maybe there's a caching issue.
2. **URL parsing issue** — Postgrex may not parse `[fdaa:0:9cc8:0:1::e]` from a URL string the same way it handles a `hostname:` option directly.
3. **Something else changed in Fly.io's infrastructure** — the MPG PgBouncer hostname used to resolve but no longer does. The app was running on stale connections since Feb 23.

### Files modified in this session
| File | Changes |
|------|---------|
| `lib/blockster_v2_web/live/hub_live/show.ex` | Login URL fix |
| `lib/blockster_v2_web/live/post_live/show.html.heex` | Login URL fix |
| `config/config.exs` | Oban PG notifier + Global peer |
| `lib/blockster_v2/application.ex` | max_restarts: 50, max_seconds: 10 |
| `lib/blockster_v2/hub_logo_cache.ex` | Retry on Repo not ready, 2s delay |
| `lib/blockster_v2/mnesia_initializer.ex` | Removed early mnesia.stop(), ensure_mnesia_running helper |
| `fly.toml` | release_command commented out |

### Secrets changed
| Secret | Change |
|--------|--------|
| `DATABASE_URL` | Unset then re-set (same value, then changed to direct IPv6) |
| `ECTO_IPV6` | Added (set to `true`) |
