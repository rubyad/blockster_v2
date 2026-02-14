defmodule BlocksterV2.ContentAutomation.FeedStore do
  @moduledoc """
  Database queries for all content automation pipeline tables.
  Wraps Ecto operations for feed items, generated topics, and the publish queue.
  """

  alias BlocksterV2.Repo
  alias BlocksterV2.ContentAutomation.{ContentFeedItem, ContentGeneratedTopic, ContentPublishQueue, FeedConfig, Settings}
  import Ecto.Query

  @per_page 25

  # ── Feed Items ──

  @doc """
  Bulk insert feed items, skipping duplicates by URL.
  Returns {inserted_count, nil}.
  """
  def store_new_items(items) when is_list(items) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      Enum.map(items, fn item ->
        item
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    Repo.insert_all(ContentFeedItem, entries,
      on_conflict: :nothing,
      conflict_target: :url
    )
  end

  @doc """
  Get recent unprocessed feed items for topic clustering.
  Returns up to 50 items from the last `hours` hours, newest first.
  """
  def get_recent_unprocessed(opts \\ []) do
    hours = Keyword.get(opts, :hours, 12)
    cutoff = DateTime.utc_now() |> DateTime.add(-hours * 3600, :second)

    from(f in ContentFeedItem,
      where: f.processed == false and f.fetched_at >= ^cutoff,
      order_by: [desc: f.published_at],
      limit: 50
    )
    |> Repo.all()
  end

  @doc """
  Mark feed items as processed and link them to a topic cluster.
  Called by TopicEngine after clustering is complete (two-phase processing).
  """
  def mark_items_processed(urls, topic_id) do
    from(f in ContentFeedItem, where: f.url in ^urls)
    |> Repo.update_all(set: [processed: true, topic_cluster_id: topic_id])
  end

  # ── Topics ──

  @doc """
  Get topic titles from recent days for deduplication.
  """
  def get_generated_topic_titles(opts \\ []) do
    days = Keyword.get(opts, :days, 7)
    cutoff = DateTime.utc_now() |> DateTime.add(-days * 86400, :second)

    from(t in ContentGeneratedTopic,
      where: t.inserted_at >= ^cutoff,
      select: t.title
    )
    |> Repo.all()
  end

  @doc """
  Get category counts for articles generated today.
  """
  def get_today_category_counts do
    today_start = Date.utc_today() |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    from(t in ContentGeneratedTopic,
      where: t.inserted_at >= ^today_start and not is_nil(t.article_id),
      group_by: t.category,
      select: {t.category, count(t.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Load a topic with its source feed items for content generation.
  """
  def get_topic_for_generation(topic_id) do
    ContentGeneratedTopic
    |> Repo.get(topic_id)
    |> Repo.preload(:feed_items)
  end

  @doc """
  Get topics that haven't been generated yet (no queue entry exists).
  Returns topics ordered by rank_score descending, limited to `limit`.
  """
  def get_ungenerated_topics(limit \\ 5) do
    from(t in ContentGeneratedTopic,
      left_join: q in ContentPublishQueue, on: q.topic_id == t.id,
      where: is_nil(q.id),
      order_by: [desc: t.rank_score],
      limit: ^limit,
      preload: [:feed_items]
    )
    |> Repo.all()
  end

  @doc """
  Insert an article into the publish queue.
  """
  def enqueue_article(attrs) do
    %ContentPublishQueue{}
    |> ContentPublishQueue.changeset(attrs)
    |> Repo.insert()
  end

  # ── Publish Queue ──

  def get_queue_entry(id), do: Repo.get(ContentPublishQueue, id)

  def get_pending_queue_entries do
    from(q in ContentPublishQueue,
      where: q.status in ["pending", "draft"],
      order_by: [desc: q.inserted_at],
      preload: [:author]
    )
    |> Repo.all()
  end

  def update_queue_entry(id, attrs) do
    Repo.get!(ContentPublishQueue, id)
    |> Ecto.Changeset.change(attrs)
    |> Repo.update()
  end

  def mark_queue_entry_published(id, post_id) do
    Repo.get!(ContentPublishQueue, id)
    |> Ecto.Changeset.change(%{
      status: "published",
      post_id: post_id,
      reviewed_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  # ── Stats ──

  def count_published_today do
    today_start = Date.utc_today() |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    from(q in ContentPublishQueue,
      where: q.status == "published" and q.updated_at >= ^today_start
    )
    |> Repo.aggregate(:count)
  end

  def count_queued do
    from(q in ContentPublishQueue, where: q.status in ["pending", "draft", "approved"])
    |> Repo.aggregate(:count)
  end

  # ── Admin Dashboard Queries ──

  @doc "Reject a queue entry with an optional reason. Non-empty reasons are saved as editorial memory."
  def reject_queue_entry(id, reason \\ nil) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    entry = Repo.get!(ContentPublishQueue, id)

    entry
    |> Ecto.Changeset.change(%{
      status: "rejected",
      rejected_reason: reason,
      reviewed_at: now
    })
    |> Repo.update()
    |> tap(fn
      {:ok, entry} ->
        Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "content_automation", {:content_automation, :article_rejected, entry})
        save_rejection_as_memory(entry, reason)
      _ -> :ok
    end)
  end

  defp save_rejection_as_memory(_entry, nil), do: :ok
  defp save_rejection_as_memory(_entry, ""), do: :ok

  defp save_rejection_as_memory(entry, reason) do
    title = get_in(entry.article_data, ["title"]) || "Untitled"
    instruction = "Rejected article \"#{title}\": #{reason}"

    case BlocksterV2.ContentAutomation.EditorialFeedback.add_memory(instruction,
      category: "topics",
      source_queue_entry_id: entry.id
    ) do
      {:ok, _} ->
        Logger.info("[FeedStore] Rejection reason saved to editorial memory: #{String.slice(reason, 0, 80)}")
      {:error, _} ->
        Logger.warning("[FeedStore] Failed to save rejection reason to memory")
    end
  end

  @doc """
  Get queue entries with flexible filtering for Queue and History pages.

  Options:
    - status: string or list of strings (default: all)
    - category: string (filters article_data->category)
    - author_id: integer
    - since: DateTime
    - page: integer (default: 1)
    - per_page: integer (default: 25)
    - order: :newest (default) or :oldest
  """
  def get_queue_entries(opts \\ []) do
    statuses = opts[:status]
    category = opts[:category]
    author_id = opts[:author_id]
    since = opts[:since]
    page = opts[:page] || 1
    per_page = opts[:per_page] || @per_page
    order = opts[:order] || :newest
    offset = (page - 1) * per_page

    query = from(q in ContentPublishQueue, preload: [:author])

    query =
      case statuses do
        nil -> query
        s when is_binary(s) -> where(query, [q], q.status == ^s)
        s when is_list(s) -> where(query, [q], q.status in ^s)
      end

    query = if category, do: where(query, [q], fragment("?->>'category' = ?", q.article_data, ^category)), else: query
    query = if author_id, do: where(query, [q], q.author_id == ^author_id), else: query
    query = if since, do: where(query, [q], q.inserted_at >= ^since), else: query

    query =
      case order do
        :oldest -> order_by(query, [q], asc: q.inserted_at)
        _ -> order_by(query, [q], desc: q.inserted_at)
      end

    query
    |> limit(^per_page)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc "Count total entries matching filters (for pagination)."
  def count_queue_entries(opts \\ []) do
    statuses = opts[:status]
    category = opts[:category]
    author_id = opts[:author_id]
    since = opts[:since]

    query = from(q in ContentPublishQueue)

    query =
      case statuses do
        nil -> query
        s when is_binary(s) -> where(query, [q], q.status == ^s)
        s when is_list(s) -> where(query, [q], q.status in ^s)
      end

    query = if category, do: where(query, [q], fragment("?->>'category' = ?", q.article_data, ^category)), else: query
    query = if author_id, do: where(query, [q], q.author_id == ^author_id), else: query
    query = if since, do: where(query, [q], q.inserted_at >= ^since), else: query

    Repo.aggregate(query, :count)
  end

  @doc "Count rejected entries today."
  def count_rejected_today do
    today_start = Date.utc_today() |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    from(q in ContentPublishQueue,
      where: q.status == "rejected" and q.updated_at >= ^today_start
    )
    |> Repo.aggregate(:count)
  end

  @doc "Count active feeds (not blocked, not admin-disabled)."
  def count_active_feeds do
    disabled = Settings.get(:disabled_feeds, [])

    FeedConfig.all_feeds()
    |> Enum.count(fn feed -> feed.status == :active and feed.source not in disabled end)
  end

  @doc "Count total configured feeds."
  def count_total_feeds do
    length(FeedConfig.all_feeds())
  end

  @doc """
  Get recent activity log entries (all statuses) for the dashboard.
  Returns queue entries ordered by most recently updated.
  """
  def get_recent_activity(limit \\ 20) do
    from(q in ContentPublishQueue,
      order_by: [desc: q.updated_at],
      limit: ^limit,
      preload: [:author]
    )
    |> Repo.all()
  end

  @doc """
  Get summary stats for history page.
  Returns %{published: int, rejected: int, top_category: string | nil}
  """
  def get_history_summary(since) do
    published =
      from(q in ContentPublishQueue,
        where: q.status == "published" and q.inserted_at >= ^since
      )
      |> Repo.aggregate(:count)

    rejected =
      from(q in ContentPublishQueue,
        where: q.status == "rejected" and q.inserted_at >= ^since
      )
      |> Repo.aggregate(:count)

    top_category =
      from(q in ContentPublishQueue,
        where: q.status == "published" and q.inserted_at >= ^since and not is_nil(fragment("?->>'category'", q.article_data)),
        group_by: fragment("?->>'category'", q.article_data),
        order_by: [desc: count(q.id)],
        limit: 1,
        select: fragment("?->>'category'", q.article_data)
      )
      |> Repo.one()

    %{published: published, rejected: rejected, top_category: top_category}
  end

  @doc "Get recent feed items with optional source filter."
  def get_recent_feed_items(opts \\ []) do
    source = opts[:source]
    page = opts[:page] || 1
    per_page = opts[:per_page] || 50
    offset = (page - 1) * per_page

    query = from(f in ContentFeedItem, order_by: [desc: f.fetched_at])
    query = if source && source != "", do: where(query, [f], f.source == ^source), else: query

    query
    |> limit(^per_page)
    |> offset(^offset)
    |> Repo.all()
  end

  @doc "Count total feed items with optional source filter."
  def count_feed_items(opts \\ []) do
    source = opts[:source]
    query = from(f in ContentFeedItem)
    query = if source && source != "", do: where(query, [f], f.source == ^source), else: query
    Repo.aggregate(query, :count)
  end

  @doc "Get feed item counts grouped by source (last 24h)."
  def get_feed_item_counts_by_source do
    cutoff = DateTime.utc_now() |> DateTime.add(-86400, :second)

    from(f in ContentFeedItem,
      where: f.fetched_at >= ^cutoff,
      group_by: f.source,
      select: {f.source, count(f.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc "Count published articles per author (for Authors page)."
  def count_posts_by_author do
    from(q in ContentPublishQueue,
      where: q.status == "published" and not is_nil(q.author_id),
      group_by: q.author_id,
      select: {q.author_id, count(q.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  # ── Cleanup ──

  @doc """
  Delete old feed items (>7 days) and completed queue entries (>48 hours).
  Called periodically to keep tables lean.
  """
  def cleanup_old_records do
    seven_days_ago = DateTime.utc_now() |> DateTime.add(-7 * 86400, :second)
    forty_eight_hours_ago = DateTime.utc_now() |> DateTime.add(-48 * 3600, :second)

    {feed_deleted, _} =
      from(f in ContentFeedItem, where: f.fetched_at < ^seven_days_ago)
      |> Repo.delete_all()

    {queue_deleted, _} =
      from(q in ContentPublishQueue,
        where: q.status in ["published", "rejected"] and q.updated_at < ^forty_eight_hours_ago
      )
      |> Repo.delete_all()

    {feed_deleted, queue_deleted}
  end
end
