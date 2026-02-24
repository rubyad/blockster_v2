# Telegram Bot Hourly Engagement System

> **Status**: Implemented and ready for production deployment behind feature flag.

The Blockster V2 Bot posts every hour in the main Telegram group (`https://t.me/+7bIzOyrYBEc3OTdh`) with diverse promotions, giveaways, competitions, custom BUX Booster rules, and referral offers — driving users to the app to read, earn, and play.

### Safety Rules

1. **The bot CANNOT modify shop product prices, discounts, or inventory.**
2. **The bot CAN freely**: mint BUX, create/remove custom rules, boost referral rates, run giveaways, run competitions, send Telegram messages.
3. **Daily BUX budget: 100,000 BUX** — Hard limit across ALL promos. Tracked via `bot_daily_rewards` Mnesia table, resets at midnight UTC.
4. **Per-user daily reward limit: 10 rewards per Telegram user per day** — Enforced via daily counter in `bot_daily_rewards` Mnesia table.
5. **All bot-created rules tagged** with `source: "telegram_bot"` for safe cleanup on pause/settlement.

---

## Architecture

```
+--------------------------------------------------+
|           HourlyPromoScheduler (GenServer)        |
|  GlobalSingleton -- one instance across cluster   |
|                                                   |
|  Every hour:                                      |
|  1. Settle previous promo (pay winners, cleanup)  |
|  2. Pick next promo from weighted rotation        |
|  3. Activate promo (custom rule, boost rates)     |
|  4. Send announcement + pin to Telegram group     |
|  5. Announce previous promo results               |
|  6. Save state to Mnesia for crash recovery       |
|  7. Schedule next hour                            |
+-------------------+------------------------------+
                    |
        +-----------+-----------+
        v           v           v
  TelegramGroup  SystemConfig   BuxMinter
  Messenger      (custom rules) (credit BUX)
  (group msg +
   pin/unpin)
```

### Files

| File | Purpose |
|------|---------|
| `lib/blockster_v2/telegram_bot/hourly_promo_scheduler.ex` | GenServer — orchestrates hourly rotation |
| `lib/blockster_v2/telegram_bot/telegram_group_messenger.ex` | Sends HTML messages, pins/unpins announcements |
| `lib/blockster_v2/telegram_bot/promo_engine.ex` | Template library, weighted selection, activation, settlement, budget enforcement |
| `lib/blockster_v2/notifications/system_config.ex` | Stores/activates custom rules dynamically |
| `lib/blockster_v2/notifications/event_processor.ex` | Evaluates custom rules, credits BUX |
| `lib/blockster_v2/notifications/formula_evaluator.ex` | Safe formula parser: `random()`, `min()`, `max()`, arithmetic, variables |
| `lib/blockster_v2_web/controllers/telegram_webhook_controller.ex` | Admin commands: `/bot_pause`, `/bot_resume`, `/bot_status`, `/bot_budget`, `/bot_next` |
| `test/blockster_v2/telegram_bot/promo_engine_test.exs` | 47 tests — structural + integration |
| `config/runtime.exs` | Feature flag: `HOURLY_PROMO_ENABLED` env var |
| `lib/blockster_v2/application.ex` | Supervision tree (behind feature flag) |
| `lib/blockster_v2/mnesia_initializer.ex` | Creates 3 Mnesia tables |

---

## Promo Categories & Templates (15 total)

### Weighted Rotation

```elixir
@promo_weights [
  {:bux_booster_rule, 35},   # 35% -- game promos (core engagement)
  {:referral_boost, 25},      # 25% -- referral promos (growth)
  {:giveaway, 20},            # 20% -- random giveaways
  {:competition, 20}          # 20% -- hourly competitions
]
```

### Deduplication Rules
- Never run the same exact template twice in a row
- Max 2 of same category in a row
- Competition always alternates with non-competition
- Referral at least once every 4 hours (weight boosted to 50 if missing)
- BUX Booster at least once every 3 hours (weight boosted to 50 if missing)

---

### Category 1: BUX Booster Rules (7 templates)

All BUX Booster rules use a **profit-based formula pattern**:

```
reward = max(payout - bet_amount, bet_amount - payout) * PERCENT + rogue_balance * 0.0001
```

- **On WIN**: `payout - bet_amount` = profit (always positive since min multiplier is 1.02x)
- **On LOSS**: `payout = 0`, so `bet_amount - payout = stake`
- **ROGUE bonus**: 0.01% of ROGUE balance added as flat bonus (100k ROGUE = 10 BUX, 1M = 100 BUX)
- **No fixed cap** — daily budget (100k) and per-user limit (10/day) provide system-level caps

**ROGUE balance also affects trigger frequency** via `every_n_formula`:
- More ROGUE = lower N = triggers more often
- Divisors scaled for 100k-2M ROGUE range

**Available per-bet metadata** (from `game_played` event):
- `bet_amount` — BUX wagered on THIS bet
- `payout` — winnings (bet * multiplier on win, 0 on loss)
- `rogue_balance` — current ROGUE token balance
- `total_bets` — lifetime bet count (used as `count_field` for recurring)

| # | Template Name | Bonus % | Trigger Frequency | Conditions |
|---|--------------|---------|-------------------|------------|
| 1 | **Bet Bonus Blitz** | 20% | every 2-6 bets (ROGUE scales) | None |
| 2 | **Safety Net Hour** | 30% | every 3-8 bets (ROGUE scales) | None |
| 3 | **ROGUE Holders Hour** | 15% | every 1-5 bets (most aggressive for holders) | None |
| 4 | **High Roller Hour** | 25% | every 2-5 bets | bet_amount >= 500 |
| 5 | **Lucky Streak** | random 10-50% | random 2-7 bets | None |
| 6 | **Newbie Power Hour** | 40% | every 2-4 bets | total_bets <= 20 |
| 7 | **Mystery Jackpot** | random 50-100% | rare: every 4-10 bets | None |

**How activation works**: PromoEngine creates a custom rule in SystemConfig tagged with `_hourly_promo: true`, `_promo_id`, `source: "telegram_bot"`. EventProcessor picks it up and auto-credits BUX when `game_played` fires.

**How settlement works**: `cleanup_hourly_rules/1` removes the tagged rule from SystemConfig.

---

### Category 2: Referral Boost (3 templates)

The bot temporarily increases referral rates in SystemConfig for 1 hour, then restores originals.

| # | Template Name | Referrer | Referee | Phone Verify |
|---|--------------|----------|---------|--------------|
| 1 | **Double Referral Hour** | 1,000 BUX (2x) | 500 BUX (2x) | 1,000 BUX (2x) |
| 2 | **Triple Threat Referral** | 1,500 BUX (3x) | 750 BUX (3x) | 1,500 BUX (3x) |
| 3 | **Mega Referral Hour** | 1,000 BUX (2x) | 500 BUX (2x) | 1,000 BUX (2x) |

**How activation works**: Original rates saved to `hourly_promo_state` Mnesia table under `:referral_originals` key. Boosted rates written to SystemConfig.

**How settlement works**: Original rates read from Mnesia and restored to SystemConfig. Falls back to defaults (500/250/500) if Mnesia record missing.

---

### Category 3: Giveaways (3 templates)

| # | Template Name | Type | Winners | Prize |
|---|--------------|------|---------|-------|
| 1 | **BUX Rain** | activity_based (`article_view`) | 5 | 100-500 BUX each |
| 2 | **Snapshot Giveaway** | auto_entry (all group members) | 3 | 250-400 BUX each |
| 3 | **New Member Welcome Drop** | new_members (joined in last hour) | All new | 1,000 BUX each |

**How settlement works**:
- **auto_entry**: Queries all users with `telegram_group_joined_at NOT NULL` + `smart_wallet_address NOT NULL`, randomly picks winners
- **activity_based**: Queries `UserEvent` table for `event_type` within the promo hour, randomly picks from active users
- **new_members**: Queries users with `telegram_group_joined_at >= promo.started_at`, credits all of them

All winners credited via `PromoEngine.credit_user/2` which enforces budget + per-user limits and calls `BuxMinter.mint_bux`.

---

### Category 4: Competitions (2 templates)

| # | Template Name | Metric | Event Type | Prize Pool | Top N |
|---|--------------|--------|------------|------------|-------|
| 1 | **Most Articles Read** | articles_read | article_view | 1,500 BUX | Top 3 |
| 2 | **Bet Count Champion** | bet_count | game_played | 1,500 BUX | Top 3 |

**Prize distribution** (tiered, 50/30/20 split):
- 1st: 750 BUX
- 2nd: 450 BUX
- 3rd: 300 BUX

**How settlement works**: Queries `UserEvent` table for `event_type` since `promo.started_at`, groups by user, orders by count, takes top N. Only users with `telegram_user_id` and `smart_wallet_address` are eligible.

---

## Permanent Reward Rules

In addition to hourly promos, three **permanent** custom rules in SystemConfig reward users for account actions (500 BUX each, one-time):

| Event | Reward | Dedup |
|-------|--------|-------|
| `x_connected` | 500 BUX | `@one_time_events` in EventProcessor |
| `wallet_connected` | 500 BUX | `@one_time_events` in EventProcessor |
| `phone_verified` | 500 BUX | `@one_time_events` in EventProcessor |

These are defined in `SystemConfig.@defaults["custom_rules"]` and seed on first DB setup. For existing production DBs, they must be added manually via SystemConfig.put or admin UI.

---

## Budget Enforcement

### Daily Budget (100,000 BUX)

```elixir
@daily_bux_limit 100_000
@max_rewards_per_user_per_day 10
```

- Tracked in `bot_daily_rewards` Mnesia table (singleton key `:daily`)
- Resets automatically at midnight UTC (date comparison)
- When budget exhausted, scheduler announces "Daily Rewards Complete!" and skips

### Per-User Limit (10 rewards/day)

- Counter stored in `user_reward_counts` map within `bot_daily_rewards`
- Both direct credits (giveaway/competition) and custom rule payouts count
- Returns `{:error, :user_daily_limit}` when exceeded

---

## Telegram Messaging

### Pin/Unpin Behavior

Each new promo announcement is automatically pinned (silently) and all previous pins are removed:

1. `unpinAllChatMessages` — clears all bot pins
2. `pinChatMessage` with `disable_notification: true` — pins new promo silently

### Message Format

All messages use HTML parse mode with:
- Bold headers with emoji
- Structured "How it works" sections
- Example reward calculations
- ROGUE holder frequency tables
- Countdown urgency
- CTA links to blockster.com

### Results Announcements

After settlement, results are formatted and posted:
- **Giveaway/Competition**: Winner list with usernames and amounts
- **BUX Booster**: Simple "promo is over" message
- **Referral**: "Rates restored to normal" message
- All include "Up next: [next promo name]!" teaser

---

## Admin Controls

### Layer 1: Environment Variable (Deploy-time kill switch)

```bash
# runtime.exs
HOURLY_PROMO_ENABLED=true  # GenServer starts
HOURLY_PROMO_ENABLED=false  # GenServer never starts (default in dev)
```

### Layer 2: SystemConfig Toggle (Runtime on/off)

```elixir
SystemConfig.get("hourly_promo_enabled", true)  # checked each hourly tick
```

When paused, `cleanup_all_bot_rules()` removes all `source: "telegram_bot"` rules.

### Layer 3: Telegram Admin Commands

| Command | Action |
|---------|--------|
| `/bot_pause` | Pauses the scheduler |
| `/bot_resume` | Resumes the scheduler |
| `/bot_status` | Shows status, current promo, budget remaining / 100,000 |
| `/bot_budget` | Shows detailed budget: distributed, remaining, users rewarded |
| `/bot_next [type]` | Forces next promo type (game, referral, giveaway, competition) |

Admin verification checks `User.is_admin == true` via Ecto query on `telegram_user_id`.

### Control Hierarchy

```
ENV var (HOURLY_PROMO_ENABLED)     <-- Deploy-time kill switch
  +-- GenServer starts or doesn't
        +-- SystemConfig key         <-- Runtime on/off
              +-- Telegram Commands  <-- Chat commands flip SystemConfig
```

---

## Mnesia Tables

### `hourly_promo_state`

Stores active promo and crash recovery data:

```elixir
# Schema: {:hourly_promo_state, key, value, timestamp, extra}
# Keys:
#   :current — current promo + history (for crash recovery)
#   :referral_originals — saved referral rates during boost
```

### `hourly_promo_entries`

For tracking competition/giveaway entries per promo:

```elixir
# Schema: {:hourly_promo_entries, key, promo_id, user_id, metric_value, entered_at}
# Indexed on: promo_id, user_id
```

### `bot_daily_rewards`

For enforcing daily budget and per-user limits:

```elixir
# Schema: {:bot_daily_rewards, :daily, date, total_bux_given, user_reward_counts}
# date = ~D[2026-02-24] — resets when date changes
# total_bux_given = integer (running total)
# user_reward_counts = %{user_id => count}
```

---

## EventProcessor Integration

When the bot activates a BUX Booster custom rule, the existing pipeline handles everything:

1. User plays a game -> `UserEvents.track(user_id, "game_played", metadata)`
2. PubSub broadcasts to EventProcessor
3. `EventProcessor.evaluate_custom_rules/3` matches the bot's hourly rule
4. `enrich_metadata/3` adds `bet_amount`, `payout`, `rogue_balance`, `total_bets` from BuxBoosterStats
5. `resolve_bonus/3` evaluates the formula via FormulaEvaluator
6. `execute_rule_action_inner/7` calls `credit_bux/2`
7. User sees BUX credited in real-time

No additional payout code needed for custom-rule-based promos.

---

## Tests

47 tests in `test/blockster_v2/telegram_bot/promo_engine_test.exs`:

### Structural Tests (27)
- Template validity (no nil announcements, only valid categories)
- Weighted random selection + dedup rules
- Budget enforcement (daily cap, per-user limit)
- Prize distribution models (tiered, winner-take-all, participation)
- Rule cleanup (removes only bot-tagged rules)
- Format results HTML (giveaway winners, competition winners, no participants)

### Integration Tests (20)
- **Formula evaluation**: win scenario, loss scenario, anti-farming (small profit), 31.68x big win, ROGUE holder bonus, frequency formula
- **EventProcessor integration**: resolve_bonus with formula, conditions ($gte/$lte), calculate_interval with every_n_formula
- **Referral boost**: activation applies boosted rates, settlement restores originals
- **Giveaway settlement**: auto_entry, activity_based, new_members with real DB queries
- **Competition settlement**: articles_read, bet_count with real DB leaderboard queries
- **Validity checks**: only valid categories picked, no nil announcements across all templates
