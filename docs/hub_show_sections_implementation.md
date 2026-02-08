# Hub Show Page Sections Implementation Guide

This document details the current implementation of sections on the Hub Show page (`/hubs/:slug`) and provides specifications for implementing the Videos, Shop, and Events sections properly.

---

## Table of Contents

1. [Current Architecture](#current-architecture)
2. [Tab System](#tab-system)
3. [Current Section Implementations](#current-section-implementations)
4. [Implementation Requirements](#implementation-requirements)
5. [Empty State Design Specifications](#empty-state-design-specifications)
6. [Code Changes Required](#code-changes-required)

---

## Current Architecture

### Files

| File | Purpose |
|------|---------|
| [lib/blockster_v2_web/live/hub_live/show.ex](lib/blockster_v2_web/live/hub_live/show.ex) | LiveView module - data loading, event handlers |
| [lib/blockster_v2_web/live/hub_live/show.html.heex](lib/blockster_v2_web/live/hub_live/show.html.heex) | Template - UI rendering |
| [lib/blockster_v2_web/live/post_live/videos_component.ex](lib/blockster_v2_web/live/post_live/videos_component.ex) | Videos section component |
| [lib/blockster_v2_web/live/post_live/shop_two_component.ex](lib/blockster_v2_web/live/post_live/shop_two_component.ex) | Shop section component (4 products) |
| [lib/blockster_v2_web/live/post_live/events_cards_component.ex](lib/blockster_v2_web/live/post_live/events_cards_component.ex) | Events cards component |

### Data Flow

```
mount/3
  └── Blog.get_hub_by_slug_with_associations(slug)
  └── Blog.list_published_posts_by_hub(hub.id, limit: 5)  → posts_three
  └── Blog.list_published_posts_by_hub(hub.id, limit: 3)  → posts_four
  └── Blog.list_published_posts_by_hub(hub.id, limit: 3)  → videos_posts
  └── assign socket with all state
```

### Socket Assigns

| Assign | Type | Purpose |
|--------|------|---------|
| `@hub` | Hub struct | Current hub data with associations |
| `@posts_three` | list | First 5 posts for PostsThreeComponent |
| `@posts_four` | list | Next 3 posts for PostsFourComponent |
| `@videos_posts` | list | 3 posts for VideosComponent |
| `@show_all` | boolean | Show All tab (default: true) |
| `@show_news` | boolean | Show News tab |
| `@show_videos` | boolean | Show Videos tab |
| `@show_shop` | boolean | Show Shop tab |
| `@show_events` | boolean | Show Events tab |
| `@show_mobile_menu` | boolean | Mobile dropdown state |
| `@news_loaded` | boolean | Whether news has been lazy-loaded |
| `@videos_loaded` | boolean | Whether videos has been lazy-loaded |
| `@shop_loaded` | boolean | Whether shop has been lazy-loaded |

---

## Tab System

### Desktop Tabs (Lines 115-154)

- 5 equal-width buttons in a pill container with `bg-[#E7E8F1]`
- Active tab gets `bg-white` background
- All tabs use `phx-click="switch_tab"` with `phx-value-tab="{name}"`

### Mobile Dropdown (Lines 156-215)

- Single dropdown button showing current tab name
- Chevron rotates 180° when open
- Dropdown menu with all tab options
- Uses `phx-click-away="close_mobile_menu"` for auto-close

### Tab Switch Handler (Lines 64-111)

```elixir
def handle_event("switch_tab", %{"tab" => tab}, socket) do
  socket =
    socket
    |> assign(:show_all, tab == "all")
    |> assign(:show_news, tab == "news")
    |> assign(:show_videos, tab == "videos")
    |> assign(:show_shop, tab == "shop")
    |> assign(:show_events, tab == "events")
    |> assign(:show_mobile_menu, false)
  # ... lazy loading logic
end
```

---

## Current Section Implementations

### 1. All Tab Content (Lines 220-263)

Currently displays:
1. **PostsThreeComponent** - 5 posts
2. **"Read more stories" link** - Switches to News tab
3. **VideosComponent** - 3 posts (same as regular posts, with play button overlay)
4. **ShopTwoComponent** - 4 products (NOT hub-specific - uses global SiteSettings)
5. **EventsCardsComponent** - Shows all published events (NOT hub-specific)

### 2. Videos Section

**Current State:**

- Uses `VideosComponent` which receives `@videos_posts`
- `@videos_posts` is loaded in mount: `Blog.list_published_posts_by_hub(hub.id, limit: 3)`
- **ISSUE**: Uses same query as regular posts - no video-specific filtering
- Posts are displayed with a play button overlay but are just regular posts

**Template Location:** Lines 239-250 (All tab), Lines 287-296 (Videos tab)

**Empty State (Current):**
```heex
<div class="text-center py-20">
  <p class="text-[#515B70] font-haas_roman_55">No videos available yet.</p>
</div>
```

### 3. Shop Section

**Current State:**

- Uses `ShopTwoComponent` which loads ALL products, not hub-specific
- Products are selected from global `SiteSettings` or defaults to first 4
- **ISSUE**: Not filtering by hub - shows same products for all hubs

**Component Logic (shop_two_component.ex:17-38):**
```elixir
def update(assigns, socket) do
  settings_key = "shop_two_products_#{assigns.id}"
  all_products = Shop.list_active_products(preload: [:images, :variants])
  # Gets selected products from SiteSettings or defaults to first 4
  selected_products = get_selected_products(product_ids, all_products)
  # ...
end
```

**Template Location:** Lines 252-257 (All tab), Lines 298-315 (Shop tab)

### 4. Events Section

**Current State:**

- Uses `EventsCardsComponent` which loads ALL published events
- **ISSUE**: Not filtering by hub - shows same events for all hubs

**Component Logic (events_cards_component.ex:7-14):**
```elixir
def update(assigns, socket) do
  events = Events.list_published_events() |> Enum.take(3)
  # ...
end
```

**Template Location:** Lines 258-262 (All tab), Lines 318-325 (Events tab)

---

## Implementation Requirements

### 1. Videos Section Requirements

**Goal:** Display up to 3 video posts for this specific hub.

**Implementation Steps:**

1. **Add video post filtering** - Posts should have a way to be marked as videos (either by category or a boolean field)

2. **Query for video posts in mount:**
   ```elixir
   # Option A: Filter by category named "Videos"
   videos_posts = Blog.list_published_posts_by_hub(hub.id, category: "Videos", limit: 3)

   # Option B: Add is_video boolean to posts schema
   videos_posts = Blog.list_video_posts_by_hub(hub.id, limit: 3)
   ```

3. **Empty State:** If no videos exist, show nicely formatted empty state with hub name

**Data Requirements:**
- Need way to identify video posts (category or boolean field)
- Need hub-specific video query

### 2. Shop Section Requirements

**Goal:** Display ALL products for this specific hub using the exact shop page product card style.

**Product Card Style (from /shop page - shop_live/index.html.heex:162-231):**

```heex
<.link navigate={~p"/shop/#{product.slug}"} class="rounded-lg border border-gray-200 bg-white hover:shadow-lg transition-shadow cursor-pointer flex flex-col h-full">
  <!-- Image container with 3D flip animation -->
  <div class="img-wrapper w-full overflow-hidden rounded-t-lg group/card" style="padding-bottom: 100%; position: relative; perspective: 1000px;">
    <!-- Hub Logo Badge (if applicable) -->
    <%= if product.hub_logo do %>
      <div class="absolute top-3 left-3 z-10 bg-white rounded-full p-1.5 shadow-md">
        <img src={product.hub_logo} alt={product.hub_name || "Hub"} class="w-6 h-6 rounded-full object-cover" />
      </div>
    <% end %>

    <!-- 3D Flip animation container -->
    <div class="absolute inset-0 transition-transform duration-700 ease-in-out group-hover/card:[transform:rotateY(180deg)]" style="transform-style: preserve-3d;">
      <!-- Front face -->
      <div class="absolute inset-0 backface-hidden" style="backface-visibility: hidden;">
        <img alt={product.name} src={product.image} class="w-full h-full object-cover" loading="lazy" />
      </div>
      <!-- Back face -->
      <div class="absolute inset-0 backface-hidden" style="backface-visibility: hidden; transform: rotateY(180deg);">
        <img alt={product.name} src={Enum.at(product.images, 1) || product.image} class="w-full h-full object-cover" loading="lazy" />
      </div>
    </div>
  </div>

  <!-- Product info -->
  <div class="px-2 py-2 md:px-4 md:py-4 flex flex-col flex-1">
    <!-- Title - Centered -->
    <h4 class="text-sm md:text-lg font-haas_medium_65 text-gray-900 text-center mb-1 md:mb-2 flex-1 line-clamp-2">
      <%= product.name %>
    </h4>

    <!-- Price Display - Centered -->
    <div class="flex flex-col items-center mb-2 md:mb-4">
      <%= if product.total_max_discount > 0 do %>
        <!-- Original Price - Crossed out -->
        <span class="text-xs md:text-sm font-haas_roman_55 text-gray-400 line-through">
          $<%= :erlang.float_to_binary(product.price, decimals: 2) %>
        </span>
        <!-- Discounted Price -->
        <span class="text-lg md:text-2xl font-haas_medium_65 text-black">
          $<%= :erlang.float_to_binary(product.max_discounted_price, decimals: 2) %>
        </span>
        <span class="text-[10px] md:text-xs font-haas_roman_55 text-gray-500 mt-0.5">
          with BUX tokens
        </span>
      <% else %>
        <!-- Regular Price -->
        <span class="text-lg md:text-2xl font-haas_medium_65 text-gray-900">
          $<%= :erlang.float_to_binary(product.price, decimals: 2) %>
        </span>
      <% end %>
    </div>

    <!-- Buy Now Button -->
    <div class="w-full py-1.5 md:py-2.5 bg-black text-white font-haas_medium_65 rounded-full text-xs md:text-sm text-center">
      Buy Now
    </div>
  </div>
</.link>
```

**Grid Layout:**
```heex
<div class="grid grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3 md:gap-6 items-stretch">
  <!-- Product cards -->
</div>
```

**Implementation Steps:**

1. **Create new query for hub products:**
   ```elixir
   # In lib/blockster_v2/shop.ex
   def list_products_by_hub(hub_id, opts \\ []) do
     preload = Keyword.get(opts, :preload, [:images, :variants])

     from(p in Product,
       where: p.hub_id == ^hub_id and p.status == :active,
       order_by: [desc: p.inserted_at],
       preload: ^preload
     )
     |> Repo.all()
   end
   ```

2. **Load hub products in mount or on tab switch:**
   ```elixir
   # In show.ex mount/3
   hub_products = Shop.list_products_by_hub(hub.id, preload: [:images, :variants, :hub])

   socket
   |> assign(:hub_products, hub_products)
   ```

3. **Create HubShopComponent or modify ShopTwoComponent** to accept hub products

4. **Empty State:** If no products, show styled empty state

### 3. Events Section Requirements

**Goal:** For ALL hubs, display "No events listed" with nicely formatted empty state.

**Implementation:** Since we're not filtering by hub and just showing empty state for all hubs:

```heex
<section class="events-section md:pt-16 pt-8 md:pb-16 pb-8">
  <div class="container mx-auto">
    <div class="mb-6">
      <h2 class="text-3xl font-haas_medium_65 text-[#141414]">Events</h2>
    </div>
    <!-- Empty State Design -->
    <div class="flex flex-col items-center justify-center py-16 px-4">
      <img
        src="/images/empty-events.svg"
        alt="No events"
        class="w-48 h-48 mb-6 opacity-60"
      />
      <h3 class="text-xl font-haas_medium_65 text-gray-600 mb-2">No events listed</h3>
      <p class="text-gray-400 text-center max-w-md">
        There are currently no events scheduled for this community. Check back later!
      </p>
    </div>
  </div>
</section>
```

---

## Empty State Design Specifications

### Consistent Empty State Pattern

All empty states should follow this pattern:

```heex
<div class="flex flex-col items-center justify-center py-16 px-4 bg-white rounded-2xl border border-[#E7E8F1]">
  <!-- Illustration/Icon -->
  <div class="w-32 h-32 mb-6 rounded-full bg-gradient-to-br from-[#8AE388] to-[#BAF55F] flex items-center justify-center opacity-60">
    <svg><!-- Relevant icon --></svg>
  </div>

  <!-- Title with hub name -->
  <h3 class="text-xl font-haas_medium_65 text-gray-600 mb-2">
    No {content_type} for {hub.name}
  </h3>

  <!-- Description -->
  <p class="text-gray-400 text-center max-w-md font-haas_roman_55">
    {helpful_message}
  </p>
</div>
```

### Videos Empty State

```heex
<div class="flex flex-col items-center justify-center py-16 px-4 bg-white rounded-2xl border border-[#E7E8F1]">
  <div class="w-32 h-32 mb-6 rounded-full bg-gradient-to-br from-[#8AE388] to-[#BAF55F] flex items-center justify-center opacity-60">
    <!-- Play icon -->
    <svg xmlns="http://www.w3.org/2000/svg" class="w-16 h-16 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z" />
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
  </div>
  <h3 class="text-xl font-haas_medium_65 text-gray-600 mb-2">
    No <%= @hub.name %> Videos
  </h3>
  <p class="text-gray-400 text-center max-w-md font-haas_roman_55">
    Video content for this community is coming soon. Stay tuned!
  </p>
</div>
```

### Shop Empty State

```heex
<div class="flex flex-col items-center justify-center py-16 px-4 bg-white rounded-2xl border border-[#E7E8F1]">
  <div class="w-32 h-32 mb-6 rounded-full bg-gradient-to-br from-[#8AE388] to-[#BAF55F] flex items-center justify-center opacity-60">
    <!-- Shopping bag icon -->
    <svg xmlns="http://www.w3.org/2000/svg" class="w-16 h-16 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z" />
    </svg>
  </div>
  <h3 class="text-xl font-haas_medium_65 text-gray-600 mb-2">
    No <%= @hub.name %> Products
  </h3>
  <p class="text-gray-400 text-center max-w-md font-haas_roman_55">
    This community doesn't have any products in the shop yet.
  </p>
  <.link navigate={~p"/shop"} class="mt-4 px-6 py-2 bg-black text-white rounded-full font-haas_medium_65 text-sm hover:bg-gray-800 transition-colors cursor-pointer">
    Browse All Products
  </.link>
</div>
```

### Events Empty State

```heex
<div class="flex flex-col items-center justify-center py-16 px-4 bg-white rounded-2xl border border-[#E7E8F1]">
  <div class="w-32 h-32 mb-6 rounded-full bg-gradient-to-br from-[#8AE388] to-[#BAF55F] flex items-center justify-center opacity-60">
    <!-- Calendar icon -->
    <svg xmlns="http://www.w3.org/2000/svg" class="w-16 h-16 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
    </svg>
  </div>
  <h3 class="text-xl font-haas_medium_65 text-gray-600 mb-2">
    No Events Listed
  </h3>
  <p class="text-gray-400 text-center max-w-md font-haas_roman_55">
    There are currently no events scheduled for this community. Check back later!
  </p>
</div>
```

---

## Code Changes Required

### Summary of Changes

| Area | Change Type | Description |
|------|-------------|-------------|
| **show.ex** | Modify | Load hub-specific products and video posts |
| **show.html.heex** | Modify | Update All tab sections, add empty states |
| **Shop module** | Add | `list_products_by_hub/2` function |
| **Blog module** | Add/Modify | Video post filtering query |
| **New Component** | Create | `HubShopSectionComponent` for hub products with shop page styling |
| **VideosComponent** | Modify | Update empty state design |
| **EventsCardsComponent** | Modify | Pass hub, update empty state |

### 1. Add Shop Query (lib/blockster_v2/shop.ex)

```elixir
@doc """
Lists all active products for a specific hub.
"""
def list_products_by_hub(hub_id, opts \\ []) do
  preload = Keyword.get(opts, :preload, [:images, :variants])

  from(p in Product,
    where: p.hub_id == ^hub_id and p.status == :active,
    order_by: [desc: p.inserted_at],
    preload: ^preload
  )
  |> Repo.all()
  |> Enum.map(&prepare_product_for_display/1)
end

defp prepare_product_for_display(product) do
  first_variant = List.first(product.variants)
  price = if first_variant, do: Decimal.to_float(first_variant.price || Decimal.new(0)), else: 0.0

  %{
    id: product.id,
    name: product.title,
    slug: product.handle,
    image: get_first_image(product),
    images: Enum.map(product.images, & &1.src),
    price: price,
    total_max_discount: product.bux_max_discount || 0,
    max_discounted_price: calculate_discounted_price(price, product.bux_max_discount || 0)
  }
end
```

### 2. Modify show.ex mount

```elixir
def mount(%{"slug" => slug}, _session, socket) do
  case Blog.get_hub_by_slug_with_associations(slug) do
    nil -> # ... error handling
    hub ->
      posts_three = Blog.list_published_posts_by_hub(hub.id, limit: 5) |> Blog.with_bux_balances()
      videos_posts = Blog.list_video_posts_by_hub(hub.id, limit: 3) |> Blog.with_bux_balances()
      hub_products = Shop.list_products_by_hub(hub.id, preload: [:images, :variants])

      {:ok,
       socket
       |> assign(:posts_three, posts_three)
       |> assign(:hub, hub)
       |> assign(:videos_posts, videos_posts)
       |> assign(:hub_products, hub_products)
       # ... rest of assigns
      }
  end
end
```

### 3. Update show.html.heex All Tab

Replace the current sections (lines 220-263) with hub-specific implementations:

```heex
<%= if @show_all do %>
  <!-- Hub Posts -->
  <div>
    <.live_component
      module={BlocksterV2Web.PostLive.PostsThreeComponent}
      id="hub-posts-three"
      posts={@posts_three}
      content={@hub.name}
      type="hub-posts"
      show_read_more={false}
      hide_title={true}
    />
  </div>
  <div class="container mx-auto flex justify-end relative z-10">
    <button phx-click="switch_tab" phx-value-tab="news" class="text-sm font-haas_medium_65 text-gray-500 hover:underline cursor-pointer">
      Read more stories from <%= @hub.name %> &gt;
    </button>
  </div>

  <!-- Hub Videos Section -->
  <div class="mt-8">
    <div class="container mx-auto">
      <h2 class="text-3xl font-haas_medium_65 text-[#141414] mb-6">Videos</h2>
      <%= if @videos_posts == [] do %>
        <!-- Videos Empty State -->
        <div class="flex flex-col items-center justify-center py-16 px-4 bg-white rounded-2xl border border-[#E7E8F1]">
          <div class="w-32 h-32 mb-6 rounded-full bg-gradient-to-br from-[#8AE388] to-[#BAF55F] flex items-center justify-center opacity-60">
            <svg xmlns="http://www.w3.org/2000/svg" class="w-16 h-16 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z" />
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
            </svg>
          </div>
          <h3 class="text-xl font-haas_medium_65 text-gray-600 mb-2">No <%= @hub.name %> Videos</h3>
          <p class="text-gray-400 text-center max-w-md font-haas_roman_55">
            Video content for this community is coming soon. Stay tuned!
          </p>
        </div>
      <% else %>
        <.live_component
          module={BlocksterV2Web.PostLive.VideosComponent}
          id="hub-videos-all"
          posts={@videos_posts}
          content={@hub.name}
          type="hub-videos"
          show_header={false}
        />
      <% end %>
    </div>
  </div>

  <!-- Hub Shop Section -->
  <div class="md:pt-16 pt-8 md:pb-4 pb-2">
    <div class="container mx-auto">
      <h2 class="text-3xl font-haas_medium_65 text-[#141414] mb-6">Shop</h2>
      <%= if @hub_products == [] do %>
        <!-- Shop Empty State -->
        <div class="flex flex-col items-center justify-center py-16 px-4 bg-white rounded-2xl border border-[#E7E8F1]">
          <div class="w-32 h-32 mb-6 rounded-full bg-gradient-to-br from-[#8AE388] to-[#BAF55F] flex items-center justify-center opacity-60">
            <svg xmlns="http://www.w3.org/2000/svg" class="w-16 h-16 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M16 11V7a4 4 0 00-8 0v4M5 9h14l1 12H4L5 9z" />
            </svg>
          </div>
          <h3 class="text-xl font-haas_medium_65 text-gray-600 mb-2">No <%= @hub.name %> Products</h3>
          <p class="text-gray-400 text-center max-w-md font-haas_roman_55">
            This community doesn't have any products in the shop yet.
          </p>
          <.link navigate={~p"/shop"} class="mt-4 px-6 py-2 bg-black text-white rounded-full font-haas_medium_65 text-sm hover:bg-gray-800 transition-colors cursor-pointer">
            Browse All Products
          </.link>
        </div>
      <% else %>
        <!-- Hub Products Grid (same styling as /shop page) -->
        <div class="grid grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3 md:gap-6 items-stretch">
          <%= for product <- @hub_products do %>
            <.link navigate={~p"/shop/#{product.slug}"} class="rounded-lg border border-gray-200 bg-white hover:shadow-lg transition-shadow cursor-pointer flex flex-col h-full">
              <div class="img-wrapper w-full overflow-hidden rounded-t-lg group/card" style="padding-bottom: 100%; position: relative; perspective: 1000px;">
                <div class="absolute inset-0 transition-transform duration-700 ease-in-out group-hover/card:[transform:rotateY(180deg)]" style="transform-style: preserve-3d;">
                  <div class="absolute inset-0 backface-hidden" style="backface-visibility: hidden;">
                    <img alt={product.name} src={product.image} class="w-full h-full object-cover" loading="lazy" />
                  </div>
                  <div class="absolute inset-0 backface-hidden" style="backface-visibility: hidden; transform: rotateY(180deg);">
                    <img alt={product.name} src={Enum.at(product.images, 1) || product.image} class="w-full h-full object-cover" loading="lazy" />
                  </div>
                </div>
              </div>
              <div class="px-2 py-2 md:px-4 md:py-4 flex flex-col flex-1">
                <h4 class="text-sm md:text-lg font-haas_medium_65 text-gray-900 text-center mb-1 md:mb-2 flex-1 line-clamp-2">
                  <%= product.name %>
                </h4>
                <div class="flex flex-col items-center mb-2 md:mb-4">
                  <%= if product.total_max_discount > 0 do %>
                    <span class="text-xs md:text-sm font-haas_roman_55 text-gray-400 line-through">
                      $<%= :erlang.float_to_binary(product.price, decimals: 2) %>
                    </span>
                    <span class="text-lg md:text-2xl font-haas_medium_65 text-black">
                      $<%= :erlang.float_to_binary(product.max_discounted_price, decimals: 2) %>
                    </span>
                    <span class="text-[10px] md:text-xs font-haas_roman_55 text-gray-500 mt-0.5">
                      with BUX tokens
                    </span>
                  <% else %>
                    <span class="text-lg md:text-2xl font-haas_medium_65 text-gray-900">
                      $<%= :erlang.float_to_binary(product.price, decimals: 2) %>
                    </span>
                  <% end %>
                </div>
                <div class="w-full py-1.5 md:py-2.5 bg-black text-white font-haas_medium_65 rounded-full text-xs md:text-sm text-center">
                  Buy Now
                </div>
              </div>
            </.link>
          <% end %>
        </div>
      <% end %>
    </div>
  </div>

  <!-- Hub Events Section -->
  <div class="md:pt-16 pt-8 md:pb-16 pb-8">
    <div class="container mx-auto">
      <h2 class="text-3xl font-haas_medium_65 text-[#141414] mb-6">Events</h2>
      <!-- Events Empty State (always shown per requirements) -->
      <div class="flex flex-col items-center justify-center py-16 px-4 bg-white rounded-2xl border border-[#E7E8F1]">
        <div class="w-32 h-32 mb-6 rounded-full bg-gradient-to-br from-[#8AE388] to-[#BAF55F] flex items-center justify-center opacity-60">
          <svg xmlns="http://www.w3.org/2000/svg" class="w-16 h-16 text-white" fill="none" viewBox="0 0 24 24" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8 7V3m8 4V3m-9 8h10M5 21h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v12a2 2 0 002 2z" />
          </svg>
        </div>
        <h3 class="text-xl font-haas_medium_65 text-gray-600 mb-2">No Events Listed</h3>
        <p class="text-gray-400 text-center max-w-md font-haas_roman_55">
          There are currently no events scheduled for this community. Check back later!
        </p>
      </div>
    </div>
  </div>
<% end %>
```

### 4. Update Individual Tab Contents

Each tab (Videos, Shop, Events) when clicked should display the same content as its section in the All tab:

**Videos Tab:** Same content as Videos section in All tab
**Shop Tab:** Same grid of hub products with same styling
**Events Tab:** Same empty state as Events section in All tab

---

## Testing Checklist

- [ ] Hub with videos: Videos section shows up to 3 video posts
- [ ] Hub without videos: Videos empty state displays with hub name
- [ ] Hub with products: Shop section shows all hub products in correct grid
- [ ] Hub without products: Shop empty state displays with hub name and "Browse All" link
- [ ] All hubs: Events section shows "No Events Listed" empty state
- [ ] All tab: Shows all sections in correct order
- [ ] Videos tab: Shows same content as Videos section in All tab
- [ ] Shop tab: Shows same content as Shop section in All tab
- [ ] Events tab: Shows same content as Events section in All tab
- [ ] Mobile: All sections and tabs work correctly on mobile
- [ ] Product cards: 3D flip animation works on hover
- [ ] Links: All product links navigate correctly to product pages

---

## Implementation Todo Checklist

### Phase 1: Backend - Data Layer ✅ COMPLETED (Feb 8, 2026)

#### 1.1 Shop Module Updates ✅
- [x] **Add `list_products_by_hub/2` function** to `lib/blockster_v2/shop.ex` (lines 37-56)
  - [x] Create Ecto query filtering by `hub_id` and `status == "active"`
  - [x] Order by `inserted_at` descending
  - [x] Preload `:images` and `:variants` associations with position ordering
  - [x] Return all products (no limit)
  - [x] Maps results through `prepare_product_for_display/1`

- [x] **Add `prepare_product_for_display/1` helper** to `lib/blockster_v2/shop.ex` (lines 62-91)
  - [x] Extract first variant price (returns 0.0 if no variant)
  - [x] Build display map with: `id`, `name`, `slug`, `image`, `images`, `price`, `total_max_discount`, `max_discounted_price`
  - [x] Calculates `total_max_discount` as max of `bux_max_discount` and `hub_token_max_discount`
  - [x] Calculates `max_discounted_price` as `price * (1 - total_max_discount / 100)`

- [x] **Add `get_first_image/1` helper** (private) to `lib/blockster_v2/shop.ex` (lines 93-98)
  - [x] Return first image src from product.images
  - [x] Fallback to placeholder: `https://via.placeholder.com/300x300?text=No+Image`

#### 1.2 Blog Module Updates (Video Posts) ✅

**Video Post Detection (Already Implemented):**
Posts are identified as videos using the `video_id` field:
- When admin enters a YouTube URL in the post form's `video_url` field
- The `Post.changeset/2` function calls `extract_video_id/1` to parse the YouTube ID
- The extracted ID is stored in `post.video_id` field
- Templates check `if post.video_id do` to show `<.video_play_icon />` overlay

**Schema Fields** (in `lib/blockster_v2/blog/post.ex`):
```elixir
field :video_url, :string      # YouTube URL entered by admin
field :video_id, :string       # Extracted YouTube video ID (e.g., "dQw4w9WgXcQ")
field :video_duration, :integer
field :video_bux_per_minute, :decimal
field :video_max_reward, :decimal
```

- [x] **Add `list_video_posts_by_hub/2` function** to `lib/blockster_v2/blog.ex` (lines 213-263)
  - [x] Create Ecto query filtering by `hub_id` and `video_id IS NOT NULL`
  - [x] Filter for published posts only (`published_at IS NOT NULL`)
  - [x] Order by `published_at` descending
  - [x] Accept `limit` option (default: 3)
  - [x] Uses same tag-matching logic as `list_published_posts_by_hub` (hub_id OR hub.tag_name match)
  - [x] Preloads: `[:author, :category, :hub, tags: ...]`
  - [x] Calls `populate_author_names/1` for author display

**Actual Implementation** (supports hub tag matching like other hub queries):
```elixir
def list_video_posts_by_hub(hub_id, opts \\ []) do
  limit = Keyword.get(opts, :limit, 3)
  hub = get_hub(hub_id)

  query = if hub && hub.tag_name do
    # Find video posts that either have this hub_id OR have a tag matching the hub's tag_name
    post_ids_query =
      from(p in Post,
        left_join: pt in "post_tags", on: pt.post_id == p.id,
        left_join: t in Tag, on: t.id == pt.tag_id,
        where: not is_nil(p.published_at),
        where: not is_nil(p.video_id),
        where: p.hub_id == ^hub_id or t.name == ^hub.tag_name,
        select: p.id,
        distinct: true
      )

    from(p in Post,
      where: p.id in subquery(post_ids_query),
      order_by: [desc: p.published_at],
      limit: ^limit,
      preload: [:author, :category, :hub, tags: ^from(t in Tag, order_by: t.name)]
    )
  else
    # Fallback to just hub_id if hub doesn't have a tag_name
    from(p in Post,
      where: not is_nil(p.published_at),
      where: not is_nil(p.video_id),
      where: p.hub_id == ^hub_id,
      order_by: [desc: p.published_at],
      limit: ^limit,
      preload: [:author, :category, :hub, tags: ^from(t in Tag, order_by: t.name)]
    )
  end

  query
  |> Repo.all()
  |> populate_author_names()
end
```

---

### Phase 2: LiveView - Data Loading ✅ COMPLETED (Feb 8, 2026)

#### 2.1 Update show.ex Mount ✅
- [x] **Add Shop alias** at top of `lib/blockster_v2_web/live/hub_live/show.ex` (line 7)
  ```elixir
  alias BlocksterV2.Shop
  ```

- [x] **Load hub products in mount/3** (lines 27-28)
  - [x] Add: `hub_products = Shop.list_products_by_hub(hub.id)`
  - [x] Add: `|> assign(:hub_products, hub_products)` to socket assigns
  - [x] Set `:shop_loaded` to `true` (products loaded eagerly for All tab)

- [x] **Update videos_posts loading** (line 24)
  - [x] Replace: `Blog.list_published_posts_by_hub(hub.id, limit: 3)`
  - [x] With: `Blog.list_video_posts_by_hub(hub.id, limit: 3)`

#### 2.2 Update Tab Switch Handler ✅
- [x] **Shop tab uses hub_products**
  - [x] `@hub_products` is loaded in mount and available for all tabs
  - [x] Removed lazy loading for shop tab (products loaded eagerly)

- [x] **Videos tab uses correct video posts** (lines 93-100)
  - [x] Updated lazy loading to use `Blog.list_video_posts_by_hub` instead of `list_published_posts_by_hub`
  - [x] `@videos_posts` now contains only posts with `video_id IS NOT NULL`

**Key Changes in show.ex:**
1. Added `alias BlocksterV2.Shop` import
2. Mount now loads `hub_products` and sets `shop_loaded: true`
3. Mount uses `list_video_posts_by_hub` for videos
4. Tab switch handler uses `list_video_posts_by_hub` for lazy loading
5. Removed shop lazy loading (no longer needed)

---

### Phase 3: Template - All Tab Updates ✅ COMPLETED (Feb 8, 2026)

#### 3.1 Videos Section in All Tab ✅
- [x] **Update Videos section** (lines 239-270 in `show.html.heex`)
  - [x] Add container div with title "Videos"
  - [x] Add conditional: `<%= if @videos_posts == [] do %>`
  - [x] Add empty state with:
    - [x] Gradient circle with play icon
    - [x] "No {hub.name} Videos" title
    - [x] Description text
  - [x] Keep VideosComponent for non-empty case with `show_header={false}`

#### 3.2 Shop Section in All Tab ✅
- [x] **Replace ShopTwoComponent** (lines 272-345 in `show.html.heex`)
  - [x] Remove `<.live_component module={ShopTwoComponent} ... />`
  - [x] Add container div with title "Shop"
  - [x] Add conditional: `<%= if @hub_products == [] do %>`
  - [x] Add empty state with:
    - [x] Gradient circle with shopping bag icon
    - [x] "No {hub.name} Products" title
    - [x] Description text
    - [x] "Browse All Products" link to `/shop`

- [x] **Add product grid for non-empty case**
  - [x] Add grid container: `grid grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-3 md:gap-6`
  - [x] Add product card for each product with:
    - [x] 3D flip image container with perspective
    - [x] Front/back images with rotateY transform
    - [x] Centered title with `line-clamp-2`
    - [x] Price display (with/without discount)
    - [x] "with BUX tokens" text for discounted items
    - [x] "Buy Now" button

#### 3.3 Events Section in All Tab ✅
- [x] **Replace EventsCardsComponent** (lines 347-371 in `show.html.heex`)
  - [x] Remove `<.live_component module={EventsCardsComponent} ... />`
  - [x] Add container div with title "Events"
  - [x] Add empty state (always shown) with:
    - [x] Gradient circle with calendar icon
    - [x] "No Events Listed" title
    - [x] Description text

---

### Phase 4: Template - Individual Tab Updates ✅ COMPLETED (Feb 8, 2026)

#### 4.1 Videos Tab Content ✅
- [x] **Update Videos tab section** (lines 396-428 in `show.html.heex`)
  - [x] Add same conditional and empty state as All tab Videos section
  - [x] Use VideosComponent for non-empty with `show_header={false}`
  - [x] Added hub name in page title: "{hub.name} Videos"

#### 4.2 Shop Tab Content ✅
- [x] **Update Shop tab section** (lines 430-511 in `show.html.heex`)
  - [x] Remove ShopOneComponent, ShopTwoComponent, ShopFourComponent
  - [x] Add same conditional and empty state as All tab Shop section
  - [x] Add same product grid as All tab
  - [x] Added hub name in page title: "{hub.name} Shop"

#### 4.3 Events Tab Content ✅
- [x] **Update Events tab section** (lines 513-535 in `show.html.heex`)
  - [x] Remove EventsComponent
  - [x] Add same empty state as All tab Events section
  - [x] Added hub name in page title: "{hub.name} Events"

---

### Phase 5: Styling & Polish ✅ COMPLETED (Feb 8, 2026)

#### 5.1 Empty State Consistency ✅
- [x] **All empty states use consistent styling**
  - [x] Same padding: `py-16 px-4`
  - [x] Same background: `bg-white rounded-2xl border border-[#E7E8F1]`
  - [x] Same gradient circle: `w-32 h-32 rounded-full bg-gradient-to-br from-[#8AE388] to-[#BAF55F]`
  - [x] Same icon size: `w-16 h-16 text-white`
  - [x] Same title style: `text-xl font-haas_medium_65 text-gray-600`
  - [x] Same description style: `text-gray-400 text-center max-w-md font-haas_roman_55`

#### 5.2 Product Card Styling ✅
- [x] **Product cards match /shop page exactly**
  - [x] Same border: `border border-gray-200`
  - [x] Same hover effect: `hover:shadow-lg transition-shadow`
  - [x] Same image aspect ratio: `padding-bottom: 100%`
  - [x] Same 3D flip animation timing: `duration-700 ease-in-out`
  - [x] Same font sizes and weights
  - [x] Same button styling

#### 5.3 Mobile Responsiveness ✅
- [x] **Mobile viewport ready**
  - [x] Grid collapses to 2 columns on mobile (`grid-cols-2 lg:grid-cols-3 xl:grid-cols-4`)
  - [x] Empty states are centered and readable
  - [x] Padding adjusts correctly (`md:pt-16 pt-8` etc.)
  - [x] Mobile tab dropdown already working (no changes needed)

---

### Phase 6: Testing

#### 6.1 Manual Testing
- [ ] **Test hub WITH videos**
  - [ ] Verify up to 3 videos display in Videos section
  - [ ] Verify Videos tab shows same content
  - [ ] Verify play button overlay appears on video cards

- [ ] **Test hub WITHOUT videos**
  - [ ] Verify empty state shows in Videos section
  - [ ] Verify hub name appears in empty state title
  - [ ] Verify Videos tab shows same empty state

- [ ] **Test hub WITH products**
  - [ ] Verify all hub products display in Shop section
  - [ ] Verify product cards have correct styling
  - [ ] Verify 3D flip animation works on hover
  - [ ] Verify product links navigate correctly
  - [ ] Verify Shop tab shows same products

- [ ] **Test hub WITHOUT products**
  - [ ] Verify empty state shows in Shop section
  - [ ] Verify hub name appears in empty state title
  - [ ] Verify "Browse All Products" link works
  - [ ] Verify Shop tab shows same empty state

- [ ] **Test Events section**
  - [ ] Verify empty state shows for all hubs
  - [ ] Verify Events tab shows same empty state

#### 6.2 Cross-Browser Testing
- [ ] Test in Chrome
- [ ] Test in Firefox
- [ ] Test in Safari
- [ ] Test on mobile (iOS Safari, Chrome Android)

---

### Phase 7: Cleanup

#### 7.1 Remove Unused Code
- [ ] **Evaluate if ShopOneComponent, ShopFourComponent still needed**
  - [ ] If not used elsewhere, consider removing

- [ ] **Evaluate if EventsComponent, EventsCardsComponent still needed**
  - [ ] If not used elsewhere, consider removing

#### 7.2 Documentation
- [ ] **Update CLAUDE.md** with any new patterns or learnings
- [ ] **Add inline comments** to complex template sections
- [ ] **Document the video post identification strategy** chosen

---

## File Change Summary

| File | Action | Priority |
|------|--------|----------|
| `lib/blockster_v2/shop.ex` | Add `list_products_by_hub/2` | High |
| `lib/blockster_v2/blog.ex` | Add `list_video_posts_by_hub/2` | High |
| `lib/blockster_v2_web/live/hub_live/show.ex` | Update mount, add imports | High |
| `lib/blockster_v2_web/live/hub_live/show.html.heex` | Major template updates | High |
| `priv/repo/migrations/*` | Optional: add is_video field | Medium |

---

## Estimated Effort

| Phase | Complexity | Estimated Time |
|-------|------------|----------------|
| Phase 1: Backend | Medium | 1-2 hours |
| Phase 2: LiveView | Low | 30 mins |
| Phase 3: All Tab Template | High | 2-3 hours |
| Phase 4: Individual Tabs | Medium | 1 hour |
| Phase 5: Styling | Low | 30 mins |
| Phase 6: Testing | Medium | 1-2 hours |
| Phase 7: Cleanup | Low | 30 mins |
| **Total** | | **6-9 hours**
