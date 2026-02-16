defmodule BlocksterV2.Social.XApiClient do
  @moduledoc """
  Client for X (Twitter) API v2.
  Handles OAuth 2.0 with PKCE and API calls for retweets.
  """

  require Logger

  @authorize_url "https://twitter.com/i/oauth2/authorize"
  @token_url "https://api.twitter.com/2/oauth2/token"
  @api_base "https://api.twitter.com/2"

  # Scopes needed for our use case
  @scopes ["tweet.read", "tweet.write", "users.read", "like.write", "offline.access"]

  # HTTP client options for resilience
  defp req_options do
    [
      connect_options: [timeout: 30_000],
      receive_timeout: 30_000,
      retry: :transient,
      retry_delay: fn attempt -> attempt * 500 end,
      max_retries: 2
    ]
  end

  @doc """
  Returns the client ID from config.
  """
  def client_id do
    Application.get_env(:blockster_v2, :x_api)[:client_id]
  end

  @doc """
  Returns the client secret from config (for confidential clients).
  """
  def client_secret do
    Application.get_env(:blockster_v2, :x_api)[:client_secret]
  end

  @doc """
  Returns the OAuth callback URL.
  """
  def callback_url do
    Application.get_env(:blockster_v2, :x_api)[:callback_url] ||
      "#{BlocksterV2Web.Endpoint.url()}/auth/x/callback"
  end

  @doc """
  Builds the authorization URL for OAuth 2.0 with PKCE.
  """
  def authorize_url(state, code_challenge) do
    params =
      URI.encode_query(%{
        response_type: "code",
        client_id: client_id(),
        redirect_uri: callback_url(),
        scope: Enum.join(@scopes, " "),
        state: state,
        code_challenge: code_challenge,
        code_challenge_method: "S256"
      })

    "#{@authorize_url}?#{params}"
  end

  @doc """
  Exchanges an authorization code for access tokens.
  """
  def exchange_code(code, code_verifier) do
    body =
      URI.encode_query(%{
        code: code,
        grant_type: "authorization_code",
        client_id: client_id(),
        redirect_uri: callback_url(),
        code_verifier: code_verifier
      })

    case Req.post(@token_url,
           body: body,
           headers: [
             {"content-type", "application/x-www-form-urlencoded"},
             {"authorization", basic_auth_header()}
           ],
           receive_timeout: 15_000,
           connect_options: [timeout: 10_000],
           retry: :transient,
           max_retries: 2
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        parse_token_response(body)

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("X OAuth token exchange failed: #{status} - #{inspect(body)}")
        {:error, "Token exchange failed: #{status}"}

      {:error, reason} ->
        Logger.error("X OAuth token exchange error: #{inspect(reason)}")
        {:error, "Token exchange error: #{inspect(reason)}"}
    end
  end

  @doc """
  Refreshes an access token using the refresh token.
  """
  def refresh_token(refresh_token) do
    body =
      URI.encode_query(%{
        refresh_token: refresh_token,
        grant_type: "refresh_token",
        client_id: client_id()
      })

    case Req.post(@token_url,
           body: body,
           headers: [
             {"content-type", "application/x-www-form-urlencoded"},
             {"authorization", basic_auth_header()}
           ]
         ) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        parse_token_response(body)

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("X OAuth token refresh failed: #{status} - #{inspect(body)}")
        {:error, "Token refresh failed: #{status}"}

      {:error, reason} ->
        Logger.error("X OAuth token refresh error: #{inspect(reason)}")
        {:error, "Token refresh error"}
    end
  end

  @doc """
  Gets the authenticated user's profile.
  """
  def get_me(access_token) do
    url = "#{@api_base}/users/me?user.fields=profile_image_url,name,username"

    case Req.get(url, headers: [{"authorization", "Bearer #{access_token}"}]) do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        {:ok, data}

      {:ok, %Req.Response{status: 200, body: resp}} ->
        {:error, "Unexpected response: #{inspect(resp)}"}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("X API get_me failed: #{status} - #{inspect(body)}")
        {:error, "API request failed: #{status}"}

      {:error, reason} ->
        Logger.error("X API get_me error: #{inspect(reason)}")
        {:error, "API request error"}
    end
  end

  @doc """
  Creates a new tweet with the given text.
  Returns {:ok, tweet_data} or {:error, reason}.
  """
  def create_tweet(access_token, text) do
    url = "#{@api_base}/tweets"

    case Req.post(url,
           json: %{text: text},
           headers: [{"authorization", "Bearer #{access_token}"}]
         ) do
      {:ok, %Req.Response{status: status, body: body}} when status in [200, 201] ->
        {:ok, body}

      {:ok, %Req.Response{status: 403, body: %{"errors" => errors}}} ->
        error_msg = Enum.map_join(errors, ", ", & &1["message"])
        {:error, error_msg}

      {:ok, %Req.Response{status: 403}} ->
        {:error, "Forbidden - your X account may have restrictions"}

      {:ok, %Req.Response{status: 429}} ->
        {:error, "X has temporarily limited actions for your account. Limits vary by account and reset within 15 minutes."}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("X API create_tweet failed: #{status} - #{inspect(body)}")
        {:error, "Tweet failed: #{status}"}

      {:error, reason} ->
        Logger.error("X API create_tweet error: #{inspect(reason)}")
        {:error, "Tweet request error"}
    end
  end

  @doc """
  Likes a tweet.
  Returns {:ok, %{liked: true}} or {:error, reason}.
  """
  def like_tweet(access_token, user_id, tweet_id) do
    url = "#{@api_base}/users/#{user_id}/likes"

    opts =
      req_options()
      |> Keyword.merge(
        json: %{tweet_id: tweet_id},
        headers: [{"authorization", "Bearer #{access_token}"}]
      )

    case Req.post(url, opts) do
      {:ok, %Req.Response{status: 200, body: %{"data" => %{"liked" => true}}}} ->
        {:ok, %{liked: true}}

      {:ok, %Req.Response{status: 200, body: resp}} ->
        # 200 means success, even if response format is unexpected
        Logger.warning("Unexpected like response format: #{inspect(resp)}")
        {:ok, %{liked: true}}

      {:ok, %Req.Response{status: 401, body: body}} ->
        # 401 means the access token is invalid/expired - user needs to reconnect
        Logger.error("X API like failed: 401 Unauthorized - #{inspect(body)}")
        {:error, :unauthorized}

      {:ok, %Req.Response{status: 403, body: %{"errors" => errors}}} ->
        error_msg = Enum.map_join(errors, ", ", & &1["message"])
        {:error, error_msg}

      {:ok, %Req.Response{status: 403}} ->
        {:error, "Forbidden - you may have already liked this post"}

      {:ok, %Req.Response{status: 429}} ->
        {:error, "X has temporarily limited actions for your account. Limits vary by account and reset within 15 minutes."}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("X API like failed: #{status} - #{inspect(body)}")
        {:error, "Like failed: #{status}"}

      {:error, %Req.TransportError{reason: :closed}} ->
        Logger.error("X API like connection closed - network issue")
        {:error, "Connection lost - please try again"}

      {:error, %Req.TransportError{reason: :timeout}} ->
        Logger.error("X API like connection timeout")
        {:error, "Request timed out - please try again"}

      {:error, reason} ->
        Logger.error("X API like network error: #{inspect(reason)}")
        {:error, "Network error - please try again"}
    end
  end

  @doc """
  Retweets and likes a tweet in one operation.
  Returns {:ok, %{retweeted: bool, liked: bool}} or {:error, reason}.
  """
  def retweet_and_like(access_token, user_id, tweet_id) do
    retweet_result = create_retweet(access_token, user_id, tweet_id)
    like_result = like_tweet(access_token, user_id, tweet_id)

    case {retweet_result, like_result} do
      # Both succeeded
      {{:ok, _}, {:ok, _}} ->
        {:ok, %{retweeted: true, liked: true}}

      # Either returned unauthorized - user needs to reconnect
      {{:error, :unauthorized}, _} ->
        {:error, :unauthorized}

      {_, {:error, :unauthorized}} ->
        {:error, :unauthorized}

      # Retweet succeeded but like failed
      {{:ok, _}, {:error, like_error}} ->
        Logger.warning("Retweet succeeded but like failed: #{inspect(like_error)}")
        {:ok, %{retweeted: true, liked: false, like_error: like_error}}

      # Retweet failed but like succeeded
      {{:error, retweet_error}, {:ok, _}} ->
        Logger.warning("Retweet failed but like succeeded: #{inspect(retweet_error)}")
        {:ok, %{retweeted: false, liked: true, retweet_error: retweet_error}}

      # Both failed
      {{:error, retweet_error}, {:error, like_error}} ->
        {:error, "Retweet: #{inspect(retweet_error)}, Like: #{inspect(like_error)}"}
    end
  end

  @doc """
  Creates a retweet of the specified tweet.
  Returns {:ok, retweet_data} or {:error, reason}.
  """
  def create_retweet(access_token, user_id, tweet_id) do
    url = "#{@api_base}/users/#{user_id}/retweets"
    token_preview = if access_token, do: String.slice(access_token, 0, 10) <> "...", else: "nil"
    Logger.info("[X API] Attempting retweet: user_id=#{user_id}, tweet_id=#{tweet_id}, token=#{token_preview}")

    opts =
      req_options()
      |> Keyword.merge(
        json: %{tweet_id: tweet_id},
        headers: [{"authorization", "Bearer #{access_token}"}]
      )

    case Req.post(url, opts) do
      {:ok, %Req.Response{status: 200, body: %{"data" => %{"retweeted" => true}}}} ->
        {:ok, %{retweeted: true}}

      {:ok, %Req.Response{status: 200, body: resp}} ->
        # 200 means success, even if response format is unexpected
        Logger.warning("Unexpected retweet response format: #{inspect(resp)}")
        {:ok, %{retweeted: true}}

      {:ok, %Req.Response{status: 401, body: body}} ->
        # 401 means the access token is invalid/expired - user needs to reconnect
        Logger.error("X API retweet failed: 401 Unauthorized - #{inspect(body)}")
        {:error, :unauthorized}

      {:ok, %Req.Response{status: 403, body: %{"errors" => errors}}} ->
        error_msg = Enum.map_join(errors, ", ", & &1["message"])
        {:error, error_msg}

      {:ok, %Req.Response{status: 403}} ->
        {:error, "Forbidden - you may have already retweeted this post"}

      {:ok, %Req.Response{status: 429}} ->
        {:error, "X has temporarily limited actions for your account. Limits vary by account and reset within 15 minutes."}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("X API retweet failed: #{status} - #{inspect(body)}")
        {:error, "Retweet failed: #{status}"}

      {:error, %Req.TransportError{reason: :closed}} ->
        Logger.error("X API retweet connection closed - network issue")
        {:error, "Connection lost - please try again"}

      {:error, %Req.TransportError{reason: :timeout}} ->
        Logger.error("X API retweet connection timeout")
        {:error, "Request timed out - please try again"}

      {:error, reason} ->
        Logger.error("X API retweet network error: #{inspect(reason)}")
        {:error, "Network error - please try again"}
    end
  end

  @doc """
  Checks if the user has retweeted a specific tweet.
  This uses the timeline lookup - be aware of rate limits.
  """
  def check_retweet(access_token, user_id, tweet_id) do
    # Get user's recent retweets - this is limited by API
    url = "#{@api_base}/users/#{user_id}/tweets?max_results=100&tweet.fields=referenced_tweets"

    case Req.get(url, headers: [{"authorization", "Bearer #{access_token}"}]) do
      {:ok, %Req.Response{status: 200, body: %{"data" => tweets}}} ->
        retweeted =
          Enum.any?(tweets, fn tweet ->
            case tweet["referenced_tweets"] do
              nil ->
                false

              refs ->
                Enum.any?(refs, fn ref ->
                  ref["type"] == "retweeted" && ref["id"] == tweet_id
                end)
            end
          end)

        {:ok, retweeted}

      {:ok, %Req.Response{status: 200, body: %{"meta" => %{"result_count" => 0}}}} ->
        {:ok, false}

      {:ok, %Req.Response{status: 200, body: resp}} ->
        Logger.warning("Unexpected timeline response: #{inspect(resp)}")
        {:ok, false}

      {:ok, %Req.Response{status: 429}} ->
        {:error, "X has temporarily limited actions for your account. Limits vary by account and reset within 15 minutes."}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("X API check_retweet failed: #{status} - #{inspect(body)}")
        {:error, "Check failed: #{status}"}

      {:error, reason} ->
        Logger.error("X API check_retweet error: #{inspect(reason)}")
        {:error, "Check request error"}
    end
  end

  @doc """
  Gets information about a specific tweet.
  """
  def get_tweet(access_token, tweet_id) do
    url = "#{@api_base}/tweets/#{tweet_id}?tweet.fields=public_metrics,author_id"

    case Req.get(url, headers: [{"authorization", "Bearer #{access_token}"}]) do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        {:ok, data}

      {:ok, %Req.Response{status: 200, body: resp}} ->
        {:error, "Unexpected response: #{inspect(resp)}"}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("X API get_tweet failed: #{status} - #{inspect(body)}")
        {:error, "API request failed: #{status}"}

      {:error, reason} ->
        Logger.error("X API get_tweet error: #{inspect(reason)}")
        {:error, "API request error"}
    end
  end

  @doc """
  Looks up a user by their @username (handle).
  Returns {:ok, user_data} or {:error, reason}.

  user_data includes: id, username, name, description, profile_image_url, public_metrics, created_at
  """
  def get_user_by_username(access_token, username) do
    # Strip @ prefix if present
    clean_username = String.trim_leading(username, "@")
    url = "#{@api_base}/users/by/username/#{clean_username}?user.fields=public_metrics,created_at,profile_image_url,name,username,description"

    case Req.get(url, headers: [{"authorization", "Bearer #{access_token}"}]) do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        {:ok, data}

      {:ok, %Req.Response{status: 200, body: resp}} ->
        {:error, "Unexpected response: #{inspect(resp)}"}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("X API get_user_by_username failed: #{status} - #{inspect(body)}")
        {:error, "API request failed: #{status}"}

      {:error, reason} ->
        Logger.error("X API get_user_by_username error: #{inspect(reason)}")
        {:error, "API request error"}
    end
  end

  @doc """
  Gets user profile with public metrics (followers, following, tweet count, listed count).
  Returns {:ok, user_data} or {:error, reason}.
  """
  def get_user_with_metrics(access_token, user_id) do
    url = "#{@api_base}/users/#{user_id}?user.fields=public_metrics,created_at,profile_image_url,name,username"

    case Req.get(url, headers: [{"authorization", "Bearer #{access_token}"}]) do
      {:ok, %Req.Response{status: 200, body: %{"data" => data}}} ->
        {:ok, data}

      {:ok, %Req.Response{status: 200, body: resp}} ->
        {:error, "Unexpected response: #{inspect(resp)}"}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("X API get_user_with_metrics failed: #{status} - #{inspect(body)}")
        {:error, "API request failed: #{status}"}

      {:error, reason} ->
        Logger.error("X API get_user_with_metrics error: #{inspect(reason)}")
        {:error, "API request error"}
    end
  end

  @doc """
  Gets user's recent tweets with public metrics (likes, retweets, replies, quotes).
  Excludes retweets to only get original content.
  Returns {:ok, tweets} or {:error, reason}.

  max_results: 10-100 (default 50)
  """
  def get_user_tweets_with_metrics(access_token, user_id, max_results \\ 50) do
    # exclude:retweets filters out retweets, so we only get original tweets
    url = "#{@api_base}/users/#{user_id}/tweets?max_results=#{max_results}&tweet.fields=public_metrics,referenced_tweets,created_at&exclude=retweets"

    case Req.get(url, headers: [{"authorization", "Bearer #{access_token}"}]) do
      {:ok, %Req.Response{status: 200, body: %{"data" => tweets}}} ->
        # Double-check: filter out any tweets that reference other tweets (retweets/quotes)
        original_tweets = Enum.filter(tweets, fn tweet ->
          case tweet["referenced_tweets"] do
            nil -> true
            [] -> true
            refs ->
              # Keep only if no "retweeted" reference type
              not Enum.any?(refs, fn ref -> ref["type"] == "retweeted" end)
          end
        end)
        {:ok, original_tweets}

      {:ok, %Req.Response{status: 200, body: %{"meta" => %{"result_count" => 0}}}} ->
        {:ok, []}

      {:ok, %Req.Response{status: 200, body: resp}} ->
        Logger.warning("Unexpected tweets response: #{inspect(resp)}")
        {:ok, []}

      {:ok, %Req.Response{status: status, body: body}} ->
        Logger.error("X API get_user_tweets_with_metrics failed: #{status} - #{inspect(body)}")
        {:error, "API request failed: #{status}"}

      {:error, reason} ->
        Logger.error("X API get_user_tweets_with_metrics error: #{inspect(reason)}")
        {:error, "API request error"}
    end
  end

  @doc """
  Fetches all data needed for X score calculation: user metrics + recent original tweets.
  Returns {:ok, %{user: user_data, tweets: [tweet_data]}} or {:error, reason}.
  """
  def fetch_score_data(access_token, user_id) do
    with {:ok, user_data} <- get_user_with_metrics(access_token, user_id),
         {:ok, tweets} <- get_user_tweets_with_metrics(access_token, user_id, 10) do
      {:ok, %{user: user_data, tweets: tweets}}
    end
  end

  # Private functions

  defp basic_auth_header do
    credentials = "#{client_id()}:#{client_secret()}"
    encoded = Base.encode64(credentials)
    "Basic #{encoded}"
  end

  defp parse_token_response(body) when is_map(body) do
    {:ok,
     %{
       access_token: body["access_token"],
       refresh_token: body["refresh_token"],
       expires_in: body["expires_in"],
       scope: String.split(body["scope"] || "", " ")
     }}
  end

  defp parse_token_response(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, data} -> parse_token_response(data)
      {:error, _} -> {:error, "Failed to parse token response"}
    end
  end
end
