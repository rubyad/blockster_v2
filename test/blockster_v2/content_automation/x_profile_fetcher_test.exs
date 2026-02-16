defmodule BlocksterV2.ContentAutomation.XProfileFetcherTest do
  use BlocksterV2.DataCase, async: false

  import Mox

  alias BlocksterV2.ContentAutomation.XProfileFetcher

  setup :verify_on_exit!

  describe "fetch_profile_data/1" do
    test "returns {:error, :no_brand_token} when brand X connection not configured" do
      # No BRAND_X_USER_ID set, or no X connection exists for the brand user
      assert {:error, :no_brand_token} = XProfileFetcher.fetch_profile_data("@vitalikbuterin")
    end

    test "returns {:ok, result} with prompt_text and embed_tweets on success" do
      # Set up brand access token via Mnesia x_connections
      brand_user_id = setup_brand_connection()

      # Mock X API calls
      BlocksterV2.Social.XApiClientMock
      |> expect(:get_user_by_username, fn _token, "vitalikbuterin" ->
        {:ok, %{
          "id" => "123456",
          "username" => "vitalikbuterin",
          "name" => "Vitalik Buterin",
          "description" => "Ethereum co-founder",
          "created_at" => "2011-06-20T00:00:00.000Z",
          "public_metrics" => %{
            "followers_count" => 5_000_000,
            "following_count" => 300
          }
        }}
      end)
      |> expect(:get_user_tweets_with_metrics, fn _token, "123456", 100 ->
        {:ok, [
          %{
            "id" => "tweet1",
            "text" => "Ethereum is evolving. The merge was just the beginning.",
            "created_at" => "2026-02-10T10:00:00.000Z",
            "public_metrics" => %{
              "like_count" => 50000,
              "retweet_count" => 10000,
              "quote_count" => 5000
            }
          },
          %{
            "id" => "tweet2",
            "text" => "L2s are the future of scaling.",
            "created_at" => "2026-02-09T10:00:00.000Z",
            "public_metrics" => %{
              "like_count" => 30000,
              "retweet_count" => 5000,
              "quote_count" => 2000
            }
          },
          %{
            "id" => "tweet3",
            "text" => "Privacy is a human right, not a feature.",
            "created_at" => "2026-02-08T10:00:00.000Z",
            "public_metrics" => %{
              "like_count" => 40000,
              "retweet_count" => 8000,
              "quote_count" => 3000
            }
          },
          %{
            "id" => "tweet4",
            "text" => "Less important tweet.",
            "created_at" => "2026-02-07T10:00:00.000Z",
            "public_metrics" => %{
              "like_count" => 1000,
              "retweet_count" => 100,
              "quote_count" => 50
            }
          }
        ]}
      end)

      assert {:ok, result} = XProfileFetcher.fetch_profile_data("@vitalikbuterin")

      assert is_binary(result.prompt_text)
      assert result.prompt_text =~ "vitalikbuterin"
      assert result.prompt_text =~ "5000000"
      assert result.prompt_text =~ "Ethereum co-founder"

      # embed_tweets should be top 3 by engagement
      assert length(result.embed_tweets) == 3
      assert hd(result.embed_tweets).id == "tweet1"

      # Each embed tweet should have a URL
      assert hd(result.embed_tweets).url =~ "twitter.com/vitalikbuterin/status/tweet1"
    end

    test "tweets sorted by engagement descending" do
      brand_user_id = setup_brand_connection()

      BlocksterV2.Social.XApiClientMock
      |> expect(:get_user_by_username, fn _token, "testuser" ->
        {:ok, %{
          "id" => "user1",
          "username" => "testuser",
          "name" => "Test User",
          "public_metrics" => %{"followers_count" => 100, "following_count" => 50}
        }}
      end)
      |> expect(:get_user_tweets_with_metrics, fn _token, "user1", 100 ->
        {:ok, [
          %{"id" => "low", "text" => "Low engagement", "created_at" => "2026-02-10",
            "public_metrics" => %{"like_count" => 10, "retweet_count" => 1, "quote_count" => 0}},
          %{"id" => "high", "text" => "High engagement", "created_at" => "2026-02-10",
            "public_metrics" => %{"like_count" => 1000, "retweet_count" => 100, "quote_count" => 50}},
          %{"id" => "mid", "text" => "Mid engagement", "created_at" => "2026-02-10",
            "public_metrics" => %{"like_count" => 100, "retweet_count" => 10, "quote_count" => 5}}
        ]}
      end)

      {:ok, result} = XProfileFetcher.fetch_profile_data("testuser")

      # Top 3 embed tweets should be: high, mid, low
      ids = Enum.map(result.embed_tweets, & &1.id)
      assert ids == ["high", "mid", "low"]
    end

    test "returns {:error, reason} when X API fails" do
      brand_user_id = setup_brand_connection()

      BlocksterV2.Social.XApiClientMock
      |> expect(:get_user_by_username, fn _token, "failuser" ->
        {:error, :rate_limited}
      end)

      assert {:error, :rate_limited} = XProfileFetcher.fetch_profile_data("failuser")
    end
  end

  # Set up a brand X connection in Mnesia so get_brand_access_token returns a token
  defp setup_brand_connection do
    import BlocksterV2.ContentAutomation.Factory
    ensure_mnesia_tables()

    # Create a user to be the brand user
    {:ok, user} =
      %BlocksterV2.Accounts.User{}
      |> Ecto.Changeset.change(%{
        email: "brand_test#{System.unique_integer([:positive])}@test.com",
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"
      })
      |> Repo.insert()

    # Set the BRAND_X_USER_ID config (under :content_automation key, read by Config module)
    current = Application.get_env(:blockster_v2, :content_automation, [])
    Application.put_env(:blockster_v2, :content_automation, Keyword.put(current, :brand_x_user_id, user.id))

    # Encrypt the access token for storage (Mnesia stores encrypted tokens)
    mock_token = "mock_access_token_#{System.unique_integer([:positive])}"
    encrypted_access = BlocksterV2.Encryption.encrypt(mock_token)
    encrypted_refresh = BlocksterV2.Encryption.encrypt("mock_refresh_token")
    now = DateTime.utc_now() |> DateTime.to_unix()

    # Store X connection in Mnesia with full 21-element tuple (table name + 20 attributes)
    :mnesia.dirty_write({
      :x_connections,
      user.id,                    # user_id
      "brand_x_user_id",          # x_user_id
      "blockster_brand",          # x_username
      "Blockster",                # x_name
      nil,                        # x_profile_image_url
      encrypted_access,           # access_token_encrypted
      encrypted_refresh,          # refresh_token_encrypted
      now + 3600,                 # token_expires_at
      ["tweet.read", "users.read"], # scopes
      now,                        # connected_at
      nil,                        # x_score
      nil,                        # followers_count
      nil,                        # following_count
      nil,                        # tweet_count
      nil,                        # listed_count
      nil,                        # avg_engagement_rate
      nil,                        # original_tweets_analyzed
      nil,                        # account_created_at
      nil,                        # score_calculated_at
      now                         # updated_at
    })

    on_exit(fn ->
      try do
        :mnesia.dirty_delete(:x_connections, user.id)
      rescue
        _ -> :ok
      end
      current = Application.get_env(:blockster_v2, :content_automation, [])
      Application.put_env(:blockster_v2, :content_automation, Keyword.delete(current, :brand_x_user_id))
    end)

    user.id
  end
end
