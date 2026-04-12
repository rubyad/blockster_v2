# Cart · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView module | `lib/blockster_v2_web/live/cart_live/index.ex` (handlers preserved, template fully rewritten, `@suggested_products` assign added) |
| Template | `lib/blockster_v2_web/live/cart_live/index.html.heex` (separate file, fully rewritten) |
| Route | `/cart` — moved from `:authenticated` to `:redesign` live_session |
| Mock file | `docs/solana/cart_mock.html` |
| Bucket | **A** — pure visual refresh, no schema changes, no new contexts |
| Wave | 4 (Page #13 — third page of Wave 4) |

## Mock structure (top to bottom)

### State 1 — Filled cart

1. **Design system header** (`<DesignSystem.header active="shop" … />`) with all
   prod assigns, Why Earn BUX banner enabled. Default `display_token="BUX"`.

2. **Page hero** — eyebrow ("N items · ready when you are"), h1 "Your cart",
   description text about BUX discount + Helio USD checkout.

3. **Two-column layout** (`grid grid-cols-12 gap-8`):
   - **Left: line items** (`col-span-12 md:col-span-7 space-y-4`):
     - Each item is a white card (`bg-white rounded-2xl border p-5 shadow`):
       - Flex row: 96×96 product image (rounded-xl) + content
       - Hub badge: tiny colored square (gradient or solid) + hub name (9px uppercase)
       - Product title (15px bold)
       - Variant info (11px muted: "Charcoal · Size M")
       - Remove button (trash icon, hover red)
       - Quantity stepper (pill-style: −/count/+) + unit price (mono bold 18px)
       - BUX redemption strip (when available):
         - BUX icon + "BUX to redeem · max N (X% off)" label
         - Number input + green discount amount
       - "No BUX discount available for this item" (italic, when not available)
     - "Continue shopping" link with left arrow below items
   - **Right: order summary** (`col-span-12 md:col-span-5`, sticky):
     - White card with eyebrow "Order summary"
     - Subtotal · N items
     - BUX discount · N BUX (green negative)
     - Your BUX balance
     - Divider
     - Total (mono bold 28px) + "+ N BUX burned" subtitle
     - "Proceed to checkout" button (black rounded-full with arrow)
     - Payment info footnote (lock icon + "Pay with USD via Helio · BUX burned on Solana")
     - Explanatory text below card

4. **Suggested products** — eyebrow ("Often bought with what's in your cart") +
   h2 "You might also like" + 4-col product card grid (same shape as shop index).

5. **Warnings banner** — amber banner above items when cart validation fails.

6. **Footer** — `<DesignSystem.footer />`.

### State 2 — Empty cart

1. **Design system header** (same).
2. **Page hero** — eyebrow ("0 items · nothing waiting"), h1 "Your cart is empty",
   description.
3. **Empty state card** — centered white card (rounded-3xl), cart icon in lime-tinted
   square, "Nothing in here yet" title, description, two CTAs: "Browse the shop"
   (black rounded-full) + "Earn BUX reading" (white bordered rounded-full).
4. **Footer** (same).

## Decisions applied from release plan

- **Bucket A**: no schema, no new contexts, no new on-chain calls.
- **`<DesignSystem.header active="shop" />`** with default `display_token="BUX"`.
- **Route move**: `live "/cart", CartLive.Index, :index` moves from `:authenticated`
  to `:redesign` live_session. The mount already redirects unauthenticated users.
- **Legacy preservation**: copy current files to
  `lib/blockster_v2_web/live/cart_live/legacy/` with module renamed
  `BlocksterV2Web.CartLive.Legacy.IndexPreRedesign`.
- **No new DS components**: every section is page-inlined markup.
- **No new schema migrations.**
- **`max_bux_for_item` bug fix**: treat `bux_max_discount=0` as uncapped (100%),
  matching the product detail page fix from Page #12. Without this, the BUX
  redemption strip never renders for any real product.
- **Hub preload added**: `:hub` added to cart item preload for hub badge display.
- **Suggested products**: `Shop.get_random_products(8)` filtered to exclude cart
  product IDs, capped at 4. Uses `Shop.prepare_product_for_display/1`. Hidden
  when cart is empty (mock doesn't show suggestions in empty state).

## Visual components consumed

- `<BlocksterV2Web.DesignSystem.header active="shop" … />` ✓ existing (Wave 0)
- `<BlocksterV2Web.DesignSystem.footer />` ✓ existing (Wave 0)

**No new DS components needed.** Page hero, line item cards, order summary,
empty state, and suggested products are all page-specific markup inlined in
the template.

## Data dependencies

### ✓ Existing — already in production

Every assign in `mount/3` is preserved exactly:

- `@page_title` ("Your Cart")
- `@cart` (Cart struct with preloaded cart_items → product → images, variants, hub)
- `@warnings` (list of validation error strings)
- `@totals` (map: subtotal, total_bux_discount, total_bux_tokens, remaining, bux_available, bux_allocated, items)
- `@token_value_usd` (0.01)
- Default `WalletAuthEvents.default_assigns/0` from `use BlocksterV2Web, :live_view`

### ⚠ New assign — simple display data from existing context

- `@suggested_products` — list of up to 4 product display maps from
  `Shop.get_random_products(8)`, excluding products already in the cart,
  capped at 4. Uses existing `Shop.prepare_product_for_display/1` which
  returns `%{id, name, slug, image, price, total_max_discount, max_discounted_price}`.
  Hidden when cart is empty. **No new context function, no new query.**

### ⚠ Bug fix in existing helper

- `max_bux_for_item/1`: changed to treat `bux_max_discount == 0` as uncapped (100%),
  computing `max_bux = price_cents * quantity` (where 1 BUX = $0.01). This aligns
  with the product detail page's behavior (fixed in Page #12). Without this fix,
  the BUX redemption strip from the mock can never render.

### ⚠ Preload enhancement

- `Cart.preload_items/1`: added `:hub` to the product preload chain
  (`product: [:images, :variants, :hub]`). The `Product` schema already has
  a `belongs_to :hub` association — this just loads it for display.

### ✗ New — must be added or schema-migrated

None. Bucket A.

## Handlers to preserve

Every `handle_event` in the current LiveView MUST be wired up by the new template:

**`handle_event`:**
- `"increment_quantity"` with `phx-value-item-id` (`phx-click` on + button)
- `"decrement_quantity"` with `phx-value-item-id` (`phx-click` on − button)
- `"remove_item"` with `phx-value-item-id` (`phx-click` on trash button)
- `"update_bux_tokens"` with `phx-value-item-id` + `name="bux"` (`phx-change` on BUX input form)
- `"proceed_to_checkout"` (`phx-click` on checkout button)

**No `handle_async`, `handle_info`, or PubSub subscriptions** in this module.

**PubSub broadcast (outgoing only):**
- `CartContext.broadcast_cart_update/1` fires on every `reload_cart/1` call,
  broadcasting on `"cart:#{user_id}"`. The cart page does NOT subscribe to
  this topic — it's consumed by the header cart badge on other pages.

## JS hooks

- **`SolanaWallet`** — on DS header (`#ds-site-header`). Already in place.
- **`TokenInput`** — on BUX input field. Already registered in `app.js`.

No new JS hooks.

## Tests required

### Component tests

None. No new DS components.

### LiveView tests

**Create** `test/blockster_v2_web/live/cart_live/index_test.exs` (no existing test file).

**Assertions:**

- DS header renders with `id="ds-site-header"` and `phx-hook="SolanaWallet"`
- Header `Shop` nav link is active
- Why Earn BUX banner renders (`"Why Earn BUX?"`)
- **Empty cart**: renders "Your cart is empty" h1
- **Empty cart**: renders "Nothing in here yet" section title
- **Empty cart**: renders "Browse the shop" CTA linking to `/shop`
- **Empty cart**: renders "Earn BUX reading" CTA
- **Filled cart**: renders "Your cart" h1
- **Filled cart**: renders eyebrow with item count
- **Filled cart**: renders product title for each item
- **Filled cart**: renders product image
- **Filled cart**: renders variant info (option1 / option2)
- **Filled cart**: renders quantity stepper (−/count/+)
- **Filled cart**: renders unit price
- **Filled cart**: order summary card renders with subtotal + total
- **Filled cart**: "Proceed to checkout" button renders
- **Filled cart**: "Continue shopping" link renders
- **Filled cart**: suggested products section renders when products exist
- Footer renders (`"Where the chain meets the model."`)

**Handler tests:**
- `increment_quantity`: quantity increases
- `decrement_quantity`: quantity decreases (minimum 1)
- `remove_item`: item removed from cart, flash shown
- `update_bux_tokens`: BUX amount updates
- `proceed_to_checkout`: creates order and navigates to checkout

### setup_mnesia coverage

The `CartLive.Index` module does NOT directly read Mnesia tables. The
`CartContext.calculate_totals/2` calls `EngagementTracker.get_user_token_balances/1`
which reads Mnesia but returns `0` gracefully via `try/catch` when tables don't exist.
No Mnesia table setup needed for basic tests. If testing BUX balance display in the
order summary, create `:user_solana_balances` and `:user_bux_balances` tables.

### Manual checks (on `bin/dev`)

- `/cart` loads logged-in with items (full layout displays)
- `/cart` loads logged-in with empty cart (empty state displays)
- `/cart` redirects anonymous users to homepage
- Per-item hub badges display with correct colors
- Per-item BUX redemption strip works (input + discount calculation)
- Items without BUX discount show italic "No BUX discount" message
- Quantity +/− works, minimum 1
- Remove item works with flash message
- Order summary updates dynamically (subtotal, discount, total)
- "Proceed to checkout" navigates to `/checkout/:id`
- "Continue shopping" links to `/shop`
- Suggested products render (4 cards, linking to `/shop/:slug`)
- DS header pill shows BUX balance
- Footer renders
- `mix test` — zero new failures vs baseline

## Per-page commit message

`redesign(cart): cart page refresh · per-item BUX redemption + sticky order summary + suggested products`

## Stubbed in v1

None. All mock elements have existing backend support.

## Open items

- **`max_bux_for_item` alignment**: the existing helper treated `bux_max_discount=0`
  as "no discount" (returns 0). The product detail page already fixed this to treat
  0 as "uncapped" (100%). This redesign applies the same fix to the cart helper.
  This is a behavioral fix, not just visual, but it's necessary for the BUX
  redemption strip to function as designed.
- **Suggested products source**: using `Shop.get_random_products/1` (existing function,
  random active products with images). Excludes cart product IDs. When the shop has
  fewer than 4 non-cart products, the grid shows fewer cards.
- **Warnings banner**: preserved from the existing template. Renders above the items
  column when `@warnings` is non-empty. The mock doesn't show this state explicitly
  but it's a production feature that must stay.
