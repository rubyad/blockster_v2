# Suggested Posts Redesign

## Overview

Replace the "Related Articles" section at the bottom of post pages with "Suggested For You" cards that:
1. Match the exact design of homepage post cards
2. Show posts with highest BUX balances that the user hasn't read yet
3. Display BUX rewards available for each post

## Current vs New Behavior

| Aspect | Current (Related Articles) | New (Suggested For You) |
|--------|---------------------------|-------------------------|
| Selection | Tag-based matching | Highest BUX balance, unread first |
| Design | Gray cards, no BUX badge | White cards with BUX badge (matches homepage) |
| Logged in | Same as anonymous | Excludes posts user has already read |
| Anonymous | Same as logged in | Top 4 highest BUX posts |

## Performance

| Operation | Storage | Speed |
|-----------|---------|-------|
| Get sorted post IDs | GenServer state (memory) | ~0.01ms |
| Get user read posts | Mnesia (memory) | ~0.1ms |
| Fetch 4 posts by ID | PostgreSQL | ~2-5ms |
| **Total** | | **~2-5ms** |

The PostgreSQL hit is unavoidable (need post metadata like title, slug, featured_image, category) but minimal - a single indexed lookup for 4 rows.

---

## Implementation Checklist

### Phase 1: Backend - EngagementTracker

- [ ] **1.1** Add `get_user_read_post_ids/1` function to `engagement_tracker.ex`
  - Query `user_post_engagement` Mnesia table by user_id
  - Return list of post_ids where user has any engagement recorded
  - File: `lib/blockster_v2/engagement_tracker.ex`

### Phase 2: Backend - Blog Context

- [ ] **2.1** Add `get_suggested_posts/3` function to `blog.ex`
  - Parameters: `current_post_id`, `user_id \\ nil`, `limit \\ 4`
  - For logged-in users: exclude current post AND read posts
  - For anonymous users: exclude only current post
  - Get post IDs from `SortedPostsCache.get_page/2`
  - Fetch full Post structs with category preload
  - Return posts with `bux_balance` field populated
  - File: `lib/blockster_v2/blog.ex`

### Phase 3: Shared Component

- [ ] **3.1** Create `post_card` component in `core_components.ex` or new file
  - Match exact styling of homepage cards (PostsThreeComponent)
  - Props: `post`, `balance`
  - Include: featured image, category badge, title, date, BUX token badge
  - File: `lib/blockster_v2_web/components/core_components.ex` (or new component file)

- [ ] **3.2** Extract `token_badge` helper component
  - Shows BUX icon + formatted balance
  - Reusable across homepage and post page

### Phase 4: Update Post Show Page

- [ ] **4.1** Update `show.ex` mount function
  - Replace `Blog.get_related_posts(post, 4)` with `Blog.get_suggested_posts/3`
  - Pass `current_user.id` if logged in, `nil` if anonymous
  - Rename assign from `related_posts` to `suggested_posts`
  - File: `lib/blockster_v2_web/live/post_live/show.ex`

- [ ] **4.2** Update `show.html.heex` template
  - Replace "Related Articles" section (lines ~362-394)
  - Change heading to "Suggested For You"
  - Use 4-column grid: `grid-cols-2 md:grid-cols-4`
  - Use new `post_card` component for each post
  - File: `lib/blockster_v2_web/live/post_live/show.html.heex`

### Phase 5: Testing & Verification

- [ ] **5.1** Test logged-in user flow
  - Read a post, verify it doesn't appear in suggestions on other posts
  - Verify posts are ordered by BUX balance (highest first)

- [ ] **5.2** Test anonymous user flow
  - Verify top 4 BUX posts shown (excluding current)
  - Verify current post is excluded

- [ ] **5.3** Test edge cases
  - User has read all high-BUX posts (should show next available)
  - Post has no BUX balance (should still appear if in top 4)
  - New user with no read history

- [ ] **5.4** Visual verification
  - Cards match homepage styling exactly
  - BUX badges display correctly
  - Responsive layout works (2 cols mobile, 4 cols desktop)

### Phase 6: Cleanup

- [ ] **6.1** Remove `get_related_posts/2` if no longer used elsewhere
  - Check for other usages before removing
  - File: `lib/blockster_v2/blog.ex`

---

## File Changes Summary

| File | Action | Description |
|------|--------|-------------|
| `lib/blockster_v2/engagement_tracker.ex` | MODIFY | Add `get_user_read_post_ids/1` |
| `lib/blockster_v2/blog.ex` | MODIFY | Add `get_suggested_posts/3` |
| `lib/blockster_v2_web/components/core_components.ex` | MODIFY | Add `post_card/1` and `token_badge/1` |
| `lib/blockster_v2_web/live/post_live/show.ex` | MODIFY | Use new `get_suggested_posts/3` |
| `lib/blockster_v2_web/live/post_live/show.html.heex` | MODIFY | New card layout with `post_card` |

---

## Code Snippets

### 1.1 EngagementTracker.get_user_read_post_ids/1

```elixir
@doc """
Returns list of post IDs that a user has read (has engagement records for).
Used for filtering suggested posts to show unread content first.
"""
def get_user_read_post_ids(user_id) when is_integer(user_id) do
  :mnesia.dirty_index_read(:user_post_engagement, user_id, :user_id)
  |> Enum.map(fn record -> elem(record, 2) end)  # post_id is at index 2
end

def get_user_read_post_ids(_), do: []
```

### 2.1 Blog.get_suggested_posts/3

```elixir
@doc """
Returns suggested posts for a user, sorted by BUX balance descending.
Excludes the current post and (for logged-in users) posts they've already read.

## Parameters
  - current_post_id: ID of the post being viewed (always excluded)
  - user_id: User ID (nil for anonymous users)
  - limit: Number of posts to return (default: 4)

## Returns
  List of Post structs with :bux_balance virtual field populated
"""
def get_suggested_posts(current_post_id, user_id \\ nil, limit \\ 4) do
  # Build exclusion list
  exclude_ids = if user_id do
    read_ids = EngagementTracker.get_user_read_post_ids(user_id)
    [current_post_id | read_ids]
  else
    [current_post_id]
  end

  # Get sorted post IDs from cache, fetch extra to account for exclusions
  fetch_limit = limit + length(exclude_ids)

  post_ids_with_balances = SortedPostsCache.get_page(fetch_limit, 0)
    |> Enum.reject(fn {id, _balance} -> id in exclude_ids end)
    |> Enum.take(limit)

  # Extract IDs and create balance lookup map
  post_ids = Enum.map(post_ids_with_balances, fn {id, _} -> id end)
  balances_map = Map.new(post_ids_with_balances)

  if Enum.empty?(post_ids) do
    []
  else
    # Fetch full post objects
    posts = from(p in Post,
      where: p.id in ^post_ids,
      preload: [:category]
    )
    |> Repo.all()

    # Sort by balance (maintain cache order) and attach balance
    posts
    |> Enum.sort_by(fn p -> -Map.get(balances_map, p.id, 0) end)
    |> Enum.map(fn p -> Map.put(p, :bux_balance, Map.get(balances_map, p.id, 0)) end)
  end
end
```

### 3.1 PostCard Component

```elixir
attr :post, :map, required: true
attr :balance, :number, default: 0

def post_card(assigns) do
  ~H"""
  <.link navigate={~p"/#{@post.slug}"} class="block group cursor-pointer">
    <div class="rounded-lg border-[#1414141A] border bg-white hover:shadow-lg transition-all flex flex-col h-full">
      <!-- Featured Image -->
      <div class="img-wrapper w-full overflow-hidden rounded-t-lg relative" style="padding-bottom: 100%;">
        <%= if @post.featured_image do %>
          <img
            src={BlocksterV2.ImageKit.w500_h500(@post.featured_image)}
            alt={@post.title}
            class="absolute inset-0 w-full h-full object-cover"
            loading="lazy"
          />
        <% else %>
          <div class="absolute inset-0 bg-gradient-to-br from-purple-100 to-blue-100" />
        <% end %>
      </div>

      <!-- Card Content -->
      <div class="px-3 py-3 pb-4 flex-1 flex flex-col text-center">
        <!-- Category Badge -->
        <%= if @post.category do %>
          <div class="flex justify-center">
            <span class="px-3 py-1 bg-white border border-[#E7E8F1] text-[#141414] rounded-full text-xs font-haas_medium_65">
              {@post.category.name}
            </span>
          </div>
        <% end %>

        <!-- Title -->
        <h4 class="font-haas_medium_65 text-[#141414] mt-2 text-md leading-tight line-clamp-2">
          {@post.title}
        </h4>

        <!-- Date -->
        <p class="text-xs font-haas_roman_55 text-[#141414] flex-1 mt-3">
          {Calendar.strftime(@post.published_at, "%B %d, %Y")}
        </p>

        <!-- BUX Token Badge -->
        <div class="flex justify-center mt-3">
          <.bux_badge balance={@balance} />
        </div>
      </div>
    </div>
  </.link>
  """
end

defp bux_badge(assigns) do
  ~H"""
  <div class="flex items-center gap-1 px-2 py-1 bg-[#F3F5FF] rounded-full">
    <img src="/images/bux-icon.png" alt="BUX" class="w-4 h-4" />
    <span class="text-xs font-haas_medium_65 text-[#141414]">
      {format_bux_balance(@balance)} BUX
    </span>
  </div>
  """
end

defp format_bux_balance(balance) when is_number(balance) and balance >= 1000 do
  "#{Float.round(balance / 1000, 1)}k"
end
defp format_bux_balance(balance) when is_number(balance), do: Integer.to_string(trunc(balance))
defp format_bux_balance(_), do: "0"
```

### 4.2 Updated show.html.heex Section

```heex
<%= if @suggested_posts && length(@suggested_posts) > 0 do %>
  <div class="mt-16 pt-10 border-t border-[#E7E8F1]">
    <h2 class="text-2xl font-haas_bold_75 mb-8 text-[#141414]">Suggested For You</h2>

    <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
      <%= for post <- @suggested_posts do %>
        <.post_card post={post} balance={post.bux_balance || 0} />
      <% end %>
    </div>
  </div>
<% end %>
```

---

## Notes

- The `user_post_engagement` Mnesia table tracks user reading activity
- Index 2 in the tuple is the `post_id` field
- `SortedPostsCache` is already sorted by BUX balance descending, then published_at descending
- The single PostgreSQL query is necessary to fetch post metadata (title, slug, featured_image, category)
- This approach is efficient: ~2-5ms total for the entire operation
