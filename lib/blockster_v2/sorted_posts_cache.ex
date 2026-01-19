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

  import Ecto.Query

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
      published_unix = case published_at do
        %DateTime{} -> DateTime.to_unix(published_at)
        %NaiveDateTime{} -> NaiveDateTime.diff(published_at, ~N[1970-01-01 00:00:00])
        unix when is_integer(unix) -> unix
        _ -> 0
      end
      [{post_id, balance, published_unix} | state.sorted_posts]
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
  def handle_cast(:reload, _state) do
    sorted_posts = load_and_sort_all_posts()
    Logger.info("[SortedPostsCache] Reloaded with #{length(sorted_posts)} posts")
    {:noreply, %{sorted_posts: sorted_posts}}
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

  # Ignore other PubSub messages
  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
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
      published_unix = case published_at do
        %DateTime{} -> DateTime.to_unix(published_at)
        %NaiveDateTime{} -> NaiveDateTime.diff(published_at, ~N[1970-01-01 00:00:00])
        _ -> 0
      end
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
