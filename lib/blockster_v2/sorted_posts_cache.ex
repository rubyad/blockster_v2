defmodule BlocksterV2.SortedPostsCache do
  @moduledoc """
  Maintains sorted lists of post IDs for efficient pagination.

  Three sorted views are maintained:
  - **By balance** (legacy): BUX pool balance DESC, then published_at DESC
  - **By date**: published_at DESC (for "Latest" tab)
  - **By popular**: total_distributed DESC, then published_at DESC (for "Popular" tab)

  Reads are O(1) - just slice the pre-sorted list.
  Writes (deposits/deducts) trigger a re-sort, but these are infrequent.

  Each post is stored as a 6-element tuple:
  `{post_id, balance, published_unix, category_id, tag_ids, total_distributed}`

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
        notify_registered(pid)
        {:ok, pid}
      {:already_registered, _pid} ->
        :ignore
    end
  end

  # -- Balance-sorted (legacy) --

  @doc """
  Gets a page of post IDs sorted by pool balance DESC, then published_at DESC.
  Returns list of {post_id, balance} tuples.
  """
  def get_page(limit, offset \\ 0) do
    GenServer.call({:global, __MODULE__}, {:get_page, :balance, limit, offset})
  end

  def get_page_by_category(category_id, limit, offset \\ 0) do
    GenServer.call({:global, __MODULE__}, {:get_page_by_category, :balance, category_id, limit, offset})
  end

  def get_page_by_tag(tag_id, limit, offset \\ 0) do
    GenServer.call({:global, __MODULE__}, {:get_page_by_tag, :balance, tag_id, limit, offset})
  end

  # -- Date-sorted (Latest tab) --

  @doc """
  Gets a page of post IDs sorted by published_at DESC.
  Returns list of {post_id, total_distributed} tuples.
  """
  def get_page_by_date(limit, offset \\ 0) do
    GenServer.call({:global, __MODULE__}, {:get_page, :date, limit, offset})
  end

  def get_page_by_date_category(category_id, limit, offset \\ 0) do
    GenServer.call({:global, __MODULE__}, {:get_page_by_category, :date, category_id, limit, offset})
  end

  def get_page_by_date_tag(tag_id, limit, offset \\ 0) do
    GenServer.call({:global, __MODULE__}, {:get_page_by_tag, :date, tag_id, limit, offset})
  end

  # -- Popular-sorted (Popular tab) --

  @doc """
  Gets a page of post IDs sorted by total_distributed DESC, then published_at DESC.
  Returns list of {post_id, total_distributed} tuples.
  """
  def get_page_by_popular(limit, offset \\ 0) do
    GenServer.call({:global, __MODULE__}, {:get_page, :popular, limit, offset})
  end

  def get_page_by_popular_category(category_id, limit, offset \\ 0) do
    GenServer.call({:global, __MODULE__}, {:get_page_by_category, :popular, category_id, limit, offset})
  end

  def get_page_by_popular_tag(tag_id, limit, offset \\ 0) do
    GenServer.call({:global, __MODULE__}, {:get_page_by_tag, :popular, tag_id, limit, offset})
  end

  # -- Counts --

  def count do
    GenServer.call({:global, __MODULE__}, :count)
  end

  def count_by_category(category_id) do
    GenServer.call({:global, __MODULE__}, {:count_by_category, category_id})
  end

  def count_by_tag(tag_id) do
    GenServer.call({:global, __MODULE__}, {:count_by_tag, tag_id})
  end

  # -- Mutations --

  def update_balance(post_id, new_balance) do
    GenServer.cast({:global, __MODULE__}, {:update_balance, post_id, new_balance})
  end

  def update_post(post_id, published_at, category_id) do
    GenServer.cast({:global, __MODULE__}, {:update_post, post_id, published_at, category_id})
  end

  @doc """
  Updates a post's tag_ids in the cache.
  Called when tags are modified on an existing post.
  """
  def update_post_tags(post_id, tag_ids) do
    GenServer.cast({:global, __MODULE__}, {:update_post_tags, post_id, tag_ids})
  end

  def add_post(post_id, balance, published_at, category_id, tag_ids) do
    GenServer.cast({:global, __MODULE__}, {:add_post, post_id, balance, published_at, category_id, tag_ids})
  end

  def add_post(post_id, balance, published_at) do
    GenServer.cast({:global, __MODULE__}, {:add_post, post_id, balance, published_at})
  end

  def remove_post(post_id) do
    GenServer.cast({:global, __MODULE__}, {:remove_post, post_id})
  end

  def reload do
    GenServer.cast({:global, __MODULE__}, :reload)
  end

  # =============================================================================
  # Server Callbacks
  # =============================================================================

  @impl true
  def init(_opts) do
    {:ok, %{
      sorted_by_balance: [],
      sorted_by_date: [],
      sorted_by_popular: [],
      mnesia_ready: false,
      mnesia_wait_attempts: 0,
      registered: false
    }}
  end

  @doc false
  def notify_registered(pid) do
    send(pid, :registered)
  end

  @impl true
  def handle_info(:registered, %{registered: false} = state) do
    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "post_bux:all")
    send(self(), :wait_for_mnesia)
    Logger.info("[SortedPostsCache] Starting, waiting for Mnesia...")
    {:noreply, %{state | registered: true}}
  end

  def handle_info(:registered, state) do
    {:noreply, state}
  end

  # -- Read handlers --

  @impl true
  def handle_call({:get_page, sort_mode, limit, offset}, _from, state) do
    list = get_sorted_list(state, sort_mode)
    page = list
      |> Enum.drop(offset)
      |> Enum.take(limit)
      |> Enum.map(&extract_id_and_value(&1, sort_mode))

    {:reply, page, state}
  end

  @impl true
  def handle_call(:count, _from, state) do
    {:reply, length(state.sorted_by_balance), state}
  end

  @impl true
  def handle_call({:get_page_by_category, sort_mode, category_id, limit, offset}, _from, state) do
    list = get_sorted_list(state, sort_mode)
    page = list
      |> Enum.filter(fn {_pid, _bal, _pub, cat_id, _tags, _dist} -> cat_id == category_id end)
      |> Enum.drop(offset)
      |> Enum.take(limit)
      |> Enum.map(&extract_id_and_value(&1, sort_mode))

    {:reply, page, state}
  end

  @impl true
  def handle_call({:get_page_by_tag, sort_mode, tag_id, limit, offset}, _from, state) do
    list = get_sorted_list(state, sort_mode)
    page = list
      |> Enum.filter(fn {_pid, _bal, _pub, _cat, tag_ids, _dist} -> tag_id in tag_ids end)
      |> Enum.drop(offset)
      |> Enum.take(limit)
      |> Enum.map(&extract_id_and_value(&1, sort_mode))

    {:reply, page, state}
  end

  @impl true
  def handle_call({:count_by_category, category_id}, _from, state) do
    count = Enum.count(state.sorted_by_balance, fn {_pid, _bal, _pub, cat_id, _tags, _dist} ->
      cat_id == category_id
    end)
    {:reply, count, state}
  end

  @impl true
  def handle_call({:count_by_tag, tag_id}, _from, state) do
    count = Enum.count(state.sorted_by_balance, fn {_pid, _bal, _pub, _cat, tag_ids, _dist} ->
      tag_id in tag_ids
    end)
    {:reply, count, state}
  end

  # -- Write handlers --

  @impl true
  def handle_cast({:update_balance, post_id, new_balance}, state) do
    posts = update_in_list(state.sorted_by_balance, post_id, fn {pid, _bal, pub, cat, tags, dist} ->
      {pid, new_balance, pub, cat, tags, dist}
    end)
    {:noreply, rebuild_all_sorts(state, posts)}
  end

  @impl true
  def handle_cast({:update_post, post_id, published_at, category_id}, state) do
    published_unix = to_unix(published_at)

    posts = update_in_list(state.sorted_by_balance, post_id, fn {pid, bal, _pub, _cat, tags, dist} ->
      {pid, bal, published_unix, category_id, tags, dist}
    end)
    {:noreply, rebuild_all_sorts(state, posts)}
  end

  @impl true
  def handle_cast({:update_post_tags, post_id, tag_ids}, state) do
    posts = update_in_list(state.sorted_by_balance, post_id, fn {pid, bal, pub, cat, _tags, dist} ->
      {pid, bal, pub, cat, tag_ids, dist}
    end)
    # Tag changes don't affect sort order, but need to update all lists for filtering
    {:noreply, rebuild_all_sorts(state, posts)}
  end

  @impl true
  def handle_cast({:add_post, post_id, balance, published_at, category_id, tag_ids}, state) do
    exists = Enum.any?(state.sorted_by_balance, fn {pid, _, _, _, _, _} -> pid == post_id end)

    if exists do
      {:noreply, state}
    else
      published_unix = to_unix(published_at)
      posts = [{post_id, balance, published_unix, category_id, tag_ids || [], 0} | state.sorted_by_balance]
      {:noreply, rebuild_all_sorts(state, posts)}
    end
  end

  # Legacy 3-argument version
  @impl true
  def handle_cast({:add_post, post_id, balance, published_at}, state) do
    exists = Enum.any?(state.sorted_by_balance, fn {pid, _, _, _, _, _} -> pid == post_id end)

    if exists do
      {:noreply, state}
    else
      published_unix = to_unix(published_at)
      posts = [{post_id, balance, published_unix, nil, [], 0} | state.sorted_by_balance]
      {:noreply, rebuild_all_sorts(state, posts)}
    end
  end

  @impl true
  def handle_cast({:remove_post, post_id}, state) do
    posts = Enum.reject(state.sorted_by_balance, fn {pid, _, _, _, _, _} -> pid == post_id end)
    {:noreply, rebuild_all_sorts(state, posts)}
  end

  @impl true
  def handle_cast(:reload, state) do
    new_state = load_all_posts_into_state(state)
    Logger.info("[SortedPostsCache] Reloaded with #{length(new_state.sorted_by_balance)} posts")
    {:noreply, %{new_state | mnesia_ready: true}}
  end

  # -- Info handlers --

  @impl true
  def handle_info(:wait_for_mnesia, state) do
    attempts = state.mnesia_wait_attempts

    if attempts >= @max_mnesia_wait_attempts do
      Logger.warning("[SortedPostsCache] Timeout waiting for Mnesia, loading with empty balances")
      new_state = load_all_posts_into_state(state)
      {:noreply, %{new_state | mnesia_ready: true}}
    else
      if table_ready?(:post_bux_points) do
        Logger.info("[SortedPostsCache] Mnesia ready, loading posts...")
        new_state = load_all_posts_into_state(state)
        Logger.info("[SortedPostsCache] Initialized with #{length(new_state.sorted_by_balance)} posts")
        schedule_periodic_reload()
        {:noreply, %{new_state | mnesia_ready: true}}
      else
        Logger.info("[SortedPostsCache] Waiting for Mnesia post_bux_points table... (attempt #{attempts + 1})")
        Process.send_after(self(), :wait_for_mnesia, 2000)
        {:noreply, %{state | mnesia_wait_attempts: attempts + 1}}
      end
    end
  end

  @impl true
  def handle_info({:bux_update, post_id, new_balance, total_distributed}, state) do
    old_balance_list = state.sorted_by_balance

    posts = update_in_list(old_balance_list, post_id, fn {pid, _bal, pub, cat, tags, _dist} ->
      {pid, new_balance, pub, cat, tags, total_distributed}
    end)

    new_state = rebuild_all_sorts(state, posts)

    # Check if balance order changed
    old_order = Enum.map(old_balance_list, fn {pid, _, _, _, _, _} -> pid end)
    new_order = Enum.map(new_state.sorted_by_balance, fn {pid, _, _, _, _, _} -> pid end)

    if old_order != new_order do
      Phoenix.PubSub.broadcast(
        BlocksterV2.PubSub,
        "post_bux:all",
        {:posts_reordered, post_id, new_balance}
      )
    end

    {:noreply, new_state}
  end

  # Legacy 3-element broadcast (backward compat during rolling deploy)
  @impl true
  def handle_info({:bux_update, post_id, new_balance}, state) do
    old_balance_list = state.sorted_by_balance

    posts = update_in_list(old_balance_list, post_id, fn {pid, _bal, pub, cat, tags, dist} ->
      {pid, new_balance, pub, cat, tags, dist}
    end)

    new_state = rebuild_all_sorts(state, posts)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:periodic_reload, state) do
    new_state = load_all_posts_into_state(state)
    Logger.debug("[SortedPostsCache] Periodic reload: #{length(new_state.sorted_by_balance)} posts")
    schedule_periodic_reload()
    {:noreply, new_state}
  end

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

  defp table_ready?(table_name) do
    try do
      case :mnesia.system_info(:is_running) do
        :yes ->
          tables = :mnesia.system_info(:tables)
          if table_name in tables do
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
        _ -> false
      end
    rescue
      _ -> false
    catch
      :exit, _ -> false
    end
  end

  defp to_unix(datetime) do
    case datetime do
      %DateTime{} -> DateTime.to_unix(datetime)
      %NaiveDateTime{} -> NaiveDateTime.diff(datetime, ~N[1970-01-01 00:00:00])
      unix when is_integer(unix) -> unix
      _ -> 0
    end
  end

  # Get the appropriate sorted list from state
  defp get_sorted_list(state, :balance), do: state.sorted_by_balance
  defp get_sorted_list(state, :date), do: state.sorted_by_date
  defp get_sorted_list(state, :popular), do: state.sorted_by_popular

  # Extract the relevant {id, value} pair based on sort mode
  defp extract_id_and_value({post_id, _balance, _pub, _cat, _tags, total_distributed}, :balance),
    do: {post_id, total_distributed}
  defp extract_id_and_value({post_id, _balance, _pub, _cat, _tags, total_distributed}, :date),
    do: {post_id, total_distributed}
  defp extract_id_and_value({post_id, _balance, _pub, _cat, _tags, total_distributed}, :popular),
    do: {post_id, total_distributed}

  # Update a single post in the unsorted list
  defp update_in_list(posts, post_id, update_fn) do
    Enum.map(posts, fn {pid, _, _, _, _, _} = entry ->
      if pid == post_id, do: update_fn.(entry), else: entry
    end)
  end

  # Rebuild all three sorted views from an unsorted post list
  defp rebuild_all_sorts(state, posts) do
    %{state |
      sorted_by_balance: sort_by_balance(posts),
      sorted_by_date: sort_by_date(posts),
      sorted_by_popular: sort_by_popular(posts)
    }
  end

  defp sort_by_balance(posts) do
    Enum.sort_by(posts, fn {_pid, balance, published_at, _cat, _tags, _dist} ->
      {-balance, -published_at}
    end)
  end

  defp sort_by_date(posts) do
    Enum.sort_by(posts, fn {_pid, _balance, published_at, _cat, _tags, _dist} ->
      -published_at
    end)
  end

  defp sort_by_popular(posts) do
    Enum.sort_by(posts, fn {_pid, _balance, published_at, _cat, _tags, total_distributed} ->
      {-total_distributed, -published_at}
    end)
  end

  # Load all posts from DB + Mnesia and build all sorted views
  defp load_all_posts_into_state(state) do
    pool_balances = BlocksterV2.EngagementTracker.get_all_post_bux_balances()
    distributed_amounts = BlocksterV2.EngagementTracker.get_all_post_distributed_amounts()

    posts = BlocksterV2.Repo.all(
      from p in BlocksterV2.Blog.Post,
        where: not is_nil(p.published_at),
        select: {p.id, p.published_at, p.category_id}
    )

    tag_mappings = BlocksterV2.Repo.all(
      from pt in "post_tags",
        select: {pt.post_id, pt.tag_id}
    )
    |> Enum.group_by(fn {post_id, _} -> post_id end, fn {_, tag_id} -> tag_id end)

    unsorted = Enum.map(posts, fn {post_id, published_at, category_id} ->
      raw_balance = Map.get(pool_balances, post_id, 0)
      balance = max(0, raw_balance)
      total_distributed = Map.get(distributed_amounts, post_id, 0)
      tag_ids = Map.get(tag_mappings, post_id, [])
      published_unix = to_unix(published_at)
      {post_id, balance, published_unix, category_id, tag_ids, total_distributed}
    end)

    rebuild_all_sorts(state, unsorted)
  end
end
