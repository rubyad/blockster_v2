# Product detail · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView module | `lib/blockster_v2_web/live/shop_live/show.ex` (handlers preserved, template fully rewritten, `@related_products` assign added) |
| Template | `lib/blockster_v2_web/live/shop_live/show.html.heex` (separate file, fully rewritten) |
| Route | `/shop/:slug` — moved from `:default` to `:redesign` live_session |
| Mock file | `docs/solana/product_detail_mock.html` |
| Bucket | **A** — pure visual refresh, no schema changes, no new contexts |
| Wave | 4 (Page #12 — second page of Wave 4) |

## Mock structure (top to bottom)

1. **Design system header** (`<DesignSystem.header active="shop" … />`) with all
   prod assigns, Why Earn BUX banner enabled. Default `display_token="BUX"`.

2. **Breadcrumb** — `Shop / [Category] / [Product Name]`. Links to `/shop` and
   `/shop?category=slug`. Final item is static text.

3. **Two-column hero** (`grid grid-cols-12 gap-10`):
   - **Left: Gallery** (`col-span-12 md:col-span-6`) — main image (aspect-square,
     rounded-2xl, border) with navigation arrows (prev/next). Thumbnail strip below
     (4-col grid, active = `border-2 border-[#141414]`, inactive = `border-neutral-200`
     hover `border-[#141414]`).
   - **Right: Buy panel** (`col-span-12 md:col-span-6`, `sticky top-[100px]`):
     - Collection eyebrow (10px bold uppercase tracking-[0.16em] text-neutral-500)
     - Title (article-title, 36-44px)
     - Hub + category + tag badges (hub = black pill with gradient dot, categories
       = neutral-100 pill, product_tags = lime tint pill, string tags = neutral pill)
     - Price block: bold mono 40px discounted + 18px strikethrough original + green
       "N% OFF" badge (when tokens redeemed). Toggle link "Hide/Show discount breakdown".
     - **BUX redemption card** (`bg-neutral-50 border rounded-2xl p-5`): BUX icon +
       "Redeem BUX tokens" title, balance display, input with Max button, calculation
       (token discount + you pay), `1 BUX = $0.01 discount` note.
     - Description (14px bold label + 13px body)
     - **Size pills** (rounded-xl, border-2, active = black bg white text,
       disabled = strikethrough text)
     - **Color swatches** (36px circles, active = double ring)
     - **Quantity** (rounded-full stepper: −/count/+)
     - **CTAs**: "Add to cart · $XX.XX" (black rounded-full) + "Buy it now" underline
     - **Reassurance grid** (3-col): Ships in 3-5 days, Sustainably sourced, 30-day returns

4. **Related products** — section with hub-specific eyebrow + "You may also like" heading
   + "All [Hub] →" link. 4-col product card grid (same card shape as shop index).

5. **Footer** — `<DesignSystem.footer />`.

## Decisions applied from release plan

- **Bucket A**: no schema, no new contexts, no new on-chain calls.
- **`<DesignSystem.header active="shop" />`** with default `display_token="BUX"`.
- **Route move**: `live "/shop/:slug", ShopLive.Show, :show` moves from `:default`
  to `:redesign` live_session.
- **Legacy preservation**: copy current files to
  `lib/blockster_v2_web/live/shop_live/legacy/` with module renamed
  `BlocksterV2Web.ShopLive.Legacy.ShowPreRedesign`.
- **No new DS components**: every section is page-inlined markup.
- **No new schema migrations.**
- **Related products**: the mock shows "More from the Phantom community" + 4 product
  cards. This uses `Shop.list_products_by_hub/2` (already exists) filtered to exclude
  the current product, capped at 4. When the product has no hub, section is hidden.
- **"Buy it now" link is inert** (stub) — mock shows it but no handler exists.
  Static underline text. Future feature.
- **Reassurance icons are static** — hardcoded shipping/sustainability/returns copy.
  Not data-driven. Matches mock exactly.
- **Size pills use mock style** (rounded-xl border-2, black active state) — replaces
  the old green `#8AE388` selected style.
- **Color swatches use mock style** (circle with ring) — replaces the old labeled
  color buttons.

## Visual components consumed

- `<BlocksterV2Web.DesignSystem.header active="shop" … />` ✓ existing (Wave 0)
- `<BlocksterV2Web.DesignSystem.footer />` ✓ existing (Wave 0)

**No new DS components needed.** Breadcrumb, gallery, buy panel, size pills, color
swatches, redemption card, reassurance grid, and related products are all page-specific
markup inlined in the template.

## Data dependencies

### ✓ Existing — already in production

Every assign in `mount/3` is preserved exactly:

- `@page_title` (product name)
- `@product` (transformed product map with: id, name, slug, price, image, images,
  bux_max_discount, max_bux_tokens, hub_name, hub_slug, hub_logo_url, artist_name,
  artist_slug, artist_image, product_type, categories, product_tags, tags, description,
  features, sizes, colors, artist, collection_name, max_inventory, sold_count)
- `@product_config` (ProductConfig struct or nil)
- `@quantity` (integer, default 1)
- `@selected_size` (string or nil)
- `@selected_color` (string or nil)
- `@current_image_index` (integer, default 0)
- `@user_bux_balance` (float)
- `@max_bux_tokens` (float)
- `@tokens_to_redeem` (float)
- `@show_discount_breakdown` (boolean)
- `@color_hex_map` (map of color name → hex)
- `@token_value_usd` (0.01)
- `@shoe_gender` (string or nil)
- `@display_sizes` (list of size strings)
- `@added_to_cart` (boolean)
- Default `WalletAuthEvents.default_assigns/0` from `use BlocksterV2Web, :live_view`

### ⚠ New assign — simple display data from existing context

- `@related_products` — list of up to 4 product display maps from
  `Shop.list_products_by_hub(hub_id)`, excluding the current product. Added in
  `mount/3` after the existing product fetch. When product has no hub, empty list.
  Uses existing `Shop.list_products_by_hub/2` which returns `prepare_product_for_display`
  maps. **No new context function, no new query.**
- `@hub_color_primary` — string, from `product.hub.color_primary` (already loaded
  in the preload chain). Used for the hub badge gradient dot in the buy panel and
  for the related products section hub link. `nil` when no hub.
- `@hub_color_secondary` — string, same as above. Used for gradient dot.

### ⚠ Stubbed in v1

| Stub | What shows | Replaces it | Resolved by |
|---|---|---|---|
| "Buy it now" link | Static underline text, no handler | Real quick-checkout flow | Follow-up commit |

### ✗ New — must be added or schema-migrated

None. Bucket A.

## Handlers to preserve

Every `handle_event` in the current LiveView MUST be wired up by the new template:

**`handle_event`:**
- `"increment_quantity"` (`phx-click` on + button)
- `"decrement_quantity"` (`phx-click` on − button)
- `"select_size"` with `phx-value-size` (`phx-click` on size pills)
- `"select_color"` with `phx-value-color` (`phx-click` on color swatches)
- `"update_tokens"` (`phx-change` on token input form)
- `"use_max_tokens"` (`phx-click` on Max button)
- `"toggle_discount_breakdown"` (`phx-click` on discount toggle link)
- `"add_to_cart"` (`phx-click` on Add to Cart button)
- `"set_shoe_gender"` with `phx-value-gender` (`phx-click` on Men's/Women's toggle)
- `"select_image"` with `phx-value-index` (`phx-click` on thumbnails)
- `"next_image"` (`phx-click` on right arrow)
- `"prev_image"` (`phx-click` on left arrow)

**No `handle_async`, `handle_info`, or PubSub subscriptions** in this module.

## JS hooks

- **`SolanaWallet`** — on DS header (`#ds-site-header`). Already in place.
- **`TokenInput`** — on the BUX input field. Already registered in `app.js`.

No new JS hooks.

## Tests required

### Component tests

None. No new DS components.

### LiveView tests

**Create** `test/blockster_v2_web/live/shop_live/show_test.exs` (no existing test file).

**Assertions:**

- DS header renders with `id="ds-site-header"` and `phx-hook="SolanaWallet"`
- Header `Shop` nav link is active
- Why Earn BUX banner renders (`"Why Earn BUX?"`)
- Breadcrumb renders with "Shop" link + product name
- Product name renders as h1
- Gallery renders main image
- Thumbnail strip renders when product has multiple images
- Collection eyebrow renders when product has collection_name
- Hub badge renders as black pill with hub name
- Category badges render for each category
- Product tag badges render
- Price display: discounted price + strikethrough + "OFF" badge when tokens > 0
- Price display: regular price only when no discount
- BUX redemption card renders with balance + input + Max button when bux_max_discount > 0
- BUX redemption card hidden when bux_max_discount == 0
- "1 BUX = $0.01 discount" text renders
- Description section renders
- Size pills render for clothing products
- Color swatches render for products with colors
- Quantity stepper renders with − / count / +
- "Add to cart" button renders (when checkout not disabled)
- "Coming Soon" renders when checkout disabled
- Related products section renders when product has hub + related products exist
- Related products section hidden when product has no hub
- Footer renders (`"Where the chain meets the model."`)

**Handler tests:**
- `select_image`: click thumbnail → current_image_index updates
- `increment_quantity` / `decrement_quantity`: quantity updates
- `select_size`: size updates
- `select_color`: color updates
- `toggle_discount_breakdown`: toggles visibility

### setup_mnesia coverage

The `ShopLive.Show` module does NOT read from any Mnesia table in `mount/3`. The
`EngagementTracker.get_user_token_balances` call does read Mnesia but returns `%{}`
gracefully when tables don't exist (uses `try/catch`). No Mnesia table setup needed
for anonymous tests. If testing logged-in BUX balance display, create
`:user_solana_balances` and `:user_bux_balances` tables.

### Manual checks (on `bin/dev`)

- `/shop/:slug` loads logged-in (product displays, BUX balance in header + redemption card)
- `/shop/:slug` loads anonymous (Connect Wallet CTA, no BUX card balance)
- Gallery: main image displays, arrows navigate, thumbnails select
- Breadcrumb links work (Shop → /shop, Category → /shop?category=slug)
- Hub badge links to hub page
- Category/tag badges link to shop filters
- Size pills: click selects, active state shows black bg
- Color swatches: click selects, active ring shows
- Quantity +/− works, minimum 1
- BUX redemption: input + Max button + calculation updates dynamically
- Toggle discount breakdown shows/hides redemption card
- Add to cart button works (logged in), flash message appears
- Checkout button appears after adding to cart
- Related products show from same hub (when hub exists)
- DS header pill shows BUX balance
- Footer renders
- `mix test` — zero new failures vs baseline

## Per-page commit message

`redesign(product-detail): product page refresh · gallery + sticky buy panel + BUX redemption card + related products`

## Stubbed in v1

| Stub | What it shows now | What replaces it | Resolved by release |
|---|---|---|---|
| "Buy it now" link | Static underline text, no handler | Quick-checkout flow | Follow-up commit |
| Reassurance icons | Hardcoded 3 cards (shipping / sustainability / returns) | Data-driven from product config | Follow-up commit |

## Open items

- **Related products**: the mock shows 4 products from the same hub. Using
  `Shop.list_products_by_hub/2` (existing function). This returns
  `prepare_product_for_display` maps which have `id`, `name`, `slug`, `image`,
  `price`, `total_max_discount`, `max_discounted_price`. Filter out the current
  product and take 4.
- **Shoe size gender toggle**: the existing module has `set_shoe_gender` handler +
  unisex_shoes logic. The mock doesn't show this (it only shows simple clothing sizes).
  **Decision**: preserve the handler and render the toggle when `product_config.size_type
  == "unisex_shoes"`. The mock is a single product snapshot; the code handles the full
  range of product types.
- **Admin edit button**: the existing template has an admin edit link. The mock doesn't
  show it. **Decision**: preserve it — admin tools are invisible to normal users and
  useful in production.
- **Artist badge**: the existing template shows artist info. The mock doesn't have an
  explicit artist badge (it uses the hub badge). **Decision**: preserve artist badge
  rendering for products that have artist_record associations — it's existing data
  that would otherwise be lost.
- **"Coming Soon" state**: the existing template shows a disabled "Coming Soon" button
  when `product_config.checkout_enabled == false`. The mock doesn't show this state.
  **Decision**: preserve it — it's a real production feature.
