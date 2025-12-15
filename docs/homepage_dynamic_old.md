# Homepage Dynamic Content System (Legacy)

This document describes the current implementation of the posts index/homepage dynamic content loading system.

---

## Table of Contents

1. [Overview](#overview)
2. [Main Index LiveView](#main-index-liveview)
3. [LiveComponents Used](#livecomponents-used)
4. [Posts Loading & Pagination](#posts-loading--pagination)
5. [BUX Balance Calculation](#bux-balance-calculation)
6. [Real-Time Updates & PubSub](#real-time-updates--pubsub)
7. [Data Flow Architecture](#data-flow-architecture)
8. [Section Layouts](#section-layouts)
9. [Admin Curation System](#admin-curation-system)

---

## Overview

The homepage is a Phoenix LiveView (`BlocksterV2Web.PostLive.Index`) that displays:
- Curated "Top Stories" section (10 positions)
- Curated "Conversations" section (6 positions)
- Infinite scroll of dynamically loaded category/tag filtered posts
- Interspersed shop/banner promotional components
- Real-time BUX balance updates via PubSub

---

## Main Index LiveView

### Location & Setup

- **File**: `lib/blockster_v2_web/live/post_live/index.ex`
- **Module**: `BlocksterV2Web.PostLive.Index`
- **Template**: `lib/blockster_v2_web/live/post_live/index.html.heex`

### Mount Process

The `mount/3` callback initializes the page:

1. **PubSub Subscription**:
   ```elixir
   if connected?(socket) do
     EngagementTracker.subscribe_to_all_bux_updates()
   end
   ```
   - Subscribes to topic: `"post_bux:all"`
   - Enables real-time BUX balance updates across all displayed posts

2. **Data Loading**:
   - **Latest News**: `Blog.get_curated_posts_for_section("latest_news")` - 10 curated positions
   - **Conversations**: `Blog.get_curated_posts_for_section("conversations")` - 6 curated positions
   - All posts enriched with BUX balances via `Blog.with_bux_balances()`

3. **Component Stream Setup**:
   ```elixir
   socket
   |> stream(:components, components)
   |> assign(:bux_balances, bux_balances)
   |> assign(:component_module_map, component_module_map)
   |> assign(:displayed_post_ids, displayed_post_ids)
   ```

4. **Tracking Structures**:
   - `displayed_post_ids`: List of all post IDs currently shown (prevents duplicates)
   - `displayed_categories`: Categories already loaded
   - `displayed_tags`: Tags already loaded
   - `component_module_map`: Maps component IDs to modules for real-time updates
   - `bux_balances`: Map of `post_id => current_bux_balance`

---

## LiveComponents Used

### Primary Curated Sections (Always Displayed)

#### 1. PostsOneComponent (`posts-one`)

- **File**: `lib/blockster_v2_web/live/post_live/posts_one_component.ex`
- **Function**: "Top Stories" section
- **Layout**: Grid with 5 main cards + 4 sidebar cards

```
┌──────────┬──────────────────┬──────────┐
│  Left    │                  │  Right   │
│ Card 1   │   Middle Card    │  Card 4  │
│          │   (Tall, Spans   │          │
│ Card 2   │    2 Rows)       │  Card 5  │
└──────────┴──────────────────┴──────────┘

┌──────────────────────────────────────────┐
│ Recommended Sidebar (4 horizontal cards) │
│ Cards 6, 7, 8, 9                         │
└──────────────────────────────────────────┘
```

- **Receives**: 10 curated posts from "latest_news" section
- **Admin Controls**: Settings icon on each card for post curation

#### 2. PostsTwoComponent (`posts-two`)

- **File**: `lib/blockster_v2_web/live/post_live/posts_two_component.ex`
- **Function**: "Conversations with industry leaders" section
- **Theme**: Dark background (`bg-bg-dark`)
- **Layout**:
  - 3 cards top row
  - 2 cards bottom row (desktop only)
  - 1 large sidebar card (position 6)
- **Receives**: 6 curated posts from "conversations" section

### Dynamic Components (Loaded via Infinite Scroll)

#### 3. PostsThreeComponent (`posts-three-{unique_id}`)

- **Function**: Generic 5-card component (same layout as posts-one)
- **Triggered**: When last component is `PostsTwoComponent` or `ShopFourComponent`
- **Content**: Category or tag filtered posts

#### 4. PostsFourComponent (`posts-four-{unique_id}`)

- **Function**: 3-card column layout
- **Triggered**: When last component is `RewardsBannerComponent`

#### 5. PostsFiveComponent (`posts-five-{unique_id}`)

- **Function**: 6-card layout
- **Triggered**: When last component is `RewardsBannerComponent`

#### 6. PostsSixComponent (`posts-six-{unique_id}`)

- **Function**: 5-card component
- **Triggered**: When last component is `PostsFiveComponent`

### Non-Post Components

- **ShopOneComponent**, **ShopTwoComponent**, **ShopThreeComponent**, **ShopFourComponent**: Commerce/promotional sections
- **RewardsBannerComponent**: BUX rewards promotional banner
- **FullWidthBannerComponent**: Large hero banner

---

## Posts Loading & Pagination

### Initial Load

Curated posts fetched via `Blog.get_curated_posts_for_section(section)`:
- Returns posts ordered by position
- Only published posts (`published_at IS NOT NULL`)
- Fully preloaded: author, category, hub, tags

### Infinite Scroll Implementation

**JavaScript Hook** (`InfiniteScroll` in `assets/js/app.js`):

```javascript
InfiniteScroll: {
  mounted() {
    const observer = new IntersectionObserver(
      entries => {
        if (entries[0].isIntersecting && !this.pending) {
          this.pending = true
          this.pushEvent("load-more", {})
        }
      },
      { rootMargin: "500px" }
    )
    observer.observe(this.el)

    // Backup scroll handler
    window.addEventListener("scroll", () => {
      if (window.innerHeight + window.scrollY >= document.body.offsetHeight - 800) {
        this.pushEvent("load-more", {})
      }
    })
  }
}
```

**Server-Side Load More** (`handle_event("load-more", _, socket)`):

1. **Algorithm Logic**:
   - Different load patterns based on last component loaded
   - Selects random available categories/tags not yet displayed
   - Respects `exclude_ids` to prevent post duplicates
   - Loads 3 components at a time

2. **Load Patterns**:
   ```
   After PostsTwo/ShopFour → ShopOne → PostsThree → RewardsBanner
   After RewardsBanner → ShopTwo → PostsFour → FullWidthBanner → PostsFive
   After PostsFive → ShopThree → PostsSix → ShopFour
   ```

3. **Post Fetching**:
   ```elixir
   if category != nil do
     Blog.list_published_posts_by_category(filter, limit: 5, exclude_ids: displayed_post_ids)
   else
     Blog.list_published_posts_by_tag(filter, limit: 5, exclude_ids: displayed_post_ids)
   end
   ```

### Database Queries

**Blog Context Functions** (`lib/blockster_v2/blog.ex`):

- `get_curated_posts_for_section(section)`: Joins CuratedPost with Post, orders by position
- `list_published_posts_by_category(slug, opts)`: Category filtered, supports limit/exclude_ids
- `list_published_posts_by_tag(slug, opts)`: Tag filtered via many-to-many join
- `search_posts_fulltext(query, opts)`: PostgreSQL full-text search with ranking

---

## BUX Balance Calculation

### Data Flow

**Initial Load**:
```elixir
bux_balances = all_posts
  |> Enum.uniq_by(& &1.id)
  |> Enum.reduce(%{}, fn post, acc ->
    Map.put(acc, post.id, Map.get(post, :bux_balance, 0))
  end)
```

**Enrichment** (`Blog.with_bux_balances/1`):
```elixir
def with_bux_balances(posts) when is_list(posts) do
  post_ids = Enum.map(posts, & &1.id)
  balances = EngagementTracker.get_post_bux_balances(post_ids)

  Enum.map(posts, fn post ->
    Map.put(post, :bux_balance, Map.get(balances, post.id, 0))
  end)
end
```

### Mnesia Source

**EngagementTracker** reads from Mnesia `post_bux_points` table:
```elixir
def get_post_bux_balance(post_id) do
  case :mnesia.dirty_read({:post_bux_points, post_id}) do
    [] -> 0
    [record] -> elem(record, 4) || 0  # Index 4 is bux_balance
  end
end
```

**Table Structure** (`post_bux_points`):
| Index | Field |
|-------|-------|
| 0 | `:post_bux_points` (table name) |
| 1 | `post_id` (primary key) |
| 2 | `reward` |
| 3 | `read_time` |
| **4** | **`bux_balance`** (displayed value) |
| 5 | `bux_deposited` |
| 6-9 | Extra fields |
| 10 | `created_at` |
| 11 | `updated_at` |

### Component-Level Display

**Helper Function** (in all Posts*Component files):
```elixir
defp get_bux_balance(assigns, post) do
  bux_balances = Map.get(assigns, :bux_balances, %{})
  Map.get(bux_balances, post.id, Map.get(post, :bux_balance, 0))
end
```

**Fallback Priority**:
1. Check `@bux_balances` map (real-time from parent)
2. Check post's `:bux_balance` virtual field
3. Default to 0

**Template Display**:
```heex
<span class="text-xs font-haas_medium_65">
  <%= Number.Delimit.number_to_delimited(get_bux_balance(assigns, post), precision: 1) %>
</span>
```

---

## Real-Time Updates & PubSub

### Architecture

**PubSub Topics**:
- `"post_bux:#{post_id}"`: Individual post updates
- `"post_bux:all"`: Global index page updates

### Subscription Flow

**Mount**:
```elixir
if connected?(socket) do
  EngagementTracker.subscribe_to_all_bux_updates()
end
```

**Subscribe Function** (EngagementTracker):
```elixir
def subscribe_to_all_bux_updates() do
  Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "post_bux:all")
end
```

### Broadcasting

**When BUX is Earned**:
```elixir
def broadcast_bux_update(post_id, new_balance) do
  Phoenix.PubSub.broadcast(
    BlocksterV2.PubSub,
    "post_bux:#{post_id}",
    {:bux_update, post_id, new_balance}
  )
  Phoenix.PubSub.broadcast(
    BlocksterV2.PubSub,
    "post_bux:all",
    {:bux_update, post_id, new_balance}
  )
end
```

### Message Handling

**Event Handler**:
```elixir
def handle_info({:bux_update, post_id, new_balance}, socket) do
  if post_id in socket.assigns.displayed_post_ids do
    bux_balances = Map.put(socket.assigns.bux_balances, post_id, new_balance)

    # Send update to all displayed post components
    for {component_id, module} <- socket.assigns.component_module_map do
      send_update(self(), module, id: component_id, bux_balances: bux_balances)
    end

    {:noreply, assign(socket, :bux_balances, bux_balances)}
  else
    {:noreply, socket}
  end
end
```

**Key Points**:
- Only updates if post is displayed
- Updates parent socket's `bux_balances`
- Broadcasts to all components via `send_update`
- Components re-render with updated `bux_balances` prop

---

## Data Flow Architecture

```
┌─────────────────────────────────────────────────┐
│  Database (PostgreSQL)                          │
│  - posts, categories, tags, hubs tables         │
│  - curated_posts table (positions)              │
└────────────────┬────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────┐
│  Blog Context                                   │
│  - get_curated_posts_for_section()              │
│  - list_published_posts_by_category()           │
│  - with_bux_balances()                          │
└────────────────┬────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────┐
│  Mnesia (In-Memory Cache)                       │
│  - post_bux_points table                        │
│  - Contains: bux_balance for each post          │
└────────────────┬────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────┐
│  Index LiveView (index.ex)                      │
│  - Loads curated posts                          │
│  - Loads BUX balances from Mnesia               │
│  - Initializes bux_balances map                 │
│  - Subscribes to PubSub                         │
└────────────────┬────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────┐
│  Component Stream                               │
│  - PostsOneComponent                            │
│  - PostsTwoComponent                            │
│  - Dynamic Posts*/Shop/Banner components        │
│  (Each receives bux_balances in props)          │
└────────────────┬────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────┐
│  Templates (.html.heex)                         │
│  - Render cards with BUX balance display        │
│  - Use get_bux_balance() helper                 │
└─────────────────────────────────────────────────┘
```

### Real-Time Update Path

```
User Action (Read/Share) → EngagementTracker
         │
         ▼
add_post_bux_earned() → Updates Mnesia → broadcast_bux_update()
         │
         ▼
Phoenix PubSub → {:bux_update, post_id, balance} to "post_bux:all"
         │
         ▼
Index LiveView handle_info/2 → Updates bux_balances → send_update() to components
         │
         ▼
LiveComponents Re-render → Browser DOM Updated
```

---

## Section Layouts

### Section 1: Master Crypto Banner (Static)

- **Location**: Top of index.html.heex
- **Content**: Static banner with hero image
- **Button**: "Claim airdrop" CTA

### Section 2: Top Stories (PostsOneComponent)

```
┌─────────────────────────────────────────────────┐
│ Breadcrumb: Home › Top Stories                  │
├─────────────────────────────────────────────────┤
│ Title: "Top Stories"                            │
├─────────────────────────────────────────────────┤
│ ┌──────────┬──────────────────┬──────────┐      │
│ │ Card 1   │   Middle Card    │  Card 4  │      │
│ │ Card 2   │   (Position 3)   │  Card 5  │      │
│ └──────────┴──────────────────┴──────────┘      │
│ ┌──────────────────────────────────────────┐    │
│ │ Recommended: Cards 6, 7, 8, 9            │    │
│ └──────────────────────────────────────────┘    │
└─────────────────────────────────────────────────┘
```

### Section 3: Conversations (PostsTwoComponent)

- Dark theme background
- 6 curated posts
- Large sidebar card on desktop
- Mobile: inline featured card

### Sections 4+: Dynamic Infinite Scroll

**Load Sequence**:
```
Initial: PostsOne (10) + PostsTwo (6)

Scroll 1: ShopOne → PostsThree (5) → RewardsBanner
Scroll 2: ShopTwo → PostsFour (3) → FullWidthBanner → PostsFive (6)
Scroll 3: ShopThree → PostsSix (5) → ShopFour

Repeat...
```

---

## Admin Curation System

### How It Works

1. **Settings Button**: Each card position has a settings icon (visible to admins)
2. **Post Selector Modal**: Opens search interface for posts
3. **Selection**: Admin searches and selects a post for that position
4. **Database Update**: `curated_posts` table updated with post_id and position

### Events

- `open_post_selector`: Opens modal with section/position params
- `search_posts`: Full-text search for post selection
- `select_post`: Assigns post to curated position
- `close_post_selector`: Closes modal

### Database Schema

**curated_posts table**:
| Column | Type | Description |
|--------|------|-------------|
| `id` | integer | Primary key |
| `section` | string | "latest_news" or "conversations" |
| `position` | integer | 1-10 for latest_news, 1-6 for conversations |
| `post_id` | integer | FK to posts table |

---

## Key Architectural Decisions

1. **Stream-based Components**: Phoenix streams for efficient DOM diffing
2. **Virtual BUX Balance**: Computed from Mnesia cache, not stored in PostgreSQL
3. **Dual PubSub Topics**: Individual post + global index updates
4. **Explicit Component Updates**: `send_update` overcomes stream caching
5. **Intersection Observer**: 500px margin for eager loading + backup scroll handler
6. **Content Diversification**: Algorithm prevents duplicates and diversifies categories/tags
7. **Admin Curation**: Database-backed manual control over featured positions
8. **Mnesia Caching**: In-memory storage for real-time BUX updates
