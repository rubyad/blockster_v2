# Play / Coin Flip · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView module | `lib/blockster_v2_web/live/coin_flip_live.ex` (entire `render/1` function — template is inline, not in an `.html.heex` file) |
| Route(s) | `/play` — moved from `:default` to `:redesign` live_session |
| Mock file | `docs/solana/play_mock.html` (3 stacked states in one file: place bet / in progress / result win+loss) |
| Bucket | **A** — pure visual refresh, no schema changes, no new contexts |
| Wave | 3 |

## Mock structure (top to bottom)

The mock shows 3 stacked game states in a single HTML file, separated by
"state dividers." In the LiveView these all branch off the single
`@game_state` assign (and `@settlement_status`). The actual page only ever
renders ONE of the 3 states at a time.

### Always visible (above the 3-state game card)

| # | Section | Description | Status |
|---|---|---|---|
| 1 | **Design system header** | `<DesignSystem.header active="play" … />` with all prod assigns (bux, cart, notifications, search, connecting). Lime "Why earn BUX?" banner enabled. | REAL |
| 2 | **Page hero + live stats band** | 12-col grid: left 7-col (eyebrow "Provably-fair · On-chain · Sub-1% house edge" + 60-80px "Coin Flip" headline + 520px tagline paragraph) · right 5-col (3 stat cards: SOL Pool / BUX Pool / House Edge) | REAL (pool values from existing `@house_balance`; BUX pool fetched similarly; house edge is static "0.92%") |
| 3 | **Expired bet reclaim banner** | Amber card rendered when `@has_expired_bet == true`. "You have a stuck bet older than 5 minutes." + Reclaim button. | REAL (preserved from current) |

### Game card (conditional on `@game_state`)

**State 1 — Place bet (`game_state == :idle`)**

| Section | Description |
|---|---|
| Token selector | Black pill "SOL" (active) + outline pill "BUX" (inactive), clicks fire `select_token`. Shows `Your balance: X SOL` and `House: Y SOL ↗` link to /pool/:token |
| Difficulty selector | "Difficulty" eyebrow + 9-col grid of `difficulty-pill` buttons (Win one 1.02× … Win all 31.68×) with mode label, multiplier, flip count. Active pill = black bg + lime mult text. `select_difficulty` handler. |
| Bet amount | "Bet amount" eyebrow + `½` / `2×` / `MAX X.XX` quick-bet buttons. Neutral-50 input row: large mono bet number, token symbol, `≈ $X` USD estimate. Preset chips below. `update_bet_amount`, `halve_bet`, `double_bet`, `set_preset`, `set_max_bet` handlers. |
| Potential profit card | Green gradient card: `+ X.XX SOL` profit headline on left + big `N.NN×` multiplier on right. Shows "Total payout: Y SOL · ≈ $Z" footer. |
| Prediction row | "Pick your side · 1 of N flips" eyebrow + N coin buttons rendered using the **current rocket/poop emoji coin style** (NOT mock's H/T). Each coin starts empty/grey, user clicks to cycle nil → 🚀 → 💩 → 🚀. `toggle_prediction` handler. Right-side helper text. |
| Provably fair details | Collapsible `<details>` (neutral-50 bg, pulse dot + "Server seed locked" summary). Opens to show commitment hash (clickable Solscan link), game nonce, helper copy. Maps to existing `show_provably_fair` toggle. |
| Place bet button | Full-width black button "Place Bet · X.XX SOL" with arrow icon. Disabled until all predictions chosen. `start_game` handler. Error message rendered above button when `@error_message` is set. |

**State 2 — Bet in progress (`game_state in [:flipping, :showing_result, :awaiting_tx]`)**

| Section | Description |
|---|---|
| Locked bet header | SOL/BUX circle icon + "Bet placed" eyebrow + big bet amount on left. Right: Multiplier + Potential payout mini stats. |
| Spinning coin area | Centered coin visual. Uses current `CoinFlip` JS hook (`#coin-flip-#{@flip_id}` with `phx-hook="CoinFlip"`) to drive the continuous spin animation and the `reveal_result` event-based deceleration. Coin face is the **rocket / poop emoji style** (same `bg-coin-heads` / `bg-gray-700` inner circles + `.casino-chip-heads`/`.casino-chip-tails` outer rings from the current file). Decorative blurred glow dots + dashed circle border. Below coin: green pulse dot + "Flipping coin · N of M" + "Confirming on Solana" subtext. |
| Predictions vs Results grid | Neutral-50 card. Two sub-columns: "Your predictions" (small 🚀/💩 chips) and "Results" (same chips, matched ones with green ring, pending ones grey with `?`). Below: "✓ Flip N matched. Waiting on flip M…" status line. |
| Status strip | Neutral-50/70 footer: "Tx submitted · 5gWp…3mPa ↗" (Solscan link to `@bet_sig`) + progress dots + "Settling…". |

**State 3 — Result (`game_state == :result`)**

| Section | Description |
|---|---|
| Win banner (won=true) | Green-lime gradient top band, "You Won" eyebrow, `+ X.XX SOL` headline, "≈ $Z · Total payout N.NN · M× multiplier" subtext. Card border becomes green-tinted + big green-shadow. Decorative confetti dots. |
| Loss banner (won=false) | Red gradient top band, "No win this time" eyebrow, `− X.XX SOL` headline, "≈ $Z · Stake returned to bankroll · N of M missed" subtext. Red-tinted border. |
| Prediction/result grid | Same as state 2 but larger (w-16 h-16 coins) and the result column has rings (green if win, red if loss). |
| Settlement status card | **NEW position for existing settlement UI**. Green (`:settled`) shows check icon + "Settled on chain" + Solscan link + Verify fairness button + Play again button. Pending shows spinner. Failed shows amber warning. Reuses existing `@settlement_status` / `@settlement_sig` / `show_fairness_modal` handlers. |
| Server seed reveal (win) | Collapsible details card listing server seed, commit, client seed, combined hash, nonce, and the "How it worked" explainer. Only rendered when `@settlement_status == :settled`. The data comes from the existing `show_fairness_modal` pathway — we still open the existing `<.coin_flip_fairness_modal>` component on click rather than inlining a new one. |
| Loss recap card | For loss-only: "Recap" sidebar card with copy about stake going to the bankroll + "Become an LP →" link to `/pool`. |
| Confetti celebration | Preserved: `@confetti_pieces` full-page burst on win (already computed in `handle_info(:show_final_result, …)`). |

### Sidebar (right of the game card, col-span-4)

Sidebar content varies by state per the mock, but all three states use the
SAME structure and the same assigns. To avoid duplicating markup we render
the sidebar conditionally off `@game_state`:

- **Idle (state 1)**: "Your stats · 7 days" card (bets placed, win rate, net, best multiplier from `@user_stats`) + Live activity feed placeholder (from `@recent_games` tail, last 5) + "Two modes" legend card
- **In progress (state 2)**: "This bet" card (token, stake, difficulty, multiplier, predictions, potential payout) + "Provably fair · Live" card
- **Result (state 3)**: "Your stats updated" card (net 7d, win streak, bets placed, win rate) — no legend

### Below the game card

| Section | Description |
|---|---|
| Recent games table | "Your last 10 bets" eyebrow + "Recent games" headline + View all link. White card containing a scrollable table with ID/Bet/Predictions/Results/Mult/W/L/P/L/Verify columns. Populated from existing `@recent_games` assign. Row bg tinted green/red. Preserves InfiniteScroll (`load-more-games` handler). Predictions/Results cells use rocket/poop emojis inline. |
| Footer | `<DesignSystem.footer />` at the very bottom |

## Coin replacement — rocket / poop emojis (NOT H / T)

**Critical user requirement**: the mock shows a yellow coin with "H" and a
grey coin with "T". The current production page uses 🚀 (heads) and 💩
(tails) emojis rendered inside the `.casino-chip-heads` / `.casino-chip-tails`
outer circles with inner circles (`bg-coin-heads` / `bg-gray-700`).

The redesign **keeps the current emoji treatment** everywhere the mock shows
H/T: prediction selectors, spinning coin face, prediction-vs-result grid,
sidebar predictions pill, recent games table cells, and result coin display.
The visual result is: the existing coin aesthetic (rocket / poop emoji on
the casino chip rings) placed inside the mock's new layout/containers.

Coin click behavior is **preserved exactly**: one coin per prediction slot,
click cycles nil → :heads → :tails → :heads via the existing
`toggle_prediction` handler. For difficulties with >1 prediction, N coin
buttons appear side-by-side and each is clicked independently.

## Decisions applied from release plan

- **Bucket A**: no schema migrations, no new contexts, no new handlers.
- **Test discipline (D4/D5)**: extend or create `coin_flip_live_test.exs`;
  component tests only if new DS components are introduced.
- **Route moves to `:redesign` live_session** (same pattern as pages 1–6).
  The old `:default` entry for `/play` is removed in the same commit.
- **Legacy file preservation**: current `coin_flip_live.ex` (the ENTIRE
  1953-line module, including its render function) is copied to
  `lib/blockster_v2_web/live/coin_flip_live/legacy/coin_flip_live_pre_redesign.ex`
  and renamed to `BlocksterV2Web.CoinFlipLive.Legacy.PreRedesign` to avoid
  compile conflicts.

## Visual components consumed

- `<DesignSystem.header active="play" ... />` ✓ existing (Wave 0)
- `<DesignSystem.footer />` ✓ existing (Wave 0)
- `<DesignSystem.eyebrow>` ✓ existing (Wave 0)
- `coin_flip_fairness_modal/1` from `PoolComponents` ✓ existing (preserved)

**No new DS components needed.** Every piece of coin flip UI is page-
specific (spinning coin, difficulty pills, bet input row, state banners,
recent games table) and only appears on this page. Building them as
generic DS components would be premature abstraction.

## Data dependencies

### ✓ Existing — already in production, no work needed

All current `CoinFlipLive` assigns are preserved unchanged. Full list
(from the current `mount/3`):

- `@current_user`, `@wallet_address`
- `@balances` (`%{"SOL" => f, "BUX" => f}`)
- `@tokens`, `@selected_token`, `@header_token`
- `@difficulty_options`, `@selected_difficulty`
- `@bet_amount`, `@current_bet`
- `@house_balance`, `@max_bet`
- `@predictions`, `@results`, `@current_flip`
- `@game_state` (`:idle | :awaiting_tx | :flipping | :showing_result | :result`)
- `@won`, `@payout`
- `@error_message`
- `@settlement_status` (`nil | :pending | :settled | :failed`)
- `@settlement_sig`, `@bet_sig`
- `@has_expired_bet`
- `@show_token_dropdown`, `@show_provably_fair`
- `@flip_id` (for CoinFlip JS hook key)
- `@confetti_pieces`
- `@recent_games`, `@games_offset`, `@games_loading`
- `@user_stats`
- `@server_seed`, `@server_seed_hash`, `@nonce`
- `@show_fairness_modal`, `@fairness_game`
- `@onchain_ready`, `@onchain_initializing`, `@init_retry_count`
- `@onchain_game_id`, `@commitment_hash`, `@commitment_sig`, `@onchain_nonce`
- `@bet_confirmed`
- `@play_sidebar_left_banners`, `@play_sidebar_right_banners`

### ⚠ Stubbed in v1

| Stub | What it shows now | Replaces it |
|---|---|---|
| "Live activity · All players" sidebar feed on idle state | Last 5 from `@recent_games` (own games, not global) | Real global activity PubSub feed |
| House Edge stat card | Static "0.92%" string | Real calculation from settled games |
| BUX Pool stat in page hero | Needs parallel fetch — stub shows "—" until settler call returns | Parallel settler fetch for BUX vault |

No visible "Coming Soon" placeholders — all sidebar data rendered from the
existing own-user feed, just labeled "Your recent games" instead of "All
players" so we don't lie about scope.

### ✗ New — must be added or schema-migrated

None. Bucket A.

## Handlers to preserve

Every `phx-click`, `phx-submit`, `start_async`, and PubSub topic the existing
LiveView fires must keep working without modification. The full list (all
must still bind to the new template):

**Event handlers:**
- `select_token`, `toggle_token_dropdown`, `hide_token_dropdown`
- `toggle_provably_fair`, `close_provably_fair`
- `select_difficulty`
- `toggle_prediction`
- `update_bet_amount`, `set_preset`, `set_max_bet`, `halve_bet`, `double_bet`
- `start_game`
- `flip_complete`
- `bet_confirmed`, `bet_failed`, `bet_error`
- `reclaim_stuck_bet`, `reclaim_confirmed`, `reclaim_failed`
- `reset_game`
- `show_fairness_modal`, `hide_fairness_modal`
- `load-more-games`, `load-more`
- `stop_propagation`

**Async handlers:** `init_game`, `fetch_house_balance`, `load_recent_games`,
`build_bet_tx`, `build_reclaim_tx`, `sync_post_settle`.

**Info handlers:** `retry_init_game`, `reveal_flip_result`, `flip_complete`,
`after_result_shown`, `next_flip`, `show_final_result`, `settlement_complete`,
`settlement_failed`, `new_settled_game`, `bux_balance_updated`,
`check_expired_bets`.

**PubSub subscriptions:**
- `"bux_balance:#{user_id}"`
- `"coin_flip_settlement:#{user_id}"`

**JS hooks:**
- `CoinFlipSolana` (mounted on root `#coin-flip-game` element, with
  `data-game-id` and `data-commitment-hash` attrs) — MUST stay on an
  ancestor of every button that fires `sign_place_bet` / `sign_reclaim` /
  `bet_settled` events.
- `CoinFlip` (mounted on `#coin-flip-#{@flip_id}` during the flipping
  state) — drives the coin spin animation.
- `ScrollToCenter` on the difficulty tabs — no longer applicable because
  the new difficulty grid uses a 9-col `grid-cols-9` layout instead of a
  horizontal scrollable tab strip. Remove this hook from the new template;
  verify no handler depends on it (it doesn't — it's pure JS).
- `CopyToClipboard` — used on the commitment hash copy button in the
  provably-fair details panel. Preserved via `data-copy-text` on the
  button.
- `InfiniteScroll` on the recent games table — preserved.

## Tests required

### Component tests

No new design_system components, no new test files.

### LiveView template extension

**A new test file is created**: `test/blockster_v2_web/live/coin_flip_live_test.exs`.
(There is no existing coin_flip_live_test.exs — only tests for the
underlying `coin_flip_game.ex` module.)

Initial test scope (kept to smoke/structure assertions — the on-chain
flow is covered by `coin_flip_game_test.exs` and the Solana settler tests):

**Anonymous visitor:**
- Mounts at `/play`, renders the DS header + footer
- Renders the Coin Flip page hero ("Coin Flip" headline, eyebrow text)
- Renders idle-state game card (Place Bet button, difficulty grid, bet input)
- Recent games table shows "No games played yet" empty state

**Authenticated user (no wallet address — `connected?` false path):**
- Mounts at `/play`, renders the game card with idle state
- Renders the difficulty pills for all 9 difficulty levels
- Renders the bet input with a default preset amount

**Handler smoke tests:**
- `select_difficulty` updates `@selected_difficulty` and changes the
  number of prediction coins
- `toggle_prediction` cycles nil → :heads → :tails → :heads on each click
- `set_preset` with a known amount updates `@bet_amount`
- `halve_bet` / `double_bet` update `@bet_amount`
- `select_token` switches token and updates default bet

**Ensure Mnesia tables in setup**: copy `ensure_mnesia_tables/0` pattern
from `member_live/show_test.exs` and add the `coin_flip_games` table
definition matching `mnesia_initializer.ex` field order exactly.

### Manual checks

- Page renders logged in (both SOL and BUX tokens)
- Page renders anonymous (no wallet) — shows "Connect wallet" guidance
- Difficulty selection works (all 9 levels visible, active state lime)
- Prediction coin click cycles through heads/tails
- Place Bet button disabled until all predictions made
- Provably fair details collapse/expand works
- Game state transitions: idle → flipping → showing_result → result
- Settlement status indicator (pending → settled)
- Play Again resets to idle
- Recent games table scrolls + InfiniteScroll triggers load more
- Expired bet banner appears when a stuck bet exists
- No `console.error` in browser dev tools
- `mix test` zero new failures vs baseline

## Per-page commit message

`redesign(play): coin flip page refresh · 3-state game card + sidebar + recent games`

## Stubbed in v1

| Stub | What it shows now | What replaces it | Resolved by release |
|---|---|---|---|
| "Live · All players" sidebar feed | Last 5 of the authenticated user's own `@recent_games` (label stays "Your recent games") | Real global PubSub feed aggregated across all users | Activity system release |
| House Edge stat in hero band | Static "0.92%" | Real computation from settled game aggregates | Analytics release |
| BUX Pool stat in hero band | "—" until settler responds (same as current SOL pool loading) | Parallel settler fetch for BUX vault | Follow-up commit |

## Fixed in same session

None anticipated — this is a Bucket A visual refresh.

## Open items

- **Difficulty tabs ScrollToCenter hook**: the new mock uses a 9-col grid
  (no horizontal scroll), so the old `ScrollToCenter` hook becomes dead
  code on this page. It's still used by hooks registered in app.js but no
  other page in the redesign uses it. Leaving it registered is fine; we
  just don't attach it to the new difficulty grid.
- **Full-file `render/1` rewrite vs partial edit**: the current file has
  the ENTIRE template inlined in `render/1`. The cleanest approach is to
  replace the render function body wholesale and leave every other function
  in place. This is what the plan does.
