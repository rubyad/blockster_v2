# Pool detail · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView module | `lib/blockster_v2_web/live/pool_detail_live.ex` (wholesale `render/1` rewrite; `mount/3` and every handler preserved) |
| Route(s) | `/pool/sol`, `/pool/bux` — moved from `:default` to `:redesign` live_session |
| Mock file | `docs/solana/pool_detail_mock.html` |
| Bucket | **A** — pure visual refresh, no schema changes, no new contexts |
| Wave | 3 (Page #9) |

## Mock structure (top to bottom)

1. **Design system header** (`<DesignSystem.header active="pool" … />`) with all prod assigns, `display_token="SOL"` on `/pool/sol` and `display_token="BUX"` on `/pool/bux`, Why Earn BUX banner on.
2. **Full-bleed pool banner hero** — gradient (SOL: emerald / BUX: lime) with subtle radial dot pattern + top-right glow.
   - Breadcrumb: `Pool / SOL Pool` (link back to `/pool`).
   - 12-col grid:
     - **Left 7-col**: identity (icon tile + "Bankroll Vault" eyebrow + "Live" pill + `SOL Pool`/`BUX Pool` 56-68px headline), LP price hero (64px mono + token unit + 24h change chip + "24h" label), 4-stat inline row (TVL / LP supply / Est. APY / Bets 24h) separated by 1px dividers.
     - **Right 5-col**: translucent "Your position" card — LP balance (36px), dollar/token estimate sub-line, 2-col pill strip (Cost basis / Unrealized P/L), days-as-LP caption with % annualized.
3. **Two-column main section** (`max-w-[1280px]`, `grid-cols-12 gap-6`):
   - **Left 4-col sticky order form** — white card rounded-2xl:
     - Deposit / Withdraw segmented tabs (bg-neutral-100 pill with active white slide).
     - "Your wallet" balance row: 2-col grid (SOL / SOL-LP or BUX / BUX-LP), small icon + mono number.
     - LP Price line (`1 SOL-LP = 1.0234 SOL`).
     - Amount input (large mono 28px), `½` and `MAX` quick buttons, balance + dollar estimate sub-row.
     - Output preview in a tinted card (`#00DC82/8` background for SOL, lime for BUX) with "You receive ≈", "New pool share" footer row.
     - Submit button: `bg-[#0a0a0a] text-white py-3.5 rounded-2xl`.
     - Helpful info card below ("How earnings work" + "Read the bankroll docs →").
   - **Right 8-col** stacked `space-y-6`:
     - **LP price chart** card (white rounded-2xl) — header with `SOL-LP price` eyebrow + big price + 24h change + timeframe pill row (`1H / 24H / 7D / 30D / All`), chart SVG container below (the existing PriceChart hook stays in a dark container).
     - **Stats grid** — 8 white rounded-2xl cards in a 4-col grid: LP price / LP supply / Volume 24h / Bets 24h / Win rate 24h / Profit 24h / Payout 24h / House edge.
     - **Activity table** — white rounded-2xl card. Header with live pulse dot + "Activity · Live" label + tab pills (All / Wins / Losses / Liquidity). Rows in a `grid-cols-[180px_1fr_140px_60px]` layout: icon tile + win/loss/deposit/withdraw label, wallet avatar + short wallet, right-aligned profit/amount, tx link. Footer with "Showing N of M events" + "Load more" button.
4. **Footer** — `<DesignSystem.footer />`.

## Decisions applied from release plan

- **Bucket A**: no schema migrations, no new contexts, no new handlers.
- **Reuse existing `pool_components.ex`**: the `<.lp_price_chart>`, `<.pool_stats_grid>`, `<.activity_table>`, `<.coin_flip_fairness_modal>` function components are kept and restyled **in place** so their APIs (and all their embedded tx-link / solscan / fairness modal logic) don't change. Only callers of these components are `PoolDetailLive` itself; `PoolIndexLive` uses different inline markup, so restyling is safe.
- **Route moves to `:redesign` live_session** (same pattern as pages #1–#8). Removed from `:default`.
- **Legacy file preservation**: current `lib/blockster_v2_web/live/pool_detail_live.ex` copied to `lib/blockster_v2_web/live/pool_detail_live/legacy/pool_detail_live_pre_redesign.ex`, renamed to `BlocksterV2Web.PoolDetailLive.Legacy.PreRedesign`. No other modules reference it, so it's dormant.
- **Test discipline (D4/D5)**: extend existing `pool_detail_live_test.exs` with assertions for the new template. Existing handler tests (tab switching, max button, deposit/withdraw, tx_confirmed/tx_failed, chart timeframe, activity tabs, balance display, pool share) all stay green.
- **Your position card**: real data when wallet connected, 2x2 stat strip shows LP balance + dollar/token estimate; Cost basis and Unrealized P/L are **not yet tracked** — those two rows show `—` placeholder strings. Noted in stub register below.
- **Est. APY** on the hero stats row: static `14.2%` on SOL / `18.7%` on BUX — same stub as pool index.

## Visual components consumed

- `<BlocksterV2Web.DesignSystem.header active="pool" display_token={…} … />` ✓ existing (Wave 0)
- `<BlocksterV2Web.DesignSystem.footer />` ✓ existing (Wave 0)
- `<BlocksterV2Web.DesignSystem.eyebrow>` ✓ existing (Wave 0)
- `<.lp_price_chart … />` ✓ existing (pool_components.ex) — **restyled in place** to match mock header layout + timeframe pill style.
- `<.pool_stats_grid … />` ✓ existing — **restyled in place** to 8 white cards on a 4-col grid with the exact stat labels + sub-lines from the mock.
- `<.activity_table … />` ✓ existing — **restyled in place** to match mock (icon tile + wallet avatar row + right-aligned amount + tx link). All embedded fairness modal / tx link logic preserved.
- `<.coin_flip_fairness_modal … />` ✓ existing — no visual change, still rendered at page root.

**No new DS components needed.** No new pool_components.ex components. The full-bleed pool banner hero, two-column grid, order form, and wallet balance row are all page-specific markup inlined in `PoolDetailLive.render/1`.

## Data dependencies

### ✓ Existing — already in production

Every assign in `mount/3` is kept exactly:

- `@vault_type`, `@header_token`, `@pool_stats`, `@pool_loading`
- `@tab`, `@amount`, `@processing` (order form state)
- `@timeframe`, `@chart_price_stats` (chart state)
- `@activity_tab`, `@activities` (activity filter state)
- `@show_fairness_modal`, `@fairness_game` (modal state)
- `@lp_balances` (`%{bsol: _, bbux: _}`)
- `@balances` (`%{"SOL" => _, "BUX" => _}`)
- `@period_stats` (`%{total, wins, volume, payout, profit}`)
- `@wallet_address`, `@current_user` (for auth branches)
- Default `WalletAuthEvents.default_assigns()` injected for anonymous visitors.

Every existing mount-time side effect is kept:

- PubSub subscriptions:
  - `"bux_balance:#{current_user.id}"` (logged-in only)
  - `"pool_activity:#{vault_type}"`
  - `"pool_chart:#{vault_type}"`
- Mnesia reads: `CoinFlipGame.period_stats/2`, `CoinFlipGame.get_recent_games_by_vault/2`, `:mnesia.dirty_index_read(:pool_activities, …)`.
- Async tasks: `start_async(:fetch_pool_stats, …)`, `start_async(:sync_on_mount, …)`.

### ⚠ Stubbed in v1

| Stub | What shows | Replaces it |
|---|---|---|
| "Your position · Cost basis / Unrealized P/L" | `—` placeholder (cost basis of an LP deposit is not tracked in Mnesia) | Real cost-basis tracking once deposits write a running average into `user_lp_balances` or a new table | Analytics release |
| "You've been an LP for X days" caption | Hidden when we can't compute it (no `first_deposit_at` tracked) | Real first-deposit timestamp once LP deposits record their entry point | Analytics release |
| Hero stats row · Est. APY | Static `14.2%` (SOL) / `18.7%` (BUX) — same stub as pool index | Real computed APY from `houseProfit / netBalance × annualization` | Analytics release |
| Hero stats row · Bets 24h / 24h change chip | "Bets" uses `period_stats.total` (already 24H when user loads the page); 24h change pct on the LP price is hidden unless `chart_price_stats.change_pct` is populated | No change — this IS real data once the user clicks the 24H timeframe, which mount does by default |
| Activity table "Showing 6 of 487 events" | Shows `Enum.count(filtered)` live, the "487" total is the same `Enum.count(activities)` — no real denominator behind it | Real server-side paginated total count | Follow-up commit |
| Activity table "Load more" button | Inert (no paging handler) | Paginated load-more action | Follow-up commit |

### ✗ New — must be added or schema-migrated

None. Bucket A.

## Handlers to preserve

Every `phx-click`, `phx-submit`, `start_async`, `handle_info`, `handle_async` in the current LiveView MUST be wired up by the new template exactly as today:

**`handle_event`:**
- `"switch_tab"` → tab state
- `"update_amount"` → amount input
- `"set_max"` → MAX button
- `"deposit"` → kick off async build_tx (deposit)
- `"withdraw"` → kick off async build_tx (withdraw)
- `"tx_confirmed"` (from PoolHook JS) → finalize + Mnesia write + PubSub broadcast + async sync_post_tx
- `"tx_failed"` (from PoolHook JS) → clear processing + flash
- `"set_chart_timeframe"` → timeframe + chart data push
- `"request_chart_data"` → chart data push (initial)
- `"set_activity_tab"` → activity filter
- `"show_fairness_modal"` / `"hide_fairness_modal"` / `"stop_propagation"` → modal state
- `"show_wallet_selector"` → WalletAuthEvents macro (auto-injected)
- `"disconnect_wallet"` → WalletAuthEvents macro
- `"wallet_connected"` → WalletAuthEvents macro

**`handle_info`:**
- `{:bux_balance_update, …}` → refetch SOL/BUX/LP balances
- `{:token_balances_update, …}` → refetch SOL/BUX balances
- `{:pool_activity, activity}` → prepend to activity list
- `{:chart_point, point}` → push chart_update to JS
- catch-all `handle_info(_msg, socket)`

**`handle_async`:**
- `:fetch_pool_stats` (ok/error/exit branches)
- `:sync_on_mount` + `:sync_post_tx`
- `:build_tx` — on success pushes `"sign_deposit"` or `"sign_withdraw"` to PoolHook JS (data shape `{transaction: base64, vault_type: "sol"|"bux"}`)

**PubSub subscriptions (identical):**
- `"bux_balance:#{user_id}"` (logged-in, on `connected?`)
- `"pool_activity:#{vault_type}"` (on `connected?`)
- `"pool_chart:#{vault_type}"` (on `connected?`)

## JS hooks

- **`PoolHook`** — mounted on the outermost `#pool-detail-page` div. Listens for `sign_deposit` / `sign_withdraw` push_events (`{transaction: base64, vault_type: …}`) and pushes back `tx_confirmed` / `tx_failed` events. **Must stay on the same outer element with `phx-hook="PoolHook"` and a stable `id`.**
- **`PriceChart`** — mounted via the `<.lp_price_chart>` component on `#price-chart-{vault_type}` with `phx-hook="PriceChart"`, `phx-update="ignore"`, `data-vault-type={@vault_type}`. Listens for `chart_data` (bulk set) and `chart_update` (single point) push_events. Must keep `phx-update="ignore"` and the `data-vault-type` attr intact.
- **`SolanaWallet`** — mounted on `#ds-site-header` by the DS header component. Already in place in Wave 0.

No new JS hooks.

## Tests required

### Component tests

None. No new DS components.

### LiveView tests

Extend `test/blockster_v2_web/live/pool_detail_live_test.exs` (already in the baseline — per `test_baseline_redesign.md` the file may be in the baseline but new assertions must pass).

**New / updated assertions:**

- `"SOL Pool"` headline renders (banner hero) with `"Bankroll Vault"` eyebrow + `"Live"` pill
- `"Current LP price"` label renders on SOL, `"Current LP price"` on BUX
- Deposit/Withdraw segmented tabs render (existing assertions carry over)
- Order form has `"Your wallet"`, `"LP Price"`, `"You receive"` labels
- Chart card renders `"SOL-LP price"` eyebrow + timeframe buttons (existing assertion carries over with new copy)
- Stats grid renders 8 card labels: `LP price`, `LP supply`, `Volume 24h`, `Bets 24h`, `Win rate 24h`, `Profit 24h`, `Payout 24h`, `House edge` (**or `realized 24h` sub-line**).
- Activity table renders the live pulse + tab pills + `"Showing N of M events"` footer
- Back-to-pool breadcrumb is a navigate link to `/pool`
- DS header + footer render on both vaults
- `/pool/invalid` still redirects to `/pool` (kept)
- Anonymous visitor still sees `"Connect Wallet"` CTA on the submit button
- Logged-in user with LP balance still sees `"Pool share"` copy

**Existing handler tests stay green**: tab switching, max button, amount keyup, set_max (deposit + withdraw), chart timeframe button, activity tab switching, tx_confirmed, tx_failed, deposit + withdraw click, balance display.

### Manual checks (on `bin/dev`)

- `/pool/sol` loads logged in (wallet connected, real SOL balance + bSOL balance in "Your wallet" row)
- `/pool/sol` loads anonymous (connect button in DS header + submit button)
- `/pool/bux` loads both states
- Deposit flow: enter amount, click Deposit, Phantom popup, approve, tx lands, row appears in activity, flash shows confirmed, balances refresh
- Withdraw flow: switch tab, enter LP amount, click Withdraw, Phantom popup, approve, row appears, balances refresh
- Chart loads on mount + updates when bet settles (live via `"pool_chart:{vault}"` topic)
- Timeframe switcher: click 1H → 24H → 7D → 30D → All, chart + stats grid updates each time
- Activity tab switcher: All → Wins → Losses → Liquidity, filters work
- Activity row Solscan links open commitment / bet / settlement txs in new tab
- Fairness modal opens on a settled game → click Verify → SHA256 breakdown shows, close with outside click or X button
- `mix test` — zero new failures vs baseline

## Per-page commit message

`redesign(pool-detail): vault detail page refresh · gradient hero + 2-col layout + restyled chart/stats/activity`

## Stubbed in v1

| Stub | What it shows now | What replaces it | Resolved by release |
|---|---|---|---|
| Your position Cost basis / Unrealized P/L / days-as-LP caption | `—` placeholders (no cost-basis tracking in Mnesia) | Real running-average cost basis tracked on deposit | Analytics release |
| Hero stats row Est. APY | Static `14.2%` / `18.7%` | Computed from profit/net × annualization | Analytics release |
| Activity table total events count | Shows local `length(@activities)` | Real paginated server-side total | Follow-up commit |
| Activity table Load more button | Inert (no handler) | Paginated load-more | Follow-up commit |

## Fixed in same session

Any NEW test regressions outside the baseline, any pre-existing compilation warnings touched by the rewrite.

## Open items

- **`display_token` on DS header**: `/pool/sol` uses `display_token="SOL"` (pill shows SOL balance, 4 decimals). `/pool/bux` uses default `display_token="BUX"` (pill shows BUX balance, 2 decimals). This matches the coin-flip page's decision to show the active token.
- **Pulse-dot animation**: the mock uses a custom `.pulse-dot` keyframe. We use Tailwind's `animate-pulse` everywhere, same as the pool index + homepage, for consistency. The visual delta is minor.
- **Mock's hero 24h change chip**: the mock shows `▲ + 2.34%` in lime. In v1 we only render the chip when `chart_price_stats.change_pct` is non-nil (so the static `+ 2.34%` from the mock is replaced with real live data).
- **Pool Banner gradient for BUX**: the mock only has SOL's emerald gradient. For BUX we use the same lime gradient from the pool index vault card to match the index → detail transition.
