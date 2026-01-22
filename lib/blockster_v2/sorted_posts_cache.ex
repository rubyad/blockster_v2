defmodule BlocksterV2.SortedPostsCache do
  @moduledoc """
  Maintains a sorted list of post IDs by BUX pool balance for efficient pagination.

  Reads are O(1) - just slice the pre-sorted list.
  Writes (deposits/deducts) trigger a re-sort, but these are infrequent.

  Memory usage: ~80 bytes per post (post_id + balance + published_at + category_id + tag_ids list)
  - 10,000 posts = ~800 KB
  - 100,000 posts = ~8 MB

  Supports filtering by category_id or tag_id for category/tag pages.

  Waits for Mnesia to be ready before loading data to ensure pool balances are available.

  This is a GLOBAL SINGLETON - only one instance runs across the entire cluster.
  Uses GlobalSingleton for safe registration during rolling deploys.
  """
  use GenServer
  require Logger

  import Ecto.Query

  @max_mnesia_wait_attempts 30  # 30 attempts * 2 seconds = 60 seconds max wait
  @periodic_reload_interval :timer.minutes(5)  # Safety net: reload every 5 minutes

  # =============================================================================
  # Client API
  # =============================================================================

  def start_link(opts \\ []) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} ->
        # Notify the process that it's now the globally registered instance
        # This triggers the actual initialization work
        notify_registered(pid)
        {:ok, pid}
      {:already_registered, _pid} ->
        :ignore
    end
  end

  @doc """
  Gets a page of post IDs sorted by pool balance DESC, then published_at DESC.
  Returns list of {post_id, balance} tuples.

  This is O(1) - just slices the pre-sorted list.
  """
  def get_page(limit, offset \\ 0) do
    GenServer.call({:global, __MODULE__}, {:get_page, limit, offset})
  end

  @doc """
  Gets the total count of posts in the cache.
  """
  def count do
    GenServer.call({:global, __MODULE__}, :count)
  end

  @doc """
  Gets a page of post IDs for a specific category, sorted by pool balance DESC.
  Returns list of {post_id, balance} tuples.

  This is O(n) filter + O(1) slice where n = total posts.
  """
  def get_page_by_category(category_id, limit, offset \\ 0) do
    GenServer.call({:global, __MODULE__}, {:get_page_by_category, category_id, limit, offset})
  end

  @doc """
  Gets a page of post IDs for a specific tag, sorted by pool balance DESC.
  Returns list of {post_id, balance} tuples.

  This is O(n) filter + O(1) slice where n = total posts.
  """
  def get_page_by_tag(tag_id, limit, offset \\ 0) do
    GenServer.call({:global, __MODULE__}, {:get_page_by_tag, tag_id, limit, offset})
  end

  @doc """
  Gets the count of posts in a specific category.
  """
  def count_by_category(category_id) do
    GenServer.call({:global, __MODULE__}, {:count_by_category, category_id})
  end

  @doc """
  Gets the count of posts with a specific tag.
  """
  def count_by_tag(tag_id) do
    GenServer.call({:global, __MODULE__}, {:count_by_tag, tag_id})
  end

  @doc """
  Updates the balance for a post and re-sorts if needed.
  Called after deposits or deductions.
  """
  def update_balance(post_id, new_balance) do
    GenServer.cast({:global, __MODULE__}, {:update_balance, post_id, new_balance})
  end

  @doc """
  Updates a post's metadata (published_at, category_id) and re-sorts.
  Called when a post is edited via admin form.
  """
  def update_post(post_id, published_at, category_id) do
    GenServer.cast({:global, __MODULE__}, {:update_post, post_id, published_at, category_id})
  end

  @doc """
  Adds a new post to the cache with category and tags.
  Called when a new post is published.
  """
  def add_post(post_id, balance, published_at, category_id, tag_ids) do
    GenServer.cast({:global, __MODULE__}, {:add_post, post_id, balance, published_at, category_id, tag_ids})
  end

  @doc """
  Adds a new post to the cache (legacy 3-argument version).
  Called when a new post is published. Category and tags default to nil/empty.
  """
  def add_post(post_id, balance, published_at) do
    GenServer.cast({:global, __MODULE__}, {:add_post, post_id, balance, published_at})
  end

  @doc """
  Removes a post from the cache.
  Called when a post is unpublished or deleted.
  """
  def remove_post(post_id) do
    GenServer.cast({:global, __MODULE__}, {:remove_post, post_id})
  end

  @doc """
  Forces a full reload from Mnesia and PostgreSQL.
  Used for initial load and recovery.
  """
  def reload do
    GenServer.cast({:global, __MODULE__}, :reload)
  end

  # =============================================================================
  # Server Callbacks
  # =============================================================================

  @impl true
  def init(_opts) do
    # Don't do any work here - wait for :registered message from start_link
    # This prevents duplicate work when GlobalSingleton loses the registration race
    {:ok, %{sorted_posts: [], mnesia_ready: false, mnesia_wait_attempts: 0, registered: false}}
  end

  @doc false
  def notify_registered(pid) do
    send(pid, :registered)
  end

  @impl true
  def handle_info(:registered, %{registered: false} = state) do
    # Now we know we're the globally registered instance - safe to start work
    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "post_bux:all")
    send(self(), :wait_for_mnesia)
    Logger.info("[SortedPostsCache] Starting, waiting for Mnesia...")
    {:noreply, %{state | registered: true}}
  end

  def handle_info(:registered, state) do
    # Already registered, ignore duplicate
    {:noreply, state}
  end

  @impl true
  def handle_call({:get_page, limit, offset}, _from, state) do
    page = state.sorted_posts
      |> Enum.drop(offset)
      |> Enum.take(limit)
      |> Enum.map(fn {post_id, balance, _published_at, _category_id, _tag_ids} -> {post_id, balance} end)

    {:reply, page, state}
  end

  @impl true
  def handle_call(:count, _from, state) do
    {:reply, length(state.sorted_posts), state}
  end

  @impl true
  def handle_call({:get_page_by_category, category_id, limit, offset}, _from, state) do
    page = state.sorted_posts
      |> Enum.filter(fn {_post_id, _balance, _published_at, cat_id, _tag_ids} -> cat_id == category_id end)
      |> Enum.drop(offset)
      |> Enum.take(limit)
      |> Enum.map(fn {post_id, balance, _published_at, _category_id, _tag_ids} -> {post_id, balance} end)

    {:reply, page, state}
  end

  @impl true
  def handle_call({:get_page_by_tag, tag_id, limit, offset}, _from, state) do
    page = state.sorted_posts
      |> Enum.filter(fn {_post_id, _balance, _published_at, _cat_id, tag_ids} -> tag_id in tag_ids end)
      |> Enum.drop(offset)
      |> Enum.take(limit)
      |> Enum.map(fn {post_id, balance, _published_at, _category_id, _tag_ids} -> {post_id, balance} end)

    {:reply, page, state}
  end

  @impl true
  def handle_call({:count_by_category, category_id}, _from, state) do
    count = state.sorted_posts
      |> Enum.count(fn {_post_id, _balance, _published_at, cat_id, _tag_ids} -> cat_id == category_id end)

    {:reply, count, state}
  end

  @impl true
  def handle_call({:count_by_tag, tag_id}, _from, state) do
    count = state.sorted_posts
      |> Enum.count(fn {_post_id, _balance, _published_at, _cat_id, tag_ids} -> tag_id in tag_ids end)

    {:reply, count, state}
  end

  @impl true
  def handle_cast({:update_balance, post_id, new_balance}, state) do
    sorted_posts = state.sorted_posts
      |> Enum.map(fn {pid, _bal, pub_at, cat_id, tag_ids} = entry ->
        if pid == post_id, do: {pid, new_balance, pub_at, cat_id, tag_ids}, else: entry
      end)
      |> sort_posts()

    {:noreply, %{state | sorted_posts: sorted_posts}}
  end

  @impl true
  def handle_cast({:update_post, post_id, published_at, category_id}, state) do
    published_unix = case published_at do
      %DateTime{} -> DateTime.to_unix(published_at)
      %NaiveDateTime{} -> NaiveDateTime.diff(published_at, ~N[1970-01-01 00:00:00])
      unix when is_integer(unix) -> unix
      _ -> 0
    end

    sorted_posts = state.sorted_posts
      |> Enum.map(fn {pid, bal, _pub_at, _cat_id, tag_ids} = entry ->
        if pid == post_id, do: {pid, bal, published_unix, category_id, tag_ids}, else: entry
      end)
      |> sort_posts()

    {:noreply, %{state | sorted_posts: sorted_posts}}
  end

  @impl true
  def handle_cast({:add_post, post_id, balance, published_at, category_id, tag_ids}, state) do
    # Check if already exists
    exists = Enum.any?(state.sorted_posts, fn {pid, _, _, _, _} -> pid == post_id end)

    sorted_posts = if exists do
      state.sorted_posts
    else
      published_unix = case published_at do
        %DateTime{} -> DateTime.to_unix(published_at)
        %NaiveDateTime{} -> NaiveDateTime.diff(published_at, ~N[1970-01-01 00:00:00])
        unix when is_integer(unix) -> unix
        _ -> 0
      end
      [{post_id, balance, published_unix, category_id, tag_ids || []} | state.sorted_posts]
      |> sort_posts()
    end

    {:noreply, %{state | sorted_posts: sorted_posts}}
  end

  # Legacy 3-argument version for backwards compatibility
  @impl true
  def handle_cast({:add_post, post_id, balance, published_at}, state) do
    # Check if already exists
    exists = Enum.any?(state.sorted_posts, fn {pid, _, _, _, _} -> pid == post_id end)

    sorted_posts = if exists do
      state.sorted_posts
    else
      published_unix = case published_at do
        %DateTime{} -> DateTime.to_unix(published_at)
        %NaiveDateTime{} -> NaiveDateTime.diff(published_at, ~N[1970-01-01 00:00:00])
        unix when is_integer(unix) -> unix
        _ -> 0
      end
      [{post_id, balance, published_unix, nil, []} | state.sorted_posts]
      |> sort_posts()
    end

    {:noreply, %{state | sorted_posts: sorted_posts}}
  end

  @impl true
  def handle_cast({:remove_post, post_id}, state) do
    sorted_posts = Enum.reject(state.sorted_posts, fn {pid, _, _, _, _} -> pid == post_id end)
    {:noreply, %{state | sorted_posts: sorted_posts}}
  end

  @impl true
  def handle_cast(:reload, state) do
    sorted_posts = load_and_sort_all_posts()
    Logger.info("[SortedPostsCache] Reloaded with #{length(sorted_posts)} posts")
    {:noreply, %{state | sorted_posts: sorted_posts, mnesia_ready: true}}
  end

  # Wait for Mnesia to be ready before loading data
  @impl true
  def handle_info(:wait_for_mnesia, state) do
    attempts = state.mnesia_wait_attempts

    if attempts >= @max_mnesia_wait_attempts do
      Logger.warning("[SortedPostsCache] Timeout waiting for Mnesia, loading with empty balances")
      sorted_posts = load_and_sort_all_posts()
      {:noreply, %{state | sorted_posts: sorted_posts, mnesia_ready: true}}
    else
      if table_ready?(:post_bux_points) do
        Logger.info("[SortedPostsCache] Mnesia ready, loading posts...")
        sorted_posts = load_and_sort_all_posts()
        Logger.info("[SortedPostsCache] Initialized with #{length(sorted_posts)} posts")
        # Schedule periodic reload as safety net
        schedule_periodic_reload()
        {:noreply, %{state | sorted_posts: sorted_posts, mnesia_ready: true}}
      else
        Logger.info("[SortedPostsCache] Waiting for Mnesia post_bux_points table... (attempt #{attempts + 1})")
        Process.send_after(self(), :wait_for_mnesia, 2000)
        {:noreply, %{state | mnesia_wait_attempts: attempts + 1}}
      end
    end
  end

  # Handle PubSub broadcasts from EngagementTracker
  @impl true
  def handle_info({:bux_update, post_id, new_balance}, state) do
    old_sorted_posts = state.sorted_posts

    # Update balance in our sorted list
    sorted_posts = old_sorted_posts
      |> Enum.map(fn {pid, _bal, pub_at, cat_id, tag_ids} = entry ->
        if pid == post_id, do: {pid, new_balance, pub_at, cat_id, tag_ids}, else: entry
      end)
      |> sort_posts()

    # Check if order changed by comparing post IDs
    old_order = Enum.map(old_sorted_posts, fn {pid, _, _, _, _} -> pid end)
    new_order = Enum.map(sorted_posts, fn {pid, _, _, _, _} -> pid end)

    if old_order != new_order do
      # Broadcast reorder event so LiveViews can refresh their post lists
      Phoenix.PubSub.broadcast(
        BlocksterV2.PubSub,
        "post_bux:all",
        {:posts_reordered, post_id, new_balance}
      )
    end

    {:noreply, %{state | sorted_posts: sorted_posts}}
  end

  # Periodic reload as safety net for any missed updates
  @impl true
  def handle_info(:periodic_reload, state) do
    sorted_posts = load_and_sort_all_posts()
    Logger.debug("[SortedPostsCache] Periodic reload: #{length(sorted_posts)} posts")
    schedule_periodic_reload()
    {:noreply, %{state | sorted_posts: sorted_posts}}
  end

  # Ignore other PubSub messages
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  defp schedule_periodic_reload do
    Process.send_after(self(), :periodic_reload, @periodic_reload_interval)
  end

  # Check if Mnesia table is ready for use
  defp table_ready?(table_name) do
    try do
      # Check if Mnesia is running
      case :mnesia.system_info(:is_running) do
        :yes ->
          tables = :mnesia.system_info(:tables)

          if table_name in tables do
            # Table exists, try a quick read to verify it's accessible
            try do
              :mnesia.dirty_first(table_name)
              true
            rescue
              _ -> false
            catch
              :exit, _ -> false
            end
          else
            false
          end

        _ ->
          false
      end
    rescue
      _ -> false
    catch
      :exit, _ -> false
    end
  end

  defp load_and_sort_all_posts do
    # Get all pool balances from Mnesia
    pool_balances = BlocksterV2.EngagementTracker.get_all_post_bux_balances()

    # Get all published posts with id, published_at, category_id
    posts = BlocksterV2.Repo.all(
      from p in BlocksterV2.Blog.Post,
        where: not is_nil(p.published_at),
        select: {p.id, p.published_at, p.category_id}
    )

    # Get all post_id => tag_ids mappings
    # Using post_tags join table
    tag_mappings = BlocksterV2.Repo.all(
      from pt in "post_tags",
        select: {pt.post_id, pt.tag_id}
    )
    |> Enum.group_by(fn {post_id, _} -> post_id end, fn {_, tag_id} -> tag_id end)

    # Build list of {post_id, balance, published_at, category_id, tag_ids} and sort
    # Use max(0, balance) so negative pools (from guaranteed earnings) sort same as empty pools
    posts
    |> Enum.map(fn {post_id, published_at, category_id} ->
      raw_balance = Map.get(pool_balances, post_id, 0)
      balance = max(0, raw_balance)
      tag_ids = Map.get(tag_mappings, post_id, [])
      published_unix = case published_at do
        %DateTime{} -> DateTime.to_unix(published_at)
        %NaiveDateTime{} -> NaiveDateTime.diff(published_at, ~N[1970-01-01 00:00:00])
        _ -> 0
      end
      {post_id, balance, published_unix, category_id, tag_ids}
    end)
    |> sort_posts()
  end

  defp sort_posts(posts) do
    # Sort by balance DESC, then published_at DESC
    Enum.sort_by(posts, fn {_post_id, balance, published_at, _category_id, _tag_ids} ->
      {-balance, -published_at}
    end)
  end
end
