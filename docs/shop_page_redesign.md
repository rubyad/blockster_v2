# Shop Page Redesign - Implementation Plan

## Overview

This document details the complete redesign of the `/shop` page to include:
1. A hero banner header identical to `/shop-landing`
2. A persistent left sidebar with filtering options
3. Admin-curated product placements with cog icon controls
4. Smart filter behavior that overrides/restores curated placements

---

## Current State Analysis

### Existing `/shop` Page (ShopLive.Index)

**Location**: `lib/blockster_v2_web/live/shop_live/index.ex`

**Current Header** (to be replaced):
- Lightning bolt icon + "Crypto-Infused Streetwear" tagline button
- Large "Blockster Shop" heading with circular product imagery overlays
- Descriptive subheading about BUX discounts
- Three filter dropdowns (Hub, Artist, Category)
- "View All" button to clear filters

**Current Layout**:
- Full-width container with 4-column product grid
- No sidebar
- Filter dropdowns in header area
- Products loaded from database in natural order
- No admin product placement capability

### Existing `/shop-landing` Page (ShopLive.Landing)

**Location**: `lib/blockster_v2_web/live/shop_live/landing.ex`

**Header Component**: `FullWidthBannerComponent`
- Configurable background image with position/zoom controls
- Draggable text overlay with customizable:
  - Text content, color, size
  - Background color with opacity
  - Border radius
  - Position (percentage-based)
- Draggable CTA button with customizable:
  - Text, URL
  - Background and text colors
  - Size (small/medium/large)
  - Position
- Banner height setting
- Visibility toggles for text and button
- Admin edit modal for all settings
- Settings stored via `SiteSettings` with prefix-based keys

**Product Placement System**: `ShopTwoComponent` (example)
- Cog icon appears on hover for admin users
- Opens product picker modal
- Allows selecting specific products for each slot
- Saves product IDs as comma-separated string in `SiteSettings`
- Falls back to first N products if no placements configured

---

## Implementation Plan

### Phase 1: Route Change

**File**: `lib/blockster_v2_web/router.ex`

**Changes**:
```elixir
# Change Shop menu link to point to /shop (already does)
# No route changes needed - /shop already exists
```

**Navigation Update** (if needed):
- Verify Shop link in main navigation points to `/shop`
- Location: `lib/blockster_v2_web/components/layouts/app.html.heex` or similar

---

### Phase 2: New Shop Page Layout Structure

**File**: `lib/blockster_v2_web/live/shop_live/index.html.heex`

**New Layout Structure**:
```
┌─────────────────────────────────────────────────────────────────┐
│                    HERO BANNER (FullWidthBannerComponent)        │
│         Same as shop-landing with configurable image/text        │
└─────────────────────────────────────────────────────────────────┘
┌──────────────┬──────────────────────────────────────────────────┐
│              │                                                   │
│   LEFT       │               PRODUCTS GRID                       │
│   SIDEBAR    │                                                   │
│              │   ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐             │
│  ┌─────────┐ │   │ ⚙️  │  │ ⚙️  │  │ ⚙️  │  │ ⚙️  │             │
│  │View All │ │   │     │  │     │  │     │  │     │             │
│  └─────────┘ │   │     │  │     │  │     │  │     │             │
│              │   └─────┘  └─────┘  └─────┘  └─────┘             │
│  ─────────── │                                                   │
│  PRODUCTS    │   ┌─────┐  ┌─────┐  ┌─────┐  ┌─────┐             │
│  ─────────── │   │ ⚙️  │  │ ⚙️  │  │ ⚙️  │  │ ⚙️  │             │
│  □ T-Shirts  │   │     │  │     │  │     │  │     │             │
│  □ Hoodies   │   │     │  │     │  │     │  │     │             │
│  □ Sneakers  │   └─────┘  └─────┘  └─────┘  └─────┘             │
│  □ Sunglasses│                                                   │
│  □ Caps      │   ... more products ...                          │
│  □ Gadgets   │                                                   │
│              │                                                   │
│  ─────────── │                                                   │
│  COMMUNITIES │                                                   │
│  ─────────── │                                                   │
│  □ MoonPay   │                                                   │
│  □ Neo       │                                                   │
│  □ Rogue     │                                                   │
│  □ ...       │                                                   │
│              │                                                   │
│  ─────────── │                                                   │
│  BRANDS      │                                                   │
│  ─────────── │                                                   │
│  □ Nike      │                                                   │
│  □ Trezor    │                                                   │
│  □ Ledger    │                                                   │
│  □ Adidas    │                                                   │
│  □ Oakley    │                                                   │
│              │                                                   │
└──────────────┴──────────────────────────────────────────────────┘
```

---

### Phase 3: Hero Banner Implementation

**Add to Template** (`index.html.heex`):
```heex
<%!-- Hero Banner - Same as shop-landing --%>
<.live_component
  module={BlocksterV2Web.PostLive.FullWidthBannerComponent}
  id="shop-page-hero-banner"
  current_user={assigns[:current_user]}
  banner_key="shop_page_banner"
/>
```

**Settings Key**: `shop_page_banner` (separate from shop-landing to allow different configuration)

**Admin Capabilities** (inherited from FullWidthBannerComponent):
- Change banner background image
- Adjust image position and zoom
- Edit overlay text content, colors, size
- Edit button text, URL, colors, size
- Drag to reposition text and button
- Set banner height
- Toggle text/button visibility

---

### Phase 4: Left Sidebar Implementation

#### 4.1 Sidebar Container

**CSS Requirements**:
```css
/* Sidebar should be sticky, full height of viewport minus header */
.shop-sidebar {
  position: sticky;
  top: 80px; /* Account for main header */
  height: calc(100vh - 80px);
  overflow-y: auto;
}
```

**Template Structure**:
```heex
<div class="flex">
  <%!-- Left Sidebar --%>
  <aside class="w-64 flex-shrink-0 hidden lg:block">
    <div class="sticky top-20 h-[calc(100vh-5rem)] overflow-y-auto pr-4 pb-8">
      <%!-- View All Button --%>
      <button
        phx-click="clear_all_filters"
        class={[
          "w-full mb-6 py-3 px-4 rounded-lg font-haas_medium_65 text-sm transition-colors cursor-pointer",
          if(@active_filter == nil, do: "bg-black text-white", else: "bg-gray-100 text-gray-700 hover:bg-gray-200")
        ]}
      >
        View All
      </button>

      <%!-- Products Section (Categories - Dynamic from products) --%>
      <%= if @categories_with_products != [] do %>
        <div class="mb-8">
          <h3 class="text-sm font-haas_medium_65 text-gray-500 uppercase tracking-wider mb-4">Products</h3>
          <ul class="space-y-2">
            <%= for category <- @categories_with_products do %>
              <li>
                <button
                  phx-click="filter_by_category"
                  phx-value-slug={category.slug}
                  phx-value-name={category.name}
                  class={[
                    "w-full text-left px-3 py-2 rounded-lg text-sm font-haas_roman_55 transition-colors cursor-pointer",
                    if(match?({:category, _, _}, @active_filter) and elem(@active_filter, 1) == category.slug,
                      do: "bg-black text-white",
                      else: "text-gray-700 hover:bg-gray-100")
                  ]}
                >
                  <%= category.name %>
                </button>
              </li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <%!-- Communities Section (Hubs - Dynamic from products) --%>
      <%= if @hubs_with_products != [] do %>
        <div class="mb-8">
          <h3 class="text-sm font-haas_medium_65 text-gray-500 uppercase tracking-wider mb-4">Communities</h3>
          <ul class="space-y-2">
            <%= for hub <- @hubs_with_products do %>
              <li>
                <button
                  phx-click="filter_by_hub"
                  phx-value-slug={hub.slug}
                  phx-value-name={hub.name}
                  class={[
                    "w-full text-left px-3 py-2 rounded-lg text-sm font-haas_roman_55 transition-colors cursor-pointer flex items-center gap-2",
                    if(match?({:hub, _, _}, @active_filter) and elem(@active_filter, 1) == hub.slug,
                      do: "bg-black text-white",
                      else: "text-gray-700 hover:bg-gray-100")
                  ]}
                >
                  <%= if hub.logo_url do %>
                    <img src={hub.logo_url} alt={hub.name} class="w-5 h-5 rounded-full object-cover" />
                  <% end %>
                  <%= hub.name %>
                </button>
              </li>
            <% end %>
          </ul>
        </div>
      <% end %>

      <%!-- Brands Section (Vendors - Dynamic from products) --%>
      <%= if @brands_with_products != [] do %>
        <div class="mb-8">
          <h3 class="text-sm font-haas_medium_65 text-gray-500 uppercase tracking-wider mb-4">Brands</h3>
          <ul class="space-y-2">
            <%= for brand <- @brands_with_products do %>
              <li>
                <button
                  phx-click="filter_by_brand"
                  phx-value-brand={brand}
                  class={[
                    "w-full text-left px-3 py-2 rounded-lg text-sm font-haas_roman_55 transition-colors cursor-pointer",
                    if(@active_filter == {:brand, brand},
                      do: "bg-black text-white",
                      else: "text-gray-700 hover:bg-gray-100")
                  ]}
                >
                  <%= brand %>
                </button>
              </li>
            <% end %>
          </ul>
        </div>
      <% end %>
    </div>
  </aside>

  <%!-- Products Grid --%>
  <main class="flex-1 min-w-0">
    <%!-- Product cards here --%>
  </main>
</div>
```

#### 4.2 Sidebar Filter Categories (All Dynamic)

**Products Section** (dynamic from product categories):
- Extract unique categories from all active products
- Query categories via product associations
- Display category name, filter by `category.slug`
- Only shows categories that have at least one active product

**Extraction Logic**:
```elixir
# In mount - derive categories from products
categories_with_products = all_products
|> Enum.flat_map(fn p -> p.categories || [] end)
|> Enum.uniq_by(& &1.id)
|> Enum.sort_by(& &1.name)
```

**Communities Section** (dynamic from product hubs):
- Extract unique hubs from all active products
- Query: `Blog.list_hubs_with_products()`
- Display hub logo + name
- Only shows hubs that have at least one active product

**Extraction Logic**:
```elixir
# In mount - derive hubs from products
hubs_with_products = all_products
|> Enum.map(& &1.hub)
|> Enum.reject(&is_nil/1)
|> Enum.uniq_by(& &1.id)
|> Enum.sort_by(& &1.name)
```

**Brands Section** (dynamic from product vendors):
- Extract unique vendor names from all active products
- Filter out nil/empty vendors
- Display vendor name as-is

**Extraction Logic**:
```elixir
# In mount - derive brands/vendors from products
brands_with_products = all_products
|> Enum.map(& &1.vendor)
|> Enum.reject(&is_nil/1)
|> Enum.reject(&(&1 == ""))
|> Enum.uniq()
|> Enum.sort()
```

**Benefits of Dynamic Filters**:
- No hardcoded values to maintain
- Filters always reflect actual product data
- Empty filter sections can be hidden automatically
- New categories/hubs/brands appear automatically when products are added

---

### Phase 5: Admin Product Placement System

#### 5.1 Settings Storage

**Settings Key**: `shop_page_product_placements`

**Format**: JSON string containing ordered array of product IDs
```json
["uuid-1", "uuid-2", "uuid-3", "uuid-4", "uuid-5", ...]
```

**Alternative**: Comma-separated UUIDs (consistent with existing components)
```
uuid-1,uuid-2,uuid-3,uuid-4,uuid-5,...
```

#### 5.2 Product Card with Admin Cog

**Template**:
```heex
<div class="relative group">
  <%!-- Admin Cog Icon (top-right, visible on hover for admins) --%>
  <%= if @current_user && @current_user.is_admin do %>
    <button
      phx-click="open_product_picker"
      phx-value-slot={index}
      class="absolute top-3 right-3 z-20 opacity-0 group-hover:opacity-100 transition-opacity bg-white rounded-full p-2 shadow-md hover:shadow-lg cursor-pointer"
    >
      <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-gray-600" viewBox="0 0 20 20" fill="currentColor">
        <path fill-rule="evenodd" d="M11.49 3.17c-.38-1.56-2.6-1.56-2.98 0a1.532 1.532 0 01-2.286.948c-1.372-.836-2.942.734-2.106 2.106.54.886.061 2.042-.947 2.287-1.561.379-1.561 2.6 0 2.978a1.532 1.532 0 01.947 2.287c-.836 1.372.734 2.942 2.106 2.106a1.532 1.532 0 012.287.947c.379 1.561 2.6 1.561 2.978 0a1.533 1.533 0 012.287-.947c1.372.836 2.942-.734 2.106-2.106a1.533 1.533 0 01.947-2.287c1.561-.379 1.561-2.6 0-2.978a1.532 1.532 0 01-.947-2.287c.836-1.372-.734-2.942-2.106-2.106a1.532 1.532 0 01-2.287-.947zM10 13a3 3 0 100-6 3 3 0 000 6z" clip-rule="evenodd" />
      </svg>
    </button>
  <% end %>

  <%!-- Existing product card content --%>
  <.link navigate={~p"/shop/#{product.slug}"} class="...">
    <%!-- Card content --%>
  </.link>
</div>
```

#### 5.3 Product Picker Modal

**Reuse pattern from ShopTwoComponent**:
```heex
<%= if @show_product_picker do %>
  <div class="fixed inset-0 bg-black/50 z-50 flex items-center justify-center" phx-click="close_product_picker">
    <div class="bg-white rounded-xl max-w-2xl w-full max-h-[80vh] overflow-hidden" phx-click="ignore">
      <div class="p-4 border-b flex justify-between items-center">
        <h3 class="text-lg font-haas_medium_65">Select Product for Slot <%= @picking_slot + 1 %></h3>
        <button phx-click="close_product_picker" class="text-gray-500 hover:text-gray-700 cursor-pointer">
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
      <div class="p-4 overflow-y-auto max-h-[60vh]">
        <div class="grid grid-cols-3 gap-4">
          <%= for product <- @all_products do %>
            <button
              phx-click="select_product_for_slot"
              phx-value-id={product.id}
              class="border rounded-lg p-2 hover:border-black transition-colors cursor-pointer text-left"
            >
              <img src={get_product_image(product)} alt={product.title} class="w-full aspect-square object-cover rounded-lg mb-2" />
              <p class="text-sm font-haas_medium_65 truncate"><%= product.title %></p>
            </button>
          <% end %>
        </div>
      </div>
    </div>
  </div>
<% end %>
```

#### 5.4 Placement Logic

**On Mount** (in LiveView):
```elixir
def mount(_params, _session, socket) do
  # Load curated placements from SiteSettings
  placements_setting = SiteSettings.get("shop_page_product_placements", "")
  curated_product_ids = parse_product_ids(placements_setting)

  # Load all active products
  all_products = Shop.list_active_products(preload: [:images, :variants, :hub, :artist_record, :categories])

  # Build display order: curated first, then remaining products
  display_products = build_display_order(curated_product_ids, all_products)

  {:ok,
   socket
   |> assign(:all_products, all_products)
   |> assign(:curated_product_ids, curated_product_ids)
   |> assign(:products, display_products)
   |> assign(:active_filter, nil)
   |> assign(:show_product_picker, false)
   |> assign(:picking_slot, nil)
   # ... other assigns
  }
end

defp build_display_order(curated_ids, all_products) do
  # Get curated products in order
  curated = curated_ids
    |> Enum.map(fn id -> Enum.find(all_products, &(to_string(&1.id) == id)) end)
    |> Enum.reject(&is_nil/1)

  # Get remaining products not in curated list
  curated_id_set = MapSet.new(curated_ids)
  remaining = Enum.reject(all_products, fn p ->
    to_string(p.id) in curated_id_set
  end)

  curated ++ remaining
end
```

---

### Phase 6: Filter Behavior

#### 6.1 Filter State Management

**Assigns**:
```elixir
@active_filter  # nil | {:category, slug, name} | {:hub, slug, name} | {:brand, name}
@filtered_mode  # true when filter is active, false for curated view
```

**Filter Tuple Format**:
- Category (Products section): `{:category, slug, name}` - includes name for display
- Hub (Communities section): `{:hub, slug, name}` - includes name for display
- Brand (Brands section): `{:brand, name}` - name is the filter value

#### 6.2 Filter Event Handlers

```elixir
@impl true
def handle_event("filter_by_category", %{"slug" => slug, "name" => name}, socket) do
  filtered_products = filter_by_category(socket.assigns.all_products, slug)

  {:noreply,
   socket
   |> assign(:active_filter, {:category, slug, name})
   |> assign(:filtered_mode, true)
   |> assign(:products, Enum.map(filtered_products, &transform_product/1))}
end

@impl true
def handle_event("filter_by_hub", %{"slug" => slug, "name" => name}, socket) do
  filtered_products = filter_by_hub(socket.assigns.all_products, slug)

  {:noreply,
   socket
   |> assign(:active_filter, {:hub, slug, name})
   |> assign(:filtered_mode, true)
   |> assign(:products, Enum.map(filtered_products, &transform_product/1))}
end

@impl true
def handle_event("filter_by_brand", %{"brand" => brand}, socket) do
  filtered_products = filter_by_vendor(socket.assigns.all_products, brand)

  {:noreply,
   socket
   |> assign(:active_filter, {:brand, brand})
   |> assign(:filtered_mode, true)
   |> assign(:products, Enum.map(filtered_products, &transform_product/1))}
end

@impl true
def handle_event("clear_all_filters", _params, socket) do
  # Restore curated order
  display_products = build_display_order(
    socket.assigns.curated_product_ids,
    socket.assigns.all_products
  )

  {:noreply,
   socket
   |> assign(:active_filter, nil)
   |> assign(:filtered_mode, false)
   |> assign(:products, Enum.map(display_products, &transform_product/1))}
end
```

#### 6.3 Filter Logic Details

**Category Filtering** (Products section):
- Check if product has any category with matching slug
- Filters by `product.categories` association

```elixir
defp filter_by_category(products, category_slug) do
  Enum.filter(products, fn p ->
    Enum.any?(p.categories || [], fn cat -> cat.slug == category_slug end)
  end)
end
```

**Hub Filtering** (Communities section):
- Check `product.hub.slug` matches selected hub

```elixir
defp filter_by_hub(products, hub_slug) do
  Enum.filter(products, fn p ->
    p.hub && p.hub.slug == hub_slug
  end)
end
```

**Brand/Vendor Filtering** (Brands section):
- Check `product.vendor` field matches selected brand exactly

```elixir
defp filter_by_vendor(products, vendor) do
  Enum.filter(products, fn p ->
    p.vendor == vendor
  end)
end
```

---

### Phase 7: Admin Product Placement Events

```elixir
@impl true
def handle_event("open_product_picker", %{"slot" => slot}, socket) do
  {:noreply,
   socket
   |> assign(:show_product_picker, true)
   |> assign(:picking_slot, String.to_integer(slot))}
end

@impl true
def handle_event("close_product_picker", _params, socket) do
  {:noreply,
   socket
   |> assign(:show_product_picker, false)
   |> assign(:picking_slot, nil)}
end

@impl true
def handle_event("ignore", _params, socket) do
  {:noreply, socket}
end

@impl true
def handle_event("select_product_for_slot", %{"id" => product_id}, socket) do
  slot = socket.assigns.picking_slot
  curated_ids = socket.assigns.curated_product_ids

  # Update or insert product ID at slot position
  new_curated_ids = update_curated_ids(curated_ids, slot, product_id)

  # Save to SiteSettings
  SiteSettings.set("shop_page_product_placements", Enum.join(new_curated_ids, ","))

  # Rebuild display order
  display_products = build_display_order(new_curated_ids, socket.assigns.all_products)

  {:noreply,
   socket
   |> assign(:curated_product_ids, new_curated_ids)
   |> assign(:products, Enum.map(display_products, &transform_product/1))
   |> assign(:show_product_picker, false)
   |> assign(:picking_slot, nil)}
end

defp update_curated_ids(existing_ids, slot, new_id) do
  # Ensure list is long enough
  padded = existing_ids ++ List.duplicate("", max(0, slot + 1 - length(existing_ids)))

  # Replace at slot, filtering out empty strings
  padded
  |> List.replace_at(slot, new_id)
  |> Enum.filter(&(&1 != ""))
  |> Enum.uniq()  # Remove duplicates
end
```

---

### Phase 8: Mobile Responsiveness

#### 8.1 Sidebar Behavior on Mobile

**Desktop (lg and up)**: Sidebar always visible, sticky
**Mobile/Tablet**: Sidebar hidden, replaced with filter button + slide-out drawer

```heex
<%!-- Mobile Filter Button --%>
<button
  phx-click="toggle_mobile_filters"
  class="lg:hidden fixed bottom-4 right-4 z-40 bg-black text-white px-4 py-3 rounded-full shadow-lg flex items-center gap-2 cursor-pointer"
>
  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 4a1 1 0 011-1h16a1 1 0 011 1v2.586a1 1 0 01-.293.707l-6.414 6.414a1 1 0 00-.293.707V17l-4 4v-6.586a1 1 0 00-.293-.707L3.293 7.293A1 1 0 013 6.586V4z" />
  </svg>
  Filters
  <%= if @active_filter do %>
    <span class="bg-white text-black text-xs px-2 py-0.5 rounded-full">1</span>
  <% end %>
</button>

<%!-- Mobile Filter Drawer --%>
<%= if @show_mobile_filters do %>
  <div class="lg:hidden fixed inset-0 z-50">
    <div class="absolute inset-0 bg-black/50" phx-click="toggle_mobile_filters"></div>
    <div class="absolute right-0 top-0 h-full w-80 bg-white shadow-xl overflow-y-auto">
      <div class="p-4 border-b flex justify-between items-center">
        <h3 class="font-haas_medium_65">Filters</h3>
        <button phx-click="toggle_mobile_filters" class="text-gray-500 cursor-pointer">
          <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
          </svg>
        </button>
      </div>
      <div class="p-4">
        <%!-- Same filter content as desktop sidebar --%>
      </div>
    </div>
  </div>
<% end %>
```

#### 8.2 Grid Responsiveness

```heex
<div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4 md:gap-6">
  <%!-- Product cards --%>
</div>
```

---

### Phase 9: Dynamic Filter Extraction

All three filter sections are derived dynamically from active products at mount time.

#### 9.1 Categories (Products Section)

**Extract from loaded products**:
```elixir
# Derive unique categories from all active products
categories_with_products = all_products
|> Enum.flat_map(fn p -> p.categories || [] end)
|> Enum.uniq_by(& &1.id)
|> Enum.sort_by(& &1.name)
```

#### 9.2 Hubs (Communities Section)

**Extract from loaded products**:
```elixir
# Derive unique hubs from all active products
hubs_with_products = all_products
|> Enum.map(& &1.hub)
|> Enum.reject(&is_nil/1)
|> Enum.uniq_by(& &1.id)
|> Enum.sort_by(& &1.name)
```

#### 9.3 Vendors (Brands Section)

**Extract from loaded products**:
```elixir
# Derive unique vendors from all active products
brands_with_products = all_products
|> Enum.map(& &1.vendor)
|> Enum.reject(&is_nil/1)
|> Enum.reject(&(&1 == ""))
|> Enum.uniq()
|> Enum.sort()
```

#### 9.4 Filter Application Logic

**Category Filter** (Products section):
```elixir
defp filter_by_category(products, category_slug) do
  Enum.filter(products, fn p ->
    Enum.any?(p.categories || [], fn cat -> cat.slug == category_slug end)
  end)
end
```

**Hub Filter** (Communities section):
```elixir
defp filter_by_hub(products, hub_slug) do
  Enum.filter(products, fn p ->
    p.hub && p.hub.slug == hub_slug
  end)
end
```

**Vendor/Brand Filter** (Brands section):
```elixir
defp filter_by_vendor(products, vendor) do
  Enum.filter(products, fn p ->
    p.vendor == vendor
  end)
end
```

---

### Phase 10: Complete LiveView Module Structure

**File**: `lib/blockster_v2_web/live/shop_live/index.ex`

```elixir
defmodule BlocksterV2Web.ShopLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Shop
  alias BlocksterV2.SiteSettings

  @impl true
  def mount(_params, _session, socket) do
    # Load curated placements
    placements_setting = SiteSettings.get("shop_page_product_placements", "")
    curated_product_ids = parse_product_ids(placements_setting)

    # Load all active products with associations
    all_products = Shop.list_active_products(preload: [:images, :variants, :hub, :artist_record, :categories])

    # === DYNAMIC FILTER EXTRACTION ===

    # Categories (Products section) - from product categories
    categories_with_products = all_products
    |> Enum.flat_map(fn p -> p.categories || [] end)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.name)

    # Hubs (Communities section) - from product hubs
    hubs_with_products = all_products
    |> Enum.map(& &1.hub)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq_by(& &1.id)
    |> Enum.sort_by(& &1.name)

    # Vendors (Brands section) - from product vendors
    brands_with_products = all_products
    |> Enum.map(& &1.vendor)
    |> Enum.reject(&is_nil/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
    |> Enum.sort()

    # Build display order
    display_products = build_display_order(curated_product_ids, all_products)

    {:ok,
     socket
     |> assign(:page_title, "Shop - Browse Products")
     |> assign(:all_products, all_products)
     |> assign(:curated_product_ids, curated_product_ids)
     |> assign(:products, Enum.map(display_products, &transform_product/1))
     |> assign(:categories_with_products, categories_with_products)  # Dynamic from products
     |> assign(:hubs_with_products, hubs_with_products)              # Dynamic from products
     |> assign(:brands_with_products, brands_with_products)          # Dynamic from products
     |> assign(:active_filter, nil)
     |> assign(:filtered_mode, false)
     |> assign(:show_product_picker, false)
     |> assign(:picking_slot, nil)
     |> assign(:show_mobile_filters, false)}
  end

  # === FILTER EVENT HANDLERS ===

  @impl true
  def handle_event("filter_by_category", %{"slug" => slug, "name" => name}, socket) do
    filtered = filter_by_category(socket.assigns.all_products, slug)
    {:noreply,
     socket
     |> assign(:active_filter, {:category, slug, name})
     |> assign(:filtered_mode, true)
     |> assign(:products, Enum.map(filtered, &transform_product/1))}
  end

  @impl true
  def handle_event("filter_by_hub", %{"slug" => slug, "name" => name}, socket) do
    filtered = filter_by_hub(socket.assigns.all_products, slug)
    {:noreply,
     socket
     |> assign(:active_filter, {:hub, slug, name})
     |> assign(:filtered_mode, true)
     |> assign(:products, Enum.map(filtered, &transform_product/1))}
  end

  @impl true
  def handle_event("filter_by_brand", %{"brand" => brand}, socket) do
    filtered = filter_by_vendor(socket.assigns.all_products, brand)
    {:noreply,
     socket
     |> assign(:active_filter, {:brand, brand})
     |> assign(:filtered_mode, true)
     |> assign(:products, Enum.map(filtered, &transform_product/1))}
  end

  @impl true
  def handle_event("clear_all_filters", _params, socket) do
    display_products = build_display_order(
      socket.assigns.curated_product_ids,
      socket.assigns.all_products
    )
    {:noreply,
     socket
     |> assign(:active_filter, nil)
     |> assign(:filtered_mode, false)
     |> assign(:products, Enum.map(display_products, &transform_product/1))}
  end

  # === FILTER HELPER FUNCTIONS ===

  defp filter_by_category(products, category_slug) do
    Enum.filter(products, fn p ->
      Enum.any?(p.categories || [], fn cat -> cat.slug == category_slug end)
    end)
  end

  defp filter_by_hub(products, hub_slug) do
    Enum.filter(products, fn p ->
      p.hub && p.hub.slug == hub_slug
    end)
  end

  defp filter_by_vendor(products, vendor) do
    Enum.filter(products, fn p ->
      p.vendor == vendor
    end)
  end

  # ... other helper functions ...
end
```

---

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `lib/blockster_v2_web/live/shop_live/index.ex` | **Major Rewrite** | Add admin placements, sidebar filters, new state management |
| `lib/blockster_v2_web/live/shop_live/index.html.heex` | **Major Rewrite** | Replace header with banner component, add sidebar layout |
| `lib/blockster_v2_web/router.ex` | **No Change** | Routes already correct |
| Navigation component | **Verify** | Ensure Shop link points to `/shop` |

---

## Settings Keys Reference

| Key | Purpose | Default |
|-----|---------|---------|
| `shop_page_banner` | Hero banner image URL | Default hero image |
| `shop_page_banner_position` | Image position | "50% 50%" |
| `shop_page_banner_zoom` | Image zoom level | "100" |
| `shop_page_banner_overlay_text` | Banner text | "Shop the collection on Blockster" |
| `shop_page_banner_overlay_text_color` | Text color | "#ffffff" |
| `shop_page_banner_overlay_text_size` | Text size | "48" |
| `shop_page_banner_overlay_bg_color` | Text background | "#000000" |
| `shop_page_banner_overlay_bg_opacity` | Background opacity | "50" |
| `shop_page_banner_overlay_position` | Text position | "50% 50%" |
| `shop_page_banner_button_text` | Button text | "View All" |
| `shop_page_banner_button_url` | Button URL | "/shop" |
| `shop_page_banner_button_bg_color` | Button background | "#ffffff" |
| `shop_page_banner_button_text_color` | Button text color | "#000000" |
| `shop_page_banner_button_position` | Button position | "50% 70%" |
| `shop_page_banner_height` | Banner height (px) | "600" |
| `shop_page_banner_show_text` | Show text overlay | "true" |
| `shop_page_banner_show_button` | Show button | "true" |
| `shop_page_product_placements` | Comma-separated product UUIDs | "" |

---

## Testing Checklist

### Hero Banner
- [ ] Banner displays correctly on page load
- [ ] Admin can open edit modal
- [ ] All banner settings save and persist
- [ ] Text and button can be repositioned by dragging
- [ ] Banner image can be changed
- [ ] Visibility toggles work

### Left Sidebar (All Dynamic)
- [ ] Sidebar is sticky and full height
- [ ] Products section shows categories derived from active products
- [ ] Communities section shows hubs derived from active products
- [ ] Brands section shows vendors derived from active products
- [ ] Empty sections are hidden if no data
- [ ] "View All" button is highlighted when no filter active
- [ ] Clicking a filter highlights it
- [ ] Only one filter can be active at a time

### Filtering (Dynamic)
- [ ] Category filter works correctly (filters by product.categories)
- [ ] Hub filter works correctly (filters by product.hub)
- [ ] Brand filter works correctly (filters by product.vendor)
- [ ] Clicking a different filter replaces the previous one
- [ ] "View All" clears filters and restores curated order

### Admin Product Placements
- [ ] Cog icon appears on hover for admin users
- [ ] Cog icon does not appear for non-admin users
- [ ] Clicking cog opens product picker modal
- [ ] Selecting a product updates the slot
- [ ] Placements are saved to SiteSettings
- [ ] Curated order displays on page load
- [ ] Curated order is ignored when filter is active

### Mobile
- [ ] Sidebar hidden on mobile
- [ ] Filter button appears on mobile
- [ ] Drawer opens/closes correctly
- [ ] Grid responsive at all breakpoints

---

## Implementation Order

1. **Phase 1**: Rewrite `index.ex` with new mount/assigns structure (dynamic filters)
2. **Phase 2**: Update `index.html.heex` with hero banner + sidebar layout
3. **Phase 3**: Implement filter event handlers
4. **Phase 4**: Implement admin product placement events
5. **Phase 5**: Add product picker modal
6. **Phase 6**: Add mobile responsiveness
7. **Phase 7**: Test all functionality
8. **Phase 8**: Verify navigation links

---

## Detailed Implementation Todo Checklist

### Step 1: LiveView Module - State Management Setup (Dynamic Filters) ✅ COMPLETE
**File**: `lib/blockster_v2_web/live/shop_live/index.ex`

#### 1.1 Module Setup
- [x] **1.1.1** Add alias for `BlocksterV2.SiteSettings`
- [x] **1.1.2** Remove any hardcoded `@product_types` or `@brands` module attributes (all dynamic now)

#### 1.2 Mount Function Rewrite
- [x] **1.2.1** Load curated product placements from SiteSettings key `shop_page_product_placements`
- [x] **1.2.2** Parse placements string into list of UUIDs with `parse_product_ids/1`
- [x] **1.2.3** Load all active products with preloads: `[:images, :variants, :hub, :artist_record, :categories]`
- [x] **1.2.4** Extract dynamic categories from products:
  ```elixir
  categories_with_products = all_products
  |> Enum.flat_map(fn p -> p.categories || [] end)
  |> Enum.uniq_by(& &1.id)
  |> Enum.sort_by(& &1.name)
  ```
- [x] **1.2.5** Extract dynamic hubs from products:
  ```elixir
  hubs_with_products = all_products
  |> Enum.map(& &1.hub)
  |> Enum.reject(&is_nil/1)
  |> Enum.uniq_by(& &1.id)
  |> Enum.sort_by(& &1.name)
  ```
- [x] **1.2.6** Extract dynamic brands/vendors from products:
  ```elixir
  brands_with_products = all_products
  |> Enum.map(& &1.vendor)
  |> Enum.reject(&is_nil/1)
  |> Enum.reject(&(&1 == ""))
  |> Enum.uniq()
  |> Enum.sort()
  ```
- [x] **1.2.7** Build display order with `build_display_order/2` (curated first, then remaining)
- [x] **1.2.8** Add new socket assigns:
  - [x] `:all_products` - raw products from DB
  - [x] `:curated_product_ids` - list of placement UUIDs
  - [x] `:products` - transformed products for display
  - [x] `:categories_with_products` - dynamic from product categories
  - [x] `:hubs_with_products` - dynamic from product hubs
  - [x] `:brands_with_products` - dynamic from product vendors
  - [x] `:active_filter` - nil | {:category, slug, name} | {:hub, slug, name} | {:brand, name}
  - [x] `:filtered_mode` - boolean
  - [x] `:show_product_picker` - boolean
  - [x] `:picking_slot` - integer | nil
  - [x] `:show_mobile_filters` - boolean

#### 1.3 Helper Functions
- [x] **1.3.1** Add `parse_product_ids/1` function (handle empty string case)
- [x] **1.3.2** Add `build_display_order/2` function:
  - Get curated products in order from IDs
  - Get remaining products not in curated list
  - Return curated ++ remaining
- [x] **1.3.3** Keep existing `transform_product/1` function
- [x] **1.3.4** Add `filter_by_category/2` function:
  - Filter products where category.slug matches
- [x] **1.3.5** Add `filter_by_hub/2` function:
  - Filter products where hub.slug matches
- [x] **1.3.6** Add `filter_by_vendor/2` function:
  - Filter products where vendor matches
- [x] **1.3.7** Add `update_curated_ids/3` function for updating placements

---

### Step 2: LiveView Module - Filter Event Handlers ✅ COMPLETE
**File**: `lib/blockster_v2_web/live/shop_live/index.ex`

- [x] **2.1** Add `handle_event("filter_by_category", %{"slug" => slug, "name" => name}, socket)`:
  - Filter products by category using `filter_by_category/2`
  - Set `:active_filter` to `{:category, slug, name}`
  - Set `:filtered_mode` to `true`
  - Update `:products` with filtered & transformed results

- [x] **2.2** Add `handle_event("filter_by_hub", %{"slug" => slug, "name" => name}, socket)`:
  - Filter products where `product.hub.slug == slug`
  - Set `:active_filter` to `{:hub, slug, name}`
  - Set `:filtered_mode` to `true`
  - Update `:products`

- [x] **2.3** Add `handle_event("filter_by_brand", %{"brand" => brand}, socket)`:
  - Filter products where `product.vendor == brand`
  - Set `:active_filter` to `{:brand, brand}`
  - Set `:filtered_mode` to `true`
  - Update `:products`

- [x] **2.4** Modify existing `handle_event("clear_all_filters", _, socket)`:
  - Set `:active_filter` to `nil`
  - Set `:filtered_mode` to `false`
  - Rebuild display order using `build_display_order/2`
  - Update `:products` with curated order

- [x] **2.5** Remove old filter dropdown event handlers (no longer needed):
  - `toggle_dropdown`
  - `update_search`
  - `select_option`
  - `clear_filter`
  - `close_dropdown`

---

### Step 3: LiveView Module - Admin Product Placement Event Handlers ✅ COMPLETE
**File**: `lib/blockster_v2_web/live/shop_live/index.ex`

- [x] **3.1** Add `handle_event("open_product_picker", %{"slot" => slot}, socket)`:
  - Set `:show_product_picker` to `true`
  - Set `:picking_slot` to `String.to_integer(slot)`

- [x] **3.2** Add `handle_event("close_product_picker", _params, socket)`:
  - Set `:show_product_picker` to `false`
  - Set `:picking_slot` to `nil`

- [x] **3.3** Add `handle_event("ignore", _params, socket)` for modal click handling

- [x] **3.4** Add `handle_event("select_product_for_slot", %{"id" => product_id}, socket)`:
  - Get current slot from `:picking_slot`
  - Update curated IDs using `update_curated_ids/3`
  - Save to SiteSettings with key `shop_page_product_placements`
  - Rebuild display order
  - Close picker modal
  - Update socket assigns

---

### Step 4: LiveView Module - Mobile Filter Event Handlers ✅ COMPLETE
**File**: `lib/blockster_v2_web/live/shop_live/index.ex`

- [x] **4.1** Add `handle_event("toggle_mobile_filters", _params, socket)`:
  - Toggle `:show_mobile_filters` boolean

---

### Step 5: Template - Remove Old Header ✅ COMPLETE
**File**: `lib/blockster_v2_web/live/shop_live/index.html.heex`

- [x] **6.1** Remove entire header section (lines ~1-33):
  - Lightning bolt button
  - "Blockster Shop" heading with images
  - Subheading paragraph
- [x] **6.2** Remove filter dropdowns section (lines ~35-223):
  - Hub filter dropdown
  - Artist filter dropdown
  - Category filter dropdown
  - "View All" button (will be recreated in sidebar)

---

### Step 6: Template - Add Hero Banner Component ✅ COMPLETE
**File**: `lib/blockster_v2_web/live/shop_live/index.html.heex`

- [x] **7.1** Add FullWidthBannerComponent at top of template:
  ```heex
  <.live_component
    module={BlocksterV2Web.PostLive.FullWidthBannerComponent}
    id="shop-page-hero-banner"
    current_user={assigns[:current_user]}
    banner_key="shop_page_banner"
  />
  ```
- [ ] **7.2** Verify banner renders correctly
- [ ] **7.3** Test admin edit functionality

---

### Step 7: Template - Add Sidebar + Main Layout Structure ✅ COMPLETE
**File**: `lib/blockster_v2_web/live/shop_live/index.html.heex`

- [x] **8.1** Create flex container wrapping sidebar + products:
  ```heex
  <div class="container mx-auto px-4 pt-8">
    <div class="flex gap-8">
      <!-- Sidebar -->
      <!-- Products Grid -->
    </div>
  </div>
  ```

- [x] **8.2** Add sidebar `<aside>` element:
  - [x] Width: `w-64`
  - [x] Flex shrink: `flex-shrink-0`
  - [x] Hidden on mobile: `hidden lg:block`

- [x] **8.3** Add sticky inner container:
  - [x] Position: `sticky top-20`
  - [x] Height: `h-[calc(100vh-5rem)]`
  - [x] Overflow: `overflow-y-auto`
  - [x] Padding: `pr-4 pb-8`

---

### Step 8: Template - Sidebar "View All" Button ✅ COMPLETE
**File**: `lib/blockster_v2_web/live/shop_live/index.html.heex`

- [x] **9.1** Add "View All" button at top of sidebar:
  ```heex
  <button
    phx-click="clear_all_filters"
    class={[
      "w-full mb-6 py-3 px-4 rounded-lg font-haas_medium_65 text-sm transition-colors cursor-pointer",
      if(@active_filter == nil, do: "bg-black text-white", else: "bg-gray-100 text-gray-700 hover:bg-gray-200")
    ]}
  >
    View All
  </button>
  ```
- [ ] **9.2** Verify active state styling when no filter selected

---

### Step 9: Template - Sidebar "Products" Section (Categories) ✅ COMPLETE
**File**: `lib/blockster_v2_web/live/shop_live/index.html.heex`

- [x] **9.1** Add section container with heading:
  ```heex
  <div class="mb-8">
    <h3 class="text-sm font-haas_medium_65 text-gray-500 uppercase tracking-wider mb-4">Products</h3>
    <ul class="space-y-2">
      <!-- Category buttons (dynamic from products) -->
    </ul>
  </div>
  ```

- [x] **9.2** Add `for` loop iterating over `@categories_with_products`

- [x] **9.3** Add filter button for each category:
  - [x] `phx-click="filter_by_category"`
  - [x] `phx-value-slug={category.slug}`
  - [x] `phx-value-name={category.name}`
  - [x] Active state: check `match?({:category, slug, _}, @active_filter) and elem(@active_filter, 1) == category.slug`
  - [x] Active styling: `bg-black text-white`
  - [x] Inactive styling: `text-gray-700 hover:bg-gray-100`
  - [x] Add `cursor-pointer` class

- [x] **9.4** Conditionally hide section if `@categories_with_products` is empty

---

### Step 10: Template - Sidebar "Communities" Section (Hubs) ✅ COMPLETE
**File**: `lib/blockster_v2_web/live/shop_live/index.html.heex`

- [x] **10.1** Add section container with heading:
  ```heex
  <div class="mb-8">
    <h3 class="text-sm font-haas_medium_65 text-gray-500 uppercase tracking-wider mb-4">Communities</h3>
    <ul class="space-y-2">
      <!-- Hub buttons (dynamic from products) -->
    </ul>
  </div>
  ```

- [x] **10.2** Add `for` loop iterating over `@hubs_with_products`

- [x] **10.3** Add filter button for each hub:
  - [x] `phx-click="filter_by_hub"`
  - [x] `phx-value-slug={hub.slug}`
  - [x] `phx-value-name={hub.name}`
  - [x] Active state: check `match?({:hub, slug, _}, @active_filter) and elem(@active_filter, 1) == hub.slug`
  - [x] Include hub logo image if available
  - [x] Add `cursor-pointer` class

- [x] **10.4** Conditionally hide section if `@hubs_with_products` is empty

---

### Step 11: Template - Sidebar "Brands" Section (Vendors) ✅ COMPLETE
**File**: `lib/blockster_v2_web/live/shop_live/index.html.heex`

- [x] **11.1** Add section container with heading:
  ```heex
  <div class="mb-8">
    <h3 class="text-sm font-haas_medium_65 text-gray-500 uppercase tracking-wider mb-4">Brands</h3>
    <ul class="space-y-2">
      <!-- Brand/vendor buttons (dynamic from products) -->
    </ul>
  </div>
  ```

- [x] **11.2** Add `for` loop iterating over `@brands_with_products`

- [x] **11.3** Add filter button for each brand:
  - [x] `phx-click="filter_by_brand"`
  - [x] `phx-value-brand={brand}`
  - [x] Active state: check `@active_filter == {:brand, brand}`
  - [x] Add `cursor-pointer` class

- [x] **11.4** Conditionally hide section if `@brands_with_products` is empty

---

### Step 12: Template - Products Grid Main Area ✅ COMPLETE
**File**: `lib/blockster_v2_web/live/shop_live/index.html.heex`

- [x] **13.1** Add main content wrapper:
  ```heex
  <main class="flex-1 min-w-0">
    <!-- Products grid -->
  </main>
  ```

- [x] **13.2** Add responsive grid container:
  ```heex
  <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4 md:gap-6">
    <!-- Product cards -->
  </div>
  ```

- [x] **13.3** Add `for` loop with index: `for {product, index} <- Enum.with_index(@products)`

---

### Step 13: Template - Product Card with Admin Cog ✅ COMPLETE
**File**: `lib/blockster_v2_web/live/shop_live/index.html.heex`

- [x] **14.1** Wrap each product card in relative container with group:
  ```heex
  <div class="relative group">
    <!-- Admin cog -->
    <!-- Product link/card -->
  </div>
  ```

- [x] **14.2** Add admin cog icon (conditional on `@current_user.is_admin`):
  - [x] Position: `absolute top-3 right-3 z-20`
  - [x] Visibility: `opacity-0 group-hover:opacity-100 transition-opacity`
  - [x] Styling: `bg-white rounded-full p-2 shadow-md hover:shadow-lg`
  - [x] `phx-click="open_product_picker"`
  - [x] `phx-value-slot={index}`
  - [x] Add `cursor-pointer` class
  - [x] Add cog SVG icon

- [x] **14.3** Keep existing product card structure (link, images, flip effect, pricing)

---

### Step 14: Template - Product Picker Modal ✅ COMPLETE
**File**: `lib/blockster_v2_web/live/shop_live/index.html.heex`

- [x] **15.1** Add conditional modal container:
  ```heex
  <%= if @show_product_picker do %>
    <div class="fixed inset-0 bg-black/50 z-50 flex items-center justify-center" phx-click="close_product_picker">
      <!-- Modal content -->
    </div>
  <% end %>
  ```

- [x] **15.2** Add modal content box:
  - [x] Styling: `bg-white rounded-xl max-w-2xl w-full max-h-[80vh] overflow-hidden`
  - [x] `phx-click="ignore"` to prevent closing when clicking inside

- [x] **15.3** Add modal header:
  - [x] Title: "Select Product for Slot X" (use `@picking_slot + 1`)
  - [x] Close button with X icon
  - [x] `phx-click="close_product_picker"` on close button

- [x] **15.4** Add scrollable product list:
  - [x] Container: `p-4 overflow-y-auto max-h-[60vh]`
  - [x] Grid: `grid grid-cols-3 gap-4`

- [x] **15.5** Add product selection buttons:
  - [x] Loop over `@all_products`
  - [x] `phx-click="select_product_for_slot"`
  - [x] `phx-value-id={product.id}`
  - [x] Show product image and title
  - [x] Add `cursor-pointer` class

---

### Step 15: Template - Mobile Filter Button ✅ COMPLETE
**File**: `lib/blockster_v2_web/live/shop_live/index.html.heex`

- [x] **16.1** Add floating filter button (visible only on mobile):
  ```heex
  <button
    phx-click="toggle_mobile_filters"
    class="lg:hidden fixed bottom-4 right-4 z-40 bg-black text-white px-4 py-3 rounded-full shadow-lg flex items-center gap-2 cursor-pointer"
  >
    <!-- Filter icon SVG -->
    Filters
    <!-- Badge showing active filter count -->
  </button>
  ```

- [x] **16.2** Add filter icon SVG
- [x] **16.3** Add badge showing "1" when `@active_filter` is not nil

---

### Step 16: Template - Mobile Filter Drawer ✅ COMPLETE
**File**: `lib/blockster_v2_web/live/shop_live/index.html.heex`

- [x] **17.1** Add conditional drawer container:
  ```heex
  <%= if @show_mobile_filters do %>
    <div class="lg:hidden fixed inset-0 z-50">
      <!-- Backdrop -->
      <!-- Drawer panel -->
    </div>
  <% end %>
  ```

- [x] **17.2** Add backdrop overlay:
  - [x] Styling: `absolute inset-0 bg-black/50`
  - [x] `phx-click="toggle_mobile_filters"`

- [x] **17.3** Add drawer panel:
  - [x] Position: `absolute right-0 top-0 h-full w-80`
  - [x] Styling: `bg-white shadow-xl overflow-y-auto`

- [x] **17.4** Add drawer header with close button

- [x] **17.5** Copy sidebar filter content into drawer body:
  - [x] View All button
  - [x] Products section
  - [x] Communities section
  - [x] Brands section

- [x] **17.6** Mobile filters auto-close after selection (via assign in event handlers)

---

### Step 17: Extract Shared Filter Component (Optional Optimization)
**File**: Create `lib/blockster_v2_web/live/shop_live/filter_sidebar_component.ex` (optional)

- [ ] **18.1** Create function component for filter sidebar content
- [ ] **18.2** Accept assigns: `product_types`, `hubs_with_products`, `brands`, `active_filter`
- [ ] **18.3** Use in both desktop sidebar and mobile drawer
- [ ] **18.4** Reduces code duplication

**Note**: Deferred - filter content is duplicated between desktop sidebar and mobile drawer but works correctly. Extraction can be done as a future optimization.

---

### Step 18: Verify Navigation
**File**: Check navigation component (likely `app.html.heex` or header component)

- [ ] **19.1** Find where Shop link is defined in main navigation
- [ ] **19.2** Verify it points to `/shop` (not `/shop-landing`)
- [ ] **19.3** Test clicking Shop in nav goes to redesigned page

---

### Step 19: CSS/Styling Verification

- [ ] **20.1** Verify all clickable elements have `cursor-pointer`
- [ ] **20.2** Verify custom fonts used: `font-haas_medium_65`, `font-haas_roman_55`
- [ ] **20.3** Verify no arbitrary hex values where Tailwind classes exist
- [ ] **20.4** Test hover states on all interactive elements
- [ ] **20.5** Test active/selected states on filter buttons

---

### Step 21: Functional Testing - Hero Banner

- [ ] **21.1** Page loads with banner visible
- [ ] **21.2** Banner uses `shop_page_banner` settings key (separate from shop-landing)
- [ ] **21.3** Admin can click edit button to open modal
- [ ] **21.4** Admin can change banner image URL
- [ ] **21.5** Admin can adjust image position/zoom
- [ ] **21.6** Admin can edit overlay text content
- [ ] **21.7** Admin can change text colors and size
- [ ] **21.8** Admin can drag text overlay to reposition
- [ ] **21.9** Admin can edit button text, URL, colors
- [ ] **21.10** Admin can drag button to reposition
- [ ] **21.11** Admin can toggle text/button visibility
- [ ] **21.12** Settings persist after page reload
- [ ] **21.13** Non-admin users cannot see edit controls

---

### Step 22: Functional Testing - Left Sidebar (Dynamic Filters)

- [ ] **22.1** Sidebar visible on desktop (lg breakpoint and up)
- [ ] **22.2** Sidebar hidden on mobile/tablet
- [ ] **22.3** Sidebar is sticky when scrolling
- [ ] **22.4** Sidebar scrolls independently if content overflows
- [ ] **22.5** "View All" button highlighted (active) on initial page load
- [ ] **22.6** Products section shows categories extracted from active products (dynamic)
- [ ] **22.7** Products section is hidden if no products have categories
- [ ] **22.8** Communities section shows hubs extracted from active products (only those with products)
- [ ] **22.9** Communities section shows hub logos
- [ ] **22.10** Communities section is hidden if no products have hubs
- [ ] **22.11** Brands section shows vendors extracted from active products (dynamic)
- [ ] **22.12** Brands section is hidden if no products have vendors
- [ ] **22.13** Adding a product with new category/hub/vendor updates filters on next page load

---

### Step 23: Functional Testing - Filter Behavior (Dynamic)

- [ ] **23.1** Clicking category filter (Products section) filters by product.categories
- [ ] **23.2** Clicked filter becomes highlighted (active state)
- [ ] **23.3** "View All" becomes unhighlighted when filter selected
- [ ] **23.4** Clicking hub filter (Communities section) filters by product.hub
- [ ] **23.5** Clicking brand filter (Brands section) filters by product.vendor
- [ ] **23.6** Clicking different filter replaces previous filter (only one active)
- [ ] **23.7** Clicking "View All" clears all filters
- [ ] **23.8** After "View All", curated product order is restored
- [ ] **23.9** Products grid shows correct count for each filter
- [ ] **23.10** Empty filter results handled gracefully (show message or empty state)
- [ ] **23.11** Category filter matches products where any category.slug matches
- [ ] **23.12** Hub filter matches products where hub.slug matches
- [ ] **23.13** Brand filter matches products where vendor string matches exactly

---

### Step 24: Functional Testing - Admin Product Placements

- [ ] **24.1** Admin sees cog icon on hover over product cards
- [ ] **24.2** Non-admin does NOT see cog icon
- [ ] **24.3** Clicking cog opens product picker modal
- [ ] **24.4** Modal shows all active products
- [ ] **24.5** Modal can be closed via X button
- [ ] **24.6** Modal can be closed by clicking backdrop
- [ ] **24.7** Selecting a product updates that slot
- [ ] **24.8** Modal closes after product selection
- [ ] **24.9** Product appears in correct position in grid
- [ ] **24.10** Placement is saved to SiteSettings
- [ ] **24.11** Placements persist after page reload
- [ ] **24.12** Multiple slots can be placed with different products
- [ ] **24.13** Same product can be removed by placing different product
- [ ] **24.14** When filter is active, cog icon still works but placement saved for unfiltered view

---

### Step 25: Functional Testing - Curated Order Logic

- [ ] **25.1** On page load (no filters), curated products appear first
- [ ] **25.2** Non-curated products appear after curated ones
- [ ] **25.3** Curated products maintain their slot order
- [ ] **25.4** When filter is applied, curated order is ignored
- [ ] **25.5** Filtered results show natural order (or by relevance)
- [ ] **25.6** Clicking "View All" restores curated order

---

### Step 26: Functional Testing - Mobile Responsiveness

- [ ] **26.1** Sidebar hidden on screens < lg breakpoint
- [ ] **26.2** Floating filter button visible on mobile
- [ ] **26.3** Filter button shows badge when filter is active
- [ ] **26.4** Clicking filter button opens drawer
- [ ] **26.5** Drawer slides in from right
- [ ] **26.6** Backdrop dims the background
- [ ] **26.7** Clicking backdrop closes drawer
- [ ] **26.8** Clicking X closes drawer
- [ ] **26.9** Selecting filter in drawer applies filter
- [ ] **26.10** Drawer closes after filter selection
- [ ] **26.11** Product grid is responsive (1 col mobile, 2 col sm, 3 col lg, 4 col xl)
- [ ] **26.12** Product cards look good at all breakpoints

---

### Step 27: Functional Testing - Product Cards

- [ ] **27.1** Product image displays correctly
- [ ] **27.2** Image flip effect works on hover (desktop)
- [ ] **27.3** Hub logo badge displays in top-left
- [ ] **27.4** Product title centered below image
- [ ] **27.5** Original price shown with strikethrough
- [ ] **27.6** Discounted price shown prominently
- [ ] **27.7** "with BUX tokens" text shown when discount available
- [ ] **27.8** "Buy Now" button styled correctly
- [ ] **27.9** Clicking card navigates to product detail page
- [ ] **27.10** Card has hover shadow effect

---

### Step 28: Edge Cases & Error Handling

- [ ] **28.1** Handle empty products list gracefully
- [ ] **28.2** Handle no hubs with products (empty Communities section)
- [ ] **28.3** Handle product without images
- [ ] **28.4** Handle product without hub
- [ ] **28.5** Handle filter with no matching products
- [ ] **28.6** Handle corrupted SiteSettings data for placements
- [ ] **28.7** Handle very long hub names (truncate or wrap)
- [ ] **28.8** Handle very long product titles

---

### Step 29: Performance Checks

- [ ] **29.1** Page loads quickly (<2 seconds)
- [ ] **29.2** Filter clicks respond instantly
- [ ] **29.3** Product picker modal opens quickly
- [ ] **29.4** No unnecessary database queries on filter changes
- [ ] **29.5** Images use lazy loading
- [ ] **29.6** Images optimized through ImageKit

---

### Step 30: Final Cleanup

- [x] **30.1** Remove unused assigns from old implementation
- [x] **30.2** Remove unused event handlers from old implementation
- [x] **30.3** Remove unused helper functions
- [ ] **30.4** Remove commented-out code
- [x] **30.5** Ensure all clickable elements have `cursor-pointer`
- [ ] **30.6** Code review for consistency with project patterns
- [ ] **30.7** Test in production-like environment
- [ ] **30.8** Update CLAUDE.md with any new learnings

---

## Implementation Progress

### Session: Feb 2, 2026

#### Completed Steps 1-16 (Full Implementation)

**Branch**: `shop-redesign`

**Files Changed**:
1. `lib/blockster_v2_web/live/shop_live/index.ex` - Complete rewrite
2. `lib/blockster_v2_web/live/shop_live/index.html.heex` - Complete rewrite

#### What Was Implemented

**LiveView Module (`index.ex`)**:
- ✅ Added `SiteSettings` alias for curated product placements
- ✅ Removed old dropdown-based filter system entirely
- ✅ New mount function with dynamic filter extraction
- ✅ All new socket assigns for sidebar filters and admin placements
- ✅ New filter event handlers: `filter_by_category`, `filter_by_hub`, `filter_by_brand`
- ✅ Admin product placement handlers: `open_product_picker`, `close_product_picker`, `select_product_for_slot`
- ✅ Mobile filter handler: `toggle_mobile_filters`
- ✅ Helper functions: `parse_product_ids/1`, `build_display_order/2`, filter functions, `update_curated_ids/3`
- ✅ Removed unused `get_sample_products/0` function
- ✅ Removed unused `@token_value_usd` module attribute
- ✅ Removed all old dropdown event handlers (`toggle_dropdown`, `update_search`, `select_option`, `clear_filter`, `close_dropdown`)

**Template (`index.html.heex`)**:
- ✅ Hero banner using `FullWidthBannerComponent` with key `shop_page_banner`
- ✅ Left sidebar (desktop only, `lg:block`) with sticky positioning
- ✅ "View All" button with active state styling
- ✅ Products section (categories dynamically extracted from products)
- ✅ Communities section (hubs with logos dynamically extracted)
- ✅ Brands section (vendors dynamically extracted)
- ✅ Product grid with responsive columns (`grid-cols-1 sm:2 lg:3 xl:4`)
- ✅ Admin cog icon on product cards (hover, admin only)
- ✅ Empty state with "View All Products" button
- ✅ Mobile filter button (fixed bottom-right)
- ✅ Mobile filter drawer (slide-in from right)
- ✅ Product picker modal for admin curated placements
- ✅ All clickable elements have `cursor-pointer`

#### Key Implementation Details

**Filter State Management**:
```elixir
# Filter states stored as tuples for easy pattern matching
@active_filter  # nil | {:category, slug, name} | {:hub, slug, name} | {:brand, name}
```

**Dynamic Filter Extraction** (in mount):
```elixir
# Categories from product associations
categories_with_products = all_products
|> Enum.flat_map(fn p -> p.categories || [] end)
|> Enum.uniq_by(& &1.id)
|> Enum.sort_by(& &1.name)

# Hubs from product associations
hubs_with_products = all_products
|> Enum.map(& &1.hub)
|> Enum.reject(&is_nil/1)
|> Enum.uniq_by(& &1.id)
|> Enum.sort_by(& &1.name)

# Vendors from product field
brands_with_products = all_products
|> Enum.map(& &1.vendor)
|> Enum.reject(&is_nil/1)
|> Enum.reject(&(&1 == ""))
|> Enum.uniq()
|> Enum.sort()
```

**Curated Product Placements**:
- Stored in SiteSettings key: `shop_page_product_placements`
- Format: Comma-separated product UUIDs
- Admin clicks cog → opens product picker → selects product → saves to SiteSettings
- Display order: curated products first, then remaining products in natural order

**Template Pattern Matching for Active States**:
```heex
<%!-- Category filter active state --%>
if(match?({:category, _, _}, @active_filter) and elem(@active_filter, 1) == category.slug,
  do: "bg-black text-white",
  else: "text-gray-700 hover:bg-gray-100")

<%!-- Brand filter active state (simpler - no name in tuple) --%>
if(@active_filter == {:brand, brand},
  do: "bg-black text-white",
  else: "text-gray-700 hover:bg-gray-100")
```

#### Compilation Status
- ✅ Compiles without errors
- ⚠️ Unrelated warnings in other files (price_tracker.ex, user_auth.ex, bux_booster_live.ex)

#### Remaining Testing Checklist
- [ ] Test hero banner displays and admin can edit settings
- [ ] Test sidebar filter buttons highlight correctly
- [ ] Test category filter filters products correctly
- [ ] Test hub filter filters products correctly
- [ ] Test brand filter filters products correctly
- [ ] Test "View All" restores curated order
- [ ] Test admin cog appears on hover (admin only)
- [ ] Test product picker modal opens/closes
- [ ] Test selecting product updates curated placement
- [ ] Test placements persist after page reload
- [ ] Test mobile filter button appears on small screens
- [ ] Test mobile drawer opens/closes
- [ ] Test mobile drawer filters work
- [ ] Test empty state appears when no products match filter
- [ ] Test product cards link to correct product pages
- [ ] Test image flip effect works on hover

#### Notes for Next Session
1. The `@all_products` assign contains raw DB records (not transformed) - needed for filter operations
2. The `@products` assign contains transformed products for display
3. Filter operations work on raw DB records, then transform results for display
4. Mobile filters auto-close after selection (sets `show_mobile_filters: false`)
5. Product picker shows raw DB products with `product.images` and `product.title`
