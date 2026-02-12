# Reward Abuse Detection System

## Context

User 141 is exploiting reading rewards by automating `article-read` WebSocket events across all posts (~8.4 BUX every 5 seconds). Server-side time validation (already applied) prevents faking `time_spent`, but scroll depth can still be spoofed. Need a detection system that flags and blocks suspicious reward velocity.

## Approach: ETS-based Reward Rate Limiter

### Thresholds
- **Max 5 read rewards per 10-minute window** per user
- When exceeded: silently block further read rewards, log warning
- Self-cleaning: old timestamps filtered on every check

### ETS Empty Table Safety
An empty table is safe because:
- `:ets.lookup(table, key)` returns `[]` on empty table (no error)
- `[]` → empty timestamp list → `length([]) < 5` → `:ok` → reward proceeds
- Fallback: `check_reward_rate_limit` calls `init_rate_limiter()` if table missing (same pattern as BuxMinter dedup at bux_minter.ex:440)

### Files to Modify

**1. `lib/blockster_v2/engagement_tracker.ex`**
- Add module attrs: `@rate_limit_table`, `@rate_limit_window` (600s), `@rate_limit_max_rewards` (5)
- Add `init_rate_limiter/0` — creates ETS table `:reward_rate_limiter`
- Add `check_reward_rate_limit/1` — checks timestamp count in window, returns `:ok` or `{:rate_limited, count}`
- Add `record_reward_timestamp/1` — appends current timestamp to user's list
- Modify `record_read_reward/4` — call `check_reward_rate_limit` before recording; if limited, return `{:rate_limited, count}`

**2. `lib/blockster_v2/application.ex`**
- Add `EngagementTracker.init_rate_limiter()` next to existing `BuxMinter.init_dedup_table()`

**3. `lib/blockster_v2_web/live/post_live/show.ex`**
- Add `{:rate_limited, _}` clause in `handle_event("article-read", ...)` after `record_read_reward` call
- Show 0 BUX earned silently (don't reveal to attacker)

## Verification
1. `mix compile --no-deps-check` — no errors
2. Deploy and check logs for `[RewardRateLimit]` warnings
3. Attacker's rewards stop after 5th article in 10 min window
