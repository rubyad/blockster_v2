defmodule BlocksterV2.ContentAutomation.TweetFinder do
  @moduledoc """
  Finds and embeds relevant third-party tweets into generated articles.

  Uses X API v2 Recent Search to find high-engagement tweets matching
  search queries suggested by Claude during content generation.

  Called after ContentGenerator returns article_data with tweet_suggestions.
  Uses TweetPlacer for smart, evenly-spaced distribution among paragraphs.

  X API Basic tier: 10,000 tweets/month read.
  ~10 articles/day * 3 queries * 30 days = ~900 searches/month.
  """

  require Logger

  alias BlocksterV2.ContentAutomation.{Config, TweetPlacer}

  @x_search_url "https://api.twitter.com/2/tweets/search/recent"
  @max_tweets_per_article 2
  @min_likes 20
  @min_author_followers 1_000

  @doc """
  Find relevant tweets and embed them into an article's TipTap content.

  Takes article_data map with :tweet_suggestions (list of search queries)
  and :content (TipTap JSON). Returns updated article_data with tweets inserted.

  Gracefully returns original article_data if X API is unavailable or no tweets found.
  """
  def find_and_embed_tweets(article_data) when is_map(article_data) do
    # X API tweet search disabled to conserve tweet read quota (15k/month cap)
    article_data
  end

  def find_and_embed_tweets(article_data), do: article_data

  @doc """
  Insert tweet nodes into TipTap content JSON.
  Uses TweetPlacer for smart distribution — evenly spaced, never stacked.
  """
  def insert_tweets_into_content(%{"type" => "doc", "content" => nodes}, tweets) do
    tweet_nodes =
      Enum.map(tweets, fn t ->
        %{"type" => "tweet", "attrs" => %{"url" => t.url, "id" => t.id}}
      end)

    # Separate existing non-tweet content from any pre-existing tweets
    content_nodes = Enum.reject(nodes, &(&1["type"] == "tweet"))
    merged = TweetPlacer.distribute_tweets(content_nodes, tweet_nodes)
    %{"type" => "doc", "content" => merged}
  end

  def insert_tweets_into_content(content, _tweets), do: content

  # ── X API Search ──

  defp search_tweets(query) do
    bearer = Config.x_bearer_token()

    if is_nil(bearer) do
      Logger.debug("[TweetFinder] No X API token configured, skipping")
      []
    else
      do_search(query, bearer)
    end
  end

  defp do_search(query, bearer) do
    # Strip $ signs to avoid X API cashtag operator errors
    sanitized_query = String.replace(query, "$", "")

    params = %{
      "query" => "#{sanitized_query} -is:retweet lang:en",
      "max_results" => "10",
      "tweet.fields" => "public_metrics,created_at,author_id",
      "expansions" => "author_id",
      "user.fields" => "username,verified,public_metrics"
    }

    case Req.get(@x_search_url,
      params: params,
      headers: [{"authorization", "Bearer #{bearer}"}],
      receive_timeout: 10_000,
      connect_options: [timeout: 5_000]
    ) do
      {:ok, %{status: 200, body: %{"data" => tweets, "includes" => %{"users" => users}}}} ->
        users_map = Map.new(users, fn u -> {u["id"], u} end)

        qualified =
          tweets
          |> Enum.filter(&meets_engagement_threshold?/1)
          |> Enum.filter(&(meets_author_threshold?(&1, users_map)))
          |> score_tweets(users_map)
          |> Enum.take(3)

        if length(tweets) > 0 && Enum.empty?(qualified) do
          best = tweets |> Enum.max_by(&tweet_likes/1)
          Logger.info("[TweetFinder] Skipped #{length(tweets)} tweets for query \"#{query}\" — " <>
            "best had #{tweet_likes(best)} likes (min: #{@min_likes})")
        end

        Enum.map(qualified, fn t ->
          user = Map.get(users_map, t["author_id"], %{})
          username = user["username"] || "unknown"

          %{
            url: "https://twitter.com/#{username}/status/#{t["id"]}",
            id: t["id"],
            username: username,
            text: t["text"]
          }
        end)

      {:ok, %{status: 200, body: %{"meta" => %{"result_count" => 0}}}} ->
        []

      {:ok, %{status: 429}} ->
        Logger.warning("[TweetFinder] X API rate limited for query: #{query}")
        []

      {:ok, %{status: status, body: body}} ->
        Logger.warning("[TweetFinder] X API returned #{status}: #{inspect(body)}")
        []

      {:error, reason} ->
        Logger.warning("[TweetFinder] X API request failed: #{inspect(reason)}")
        []
    end
  end

  defp meets_engagement_threshold?(tweet) do
    tweet_likes(tweet) >= @min_likes
  end

  defp meets_author_threshold?(tweet, users_map) do
    user = Map.get(users_map, tweet["author_id"], %{})
    followers = get_in(user, ["public_metrics", "followers_count"]) || 0
    followers >= @min_author_followers
  end

  defp score_tweets(tweets, users_map) do
    Enum.sort_by(tweets, fn t ->
      metrics = t["public_metrics"] || %{}
      likes = metrics["like_count"] || 0
      retweets = metrics["retweet_count"] || 0

      user = Map.get(users_map, t["author_id"], %{})
      followers = get_in(user, ["public_metrics", "followers_count"]) || 0
      verified = user["verified"] == true

      # Engagement score: likes + retweets weighted
      engagement = likes + retweets * 2

      # Author credibility bonus: log-scale follower boost + verified bonus
      follower_bonus = :math.log10(max(followers, 1)) * 10
      verified_bonus = if verified, do: 50, else: 0

      engagement + follower_bonus + verified_bonus
    end, :desc)
  end

  defp tweet_likes(tweet) do
    get_in(tweet, ["public_metrics", "like_count"]) || 0
  end

  # ── Helpers ──

  defp get_queries(%{"tweet_suggestions" => q}) when is_list(q), do: q
  defp get_queries(%{tweet_suggestions: q}) when is_list(q), do: q
  defp get_queries(_), do: []

  defp put_content(data, content) when is_struct(data), do: %{data | content: content}
  defp put_content(data, content) when is_map(data) do
    if Map.has_key?(data, :content), do: %{data | content: content}, else: Map.put(data, "content", content)
  end
end
