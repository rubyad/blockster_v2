# Production Outage Report — Feb 25-26, 2026

## Duration
~33 hours (Feb 25 ~21:00 UTC to Feb 26 ~06:05 UTC)

## Root Cause
**The `:keepalive` TCP socket option in Ecto Repo config kills IPv6 connections on Fly.io's internal network.**

The Repo was configured with `socket_options: [:inet6, :keepalive]`. When Postgrex opens a TCP connection with both `:inet6` and `:keepalive`, the connection process is killed within ~50ms. This caused the Repo to crash-loop silently (zero Postgrex error output), exhausting the supervisor's max_restarts budget and shutting down the entire application.

## Why it was hard to find

1. **Zero error output** — The connection process was killed before Postgrex could log anything, even with `show_sensitive_data_on_connection_error: true` and `log: :debug`
2. **SIGUSR1 red herring** — Fly's init process reaped dead child processes with SIGUSR1 during cleanup, which initially appeared to be the cause
3. **Manual tests worked** — `Repo.start_link` via SSH eval worked because the Repo linked to the eval process, which masked the crash timing
4. **Multiple concurrent issues** — Oban's Postgres notifier (incompatible with PgBouncer), MnesiaInitializer race conditions, and default supervisor max_restarts all created additional crash pressure that obscured the root cause

## The Fix (3 changes)

1. **Removed `:keepalive` from socket_options** — `socket_options: maybe_ipv6` instead of `socket_options: maybe_ipv6 ++ [:keepalive]`
2. **Added `ERL_AFLAGS="-proto_dist inet6_tcp"` to Dockerfile** — Tells the BEAM VM to use IPv6 for Erlang distribution (Fly's `fly launch` normally generates this but our Dockerfile was missing it)
3. **Added `:os.set_signal(:sigusr1, :ignore)` in Application.start** — Prevents the BEAM from writing crash dumps and terminating when Fly's init sends SIGUSR1 to child processes during deployment

## Other fixes applied during debugging

- **Oban notifier**: Changed from `Oban.Notifiers.Postgres` to `Oban.Notifiers.PG` (compatible with PgBouncer transaction mode)
- **Oban peer**: Changed to `Oban.Peers.Global` (works with PgBouncer)
- **MnesiaInitializer**: Applied race condition fix (removes `:mnesia.stop()` calls that destroyed ETS tables)
- **Supervisor max_restarts**: Increased to `500/30s` (default `3/5s` was far too low for startup)
- **seed_defaults delay**: Increased from 1s to 5s (Repo needs more time to initialize)

## How it was diagnosed

The breakthrough came from SSH testing with `Process.flag(:trap_exit, true)`:

```elixir
# WORKS — alive after 3s
Postgrex.start_link(hostname: hostname, socket_options: [:inet6])

# KILLED in 49ms
Postgrex.start_link(hostname: hostname, socket_options: [:inet6, :keepalive])
```

This isolated `:keepalive` as the sole cause of the connection failures.

## Timeline

| Time (UTC) | Event |
|------------|-------|
| Feb 25 ~21:00 | Deploy v290 (login URL fix) — app starts crash-looping |
| Feb 25 21:00-23:00 | Initial debugging: Oban crash cascade identified |
| Feb 26 00:00-02:00 | Rolled back to v289 code — still crashes (not our code) |
| Feb 26 02:00-04:00 | Disabled Oban, tweaked Repo settings, applied Mnesia fix — still crashes |
| Feb 26 04:00-05:00 | Disabled Repo — app stable (serving 500s). Confirmed Repo is sole crash source |
| Feb 26 05:00-05:30 | Added `ERL_AFLAGS` to Dockerfile — endpoint starts but SIGUSR1 kills app |
| Feb 26 05:30-05:50 | Added SIGUSR1 ignore — app survives signal but Repo still crash-loops |
| Feb 26 05:55-05:58 | SSH diagnostics with `trap_exit` — **found `:keepalive` is the killer** |
| Feb 26 05:58-06:05 | Removed `:keepalive`, re-enabled Repo — **app fully operational** |

## Lessons Learned

1. **TCP `:keepalive` + `:inet6` is broken on Fly.io** — The combination kills connections instantly with no error output. Use `:inet6` alone.
2. **Fly Dockerfiles need `ERL_AFLAGS="-proto_dist inet6_tcp"`** — This is normally added by `fly launch` but can be lost if the Dockerfile is manually created or regenerated.
3. **SIGUSR1 in Erlang triggers crash dumps** — The BEAM's default SIGUSR1 handler writes a crash dump and exits. On Fly, child processes may receive SIGUSR1 during deployment cleanup. Ignoring this signal prevents spurious crashes.
4. **Silent crash-loops are the hardest to debug** — When a process is killed before it can log anything, standard debugging tools (error logging, `show_sensitive_data_on_connection_error`) are useless. The key technique is `Process.flag(:trap_exit, true)` to capture EXIT reasons.
5. **Multiple concurrent issues compound debugging** — Oban crashes, Mnesia races, and low max_restarts all created noise that obscured the root cause. Disabling systems one by one was essential.
