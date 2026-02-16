defmodule BlocksterV2.ContentAutomation.XProfileFetcher do
  @moduledoc """
  Fetch a person's recent X posts for Blockster of the Week profiles.

  Uses the brand's X API access token to pull public timeline data,
  sorts by engagement, and formats for the generation prompt.
  Returns both prompt text (for Claude) and embed tweet data (for post-generation embedding).
  """

  require Logger

  alias BlocksterV2.ContentAutomation.Config
  alias BlocksterV2.Social

  @x_api_client Application.compile_env(:blockster_v2, :x_api_client, BlocksterV2.Social.XApiClient)

  @doc """
  Fetch profile data and top tweets for a given X handle.

  Returns `{:ok, %{prompt_text: string, embed_tweets: list}}` or `{:error, reason}`.

  - `prompt_text` — formatted text to include in the Claude prompt
  - `embed_tweets` — list of `%{url: url, id: id}` for embedding as TipTap tweet nodes after generation
  """
  def fetch_profile_data(x_handle) do
    case get_brand_access_token() do
      nil ->
        {:error, :no_brand_token}

      access_token ->
        do_fetch(access_token, x_handle)
    end
  end

  defp do_fetch(access_token, x_handle) do
    clean_handle = String.trim_leading(x_handle, "@")

    with {:ok, user} <- @x_api_client.get_user_by_username(access_token, clean_handle),
         {:ok, tweets} <- @x_api_client.get_user_tweets_with_metrics(access_token, user["id"], 100) do

      # Sort by engagement (likes + retweets + quote count)
      sorted =
        tweets
        |> Enum.map(fn tweet ->
          metrics = tweet["public_metrics"] || %{}
          engagement =
            (metrics["like_count"] || 0) +
            (metrics["retweet_count"] || 0) +
            (metrics["quote_count"] || 0)

          Map.put(tweet, "engagement_score", engagement)
        end)
        |> Enum.sort_by(& &1["engagement_score"], :desc)

      # Top 20 for prompt, top 3 for embedding
      top_posts = Enum.take(sorted, 20)
      embed_tweets = build_embed_tweets(Enum.take(sorted, 3), clean_handle)
      prompt_text = format_profile_for_prompt(user, top_posts)

      Logger.info("[XProfileFetcher] Fetched #{length(tweets)} tweets for @#{clean_handle}, top 20 by engagement")

      {:ok, %{prompt_text: prompt_text, embed_tweets: embed_tweets, user: user}}
    end
  end

  defp format_profile_for_prompt(user, posts) do
    metrics = user["public_metrics"] || %{}

    header = """
    X/TWITTER PROFILE: @#{user["username"]} (#{user["name"]})
    Followers: #{metrics["followers_count"] || "unknown"}
    Following: #{metrics["following_count"] || "unknown"}
    Bio: #{user["description"] || "No bio"}
    Account created: #{user["created_at"] || "unknown"}
    """

    post_text =
      posts
      |> Enum.with_index(1)
      |> Enum.map(fn {tweet, i} ->
        tweet_metrics = tweet["public_metrics"] || %{}
        "#{i}. [#{tweet["created_at"]}] (#{tweet_metrics["like_count"] || 0} likes, " <>
        "#{tweet_metrics["retweet_count"] || 0} RTs, #{tweet_metrics["quote_count"] || 0} quotes)\n" <>
        "   #{tweet["text"]}\n"
      end)
      |> Enum.join("\n")

    header <> "\nRECENT HIGH-ENGAGEMENT POSTS:\n" <> post_text
  end

  defp build_embed_tweets(tweets, username) do
    Enum.map(tweets, fn tweet ->
      %{
        url: "https://twitter.com/#{username}/status/#{tweet["id"]}",
        id: tweet["id"]
      }
    end)
  end

  defp get_brand_access_token do
    brand_user_id = Config.brand_x_user_id()

    if is_nil(brand_user_id) do
      nil
    else
      case Social.get_x_connection_for_user(brand_user_id) do
        nil -> nil
        connection -> connection.access_token
      end
    end
  end
end
