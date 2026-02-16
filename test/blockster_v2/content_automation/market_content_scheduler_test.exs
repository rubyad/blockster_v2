defmodule BlocksterV2.ContentAutomation.MarketContentSchedulerTest do
  use BlocksterV2.DataCase, async: false

  import Mox

  alias BlocksterV2.ContentAutomation.{MarketContentScheduler, Settings}
  import BlocksterV2.ContentAutomation.Factory

  setup :verify_on_exit!

  setup do
    ensure_mnesia_tables()
    Settings.init_cache()
    populate_altcoin_cache()

    on_exit(fn ->
      for key <- [:last_market_movers_date, :last_narrative_ai, :last_narrative_defi,
                  :last_narrative_meme, :last_narrative_l1] do
        try do
          :mnesia.dirty_delete(:content_automation_settings, key)
          :ets.delete(:content_settings_cache, key)
        rescue
          _ -> :ok
        end
      end
    end)

    :ok
  end

  defp create_author(_) do
    [first | _] = create_author_personas()
    %{author: first}
  end

  describe "maybe_generate_weekly_movers/0" do
    setup [:create_author]

    test "returns {:error, :already_generated} when Settings has today's date" do
      today_str = Date.utc_today() |> Date.to_iso8601()
      Settings.set(:last_market_movers_date, today_str)

      assert {:error, :already_generated} = MarketContentScheduler.maybe_generate_weekly_movers()
    end

    test "sets Settings key :last_market_movers_date when generating", %{author: _author} do
      today_str = Date.utc_today() |> Date.to_iso8601()

      # Mock the Claude API call that ContentGenerator.generate_on_demand will make
      BlocksterV2.ContentAutomation.ClaudeClientMock
      |> expect(:call_with_tools, fn _prompt, _tools, _opts ->
        {:ok, %{
          "title" => "Weekly Market Movers",
          "excerpt" => "This week's biggest altcoin moves.",
          "sections" => [
            %{"type" => "heading", "level" => 2, "text" => "Market Overview"},
            %{"type" => "paragraph", "text" => String.duplicate("word ", 500)},
            %{"type" => "paragraph", "text" => "Second paragraph here."},
            %{"type" => "paragraph", "text" => "Third paragraph here."}
          ],
          "tags" => ["altcoins", "market", "movers"],
          "image_search_queries" => ["altcoin market"],
          "tweet_suggestions" => [],
          "promotional_tweet" => nil
        }}
      end)

      assert {:ok, _entry} = MarketContentScheduler.maybe_generate_weekly_movers()
      assert Settings.get(:last_market_movers_date) == today_str
    end

    test "builds params with correct template and category", %{author: _author} do
      BlocksterV2.ContentAutomation.ClaudeClientMock
      |> expect(:call_with_tools, fn prompt, _tools, _opts ->
        # Verify the prompt contains market data formatting
        assert prompt =~ "crypto market analyst" or prompt =~ "altcoin"

        {:ok, %{
          "title" => "Market Movers Test",
          "excerpt" => "Test excerpt.",
          "sections" => [
            %{"type" => "heading", "level" => 2, "text" => "Overview"},
            %{"type" => "paragraph", "text" => String.duplicate("word ", 500)},
            %{"type" => "paragraph", "text" => "Paragraph two."},
            %{"type" => "paragraph", "text" => "Paragraph three."}
          ],
          "tags" => ["altcoins", "market", "analysis"],
          "image_search_queries" => [],
          "tweet_suggestions" => [],
          "promotional_tweet" => nil
        }}
      end)

      assert {:ok, entry} = MarketContentScheduler.maybe_generate_weekly_movers()
      assert entry.content_type == "news"
      # Reload from DB so JSONB keys are consistently strings
      entry = Repo.get!(BlocksterV2.ContentAutomation.ContentPublishQueue, entry.id)
      assert entry.article_data["category"] == "altcoins"
    end
  end

  describe "maybe_generate_narrative_report/0" do
    setup [:create_author]

    test "returns {:error, :no_strong_narratives} when no sector has >10% avg change" do
      # Default test coins have sectors with moderate changes
      # Replace cache with coins that have small changes
      low_change_coins = [
        %{id: "render-token", symbol: "RENDER", name: "Render", current_price: 9.20,
          market_cap: 4_800_000_000, total_volume: 350_000_000,
          price_change_24h: 1.0, price_change_7d: 2.0, price_change_30d: 3.0,
          last_updated: "2026-02-15T10:00:00Z"},
        %{id: "near", symbol: "NEAR", name: "NEAR Protocol", current_price: 6.50,
          market_cap: 7_500_000_000, total_volume: 500_000_000,
          price_change_24h: -1.0, price_change_7d: -2.0, price_change_30d: -3.0,
          last_updated: "2026-02-15T10:00:00Z"}
      ]

      populate_altcoin_cache(low_change_coins)

      assert {:error, :no_strong_narratives} = MarketContentScheduler.maybe_generate_narrative_report()
    end

    test "skips sectors already covered within 7 days" do
      # Mark AI sector as recently covered
      today_str = Date.utc_today() |> Date.to_iso8601()
      Settings.set(:last_narrative_ai, today_str)

      # Use coins with large AI sector changes
      ai_coins = [
        %{id: "render-token", symbol: "RENDER", name: "Render", current_price: 9.20,
          market_cap: 4_800_000_000, total_volume: 350_000_000,
          price_change_24h: 15.0, price_change_7d: 25.0, price_change_30d: 40.0,
          last_updated: "2026-02-15T10:00:00Z"},
        %{id: "near", symbol: "NEAR", name: "NEAR Protocol", current_price: 6.50,
          market_cap: 7_500_000_000, total_volume: 500_000_000,
          price_change_24h: 12.0, price_change_7d: 20.0, price_change_30d: 35.0,
          last_updated: "2026-02-15T10:00:00Z"}
      ]

      populate_altcoin_cache(ai_coins)

      # Should skip AI since it was covered today, and no other sectors have >10%
      result = MarketContentScheduler.maybe_generate_narrative_report()
      assert {:error, :no_strong_narratives} = result
    end

    test "generates for sectors not covered recently", %{author: _author} do
      # Set last narrative for meme sector to >7 days ago
      old_date = Date.add(Date.utc_today(), -8) |> Date.to_iso8601()
      Settings.set(:last_narrative_meme, old_date)

      # Use coins with strong meme sector movement
      meme_coins = [
        %{id: "dogecoin", symbol: "DOGE", name: "Dogecoin", current_price: 0.15,
          market_cap: 22_000_000_000, total_volume: 2_000_000_000,
          price_change_24h: 15.0, price_change_7d: 25.0, price_change_30d: 40.0,
          last_updated: "2026-02-15T10:00:00Z"},
        %{id: "shiba-inu", symbol: "SHIB", name: "Shiba Inu", current_price: 0.000025,
          market_cap: 15_000_000_000, total_volume: 1_500_000_000,
          price_change_24h: 12.0, price_change_7d: 20.0, price_change_30d: 35.0,
          last_updated: "2026-02-15T10:00:00Z"},
        %{id: "pepe", symbol: "PEPE", name: "Pepe", current_price: 0.0000012,
          market_cap: 5_000_000_000, total_volume: 800_000_000,
          price_change_24h: 18.0, price_change_7d: 30.0, price_change_30d: 50.0,
          last_updated: "2026-02-15T10:00:00Z"}
      ]

      populate_altcoin_cache(meme_coins)

      BlocksterV2.ContentAutomation.ClaudeClientMock
      |> expect(:call_with_tools, fn _prompt, _tools, _opts ->
        {:ok, %{
          "title" => "Meme Sector Rally Analysis",
          "excerpt" => "Meme tokens are surging.",
          "sections" => [
            %{"type" => "heading", "level" => 2, "text" => "The Rotation"},
            %{"type" => "paragraph", "text" => String.duplicate("word ", 500)},
            %{"type" => "paragraph", "text" => "Analysis paragraph."},
            %{"type" => "paragraph", "text" => "Conclusion paragraph."}
          ],
          "tags" => ["meme", "altcoins", "rally"],
          "image_search_queries" => [],
          "tweet_suggestions" => [],
          "promotional_tweet" => nil
        }}
      end)

      assert {:ok, _results} = MarketContentScheduler.maybe_generate_narrative_report()
    end
  end
end
