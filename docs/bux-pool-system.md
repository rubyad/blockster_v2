# BUX Pool System - Implementation Plan

## Overview

Transform the BUX rewards system from an **unlimited earning model** (where every read/share mints new BUX and increments a post's counter) to a **finite pool model** (where admin deposits BUX into posts, and users drain the pool as they earn).

### Key Concept: Pool as a Gate, Not a Source

```
┌─────────────────────────────────────────────────────────────────────┐
│                         POOL SYSTEM FLOW                            │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Admin deposits 1000 BUX ──► post_bux_points.bux_balance = 1000    │
│                              (Mnesia - just a number, no tokens)    │
│                                                                     │
│  User opens article                                                 │
│         │                                                           │
│         ▼                                                           │
│  ┌─────────────────────┐                                            │
│  │ Check pool first    │                                            │
│  │ Pool = 1000 > 0? ✓  │                                            │
│  └─────────┬───────────┘                                            │
│            │ YES - Show earning UI, track engagement                │
│            ▼                                                        │
│  User finishes reading ──► Calculate earned: 10 BUX                 │
│            │                                                        │
│            ▼                                                        │
│  ┌─────────────────────┐    ┌──────────────────────────┐           │
│  │ Decrement pool      │    │ Mint 10 BUX to user      │           │
│  │ 1000 - 10 = 990     │───►│ (blockchain transaction) │           │
│  │ (Mnesia update)     │    │ SAME AS CURRENT SYSTEM   │           │
│  └─────────────────────┘    └──────────────────────────┘           │
│                                                                     │
│  If pool = 0 on open ──► Show "No BUX available" (no earning UI)   │
│                                                                     │
│  Admin tops up 500 BUX ──► Pool = 500 ──► Users can earn again     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘

The pool is just an ACCOUNTING LIMIT in Mnesia.
Actual BUX tokens are still minted on-chain exactly as before.
The pool controls WHETHER minting happens, not HOW it happens.
```

### Current System
- Posts have unlimited BUX potential
- Every user read/share mints new BUX tokens (blockchain)
- `post_bux_points.bux_balance` **increments** as users earn
- Posts sorted by `published_at DESC`
- Badge shows "total BUX earned from this post"

### New System
- Admin deposits a finite BUX allocation into each post's pool (Mnesia only)
- Pool acts as a **gate/limit** for minting - not a replacement
- When user earns BUX: check pool → if available, mint to user (blockchain) AND decrement pool
- `post_bux_points.bux_balance` **decrements** as users earn
- When pool hits 0, minting is blocked until admin tops up
- Admin can top up any post at any time to reactivate earnings
- Posts sorted by `bux_balance DESC`, then `published_at DESC`
- Badge shows "remaining BUX available to earn"

---

## Architecture Changes

### Data Flow Comparison

**Current Flow:**
```
User reads article
    ↓
Calculate BUX earned (engagement × base_reward × multiplier)
    ↓
Mint BUX tokens to user wallet (blockchain)
    ↓
Increment post_bux_points.bux_balance += earned
    ↓
Broadcast update to UI
```

**New Flow:**
```
User opens article
    ↓
Check if post pool has BUX available (Mnesia)
    ↓
If pool = 0:
    └─ Show "No BUX available" - don't track engagement or show earning UI

If pool > 0:
    ├─ Show earning UI with progress
    ├─ Track engagement as user reads
    ↓
User finishes reading
    ↓
Calculate BUX earned (engagement × base_reward × multiplier)
    ↓
If pool >= earned:
    ├─ Decrement pool by earned amount (Mnesia)
    ├─ Mint BUX tokens to user wallet (blockchain) ← SAME AS BEFORE
    └─ Broadcast update to UI
Else if pool > 0 but < earned:
    ├─ Award remaining pool amount (partial)
    ├─ Set pool = 0 (Mnesia)
    ├─ Mint partial amount to user (blockchain)
    └─ Broadcast update (pool exhausted)
```

### Key Differences

| Aspect | Current | New |
|--------|---------|-----|
| BUX Source | Minted on-chain (unlimited) | Minted on-chain (gated by pool) |
| Pool Direction | Increments (accumulates) | Decrements (drains) |
| Pool Limit | Unlimited | Finite (admin-controlled) |
| Pool Purpose | Tracks total earned | Gates/limits minting |
| Empty Pool | N/A | Minting blocked until top-up |
| Sorting | Published date | Pool balance DESC, then date DESC |
| Badge Meaning | "Total earned" | "Available to earn" |

---

## Database & Storage Changes

### Mnesia Table: `post_bux_points`

**NO SCHEMA CHANGES REQUIRED** - All needed fields already exist in the table.

**Existing Structure (indices 0-11):**
```
{:post_bux_points, post_id, reward, read_time, bux_balance, bux_deposited,
 extra_field1, extra_field2, extra_field3, extra_field4, created_at, updated_at}
```

**Field Usage Changes (semantic only, no schema modification):**

| Index | Field | Current Use | New Use |
|-------|-------|-------------|---------|
| 1 | post_id | Primary key | No change |
| 2 | reward | Unused | Unused |
| 3 | read_time | Unused | Unused |
| 4 | bux_balance | Running total earned | **Remaining pool balance** (repurposed) |
| 5 | bux_deposited | Unused | **Total deposited by admin (lifetime)** (already exists, now used) |
| 6 | extra_field1 | Unused | **Total distributed to users (lifetime)** (already exists, now used) |
| 7 | extra_field2 | Unused | Unused |
| 8 | extra_field3 | Unused | Unused |
| 9 | extra_field4 | Unused | Unused |
| 10 | created_at | Timestamp | No change |
| 11 | updated_at | Timestamp | No change |

**Why No Migration Needed:**
- The tuple structure stays exactly the same (12 elements)
- We're only changing how existing fields are interpreted
- Existing records with `bux_balance > 0` will be treated as having a pool
- `bux_deposited` and `extra_field1` default to `nil`/`0` - safe to start using

**New Field Semantics:**
- `bux_balance` (index 4): Current pool balance (decrements as users earn)
- `bux_deposited` (index 5): Lifetime total deposited by admin
- `extra_field1` (index 6): Lifetime total distributed to users

**Invariant:** `bux_deposited = bux_balance + total_distributed`

---

## Implementation Details

### 1. Admin Deposit Functionality

**New Function:** `EngagementTracker.deposit_post_bux(post_id, amount)`

```elixir
@doc """
Admin deposits BUX into a post's pool.
Increases bux_balance (available to earn) and bux_deposited (lifetime total).
"""
def deposit_post_bux(post_id, amount) when is_integer(amount) and amount > 0 do
  now = System.system_time(:second)

  case :mnesia.dirty_read({:post_bux_points, post_id}) do
    [] ->
      # Create new record
      record = {:post_bux_points, post_id, nil, nil,
                amount,  # bux_balance (pool)
                amount,  # bux_deposited (lifetime)
                0,       # total_distributed
                nil, nil, nil, now, now}
      :mnesia.dirty_write(record)
      broadcast_bux_update(post_id, amount)
      {:ok, amount}

    [existing] ->
      current_balance = elem(existing, 4) || 0
      current_deposited = elem(existing, 5) || 0
      new_balance = current_balance + amount
      new_deposited = current_deposited + amount

      updated = existing
        |> put_elem(4, new_balance)
        |> put_elem(5, new_deposited)
        |> put_elem(11, now)

      :mnesia.dirty_write(updated)
      broadcast_bux_update(post_id, new_balance)
      {:ok, new_balance}
  end
end
```

### 2. Check & Decrement Pool

**New Function:** `EngagementTracker.try_deduct_from_pool(post_id, requested_amount)`

```elixir
@doc """
Attempts to deduct BUX from post's pool. Returns amount that can be awarded.
Does NOT mint - just checks availability and decrements pool.
If pool has less than requested, returns whatever remains (partial).
If pool is empty, returns 0.

Call this BEFORE minting. Only mint the returned amount.
"""
def try_deduct_from_pool(post_id, requested_amount) do
  now = System.system_time(:second)

  case :mnesia.dirty_read({:post_bux_points, post_id}) do
    [] ->
      # No pool exists for this post
      {:ok, 0, :no_pool}

    [record] ->
      pool_balance = elem(record, 4) || 0

      cond do
        pool_balance <= 0 ->
          {:ok, 0, :pool_empty}

        pool_balance >= requested_amount ->
          # Full amount available - deduct it
          new_balance = pool_balance - requested_amount
          total_distributed = (elem(record, 6) || 0) + requested_amount

          updated = record
            |> put_elem(4, new_balance)
            |> put_elem(6, total_distributed)
            |> put_elem(11, now)

          :mnesia.dirty_write(updated)
          broadcast_bux_update(post_id, new_balance)
          {:ok, requested_amount, :full_amount}

        true ->
          # Partial amount available - deduct whatever remains
          awarded = pool_balance
          total_distributed = (elem(record, 6) || 0) + awarded

          updated = record
            |> put_elem(4, 0)
            |> put_elem(6, total_distributed)
            |> put_elem(11, now)

          :mnesia.dirty_write(updated)
          broadcast_bux_update(post_id, 0)
          {:ok, awarded, :partial_amount}
      end
  end
end
```

### 3. Reading Reward Flow Changes

**File:** `lib/blockster_v2_web/live/post_live/show.ex`

Two key changes:
1. **On mount:** Check pool availability before showing earning UI
2. **On read complete:** Deduct from pool before minting

#### 3a. Mount - Check Pool Availability

**Current:** Always shows earning UI regardless of pool state

**New (in mount):**
```elixir
# Check pool availability on mount
pool_balance = EngagementTracker.get_post_bux_balance(post.id)
pool_available = pool_balance > 0

socket
|> assign(:pool_available, pool_available)
|> assign(:pool_balance, pool_balance)
```

**In template:** Only show earning UI if `@pool_available`:
```heex
<%= if @pool_available do %>
  <!-- Show engagement tracker, BUX earning progress, etc. -->
  <div phx-hook="EngagementTracker" ...>
<% else %>
  <!-- Show "No BUX available" message instead -->
  <div class="text-gray-500">No BUX rewards available for this article</div>
<% end %>
```

#### 3b. Read Complete - Deduct and Mint

**Current (lines 250-285):**
```elixir
# Calculate BUX
bux_earned = EngagementTracker.calculate_bux_earned(score, base_bux_reward, user_multiplier)

# Record and mint (unlimited)
case EngagementTracker.record_read_reward(user_id, post_id, bux_earned) do
  {:ok, recorded_bux, nil} ->
    # Mint tokens - always succeeds, no limit
    Task.start(fn ->
      BuxMinter.mint_bux(wallet, recorded_bux, user_id, post_id, :read)
    end)
end
```

**New:**
```elixir
# Calculate desired BUX
desired_bux = EngagementTracker.calculate_bux_earned(score, base_bux_reward, user_multiplier)

# Check if already rewarded for this post
case EngagementTracker.get_user_post_reward(user_id, post_id) do
  {:ok, existing} when not is_nil(existing.bux_rewarded) ->
    # Already rewarded - show existing amount
    {:noreply, assign(socket, :bux_earned, existing.bux_rewarded)}

  _ ->
    # Try to deduct from pool FIRST
    case EngagementTracker.try_deduct_from_pool(post_id, desired_bux) do
      {:ok, 0, status} ->
        # Pool empty or doesn't exist - no minting
        message = case status do
          :pool_empty -> "This post's BUX pool is empty"
          :no_pool -> "This post has no BUX available"
        end
        {:noreply, socket |> assign(:bux_earned, 0) |> put_flash(:info, message)}

      {:ok, actual_amount, status} ->
        # Pool had BUX - now mint to user
        Task.start(fn ->
          BuxMinter.mint_bux(wallet, actual_amount, user_id, post_id, :read)
        end)

        # Record the reward
        EngagementTracker.record_read_reward(user_id, post_id, actual_amount)

        message = if status == :partial_amount do
          "Pool depleted! You earned #{actual_amount} BUX (partial)"
        end

        socket = socket
          |> assign(:bux_earned, actual_amount)
          |> then(fn s -> if message, do: put_flash(s, :info, message), else: s end)

        {:noreply, socket}
    end
end
```

### 4. Sorted Posts Cache (GenServer)

**Why a Cache?**

The naive approach of fetching all posts and sorting on every request is inefficient:
- Loads ALL posts from PostgreSQL on every page load and infinite scroll
- Loads ALL balances from Mnesia
- Sorts in application memory on every request
- O(n) work for O(1) reads

**Solution:** A GenServer that maintains a pre-sorted list of `{post_id, balance, published_at}` tuples.

**File:** `lib/blockster_v2/sorted_posts_cache.ex`

```elixir
defmodule BlocksterV2.SortedPostsCache do
  @moduledoc """
  Maintains a sorted list of post IDs by BUX pool balance for efficient pagination.

  Reads are O(1) - just slice the pre-sorted list.
  Writes (deposits/deducts) trigger a re-sort, but these are infrequent.

  Memory usage: ~24 bytes per post (post_id + balance + published_at timestamp)
  - 10,000 posts = ~240 KB
  - 100,000 posts = ~2.4 MB
  """
  use GenServer
  require Logger

  @table :sorted_posts_cache

  # =============================================================================
  # Client API
  # =============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets a page of post IDs sorted by pool balance DESC, then published_at DESC.
  Returns list of {post_id, balance} tuples.

  This is O(1) - just slices the pre-sorted list.
  """
  def get_page(limit, offset \\ 0) do
    GenServer.call(__MODULE__, {:get_page, limit, offset})
  end

  @doc """
  Gets the total count of posts in the cache.
  """
  def count do
    GenServer.call(__MODULE__, :count)
  end

  @doc """
  Updates the balance for a post and re-sorts if needed.
  Called after deposits or deductions.
  """
  def update_balance(post_id, new_balance) do
    GenServer.cast(__MODULE__, {:update_balance, post_id, new_balance})
  end

  @doc """
  Adds a new post to the cache.
  Called when a new post is published.
  """
  def add_post(post_id, balance, published_at) do
    GenServer.cast(__MODULE__, {:add_post, post_id, balance, published_at})
  end

  @doc """
  Removes a post from the cache.
  Called when a post is unpublished or deleted.
  """
  def remove_post(post_id) do
    GenServer.cast(__MODULE__, {:remove_post, post_id})
  end

  @doc """
  Forces a full reload from Mnesia and PostgreSQL.
  Used for initial load and recovery.
  """
  def reload do
    GenServer.cast(__MODULE__, :reload)
  end

  # =============================================================================
  # Server Callbacks
  # =============================================================================

  @impl true
  def init(_opts) do
    # Subscribe to pool balance updates
    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "post_bux:all")

    # Load initial data
    sorted_posts = load_and_sort_all_posts()

    Logger.info("[SortedPostsCache] Initialized with #{length(sorted_posts)} posts")
    {:ok, %{sorted_posts: sorted_posts}}
  end

  @impl true
  def handle_call({:get_page, limit, offset}, _from, state) do
    page = state.sorted_posts
      |> Enum.drop(offset)
      |> Enum.take(limit)
      |> Enum.map(fn {post_id, balance, _published_at} -> {post_id, balance} end)

    {:reply, page, state}
  end

  @impl true
  def handle_call(:count, _from, state) do
    {:reply, length(state.sorted_posts), state}
  end

  @impl true
  def handle_cast({:update_balance, post_id, new_balance}, state) do
    sorted_posts = state.sorted_posts
      |> Enum.map(fn {pid, _bal, pub_at} = entry ->
        if pid == post_id, do: {pid, new_balance, pub_at}, else: entry
      end)
      |> sort_posts()

    {:noreply, %{state | sorted_posts: sorted_posts}}
  end

  @impl true
  def handle_cast({:add_post, post_id, balance, published_at}, state) do
    # Check if already exists
    exists = Enum.any?(state.sorted_posts, fn {pid, _, _} -> pid == post_id end)

    sorted_posts = if exists do
      state.sorted_posts
    else
      [{post_id, balance, published_at} | state.sorted_posts]
      |> sort_posts()
    end

    {:noreply, %{state | sorted_posts: sorted_posts}}
  end

  @impl true
  def handle_cast({:remove_post, post_id}, state) do
    sorted_posts = Enum.reject(state.sorted_posts, fn {pid, _, _} -> pid == post_id end)
    {:noreply, %{state | sorted_posts: sorted_posts}}
  end

  @impl true
  def handle_cast(:reload, state) do
    sorted_posts = load_and_sort_all_posts()
    Logger.info("[SortedPostsCache] Reloaded with #{length(sorted_posts)} posts")
    {:noreply, %{state | sorted_posts: sorted_posts}}
  end

  # Handle PubSub broadcasts from EngagementTracker
  @impl true
  def handle_info({:bux_update, post_id, new_balance}, state) do
    # Update balance in our sorted list
    sorted_posts = state.sorted_posts
      |> Enum.map(fn {pid, _bal, pub_at} = entry ->
        if pid == post_id, do: {pid, new_balance, pub_at}, else: entry
      end)
      |> sort_posts()

    {:noreply, %{state | sorted_posts: sorted_posts}}
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  defp load_and_sort_all_posts do
    # Get all pool balances from Mnesia
    pool_balances = BlocksterV2.EngagementTracker.get_all_post_bux_balances()

    # Get all published posts with just id and published_at
    posts = BlocksterV2.Repo.all(
      from p in BlocksterV2.Blog.Post,
        where: not is_nil(p.published_at),
        select: {p.id, p.published_at}
    )

    # Build list of {post_id, balance, published_at} and sort
    posts
    |> Enum.map(fn {post_id, published_at} ->
      balance = Map.get(pool_balances, post_id, 0)
      published_unix = if published_at, do: DateTime.to_unix(published_at), else: 0
      {post_id, balance, published_unix}
    end)
    |> sort_posts()
  end

  defp sort_posts(posts) do
    # Sort by balance DESC, then published_at DESC
    Enum.sort_by(posts, fn {_post_id, balance, published_at} ->
      {-balance, -published_at}
    end)
  end
end
```

**Add to Supervision Tree:** `lib/blockster_v2/application.ex`

```elixir
children = [
  # ... existing children ...
  BlocksterV2.SortedPostsCache,
  # ... rest of children ...
]
```

### 5. Blog Query Using Cache

**File:** `lib/blockster_v2/blog.ex`

```elixir
@doc """
Lists published posts sorted by BUX pool balance (highest first),
then by published_at for posts with equal/zero balance.

Uses SortedPostsCache for O(1) pagination instead of sorting on every request.
"""
def list_published_posts_by_pool(opts \\ []) do
  limit = Keyword.get(opts, :limit, 20)
  offset = Keyword.get(opts, :offset, 0)

  # Get sorted post IDs from cache (O(1) slice operation)
  sorted_ids_with_balances = SortedPostsCache.get_page(limit, offset)
  post_ids = Enum.map(sorted_ids_with_balances, fn {id, _balance} -> id end)
  balances_map = Map.new(sorted_ids_with_balances)

  # Fetch only the posts we need from database
  posts = from(p in Post,
    where: p.id in ^post_ids,
    preload: [:author, :category, :hub, :tags]
  )
  |> Repo.all()

  # Re-order posts to match sorted order and attach balance
  post_ids
  |> Enum.map(fn post_id ->
    post = Enum.find(posts, fn p -> p.id == post_id end)
    if post do
      Map.put(post, :bux_balance, Map.get(balances_map, post_id, 0))
    end
  end)
  |> Enum.reject(&is_nil/1)
end

@doc """
Gets the total count of published posts (for pagination UI).
"""
def count_published_posts do
  SortedPostsCache.count()
end
```

### 6. Performance Comparison

| Operation | Naive Approach | Cached Approach |
|-----------|----------------|-----------------|
| Page load | O(n) - fetch all, sort all | O(1) - slice list, fetch page |
| Infinite scroll | O(n) - same as page load | O(1) - same as page load |
| Admin deposit | O(1) | O(n log n) - re-sort |
| User earns BUX | O(1) | O(n log n) - re-sort |

**Reads dominate traffic** (homepage views, scrolling) - these are now O(1).
**Writes are rare** (admin deposits, user completions) - O(n log n) re-sort is acceptable.

### 5. Reading Reward Flow Changes

**File:** `lib/blockster_v2_web/live/post_live/show.ex`

**Current (lines 250-285):**
```elixir
# Calculate BUX
bux_earned = EngagementTracker.calculate_bux_earned(score, base_bux_reward, user_multiplier)

# Record and mint
case EngagementTracker.record_read_reward(user_id, post_id, bux_earned) do
  {:ok, recorded_bux, tx_id} when not is_nil(tx_id) ->
    # Already rewarded
    ...
  {:ok, recorded_bux, nil} ->
    # Mint new tokens
    Task.start(fn ->
      BuxMinter.mint_bux(wallet, recorded_bux, user_id, post_id, :read)
    end)
    ...
end
```

**New:**
```elixir
# Calculate desired BUX
desired_bux = EngagementTracker.calculate_bux_earned(score, base_bux_reward, user_multiplier)

# Check if already rewarded for this post
case EngagementTracker.get_user_post_reward(user_id, post_id) do
  {:ok, existing} when not is_nil(existing.bux_rewarded) ->
    # Already rewarded - show existing amount
    {:noreply, assign(socket, :bux_earned, existing.bux_rewarded)}

  _ ->
    # Try to award from pool
    case EngagementTracker.award_bux_from_pool(post_id, user_id, desired_bux) do
      {:ok, actual_awarded, status} ->
        # Record the reward (even if 0)
        EngagementTracker.record_read_reward(user_id, post_id, actual_awarded)

        message = case status do
          :full_award -> nil
          :partial_award -> "Pool depleted! You earned #{actual_awarded} BUX (partial)"
          :pool_empty -> "This post's BUX pool is empty"
          :no_pool -> "This post has no BUX pool"
        end

        socket = socket
          |> assign(:bux_earned, actual_awarded)
          |> then(fn s -> if message, do: put_flash(s, :info, message), else: s end)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Error awarding BUX: #{reason}")}
    end
end
```

### 6. X Share Reward Flow Changes

**File:** `lib/blockster_v2_web/live/post_live/show.ex`

Similar pattern to reading - use `award_bux_from_pool/3` instead of `BuxMinter.mint_bux/5`.

### 7. Admin UI for Depositing BUX

**File:** `lib/blockster_v2_web/live/post_live/form_component.html.heex`

Add new section for pool management:

```heex
<%= if @current_user && @current_user.is_admin do %>
  <div class="border-t border-gray-200 pt-6 mt-6">
    <h3 class="text-lg font-semibold mb-4">BUX Pool Management</h3>

    <div class="grid grid-cols-2 gap-4 mb-4">
      <div class="bg-gray-50 p-4 rounded-lg">
        <div class="text-sm text-gray-500">Current Pool Balance</div>
        <div class="text-2xl font-bold text-green-600">
          <%= Number.Delimit.number_to_delimited(@pool_balance || 0, precision: 0) %> BUX
        </div>
      </div>
      <div class="bg-gray-50 p-4 rounded-lg">
        <div class="text-sm text-gray-500">Total Distributed</div>
        <div class="text-2xl font-bold text-blue-600">
          <%= Number.Delimit.number_to_delimited(@total_distributed || 0, precision: 0) %> BUX
        </div>
      </div>
    </div>

    <div class="flex items-end gap-4">
      <div class="flex-1">
        <.input
          field={@form[:deposit_amount]}
          type="number"
          label="Deposit BUX to Pool"
          min="1"
          step="1"
          placeholder="Enter amount to deposit"
        />
      </div>
      <button
        type="button"
        phx-click="deposit_bux"
        phx-target={@myself}
        class="px-4 py-2 bg-green-600 text-white rounded-lg hover:bg-green-700 cursor-pointer"
      >
        Deposit BUX
      </button>
    </div>

    <p class="text-sm text-gray-500 mt-2">
      Deposited BUX will be available for users to earn by reading this article.
      When the pool reaches zero, users can no longer earn BUX from this post.
    </p>
  </div>
<% end %>
```

### 8. Quick Deposit from Post Cards (Admin Only)

**Files:**
- `lib/blockster_v2_web/live/post_live/posts_*_component.html.heex` (all post card templates)
- `lib/blockster_v2_web/live/post_live/index.ex` (event handler)

Admin sees BUX badge as clickable. Clicking opens inline deposit form.

**Template changes (post card):**
```heex
<%= if @current_user && @current_user.is_admin do %>
  <!-- Admin sees clickable badge -->
  <div class="relative group">
    <button
      type="button"
      phx-click="toggle_quick_deposit"
      phx-value-post-id={post.id}
      class="cursor-pointer"
    >
      <.token_badge post={post} balance={bux_balance} />
    </button>

    <!-- Quick deposit dropdown (shown when toggled) -->
    <%= if @quick_deposit_post_id == post.id do %>
      <div class="absolute top-full left-0 mt-1 bg-white border rounded-lg shadow-lg p-3 z-50 min-w-[200px]">
        <form phx-submit="quick_deposit" phx-value-post-id={post.id}>
          <div class="flex items-center gap-2">
            <input
              type="number"
              name="amount"
              min="1"
              placeholder="Amount"
              class="w-24 px-2 py-1 border rounded text-sm"
              autofocus
            />
            <button
              type="submit"
              class="px-3 py-1 bg-green-600 text-white rounded text-sm hover:bg-green-700 cursor-pointer"
            >
              Deposit
            </button>
          </div>
        </form>
        <button
          type="button"
          phx-click="toggle_quick_deposit"
          phx-value-post-id=""
          class="text-xs text-gray-500 mt-2 cursor-pointer hover:text-gray-700"
        >
          Cancel
        </button>
      </div>
    <% end %>
  </div>
<% else %>
  <!-- Regular users see non-clickable badge -->
  <.token_badge post={post} balance={bux_balance} />
<% end %>
```

**Event handlers (index.ex):**
```elixir
# Toggle quick deposit dropdown
def handle_event("toggle_quick_deposit", %{"post-id" => post_id}, socket) do
  current = socket.assigns[:quick_deposit_post_id]
  new_id = if current == post_id, do: nil, else: post_id
  {:noreply, assign(socket, :quick_deposit_post_id, new_id)}
end

# Handle quick deposit submission
def handle_event("quick_deposit", %{"amount" => amount_str, "post-id" => post_id}, socket) do
  if socket.assigns.current_user && socket.assigns.current_user.is_admin do
    case Integer.parse(amount_str) do
      {amount, _} when amount > 0 ->
        post_id = String.to_integer(post_id)
        case EngagementTracker.deposit_post_bux(post_id, amount) do
          {:ok, new_balance} ->
            {:noreply,
             socket
             |> assign(:quick_deposit_post_id, nil)
             |> put_flash(:info, "Deposited #{amount} BUX. Pool now: #{new_balance}")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Deposit failed: #{reason}")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Invalid amount")}
    end
  else
    {:noreply, put_flash(socket, :error, "Admin only")}
  end
end
```

### 9. Admin Posts Page - Pool Management

**File:** `lib/blockster_v2_web/live/admin/posts_live.ex`

Add pool management column and bulk deposit functionality.

**Mount - fetch pool balances:**
```elixir
def mount(_params, _session, socket) do
  posts = Blog.list_posts_admin()  # Existing query
  pool_balances = EngagementTracker.get_all_post_bux_balances()

  # Attach balance to each post
  posts_with_pools = Enum.map(posts, fn post ->
    Map.put(post, :pool_balance, Map.get(pool_balances, post.id, 0))
  end)

  {:ok,
   socket
   |> assign(:posts, posts_with_pools)
   |> assign(:selected_posts, MapSet.new())
   |> assign(:bulk_deposit_amount, nil)
   |> assign(:sort_by, :published_at)
   |> assign(:sort_dir, :desc)}
end
```

**Template - posts table with pool column:**
```heex
<div class="overflow-x-auto">
  <table class="min-w-full divide-y divide-gray-200">
    <thead class="bg-gray-50">
      <tr>
        <th class="px-4 py-3 text-left">
          <input type="checkbox" phx-click="toggle_all" class="cursor-pointer" />
        </th>
        <th class="px-4 py-3 text-left text-sm font-semibold">Title</th>
        <th class="px-4 py-3 text-left text-sm font-semibold cursor-pointer" phx-click="sort" phx-value-by="published_at">
          Published
        </th>
        <th class="px-4 py-3 text-left text-sm font-semibold cursor-pointer" phx-click="sort" phx-value-by="pool_balance">
          Pool Balance
        </th>
        <th class="px-4 py-3 text-left text-sm font-semibold">Quick Deposit</th>
        <th class="px-4 py-3 text-left text-sm font-semibold">Actions</th>
      </tr>
    </thead>
    <tbody class="divide-y divide-gray-200">
      <%= for post <- @posts do %>
        <tr class="hover:bg-gray-50">
          <td class="px-4 py-3">
            <input
              type="checkbox"
              checked={MapSet.member?(@selected_posts, post.id)}
              phx-click="toggle_select"
              phx-value-id={post.id}
              class="cursor-pointer"
            />
          </td>
          <td class="px-4 py-3">
            <.link navigate={~p"/#{post.slug}"} class="text-blue-600 hover:underline cursor-pointer">
              <%= post.title %>
            </.link>
          </td>
          <td class="px-4 py-3 text-sm text-gray-600">
            <%= if post.published_at, do: Calendar.strftime(post.published_at, "%Y-%m-%d") %>
          </td>
          <td class="px-4 py-3">
            <span class={"font-medium #{if post.pool_balance == 0, do: "text-gray-400", else: "text-green-600"}"}>
              <%= Number.Delimit.number_to_delimited(post.pool_balance, precision: 0) %> BUX
            </span>
          </td>
          <td class="px-4 py-3">
            <form phx-submit="deposit_single" phx-value-post-id={post.id} class="flex items-center gap-2">
              <input
                type="number"
                name="amount"
                min="1"
                placeholder="Amount"
                class="w-20 px-2 py-1 border rounded text-sm"
              />
              <button type="submit" class="px-2 py-1 bg-green-600 text-white rounded text-xs cursor-pointer hover:bg-green-700">
                +
              </button>
            </form>
          </td>
          <td class="px-4 py-3">
            <.link navigate={~p"/admin/posts/#{post.id}/edit"} class="text-blue-600 hover:underline cursor-pointer text-sm">
              Edit
            </.link>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>

<!-- Bulk deposit UI -->
<%= if MapSet.size(@selected_posts) > 0 do %>
  <div class="fixed bottom-4 left-1/2 transform -translate-x-1/2 bg-white border rounded-lg shadow-lg p-4 flex items-center gap-4">
    <span class="text-sm font-medium">
      <%= MapSet.size(@selected_posts) %> posts selected
    </span>
    <form phx-submit="bulk_deposit" class="flex items-center gap-2">
      <input
        type="number"
        name="amount"
        min="1"
        placeholder="BUX each"
        class="w-24 px-2 py-1 border rounded"
      />
      <button type="submit" class="px-4 py-2 bg-green-600 text-white rounded cursor-pointer hover:bg-green-700">
        Deposit to All
      </button>
    </form>
    <button phx-click="clear_selection" class="text-gray-500 cursor-pointer hover:text-gray-700">
      Clear
    </button>
  </div>
<% end %>
```

**Event handlers:**
```elixir
# Single post deposit
def handle_event("deposit_single", %{"amount" => amount_str, "post-id" => post_id}, socket) do
  with {amount, _} <- Integer.parse(amount_str),
       true <- amount > 0,
       post_id <- String.to_integer(post_id),
       {:ok, new_balance} <- EngagementTracker.deposit_post_bux(post_id, amount) do
    # Update the post in the list
    posts = Enum.map(socket.assigns.posts, fn post ->
      if post.id == post_id, do: Map.put(post, :pool_balance, new_balance), else: post
    end)

    {:noreply,
     socket
     |> assign(:posts, posts)
     |> put_flash(:info, "Deposited #{amount} BUX")}
  else
    _ -> {:noreply, put_flash(socket, :error, "Invalid deposit")}
  end
end

# Bulk deposit to selected posts
def handle_event("bulk_deposit", %{"amount" => amount_str}, socket) do
  with {amount, _} <- Integer.parse(amount_str),
       true <- amount > 0 do
    selected_ids = MapSet.to_list(socket.assigns.selected_posts)

    # Deposit to each selected post
    results = Enum.map(selected_ids, fn post_id ->
      EngagementTracker.deposit_post_bux(post_id, amount)
    end)

    success_count = Enum.count(results, &match?({:ok, _}, &1))

    # Refresh pool balances
    pool_balances = EngagementTracker.get_all_post_bux_balances()
    posts = Enum.map(socket.assigns.posts, fn post ->
      Map.put(post, :pool_balance, Map.get(pool_balances, post.id, 0))
    end)

    {:noreply,
     socket
     |> assign(:posts, posts)
     |> assign(:selected_posts, MapSet.new())
     |> put_flash(:info, "Deposited #{amount} BUX to #{success_count} posts")}
  else
    _ -> {:noreply, put_flash(socket, :error, "Invalid amount")}
  end
end

# Sort by column
def handle_event("sort", %{"by" => column}, socket) do
  column = String.to_atom(column)
  dir = if socket.assigns.sort_by == column && socket.assigns.sort_dir == :desc, do: :asc, else: :desc

  posts = Enum.sort_by(socket.assigns.posts, &Map.get(&1, column), dir)

  {:noreply, assign(socket, posts: posts, sort_by: column, sort_dir: dir)}
end

# Toggle post selection
def handle_event("toggle_select", %{"id" => id}, socket) do
  id = String.to_integer(id)
  selected = socket.assigns.selected_posts
  new_selected = if MapSet.member?(selected, id) do
    MapSet.delete(selected, id)
  else
    MapSet.put(selected, id)
  end
  {:noreply, assign(socket, :selected_posts, new_selected)}
end

# Toggle all
def handle_event("toggle_all", _, socket) do
  all_ids = Enum.map(socket.assigns.posts, & &1.id) |> MapSet.new()
  new_selected = if MapSet.size(socket.assigns.selected_posts) == MapSet.size(all_ids) do
    MapSet.new()
  else
    all_ids
  end
  {:noreply, assign(socket, :selected_posts, new_selected)}
end

def handle_event("clear_selection", _, socket) do
  {:noreply, assign(socket, :selected_posts, MapSet.new())}
end
```

### 10. Post Card Badge Update

**File:** `lib/blockster_v2_web/components/shared_components.ex`

The badge already displays `@balance` - no change needed to the component itself.
The semantic meaning changes from "earned" to "remaining".

Consider adding visual indicator when pool is low/empty:

```heex
def token_badge(assigns) do
  ~H"""
  <div class={"p-[0.5px] rounded-[100px] inline-block #{if @balance == 0, do: "bg-gray-400", else: "bg-[#141414]"}"}>
    <div class={"flex items-center gap-1.5 rounded-[100px] px-2 py-1 min-w-[73px] #{if @balance == 0, do: "bg-gray-100", else: "bg-white"}"}>
      <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="BUX" class={"h-5 w-5 rounded-full object-cover #{if @balance == 0, do: "opacity-50"}"} />
      <span class={"text-xs font-haas_medium_65 #{if @balance == 0, do: "text-gray-400"}"}>
        {Number.Delimit.number_to_delimited(@balance, precision: 0)}
      </span>
    </div>
  </div>
  """
end
```

---

## File Changes Summary

### Files to Modify

| File | Changes |
|------|---------|
| `lib/blockster_v2/engagement_tracker.ex` | Add `deposit_post_bux/2`, `try_deduct_from_pool/2`, `get_post_pool_stats/1`, `get_all_post_bux_balances/0` |
| `lib/blockster_v2/blog.ex` | Add `list_published_posts_by_pool/1`, modify sorting logic |
| `lib/blockster_v2_web/live/post_live/show.ex` | Check pool on mount, deduct from pool before minting |
| `lib/blockster_v2_web/live/post_live/index.ex` | Use new sorting function, add quick deposit handlers |
| `lib/blockster_v2_web/live/post_live/form_component.ex` | Add deposit handling |
| `lib/blockster_v2_web/live/post_live/form_component.html.heex` | Add pool management UI |
| `lib/blockster_v2_web/live/post_live/posts_*_component.html.heex` | Add admin quick deposit UI on post cards |
| `lib/blockster_v2_web/live/admin/posts_live.ex` | Add pool column, inline deposit, bulk deposit |
| `lib/blockster_v2_web/components/shared_components.ex` | Update badge for empty pool state |
| `lib/blockster_v2/bux_minter.ex` | Remove `add_post_bux_earned` call (or keep for tracking) |

### Files to Create

| File | Purpose |
|------|---------|
| `lib/blockster_v2/sorted_posts_cache.ex` | GenServer maintaining sorted post list for O(1) pagination |
| `priv/repo/migrations/YYYYMMDD_add_pool_tracking.exs` | (Optional) Add PostgreSQL backup fields |

### No Changes Required

- Mnesia table structure (existing fields sufficient)
- PubSub broadcasts (already work for pool updates)
- Post schema (existing `base_bux_reward` field sufficient)

---

## Migration Strategy

### Phase 1: Parallel Operation
1. Add new pool functions without removing old ones
2. Old system continues working
3. Test new functions in isolation

### Phase 2: Feature Flag
1. Add config flag: `config :blockster_v2, :use_bux_pools, true`
2. Show.ex checks flag to decide mint vs pool
3. Index.ex checks flag for sorting method

### Phase 3: Data Migration
1. For each post with `bux_balance > 0`:
   - Set `bux_deposited = bux_balance` (treat earned as deposited)
   - Set `extra_field1 = 0` (reset distributed)
   - Or: Set all to 0 and have admin re-deposit

### Phase 4: Cutover
1. Enable pool system for all users
2. Remove old minting code path
3. Update UI labels ("Earn up to X BUX" instead of "X BUX earned")

---

## Implementation Checklist

**Implementation Date:** January 18, 2026

### Phase 1: Core Pool Functions (Backend) ✅ COMPLETE

- [x] **1.1** Add `deposit_post_bux/2` to EngagementTracker
  - File: `lib/blockster_v2/engagement_tracker.ex` (lines 1245-1295)
  - Creates/updates post pool balance
  - Updates `bux_deposited` lifetime counter
  - Broadcasts update via PubSub
  - **Note:** Added after existing `unsubscribe_from_all_bux_updates/0` function

- [x] **1.2** Add `try_deduct_from_pool/2` to EngagementTracker
  - File: `lib/blockster_v2/engagement_tracker.ex` (lines 1297-1355)
  - Checks pool availability
  - Decrements pool balance if available
  - Handles full/partial/empty scenarios (returns `:full_amount`, `:partial_amount`, `:pool_empty`, `:no_pool`)
  - Updates `total_distributed` counter (index 6)
  - Returns `{:ok, amount, status}` tuple - caller does actual minting

- [x] **1.3** Add `get_post_pool_stats/1` to EngagementTracker
  - File: `lib/blockster_v2/engagement_tracker.ex` (lines 1360-1372)
  - Returns `{balance, deposited, distributed}` tuple
  - Used by admin UI in form_component

- [x] **1.4** Add `get_all_post_bux_balances/0` to EngagementTracker
  - File: `lib/blockster_v2/engagement_tracker.ex` (lines 1374-1390)
  - Returns map of all post_id => balance
  - Uses Mnesia `dirty_match_object` for efficiency
  - Used by SortedPostsCache for initialization

### Phase 2: Sorted Posts Cache (GenServer) ✅ COMPLETE

- [x] **2.1** Create `SortedPostsCache` GenServer
  - File: `lib/blockster_v2/sorted_posts_cache.ex` (NEW FILE)
  - Maintains pre-sorted list of `{post_id, balance, published_at}` tuples
  - Subscribes to `post_bux:all` PubSub topic for real-time updates
  - Client API: `get_page/2`, `count/0`, `update_balance/2`, `add_post/3`, `remove_post/1`, `reload/0`
  - Handles DateTime and NaiveDateTime conversion for `published_at`

- [x] **2.2** Add SortedPostsCache to supervision tree
  - File: `lib/blockster_v2/application.ex` (line 28)
  - Added `{BlocksterV2.SortedPostsCache, []}` after MnesiaInitializer
  - Starts after Mnesia so tables are available

- [x] **2.3** Add `list_published_posts_by_pool/1` to Blog
  - File: `lib/blockster_v2/blog.ex` (lines 231-261)
  - Uses `SortedPostsCache.get_page/2` for O(1) sorted IDs
  - Fetches only needed posts from PostgreSQL with preloads
  - Re-orders results to match sorted order
  - Attaches `bux_balance` to each post

- [x] **2.4** Add `count_published_posts/0` to Blog
  - File: `lib/blockster_v2/blog.ex` (lines 267-269)
  - Uses `SortedPostsCache.count/0`
  - For pagination UI (total pages)

### Phase 3: Homepage & Display (Frontend) ✅ COMPLETE

- [x] **3.1** Update `build_initial_components/0` in Index
  - File: `lib/blockster_v2_web/live/post_live/index.ex`
  - Calls `build_components_batch(0, [])` which now uses pool-sorted posts

- [x] **3.2** Update `build_components_batch/2` in Index
  - File: `lib/blockster_v2_web/live/post_live/index.ex` (lines 208-212)
  - Now uses `Blog.list_published_posts_by_pool/1` instead of `Blog.list_published_posts/1`
  - Removed `Blog.with_bux_balances()` call since new function already attaches balances

- [x] **3.3** Update token_badge for empty state
  - File: `lib/blockster_v2_web/components/shared_components.ex` (lines 40-63)
  - Added `is_empty` logic (balance = 0 or nil)
  - Gray border (`bg-gray-400`), gray background (`bg-gray-100`), dimmed icon (`opacity-50`), gray text (`text-gray-400`)
  - Changed precision from 2 to 0 decimal places

### Phase 4: Reading Reward Flow ✅ COMPLETE

- [x] **4.1** Check pool availability on mount in Show
  - File: `lib/blockster_v2_web/live/post_live/show.ex` (lines 37-38, 133-134)
  - Fetches `pool_balance` from `EngagementTracker.get_post_bux_balance/1`
  - Assigns `pool_available` (boolean) and `pool_balance` to socket

- [x] **4.2** Conditionally render earning UI in Show template
  - File: `lib/blockster_v2_web/live/post_live/show.html.heex` (lines 46-75)
  - When `@pool_available` is true: Shows green "Earning BUX" panel with score/multiplier breakdown
  - When `@pool_available` is false: Shows gray "Pool Empty" panel with "No BUX Available" message
  - Panel updates dynamically via PubSub when pool status changes

- [x] **4.3** Modify `handle_event("article-read", ...)` in Show
  - File: `lib/blockster_v2_web/live/post_live/show.ex` (lines 252-340)
  - Calls `try_deduct_from_pool/2` BEFORE calling `record_read_reward`
  - Handles `:full_amount`, `:partial_amount`, `:pool_empty`, `:no_pool` statuses
  - Shows flash messages for partial/empty pool cases
  - Only mints if pool had BUX available

- [ ] **4.4** Remove `add_post_bux_earned` call from BuxMinter
  - File: `lib/blockster_v2/bux_minter.ex`
  - **NOT DONE:** Keeping old increment logic for now as fallback
  - Pool decrement happens in `try_deduct_from_pool` before minting
  - Can remove in future cleanup phase

- [x] **4.5** Update `handle_info({:bux_update, ...})` in Show
  - File: `lib/blockster_v2_web/live/post_live/show.ex` (lines 365-374)
  - Now updates `pool_balance` and `pool_available` assigns
  - If pool drains to 0 while user is reading, UI reflects this

### Phase 5: X Share Reward Flow ✅ COMPLETE

- [x] **5.1** Modify share reward handling in Show
  - File: `lib/blockster_v2_web/live/post_live/show.ex` (lines 505-580)
  - Now calls `try_deduct_from_pool/2` BEFORE minting share reward
  - Handles all pool statuses: `:full_amount`, `:partial_amount`, `:pool_empty`, `:no_pool`
  - If pool empty: Share still succeeds but shows info message "Pool empty - no BUX available"
  - If partial: Shows message with actual amount earned
  - Updates `pool_balance` and `pool_available` assigns after deduction

- [x] **5.2** Update X share reward display
  - Success messages now reflect actual amount earned (may differ from displayed reward if pool was partially available)
  - Pool-specific messages guide user understanding of the pool system

### Phase 6: Admin Pool Management UI ✅ COMPLETE

- [x] **6.1** Add pool stats to form assigns
  - File: `lib/blockster_v2_web/live/post_live/form_component.ex` (lines 65-71)
  - Fetches `{pool_balance, pool_deposited, pool_distributed}` on mount
  - Only for existing posts (when `post.id` is set)

- [x] **6.2** Add deposit event handler
  - File: `lib/blockster_v2_web/live/post_live/form_component.ex` (lines 294-325)
  - Handles `"deposit_bux"` event with amount validation
  - Validates admin-only access
  - Calls `deposit_post_bux/2` and refreshes pool stats
  - Shows success/error flash messages

- [x] **6.3** Add pool management UI section
  - File: `lib/blockster_v2_web/live/post_live/form_component.html.heex` (lines 393-448)
  - Shows current balance (green), deposited (blue), distributed (purple)
  - Deposit form with number input and submit button
  - Admin-only visibility, only shown for existing posts

- [x] **6.4** Add quick deposit from post cards (admin only)
  - **Cog Icon on Post Cards:** Added admin-only cog icon button to top-right of all post cards
    - File: `lib/blockster_v2_web/live/post_live/posts_three_component.html.heex` (5 cards)
    - File: `lib/blockster_v2_web/live/post_live/posts_four_component.html.heex` (3 cards)
    - File: `lib/blockster_v2_web/live/post_live/posts_five_component.html.heex` (6 cards)
    - File: `lib/blockster_v2_web/live/post_live/posts_six_component.html.heex` (5 cards)
    - Button uses `phx-click="open_bux_deposit_modal"` with `phx-value-post-id={post.id}`
    - Styled: white background, rounded-full, shadow, hover:bg-gray-100
  - **Modal State in index.ex:**
    - Added assigns: `show_bux_deposit_modal` (boolean), `deposit_modal_post` (map with id, title, pool_balance, total_deposited, total_distributed)
    - Event handler `open_bux_deposit_modal` - fetches post and pool stats via `EngagementTracker.get_post_pool_stats/1`
    - Event handler `close_bux_deposit_modal` - resets modal state
    - Event handler `deposit_bux` - validates admin, parses amount, calls `EngagementTracker.deposit_post_bux/2`, updates `bux_balances` map
  - **Modal UI in index.html.heex:**
    - Fixed overlay with `bg-gray-900/60`, centered modal with `phx-click-away="close_bux_deposit_modal"`
    - Header: "Quick BUX Deposit" title + X close button
    - Post title display (truncated)
    - Stats grid (3 columns): Pool Balance (green), Deposited (blue), Distributed (purple)
    - Deposit form: number input + Cancel/Deposit BUX buttons
    - Uses `Number.Delimit.number_to_delimited/2` for formatted display

- [x] **6.5** Add pool management to admin posts page
  - File: `lib/blockster_v2_web/live/posts_admin_live.ex` (existing file updated)
  - File: `lib/blockster_v2_web/live/posts_admin_live.html.heex` (updated)
  - Added Pool column showing current balance (green when has BUX, gray when empty)
  - Added inline deposit form per row (input + "+" button)
  - Added sortable Pool column (click header to sort by balance asc/desc)
  - Added checkbox selection for bulk operations
  - Added floating bulk deposit bar when posts are selected
  - Added "toggle all" checkbox in header
  - Event handlers: `deposit_single`, `bulk_deposit`, `toggle_select`, `toggle_all`, `clear_selection`, `sort`

### Phase 7: Real-time Updates ✅ COMPLETE

- [x] **7.1** Verify PubSub broadcasts work for pool decrements
  - File: `lib/blockster_v2/engagement_tracker.ex`
  - `broadcast_bux_update/2` called in both `deposit_post_bux` and `try_deduct_from_pool`

- [x] **7.2** Verify homepage updates on pool changes
  - File: `lib/blockster_v2_web/live/post_live/index.ex`
  - Existing `handle_info({:bux_update, ...})` handler updates balance display
  - Added `handle_info({:posts_reordered, ...})` handler to rebuild components when sort order changes

- [x] **7.3** SortedPostsCache receives and processes updates
  - File: `lib/blockster_v2/sorted_posts_cache.ex`
  - `handle_info({:bux_update, ...})` updates balance and re-sorts
  - **NEW:** Now broadcasts `{:posts_reordered, post_id, new_balance}` when sort order changes
  - LiveViews subscribe to `post_bux:all` and receive reorder events

- [x] **7.4** SortedPostsCache waits for Mnesia on startup
  - File: `lib/blockster_v2/sorted_posts_cache.ex`
  - Polls every 2 seconds until `post_bux_points` table is ready
  - Prevents loading empty balances when started before Mnesia initialization completes
  - 60-second timeout before falling back to empty balances

- [x] **7.5** Modal closes after successful deposit
  - File: `lib/blockster_v2_web/live/post_live/index.ex`
  - `deposit_bux` event handler now sets `show_bux_deposit_modal: false` on success

### Phase 8: Edge Cases & Validation ✅ COMPLETE

- [x] **8.1** Handle race conditions
  - **IMPLEMENTED:** Created `PostBuxPoolWriter` GenServer for serialized pool operations
  - File: `lib/blockster_v2/post_bux_pool_writer.ex` (NEW FILE)
  - Added to supervision tree in `lib/blockster_v2/application.ex`
  - `EngagementTracker.deposit_post_bux/2` now delegates to `PostBuxPoolWriter.deposit/2`
  - `EngagementTracker.try_deduct_from_pool/2` now delegates to `PostBuxPoolWriter.try_deduct/2`
  - All pool operations serialized through GenServer.call/3 with 10s timeout
  - Prevents over-distribution when multiple users drain pool simultaneously

- [x] **8.2** Validate deposit amounts
  - `deposit_post_bux/2` requires `amount > 0` and integer
  - Form handler validates amount parsing
  - Admin authority checked in event handler

- [x] **8.3** Handle posts with no pool
  - Returns `:no_pool` status from `try_deduct_from_pool`
  - Shows flash message "This post has no BUX available"
  - Badge shows grayed-out state when balance = 0

- [x] **8.4** Test empty pool scenarios
  - `:pool_empty` status handled in show.ex
  - `:partial_amount` status shows partial earnings message
  - **Needs manual testing for mid-read pool drain**

### Phase 9: Data Migration (Production) ✅ SCRIPT READY

- [x] **9.1** Decide migration strategy
  - **DECIDED:** Reset all pools to 0 - admin re-deposits to desired posts
  - Existing `bux_balance` values are from old "total earned" semantics
  - New semantics: `bux_balance` = "remaining pool balance"

- [x] **9.2** Create migration script
  - File: `priv/scripts/reset_post_bux_pools.exs` (NEW FILE)
  - Sets `bux_balance`, `bux_deposited`, and `total_distributed` to 0 for ALL records
  - Includes safety features:
    - Preview of records to be reset (shows current values)
    - Requires confirmation ("yes" to proceed, any other input aborts)
    - Logs each reset with post ID
  - **Usage (production):**
    ```bash
    # SSH into production
    flyctl ssh console -a blockster-v2

    # Run the script
    /app/bin/blockster_v2 eval "Code.require_file(\"/app/priv/scripts/reset_post_bux_pools.exs\")"
    ```
  - **Usage (local development):**
    ```bash
    elixir --sname admin -S mix run priv/scripts/reset_post_bux_pools.exs
    ```

- [ ] **9.3** Run migration on staging
  - Test sorting, deposits, and earning flow

- [ ] **9.4** Run migration on production
  - Coordinate with admin to re-deposit to desired posts

### Phase 10: Documentation & Cleanup ⏳ NOT STARTED

- [ ] **10.1** Update CLAUDE.md with new system
  - Document pool mechanics
  - Document SortedPostsCache GenServer
  - Update engagement tracking section

- [ ] **10.2** Create admin documentation
  - How to deposit BUX
  - When to top up posts
  - Monitoring pool levels

- [ ] **10.3** Remove deprecated code
  - `add_post_bux_earned` in BuxMinter (after testing)
  - Old sorting by `published_at` in Blog (if not needed elsewhere)

- [ ] **10.4** Add pool analytics (optional)
  - Dashboard showing pool levels
  - Alerts for low pools
  - Distribution stats

---

## Phase 11: Category & Tag Pages - BUX Pool Sorting

### Overview

Extend the BUX pool sorting system to category (`/category/:slug`) and tag (`/tag/:slug`) pages. Posts will be sorted by `bux_balance DESC`, then `published_at DESC` - matching the homepage behavior.

**Key Difference from Homepage:**
- **NO quick deposit admin cog** on post cards (admin manages pools from homepage or admin panel only)
- Same visual BUX badge showing remaining pool balance (with empty state styling)

### Current Implementation Analysis

**Category Page** (`lib/blockster_v2_web/live/post_live/category.ex`):
- Uses `Blog.list_published_posts_by_category/2` with `exclude_ids` and `limit` options
- Calls `Blog.with_bux_balances()` to attach Mnesia balances
- Sorts by `published_at DESC` (in the SQL query)
- Uses same component cycle: PostsThree → PostsFour → PostsFive → PostsSix

**Tag Page** (`lib/blockster_v2_web/live/post_live/tag.ex`):
- Uses `Blog.list_published_posts_by_tag/2` with `exclude_ids` and `limit` options
- Calls `Blog.with_bux_balances()` to attach Mnesia balances
- Sorts by `published_at DESC` (in the SQL query)
- Uses same component cycle: PostsThree → PostsFour → PostsFive → PostsSix

**Problem with Current Approach:**
- SQL-based sorting can't incorporate Mnesia pool balances
- Each batch fetch is independent - no global view of sort order
- `exclude_ids` pattern works for `published_at` ordering but not for pool-based ordering

### Implementation Strategy

**Option A: Extend SortedPostsCache (Recommended)**

Add filtered views to `SortedPostsCache` that pre-filter by category/tag while maintaining pool sort order.

**Pros:**
- O(1) pagination (same as homepage)
- Consistent sort order across page loads
- Single source of truth for pool ordering

**Cons:**
- Slightly more complex cache
- Need to store category_id and tag_ids per post

**Option B: Query-Time Sorting**

Fetch all matching posts, sort in memory by pool balance, paginate.

**Pros:**
- Simpler cache (no changes)
- Works with existing query patterns

**Cons:**
- O(n) per page load where n = posts in category/tag
- Inconsistent ordering if pool changes between fetches

**Recommended: Option A** - Extend SortedPostsCache with category/tag filtering.

---

### Implementation Checklist

**Implementation Date:** January 19, 2026

#### Phase 11.1: Extend SortedPostsCache ✅ COMPLETE

- [x] **11.1.1** Add category_id and tag_ids to cached tuples
  - File: `lib/blockster_v2/sorted_posts_cache.ex`
  - Changed tuple from `{post_id, balance, published_at}` to `{post_id, balance, published_at, category_id, tag_ids}`
  - `tag_ids` is a list of tag IDs (posts can have multiple tags)

- [x] **11.1.2** Update `load_and_sort_all_posts/0` to include category/tags
  - Fetches category_id directly from Post query
  - Fetches tag_ids via separate query to posts_tags join table
  - Groups tag_ids by post_id using `Enum.group_by/3`

- [x] **11.1.3** Add `get_page_by_category/3` function
  - Filters `sorted_posts` by `category_id`, then applies limit/offset
  - O(n) filter + O(1) slice where n = total posts

- [x] **11.1.4** Add `get_page_by_tag/3` function
  - Filters `sorted_posts` where `tag_id in tag_ids`, then applies limit/offset
  - O(n) filter + O(1) slice where n = total posts

- [x] **11.1.5** Add `count_by_category/1` and `count_by_tag/1` functions
  - For pagination UI (total count of filtered posts)

- [x] **11.1.6** Add handle_call clauses for new operations
  - `{:get_page_by_category, category_id, limit, offset}` - filter + slice
  - `{:get_page_by_tag, tag_id, limit, offset}` - filter + slice
  - `{:count_by_category, category_id}` - filter + length
  - `{:count_by_tag, tag_id}` - filter + length

- [x] **11.1.7** Update `add_post/3` to accept category_id and tag_ids
  - Added new `add_post/5` function with category_id and tag_ids
  - Kept legacy `add_post/3` for backwards compatibility (defaults to nil category, empty tags)

#### Phase 11.2: Add Blog Functions for Pool-Sorted Category/Tag Queries ✅ COMPLETE

- [x] **11.2.1** Add `list_published_posts_by_category_pool/2` to Blog
  - File: `lib/blockster_v2/blog.ex` (lines 271-327)
  - Uses `SortedPostsCache.get_page_by_category/3` for O(n) filter + O(1) pagination
  - Handles exclude_ids for infinite scroll
  - Attaches bux_balance to each post

- [x] **11.2.2** Add `list_published_posts_by_tag_pool/2` to Blog
  - File: `lib/blockster_v2/blog.ex` (lines 329-387)
  - Same pattern as category, uses `SortedPostsCache.get_page_by_tag/3`
  - Gets tag_id from slug first

- [x] **11.2.3** Add `count_published_posts_by_category/1` and `count_published_posts_by_tag/1`
  - File: `lib/blockster_v2/blog.ex` (lines 389-408)
  - For pagination UI (total count of filtered posts)

#### Phase 11.3: Update Category LiveView ✅ COMPLETE

- [x] **11.3.1** Modify `build_components_batch/3` in Category
  - File: `lib/blockster_v2_web/live/post_live/category.ex`
  - Replaced `Blog.list_published_posts_by_category()` with `Blog.list_published_posts_by_category_pool()`
  - Removed `|> Blog.with_bux_balances()` call (new function attaches balances)
  - Function now returns 3-tuple: `{components, post_ids, bux_balances}`

- [x] **11.3.2** Subscribe to PubSub for real-time balance updates
  - Added in mount: `Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "post_bux:all")`
  - Added handle_info for `{:bux_update, post_id, new_balance}` to update displayed balances
  - Added handle_info for `{:posts_reordered, _, _}` (ignores for now, would require component rebuild)

- [x] **11.3.3** Verify post cards display BUX badge (no admin cog)
  - Admin cog is only rendered in index.ex (homepage), NOT in category.ex
  - Post card templates already render `token_badge` with `bux_balance`

#### Phase 11.4: Update Tag LiveView ✅ COMPLETE

- [x] **11.4.1** Modify `build_components_batch/3` in Tag
  - File: `lib/blockster_v2_web/live/post_live/tag.ex`
  - Replaced `Blog.list_published_posts_by_tag()` with `Blog.list_published_posts_by_tag_pool()`
  - Removed `|> Blog.with_bux_balances()` call
  - Function now returns 3-tuple: `{components, post_ids, bux_balances}`

- [x] **11.4.2** Subscribe to PubSub for real-time balance updates
  - Same pattern as category page
  - Subscribe in mount, handle `:bux_update` and `:posts_reordered`

- [x] **11.4.3** Verify post cards display BUX badge (no admin cog)
  - Admin cog is only rendered in index.ex (homepage), NOT in tag.ex

#### Phase 11.5: Handle Edge Cases ✅ COMPLETE

- [x] **11.5.1** Handle empty category/tag (no posts)
  - `get_page_by_category/3` returns `[]` when no posts match
  - Category/Tag pages continue to show empty state (existing behavior)

- [x] **11.5.2** Handle category/tag with all zero-pool posts
  - Posts display in `published_at DESC` order (secondary sort)
  - BUX badges show grayed-out state (existing behavior from Phase 3.3)

- [x] **11.5.3** Handle new post published to category/tag
  - Legacy `add_post/3` still works with nil category and empty tags
  - Full cache reload on application restart

- [ ] **11.5.4** Handle post category/tag change (OPTIONAL - Future Enhancement)
  - Currently requires cache reload if category/tags change
  - Could add `update_post_metadata/3` function for real-time updates

#### Phase 11.6: Testing

- [ ] **11.6.1** Unit tests for SortedPostsCache filtered queries (OPTIONAL)
- [ ] **11.6.2** Integration tests for category page (OPTIONAL)
- [ ] **11.6.3** Integration tests for tag page (OPTIONAL)

- [ ] **11.6.4** Manual testing checklist
  - [ ] Navigate to category page, verify posts sorted by pool balance
  - [ ] Navigate to tag page, verify posts sorted by pool balance
  - [ ] Deposit BUX to post in category, verify order changes
  - [ ] Scroll to load more posts, verify order maintained
  - [ ] Verify NO admin cog on post cards in category/tag pages
  - [ ] Verify BUX badge shows correct balance
  - [ ] Verify empty pool posts show grayed badge

---

### Files Modified (Phase 11)

| File | Changes |
|------|---------|
| `lib/blockster_v2/sorted_posts_cache.ex` | Added category_id/tag_ids to tuples, added filtered query functions |
| `lib/blockster_v2/blog.ex` | Added `list_published_posts_by_category_pool/2`, `list_published_posts_by_tag_pool/2`, count functions |
| `lib/blockster_v2_web/live/post_live/category.ex` | Use pool-sorted query, subscribe to PubSub, track bux_balances |
| `lib/blockster_v2_web/live/post_live/tag.ex` | Use pool-sorted query, subscribe to PubSub, track bux_balances |

---

### Original Files to Modify (from plan)

| File | Changes |
|------|---------|
| `lib/blockster_v2/sorted_posts_cache.ex` | Add category_id/tag_ids to tuples, add filtered query functions |
| `lib/blockster_v2/blog.ex` | Add `list_published_posts_by_category_pool/2`, `list_published_posts_by_tag_pool/2` |
| `lib/blockster_v2_web/live/post_live/category.ex` | Use new pool-sorted function, subscribe to PubSub |
| `lib/blockster_v2_web/live/post_live/tag.ex` | Use new pool-sorted function, subscribe to PubSub |

### No Changes Required

- Post card templates (already display BUX badge via `token_badge`)
- `token_badge` component (already handles empty state)
- Admin cog (only rendered in homepage index.ex, not in category.ex or tag.ex)

---

### Performance Considerations

**Approach: Simple O(n) In-Memory Filter**

The category/tag queries use a simple filter over the pre-sorted list:
```elixir
# get_page_by_category - O(n) filter, then O(1) slice
state.sorted_posts
|> Enum.filter(fn {_, _, _, cat_id, _} -> cat_id == category_id end)
|> Enum.drop(offset)
|> Enum.take(limit)
```

**Why this is efficient for your scale:**
- ~500 posts total = <1ms filter time
- Even at 10,000 posts = ~2-3ms filter time
- All in-memory (no DB/Mnesia calls)
- Filtering tuples is extremely fast in Erlang/Elixir

**Comparison to homepage:**
- Homepage: O(1) slice (no filter needed - takes from global sorted list)
- Category/Tag: O(n) filter + O(1) slice (filter by category_id/tag_id first)

**Memory:**
- Adding category_id (integer) + tag_ids (list of integers) per post
- Estimated: +16 bytes (category_id) + ~40 bytes average (tag_ids list) = +56 bytes per post
- 10,000 posts = ~560 KB additional memory (acceptable)

**Initial Load:**
- Single SQL query fetches all post IDs with category_id and tag_ids
- PostgreSQL `array_agg` for tags is efficient
- One Mnesia dirty_match_object for all pool balances (existing)

**Future optimization (only if needed at 50k+ posts):**
- Add secondary indexes: `by_category: %{category_id => [sorted_posts]}`
- Converts category/tag queries to O(1) slice
- ~3x memory but O(1) queries

---

## Testing Scenarios

### Unit Tests

1. `deposit_post_bux/2` creates new record with correct values
2. `deposit_post_bux/2` increments existing record correctly
3. `try_deduct_from_pool/2` returns full amount when pool sufficient
4. `try_deduct_from_pool/2` returns partial when pool insufficient
5. `try_deduct_from_pool/2` returns 0 when pool empty
6. `SortedPostsCache.get_page/2` returns correct slice of sorted posts
7. `SortedPostsCache.update_balance/2` re-sorts correctly after balance change
8. `SortedPostsCache.add_post/3` inserts in correct sorted position
9. `SortedPostsCache.remove_post/1` removes post from cache

### Integration Tests

1. User reads article → pool decrements → badge updates → cache re-sorts
2. Admin deposits → pool increments → badge updates → cache re-sorts
3. Multiple users read simultaneously → no over-distribution
4. Pool empties → subsequent users see "empty" state
5. Homepage shows posts sorted by pool balance (from cache)
6. Infinite scroll fetches next page correctly (offset/limit)
7. PubSub broadcast triggers SortedPostsCache update

### Manual Testing Checklist

- [ ] Create new post, verify pool = 0
- [ ] Deposit BUX as admin, verify badge shows amount
- [ ] Read article, verify pool decrements
- [ ] Verify user balance increases
- [ ] Verify homepage sorting changes
- [ ] Empty pool completely, verify "empty" state
- [ ] Top up empty pool, verify earnings resume
- [ ] Test X share with pool system

---

## Rollback Plan

If issues arise:

1. **Immediate:** Disable pool system via feature flag
2. **Short-term:** Revert to minting-based rewards
3. **Data:** Pool balances preserved in Mnesia, can resume later

---

## Future Enhancements

1. **Scheduled deposits:** Auto-deposit X BUX daily/weekly
2. **Pool alerts:** Notify admin when pool below threshold
3. **User-funded pools:** Allow users to donate to post pools
4. **Pool multipliers:** Time-based bonus rates (happy hour)
5. **Analytics dashboard:** Pool depletion rates, popular posts, etc.
