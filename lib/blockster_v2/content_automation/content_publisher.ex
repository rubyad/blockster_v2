defmodule BlocksterV2.ContentAutomation.ContentPublisher do
  @moduledoc """
  Publishes approved articles from the queue as blog posts.

  Handles: post creation, tag assignment, BUX pool deposit, cache update,
  and queue entry status tracking.

  Stateless module — called by ContentQueue or admin actions.
  """

  require Logger

  alias BlocksterV2.Blog
  alias BlocksterV2.EngagementTracker
  alias BlocksterV2.Social
  alias BlocksterV2.Social.XApiClient
  alias BlocksterV2.ContentAutomation.{Config, FeedStore, TipTapBuilder}

  # BUX rewards scale with article length
  # base_bux_reward is multiplied by user's engagement_score/10, multiplier, and geo_multiplier
  @bux_per_minute_read 2
  @bux_pool_multiplier 500
  @min_bux_reward 1
  @max_bux_reward 10
  @min_bux_pool 1000

  @doc """
  Publish a queue entry as a blog post.

  Takes a ContentPublishQueue entry (with article_data map and author_id).
  Creates the post, assigns tags, deposits BUX, updates cache, and marks queue entry published.

  Returns `{:ok, post}` or `{:error, reason}`.
  """
  def publish_queue_entry(%{id: queue_id, article_data: article_data, author_id: author_id} = entry) do
    pipeline_id = entry.pipeline_id || "manual"
    Logger.info("[ContentPublisher] pipeline=#{pipeline_id} Publishing: \"#{article_data["title"]}\"")

    # Only tweet if admin explicitly approved the tweet from the edit page
    skip_tweet = get_in(article_data, ["tweet_approved"]) != true

    with {:ok, category_id} <- resolve_category(article_data["category"]),
         {:ok, post} <- create_post(article_data, author_id, category_id),
         :ok <- assign_tags(post, article_data["tags"]),
         {:ok, post} <- Blog.publish_post(post),
         :ok <- deposit_bux(post, article_data),
         :ok <- update_cache(post),
         {:ok, _entry} <- FeedStore.mark_queue_entry_published(queue_id, post.id),
         :ok <- link_topic_to_post(entry.topic_id, post.id, author_id) do
      word_count = TipTapBuilder.count_words(article_data["content"])

      Logger.info(
        "[ContentPublisher] pipeline=#{pipeline_id} Published post #{post.id}: " <>
        "\"#{post.title}\" (#{word_count} words, slug: #{post.slug})"
      )

      # Post promotional tweet and create share campaign (non-blocking)
      unless skip_tweet do
        post_promotional_tweet_and_campaign(post, article_data, pipeline_id)
      end

      Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "content_automation", {:content_automation, :article_published, post})
      {:ok, post}
    else
      {:error, reason} ->
        Logger.error("[ContentPublisher] pipeline=#{pipeline_id} Publish failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Calculate BUX reward and pool size for an article based on word count.
  Returns `{base_reward, pool_size}`.
  """
  def calculate_bux(content) do
    word_count = TipTapBuilder.count_words(content)
    read_minutes = max(1, word_count / 250)

    bux_reward =
      trunc(read_minutes * @bux_per_minute_read)
      |> max(@min_bux_reward)
      |> min(@max_bux_reward)

    bux_pool = max(@min_bux_pool, bux_reward * @bux_pool_multiplier)

    {bux_reward, bux_pool}
  end

  @doc """
  Create a draft post from a queue entry (without publishing).

  Creates the post with tags but skips publish, BUX deposit, and cache update.
  Stores the post_id on the queue entry so the draft can be previewed or published later.

  Returns `{:ok, post}` or `{:error, reason}`.
  """
  def create_draft_post(%{id: queue_id, article_data: article_data, author_id: author_id} = _entry) do
    with {:ok, category_id} <- resolve_category(article_data["category"]),
         {:ok, post} <- create_post(article_data, author_id, category_id),
         :ok <- assign_tags(post, article_data["tags"]),
         {:ok, _entry} <- FeedStore.update_queue_entry(queue_id, %{post_id: post.id}) do
      Logger.info("[ContentPublisher] Draft created: post #{post.id} (#{post.slug})")
      {:ok, post}
    else
      {:error, reason} ->
        Logger.error("[ContentPublisher] Draft creation failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Delete a draft post when a queue entry is rejected.
  Only deletes if the post is unpublished (has no published_at).
  """
  def cleanup_draft_post(nil), do: :ok

  def cleanup_draft_post(post_id) do
    case BlocksterV2.Repo.get(BlocksterV2.Blog.Post, post_id) do
      nil -> :ok
      %{published_at: nil} = post ->
        Blog.delete_post(post)
        Logger.info("[ContentPublisher] Cleaned up draft post #{post_id}")
        :ok
      _ ->
        # Post is already published — don't delete
        :ok
    end
  end

  # ── Private Helpers ──

  defp create_post(article_data, author_id, category_id) do
    Blog.create_post(%{
      title: article_data["title"],
      content: article_data["content"],
      excerpt: article_data["excerpt"],
      featured_image: article_data["featured_image"],
      author_id: author_id,
      category_id: category_id,
      base_bux_reward: elem(calculate_bux(article_data["content"]), 0)
    })
  end

  defp assign_tags(post, tags) when is_list(tags) and tags != [] do
    Blog.update_post_tags(post, tags)
    :ok
  end

  defp assign_tags(_post, _tags), do: :ok

  defp deposit_bux(post, article_data) do
    {_reward, pool_size} = calculate_bux(article_data["content"])
    EngagementTracker.deposit_post_bux(post.id, pool_size)
    :ok
  end

  defp update_cache(_post) do
    # SortedPostsCache removed — posts are queried directly from DB now
    :ok
  end

  defp link_topic_to_post(nil, _post_id, _author_id), do: :ok

  defp link_topic_to_post(topic_id, post_id, author_id) do
    case BlocksterV2.Repo.get(BlocksterV2.ContentAutomation.ContentGeneratedTopic, topic_id) do
      nil -> :ok
      topic ->
        topic
        |> Ecto.Changeset.change(%{
          article_id: post_id,
          author_id: author_id,
          published_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> BlocksterV2.Repo.update()

        :ok
    end
  end

  # ── Promotional Tweet & Share Campaign ──

  @doc """
  Post a promotional tweet for a published article and create a share campaign.
  Called manually by admin from the edit page, or internally during publish if post_tweet flag is set.
  """
  def post_promotional_tweet(post, tweet_template) do
    post_promotional_tweet_and_campaign(post, %{"promotional_tweet" => tweet_template}, "manual")
  end

  defp post_promotional_tweet_and_campaign(post, article_data, pipeline_id) do
    tweet_template = article_data["promotional_tweet"]

    if is_nil(tweet_template) or tweet_template == "" do
      Logger.debug("[ContentPublisher] pipeline=#{pipeline_id} No promotional tweet template")
      :ok
    else
      article_url = "https://blockster.com/#{post.slug}"
      tweet_text = String.replace(tweet_template, "{{ARTICLE_URL}}", article_url)

      case get_brand_access_token() do
        nil ->
          Logger.warning("[ContentPublisher] pipeline=#{pipeline_id} No brand X connection — skipping tweet")
          :ok

        access_token ->
          case XApiClient.create_tweet(access_token, tweet_text) do
            {:ok, %{"data" => %{"id" => tweet_id}}} ->
              tweet_url = "https://x.com/BlocksterCom/status/#{tweet_id}"
              Logger.info("[ContentPublisher] pipeline=#{pipeline_id} Tweet posted: #{tweet_url}")

              # Create share campaign so users can earn BUX by retweeting
              case EngagementTracker.create_share_campaign(post.id, %{
                tweet_id: tweet_id,
                tweet_url: tweet_url,
                tweet_text: tweet_text,
                bux_reward: 50,
                is_active: true,
                max_participants: nil,
                starts_at: nil,
                ends_at: nil
              }) do
                {:ok, _campaign} ->
                  Logger.info("[ContentPublisher] pipeline=#{pipeline_id} Share campaign created for post #{post.id}")

                {:error, reason} ->
                  Logger.warning("[ContentPublisher] pipeline=#{pipeline_id} Campaign creation failed: #{inspect(reason)}")
              end

            {:error, reason} ->
              Logger.warning("[ContentPublisher] pipeline=#{pipeline_id} Tweet failed: #{inspect(reason)}")
          end
      end
    end
  rescue
    e ->
      Logger.error("[ContentPublisher] pipeline=#{pipeline_id} Tweet/campaign error: #{Exception.message(e)}")
      :ok
  end

  defp get_brand_access_token do
    brand_user_id = Config.brand_x_user_id()

    if is_nil(brand_user_id) do
      nil
    else
      case Social.get_x_connection_for_user(brand_user_id) do
        nil -> nil
        connection -> ensure_fresh_token(connection)
      end
    end
  end

  defp ensure_fresh_token(connection) do
    expires_at = connection.token_expires_at

    needs_refresh =
      cond do
        is_nil(expires_at) -> false
        is_struct(expires_at, DateTime) ->
          DateTime.compare(expires_at, DateTime.add(DateTime.utc_now(), 5, :minute)) == :lt
        is_integer(expires_at) ->
          expires_at < System.system_time(:second) + 300
        true -> false
      end

    if needs_refresh do
      case XApiClient.refresh_token(connection.refresh_token) do
        {:ok, token_data} ->
          expires_at = DateTime.add(DateTime.utc_now(), token_data.expires_in || 7200, :second)

          case BlocksterV2.EngagementTracker.update_x_connection_tokens(
            connection.user_id,
            token_data.access_token,
            token_data.refresh_token,
            expires_at
          ) do
            {:ok, _updated} ->
              Logger.info("[ContentPublisher] Refreshed brand X token")
              token_data.access_token

            {:error, reason} ->
              Logger.error("[ContentPublisher] Token refresh save failed: #{inspect(reason)}")
              connection.access_token
          end

        {:error, reason} ->
          Logger.error("[ContentPublisher] Brand X token refresh failed: #{inspect(reason)}")
          nil
      end
    else
      connection.access_token
    end
  end

  # ── Category Resolution ──

  # Map content automation categories to blog category slugs.
  # Creates categories on the fly if they don't exist.
  @category_map %{
    "defi" => {"DeFi", "defi"},
    "rwa" => {"Real World Assets", "rwa"},
    "regulation" => {"Regulation", "regulation"},
    "gaming" => {"Gaming", "gaming"},
    "trading" => {"Trading", "trading"},
    "token_launches" => {"Token Launches", "token-launches"},
    "gambling" => {"Gambling", "gambling"},
    "privacy" => {"Privacy", "privacy"},
    "macro_trends" => {"Macro", "macro"},
    "investment" => {"Investment", "investment"},
    "bitcoin" => {"Bitcoin", "bitcoin"},
    "ethereum" => {"Ethereum", "ethereum"},
    "altcoins" => {"Altcoins", "altcoins"},
    "nft" => {"NFT", "nft"},
    "ai_crypto" => {"AI", "ai"},
    "stablecoins" => {"Stablecoins", "stablecoins"},
    "cbdc" => {"CBDCs", "cbdc"},
    "security_hacks" => {"Security", "security"},
    "adoption" => {"Adoption", "adoption"},
    "mining" => {"Mining", "mining"},
    "fundraising" => {"Fundraising", "fundraising"},
    "events" => {"Events", "events"},
    "blockster_of_week" => {"Blockster of the Week", "blockster-of-the-week"}
  }

  defp resolve_category(category) when is_binary(category) do
    {name, slug} = Map.get(@category_map, category, {String.capitalize(category), category})

    case Blog.get_category_by_slug(slug) do
      nil ->
        case Blog.create_category(%{name: name, slug: slug}) do
          {:ok, cat} -> {:ok, cat.id}
          {:error, _} ->
            # Race condition — another node may have created it
            case Blog.get_category_by_slug(slug) do
              nil -> {:error, :category_creation_failed}
              cat -> {:ok, cat.id}
            end
        end

      cat ->
        {:ok, cat.id}
    end
  end

  defp resolve_category(_), do: {:ok, nil}
end
