# Post Display Redesign: Latest/Popular Tabs + Trading Category Bug Fix

## 1. Current System Analysis

### How Posts Are Currently Sorted

All post listing pages (homepage, category, tag) sort posts by **BUX pool balance descending**, then by `published_at` descending as tiebreaker. This means posts with the most remaining BUX in their reward pool appear first.

**The sorting pipeline:**

1. **`SortedPostsCache`** (`lib/blockster_v2/sorted_posts_cache.ex`) - A global GenServer singleton that maintains an in-memory sorted list of all published posts
2. On startup, it loads all published posts from PostgreSQL and all pool balances from Mnesia's `post_bux_points` table
3. Each entry is a tuple: `{post_id, balance, published_unix, category_id, tag_ids}`
4. Sorted by `{-balance, -published_at}` (highest balance first, newest first for ties)
5. All queries use this cache for O(1) pagination

**Key functions in `Blog` module** (`lib/blockster_v2/blog.ex`):
- `list_published_posts_by_pool/1` (line 322) - Homepage: fetches page from SortedPostsCache, loads posts from DB, attaches `bux_balance`
- `list_published_posts_by_category_pool/2` (line 371) - Category pages: filters cache by `category_id`, same sorting
- `list_published_posts_by_tag_pool/2` - Tag pages: filters cache by `tag_id`, same sorting

### Pages Affected

| Page | LiveView Module | File |
|------|----------------|------|
| Homepage `/` | `PostLive.Index` | `lib/blockster_v2_web/live/post_live/index.ex` |
| Category `/category/:category` | `PostLive.Category` | `lib/blockster_v2_web/live/post_live/category.ex` |
| Tag `/tag/:tag` | `PostLive.Tag` | `lib/blockster_v2_web/live/post_live/tag.ex` |

### Post Display Components

Posts are displayed in a cycling layout pattern using 4 LiveComponents:
- `PostsThreeComponent` (5 posts)
- `PostsFourComponent` (3 posts)
- `PostsFiveComponent` (6 posts)
- `PostsSixComponent` (5 posts)
- Total per cycle: **19 posts**

Pagination uses **infinite scroll** via the `InfiniteScroll` JS hook with `load-more` event.

### Current BUX Data Structure

**Mnesia table: `post_bux_points`** (12 fields):
```
{:post_bux_points, post_id, reward, read_time, bux_balance, bux_deposited, total_distributed, extra_field2, extra_field3, extra_field4, created_at, updated_at}
```

| Index | Field | Description |
|-------|-------|-------------|
| 1 | post_id | Primary key |
| 4 | bux_balance | **Current remaining pool balance** (can be negative for guaranteed earnings) |
| 5 | bux_deposited | Total BUX deposited into pool (lifetime) |
| 6 | total_distributed | **Total BUX paid out to readers** (lifetime) |

**Key insight:** `total_distributed` (index 6) already tracks total BUX paid out! This is exactly what the "Popular" tab needs. It's incremented in `PostBuxPoolWriter` (`lib/blockster_v2/post_bux_pool_writer.ex`) every time BUX is deducted from a pool (lines 182, 196, 251).

### Current UI

- **No tabs exist** - posts are just listed in BUX balance order
- The homepage shows "Latest Posts" as page title (line 61 of index.ex) but the actual sort is by BUX balance, not date
- Category pages show a breadcrumb + category name header
- Tag pages show a tag name header

---

## 2. Category & Data Bugs

### 2.1 Trading Category Nav Link (Confirmed Broken)

**Production DB query confirmed** the actual categories. The nav link uses slug `crypto-trading` but the DB slug is `trading`.

**Production categories:**
```
{50, "AI", "ai"}, {2, "Analysis", "analysis"}, {8, "Announcements", "announcements"},
{48, " Art", "art"}, {1, "Blockchain", "blockchain"}, {13, "Business", "business"},
{7, "DeFi", "defi"}, {4, "Events", "events"}, {9, "Gaming", "gaming"},
{3, "Investment", "investment"}, {47, " Lifestyle", "lifestyle"}, {49, " NFT", "nft"},
{6, "People", "people"}, {51, "RWA", "rwa"}, {10, "Tech", "tech"},
{5, "Trading", "trading"}
```

| Nav Link | Nav Slug | DB Slug | Status |
|----------|----------|---------|--------|
| Trading | `crypto-trading` | `trading` | **BROKEN** |
| All others | match | match | OK |

**Fix:** Change nav link from `crypto-trading` to `trading` in `layouts.ex` line 350.

### 2.2 Content Automation Category Mapping Mismatches

The `@category_map` in `content_publisher.ex` maps internal topic names to `{display_name, slug}` pairs.
When an auto-generated post is published, `resolve_category/1` looks up the slug in the DB.
If the slug doesn't exist, it **creates a new category on the fly**.

Content automation hasn't been deployed to production yet, so none of these duplicates exist yet.
But once deployed, 3 mappings will create phantom duplicate categories instead of using existing ones:

| Automation Topic | Currently Maps To | Existing DB Category | Problem |
|---|---|---|---|
| `trading` | "Markets" / `markets` | "Trading" / `trading` | Slug `markets` won't find `trading`. Creates duplicate. Trading nav link won't show these posts. |
| `nft` | "NFTs" / `nfts` | "NFT" / `nft` | Slug `nfts` won't find `nft`. Creates duplicate. |
| `ai_crypto` | "AI & Crypto" / `ai-crypto` | "AI" / `ai` | Slug `ai-crypto` won't find `ai`. Creates duplicate. AI nav link won't show these posts. |

The other 17 mappings are fine - they either match existing DB slugs exactly (defi, rwa, gaming, investment)
or will create new categories that don't conflict (regulation, bitcoin, ethereum, etc.).

**Fix in `content_publisher.ex`:**
```elixir
"trading" => {"Trading", "trading"},      # was {"Markets", "markets"}
"nft" => {"NFT", "nft"},                  # was {"NFTs", "nfts"}
"ai_crypto" => {"AI", "ai"},              # was {"AI & Crypto", "ai-crypto"}
```

**Note on category growth:** The automation system defines 20 topics. Only 8 of those have nav links.
Once deployed, ~12 new categories will be auto-created (regulation, bitcoin, ethereum, altcoins, etc.)
that are not reachable from the top nav. These posts will still appear on the homepage and in search,
but won't have dedicated nav links. This is fine for now but worth revisiting if those categories
accumulate significant content.

### 2.3 Dirty Category Names (Leading Spaces)

Three categories have leading spaces in their names:
- `" Art"` (id 48) → should be `"Art"`
- `" Lifestyle"` (id 47) → should be `"Lifestyle"`
- `" NFT"` (id 49) → should be `"NFT"`

**Fix:** Run a one-time DB update via `flyctl ssh console` to trim the names:
```elixir
Repo.update_all(from(c in Category, where: c.id in [47, 48, 49]),
  set: [name: fragment("TRIM(name)")])
```

### 2.4 SortedPostsCache Tag Update Bug

The user reports posts appearing/disappearing when changing tags or categories. This is because:

1. **SortedPostsCache stores `category_id` and `tag_ids`** - When a post's tags are changed, the cache entry is NOT updated
2. The `update_post/3` function (line 106) only updates `published_at` and `category_id`, **not tag_ids**
3. There is no function to update tag_ids in the cache when tags are changed on an existing post
4. The periodic reload (every 5 minutes) eventually fixes it, which is why "switching categories/tags fixes it"

**Fix:** Add tag update support to `SortedPostsCache` and call it when tags are modified in the admin/editor.

---

## 3. Implementation Plan

### Phase 1: Fix Category Bugs

#### Step 1.1: Fix Trading Nav Link
**File:** `lib/blockster_v2_web/components/layouts.ex` (line 350)
Change `crypto-trading` to `trading` in both the navigate path and data-category-path.

#### Step 1.2: Fix Content Automation Category Mappings (3 mismatches)
**File:** `lib/blockster_v2/content_automation/content_publisher.ex`
```elixir
"trading" => {"Trading", "trading"},      # line 265: was {"Markets", "markets"}
"nft" => {"NFT", "nft"},                  # line 274: was {"NFTs", "nfts"}
"ai_crypto" => {"AI", "ai"},              # line 275: was {"AI & Crypto", "ai-crypto"}
```

#### Step 1.3: Clean Up Dirty Category Names
Run one-time fix on production DB to trim leading spaces from Art, Lifestyle, NFT category names.

#### Step 1.4: Fix SortedPostsCache Tag Updates
**File:** `lib/blockster_v2/sorted_posts_cache.ex`

Add new function:
```elixir
def update_post_tags(post_id, tag_ids) do
  GenServer.cast({:global, __MODULE__}, {:update_post_tags, post_id, tag_ids})
end
```

Add handler:
```elixir
def handle_cast({:update_post_tags, post_id, tag_ids}, state) do
  sorted_posts = state.sorted_posts
    |> Enum.map(fn {pid, bal, pub_at, cat_id, _tag_ids} = entry ->
      if pid == post_id, do: {pid, bal, pub_at, cat_id, tag_ids}, else: entry
    end)
  {:noreply, %{state | sorted_posts: sorted_posts}}
end
```

Also update `update_post/3` to accept tag_ids:
```elixir
def update_post(post_id, published_at, category_id, tag_ids \\ nil)
```

**File:** Wherever posts are edited (form submission handler) - call `SortedPostsCache.update_post_tags/2` after saving.

---

### Phase 2: Add Latest/Popular Tabs

#### Step 2.1: Extend SortedPostsCache with Date-Sorted View

**File:** `lib/blockster_v2/sorted_posts_cache.ex`

The cache currently only maintains a balance-sorted list. We need **two sorted views**:
1. **By date** (`published_at` DESC) - for "Latest" tab (default)
2. **By total distributed** (`total_distributed` DESC, then `published_at` DESC) - for "Popular" tab

**Option A (Recommended): Maintain two sorted lists in state**

Change state from:
```elixir
%{sorted_posts: [...], mnesia_ready: false, ...}
```
To:
```elixir
%{
  sorted_by_balance: [...],   # Legacy: {post_id, balance, published_unix, category_id, tag_ids}
  sorted_by_date: [...],       # New: same tuple format, sorted by published_unix DESC
  sorted_by_popular: [...],    # New: {post_id, total_distributed, published_unix, category_id, tag_ids}
  mnesia_ready: false, ...
}
```

Add new client functions:
```elixir
def get_page_by_date(limit, offset \\ 0)
def get_page_by_date_category(category_id, limit, offset \\ 0)
def get_page_by_date_tag(tag_id, limit, offset \\ 0)

def get_page_by_popular(limit, offset \\ 0)
def get_page_by_popular_category(category_id, limit, offset \\ 0)
def get_page_by_popular_tag(tag_id, limit, offset \\ 0)
```

**Date sort function:**
```elixir
defp sort_posts_by_date(posts) do
  Enum.sort_by(posts, fn {_post_id, _balance, published_at, _category_id, _tag_ids} ->
    -published_at
  end)
end
```

**Popular sort function:**
The "Popular" list uses `total_distributed` instead of `balance`. Need to store `total_distributed` in the tuple.

Extend the tuple to 6 elements:
```elixir
{post_id, balance, published_unix, category_id, tag_ids, total_distributed}
```

```elixir
defp sort_posts_by_popular(posts) do
  Enum.sort_by(posts, fn {_post_id, _balance, published_at, _category_id, _tag_ids, total_distributed} ->
    {-total_distributed, -published_at}
  end)
end
```

Update `load_and_sort_all_posts/0` to:
1. Read `total_distributed` (elem 6) from `post_bux_points` Mnesia records
2. Include it in the tuple
3. Return three sorted lists

#### Step 2.2: Add Blog Functions for Date and Popular Sorting

**File:** `lib/blockster_v2/blog.ex`

Add new query functions:
```elixir
# Latest (date-sorted)
def list_published_posts_by_date(opts \\ [])
def list_published_posts_by_date_category(category_slug, opts \\ [])
def list_published_posts_by_date_tag(tag_slug, opts \\ [])

# Popular (total distributed-sorted)
def list_published_posts_by_popular(opts \\ [])
def list_published_posts_by_popular_category(category_slug, opts \\ [])
def list_published_posts_by_popular_tag(tag_slug, opts \\ [])
```

These follow the same pattern as existing `list_published_posts_by_pool` but call different SortedPostsCache functions.

#### Step 2.3: Update Homepage LiveView

**File:** `lib/blockster_v2_web/live/post_live/index.ex`

Add sort mode to assigns:
```elixir
|> assign(:sort_mode, "latest")  # "latest" or "popular"
```

Add tab switch event handler:
```elixir
def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in ["latest", "popular"] do
  # Rebuild components with new sort order
  {components, displayed_post_ids} = build_initial_components(tab)
  all_posts = Enum.flat_map(components, fn c -> c.posts end)
  bux_balances = build_bux_balances_map(all_posts)

  component_map = components
    |> Enum.filter(fn comp -> String.starts_with?(comp.id, "posts-") or String.starts_with?(comp.id, "home-") end)
    |> Enum.reduce(%{}, fn comp, acc -> Map.put(acc, comp.id, comp.module) end)

  {:noreply,
   socket
   |> assign(:sort_mode, tab)
   |> assign(:page_title, if(tab == "latest", do: "Latest Posts", else: "Popular Posts"))
   |> assign(:displayed_post_ids, displayed_post_ids)
   |> assign(:bux_balances, bux_balances)
   |> assign(:component_module_map, component_map)
   |> assign(:current_offset, @posts_per_cycle)
   |> stream(:components, components, reset: true)}
end
```

Update `build_components_batch/2` to accept sort mode and call appropriate Blog function.

#### Step 2.4: Update Category Page LiveView

**File:** `lib/blockster_v2_web/live/post_live/category.ex`

Same pattern: add `sort_mode` assign, `switch_tab` event handler, update `build_components_batch` to use sort-mode-appropriate queries.

#### Step 2.5: Update Tag Page LiveView

**File:** `lib/blockster_v2_web/live/post_live/tag.ex`

Same pattern as category page.

#### Step 2.6: Add Tab UI to Templates

**File:** `lib/blockster_v2_web/live/post_live/index.html.heex`

Add tabs above the post stream:
```heex
<div class="bg-[#F5F6FB] md:pt-32" id="homepage">
  <!-- Sort Tabs -->
  <div class="max-w-7xl mx-auto px-4 pt-4 pb-2 flex items-center gap-6">
    <button
      phx-click="switch_tab"
      phx-value-tab="latest"
      class={"text-sm font-haas_medium_65 pb-2 border-b-2 cursor-pointer transition-colors " <>
        if(@sort_mode == "latest", do: "text-[#141414] border-[#CAFC00]", else: "text-[#515B70] border-transparent hover:text-[#141414]")}
    >
      Latest
    </button>
    <button
      phx-click="switch_tab"
      phx-value-tab="popular"
      class={"text-sm font-haas_medium_65 pb-2 border-b-2 cursor-pointer transition-colors " <>
        if(@sort_mode == "popular", do: "text-[#141414] border-[#CAFC00]", else: "text-[#515B70] border-transparent hover:text-[#141414]")}
    >
      Popular
    </button>
  </div>
  <!-- ... rest of template ... -->
</div>
```

**File:** `lib/blockster_v2_web/live/post_live/category.html.heex`

Add same tab UI below the category header.

**File:** `lib/blockster_v2_web/live/post_live/tag.html.heex`

Add same tab UI below the tag header.

---

### Phase 3: Handle Edge Cases and Cleanup

#### 3.1: Infinite Scroll with Sort Mode

The `load-more` event handler in each LiveView must respect the current `sort_mode`. When loading more posts, use the appropriate Blog function based on `sort_mode`.

#### 3.2: Real-Time BUX Updates

- **Latest tab:** When receiving `{:bux_update, ...}` or `{:posts_reordered, ...}`, **do NOT reorder** since Latest is date-sorted (date doesn't change)
- **Popular tab:** Reordering could be triggered when `total_distributed` changes, but this would be disruptive UX. Better to update balance display without reordering (reordering only happens on page load/tab switch)

#### 3.3: Remove Balance-Based Reordering for Latest Tab

Currently `handle_info({:posts_reordered, ...})` rebuilds the homepage. For "Latest" tab, this should be a no-op. Only trigger rebuild when in "Popular" mode (and even then, consider skipping to avoid layout jumps).

#### 3.4: Fix Mobile Post Card Flashing

**Problem:** On mobile, post cards visibly flash every time any post's BUX balance updates. This happens because the BUX update handler in `index.ex` (lines 262-276) calls `send_update` to **ALL** displayed post components on every single BUX update:

```elixir
# Current code — shotgun send_update to every component
def handle_info({:bux_update, post_id, new_balance}, socket) do
  if post_id in socket.assigns.displayed_post_ids do
    bux_balances = Map.put(socket.assigns.bux_balances, post_id, new_balance)
    for {component_id, module} <- socket.assigns.component_module_map do
      send_update(self(), module, id: component_id, bux_balances: bux_balances)
    end
    {:noreply, assign(socket, :bux_balances, bux_balances)}
  end
end
```

Each `send_update` triggers a full re-render of the entire component — images, titles, excerpts, everything — even though only the BUX badge value changed. On mobile with slower rendering, this causes a visible flash/flicker across all cards.

**Root cause:** LiveView's `send_update` forces the component's `update/2` callback to run, which produces a new render tree. Even though LiveView diffs and only patches changed DOM, the brief layout recalculation on mobile causes visual flicker, especially with images.

**Important UX detail:** The token badge will now show **total BUX paid out** (`total_distributed`),
not the remaining pool balance. This value updates when *other* users earn from the post. However,
once the *current* user has earned, the card switches to showing earned badges instead — at which
point balance updates are irrelevant for that card.

So the real-time update is only needed for posts where the current user hasn't earned yet.

**Fix approach — targeted `send_update` only to affected component:**

Instead of sending updates to ALL components, find which component contains the updated post and only update that one:

```elixir
def handle_info({:bux_update, post_id, new_balance}, socket) do
  if post_id in socket.assigns.displayed_post_ids do
    bux_balances = Map.put(socket.assigns.bux_balances, post_id, new_balance)

    # Only send_update to the component that contains this post
    case Map.get(socket.assigns.post_to_component_map, post_id) do
      {component_id, module} ->
        send_update(self(), module, id: component_id, bux_balances: bux_balances)
      nil -> :ok
    end

    {:noreply, assign(socket, :bux_balances, bux_balances)}
  else
    {:noreply, socket}
  end
end
```

This requires tracking which component contains which post_id (add a `post_to_component_map` assign
built during `build_components_batch`). The map is `%{post_id => {component_id, module}}`.

**Files to modify:**
- `lib/blockster_v2_web/live/post_live/index.ex` — targeted send_update + post-to-component mapping
- `lib/blockster_v2_web/live/post_live/category.ex` — same fix
- `lib/blockster_v2_web/live/post_live/tag.ex` — same fix

#### 3.5: URL State (Optional)

Consider adding sort mode to URL params for shareability:
- `/?sort=latest` (default, can be omitted)
- `/?sort=popular`
- `/category/blockchain?sort=popular`

This would require updating `handle_params` to read the sort param.

---

## 4. File Change Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `lib/blockster_v2_web/components/layouts.ex` | Edit | Fix Trading category slug `crypto-trading` → `trading` |
| `lib/blockster_v2/content_automation/content_publisher.ex` | Edit | Fix category map: `"trading" => {"Trading", "trading"}` |
| `lib/blockster_v2/sorted_posts_cache.ex` | Edit | Add date/popular sorted lists, `total_distributed` to tuple, new API functions, tag update support |
| `lib/blockster_v2/blog.ex` | Edit | Add `list_published_posts_by_date*` and `list_published_posts_by_popular*` functions |
| `lib/blockster_v2/engagement_tracker.ex` | Edit | Add `get_all_post_distributed_amounts/0` function |
| `lib/blockster_v2_web/live/post_live/index.ex` | Edit | Add sort_mode assign, switch_tab handler, update build_components_batch, fix BUX update flash |
| `lib/blockster_v2_web/live/post_live/index.html.heex` | Edit | Add Latest/Popular tab UI |
| `lib/blockster_v2_web/live/post_live/category.ex` | Edit | Add sort_mode, switch_tab, update queries, fix BUX update flash |
| `lib/blockster_v2_web/live/post_live/category.html.heex` | Edit | Add Latest/Popular tab UI |
| `lib/blockster_v2_web/live/post_live/tag.ex` | Edit | Add sort_mode, switch_tab, update queries, fix BUX update flash |
| `lib/blockster_v2_web/live/post_live/tag.html.heex` | Edit | Add Latest/Popular tab UI |
| Production DB (one-time) | Run | Trim leading spaces from Art, Lifestyle, NFT category names |

## 5. Implementation Order

1. **Fix Trading nav link** (`crypto-trading` → `trading` in layouts.ex)
2. **Fix content automation category mappings** (3 mismatches: trading, nft, ai_crypto in content_publisher.ex)
3. **Clean dirty category names** (trim leading spaces on Art, Lifestyle, NFT via production DB)
4. **Fix SortedPostsCache tag update** (add `update_post_tags`)
5. **Extend SortedPostsCache** with date/popular sorted lists and `total_distributed`
6. **Add new Blog functions** for date and popular queries
7. **Add `get_all_post_distributed_amounts`** to EngagementTracker
8. **Update Homepage** LiveView + template with tabs
9. **Update Category** LiveView + template with tabs
10. **Update Tag** LiveView + template with tabs
11. **Handle real-time update edge cases**
12. **Fix mobile card flash** — targeted `send_update` instead of shotgun to all components
13. **Test all pages and tab switching**

## 6. Notes

- The "Popular" sort uses `total_distributed` (BUX paid out to readers), NOT `bux_balance` (remaining pool). This is the correct metric for popularity since it reflects how many readers have been rewarded.
- Posts with zero `total_distributed` will appear at the bottom of the "Popular" tab, sorted by date.
- The "Latest" tab is purely chronological (`published_at DESC`), ignoring BUX entirely.
- The existing BUX balance sort (current default) is effectively deprecated but the data remains in the cache for the Popular tab's tiebreaking.
