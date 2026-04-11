# Pool index · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView module | `lib/blockster_v2_web/live/pool_index_live.ex` (entire render/1 + a light expansion of `mount/3` to load cross-vault activity) |
| Route(s) | `/pool` — moved from `:default` to `:redesign` live_session |
| Mock file | `docs/solana/pool_index_mock.html` |
| Bucket | **A** — pure visual refresh, no schema changes, no new contexts |
| Wave | 3 (Page #8) |

## Mock structure (top to bottom)

1. **Design system header** (`<DesignSystem.header active="pool" … />`) with all prod assigns. `display_token="BUX"` (default). Lime "Why Earn BUX?" banner on.
2. **Page header + stat band** — 12-col grid. Left 7-col: eyebrow "Earn from every bet · On-chain settlement" + big "Liquidity Pools" headline (60/80px) + descriptive paragraph. Right 5-col: 3 small white stat cards — Total TVL / Bets settled 24h / House profit 24h.
3. **Two vault cards** — 1-col on mobile, 2-col desktop. Each `min-h-[420px]`, 3xl radius, gradient background (SOL = emerald green, BUX = lime), with:
   - Top row: icon tile + "Vault" eyebrow + "SOL Pool" / "BUX Pool" title, right side "LIVE" pulse pill.
   - LP Price big mono number + token unit + 24h change + "24h" label.
   - Mini SVG sparkline (decorative — NOT real chart data).
   - 2×2 stats grid: TVL / Supply / Volume 24h / Profit 24h. Each cell has eyebrow + big mono number + sub-line.
   - Your position card (user's LP balance in that vault) with pool-share %.
   - CTA row: rounded-full button "Enter SOL Pool →" / "Enter BUX Pool →" + "est. APY" caption.
   - Whole card is a single `<.link navigate={~p"/pool/sol"}>` / `~p"/pool/bux"` so any click on the card navigates.
4. **How it works** — 3-step white card grid (Deposit / Earn / Withdraw), numbered 1/2/3 pills, copy from mock verbatim.
5. **Pool activity** — real-time cross-pool activity table. Eyebrow + "Pool activity" headline on left, "Live across both pools" pulse pill on right. 6-col grid: Type / Pool / Wallet / Amount / Time / TX. Footer: "Showing N of M events from the last 24h" + "Open SOL pool details →" link.
6. **Footer** — `<DesignSystem.footer />`.

## Decisions applied from release plan

- **Bucket A**: no schema migrations, no new contexts.
- **Cross-vault activity on index**: the detail page already loads + subscribes per vault; the index does the same read twice (once for `sol`, once for `bux`), merges, sorts by `_created_at` desc, takes top 6. Subscribes to `"pool_activity:sol"` + `"pool_activity:bux"` topics for live updates.
- **Route moves to `:redesign` live_session** (same pattern as pages #1–#7). Removed from `:default`.
- **Legacy file preservation**: current `lib/blockster_v2_web/live/pool_index_live.ex` copied to `lib/blockster_v2_web/live/pool_index_live/legacy/pool_index_live_pre_redesign.ex`, renamed to `BlocksterV2Web.PoolIndexLive.Legacy.PreRedesign` to avoid compile conflicts. No other modules reference it, so it's dormant.
- **Test discipline (D4/D5)**: extend existing `pool_index_live_test.exs` with assertions for the new template. No new DS component tests — no new DS components built.

## Visual components consumed

- `<BlocksterV2Web.DesignSystem.header active="pool" … />` ✓ existing (Wave 0)
- `<BlocksterV2Web.DesignSystem.footer />` ✓ existing (Wave 0)
- `<BlocksterV2Web.DesignSystem.eyebrow>` ✓ existing (Wave 0)

**No new DS components needed.** The vault cards, stat band, how-it-works grid, and activity table are all page-specific markup that only renders on `/pool`. Building them as generic DS components would be premature abstraction. All styling is inline Tailwind matching the mock exactly.

## Data dependencies

### ✓ Existing — already in production

- `BuxMinter.get_pool_stats/0` — returns `{:ok, %{"sol" => stats, "bux" => stats}}` where each stats map has `"totalBalance"`, `"netBalance"`, `"lpSupply"`, `"lpPrice"`, `"houseProfit"`, `"totalBets"`, `"totalVolume"`, `"totalPayout"` (settler deserializes on-chain vault state).
- `BlocksterV2.CoinFlipGame.get_recent_games_by_vault/2` — per-vault recent bets (Mnesia). Used by detail page already.
- `:pool_activities` Mnesia table — deposit/withdraw records. Read via `:mnesia.dirty_index_read(:pool_activities, vault_type, :vault_type)` (indexed read). Used by detail page already.
- PubSub topics `"pool_activity:sol"` + `"pool_activity:bux"` — broadcast from `PoolDetailLive` whenever a deposit/withdraw commits. Already firing in prod.
- `BuxMinter.get_lp_balance/2` — user's bSOL / bBUX balance. Used on detail page. On the index we use it to show "Your position" on each vault card.
- `@current_user`, `@wallet_address` — already supplied by `UserAuth` on_mount.

### ⚠ Stubbed in v1

| Stub | What shows | Replaces it |
|---|---|---|
| Page-header 3-stat band (Total TVL / Bets settled 24h / House profit 24h) | Total TVL = sum of both vault `netBalance` converted via a rough SOL$160 / BUX$0.01 estimate (same static multiplier the detail page uses). Bets settled 24h = sum of both vaults' `totalBets` (all-time, labeled "all time" not "24h" to stay honest). House profit 24h = sum of both `houseProfit` (all-time). | Real 24h aggregates once an analytics rollup exists. |
| Mini sparklines on vault cards | Decorative static `<svg>` paths copied from the mock — purely visual, no real data. | Real per-vault LP-price sparkline once `LpPriceHistory` exposes a compact cross-range helper. |
| APY estimate caption ("est. APY 14.2%" / "18.7%") | Static strings matching the mock. | Real computed APY from `houseProfit / netBalance × annualization`. |
| "pool share" % on Your position card | Computed from `user_lp_balance / lpSupply × 100` using the just-fetched stats. No stub — real math. | — (this IS the real data) |

No visible "Coming Soon" placeholders on this page — everything the mock shows is either real data or a static visual matching the mock's own hardcoded copy. The stat-band numbers and APY caption are the only places the values diverge from "truth" and they're derived from the same stats the detail page already uses.

### ✗ New — must be added or schema-migrated

None. Bucket A.

## Assigns added (no new handlers, just new data reads)

The new `mount/3` expands slightly to load the cross-vault activity and user LP balances. All additions are straightforward async fetches that follow the same pattern as `PoolDetailLive`.

Added assigns:

- `:activities` — list of merged `%{"type", "pool", "wallet", "amount", "time", "tx_sig", "_created_at"}` rows (max 6 shown, stored up to 50 for live updates).
- `:user_sol_lp` — float, the user's bSOL balance (0.0 if no wallet). Used in Your position card on SOL vault.
- `:user_bux_lp` — float, the user's bBUX balance (0.0 if no wallet). Used in Your position card on BUX vault.
- `:sol_pool_share` — float, SOL-LP ÷ SOL vault supply × 100.
- `:bux_pool_share` — float, BUX-LP ÷ BUX vault supply × 100.

All existing assigns (`@pool_stats`, `@pool_loading`) are preserved.

## Handlers to preserve / add

**Existing handlers (preserved exactly):**

- `handle_async(:fetch_pool_stats, …)` — 3 branches (success / error / exit).
- `handle_info(_msg, socket)` — catch-all.

**New handlers (minimal additions):**

- `handle_async(:fetch_activities, …)` — merges sol+bux bet activity + pool_activity reads, assigns `:activities`.
- `handle_async(:fetch_user_lp_balances, …)` — fetches both LP balances in parallel, assigns `:user_sol_lp` / `:user_bux_lp`.
- `handle_info({:pool_activity, activity}, socket)` — prepends to `:activities`, takes 50. Matches the detail page's handler signature so the broadcast format stays consistent.

**PubSub subscriptions:**

- `"pool_activity:sol"` (on `connected?(socket)` only)
- `"pool_activity:bux"` (on `connected?(socket)` only)

Both topics already exist and are broadcast from `PoolDetailLive.handle_event("deposit"/"withdraw", …)` and `CoinFlipGame.settle_game/1` (bet activity). We subscribe, we never publish.

## JS hooks

- **`SolanaWallet`** — mounted on `#ds-site-header` by the DS header component. Already in place in Wave 0. Don't remove it, don't duplicate it on an outer element.
- No page-specific hooks. No chart, no copy-button, no infinite scroll.

## Tests required

### Component tests

None. No new DS components.

### LiveView tests

Extend `test/blockster_v2_web/live/pool_index_live_test.exs`. Existing assertions for "Liquidity Pools / SOL Pool / BUX Pool / How it works / Back to Play / /pool/sol / /pool/bux / animate-pulse / Live / animate-ping" will be rewritten because the new markup drops the "Back to Play" link and the `animate-pulse`/`animate-ping` classes (the mock uses `pulse-dot` keyframes but we don't import that CSS — instead we use Tailwind's `animate-pulse` on the live dots, verify).

New / kept assertions:

**Anonymous visitor at `/pool`:**
- Mounts, DS header + footer render
- "Liquidity Pools" headline + "Earn from every bet · On-chain settlement" eyebrow
- Total TVL / Bets settled / House profit stat-band cards present (3 stat cards)
- SOL Pool vault card + BUX Pool vault card each render with LP Price label, LP-token unit, "Enter SOL Pool →" / "Enter BUX Pool →" CTA text
- Both vault cards link to `/pool/sol` and `/pool/bux`
- How it works 3 steps (Deposit / Earn / Withdraw) render
- Pool activity section renders "Pool activity" headline (empty state acceptable on a fresh test DB)

**Route move:**
- `/pool` responds 200 under the `:redesign` live_session (same test framework — just assert `live(conn, ~p"/pool")` succeeds without redirect).

**Ensure Mnesia tables in setup**: copy the `ensure_mnesia_tables/0` pattern from `member_live/show_test.exs`, add `:user_lp_balances`, `:lp_price_history`, `:coin_flip_games`, `:pool_activities`, and the tables currently required (`user_solana_balances`, `user_bux_balances`, etc). Field order must match `mnesia_initializer.ex` exactly.

### Manual checks (on `bin/dev`)

- `/pool` loads logged in (wallet connected, real `@bux_balance`, header shows BUX pill)
- `/pool` loads anonymous (no wallet, connect button in header)
- Both vault cards render with real data after `fetch_pool_stats` resolves
- Your position card shows real LP balance when wallet is connected
- "Enter SOL Pool →" / "Enter BUX Pool →" navigation works
- Header nav "Pool" link has active underline (via `active="pool"` prop)
- Why Earn BUX banner is visible
- Footer renders at bottom (DS footer)
- No console errors
- Devtools Network tab: `/pool-stats`, `/lp-balance/*/sol`, `/lp-balance/*/bux` all fire and return 200
- `mix test` — zero new failures vs baseline

## Per-page commit message

`redesign(pool-index): liquidity pools page refresh · vault cards + activity band`

## Stubbed in v1

| Stub | What it shows now | What replaces it | Resolved by release |
|---|---|---|---|
| Page-header 3-stat band 24h aggregates | All-time totals from `pool_stats.{sol,bux}` summed, with the 24h sub-labels kept per the mock but values are cumulative | Real 24h rolling aggregates from a new analytics context | Analytics release |
| Mini sparklines on vault cards | Static decorative `<svg>` path from the mock | Real LP-price sparkline series from `LpPriceHistory` | Follow-up commit once a compact "last N points" helper exists |
| Est. APY caption on vault cards | Static "14.2%" / "18.7%" strings matching the mock | Real computed APY from profit/net × annualization | Analytics release |

## Fixed in same session

Any NEW test regressions outside the baseline, any pre-existing compilation warnings touched by the rebuild.

## Open items

- **Pulse dot keyframes**: the mock uses a custom `.pulse-dot` CSS keyframe. Tailwind's `animate-pulse` gives a softer effect. We'll use Tailwind's built-in for simplicity — matches other redesigned pages (homepage, hubs, play). The visual delta is minor.
- **Mock's activity row 6-col grid**: the existing `<.activity_table />` in `pool_components.ex` uses a different row layout (icon + flex content). Rather than reuse it and diverge from the mock, we render the 6-col grid inline in `pool_index_live.ex`'s render so this page matches the mock exactly without forcing the detail page to change.
- **Card hover effect**: mock's `.vault-card:hover` does `translateY(-4px)` + big shadow. Implemented via Tailwind `hover:-translate-y-1 hover:shadow-[0_30px_60px_-20px_rgba(0,0,0,0.35)] transition-transform transition-shadow duration-300`.
