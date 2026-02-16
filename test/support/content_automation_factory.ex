defmodule BlocksterV2.ContentAutomation.Factory do
  @moduledoc "Test data factory for content automation tests."

  alias BlocksterV2.Repo
  alias BlocksterV2.ContentAutomation.ContentPublishQueue

  def build_queue_entry(attrs \\ %{}) do
    defaults = %{
      status: "pending",
      content_type: "news",
      article_data: %{
        "title" => "Test Article Title",
        "content" => build_valid_tiptap_content(),
        "excerpt" => "Test excerpt for the article",
        "category" => "bitcoin",
        "tags" => ["bitcoin", "test"],
        "featured_image" => "https://example.com/image.jpg"
      },
      author_id: 300
    }

    struct(ContentPublishQueue, Map.merge(defaults, attrs))
  end

  def insert_queue_entry(attrs \\ %{}) do
    build_queue_entry(attrs) |> Repo.insert!()
  end

  def build_feed_item(attrs \\ %{}) do
    defaults = %{
      title: "Test Feed Item",
      url: "https://example.com/article-#{System.unique_integer([:positive])}",
      source: "TestSource",
      summary: "Summary of the test feed item with enough context for clustering.",
      fetched_at: DateTime.utc_now() |> DateTime.truncate(:second)
    }

    Map.merge(defaults, attrs)
  end

  def build_valid_tiptap_content(word_count \\ 500) do
    words = 1..word_count |> Enum.map(fn _ -> "word" end) |> Enum.join(" ")

    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "heading",
          "attrs" => %{"level" => 2},
          "content" => [%{"type" => "text", "text" => "Test Heading"}]
        },
        %{
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => words}]
        },
        %{
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "Second paragraph with some content."}]
        },
        %{
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "Third paragraph for structure check."}]
        }
      ]
    }
  end

  def sample_coins do
    [
      %{id: "bitcoin", symbol: "BTC", name: "Bitcoin", current_price: 95_000.0, market_cap: 1_800_000_000_000, total_volume: 45_000_000_000, price_change_24h: 2.5, price_change_7d: 8.3, price_change_30d: 15.2, last_updated: "2026-02-15T10:00:00Z"},
      %{id: "ethereum", symbol: "ETH", name: "Ethereum", current_price: 3200.0, market_cap: 380_000_000_000, total_volume: 18_000_000_000, price_change_24h: 1.8, price_change_7d: 5.1, price_change_30d: 12.0, last_updated: "2026-02-15T10:00:00Z"},
      %{id: "solana", symbol: "SOL", name: "Solana", current_price: 180.0, market_cap: 85_000_000_000, total_volume: 4_500_000_000, price_change_24h: 4.2, price_change_7d: 12.5, price_change_30d: 25.0, last_updated: "2026-02-15T10:00:00Z"},
      %{id: "avalanche-2", symbol: "AVAX", name: "Avalanche", current_price: 42.0, market_cap: 16_000_000_000, total_volume: 800_000_000, price_change_24h: 3.1, price_change_7d: 9.8, price_change_30d: 18.0, last_updated: "2026-02-15T10:00:00Z"},
      %{id: "cardano", symbol: "ADA", name: "Cardano", current_price: 0.85, market_cap: 30_000_000_000, total_volume: 1_200_000_000, price_change_24h: -1.2, price_change_7d: 6.3, price_change_30d: 10.0, last_updated: "2026-02-15T10:00:00Z"},
      %{id: "dogecoin", symbol: "DOGE", name: "Dogecoin", current_price: 0.15, market_cap: 22_000_000_000, total_volume: 2_000_000_000, price_change_24h: 5.5, price_change_7d: 15.0, price_change_30d: 30.0, last_updated: "2026-02-15T10:00:00Z"},
      %{id: "shiba-inu", symbol: "SHIB", name: "Shiba Inu", current_price: 0.000025, market_cap: 15_000_000_000, total_volume: 1_500_000_000, price_change_24h: 6.2, price_change_7d: 18.0, price_change_30d: 35.0, last_updated: "2026-02-15T10:00:00Z"},
      %{id: "pepe", symbol: "PEPE", name: "Pepe", current_price: 0.0000012, market_cap: 5_000_000_000, total_volume: 800_000_000, price_change_24h: 8.0, price_change_7d: 22.0, price_change_30d: 40.0, last_updated: "2026-02-15T10:00:00Z"},
      %{id: "near", symbol: "NEAR", name: "NEAR Protocol", current_price: 6.50, market_cap: 7_500_000_000, total_volume: 500_000_000, price_change_24h: -2.0, price_change_7d: -8.5, price_change_30d: -15.0, last_updated: "2026-02-15T10:00:00Z"},
      %{id: "render-token", symbol: "RENDER", name: "Render", current_price: 9.20, market_cap: 4_800_000_000, total_volume: 350_000_000, price_change_24h: -3.5, price_change_7d: -12.0, price_change_30d: -20.0, last_updated: "2026-02-15T10:00:00Z"}
    ]
  end

  @doc "Ensure Mnesia tables needed for content automation tests exist."
  def ensure_mnesia_tables do
    :mnesia.start()

    tables = [
      {:content_automation_settings, [:key, :value, :updated_at, :updated_by], []},
      {:upcoming_events, [:id, :name, :event_type, :start_date, :end_date, :location, :url,
        :description, :tier, :added_by, :article_generated, :created_at], []},
      {:x_connections, [:user_id, :x_user_id, :x_username, :x_name, :x_profile_image_url,
        :access_token_encrypted, :refresh_token_encrypted, :token_expires_at, :scopes,
        :connected_at, :x_score, :followers_count, :following_count, :tweet_count,
        :listed_count, :avg_engagement_rate, :original_tweets_analyzed, :account_created_at,
        :score_calculated_at, :updated_at], [:x_user_id, :x_username]}
    ]

    for {name, attrs, index} <- tables do
      case :mnesia.create_table(name, type: :set, attributes: attrs, index: index, ram_copies: [node()]) do
        {:atomic, :ok} -> :ok
        {:aborted, {:already_exists, ^name}} -> :ok
        other -> other
      end
    end

    :ok
  end

  @doc "Create all 8 author persona users so AuthorRotator can find them."
  def create_author_personas do
    for persona <- BlocksterV2.ContentAutomation.AuthorRotator.personas() do
      case Repo.get_by(BlocksterV2.Accounts.User, email: persona.email) do
        nil ->
          {:ok, user} =
            %BlocksterV2.Accounts.User{}
            |> Ecto.Changeset.change(%{
              email: persona.email,
              wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
              is_admin: true,
              is_author: true
            })
            |> Repo.insert()
          user

        existing ->
          existing
      end
    end
  end

  def populate_altcoin_cache(coins \\ sample_coins()) do
    table = :altcoin_analyzer_cache

    if :ets.whereis(table) == :undefined do
      :ets.new(table, [:set, :public, :named_table, read_concurrency: true])
    end

    far_future = System.monotonic_time(:millisecond) + :timer.hours(24)
    :ets.insert(table, {:market_data, coins, far_future})
    coins
  end
end
