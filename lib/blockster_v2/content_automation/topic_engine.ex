defmodule BlocksterV2.ContentAutomation.TopicEngine do
  @moduledoc """
  Analyzes unprocessed feed items every 15 minutes, clusters them into topics
  using Claude Haiku, ranks/scores them, and selects the best topics for
  content generation.

  Runs as a global singleton across the cluster (one engine per cluster).

  Pipeline: fetch items → Claude clustering → enrich → keyword blocks →
  rank/score → dedup → category diversity → select → store (two-phase)
  """

  use GenServer
  require Logger

  alias BlocksterV2.Repo
  alias BlocksterV2.ContentAutomation.{
    ClaudeClient,
    Config,
    ContentGeneratedTopic,
    ContentGenerator,
    FeedStore,
    Settings
  }

  @default_analysis_interval :timer.minutes(15)

  @categories ~w(
    defi rwa regulation gaming trading token_launches gambling privacy
    macro_trends investment bitcoin ethereum altcoins nft ai_crypto
    stablecoins cbdc security_hacks adoption mining fundraising events
  )

  # ── Client API ──

  def start_link(opts) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
  end

  @doc "Force an immediate analysis cycle (for admin dashboard)."
  def force_analyze do
    case :global.whereis_name(__MODULE__) do
      :undefined -> {:error, :not_running}
      pid -> GenServer.cast(pid, :force_analyze)
    end
  end

  @doc "Get the current state (for admin dashboard)."
  def get_state do
    case :global.whereis_name(__MODULE__) do
      :undefined -> {:error, :not_running}
      pid -> GenServer.call(pid, :get_state)
    end
  end

  # ── Server Callbacks ──

  @impl true
  def init(_opts) do
    Logger.info("[TopicEngine] Starting on #{node()}")

    # First analysis after a short delay
    Process.send_after(self(), :analyze, :timer.seconds(60))

    {:ok, %{
      last_analysis: nil,
      last_results: %{},
      total_cycles: 0
    }}
  end

  @impl true
  def handle_info(:analyze, state) do
    state = run_analysis(state)
    schedule_analysis()
    {:noreply, state}
  end

  @impl true
  def handle_cast(:force_analyze, state) do
    Logger.info("[TopicEngine] Force analysis triggered")
    state = run_analysis(state)
    {:noreply, state}
  end

  # Also accept notification from FeedPoller when new items arrive
  @impl true
  def handle_cast(:new_items_available, state) do
    Logger.debug("[TopicEngine] Notified of new feed items")
    {:noreply, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # ── Analysis Pipeline ──

  defp run_analysis(state) do
    if Settings.paused?() do
      Logger.info("[TopicEngine] Pipeline paused, skipping analysis")
      state
    else
      case analyze_and_select() do
        {:ok, selected_topics} ->
          %{state |
            last_analysis: DateTime.utc_now() |> DateTime.truncate(:second),
            last_results: %{selected: length(selected_topics)},
            total_cycles: state.total_cycles + 1
          }

        {:error, reason} ->
          Logger.error("[TopicEngine] Analysis failed: #{inspect(reason)}")
          %{state | total_cycles: state.total_cycles + 1}
      end
    end
  end

  @doc false
  def analyze_and_select do
    target_queue_size = Settings.get(:target_queue_size, 10)

    # 1. How many slots are available? (keep queue at target size, independent of published count)
    queued = FeedStore.count_queued()
    slots_available = target_queue_size - queued

    if slots_available <= 0 do
      Logger.info("[TopicEngine] Queue full (#{queued} queued, target #{target_queue_size})")
      {:ok, []}
    else
      # 2. Fetch unprocessed feed items from last 12 hours
      items = FeedStore.get_recent_unprocessed(hours: 12)

      if length(items) < 3 do
        Logger.info("[TopicEngine] Only #{length(items)} items, need at least 3 — skipping cycle")
        {:ok, []}
      else
        Logger.info("[TopicEngine] Analyzing #{length(items)} feed items for #{slots_available} available slots")

        # 3. Pre-filter for Claude (truncate summaries, cap at 50)
        batch = prepare_batch(items)

        # 4. Claude Haiku clusters items into topics
        case cluster_into_topics(batch) do
          {:ok, claude_topics} ->
            # 5. Enrich with feed item metadata
            topics = enrich_topics_with_feed_data(claude_topics, items)

            # 6. Apply keyword blocks
            topics = apply_keyword_blocks(topics)

            # 7. Score and rank
            ranked = rank_topics(topics)

            # 8. Filter already-covered topics (dedup against last 7 days)
            filtered = filter_already_covered(ranked)

            # 9. Apply category diversity
            diversified = apply_category_diversity(filtered)

            # 10. Enforce content mix (>50% news)
            mixed = enforce_content_mix(diversified)

            # 11. Take available slots
            selected = Enum.take(mixed, slots_available)

            # 11. Two-phase: store topics in PostgreSQL, THEN mark items as processed
            stored = store_and_mark_processed(selected)

            Logger.info(
              "[TopicEngine] Selected #{length(stored)} topics from #{length(claude_topics)} clusters " <>
              "(#{length(items)} feed items, #{length(ranked)} ranked, #{length(filtered)} after dedup)"
            )

            # 12. Generate articles for stored topics
            generated = generate_articles_for_topics(stored)

            Logger.info("[TopicEngine] Generated #{length(generated)} articles from #{length(stored)} topics")

            {:ok, stored}

          {:error, reason} ->
            {:error, reason}
        end
      end
    end
  end

  # ── Pre-filtering ──

  defp prepare_batch(items) do
    items
    |> Enum.map(fn item ->
      %{item | summary: truncate(item.summary, 300)}
    end)
    |> Enum.take(30)
  end

  defp truncate(nil, _max), do: ""
  defp truncate(str, max) when byte_size(str) <= max, do: str
  defp truncate(str, max), do: String.slice(str, 0, max)

  # ── Claude Haiku Clustering ──

  defp cluster_into_topics(items) do
    prompt = build_clustering_prompt(items)
    tools = clustering_tool_schema()

    case ClaudeClient.call_with_tools(prompt, tools,
      model: Config.topic_model(),
      temperature: 0.1,
      max_tokens: 16_384
    ) do
      {:ok, %{"topics" => topics}} when is_list(topics) ->
        Logger.info("[TopicEngine] Claude identified #{length(topics)} topic clusters")
        {:ok, topics}

      {:ok, other} ->
        Logger.error("[TopicEngine] Unexpected Claude output: #{inspect(other)}")
        {:error, :unexpected_output}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_clustering_prompt(items) do
    formatted = format_items_for_prompt(items)

    """
    Analyze these #{length(items)} crypto news articles and group them into distinct topics.
    Each topic should represent a single news story or theme covered by one or more articles.

    For each topic:
    - Give it a concise, specific title (not generic)
    - Assign exactly ONE category from the allowed list
    - Classify the content_type as one of:
      * "news": Factual reporting on events, announcements, data, launches, regulatory actions,
        security incidents, market movements. Report WHAT happened and WHY it matters. No editorial slant.
      * "opinion": Analysis, predictions, editorials, trend commentary, counter-narratives.
        Includes the author's perspective and editorial voice.
      * "offer": Actionable opportunities — yield farming, DEX/CEX promotions, airdrops, token launches
        with specific terms the reader can act on right now.
      DEFAULT TO "news" unless the topic clearly calls for opinion/editorial treatment or is
      a specific actionable opportunity.
    - If content_type is "offer", also set offer_type to one of:
      yield_opportunity, exchange_promotion, token_launch, airdrop, listing
    - List ALL source article URLs that cover this topic
    - Summarize the key facts across all sources
    - Suggest 2-3 original angles for a pro-decentralization, pro-individual-liberty
      commentary site. The best angle should be first.

    Articles:
    #{formatted}

    Important:
    - Every article URL must appear in exactly one topic (no duplicates, no orphans)
    - If an article doesn't fit any cluster, create a single-article topic for it
    - Prefer fewer, broader topics over many narrow ones
    - Categories must be one of: #{Enum.join(@categories, ", ")}
    """
  end

  defp format_items_for_prompt(items) do
    items
    |> Enum.with_index(1)
    |> Enum.map(fn {item, idx} ->
      source_label = if item.tier == "premium", do: "[PREMIUM] #{item.source}", else: item.source
      summary = truncate(item.summary, 300)

      "#{idx}. #{source_label}: \"#{item.title}\"\n   URL: #{item.url}\n   #{summary}\n"
    end)
    |> Enum.join("\n")
  end

  defp clustering_tool_schema do
    [%{
      "name" => "report_topics",
      "description" => "Report the clustered topics found in the news articles",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "topics" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "title" => %{"type" => "string", "description" => "Concise, specific topic title"},
                "category" => %{"type" => "string", "enum" => @categories},
                "source_urls" => %{
                  "type" => "array",
                  "items" => %{"type" => "string"},
                  "description" => "URLs of articles covering this topic"
                },
                "key_facts" => %{
                  "type" => "string",
                  "description" => "Key facts synthesized across all sources"
                },
                "angles" => %{
                  "type" => "array",
                  "items" => %{"type" => "string"},
                  "maxItems" => 3,
                  "description" => "Original commentary angles (best first)"
                },
                "content_type" => %{
                  "type" => "string",
                  "enum" => ["news", "opinion", "offer"],
                  "description" => "news = factual reporting, opinion = editorial/analysis, offer = actionable opportunity"
                },
                "offer_type" => %{
                  "type" => "string",
                  "enum" => ["yield_opportunity", "exchange_promotion", "token_launch", "airdrop", "listing"],
                  "description" => "Only set when content_type is 'offer'. Sub-type of the opportunity."
                }
              },
              "required" => ["title", "category", "source_urls", "key_facts", "angles", "content_type"]
            }
          }
        },
        "required" => ["topics"]
      }
    }]
  end

  # ── Enrich Claude Output with Feed Data ──

  defp enrich_topics_with_feed_data(claude_topics, feed_items) do
    items_by_url = Map.new(feed_items, fn item -> {item.url, item} end)

    claude_topics
    |> Enum.map(fn topic ->
      source_urls = topic["source_urls"] || []

      source_items =
        source_urls
        |> Enum.map(&Map.get(items_by_url, &1))
        |> Enum.reject(&is_nil/1)

      newest_item = Enum.max_by(source_items, & &1.published_at, DateTime, fn -> nil end)

      %{
        title: topic["title"],
        category: topic["category"],
        source_urls: source_urls,
        source_items: source_items,
        key_facts: topic["key_facts"],
        angles: topic["angles"] || [],
        selected_angle: List.first(topic["angles"] || []),
        newest_item_at: newest_item && newest_item.published_at,
        has_premium_source: Enum.any?(source_items, &(&1.tier == "premium")),
        content_type: topic["content_type"] || "news",
        offer_type: topic["offer_type"]
      }
    end)
    |> Enum.filter(fn topic -> length(topic.source_items) > 0 end)
  end

  # ── Keyword Blocks ──

  defp apply_keyword_blocks(topics) do
    blocks = Settings.get(:keyword_blocks, [])

    if Enum.empty?(blocks) do
      topics
    else
      Enum.reject(topics, fn topic ->
        title_lower = String.downcase(topic.title)

        Enum.any?(blocks, fn blocked ->
          String.contains?(title_lower, String.downcase(blocked))
        end)
      end)
    end
  end

  # ── Scoring & Ranking ──

  defp rank_topics(topics) do
    category_config = Settings.get(:category_config, %{})
    keyword_boosts = Settings.get(:keyword_boosts, [])
    now = DateTime.utc_now()

    topics
    |> Enum.map(fn topic ->
      # Source coverage: premium = 2.0, standard = 1.0
      source_score =
        topic.source_items
        |> Enum.map(fn item -> if item.tier == "premium", do: 2.0, else: 1.0 end)
        |> Enum.sum()

      # Multi-source bonus
      multi_source_bonus =
        case length(topic.source_items) do
          n when n >= 5 -> 4.0
          n when n >= 3 -> 2.0
          n when n >= 2 -> 0.5
          _ -> 0.0
        end

      # Recency bonus
      hours_old = hours_since(topic.newest_item_at)

      recency_score =
        cond do
          hours_old < 2 -> 3.0
          hours_old < 4 -> 2.0
          hours_old < 8 -> 1.0
          true -> 0.0
        end

      # Premium source bonus
      premium_bonus = if topic.has_premium_source, do: 3.0, else: 0.0

      # Admin category boost
      cat_config = Map.get(category_config, topic.category, %{})
      category_boost = Map.get(cat_config, :boost, 0)

      # Admin keyword boosts (with expiry)
      keyword_boost =
        keyword_boosts
        |> Enum.filter(fn kb ->
          expires = Map.get(kb, :expires_at)
          is_nil(expires) or DateTime.compare(expires, now) == :gt
        end)
        |> Enum.filter(fn kb ->
          String.contains?(String.downcase(topic.title), String.downcase(kb.keyword))
        end)
        |> Enum.map(& &1.boost)
        |> Enum.sum()

      total_score =
        source_score + multi_source_bonus + recency_score +
        premium_bonus + category_boost + keyword_boost

      Map.merge(topic, %{
        rank_score: total_score,
        source_count: length(topic.source_items)
      })
    end)
    |> Enum.filter(&(&1.rank_score > 0))
    |> Enum.sort_by(&(&1.rank_score), :desc)
  end

  # ── Deduplication ──

  defp filter_already_covered(topics) do
    recent_titles = FeedStore.get_generated_topic_titles(days: 7)

    Enum.reject(topics, fn topic ->
      topic_words = significant_words(topic.title)

      Enum.any?(recent_titles, fn recent_title ->
        recent_words = significant_words(recent_title)
        overlap = MapSet.intersection(topic_words, recent_words) |> MapSet.size()
        min_size = min(MapSet.size(topic_words), MapSet.size(recent_words))
        min_size > 0 and overlap / min_size > 0.6
      end)
    end)
  end

  @stopwords ~w(the a an is are was were be been being have has had do does did
    will would shall should may might can could of in to for on with
    at by from as into about between through after before its this that
    their they them these those and or but not no nor so yet also just)

  defp significant_words(title) do
    title
    |> String.downcase()
    |> String.split(~r/\W+/, trim: true)
    |> Enum.reject(&(&1 in @stopwords))
    |> MapSet.new()
  end

  # ── Category Diversity ──

  defp apply_category_diversity(ranked_topics) do
    category_config = Settings.get(:category_config, %{})
    today_counts = FeedStore.get_today_category_counts()

    {selected, _counts} =
      Enum.reduce(ranked_topics, {[], today_counts}, fn topic, {acc, counts} ->
        cat_config = Map.get(category_config, topic.category, %{})
        max_per_day = Map.get(cat_config, :max_per_day, 2)
        current = Map.get(counts, topic.category, 0)

        if current < max_per_day do
          {acc ++ [topic], Map.put(counts, topic.category, current + 1)}
        else
          Logger.debug("[TopicEngine] Skipping '#{topic.title}' — #{topic.category} hit #{max_per_day}/day limit")
          {acc, counts}
        end
      end)

    selected
  end

  # ── Content Mix Enforcement ──

  defp enforce_content_mix(topics) do
    %{news: news_count, opinion: opinion_count, offer: offer_count} =
      FeedStore.count_queued_by_content_type()

    total_queued = news_count + opinion_count + offer_count

    # Target: 50% news minimum across entire queue
    news_ratio = if total_queued > 0, do: news_count / total_queued, else: 1.0

    if news_ratio < 0.50 do
      # Prioritize news topics to restore balance
      {news_topics, other_topics} = Enum.split_with(topics, &(&1.content_type == "news"))
      news_topics ++ other_topics
    else
      topics
    end
  end

  # ── Two-Phase Processing ──

  defp store_and_mark_processed(selected_topics) do
    Enum.flat_map(selected_topics, fn topic ->
      pipeline_id = Ecto.UUID.generate()

      case Repo.transaction(fn ->
        # Phase 1: Store the topic in PostgreSQL
        {:ok, stored} =
          %ContentGeneratedTopic{}
          |> ContentGeneratedTopic.changeset(%{
            title: topic.title,
            category: topic.category,
            source_urls: topic.source_urls,
            rank_score: topic.rank_score,
            source_count: topic.source_count,
            pipeline_id: pipeline_id,
            content_type: topic.content_type || "news",
            offer_type: topic.offer_type
          })
          |> Repo.insert()

        # Phase 2: Mark source feed items as processed (only after topic is safely stored)
        FeedStore.mark_items_processed(topic.source_urls, stored.id)

        Map.merge(topic, %{
          id: stored.id,
          pipeline_id: pipeline_id
        })
      end) do
        {:ok, stored_topic} ->
          Logger.info("[TopicEngine] Stored topic: \"#{topic.title}\" (pipeline=#{pipeline_id}, score=#{topic.rank_score})")
          [stored_topic]

        {:error, reason} ->
          Logger.error("[TopicEngine] Failed to store topic \"#{topic.title}\": #{inspect(reason)}")
          []
      end
    end)
  end

  # ── Content Generation ──

  defp generate_articles_for_topics(stored_topics) do
    Enum.flat_map(stored_topics, fn topic ->
      # Load the full topic with feed_items from DB
      case FeedStore.get_topic_for_generation(topic.id) do
        nil ->
          Logger.error("[TopicEngine] Could not load topic #{topic.id} for generation")
          []

        db_topic ->
          # Merge runtime data (angles, key_facts) with DB topic
          generation_topic = %{
            id: db_topic.id,
            title: db_topic.title,
            category: db_topic.category,
            pipeline_id: topic.pipeline_id,
            feed_items: db_topic.feed_items,
            key_facts: topic[:key_facts],
            selected_angle: topic[:selected_angle],
            angles: topic[:angles] || []
          }

          try do
            case ContentGenerator.generate_article(generation_topic) do
              {:ok, _entry} -> [topic.id]
              {:error, _reason} -> []
            end
          rescue
            e ->
              Logger.error("[TopicEngine] Generation crashed for \"#{topic.title}\": #{Exception.message(e)}")
              []
          end
      end
    end)
  end

  # ── Helpers ──

  defp hours_since(nil), do: 999

  defp hours_since(timestamp) do
    diff = DateTime.diff(DateTime.utc_now(), timestamp, :second)
    if diff >= 0, do: div(diff, 3600), else: 0
  end

  defp schedule_analysis do
    interval =
      Application.get_env(:blockster_v2, :content_automation, [])[:topic_analysis_interval] ||
        @default_analysis_interval

    Process.send_after(self(), :analyze, interval)
  end
end
