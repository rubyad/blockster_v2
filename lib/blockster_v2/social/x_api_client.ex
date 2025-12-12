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
  @scopes ["tweet.read", "tweet.write", "users.read", "offline.access"]

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

    headers = [
      {~c"Content-Type", ~c"application/x-www-form-urlencoded"},
      {~c"Authorization", String.to_charlist(basic_auth_header())}
    ]

    case :httpc.request(
           :post,
           {String.to_charlist(@token_url), headers, ~c"application/x-www-form-urlencoded",
            String.to_charlist(body)},
           [],
           []
         ) do
      {:ok, {{_, 200, _}, _, response_body}} ->
        parse_token_response(List.to_string(response_body))

      {:ok, {{_, status, _}, _, response_body}} ->
        Logger.error("X OAuth token exchange failed: #{status} - #{response_body}")
        {:error, "Token exchange failed: #{status}"}

      {:error, reason} ->
        Logger.error("X OAuth token exchange error: #{inspect(reason)}")
        {:error, "Token exchange error"}
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

    headers = [
      {~c"Content-Type", ~c"application/x-www-form-urlencoded"},
      {~c"Authorization", String.to_charlist(basic_auth_header())}
    ]

    case :httpc.request(
           :post,
           {String.to_charlist(@token_url), headers, ~c"application/x-www-form-urlencoded",
            String.to_charlist(body)},
           [],
           []
         ) do
      {:ok, {{_, 200, _}, _, response_body}} ->
        parse_token_response(List.to_string(response_body))

      {:ok, {{_, status, _}, _, response_body}} ->
        Logger.error("X OAuth token refresh failed: #{status} - #{response_body}")
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
    headers = [
      {~c"Authorization", String.to_charlist("Bearer #{access_token}")}
    ]

    url = "#{@api_base}/users/me?user.fields=profile_image_url,name,username"

    case :httpc.request(:get, {String.to_charlist(url), headers}, [], []) do
      {:ok, {{_, 200, _}, _, response_body}} ->
        case Jason.decode(List.to_string(response_body)) do
          {:ok, %{"data" => data}} -> {:ok, data}
          {:ok, resp} -> {:error, "Unexpected response: #{inspect(resp)}"}
          {:error, _} -> {:error, "Failed to parse response"}
        end

      {:ok, {{_, status, _}, _, response_body}} ->
        Logger.error("X API get_me failed: #{status} - #{response_body}")
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
    headers = [
      {~c"Authorization", String.to_charlist("Bearer #{access_token}")},
      {~c"Content-Type", ~c"application/json"}
    ]

    url = "#{@api_base}/tweets"
    body = Jason.encode!(%{text: text})

    case :httpc.request(
           :post,
           {String.to_charlist(url), headers, ~c"application/json", String.to_charlist(body)},
           [],
           []
         ) do
      {:ok, {{_, 201, _}, _, response_body}} ->
        case Jason.decode(List.to_string(response_body)) do
          {:ok, data} ->
            {:ok, data}

          {:error, _} ->
            {:error, "Failed to parse response"}
        end

      {:ok, {{_, 200, _}, _, response_body}} ->
        case Jason.decode(List.to_string(response_body)) do
          {:ok, data} ->
            {:ok, data}

          {:error, _} ->
            {:error, "Failed to parse response"}
        end

      {:ok, {{_, 403, _}, _, response_body}} ->
        case Jason.decode(List.to_string(response_body)) do
          {:ok, %{"errors" => errors}} ->
            error_msg = Enum.map_join(errors, ", ", & &1["message"])
            {:error, error_msg}

          _ ->
            {:error, "Forbidden - may be rate limited"}
        end

      {:ok, {{_, 429, _}, _, _response_body}} ->
        {:error, "Rate limited - please try again later"}

      {:ok, {{_, status, _}, _, response_body}} ->
        Logger.error("X API create_tweet failed: #{status} - #{response_body}")
        {:error, "Tweet failed: #{status}"}

      {:error, reason} ->
        Logger.error("X API create_tweet error: #{inspect(reason)}")
        {:error, "Tweet request error"}
    end
  end

  @doc """
  Creates a retweet of the specified tweet.
  Returns {:ok, retweet_data} or {:error, reason}.
  """
  def create_retweet(access_token, user_id, tweet_id) do
    headers = [
      {~c"Authorization", String.to_charlist("Bearer #{access_token}")},
      {~c"Content-Type", ~c"application/json"}
    ]

    url = "#{@api_base}/users/#{user_id}/retweets"
    body = Jason.encode!(%{tweet_id: tweet_id})

    case :httpc.request(
           :post,
           {String.to_charlist(url), headers, ~c"application/json", String.to_charlist(body)},
           [],
           []
         ) do
      {:ok, {{_, 200, _}, _, response_body}} ->
        case Jason.decode(List.to_string(response_body)) do
          {:ok, %{"data" => %{"retweeted" => true}}} ->
            {:ok, %{retweeted: true}}

          {:ok, resp} ->
            Logger.warning("Unexpected retweet response: #{inspect(resp)}")
            {:ok, resp}

          {:error, _} ->
            {:error, "Failed to parse response"}
        end

      {:ok, {{_, 403, _}, _, response_body}} ->
        # Could be rate limited or already retweeted
        case Jason.decode(List.to_string(response_body)) do
          {:ok, %{"errors" => errors}} ->
            error_msg = Enum.map_join(errors, ", ", & &1["message"])
            {:error, error_msg}

          _ ->
            {:error, "Forbidden - may be rate limited or already retweeted"}
        end

      {:ok, {{_, 429, _}, _, _response_body}} ->
        {:error, "Rate limited - please try again later"}

      {:ok, {{_, status, _}, _, response_body}} ->
        Logger.error("X API retweet failed: #{status} - #{response_body}")
        {:error, "Retweet failed: #{status}"}

      {:error, reason} ->
        Logger.error("X API retweet error: #{inspect(reason)}")
        {:error, "Retweet request error"}
    end
  end

  @doc """
  Checks if the user has retweeted a specific tweet.
  This uses the timeline lookup - be aware of rate limits.
  """
  def check_retweet(access_token, user_id, tweet_id) do
    headers = [
      {~c"Authorization", String.to_charlist("Bearer #{access_token}")}
    ]

    # Get user's recent retweets - this is limited by API
    url = "#{@api_base}/users/#{user_id}/tweets?max_results=100&tweet.fields=referenced_tweets"

    case :httpc.request(:get, {String.to_charlist(url), headers}, [], []) do
      {:ok, {{_, 200, _}, _, response_body}} ->
        case Jason.decode(List.to_string(response_body)) do
          {:ok, %{"data" => tweets}} ->
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

          {:ok, %{"meta" => %{"result_count" => 0}}} ->
            {:ok, false}

          {:ok, resp} ->
            Logger.warning("Unexpected timeline response: #{inspect(resp)}")
            {:ok, false}

          {:error, _} ->
            {:error, "Failed to parse response"}
        end

      {:ok, {{_, 429, _}, _, _response_body}} ->
        {:error, "Rate limited - please try again later"}

      {:ok, {{_, status, _}, _, response_body}} ->
        Logger.error("X API check_retweet failed: #{status} - #{response_body}")
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
    headers = [
      {~c"Authorization", String.to_charlist("Bearer #{access_token}")}
    ]

    url = "#{@api_base}/tweets/#{tweet_id}?tweet.fields=public_metrics,author_id"

    case :httpc.request(:get, {String.to_charlist(url), headers}, [], []) do
      {:ok, {{_, 200, _}, _, response_body}} ->
        case Jason.decode(List.to_string(response_body)) do
          {:ok, %{"data" => data}} -> {:ok, data}
          {:ok, resp} -> {:error, "Unexpected response: #{inspect(resp)}"}
          {:error, _} -> {:error, "Failed to parse response"}
        end

      {:ok, {{_, status, _}, _, response_body}} ->
        Logger.error("X API get_tweet failed: #{status} - #{response_body}")
        {:error, "API request failed: #{status}"}

      {:error, reason} ->
        Logger.error("X API get_tweet error: #{inspect(reason)}")
        {:error, "API request error"}
    end
  end

  # Private functions

  defp basic_auth_header do
    credentials = "#{client_id()}:#{client_secret()}"
    encoded = Base.encode64(credentials)
    "Basic #{encoded}"
  end

  defp parse_token_response(body) do
    case Jason.decode(body) do
      {:ok, data} ->
        {:ok,
         %{
           access_token: data["access_token"],
           refresh_token: data["refresh_token"],
           expires_in: data["expires_in"],
           scope: String.split(data["scope"] || "", " ")
         }}

      {:error, _} ->
        {:error, "Failed to parse token response"}
    end
  end
end
