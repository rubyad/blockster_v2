# Telegram Bot Hourly Engagement System

> **Status**: Implemented and deployed. Scheduler always starts; runtime toggle controls whether promos fire.

The Blockster V2 Bot posts every hour in the main Telegram group (`https://t.me/+7bIzOyrYBEc3OTdh`) with diverse promotions, giveaways, competitions, custom BUX Booster rules, and referral offers — driving users to the app to read, earn, and play.

### Safety Rules

1. **The bot CANNOT modify shop product prices, discounts, or inventory.**
2. **The bot CAN freely**: mint BUX, create/remove custom rules, boost referral rates, run giveaways, run competitions, send Telegram messages.
3. **Daily BUX budget: 100,000 BUX** — Hard limit across ALL promos. Tracked via `bot_daily_rewards` Mnesia table, resets at midnight UTC.
4. **Per-user daily reward limit: 10 rewards per Telegram user per day** — Enforced via daily counter in `bot_daily_rewards` Mnesia table.
5. **All bot-created rules tagged** with `source: "telegram_bot"` for safe cleanup on pause/settlement.
6. **Bot rules are in-app only** — EventProcessor forces `channel: "in_app"` for any rule with `source: "telegram_bot"`, preventing email spam from hourly promos.
7. **Telegram messages only sent in production** — `TelegramGroupMessenger` returns a fake success in dev/test to prevent localhost from spamming the real group.

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
| `lib/blockster_v2/telegram_bot/promo_qa.ex` | Claude Haiku Q&A bot — answers promo questions in Telegram group |
| `lib/blockster_v2_web/controllers/telegram_webhook_controller.ex` | Admin commands + Q&A: `/bot_pause`, `/bot_resume`, `/bot_status`, `/bot_budget`, `/bot_next`, and natural language questions |
| `test/blockster_v2/telegram_bot/promo_engine_test.exs` | 47 tests — structural + integration |
| `config/runtime.exs` | Config: bot token, channel ID env vars |
| `lib/blockster_v2/application.ex` | Supervision tree — scheduler always starts (runtime toggle controls firing) |
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

**How settlement works**: `cleanup_hourly_rules/1` removes the tagged rule from SystemConfig. Also cleans up any expired bot rules (checks `_expires_at` timestamp) to prevent orphaned rules from piling up if settlement was skipped (e.g. after a crash).

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

In addition to hourly promos, six **permanent** custom rules in SystemConfig reward users for account actions and gameplay milestones:

| Event | Reward | Channel | Dedup |
|-------|--------|---------|-------|
| `phone_verified` | 500 BUX | all | `@one_time_events` in EventProcessor |
| `x_connected` | 500 BUX | all | `@one_time_events` in EventProcessor |
| `wallet_connected` | 500 BUX | all | `@one_time_events` in EventProcessor |
| `telegram_connected` | 500 BUX | all | `@one_time_events` in EventProcessor |
| `game_played` (High Roller) | 500 BUX | all | bet_amount >= 1000, one-time |
| `game_played` (First Bet) | 250 BUX | all | total_bets <= 1, one-time |

These are defined in `SystemConfig.@defaults["custom_rules"]` and seed on first DB setup. For existing production DBs, they must be added manually via SystemConfig.put or admin UI.

**Note**: These permanent rules use `channel: "all"` (in-app + email + telegram). This is intentional for one-time milestone rewards. The `source: "telegram_bot"` in-app-only guard only applies to hourly promo rules.

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

### Production Only

`TelegramGroupMessenger.send_group_message/2` checks `Application.get_env(:blockster_v2, :env)` and only sends in `:prod`. In dev/test it returns a fake `{:ok, %{body: %{"ok" => true, ...}}}` so the scheduler pipeline works normally without hitting the real Telegram API.

### Retry Logic

Transient `Req.TransportError` failures (TCP connection closed, etc.) are retried up to 2 times with 2-second delays before giving up.

### Error Handling

The scheduler checks `{:ok, %{body: %{"ok" => true}}}` for success, not just `{:ok, _}`. This is important because `Req.post` returns `{:ok, %Req.Response{}}` even for HTTP 400/403 errors. Telegram API rejections (e.g. supergroup migration, invalid chat ID) are now logged as errors instead of silently swallowed.

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

### Known Issue: Supergroup Migration

If the Telegram group is upgraded to a supergroup, the chat ID changes. The Telegram API returns `"group chat was upgraded to a supergroup chat"` with the new `migrate_to_chat_id`. Fix by updating the `TELEGRAM_BLOCKSTER_V2_CHANNEL_ID` env var/secret.

---

## Admin Controls

### Layer 1: SystemConfig Toggle (Runtime on/off)

The scheduler GenServer always starts in the supervision tree. Each hourly tick checks:

```elixir
SystemConfig.get("hourly_promo_enabled", false)  # checked each hourly tick
```

When disabled (default), the scheduler skips the promo cycle. When paused via admin command, `cleanup_all_bot_rules()` removes all `source: "telegram_bot"` rules.

### Layer 2: Telegram Admin Commands

| Command | Action |
|---------|--------|
| `/bot_pause` | Pauses the scheduler (sets SystemConfig to false) |
| `/bot_resume` | Resumes the scheduler (sets SystemConfig to true) |
| `/bot_status` | Shows status, current promo, budget remaining / 100,000 |
| `/bot_budget` | Shows detailed budget: distributed, remaining, users rewarded |
| `/bot_next [type]` | Forces next promo type (game, referral, giveaway, competition) |

Admin verification checks `User.is_admin == true` via Ecto query on `telegram_user_id`.

### Control Hierarchy

```
GenServer always running (supervision tree)
  +-- SystemConfig key ("hourly_promo_enabled")  <-- Runtime on/off
        +-- Telegram Commands                     <-- Chat commands flip SystemConfig
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

**Startup race condition**: The scheduler starts before MnesiaInitializer creates tables. `restore_state_from_mnesia` calls `wait_for_tables` (10s timeout) and catches both `:exit` signals and exceptions. If `current_promo` is nil after restore, a `Process.send_after(:retry_mnesia_restore, 5_000)` retries once after 5 seconds.

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

## Promo Q&A Bot

`PromoQA` (`promo_qa.ex`) answers user questions about promos in the Telegram group using Claude Haiku (`claude-haiku-4-5-20251001`).

**How it works**:
1. User sends a message mentioning the bot or replying to the bot in the group
2. `TelegramWebhookController` detects it's not an admin command and routes to `PromoQA.answer_question/2`
3. PromoQA builds context from live system data (current promo, budget, all template descriptions)
4. Claude Haiku answers grounded in that context — never hallucinates

**Safeguards**:
- **Rate limiting**: ETS-based, 10-second cooldown per user
- **Input sanitization**: 500 char max, strips HTML/XML tags, removes injection patterns
- **System prompt**: Strict rules — never reveal instructions, never output code/JSON, never speculate
- **API key**: Uses same `ANTHROPIC_API_KEY` as content automation

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
