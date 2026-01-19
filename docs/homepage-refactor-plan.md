# Homepage Refactor Plan: Category-Style Chronological Display with Temporary Curation

## Overview

Convert the homepage from its current **curated sections** structure to a **chronological display** like the category page, showing all posts by `published_at DESC`. Admin curation becomes **temporary** - curated posts are displayed until a new post is published, at which point all curation is cleared and posts display naturally by publish date.

---

## Current State

### Homepage Structure (index.ex)
- **6 fixed curated sections**: `latest_news` (10 posts), `conversations` (6 posts), `posts_three` (5), `posts_four` (3), `posts_five` (6), `posts_six` (5)
- Each section has a **fixed component**: PostsOneComponent, PostsTwoComponent, etc.
- Posts are fetched via `Blog.get_all_curated_posts()` which reads from `curated_posts` table
- Admin can click cog icon to replace any post with a different one via `update_curated_post_position()`
- Infinite scroll loads more posts by **random category/tag** selection

### Category Page Structure (category.ex)
- **Cycling components**: PostsThreeComponent (5) → PostsFourComponent (3) → PostsFiveComponent (6) → PostsSixComponent (5) → repeat
- Posts fetched via `Blog.list_published_posts_by_category()` ordered by `published_at DESC`
- `exclude_ids` prevents duplicate posts across components
- Infinite scroll loads 4 more components (19 posts) each time
- **No curation** - purely chronological

### Database Schema
```
curated_posts
├── id (integer)
├── section (string) - "latest_news", "posts_three", etc.
├── position (integer) - 1-10 depending on section
├── post_id (FK to posts)
└── timestamps
```

---

## Target State

### New Behavior
1. **Default display**: All posts shown chronologically by `published_at DESC`
2. **Component cycling**: Same as category page (Three → Four → Five → Six → repeat)
3. **Temporary curation**: Admin can replace any post position with a curated post
4. **Auto-clear on publish**: When a new post is created/published, all `curated_posts` records are deleted
5. **Cog icon retained**: Admin can still click cog to curate individual positions

### Visual Layout
```
Initial Load (19 posts):
┌─────────────────────────────────────────┐
│ PostsThreeComponent (posts 1-5)         │
├─────────────────────────────────────────┤
│ PostsFourComponent (posts 6-8)          │
├─────────────────────────────────────────┤
│ PostsFiveComponent (posts 9-14)         │
├─────────────────────────────────────────┤
│ PostsSixComponent (posts 15-19)         │
└─────────────────────────────────────────┘

On scroll (19 more posts):
┌─────────────────────────────────────────┐
│ PostsThreeComponent (posts 20-24)       │
├─────────────────────────────────────────┤
│ PostsFourComponent (posts 25-27)        │
├─────────────────────────────────────────┤
│ PostsFiveComponent (posts 28-33)        │
├─────────────────────────────────────────┤
│ PostsSixComponent (posts 34-38)         │
└─────────────────────────────────────────┘
```

---

## Implementation Plan

### Phase 1: Database Changes

#### 1.1 Modify `curated_posts` Table Schema
The existing schema works but needs a simpler structure for position-based curation:

```elixir
# Option A: Keep existing schema, just change usage
# curated_posts now represents "override at global position N"
# Section field becomes obsolete - use a single flat position number

# Option B: New simpler schema (RECOMMENDED)
# Migration: priv/repo/migrations/XXXXXX_simplify_curated_posts.exs

def change do
  # Drop old constraints
  drop_if_exists unique_index(:curated_posts, [:section, :position])

  # Remove section column, position becomes global
  alter table(:curated_posts) do
    remove :section
    # position now means "global position in feed" (1, 2, 3, etc.)
    # post_id stays the same
  end

  # Add unique constraint on position alone
  create unique_index(:curated_posts, [:position])
end
```

#### 1.2 Update CuratedPost Schema
```elixir
# lib/blockster_v2/blog/curated_post.ex
defmodule BlocksterV2.Blog.CuratedPost do
  schema "curated_posts" do
    field :position, :integer  # Global position (1, 2, 3, etc.)
    belongs_to :post, BlocksterV2.Blog.Post
    timestamps()
  end

  def changeset(curated_post, attrs) do
    curated_post
    |> cast(attrs, [:position, :post_id])
    |> validate_required([:position, :post_id])
    |> validate_number(:position, greater_than: 0)
    |> unique_constraint(:position)
  end
end
```

### Phase 2: Blog Context Functions

#### 2.1 New Function: Get Posts with Curation Overrides
```elixir
# lib/blockster_v2/blog.ex

@doc """
Returns published posts in chronological order, with curated overrides applied.
Curated posts replace posts at their specified positions.

## Duplicate Prevention
When a post is curated to position N, it must NOT appear again at its natural
chronological position. We achieve this by:
1. Fetching ALL curated post IDs (not just those in current range)
2. Excluding ALL curated post IDs from chronological query
3. Curated posts only appear at their designated positions

Example: Post "Bitcoin News" is #15 chronologically, admin curates it to position 1.
- Position 1: "Bitcoin News" (curated)
- Position 15: Some other post (Bitcoin News is excluded from chrono query)

## Options
  * :limit - max posts to return
  * :offset - number of posts to skip (for pagination)
  * :exclude_ids - post IDs to exclude

## Returns
List of posts where curated posts appear at their designated positions,
and remaining positions filled chronologically (with curated posts excluded).
"""
def list_posts_with_curation(opts \\ []) do
  limit = Keyword.get(opts, :limit, 19)
  offset = Keyword.get(opts, :offset, 0)
  exclude_ids = Keyword.get(opts, :exclude_ids, [])

  # Get ALL curated posts (not just those in current range)
  # This is crucial for duplicate prevention
  curated_map = get_curated_positions_map()

  # ALL curated post IDs must be excluded from chronological query
  # This prevents a curated post from appearing both at its curated position
  # AND at its natural chronological position
  all_curated_post_ids = Map.values(curated_map) |> Enum.map(& &1.id)

  # Calculate which positions we need
  start_position = offset + 1
  end_position = offset + limit

  # Find curated posts in THIS range (for insertion)
  curated_in_range = curated_map
    |> Enum.filter(fn {pos, _post} -> pos >= start_position and pos <= end_position end)
    |> Map.new()

  # Calculate how many chronological posts we need
  # (total positions minus curated positions in range)
  chrono_needed = limit - map_size(curated_in_range)

  # Fetch chronological posts, excluding ALL curated posts (not just those in range)
  # This is the key to preventing duplicates!
  chrono_posts = list_published_posts(
    limit: chrono_needed + 10,  # Buffer for exclusions
    exclude_ids: exclude_ids ++ all_curated_post_ids
  )
  |> Enum.take(chrono_needed)

  # Merge curated and chronological posts at correct positions
  merge_posts_with_curation(curated_in_range, chrono_posts, start_position, end_position)
end

@doc """
Returns a map of position => post for all curated positions.
"""
def get_curated_positions_map do
  from(cp in CuratedPost,
    join: p in assoc(cp, :post),
    where: not is_nil(p.published_at),
    preload: [post: {p, [:author, :category, :hub, :tags]}]
  )
  |> Repo.all()
  |> Enum.map(fn cp -> {cp.position, cp.post} end)
  |> Map.new()
end

defp merge_posts_with_curation(curated_map, chrono_posts, start_pos, end_pos) do
  chrono_queue = :queue.from_list(chrono_posts)

  Enum.reduce(start_pos..end_pos, {[], chrono_queue}, fn pos, {acc, queue} ->
    case Map.get(curated_map, pos) do
      nil ->
        # Use next chronological post
        case :queue.out(queue) do
          {{:value, post}, new_queue} -> {acc ++ [post], new_queue}
          {:empty, queue} -> {acc, queue}
        end

      curated_post ->
        # Use curated post at this position
        {acc ++ [curated_post], queue}
    end
  end)
  |> elem(0)
end
```

#### 2.2 Function: Clear All Curation
```elixir
@doc """
Deletes all curated posts. Called when a new post is published.
"""
def clear_all_curation do
  Repo.delete_all(CuratedPost)
end
```

#### 2.3 Function: Set Curated Post at Position
```elixir
@doc """
Sets a curated post at a specific global position.
Creates or updates the curation.
"""
def set_curated_post(position, post_id) do
  case Repo.get_by(CuratedPost, position: position) do
    nil ->
      %CuratedPost{}
      |> CuratedPost.changeset(%{position: position, post_id: post_id})
      |> Repo.insert()

    existing ->
      existing
      |> CuratedPost.changeset(%{post_id: post_id})
      |> Repo.update()
  end
end

@doc """
Removes curation from a specific position.
"""
def clear_curated_post(position) do
  case Repo.get_by(CuratedPost, position: position) do
    nil -> {:ok, nil}
    existing -> Repo.delete(existing)
  end
end
```

### Phase 3: Auto-Clear on Post Publish

#### 3.1 Modify Post Creation/Publishing
```elixir
# lib/blockster_v2/blog.ex

def create_post(attrs) do
  result = %Post{}
    |> Post.changeset(attrs)
    |> Repo.insert()

  case result do
    {:ok, post} ->
      # Clear curation if post is published
      if post.published_at do
        clear_all_curation()
      end
      {:ok, post}

    error -> error
  end
end

def update_post(%Post{} = post, attrs) do
  was_published = post.published_at != nil

  result = post
    |> Post.changeset(attrs)
    |> Repo.update()

  case result do
    {:ok, updated_post} ->
      # Clear curation if post was just published (wasn't before, is now)
      is_now_published = updated_post.published_at != nil
      if !was_published and is_now_published do
        clear_all_curation()
      end
      {:ok, updated_post}

    error -> error
  end
end
```

### Phase 4: Refactor Homepage LiveView

#### 4.1 Simplified Mount
```elixir
# lib/blockster_v2_web/live/post_live/index.ex

@component_modules [
  BlocksterV2Web.PostLive.PostsThreeComponent,
  BlocksterV2Web.PostLive.PostsFourComponent,
  BlocksterV2Web.PostLive.PostsFiveComponent,
  BlocksterV2Web.PostLive.PostsSixComponent
]

@posts_per_component %{
  BlocksterV2Web.PostLive.PostsThreeComponent => 5,
  BlocksterV2Web.PostLive.PostsFourComponent => 3,
  BlocksterV2Web.PostLive.PostsFiveComponent => 6,
  BlocksterV2Web.PostLive.PostsSixComponent => 5
}

def mount(_params, _session, socket) do
  if connected?(socket) do
    EngagementTracker.subscribe_to_all_bux_updates()
  end

  # Build initial 4 components (19 posts total)
  {components, displayed_post_ids} = build_initial_components()

  # Build bux_balances map
  all_posts = Enum.flat_map(components, fn c -> c.posts end)
  bux_balances = build_bux_balances_map(all_posts)

  {:ok,
   socket
   |> assign(:page_title, "Latest Posts")
   |> assign(:displayed_post_ids, displayed_post_ids)
   |> assign(:bux_balances, bux_balances)
   |> assign(:last_component_module, BlocksterV2Web.PostLive.PostsSixComponent)
   |> assign(:current_offset, 19)  # Track for pagination
   |> assign(:show_post_selector, false)
   |> assign(:selector_position, nil)
   |> assign(:selector_query, "")
   |> assign(:selector_results, [])
   |> stream(:components, components)}
end

defp build_initial_components do
  build_components_batch(0, [])
end

defp build_components_batch(offset, displayed_post_ids) do
  # Calculate posts needed for one full cycle
  total_posts_needed = 5 + 3 + 6 + 5  # 19

  # Fetch posts with curation overrides
  posts = Blog.list_posts_with_curation(
    limit: total_posts_needed,
    offset: offset,
    exclude_ids: displayed_post_ids
  ) |> Blog.with_bux_balances()

  if posts == [] do
    {[], displayed_post_ids}
  else
    # Distribute posts across components
    {three_posts, rest} = Enum.split(posts, 5)
    {four_posts, rest} = Enum.split(rest, 3)
    {five_posts, rest} = Enum.split(rest, 6)
    {six_posts, _} = Enum.split(rest, 5)

    components = [
      %{
        id: "posts-three-#{offset}",
        module: BlocksterV2Web.PostLive.PostsThreeComponent,
        posts: three_posts,
        type: "home-posts",
        content: "home",
        # Calculate global positions for cog icons
        start_position: offset + 1
      },
      %{
        id: "posts-four-#{offset}",
        module: BlocksterV2Web.PostLive.PostsFourComponent,
        posts: four_posts,
        type: "home-posts",
        content: "home",
        start_position: offset + 6
      },
      %{
        id: "posts-five-#{offset}",
        module: BlocksterV2Web.PostLive.PostsFiveComponent,
        posts: five_posts,
        type: "home-posts",
        content: "home",
        start_position: offset + 9
      },
      %{
        id: "posts-six-#{offset}",
        module: BlocksterV2Web.PostLive.PostsSixComponent,
        posts: six_posts,
        type: "home-posts",
        content: "home",
        start_position: offset + 15
      }
    ]

    new_post_ids = Enum.map(posts, & &1.id)
    {components, displayed_post_ids ++ new_post_ids}
  end
end
```

#### 4.2 Simplified Load More
```elixir
def handle_event("load-more", _, socket) do
  offset = socket.assigns.current_offset
  displayed_post_ids = socket.assigns.displayed_post_ids

  {new_components, new_displayed_post_ids} =
    build_components_batch(offset, displayed_post_ids)

  if new_components == [] do
    {:reply, %{end_reached: true}, socket}
  else
    socket =
      Enum.reduce(new_components, socket, fn component, acc_socket ->
        stream_insert(acc_socket, :components, component, at: -1)
      end)

    {:noreply,
     socket
     |> assign(:displayed_post_ids, new_displayed_post_ids)
     |> assign(:current_offset, offset + 19)}
  end
end
```

#### 4.3 Update Curation Handler
```elixir
def handle_event("open_post_selector", %{"position" => position}, socket) do
  # Position is now global (1, 2, 3, etc.)
  recent_posts = Blog.list_published_posts(limit: 100)

  {:noreply,
   socket
   |> assign(:show_post_selector, true)
   |> assign(:selector_position, String.to_integer(position))
   |> assign(:selector_query, "")
   |> assign(:selector_results, recent_posts)}
end

def handle_event("select_post", %{"post_id" => post_id}, socket) do
  position = socket.assigns.selector_position
  post_id = String.to_integer(post_id)

  case Blog.set_curated_post(position, post_id) do
    {:ok, _} ->
      # Reload all components
      {components, displayed_post_ids} = build_initial_components()
      all_posts = Enum.flat_map(components, fn c -> c.posts end)
      bux_balances = build_bux_balances_map(all_posts)

      {:noreply,
       socket
       |> stream(:components, components, reset: true)
       |> assign(:displayed_post_ids, displayed_post_ids)
       |> assign(:bux_balances, bux_balances)
       |> assign(:current_offset, 19)
       |> assign(:show_post_selector, false)
       |> put_flash(:info, "Post curated at position #{position}")}

    {:error, _} ->
      {:noreply, put_flash(socket, :error, "Failed to curate post")}
  end
end
```

### Phase 5: Update Component Templates

#### 5.1 Modify Cog Icon to Pass Global Position
Each component template needs to pass the **global position** instead of section-based position.

```heex
<!-- In posts_three_component.html.heex -->
<%= for {post, idx} <- Enum.with_index(@posts, @start_position) do %>
  <div class="... relative">
    <%= if assigns[:current_user] && @current_user.is_admin do %>
      <button
        phx-click="open_post_selector"
        phx-value-position={idx}
        class="absolute top-2 right-2 z-10 bg-white rounded-full p-2 shadow-md hover:bg-gray-100 transition-colors cursor-pointer"
      >
        <!-- Cog SVG -->
      </button>
    <% end %>
    <!-- Rest of card -->
  </div>
<% end %>
```

#### 5.2 Component Module Updates
Add `start_position` to component assigns:

```elixir
# Each posts_*_component.ex needs to accept start_position
defmodule BlocksterV2Web.PostLive.PostsThreeComponent do
  use BlocksterV2Web, :live_component

  # start_position assign used in template for cog icon phx-value-position
end
```

### Phase 6: Remove Obsolete Code

#### 6.1 Remove Section Titles System
- Delete `section_settings` table (migration)
- Remove `SectionSetting` schema
- Remove `get_all_section_titles()`, `update_section_title()` functions
- Remove title editing UI from homepage

#### 6.2 Remove Section-Based Curation
- Remove `get_all_curated_posts()` (grouped by section)
- Remove section validation in CuratedPost changeset
- Remove section column from curated_posts table

#### 6.3 Clean Up Index LiveView
- Remove all section-specific code (`latest_news_posts`, `conversations_posts`, etc.)
- Remove complex `handle_event("load-more")` with category/tag selection
- Remove title editing event handlers
- Remove shop/banner component loading

---

## Implementation Todo List (In Order)

### Step 1: Database Migration - Simplify curated_posts ✅ COMPLETED
```bash
mix ecto.gen.migration simplify_curated_posts
```

- [x] **1.1** Create migration file `priv/repo/migrations/20260118193523_simplify_curated_posts.exs`
  ```elixir
  def up do
    # First, clear all existing curated posts (fresh start)
    execute "DELETE FROM curated_posts"

    # Drop the old unique constraint
    drop_if_exists unique_index(:curated_posts, [:section, :position])

    # Remove section column
    alter table(:curated_posts) do
      remove :section
    end

    # Add new unique constraint on position alone
    create unique_index(:curated_posts, [:position])
  end

  def down do
    drop_if_exists unique_index(:curated_posts, [:position])

    alter table(:curated_posts) do
      add :section, :string
    end

    create unique_index(:curated_posts, [:section, :position])
  end
  ```

- [x] **1.2** Run migration locally: `mix ecto.migrate`

**Notes:**
- Migration file created at `priv/repo/migrations/20260118193523_simplify_curated_posts.exs`
- Migration ran successfully, verified with `mix ecto.migrate`

### Step 2: Update CuratedPost Schema ✅ COMPLETED
- [x] **2.1** Edit `lib/blockster_v2/blog/curated_post.ex`:
  - Remove `field :section, :string`
  - Remove section from changeset cast/validate
  - Remove `validate_inclusion` for section
  - Remove `validate_position_range/1` private function
  - Update unique constraint to just `[:position]`

**Notes:**
- Updated schema to only have `position` and `post_id` fields
- Added `validate_number(:position, greater_than: 0)` to ensure positions are positive
- Updated moduledoc to explain the new position-based curation system

### Step 3: Add New Blog Context Functions ✅ COMPLETED
- [x] **3.1** Add `get_curated_positions_map/0` to `lib/blockster_v2/blog.ex`
- [x] **3.2** Add `list_posts_with_curation/1` to `lib/blockster_v2/blog.ex`
- [x] **3.3** Add helper `merge_posts_with_curation/4` (private function)
- [x] **3.4** Add `set_curated_post/2` to `lib/blockster_v2/blog.ex`
- [x] **3.5** Add `clear_curated_post/1` to `lib/blockster_v2/blog.ex`
- [x] **3.6** Add `clear_all_curation/0` to `lib/blockster_v2/blog.ex`

**Notes:**
- All functions added around line 772-940 in `lib/blockster_v2/blog.ex`
- Added `list_published_posts_with_exclusions/1` helper function for fetching chronological posts
- `list_posts_with_curation/1` implements duplicate prevention by excluding ALL curated post IDs from the chronological query
- The `merge_posts_with_curation/4` uses `:queue` module for efficient post distribution
- Chrono offset calculation accounts for curated posts in previous pages

### Step 4: Auto-Clear Curation on Post Publish ✅ COMPLETED
- [x] **4.1** Modify `create_post/1` in `lib/blockster_v2/blog.ex` - call `clear_all_curation()` when post is published
- [x] **4.2** Modify `update_post/2` in `lib/blockster_v2/blog.ex` - call `clear_all_curation()` when post transitions from unpublished to published
- [x] **4.3** Modify `publish_post/1` in `lib/blockster_v2/blog.ex` - call `clear_all_curation()` when post is published

**Notes:**
- `create_post/1` checks if `post.published_at` is set and clears curation
- `update_post/2` tracks `was_published` state before update and clears if transitioning to published
- `publish_post/1` always clears curation after successful publish

### Step 5: Refactor Homepage LiveView (index.ex) ✅ COMPLETED
- [x] **5.1** Add module attributes for component cycling (added as documentation comments)
- [x] **5.2** Rewrite `mount/3` - use `build_initial_components/0` pattern from category.ex
- [x] **5.3** Add `build_initial_components/0` private function
- [x] **5.4** Add `build_components_batch/2` private function
- [x] **5.5** Rewrite `handle_event("load-more", ...)` - simplified version like category.ex
- [x] **5.6** Update `handle_event("open_post_selector", ...)` - accept global position instead of section/position
- [x] **5.7** Update `handle_event("select_post", ...)` - call `set_curated_post/2` and reload components
- [x] **5.8** Remove section title editing handlers
- [x] **5.9** Remove `get_default_title/1` and `reload_components_with_titles/2`
- [x] **5.10** Remove obsolete assigns
- [x] **5.11** Add new assign: `current_offset` to track pagination position

**Notes:**
- Complete rewrite of `lib/blockster_v2_web/live/post_live/index.ex`
- Component cycle: Three(5) → Four(3) → Five(6) → Six(5) = 19 posts per cycle
- Each component receives `start_position` for global position calculation
- `start_position` values: Three=1, Four=6, Five=9, Six=15 (for first batch)
- Post selector modal retained with simplified position-only approach
- Some compilation warnings about unused module attributes are intentional (documentation)

### Step 6: Update Homepage Template (index.html.heex) ✅ COMPLETED
- [x] **6.1** Remove title editing modal/UI if present
- [x] **6.2** Ensure template works with new component stream structure

**Notes:**
- Added `start_position={Map.get(comp, :start_position)}` to live_component call
- Template structure largely unchanged, just added new attribute

### Step 7: Update Component Templates for Global Position ✅ COMPLETED
- [x] **7.1** Update `posts_three_component.html.heex` - cog icon uses `@start_position + local_idx` for phx-value-position
- [x] **7.2** Update `posts_four_component.html.heex` - same change (uses loop with `Enum.with_index`)
- [x] **7.3** Update `posts_five_component.html.heex` - same change (6 positions: 0-5)
- [x] **7.4** Update `posts_six_component.html.heex` - same change (5 positions: 0-4)
- [x] **7.5** Ensure components accept `start_position` assign (LiveComponents automatically accept all assigns)

**Notes:**
- All 4 component templates updated with consistent pattern
- Cog icon condition changed from `assigns[:current_user] && @current_user.is_admin` to:
  `assigns[:current_user] && @current_user.is_admin && Map.get(assigns, :type) == "home-posts" && Map.get(assigns, :start_position)`
- This ensures cog icons ONLY appear on homepage, not on category/tag/hub pages
- Removed `phx-value-section` attribute entirely (no longer needed)
- Position calculation: `phx-value-position={@start_position + local_idx}` where local_idx is 0-based
- Section title display condition updated to exclude `"home-posts"` type

### Step 8: Cleanup - Remove Obsolete Code ✅ COMPLETED
- [x] **8.1** Delete `lib/blockster_v2/blog/section_setting.ex`
- [x] **8.2** Remove `SectionSetting` alias from `lib/blockster_v2/blog.ex`
- [x] **8.3** Remove section settings functions from Blog: `get_section_title/2`, `get_all_section_titles/0`, `update_section_title/2`
- [x] **8.4** Remove old curation functions from Blog: `get_all_curated_posts/0`, `get_curated_posts_for_section/1`, `update_curated_post_position/3`
- [x] **8.5** (Optional - SKIPPED) Keep `posts_one_component` and `posts_two_component` for potential future use
- [x] **8.6** (Optional - SKIPPED) Keep `posts_one_component` and `posts_two_component` for potential future use

**Notes:**
- Deleted `lib/blockster_v2/blog/section_setting.ex`
- Removed `SectionSetting` alias from blog.ex line 13
- Removed all section settings functions (lines 1049-1087)
- Removed legacy curation functions (lines 977-1047)
- Fixed compilation errors in posts_three_component and posts_four_component (changed `idx` to `local_idx` in token_badge ids)

### Step 9: Database Migration - Drop section_settings Table ✅ COMPLETED
```bash
mix ecto.gen.migration drop_section_settings
```

- [x] **9.1** Create migration:
  ```elixir
  def up do
    drop table(:section_settings)
  end

  def down do
    create table(:section_settings) do
      add :section, :string, null: false
      add :title, :string
      timestamps()
    end
    create unique_index(:section_settings, [:section])
  end
  ```

- [x] **9.2** Run migration: `mix ecto.migrate`

**Notes:**
- Migration file created at `priv/repo/migrations/20260118200032_drop_section_settings.exs`
- Migration ran successfully

### Step 10: Testing
- [ ] **10.1** Start server: `elixir --sname node1 -S mix phx.server`
- [ ] **10.2** Visit homepage - verify posts display chronologically (newest first)
- [ ] **10.3** Scroll down - verify infinite scroll loads more posts without duplicates
- [ ] **10.4** (Admin) Click cog icon - verify post selector opens with correct position
- [ ] **10.5** (Admin) Select a post to curate - verify it appears at the selected position
- [ ] **10.6** (Admin) Verify curated post doesn't appear twice (not at curated position AND natural position)
- [ ] **10.7** Refresh page - verify curation persists
- [ ] **10.8** Create/publish new post - verify all curation is cleared
- [ ] **10.9** Verify BUX balance badges update in real-time

### Step 11: Deploy
- [ ] **11.1** Commit all changes
- [ ] **11.2** Push to branch
- [ ] **11.3** Deploy to staging/production
- [ ] **11.4** Run migrations on production: migrations run automatically via release

---

## Quick Reference: Files to Modify

| Step | File | Action |
|------|------|--------|
| 1 | `priv/repo/migrations/XXXXXX_simplify_curated_posts.exs` | Create |
| 2 | `lib/blockster_v2/blog/curated_post.ex` | Modify |
| 3-4 | `lib/blockster_v2/blog.ex` | Modify |
| 5 | `lib/blockster_v2_web/live/post_live/index.ex` | Major refactor |
| 6 | `lib/blockster_v2_web/live/post_live/index.html.heex` | Modify |
| 7 | `lib/blockster_v2_web/live/post_live/posts_*_component.html.heex` | Modify (4 files) |
| 8 | `lib/blockster_v2/blog/section_setting.ex` | Delete |
| 8 | `lib/blockster_v2_web/live/post_live/posts_one_component.*` | Delete (optional) |
| 8 | `lib/blockster_v2_web/live/post_live/posts_two_component.*` | Delete (optional) |
| 9 | `priv/repo/migrations/XXXXXX_drop_section_settings.exs` | Create |

---

## Testing Checklist
- [ ] Test chronological display without curation
- [ ] Test admin curation at specific position
- [ ] Test curated post removed from natural position (no duplicates)
- [ ] Test curation persists across page loads
- [ ] Test curation clears when new post published
- [ ] Test infinite scroll loads more posts
- [ ] Test no duplicate posts appear across scroll loads
- [ ] Test BUX balance updates work

---

## Files to Modify

| File | Changes |
|------|---------|
| `lib/blockster_v2/blog/curated_post.ex` | Remove section field, simplify validation |
| `lib/blockster_v2/blog.ex` | Add new curation functions, modify create/update_post |
| `lib/blockster_v2_web/live/post_live/index.ex` | Complete refactor to category-style |
| `lib/blockster_v2_web/live/post_live/index.html.heex` | Remove title editing UI |
| `lib/blockster_v2_web/live/post_live/posts_three_component.html.heex` | Add start_position to cog |
| `lib/blockster_v2_web/live/post_live/posts_four_component.html.heex` | Add start_position to cog |
| `lib/blockster_v2_web/live/post_live/posts_five_component.html.heex` | Add start_position to cog |
| `lib/blockster_v2_web/live/post_live/posts_six_component.html.heex` | Add start_position to cog |

### Files to Delete
| File | Reason |
|------|--------|
| `lib/blockster_v2/blog/section_setting.ex` | No longer needed |
| `lib/blockster_v2_web/live/post_live/posts_one_component.*` | Replaced by cycling |
| `lib/blockster_v2_web/live/post_live/posts_two_component.*` | Replaced by cycling |

---

## Rollback Plan

If issues arise:
1. Revert migration (restore `section` column)
2. Revert code changes via git
3. Re-seed `curated_posts` with section data

Keep backup of current `curated_posts` data before migration.

---

## Notes

### Why This Approach?
- **Simpler mental model**: Posts just appear by date, curation is a temporary override
- **Less maintenance**: No need to manually fill 6 sections with 35+ curated posts
- **Fresh content**: New posts automatically appear at the top
- **Admin flexibility**: Can still highlight specific posts when needed

### Edge Cases

#### Duplicate Prevention (Curated Post Appears Twice)
**Scenario**: Admin curates post #15 (chronologically) to position 1.
**Problem**: Without handling, the post would appear at position 1 (curated) AND position 15 (natural).
**Solution**:
- `list_posts_with_curation()` fetches ALL curated post IDs upfront
- ALL curated post IDs are excluded from the chronological query
- Curated posts ONLY appear at their designated positions
- The natural chronological slot is filled by the next eligible post

```
Before curation:
  Pos 1: Post A (newest)
  Pos 15: Post X (the one we want to promote)

After curating Post X to position 1:
  Pos 1: Post X (curated - moved from pos 15)
  Pos 2: Post A (shifted down - was at pos 1)
  Pos 15: Post Y (next in line - Post X excluded from chrono query)
```

#### Other Edge Cases
- **Multiple curated posts at same position**: Unique constraint prevents this
- **Curated post unpublished**: Query filters `where: not is_nil(p.published_at)`
- **Curated post deleted**: FK constraint with ON DELETE CASCADE removes curation
- **No posts available**: Empty state handled in components
- **Curated post outside current page range**: Still excluded from chrono query to prevent it appearing naturally when user scrolls to that position

### Future Enhancements
- Add "pin for X hours" feature with expiry
- Track who curated what and when
- Allow curation within specific components only
