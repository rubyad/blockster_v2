# Airdrop · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView module | `lib/blockster_v2_web/live/airdrop_live.ex` (wholesale `render/1` rewrite; `mount/3` and every handler / async / info clause preserved) |
| Route | `/airdrop` — moved from `:default` to `:redesign` live_session |
| Mock file | `docs/solana/airdrop_mock.html` |
| Bucket | **A** — pure visual refresh, no schema changes, no new contexts |
| Wave | 3 (Page #10 — last page of Wave 3) |

## Mock structure (top to bottom)

1. **Design system header** (`<DesignSystem.header active="airdrop" … />`) with all
   prod assigns and the Why Earn BUX banner enabled. Default `display_token="BUX"`
   is correct here — the airdrop is a BUX-entry surface.
2. **Editorial page hero** (`pt-12 pb-10`, `grid-cols-12`) — left 7-col headline
   block, right 5-col 3-stat band:
   - Eyebrow: `Round {round_id} · Open for entries` (or `Drawn` / `Opening soon`),
     followed by a green `Live` pulse pill while the round is open.
   - 60–80px `article-title` headline. **`$2,000 / up for grabs`** when open,
     **`The airdrop has been drawn`** dark variant after draw. Currency value comes
     from `prize_summary.total`.
   - Sub copy: `Redeem the BUX you earned reading. 1 BUX = 1 entry. 33 winners
     drawn on chain when the countdown hits zero. Provably fair, settled on Solana.`
   - Right 3-stat grid: `Total pool` ($X · USDC + SOL) · `Winners` (33 · drawn at
     close) · `Rate` (1:1 · BUX → entry).
3. **OPEN STATE — Entry phase** (rendered when `airdrop_drawn? == false`)
   - Two-column section (`grid-cols-12 gap-8`, `border-t border-neutral-200/70`):
     - **Left 7-col stack** (`space-y-6`):
       1. **Countdown card** — white rounded-2xl, top header `Drawing on` eyebrow
          + bold formatted end_time + `Round N` clock badge on the right. Below
          a 4-col grid of neutral-50 tiles (40px mono number + uppercase label):
          Days / Hours / Min / Sec. Pads each value to two digits.
       2. **Prize distribution card** — 4-col grid of tinted prize tiles
          (1st = amber gradient, 2nd = neutral gradient, 3rd = orange gradient,
          4th–33rd = lime tinted). Eyebrow `Prize distribution` + section title
          `33 winners · $2,000 total`.
       3. **Pool stats card** — 3-col grid: `Total deposited` (BUX entries) ·
          `Participants` (readers entered) · `Avg entry` (BUX / player).
       4. **Provably fair commitment card** — eyebrow + small copy + neutral
          inset showing `commitment_hash` (mono break-all). Footnote with link
          to commitment tx. Hidden when no round / no commitment.
     - **Right 5-col sticky entry form** (`sticky top-[100px] self-start`):
       - White rounded-2xl card with **dark `#0a0a0a` header strip** (`Enter the
         airdrop` eyebrow + `Redeem BUX → get entries` + lime icon tile).
       - Body padding 6:
         - Balance display row (neutral-50 inset).
         - 20px mono input + lime-on-black `MAX` pill (existing
           `phx-keyup="update_redeem_amount"` + `phx-click="set_max"`).
         - Sub-row: `= N entries` + `Position #X – #Y` projection line.
         - 4-col **quick amount chips** (100 / 1,000 / 2,500 / 10,000) — each
           sets `redeem_amount` via a new `set_amount` event handler. Selected
           chip gets a black border. (Stub-light: tiny new handler — see below.)
         - Odds preview neutral inset: `Your share of pool`, `Odds (any prize)`,
           `Expected value` (uses live total_entries when available).
         - Black `Redeem N BUX` submit button (existing `phx-click="redeem_bux"`
           with full state machine — Connect Wallet / Verify Phone / Enter
           Amount / Insufficient Balance / Redeeming…).
         - Footnote `Phone verified · Solana wallet connected` line (only when
           both are true).
       - Below the form, **Your entries · N redemptions** receipt list — small
         eyebrow + stack of receipt cards (white, rounded-2xl, with green check
         icon + amount + position range + datetime + Solscan tx link). Same
         data as today's `<.receipt_panel>` but restyled.
4. **HOW IT WORKS** band (`py-12 border-t`) — center eyebrow + 36–44px article
   title + 3-col grid of white cards numbered 1/2/3 with lime icon tiles. Always
   rendered (open + drawn states).
5. **State divider** — only renders when `airdrop_drawn?` is true. Mono mini
   divider line with `Drawn state · winners revealed ↓` label.
6. **DRAWN STATE — Celebration** (rendered when `airdrop_drawn? == true`)
   - **Dark celebration banner** — `bg-[#0a0a0a]`, lime accent gradient + radial
     dot pattern overlay. Center `Round N · drawn` lime eyebrow, 44–56px white
     headline `The airdrop has been drawn`, sub copy. Two CTA chips: lime
     `Verify fairness` (opens existing modal) + glass `View on Solscan ↗` (links
     to draw_tx if available, else airdrop program account).
   - **Top 3 podium** — 3-col grid of tinted cards (gold / silver / bronze),
     each with the place label, prize value, truncated wallet, and position.
   - **Verification metadata card** — 3-col grid: `Slot at close` + close tx
     link · `Server seed (revealed)` (mono ellipsis) · `SHA-256 verification`
     green check pill. Pulled from `verification_data`.
   - **Full winners table** — white rounded-2xl card. Header with eyebrow `All
     33 winners` + section title `Round N results` + meta line. Column header
     row (5-col grid `[60px_1fr_140px_140px_120px]`: # · Wallet · Position ·
     Prize · Status). Body uses the existing `@winners` collection, rendered
     in same 5-col grid. Top 3 rows tinted (yellow/neutral/orange). Status
     column delegates to a new inline status pill helper that mirrors the
     existing `winner_status` logic (Claimed badge with tx link / Claim CTA
     button when current_user matches and wallet_connected / Connect-wallet
     placeholder / em-dash). Footer "Show all 33 winners" toggle is **stub-only**
     in v1 (the table renders all rows already; toggle is hidden when length(winners) ≤ 8).
   - **Your receipt panel** — gold gradient card, only when current_user has
     a winning entry. Shows trophy icon + position range + place + prize +
     existing claim CTA (or claimed badge). When user has only losing entries
     in a drawn round, render the small white "Your other entries" card with
     a "See receipts" toggle (anchor to the receipts list above).
7. **Footer** — `<DesignSystem.footer />`.

## Decisions applied from release plan

- **Bucket A**: no schema, no new contexts, no new on-chain calls. Every
  existing handler / assign / PubSub topic / JS hook stays.
- **`<DesignSystem.header active="airdrop" />`** with default `display_token="BUX"`
  (airdrop is BUX-first). The header has `phx-hook="SolanaWallet"` baked in —
  do not duplicate or remove.
- **Route move**: `live "/airdrop", AirdropLive, :index` moves from `:default`
  to `:redesign` live_session (matches pages #1–#9).
- **Legacy preservation**: copy current file to
  `lib/blockster_v2_web/live/airdrop_live/legacy/airdrop_live_pre_redesign.ex`
  with module renamed `BlocksterV2Web.AirdropLive.Legacy.PreRedesign`.
- **No new DS components**: every section is page-inlined markup. Inlining
  beats premature DS extraction at this stage; if a future page needs the
  countdown grid or prize tile patterns we extract them then.
- **Reuse `<DesignSystem.footer />`** + DS header — matches every other
  redesigned page.
- **No new schema migrations.**
- **One new tiny event handler**: `set_amount` (sets `redeem_amount` from a
  quick-chip click value, parallel to `set_max`). Justified by mock fidelity
  for the 4 quick-amount chips. 5 LOC.

## Visual components consumed

- `<BlocksterV2Web.DesignSystem.header active="airdrop" … />` ✓ existing (Wave 0)
- `<BlocksterV2Web.DesignSystem.footer />` ✓ existing (Wave 0)
- `<BlocksterV2Web.DesignSystem.eyebrow>` ✓ existing (Wave 0)

**No new DS components needed.** The countdown tile, prize tile, podium tile,
receipt card, winners table row, and entry-form layout are all page-specific
markup inlined in `AirdropLive.render/1`.

## Data dependencies

### ✓ Existing — already in production

Every assign in `mount/3` is preserved exactly:

- `@page_title`, `@user_bux_balance`, `@airdrop_end_time`, `@prize_summary`
  (`%{total, first, second, third, rest, rest_count}`)
- `@redeem_amount`, `@time_remaining` (`%{days, hours, minutes, seconds, total_seconds}`)
- `@current_round`, `@user_entries` (reversed list of `Airdrop.UserEntry`),
  `@entry_results` (`%{entry_id => [winner, …]}`)
- `@total_entries`, `@participant_count`
- `@wallet_connected`, `@airdrop_drawn`, `@winners`, `@verification_data`
- `@redeeming`, `@claiming_index`, `@show_fairness_modal`
- `@airdrop_sidebar_left_banners`, `@airdrop_sidebar_right_banners` — kept on
  the assigns map but **no longer rendered** in v1 (the new layout uses the
  full 1280px width with no sidebar slots; the mock has no sidebar). They
  stay assigned so any test that asserts on them or any future placement
  swap is one-line. Note in stub register.
- Default `WalletAuthEvents.default_assigns/0` available because
  `use BlocksterV2Web, :live_view` injects the macro.

Every existing mount-time side effect is preserved:

- PubSub: `Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "airdrop:#{round_id}")`
  inside `connected?(socket)`.
- `:timer.send_interval(1000, self(), :tick)` for the countdown.
- `Airdrop.get_current_round/0`, `get_user_entries/2`, `get_total_entries/1`,
  `get_participant_count/1`, `get_winners/1`, `get_verification_data/1`,
  `prize_summary/0` calls in mount.

### ⚠ Stubbed in v1

| Stub | What shows | Replaces it |
|---|---|---|
| Header strip Solana mainnet pill in mock | Dropped — DS header has its own Solana mainnet indicator already | n/a |
| Sidebar ad banner placements (`airdrop_sidebar_left`, `airdrop_sidebar_right`) | Hidden in the new layout (mock has no sidebars). Assigns still loaded so the data is available for a later layout that re-introduces sidebars without changing the loader. | Future ad placement reshuffle |
| Entry form quick-chip preset values (100 / 1,000 / 2,500 / 10,000) | Hardcoded preset list — mock fidelity. Active chip is detected from current `redeem_amount`. | Configurable preset list (likely never — these match the mock and the user's intent) |
| Entry form Position projection line (`#X – #Y`) | Computed from `total_entries + 1` to `total_entries + parsed_amount` (reflects current pool size). | n/a — this IS real data |
| Entry form `Your share of pool` / `Odds (any prize)` / `Expected value` | Computed from `parsed_amount / (total_entries + parsed_amount)`. Expected value uses 33 winners and `prize_summary.total`. | n/a — real-time math |
| Entry form `Phone verified · Solana wallet connected` footer | Conditionally shown when both are true. Hidden otherwise. Plain text indicator. | n/a |
| Drawn-state hero `View on Solscan` CTA | Falls back to the airdrop program account on Solscan when no `verification_data.draw_tx` is set yet. | Per-round draw_tx wired into verification data (already exists if present) |
| Winners table "Show all 33 winners" toggle | The full winners list is already rendered in v1; toggle is hidden when `length(@winners) ≤ 8`. When > 8 we render the top 8 + a `phx-click` toggle that flips a `:show_all_winners` socket assign. (One new bool assign + one new event handler — mock fidelity.) | n/a |

### ✗ New — must be added or schema-migrated

None. Bucket A.

**One new event handler** + **one new socket assign** for mock fidelity:

- `handle_event("set_amount", %{"value" => v}, socket)` — parses `v` to integer
  and writes to `redeem_amount`. Mirrors `set_max`. ~5 LOC.
- `handle_event("toggle_show_all_winners", _params, socket)` — flips
  `:show_all_winners` boolean. Default `false`. ~3 LOC.
- New assign `:show_all_winners` initialized to `false` in mount.

## Handlers to preserve

Every `handle_event`, `handle_async`, `handle_info` in the current LiveView
MUST be wired up by the new template exactly as today:

**`handle_event`:**
- `"update_redeem_amount"` → input keyup handler
- `"set_max"` → MAX button (existing)
- `"redeem_bux"` → kicks off `:build_deposit_tx` start_async
- `"airdrop_deposit_confirmed"` (from JS hook) → kicks off `:redeem_bux` start_async
- `"airdrop_deposit_error"` (from JS hook) → flashes error
- `"claim_prize"` → kicks off `:build_claim_tx` start_async
- `"airdrop_claim_confirmed"` (from JS hook) → kicks off `:claim_prize` start_async
- `"airdrop_claim_error"` (from JS hook) → flashes error
- `"show_fairness_modal"` / `"close_fairness_modal"` / `"stop_propagation"` → modal state
- `"show_wallet_selector"` / `"disconnect_wallet"` / `"wallet_connected"` →
  WalletAuthEvents macro (auto-injected)

**New (mock fidelity):**
- `"set_amount"` → quick-chip preset
- `"toggle_show_all_winners"` → expand/collapse winners table

**`handle_async`:**
- `:build_deposit_tx` (ok / error / exit branches) — pushes `sign_airdrop_deposit`
- `:build_claim_tx` (ok / error / exit branches) — pushes `sign_airdrop_claim`
- `:redeem_bux` (ok / error / exit branches) — Mnesia write + flash + assigns
- `:claim_prize` (ok / error / exit branches) — winners list update + flash

**`handle_info`:**
- `:tick` → countdown refresh
- `{:airdrop_deposit, _round_id, total_entries, participant_count}` → live pool stats
- `{:airdrop_drawn, round_id, winners}` → state transition
- `{:airdrop_winner_revealed, _round_id, winner}` → upsert winner

**PubSub subscriptions (identical):**
- `"airdrop:#{round_id}"` (logged-in or anonymous, on `connected?`)
- `:timer.send_interval(1000, …)` for countdown ticks

## JS hooks

- **`AirdropSolanaHook`** — currently mounted on a hidden
  `#airdrop-solana-hook` div with `phx-hook="AirdropSolanaHook"`. The hook
  listens for `sign_airdrop_deposit` / `sign_airdrop_claim` push_events and
  pushes back `airdrop_deposit_confirmed` / `airdrop_deposit_error` /
  `airdrop_claim_confirmed` / `airdrop_claim_error`. **Preserve the same
  element + id + hook attribute exactly** — the hook keys off this element
  and the existing handler events match its push_event names.
- **`SolanaWallet`** — mounted on `#ds-site-header` by the DS header. Already
  in place after Wave 0.

No new JS hooks.

## Tests required

### Component tests

None. No new DS components.

### LiveView tests

Extend `test/blockster_v2_web/live/airdrop_live_test.exs` (already in the
baseline — per `test_baseline_redesign.md` the file may be in the baseline
but new assertions must pass).

**Existing tests stay green.** Most assertions are copy-text assertions
(`"Days"`, `"Hours"`, `"Min"`, `"Sec"`, `"$250"`, `"How It Works"`, `"Connect
Wallet to Enter"`, etc.) which all carry over to the new layout. A handful
of copy strings change — update those in place:

- `"Drawing On"` / `"Drawing Complete"` — kept on the countdown card eyebrow.
  Mock says `Drawing on`; lower-case to match. **Update existing test.**
- `"How It Works"` → kept (`"How it works"` in mock — case sensitive). Mock
  uses `"How it works"`; **update existing test** to assert lowercase.
- `"The Airdrop Has Been Drawn"` → mock says `"The airdrop has been drawn"`.
  **Update existing test** for case.
- `"Congratulations to our 33 winners"` → mock says `"Congratulations to all
  33 winners. The provably-fair algorithm is publicly verifiable."` **Update
  existing test** copy.
- `"Enter the Airdrop"` → mock says `"Enter the airdrop"`. **Update existing
  test.**
- `"All 33 Winners"` → mock says `"All 33 winners"`. **Update existing test.**
- `"Your Entries"` → mock says `"Your entries"` (lowercase 'e'). **Update
  existing test.**
- `"Drawing Complete"` → kept verbatim on the drawn-state countdown subhead
  (or replaced with `"Round drawn"`). **Decide once writing the template.**

**New / updated assertions:**

- DS header renders with `id="ds-site-header"` and `phx-hook="SolanaWallet"`
- Header `Airdrop` nav link is active
- Why Earn BUX banner renders (`"Why Earn BUX?"`)
- Editorial page hero renders the title `"$2,000"` and `"up for grabs"` (or
  the dark drawn-state title) and the right-side 3-stat band with `"Total
  pool"`, `"Winners"`, `"Rate"` labels
- Countdown card renders all 4 tile labels (`Days`, `Hours`, `Min`, `Sec`)
- Prize distribution card renders `"Prize distribution"` eyebrow + `"33 winners"`
- Provably fair commitment card renders `"Provably fair commitment"` eyebrow
  when `current_round.commitment_hash` is set
- Sticky entry form renders `"Enter the airdrop"` (dark header) + `"Your BUX
  balance"` + `"BUX to redeem"` label
- Quick-amount chips render (`100`, `1,000`, `2,500`, `10,000`) and clicking
  one updates the amount (use new `set_amount` handler)
- How it works section: `"How it works"` + `"Earn BUX reading"` + `"Redeem · 1
  BUX = 1 entry"` + `"33 winners drawn on chain"`
- Drawn state: dark celebration banner copy renders + top-3 podium + winners
  table headers (`#`, `Wallet`, `Position`, `Prize`, `Status`)
- Show all winners toggle does NOT render when winners ≤ 8 (always the case
  in tests since `create_drawn_round` creates 33 winners — toggle DOES render,
  test that clicking it expands)
- Footer renders (`"Where the chain meets the model."`)

**Existing handler tests stay green**: MAX button, redeem button, claim flow,
verify fairness modal open/close, PubSub real-time updates, input validation.
The handler bodies are untouched so the Phoenix `view |> element(...) |>
render_*` tests resolve identically.

### setup_mnesia coverage

Existing `setup_mnesia/1` already declares `user_bux_balances` +
`user_rogue_balances`. The new template does NOT introduce any new Mnesia
table reads (the entry/redemption flow goes through Postgres-backed
`Airdrop.redeem_bux/4` which already works in test). No expansion needed.

### Manual checks (on `bin/dev`)

- `/airdrop` loads logged-in (round open, BUX balance shows in entry form)
- `/airdrop` loads anonymous (Connect Wallet CTA on submit, balance hidden)
- Countdown ticks each second
- Quick chip click updates amount + entry preview math + odds preview
- MAX button fills full balance
- Deposit flow: enter amount, click `Redeem N BUX`, Phantom popup, approve,
  tx lands, receipt card appears, balance refreshes, flash shows confirmed
- Claim flow (drawn round): click `Claim $X` from your-receipt or winners
  table row, Phantom popup, approve, status updates to `Claimed`
- PubSub: another browser deposits → pool stats update live
- PubSub: trigger `{:airdrop_drawn, ...}` via console → state transitions to
  drawn, banner + podium + table render
- Verify fairness modal: opens, closes via Close button + Escape key
- DS header pill shows BUX balance, disconnect wallet works
- `mix test` — zero new failures vs baseline

## Per-page commit message

`redesign(airdrop): airdrop page refresh · editorial hero + countdown + sticky entry + dark drawn-state celebration`

## Stubbed in v1

| Stub | What it shows now | What replaces it | Resolved by release |
|---|---|---|---|
| Sidebar ad placements (`airdrop_sidebar_left`, `airdrop_sidebar_right`) | Loaded into assigns but not rendered (mock has no sidebar slot) | Re-introduce when a new layout brings sidebars back, or move ads to a different placement | Ad placement reshuffle (TBD) |
| Drawn-state hero `View on Solscan` link target | Falls back to airdrop program account when no per-round `draw_tx` is recorded | Real `draw_tx` field on the verification data → linked to that exact tx | Already supported when data is present |
| Winners table "Show all winners" toggle | Default-collapsed top-8 view with toggle to expand to all 33 | n/a — this IS the v1 behavior | Locked in v1 |

## Fixed in same session

Any NEW test regressions outside the baseline, any pre-existing compilation
warnings touched by the rewrite.

## Open items

- **Drawn-state copy decision** — `Drawing Complete` (current) vs `Round drawn`
  (mock-faithful). Will pick during template write — both pass tests if
  asserted on whatever ships.
- **`AirdropSolanaHook` element placement** — currently a top-level hidden div.
  In the new template it stays at the very top of the page-root container so
  push_events still flow. Verified safe — the hook does no DOM querying.
- **Phantom simulation warning on devnet** — same cross-RPC propagation issue
  as Pool detail and Coin Flip. Expected on devnet, parked until mainnet.
  See the master stub register.
