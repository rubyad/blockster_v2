# Wallet Connect Modal · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| Component module | `lib/blockster_v2_web/components/wallet_components.ex` (`wallet_selector_modal/1` rewritten, `connect_button/1` preserved) |
| Route(s) | N/A — this is a component rendered in both `app.html.heex` and `redesign.html.heex` layouts |
| Mock file | `docs/solana/wallet_modal_mock.html` |
| Bucket | **A** — pure visual refresh, no schema changes, no new contexts |
| Wave | 5 (Page #15 — first page of Wave 5 Discovery) |

## Mock structure (top to bottom)

The mock shows 2 stacked states. In production, the modal renders one state at a time
based on the `@connecting` assign.

### State 1 — Wallet Selection (default, `connecting == false`)

1. **Modal backdrop** — fixed overlay with dark semi-transparent gradient +
   subtle lime dot-grid pattern (`radial-gradient` on `::before` pseudo-element).

2. **Modal card** (`max-w-[440px]`, white, `rounded-3xl`, heavy shadow + ring):
   - **Top bar**: Blockster icon (24×24 rounded-md) + "SIGN IN" eyebrow label (11px
     uppercase tracking-[0.16em]) + close button (32×32 rounded-full, neutral-100 bg,
     X SVG icon).
   - **Title section**: h2 "Connect a Solana wallet" (26px, article-title tracking) +
     subtitle "Pick the wallet you want to use to sign in. Blockster never sees your
     seed phrase or private keys." (13px, neutral-500).
   - **Wallet rows** (`px-4 pb-2 space-y-2`): Each wallet is a `<button>` with:
     - Brand badge (48×48 `rounded-xl`, gradient bg per wallet, brand SVG icon, shadow + ring)
     - Name (15px bold) + detected/install badge:
       - Detected: green-tinted pill (9px uppercase) with green dot + "Detected"
       - Not installed: neutral pill (9px uppercase) with "Install"
     - Action: detected → "Connect" black rounded-full button with arrow SVG;
       not installed → "Get" white bordered rounded-full button with external-link SVG
   - **Footer**: lime info circle (28×28, lime-tinted bg + border) + "What's a wallet?"
     link + explanation text. Below: Terms + Privacy Policy links (10px, neutral-400).

### State 2 — Connecting (wallet selected, `connecting == true`)

1. **Same modal backdrop** as State 1.

2. **Modal card** (same frame):
   - **Top bar**: "Back" button (left-arrow + text, 11px uppercase tracking) +
     close button (same as State 1).
   - **Big wallet badge** (centered): 80×80 rounded-2xl brand badge with heavier
     shadow. Spinning lime ring (`<svg>` circle with `stroke-dasharray`, CSS
     `animation: spin 0.9s linear infinite`).
   - **Title**: "Opening [WalletName]" (24px, article-title tracking).
   - **Subtitle**: "Approve the connection in your [WalletName] popup. We'll bring
     you back here once you sign." (13px, neutral-500).
   - **Progress shimmer strip**: 4px rounded-full bar, lime shimmer animation
     (`background-size: 200%`, `animation: shimmer 1.2s linear infinite`).
   - **Status steps** (3 rows):
     - "Wallet detected" — green circle (20×20) with white checkmark + "0.2s" mono
     - "Awaiting signature…" — lime circle with black pulsing dot + "live" mono
     - "Verify and sign in" — dashed border circle (future/pending)
   - **Cancel link**: "Cancel and pick a different wallet" (12px, neutral-500,
     center-aligned, hover neutral-900). Bordered at top.

## Decisions applied from release plan

- **Bucket A**: no schema, no new contexts, no new on-chain calls.
- **No route changes** — this is a layout-level component.
- **Legacy preservation**: copy current `wallet_components.ex` to
  `lib/blockster_v2_web/components/legacy/wallet_components_pre_redesign.ex` with
  module renamed.
- **`connect_button/1` is NOT restyled** — it's consumed by the old `app.html.heex`
  header only. Redesigned pages use the DS header which has its own inline connect
  button. Preserve as-is.
- **New assign: `connecting_wallet_name`** — the connecting state needs the wallet
  name to render "Opening Phantom" / "Opening Solflare". Added to `select_wallet`
  handler in `wallet_auth_events.ex` and to `default_assigns/0`. Also passed through
  from both layout files.
- **Wallet brand data** (`@wallet_registry`): extended with `tagline` and
  `gradient_class` per wallet, matching the mock. Brand gradients use inline Tailwind
  (`bg-gradient-to-br from-[…] to-[…]`) since they're one-off values.
- **No new DS components needed** — the modal is self-contained.
- **No new schema migrations.**

## Visual components consumed

- None from `lib/blockster_v2_web/components/design_system/`. The modal is an
  independent component rendered in both layouts.

**No new DS components needed.** The modal's backdrop, card, wallet rows, status
steps, and shimmer are all self-contained markup inside `wallet_components.ex`.

## Data dependencies

### ✓ Existing — already in production

- `@show` (boolean) — toggles modal visibility
- `@detected_wallets` (list) — wallets detected by the JS hook
- `@connecting` (boolean) — true while awaiting wallet approval

### ⚠ New assigns — one addition

- **`@connecting_wallet_name`** (string | nil) — name of the wallet currently being
  connected. Set by `select_wallet` handler, cleared on success/failure/cancel.
  Needed to render "Opening Phantom" and the big brand badge in State 2. Also
  needed for the "Back" button to return to State 1.

### ✗ New — must be added or schema-migrated

None. Bucket A.

## Handlers to preserve

All handlers live in `wallet_auth_events.ex` (injected via `use BlocksterV2Web, :live_view`).
The modal template fires these events:

**`handle_event`:**
- `"hide_wallet_selector"` — `phx-click` on close button + backdrop
- `"select_wallet"` with `phx-value-name` — `phx-click` on detected wallet row's Connect button
- `"show_wallet_selector"` — fired when "Back" is clicked from connecting state (resets to selection)

**New behavior in existing handlers:**
- `"select_wallet"` — also assigns `connecting_wallet_name: wallet_name`
- `"hide_wallet_selector"` — also clears `connecting_wallet_name: nil`

**Events NOT in the modal template (handled by JS hook):**
- `"wallet_connected"`, `"wallet_error"`, `"wallet_disconnected"` etc. — these are
  push_events from the SolanaWallet JS hook, not from the modal template.

## JS hooks

- **`SolanaWallet`** — on DS header (`#ds-site-header`) or old header. NOT on the modal
  itself. The modal only fires LiveView events; the JS hook intercepts `request_connect`
  push_events from the server. **No changes to the JS hook.**

No new JS hooks. The CSS animations (spin, shimmer, pulse-dot) use Tailwind `animate-*`
utilities and inline `<style>` block in the component.

## Tests required

### Component tests

**Create** `test/blockster_v2_web/components/wallet_components_test.exs`.

**Assertions:**

- **State 1 (wallet selection)**:
  - Modal renders when `show: true`
  - Modal does NOT render when `show: false`
  - "SIGN IN" eyebrow text renders
  - "Connect a Solana wallet" title renders
  - Close button with `phx-click="hide_wallet_selector"` renders
  - Wallet rows render for each wallet in registry
  - Detected wallet shows "Detected" badge + "Connect" button with `phx-click="select_wallet"`
  - Undetected wallet shows "Install" badge + "Get" external link
  - "What's a wallet?" link renders in footer
  - Terms and Privacy Policy links render

- **State 2 (connecting)**:
  - When `connecting: true` and `connecting_wallet_name: "Phantom"`, shows connecting UI
  - "Opening Phantom" title renders
  - Progress shimmer strip renders
  - Status steps render (3 rows)
  - "Cancel and pick a different wallet" link renders
  - Back button renders with `phx-click="show_wallet_selector"`

### LiveView tests

None needed — the component is rendered in the layout, not in a specific LiveView.
The existing header_test.exs already verifies the header renders. The wallet modal
is a layout-level component tested via `render_component/2`.

### Manual checks (on `bin/dev`)

- Click "Connect Wallet" in DS header → modal opens (State 1)
- Wallet rows show correct detection status
- Click a detected wallet → connecting state (State 2) with correct wallet name
- Click "Back" → returns to State 1
- Click close button → modal closes
- Click backdrop → modal closes
- Phantom popup appears when connecting
- Successful connection logs in user
- `mix test` — zero new failures vs baseline

## Per-page commit message

`redesign(wallet-modal): wallet connect modal refresh · white card + brand badges + connecting shimmer + status steps`

## Stubbed in v1

None. All mock elements have existing backend support.

## Open items

- **`connect_button/1`**: NOT restyled in this page. It's only used by the old
  `app.html.heex` layout. Redesigned pages use the DS header's inline button.
  The component stays as-is for backwards compat with non-migrated pages.
- **Wallet brand SVGs**: The mock uses inline SVG placeholders for wallet icons.
  The existing code uses `<img>` tags pointing to `/images/wallets/*.svg`. The
  redesign switches to inline SVGs matching the mock for the 3 known wallets,
  with a fallback initial letter for any future wallet additions.
