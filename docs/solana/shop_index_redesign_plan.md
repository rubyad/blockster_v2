# Shop index · redesign plan

> Part of the existing-pages redesign release. See `redesign_release_plan.md`
> for context. Big-bang cutover, no per-page feature flag.

## What this replaces

| Field | Value |
|---|---|
| LiveView module | `lib/blockster_v2_web/live/shop_live/index.ex` (wholesale template rewrite; `mount/3`, `handle_params/3`, and every handler preserved) |
| Template | `lib/blockster_v2_web/live/shop_live/index.html.heex` (separate file, fully rewritten) |
| Route | `/shop` — moved from `:default` to `:redesign` live_session |
| Mock file | `docs/solana/shop_index_mock.html` |
| Bucket | **A** — pure visual refresh, no schema changes, no new contexts |
| Wave | 4 (Page #11 — first page of Wave 4) |

## Mock structure (top to bottom)

1. **Design system header** (`<DesignSystem.header active="shop" … />`) with all
   prod assigns, Why Earn BUX banner enabled, and cart icon in header (existing
   cart_item_count assign). Default `display_token="BUX"` is correct — shop is a
   BUX-spending surface.

2. **Full-bleed hero banner** — `bg-neutral-900` with background image + dark
   left-to-transparent gradient overlay. Left-aligned content:
   - Lime eyebrow: `Spend the BUX you earned`
   - 44-64px article-title white headline: `Crypto-inspired streetwear & gadgets`
   - White/75 16px description: `Apparel, hardware wallets, and event passes…`
   - Two frosted pills: `N products in stock` + `1 BUX = $0.01 off`

3. **Two-column main layout** (`flex gap-8`, `max-w-[1280px]`):
   - **Left sidebar** (`w-60`, `sticky top-24`, `hidden lg:block`) — white
     rounded-2xl card with:
     - `View all` button (active = black bg, inactive = hover gray)
     - **Products** section label (eyebrow) + filter links for categories
       (each with neutral dot + name + mono count)
     - **Communities** section label + filter links for hubs (each with
       hub-color gradient dot + name + mono count)
     - **Brands** section label + filter links for vendors (each with
       neutral dot + name + mono count)
     - Active filter link gets `bg-[#141414] text-white font-bold`
   - **Product grid** (`flex-1 min-w-0`):
     - Toolbar: `Showing N products` left + `Sort by · Most popular` dropdown right
     - 2-col (mobile) / 3-col (lg) grid of product cards
     - Each card: aspect-square image with optional hub logo badge (white
       circle with hub-gradient inner circle, top-left), text-center body
       with bold title, price block (strikethrough original + bold
       discounted mono price + "with BUX tokens" caption when discount > 0,
       or just the price when no discount), black rounded-full `Buy Now` button
     - `Load N more products` button at bottom center

4. **Mobile filter button** — fixed bottom-right, black pill `Filters` with
   active badge count.

5. **Mobile filter drawer** — right-side slide-over with same 3-section filter
   structure as desktop sidebar.

6. **Product picker modal** (admin only) — overlay modal for slot assignment.

7. **Footer** — `<DesignSystem.footer />`.

## Decisions applied from release plan

- **Bucket A**: no schema, no new contexts, no new on-chain calls. Every
  existing handler / assign stays.
- **`<DesignSystem.header active="shop" />`** with default `display_token="BUX"`.
  The header has `phx-hook="SolanaWallet"` baked in — do not duplicate.
- **Route move**: `live "/shop", ShopLive.Index, :index` moves from `:default`
  to `:redesign` live_session (matches pages #1–#10).
- **Legacy preservation**: copy current files to
  `lib/blockster_v2_web/live/shop_live/legacy/` with module renamed
  `BlocksterV2Web.ShopLive.Legacy.IndexPreRedesign`.
- **No new DS components**: every section is page-inlined markup. Hero banner,
  sidebar filter, product card, toolbar — all inlined in the template.
- **Reuse `<DesignSystem.footer />`** + DS header — matches every other
  redesigned page.
- **No new schema migrations.**
- **No new event handlers.** All existing handlers are preserved exactly.
- **Sort dropdown is inert** (stub) — mock shows it but no sort handler exists.
  The "Most popular" label is static text. Sort system is a future feature.
- **"Load N more products" button is inert** (stub) — mock shows it but no
  pagination handler exists. All products are loaded in mount. Pagination is a
  future feature.

## Visual components consumed

- `<BlocksterV2Web.DesignSystem.header active="shop" … />` ✓ existing (Wave 0)
- `<BlocksterV2Web.DesignSystem.footer />` ✓ existing (Wave 0)

**No new DS components needed.** The hero banner, sidebar filter, product card,
and toolbar are all page-specific markup inlined in the template.

## Data dependencies

### ✓ Existing — already in production

Every assign in `mount/3` and `handle_params/3` is preserved exactly:

- `@page_title` ("Shop - Browse Products")
- `@all_products` (list of Product structs with preloaded associations)
- `@products_by_id` (map of string ID → product for quick lookup)
- `@total_slots` (count of active products)
- `@display_slots` (list of `{slot_number, transformed_product_or_nil}`)
- `@slot_assignments` (map of product_id → [slot_numbers], for admin picker)
- `@filtered_products` (nil when no filter, list when filtered)
- `@categories_with_products` (unique categories from products, sorted)
- `@hubs_with_products` (unique hubs from products, sorted)
- `@brands_with_products` (unique vendor names, deduplicated, sorted)
- `@active_filter` (nil | {:category, slug, name} | {:hub, slug, name} | {:brand, name} | {:artist, slug, name} | {:tag, slug})
- `@show_product_picker` (boolean, admin only)
- `@picking_slot` (integer | nil, admin only)
- `@show_mobile_filters` (boolean)
- Default `WalletAuthEvents.default_assigns/0` from `use BlocksterV2Web, :live_view`

Helper functions preserved exactly:
- `transform_product/1` — transforms Product struct to display map
- `build_display_slots/2` — builds slot-based display list
- `build_slot_assignments/1` — builds admin slot assignment map
- `category_icon/1`, `brand_icon/1` — icon lookup functions
- `apply_url_filters/2` — URL param → filter state

### ⚠ Stubbed in v1

| Stub | What shows | Replaces it |
|---|---|---|
| Sort dropdown | Static "Most popular" button, inert (no handler) | Real sort handler with dropdown options | Follow-up commit |
| "Load N more products" button | Static button, inert (no handler) | Real pagination with server-side limit/offset | Follow-up commit |
| Product count in sidebar filter links | Mock shows counts (e.g. "48", "22") — **real** data from `length(filtered)` per category/hub/brand | n/a — this IS real data, computed from `@all_products` |
| Hero banner product count pill | Shows `@total_slots` — real data | n/a |
| Hero banner image | Static banner URL from existing `FullWidthBannerComponent` | n/a |

### ✗ New — must be added or schema-migrated

None. Bucket A.

## Handlers to preserve

Every `handle_event` and `handle_params` in the current LiveView MUST be wired
up by the new template exactly as today:

**`handle_params`:**
- `apply_url_filters/2` — reads `params["category"]`, `params["hub"]`,
  `params["brand"]`, `params["artist"]`, `params["tag"]` from URL and sets
  `@active_filter` + `@filtered_products`

**`handle_event`:**
- `"filter_by_category"` (`phx-click` on category sidebar links)
- `"filter_by_hub"` (`phx-click` on hub sidebar links)
- `"filter_by_brand"` (`phx-click` on brand sidebar links)
- `"clear_all_filters"` (`phx-click` on View All button + filter badge X)
- `"toggle_mobile_filters"` (`phx-click` on mobile filter FAB + drawer close)
- `"open_product_picker"` (`phx-click` on admin cog icon, admin only)
- `"close_product_picker"` (`phx-click` on modal close, admin only)
- `"ignore"` (`phx-click` on modal inner div, stops propagation, admin only)
- `"select_product_for_slot"` (`phx-click` on product in picker, admin only)

**No `handle_async`, `handle_info`, or PubSub subscriptions** in this module.

## JS hooks

- **`SolanaWallet`** — mounted on `#ds-site-header` by the DS header. Already
  in place after Wave 0.

No page-specific JS hooks. No new JS hooks.

## Tests required

### Component tests

None. No new DS components.

### LiveView tests

**Create** `test/blockster_v2_web/live/shop_live/index_test.exs` (no existing
test file exists for this page).

**Assertions:**

- DS header renders with `id="ds-site-header"` and `phx-hook="SolanaWallet"`
- Header `Shop` nav link is active
- Why Earn BUX banner renders (`"Why Earn BUX?"`)
- Hero banner renders with `"Spend the BUX you earned"` eyebrow +
  `"Crypto-inspired streetwear & gadgets"` headline +
  `"products in stock"` pill
- Sidebar filter renders with `"Products"`, `"Communities"`, `"Brands"` labels
- Product grid renders products with name, price, `"Buy Now"` button
- Products with BUX discount show strikethrough original + discounted price +
  `"with BUX tokens"` caption
- Products without discount show only the regular price
- Filter by category: click category link → URL patch → filtered products shown
- Filter by hub: click hub link → URL patch → filtered products shown
- Filter by brand: click brand link → URL patch → filtered products shown
- Clear filter: click "View all" → URL patch → all products shown
- Active filter badge renders with filter name + close X button
- Empty filtered results show "No products found" + "View All Products" link
- Footer renders (`"Where the chain meets the model."`)
- Admin product picker modal: admin user sees cog icon, opens picker, selects product

### setup_mnesia coverage

The `ShopSlots` module reads from the `:shop_product_slots` Mnesia table in
`build_display_list/1`. Tests MUST create this table in `setup_mnesia/0` or the
mount will crash with `{:aborted, {:no_exists, :shop_product_slots}}`. Fields:
`[:slot_number, :product_id]`.

### Manual checks (on `bin/dev`)

- `/shop` loads logged-in (products display, BUX balance in header, cart icon)
- `/shop` loads anonymous (Connect Wallet CTA, no admin tools)
- Sidebar category/hub/brand filters work (URL updates, grid filters)
- Clear filter returns to all products
- Mobile filter FAB appears on narrow viewport, drawer opens/closes
- Product cards link to `/shop/:slug`
- Hub logo badges appear on products with hub associations
- Products with BUX discount show strikethrough + discounted price
- Products without discount show only regular price
- Admin user sees slot cog icons, product picker opens/works
- DS header pill shows BUX balance, disconnect wallet works
- `mix test` — zero new failures vs baseline

## Per-page commit message

`redesign(shop-index): shop page refresh · full-bleed hero banner + sidebar filter + 3-col product grid`

## Stubbed in v1

| Stub | What it shows now | What replaces it | Resolved by release |
|---|---|---|---|
| Sort dropdown | Static "Most popular" button, no handler | Real sort handler + dropdown | Follow-up commit |
| "Load N more products" button | Static button, no handler | Paginated load-more | Follow-up commit |

## Open items

- **Hero banner image**: the mock uses an Unsplash placeholder. The existing
  template uses `https://ik.imagekit.io/blockster/Web%20Banner%203.png`. Use
  the existing ImageKit URL for production fidelity.
- **Product card image flip**: the existing template has a CSS 3D flip animation
  showing the second image on hover. The mock does NOT have this — it uses a
  simple static image. **Decision**: drop the flip animation to match the mock.
  Simpler, faster, matches the design language. The flip was a pre-redesign
  flourish.
- **Filter link counts**: the mock shows per-filter counts (e.g. "48", "22").
  The existing template does NOT show counts. **Decision**: add counts computed
  from `@all_products` — count products per category/hub/brand dynamically.
  This is display-only, no new data dependency.
