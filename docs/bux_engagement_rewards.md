# BUX Engagement Rewards — Reading Articles & Watching Videos

How Blockster V2 monitors a user's reading/watching and turns it into an on-chain BUX
mint. This is a source-verified reference; every formula and constant below was read
directly from the cited file and line.

> **Scope:** the reading-reward path and the video-watch path. Both run inside one
> LiveView (`PostLive.Show`, route `/:slug`) and end in the same settler `/mint` call.
> Other `reward_type`s (signup bonus, X-share, shop affiliate, AI bonus, legacy
> migration) reuse the same mint plumbing but are out of scope here.

## TL;DR pipeline

```
 Browser hook                 LiveView (PostLive.Show)            Settler (Node)        Solana
┌──────────────┐  pushEvent  ┌──────────────────────────┐  POST  ┌────────────┐       ┌──────────┐
│EngagementTrk │ ──────────► │ score → multiplier → BUX │ /mint  │ mintBux()  │ ────► │ mint_to  │
│VideoWatchTrk │   metrics   │ idempotency (once/post)  │ HMAC   │ atomic tx  │  SPL  │ BUX→ATA  │
└──────────────┘             └──────────────────────────┘        └────────────┘       └──────────┘
```

`bux = (engagement_score / 10) × base_bux_reward × user_multiplier × geo_multiplier`,
rounded to 2 decimals. The reward is granted **once per (user, post)** and minted
**fire-and-forget** to the user's `wallet_address`.

## Key files

| Concern | File |
|---|---|
| Article/video page + all reward handlers | `lib/blockster_v2_web/live/post_live/show.ex` (+ `show.html.heex`) |
| Score / min-read-time / BUX formula / recording | `lib/blockster_v2/engagement_tracker.ex` |
| Reward multiplier | `lib/blockster_v2/unified_multiplier.ex` (+ `sol_multiplier.ex`, `email_multiplier.ex`) |
| Mint client (main app → settler) | `lib/blockster_v2/bux_minter.ex` |
| HMAC auth | `lib/blockster_v2/settler_hmac.ex` |
| Reading hook (client) | `assets/js/engagement_tracker.js` |
| Video hook (client) | `assets/js/video_watch_tracker.js` |
| On-chain mint | `contracts/blockster-settler/src/services/token-service.ts`, `routes/mint.ts`, `services/rpc-client.ts` |
| Bot reader minting | `lib/blockster_v2/bot_system/bot_coordinator.ex` |

---

## 1. Client-side tracking

Two **independent** hooks are mounted on the article page; both are registered on the
`LiveSocket` in `assets/js/app.js`.

### 1a. Reading — `EngagementTracker` (`assets/js/engagement_tracker.js`)

Mounted on `#post-engagement-tracker` via `phx-hook="EngagementTracker"`
(`show.html.heex:369-370`). The server feeds it via `data-*` attributes
(`show.html.heex:371-378`): `user-id`, `post-id`, `word-count`, `base-bux-reward`,
`user-multiplier`, `already-rewarded`, `pool-available`, `video-modal-open`.

On `mounted()` (`engagement_tracker.js:15-133`):

- **Early-exit, no tracking at all** if a logged-in user has `already-rewarded`
  (`:23-26`) or the post's reward pool is empty (`pool-available === false`, `:29-32`).
- **Minimum read time** computed client-side: `Math.max(Math.floor(wordCount / 10), 5)`
  (`:38`) — 10 words/sec, floor 5 s. Mirrors the server's `calculate_min_read_time/1`.
- Immediately pushes **`"article-visited"`** with `{min_read_time, word_count}` for
  logged-in users (`:76-79`) — this stamps the server's anti-replay clock (see §4).
- A `requestAnimationFrame` `tick()` loop (`:174-190`) accumulates **active wall-clock
  time in whole seconds**, frozen while the tab is hidden or paused. There is **no
  idle/mouse-inactivity detection** — time accrues as long as the tab is visible.
- A 2000 ms interval fires `sendEngagementUpdate()` while not paused and not yet recorded
  (`:97-101`). Scroll is delayed 500 ms then throttled to 100 ms (`:110-113`).
- A `MutationObserver` on `data-video-modal-open` pauses reading-time accrual while the
  video modal is open (`:120-132`).

**Metrics captured** (`trackScroll()`, `:204-295`): `scrollEvents` (throttled callback
count), `avgScrollSpeed`/`maxScrollSpeed` (px/s over last 50 samples),
`scrollReversals` (direction changes), `scrollDepth` (high-water-mark % scrolled vs the
`#article-end-marker`), `focusChanges`. End-of-article fires when the marker is
`<= window.innerHeight - 200` px (`:269`), with a mobile fallback of
`scrollDepth >= 95 && timeSpent >= minReadTime` (`:289-294`).

**What is sent to the server:**

| Trigger | Event (logged-in) | Event (anonymous) | Payload |
|---|---|---|---|
| every 2 s | `engagement-update` (`:157`) | `anonymous-engagement-update` (`:154`) | `time_spent, min_read_time, scroll_depth, reached_end, scroll_events, avg_scroll_speed, max_scroll_speed, scroll_reversals, focus_changes` (`:137-147`) |
| once, at end | `article-read` (`:326`) | local-store + `show-anonymous-claim` (`:316-320`) | same metric shape |

- There is **no flush on unload** — `destroyed()` pushes nothing (`:393-414`).
- Anonymous users never mint; the hook only stores a display-only "you would have
  earned" value (`earnedAmount = score × 5.0`, `:338`) in `localStorage` under
  `pending_claim_read_${postId}` with a 30-minute expiry (`:340-350`).

### 1b. Video — `VideoWatchTracker` (`assets/js/video_watch_tracker.js`)

A **completely separate hook**, mounted on `#video-watch-container` via
`phx-hook="VideoWatchTracker"` (`show.html.heex:1027-1029`). It drives off the **YouTube
iFrame API** (not HTML5 `<video>` events) with a **high-water-mark** model: you only earn
for watching *past your previous furthest position*.

- A `tick()` loop credits time only when `currentPosition > runningHighWaterMark`
  (`:343`), with an anti-seek clamp `Math.min(newTimeWatched, wholeSeconds)` (`:351`).
- Earning **pauses** while the video is paused, the tab is hidden, the window is blurred,
  the player is buffering, or the video is muted (`:217-228, :272-304, :309/323`).
- Anti-gaming counters: `pauseCount`, `tabAwayCount`, `muteCount`.
- Events: `video-modal-opened`, `video-playing`, `video-paused`,
  `video-watch-update` (every 5 s, debounced to ≥0.1 BUX change), and
  `video-watch-complete` (fired from `finalizeWatching()` and from `destroyed()`, so the
  final mint lands when the modal closes).

---

## 2. Server event handlers (`PostLive.Show`)

| Client event | Handler | Effect |
|---|---|---|
| `article-visited` | `show.ex:671` | `record_visit/3` stamps `created_at` — the anti-replay clock |
| `engagement-update` | `show.ex:687` | recompute score for live display only (no mint), gated by `not already_rewarded` |
| `article-read` | `show.ex:732` | **the reward path**: record → compute BUX → record reward → mint |
| `anonymous-engagement-update` / `show-anonymous-claim` | `show.ex:879` / `:898` | display-only `score × 5.0` |
| `video-watch-complete` | `show.ex:1052` | `mint_video_session_reward/4` |
| `video-watch-update` | `show.ex:1043` | analytics no-op |

---

## 3. Server scoring (reading)

Authoritative: `EngagementTracker.calculate_engagement_score/9`
(`engagement_tracker.ex:429-467`).

```elixir
score = 1.0                                    # base

# Time sub-score (0–6), time_ratio = time_spent / min_read_time
time_ratio >= 1.0 -> 6.0   #  ≥100% of min read time
time_ratio >= 0.9 -> 5.0
time_ratio >= 0.8 -> 4.0
time_ratio >= 0.7 -> 3.0
time_ratio >= 0.5 -> 2.0
time_ratio >= 0.3 -> 1.0
true              -> 0.0   #  too fast

# Depth sub-score (0–3)
scroll_depth >= 100 or reached_end -> 3.0
scroll_depth >= 66                 -> 2.0
scroll_depth >= 33                 -> 1.0
true                               -> 0.0

raw_score = 1 + time_score + depth_score
final     = raw_score |> max(1.0) |> min(10.0) |> round()   # INTEGER 1..10
```

`min_read_time = calculate_min_read_time/1` (`engagement_tracker.ex:473-478`) =
`max(div(word_count, 10), 5)` — **10 words/sec (600 wpm), minimum 5 s**; non-integer
word count → `60`. Word count is computed by walking the TipTap doc JSON
(`count_words/1`, `:483-501`).

> ⚠️ **Stale comment:** the inline comment at `engagement_tracker.ex:437` says "5 words/
> second". The code is `div(word_count, 10)` = **10 words/sec**; the moduledoc at `:471`
> is correct. Client (`engagement_tracker.js:38`) also uses `/10`, so they agree.

The five remaining params (`scroll_events`, `avg_scroll_speed`, `max_scroll_speed`,
`scroll_reversals`, `focus_changes`) are **`_`-prefixed and unused** — see §4.

---

## 4. Anti-abuse — what actually exists

> ⚠️ **Doc-vs-code discrepancy.** The CLAUDE.md "Engagement Tracking" line —
> *"Bot detection: <3 scroll events, >5000 px/s scroll, >300 wpm reading"* — has **no
> implementation in the reading reward path.** The client collects those metrics and the
> server persists them into `:user_post_engagement`, but `calculate_engagement_score/9`
> ignores them (they are `_`-prefixed, `engagement_tracker.ex:430-431`). No `5000`,
> `300`, wpm, or velocity check appears in the reading path. Treat that CLAUDE.md line as
> stale/aspirational.

The anti-abuse that **does** run on the reading side is a **server-clamped elapsed time**
inside `record_read/3` (`engagement_tracker.ex:182-276`) — an attacker cannot fake
wall-clock time on the server:

- With an existing visit record: `time_spent = min(client_time, now - created_at)`
  (`:238-240`), where `created_at` was stamped by `record_visit/3` on `article-visited`.
- With no visit record: `time_spent = min(client_time, min_read_time * 2)` (`:201`).

This **lowers** the time sub-score (and thus BUX); it never hard-rejects a read.

The only explicit *penalty* logic anywhere is on the **video** side,
`apply_video_penalties/2` (`show.ex:1235-1257`): `pause_count > 10 → ×0.8`,
`tab_away_count > 5 → ×0.9`. These reduce, never zero, the video reward.

---

## 5. The reward multiplier (`UnifiedMultiplier`)

```elixir
# unified_multiplier.ex:341-344
overall = x_mult × phone_mult × sol_mult × email_mult |> Float.round(1)
```

| Factor | Range | How it's earned | Source |
|---|---|---|---|
| **X** | 1.0 – 10.0 | `max(x_score/10, 1.0) |> min(10.0)`; `x_score` (0–100) from `x_connections` | `unified_multiplier.ex:318-322` |
| **Phone** | 0.5 – 2.0 | tier by `geo_tier` when `phone_verified`: premium 2.0 / standard 1.5 / basic 1.0; else 0.5 | `:51-56, :327-334` |
| **SOL** | 0.0 – 5.0 | tiered by SOL balance (see below) | `sol_multiplier.ex:33-44, 85-90` |
| **Email** | 0.5 / 2.0 | 2.0 if `email_verified`, else 0.5 | `email_multiplier.ex:13-14` |

SOL tiers (`sol_multiplier.ex:33-44`): `≥10→5.0, ≥5→4.5, ≥2.5→4.0, ≥1→3.5, ≥0.5→3.0,
≥0.25→2.5, ≥0.1→2.0, ≥0.05→1.5, ≥0.01→1.0, <0.01→0.0`.

> ⚠️ **Zero-collapse footgun.** Holding **< 0.01 SOL → SOL factor 0.0**, which zeros the
> entire product (and thus the BUX reward). This is why bots are seeded with non-zero
> floors on every factor (see §9) — any single zero factor collapses the multiplier.

> ⚠️ **The "200x cap" is documented but not clamped in code.** `calculate_overall/4` has
> no `min(result, 200.0)`. `@overall_max 200.0` (`unified_multiplier.ex:37-48`) is only
> read by `max_overall/0` and `is_maxed?/1`. 200 is the *emergent* ceiling of the factor
> maxima (`10 × 2 × 5 × 2 = 200`), not an enforced clamp.

The value is cached in Mnesia `:unified_multipliers_v2` (keyed by `user_id`), fetched via
`get_overall_multiplier/1` (`:68-84`), lazily computed if missing. Anonymous users get a
hardcoded `0.5` at the LiveView call site (`safe_get_user_multiplier/1`, `show.ex:470-477`).

**`:unified_multipliers_v2` tuple** (`unified_multiplier.ex:398-409`):
`{:unified_multipliers_v2, user_id, x_score, x_multiplier, phone_multiplier,
sol_multiplier, email_multiplier, overall_multiplier, last_updated, created_at}`.

---

## 6. The BUX reward formula

```elixir
# engagement_tracker.ex:634-642
def calculate_bux_earned(engagement_score, base_bux_reward, user_multiplier, geo_multiplier \\ 1.0) do
  score_factor = engagement_score / 10.0
  (score_factor * (base_bux_reward || 1) * (user_multiplier || 1) * (geo_multiplier || 1.0))
  |> Float.round(2)
end
```

`bux = (engagement_score / 10) × base_bux_reward × user_multiplier × geo_multiplier`,
**`Float.round(2)`** (not `trunc` — the trunc rule in CLAUDE.md is for coin-flip payouts).

- `base_bux_reward` is a Post field, `:integer, default: 1` (`lib/blockster_v2/blog/post.ex`).
- `user_multiplier` already includes the phone/geo tier, so `geo_multiplier` is passed as
  `1.0` to avoid double-counting (`show.ex:742-752`; the `|| 0.5` fallback should not fire
  in normal operation since `@geo_multiplier` is set to `1.0` at mount).
- No cap, no minimum inside this function. (The "floor to 5 BUX" applies only to bots — §9.)

**Worked example:** a fully-read article (score 10), `base_bux_reward = 1`, a phone-verified
email-verified user holding ≥1 SOL with X-score 50 →
multiplier `= 5.0 × 1.5(say) × 3.5 × 2.0 = 52.5`, so
`bux = (10/10) × 1 × 52.5 × 1.0 = 52.5 BUX`.

---

## 7. Idempotency — granted once per (user, post)

Enforced in `record_read_reward/4` (`engagement_tracker.ex:764-838`) against Mnesia
`:user_post_rewards` keyed by `{user_id, post_id}`:

- No record → write `read_bux = bux_earned`, `read_paid = false`, return `{:ok, bux}`.
- Record exists with `read_bux > 0` → return `{:already_rewarded, read_bux}`, write nothing.
- Record exists but no read reward yet (e.g. user shared before reading) → fill in the read
  reward, preserve share fields.

The LiveView `article-read` handler (`show.ex:732-865`) branches on this: `{:ok, …}` →
mint; `{:already_rewarded, …}` → no mint, surface the existing tx. The client also
self-gates via `hasRecordedRead`, and the page display-gates via `already_rewarded`.

On a successful mint, `BuxMinter` calls `mark_read_reward_paid/3`
(`engagement_tracker.ex:943-973`) which flips `read_paid → true`, stores `read_tx_id`, and
adds `read_bux` to `total_paid_bux`.

**`:user_post_rewards` indices** (`engagement_tracker.ex:668-686`): `4 read_bux`,
`5 read_paid`, `6 read_tx_id`, `13 total_bux`, `14 total_paid_bux`, `15 created_at`,
`16 updated_at`. (Per-session reading metrics go to `:user_post_engagement`, which is
overwritten each call — idempotency lives entirely in `:user_post_rewards`.)

---

## 8. On-chain mint flow

The `article-read` handler fires the mint **fire-and-forget via `Task.start`**
(`show.ex:805`), using `wallet = current_user.wallet_address` (guarded by
`wallet && wallet != "" && recorded_bux > 0`). **`smart_wallet_address` is never used.**

> ⚠️ The read-path mint **swallows failures silently** — the catch-all `_ -> :ok`
> (`show.ex:822-823`) logs nothing, and the post pool is only deducted on success. The
> video path, by contrast, logs on `{:error, reason}` (`show.ex:1187-1189`).

**Main app → settler** (`BuxMinter.mint_bux/7`, `bux_minter.ex:44-92`):

1. Guard: `reward_type in [:read, :x_share, :video_watch, :signup, :phone_verified,
   :shop_affiliate, :shop_refund, :ai_bonus, :legacy_migration]` (`:45`).
2. Missing/empty secret → `{:error, :not_configured}`.
3. Payload (camelCase): `%{wallet:, amount:, userId:, rewardType:}`; encode once, sign the
   exact bytes (`:53-61`).
4. `POST {settler_url}/mint` via `Req.post(..., receive_timeout: 60_000, retry: false)`.
5. On 200: read `signature`; if `:read`, `mark_read_reward_paid`; record gas;
   `sync_user_balances_async(force: true)`.

**HMAC** (`SettlerHmac.headers/2`, `settler_hmac.ex:42-56`): `payload = "#{timestamp}.#{body}"`,
`HMAC-SHA256` hex, headers `x-timestamp` + `x-signature`. The settler enforces a **5-minute
freshness window** (`hmac-auth.ts:28-32`) and a timing-safe signature compare over the raw
body. (See CLAUDE.md "Settler API auth = HMAC, not Bearer".)

**Settler → Solana** (`token-service.ts:31-67`):

- `rawAmount = BigInt(Math.floor(amount * 10 ** 9))` — **BUX has 9 decimals**
  (`config.ts:96`).
- One **atomic tx**: `createAssociatedTokenAccountIdempotentInstruction(...)` +
  `createMintToInstruction(BUX_MINT, ata, MINT_AUTHORITY, rawAmount)`, sent via
  `sendSettlerTx(..., MINT_AUTHORITY)`.
- `sendSettlerTx` (`rpc-client.ts:88-107`) adds a compute budget (200k units, 50k µLamports
  priority fee), signs with `MINT_AUTHORITY`, sends, then `waitForConfirmation`.
- `waitForConfirmation` (`rpc-client.ts:39-63`) polls `getSignatureStatuses` every ~1 s up
  to 60 s — **no websockets, no rebroadcast** (per CLAUDE.md Solana rules).

> Prod gas note: the fee payer is `MINT_AUTHORITY` (`6b4n…`). If it runs out of SOL, every
> BUX mint fails with "insufficient funds for rent" and post-card counters freeze. See the
> memory note "Prod settler mainnet gas wallet".

---

## 9. Bot reader minting (separate path, real on-chain mints)

The 1000-bot reader system (`bot_coordinator.ex`) scores reads identically but:

- Uses `geo_multiplier = 1.0` (the multiplier already includes the phone tier).
- Applies a **floor**: `min_bot_reward = 5.0`; if `0 < raw_bux < 5.0`, the reward is
  jittered up to `Float.round(min_reward + :rand.uniform() * min_reward, 2)`
  (`bot_coordinator.ex:357-362`). The floor only rescues `raw_bux > 0` — a zero multiplier
  still collapses to 0 and is silently skipped.
- Mints route through a rate-limited FIFO queue to `wallet_address`.
- `BuxMinter.sync_user_balances/2` short-circuits for bots (`bot_user?/1` →
  `{:ok, :skipped_bot}`) so syncing an empty bot SOL wallet doesn't zero its multiplier.

Bot multipliers are seeded with every factor floored above zero on boot, and re-repaired
for any bot with `overall_multiplier ≤ 0.0` — because any zero factor collapses the product.
See [docs/bot_reader_system.md](bot_reader_system.md).

---

## 10. UI feedback

The "you earned X BUX" UI is assigned **synchronously** when `record_read_reward` succeeds
(`show.ex:836-846`), before the mint lands. On mint success the `Task` sends
`{:mint_completed, tx_hash}`; the handler assigns `:read_tx_id` and triggers
`sync_user_balances_async(force: true)` + an async on-chain balance read. The resulting
balances broadcast on `bux_balance:<user_id>` (`BuxBalanceHook`), which every subscribed
LiveView consumes to update the header BUX counter live. Bots produce no UI.

---

## Verified constants (source of truth)

| Constant | Value | Source |
|---|---|---|
| Time sub-score thresholds | 1.0/0.9/0.8/0.7/0.5/0.3 → 6/5/4/3/2/1 | `engagement_tracker.ex:439-447` |
| Depth sub-score thresholds | 100|end / 66 / 33 → 3/2/1 | `engagement_tracker.ex:451-456` |
| Score clamp | `max(1.0) |> min(10.0) |> round()` | `engagement_tracker.ex:463-466` |
| Min read time | `max(div(word_count, 10), 5)` (10 wps, min 5 s) | `engagement_tracker.ex:475` |
| BUX formula | `(score/10 × base × mult × geo) |> Float.round(2)` | `engagement_tracker.ex:634-642` |
| Overall multiplier | `x × phone × sol × email |> Float.round(1)` (no 200x clamp) | `unified_multiplier.ex:341-344` |
| Factor bounds | x 1–10, phone 0.5–2, sol 0–5, email 0.5–2 | `unified_multiplier.ex:37-48` |
| SOL < 0.01 → factor | `0.0` (collapses product) | `sol_multiplier.ex:33-44` |
| Anti-replay clamp | `min(client_time, now - created_at)` | `engagement_tracker.ex:240` |
| Idempotency | `read_bux > 0 → {:already_rewarded}` | `engagement_tracker.ex:797-799` |
| Video penalties | pause>10 → ×0.8; tab_away>5 → ×0.9 | `show.ex:1240-1251` |
| Bot floor | `min_bot_reward 5.0`, jittered | `bot_coordinator.ex:357-362` |
| On-chain scaling | `floor(amount × 10^9)`, BUX_DECIMALS 9 | `token-service.ts:36`, `config.ts:96` |
| Mint endpoint | `POST {settler_url}/mint` | `bux_minter.ex:63` |
| HMAC payload | `"#{timestamp}.#{body}"`, HMAC-SHA256 hex, 5-min window | `settler_hmac.ex:44-49`, `hmac-auth.ts:30` |

## Known discrepancies / footguns

1. **CLAUDE.md reading bot-detection thresholds (`<3 scroll events`, `>5000 px/s`,
   `>300 wpm`) are not implemented.** The scoring function ignores all velocity/scroll-event
   metrics. The only reading-side defense is the server-clamped elapsed time (§4).
2. **The 200x multiplier cap is not clamped** — it's an emergent ceiling, not enforced code (§5).
3. **A `< 0.01 SOL` balance zeros the whole multiplier** (and thus the reward) (§5).
4. **The read-path mint swallows settler failures silently** — no log, no retry (§8).
5. **Stale inline comment** at `engagement_tracker.ex:437` says "5 words/second"; the code
   is 10 wps (§3).
6. The `TimeTracker` hook / `time_update` handler (`show.ex:436`, `assets/js/time_tracker.js`)
   appear to be **legacy/dead** on the redesigned article page — reading time is captured
   solely by `EngagementTracker.timeSpent`.
