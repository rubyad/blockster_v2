# Checkout · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView module | `lib/blockster_v2_web/live/checkout_live/index.ex` (handlers preserved exactly, template fully rewritten) |
| Template | `lib/blockster_v2_web/live/checkout_live/index.html.heex` (separate file, fully rewritten) |
| Route | `/checkout/:order_id` — moved from `:authenticated` to `:redesign` live_session |
| Mock file | `docs/solana/checkout_mock.html` |
| Bucket | **A** — pure visual refresh, no schema changes, no new contexts |
| Wave | 4 (Page #14 — fourth and final page of Wave 4) |

## Mock structure (top to bottom)

The mock shows 4 stacked states (Shipping → Review → Payment → Confirmation).
In the LiveView, only one state renders at a time based on `@step`.

### State 1 — Shipping (step indicator: 1 current, 2-4 future)

1. **Design system header** (`<DesignSystem.header active="shop" … />`) with all
   prod assigns, Why Earn BUX banner enabled.

2. **Step indicator bar** — white card with 4 step dots connected by lines.
   Step dots: `.done` (black bg + checkmark), `.current` (lime bg + number + glow),
   `.future` (gray bg + number). Labels below dots (10px uppercase bold tracking).

3. **Two-column layout** (`grid grid-cols-12 gap-8`):
   - **Left: shipping form** (`col-span-12 md:col-span-7`):
     - White card with eyebrow "Step 1 of 4", h2 "Where should we ship it?",
       description text.
     - Form fields: Full name + Email (2-col), Address, Apt/suite (optional),
       City + State + Postal (3-col), Country + Phone (2-col).
     - Form labels: 11px uppercase bold tracking, muted color.
     - Form inputs: white bg, rounded-xl border, 13px text, focus: border-black.
     - "Continue to shipping options" button (black rounded-full with arrow).
   - **Right: order summary** (`col-span-12 md:col-span-5`, sticky):
     - White card with eyebrow "Order summary · N items".
     - Item list: 48×48 image + product name (12px bold) + variant/qty (10px mono)
       + price (12px mono bold).
     - Divider, then Subtotal + BUX discount (green) + Shipping ("Next step" italic).
     - Total section: "Total · USD" label + large mono bold price + "N BUX burned" subtitle.

### State 2 — Review (step indicator: 1 done, 2 current, 3-4 future)

1. **Step indicator** (same card, updated dots).

2. **Two-column layout**:
   - **Left: review details** (`col-span-12 md:col-span-7`):
     - White card with eyebrow "Step 2 of 4", h2 "Review your order".
     - **Items section**: 11px uppercase label, item rows with 56×56 image +
       product name + variant/qty/BUX info + price (with strikethrough original).
     - **Address section**: divider, "Shipping to" label + Edit button, address lines.
     - **Shipping method section**: divider, label + Edit button, method + cost.
   - Bottom: 2-col button row: "Back to shipping" (white bordered) + "Continue to payment" (black).
   - **Right: order summary** (sticky):
     - Subtotal + BUX discount + Shipping method + Sales tax.
     - Total with large price + "BUX burned" subtitle.

### State 3 — Payment (step indicator: 1-2 done, 3 current, 4 future)

1. **Step indicator** (updated).

2. **Two-column layout**:
   - **Left: payment cards** (`col-span-12 md:col-span-7 space-y-5`):
     - White card with eyebrow "Step 3 of 4", h2 "Pay your order", description.
     - **BUX burn card** (`.pay-card`): lime icon bg + "Burn N BUX" title +
       status badge (Confirmed = green). Description text. TX link (mono, 10px).
       States: pending (with "Send BUX" button), processing, completed (green border),
       failed (with retry).
     - **Helio card** (`.pay-card.active`): blue gradient icon + "Pay $X via Helio"
       title. Description. Embedded widget placeholder (dashed border). "Pay $X"
       button. "Powered by Helio" footer.
   - **Right: final total** (sticky):
     - Subtotal + BUX discount + Shipping.
     - Large total price (28px mono bold).
     - "BUX burned on chain" confirmed line (green).
     - "Remaining BUX balance" line.

### State 4 — Confirmation (step indicator: 1-3 done, 4 current)

1. **Step indicator** (all done except 4 current).

2. **Centered confirmation card** (`max-w-[640px] mx-auto`):
   - Green success icon (80×80 rounded-3xl, green tint bg + dark green checkmark).
   - Eyebrow "Order complete".
   - h2 "Thanks, [name]." (36px).
   - Receipt email message with bold email address.
   - **Order details grid** (2-col): Order ID, Total paid, BUX burn tx (link),
     Helio ref, BUX redeemed, Estimated arrival. All mono text.
   - CTAs: "View order" (black rounded-full) + "Continue shopping" (white bordered).

3. **Footer** — `<DesignSystem.footer />`.

## Decisions applied from release plan

- **Bucket A**: no schema, no new contexts, no new on-chain calls.
- **`<DesignSystem.header active="shop" />`** with default `display_token="BUX"`.
- **Route move**: `live "/checkout/:order_id", CheckoutLive.Index, :index` moves from
  `:authenticated` to `:redesign` live_session. The mount already redirects unauthenticated users.
- **Legacy preservation**: copy current files to
  `lib/blockster_v2_web/live/checkout_live/legacy/` with module renamed
  `BlocksterV2Web.CheckoutLive.Legacy.IndexPreRedesign`.
- **No new DS components**: every section is page-inlined markup.
- **No new schema migrations.**
- **Two-column layout added**: the existing template is single-column (`max-w-3xl`).
  The mock uses `grid grid-cols-12 gap-8` with a sticky order summary on the right
  for steps 1-3. This is the biggest structural change.
- **Step indicator restyled**: from inline dots to a card-based indicator bar with
  lime current dot (glow shadow), black done dots (checkmark SVG), gray future dots.
- **Pay cards restyled**: BUX burn and Helio payment cards get the `.pay-card` treatment
  with done/active/pending border states.
- **Confirmation page restyled**: from basic card to centered celebration layout with
  green success icon, order details grid, and dual CTAs.

## Visual components consumed

- `<BlocksterV2Web.DesignSystem.header active="shop" … />` ✓ existing (Wave 0)
- `<BlocksterV2Web.DesignSystem.footer />` ✓ existing (Wave 0)

**No new DS components needed.** Step indicator, form fields, pay cards, order summary,
and confirmation card are all page-specific markup inlined in the template.

## Data dependencies

### ✓ Existing — already in production

Every assign in `mount/3` is preserved exactly:

- `@page_title` ("Checkout" or "Order Confirmed")
- `@order` (Order struct with preloaded order_items, affiliate_payouts, user, referrer)
- `@step` (`:shipping` | `:review` | `:payment` | `:confirmation`)
- `@shipping_phase` (`:address` | `:rate_selection`)
- `@shipping_changeset` (Ecto changeset for form binding)
- `@shipping_rates` (list of rate structs from Shipping module)
- `@shipping_zone` (`:us` | `:international`)
- `@selected_shipping_rate` (rate key string or nil)
- `@bux_payment_status` (`:pending` | `:processing` | `:completed` | `:failed`)
- `@rogue_payment_status` (always `:pending`, deprecated)
- `@helio_payment_status` (`:pending` | `:widget_ready` | `:processing` | `:confirming` | `:completed` | `:failed`)
- `@helio_amount` (Decimal — remaining USD after BUX discount)
- `@rogue_usd_amount`, `@rogue_tokens`, `@rogue_discount_saved`, `@rogue_rate_locked`,
  `@rogue_rate_locked_at`, `@rogue_balance` — all zeroed (deprecated)
- Default `WalletAuthEvents.default_assigns/0` from `use BlocksterV2Web, :live_view`

### ⚠ New assigns — none

No new assigns needed. All data for the redesigned template comes from existing assigns.

### ✗ New — must be added or schema-migrated

None. Bucket A.

## Handlers to preserve

Every `handle_event` in the current LiveView MUST be wired up by the new template:

**`handle_event`:**
- `"validate_shipping"` — `phx-change` on shipping form
- `"save_shipping"` — `phx-submit` on shipping form
- `"select_shipping_rate"` with `phx-value-rate` — `phx-click` on rate button
- `"set_rogue_amount"` — no-op (deprecated, kept for compat)
- `"proceed_to_payment"` — `phx-click` on review step's continue button
- `"go_to_step"` with `phx-value-step` — `phx-click` on back buttons
- `"edit_shipping_address"` — `phx-click` on edit button in rate selection
- `"initiate_bux_payment"` — `phx-click` on "Send BUX" button
- `"bux_payment_complete"` — callback from JS hook (tx_hash)
- `"bux_payment_error"` — callback from JS hook (error)
- `"advance_after_bux"` — `phx-click` on "Complete Order" button
- `"initiate_rogue_payment"` — no-op (deprecated)
- `"rogue_payment_complete"` — no-op (deprecated)
- `"rogue_payment_error"` — no-op (deprecated)
- `"advance_after_rogue"` — no-op (deprecated)
- `"initiate_helio_payment"` — `phx-click` on "Pay $X" button + "Re-open Payment"
- `"helio_payment_success"` — callback from HelioCheckoutHook
- `"helio_payment_error"` — callback from HelioCheckoutHook
- `"helio_payment_cancelled"` — callback from HelioCheckoutHook
- `"complete_order"` — `phx-click` on "Place Order" button

**`handle_info`:**
- `{:order_updated, updated_order}` — PubSub webhook-driven update
- `:check_order_status` — DB polling every 5s
- `:poll_helio_payment` — Helio API polling

**`handle_async`:**
- `:poll_helio` — three clauses: nil (retry), tx found (complete), error (retry)

**PubSub subscriptions:**
- `"order:#{order.id}"` — subscribed in mount for `helio_pending` orders and in
  `initiate_helio_payment`

## JS hooks

- **`SolanaWallet`** — on DS header (`#ds-site-header`). Already in place.
- **`BuxPaymentHook`** — on `#bux-payment-hook`. Deprecated (empty mounted), but still
  referenced by the template. Keep the hook mount point for backwards compat.
- **`HelioCheckoutHook`** — on `#helio-checkout-hook`. Loads Helio SDK, renders widget,
  reports payment results. Must preserve: `data-order-id`, `data-order-number` attrs,
  `#helio-widget-container` inner div for widget rendering.

No new JS hooks.

## Tests required

### Component tests

None. No new DS components.

### LiveView tests

**Create** `test/blockster_v2_web/live/checkout_live/index_test.exs` (no existing LiveView test file).

**Assertions:**

- DS header renders with `id="ds-site-header"` and `phx-hook="SolanaWallet"`
- Header `Shop` nav link is active
- Why Earn BUX banner renders (`"Why Earn BUX?"`)
- **Shipping step**: renders "Where should we ship it?" h2
- **Shipping step**: renders form fields (name, email, address, city, state, postal, country, phone)
- **Shipping step**: renders "Continue to shipping options" button
- **Shipping step**: order summary card renders with item list
- **Shipping step**: order summary shows subtotal and total
- **Review step**: renders "Review your order" h2
- **Review step**: renders order items with images and prices
- **Review step**: renders shipping address
- **Review step**: renders "Continue to payment" and "Back to shipping" buttons
- **Payment step**: renders "Pay your order" h2
- **Payment step**: BUX burn card renders when bux_tokens_burned > 0
- **Payment step**: Helio card renders when helio_payment_amount > 0
- **Payment step**: HelioCheckoutHook element with correct data attrs
- **Confirmation step**: renders green success icon area
- **Confirmation step**: renders "Order complete" eyebrow
- **Confirmation step**: renders order details grid
- **Confirmation step**: renders "Continue shopping" CTA
- Footer renders (`"Where the chain meets the model."`)

**Handler tests:**
- `validate_shipping`: form validates on change
- `save_shipping`: persists shipping info, moves to rate selection
- `select_shipping_rate`: selects rate, moves to review
- `go_to_step`: navigates back (review→shipping allowed, payment→review allowed)
- `edit_shipping_address`: returns to address form from rate selection
- `proceed_to_payment`: moves to payment step
- `initiate_bux_payment`: deducts BUX, pushes client event
- `bux_payment_complete`: marks BUX paid, shows tx link
- `initiate_helio_payment`: marks helio_pending, pushes widget render event

### setup_mnesia coverage

The `CheckoutLive.Index` module does NOT directly read Mnesia tables.
`BalanceManager.deduct_bux/2` reads `user_solana_balances` via EngagementTracker,
but the deduct operation uses `try/catch` internally. For BUX payment tests,
create `:user_solana_balances` and `:user_bux_balances` tables.

### Manual checks (on `bin/dev`)

- `/checkout/:id` loads logged-in with pending order (shipping form displays)
- `/checkout/:id` redirects anonymous users to login
- `/checkout/:id` redirects for non-owned orders
- Step indicator updates correctly through all 4 steps
- Shipping form validates and persists
- Rate selection works with correct pricing
- Review step shows all order details with edit buttons
- Payment step shows BUX burn card + Helio card
- BUX burn triggers wallet signing flow
- Helio widget loads and renders inline
- Confirmation page shows order details + tx links
- DS header pill shows BUX balance
- Footer renders
- `mix test` — zero new failures vs baseline

## Per-page commit message

`redesign(checkout): checkout page refresh · 4-step wizard with sticky summary + pay cards + confirmation celebration`

## Stubbed in v1

None. All mock elements have existing backend support.

## Open items

- **ROGUE payment references**: the existing template and handlers have ROGUE payment
  code (all deprecated/zeroed). The redesigned template drops all ROGUE display elements
  since the mock doesn't show them. The handlers are preserved as no-ops for backwards compat.
- **BuxPaymentHook**: the hook is deprecated (empty `mounted()`), but the template still
  mounts it on `#bux-payment-hook`. The actual BUX transfer is triggered via
  `push_event("initiate_bux_payment_client", ...)` which is handled by the `SolanaWallet`
  hook. The `BuxPaymentHook` mount point is kept for safety.
- **Order summary on all steps**: the mock shows a sticky order summary on the right
  column for steps 1-3. Step 4 (confirmation) is centered single-column. The existing
  template is entirely single-column — this is the biggest layout change.
