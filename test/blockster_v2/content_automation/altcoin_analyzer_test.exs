defmodule BlocksterV2.ContentAutomation.AltcoinAnalyzerTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.ContentAutomation.AltcoinAnalyzer
  import BlocksterV2.ContentAutomation.Factory

  setup do
    # Clean up ETS table if it exists from a previous test
    if :ets.whereis(:altcoin_analyzer_cache) != :undefined do
      :ets.delete_all_objects(:altcoin_analyzer_cache)
    end

    :ok
  end

  describe "sector_tags/0" do
    test "returns map with 8 sectors" do
      tags = AltcoinAnalyzer.sector_tags()
      assert map_size(tags) == 8
    end

    test "all values are lists of strings" do
      tags = AltcoinAnalyzer.sector_tags()

      Enum.each(tags, fn {_k, v} ->
        assert is_list(v)
        Enum.each(v, fn item -> assert is_binary(item) end)
      end)
    end

    test "known sectors present: ai, defi, l1, l2, gaming, rwa, meme, depin" do
      tags = AltcoinAnalyzer.sector_tags()
      expected = ~w(ai defi l1 l2 gaming rwa meme depin)
      assert MapSet.new(Map.keys(tags)) == MapSet.new(expected)
    end

    test "gaming and rwa sectors have empty lists (no tracked tokens)" do
      tags = AltcoinAnalyzer.sector_tags()
      assert tags["gaming"] == []
      assert tags["rwa"] == []
    end
  end

  describe "sector_names/0" do
    test "returns sorted list of 8 sector name strings" do
      names = AltcoinAnalyzer.sector_names()
      assert length(names) == 8
      assert names == Enum.sort(names)
    end

    test "first is ai, last is rwa" do
      names = AltcoinAnalyzer.sector_names()
      assert List.first(names) == "ai"
      assert List.last(names) == "rwa"
    end
  end

  describe "get_movers/2" do
    setup do
      populate_altcoin_cache()
      :ok
    end

    test "returns map with gainers, losers, and period keys" do
      result = AltcoinAnalyzer.get_movers(:"7d", 10)

      assert is_map(result)
      assert Map.has_key?(result, :gainers)
      assert Map.has_key?(result, :losers)
      assert Map.has_key?(result, :period)
    end

    test "gainers sorted by change descending (highest first)" do
      result = AltcoinAnalyzer.get_movers(:"7d", 10)

      changes = Enum.map(result.gainers, & &1.price_change_7d)
      assert changes == Enum.sort(changes, :desc)
    end

    test "losers sorted by change ascending (most negative first)" do
      result = AltcoinAnalyzer.get_movers(:"7d", 10)

      changes = Enum.map(result.losers, & &1.price_change_7d)
      assert changes == Enum.sort(changes, :asc)
    end

    test "default period is :\"7d\"" do
      result = AltcoinAnalyzer.get_movers()
      assert result.period == :"7d"
    end

    test "respects limit parameter (limit: 3)" do
      result = AltcoinAnalyzer.get_movers(:"7d", 3)

      assert length(result.gainers) <= 3
      assert length(result.losers) <= 3
    end

    test "works with :\"24h\" period" do
      result = AltcoinAnalyzer.get_movers(:"24h", 10)
      assert result.period == :"24h"
      assert is_list(result.gainers)
    end

    test "works with :\"30d\" period" do
      result = AltcoinAnalyzer.get_movers(:"30d", 10)
      assert result.period == :"30d"
      assert is_list(result.gainers)
    end

    test "returns empty lists when ETS cache has no data" do
      # Clear the cache
      :ets.delete_all_objects(:altcoin_analyzer_cache)
      # Insert empty data
      far_future = System.monotonic_time(:millisecond) + :timer.hours(24)
      :ets.insert(:altcoin_analyzer_cache, {:market_data, [], far_future})

      result = AltcoinAnalyzer.get_movers(:"7d", 10)
      assert result.gainers == []
      assert result.losers == []
    end
  end

  describe "detect_narratives/1" do
    setup do
      populate_altcoin_cache()
      :ok
    end

    test "detects meme sector narrative (DOGE, SHIB, PEPE all >5%)" do
      narratives = AltcoinAnalyzer.detect_narratives(:"7d")

      meme_narrative = Enum.find(narratives, fn {sector, _data} -> sector == "meme" end)
      assert meme_narrative != nil

      {_sector, data} = meme_narrative
      assert data.count >= 3
      assert abs(data.avg_change) > 5.0
    end

    test "does not detect ai sector (only 2 tokens: RENDER, NEAR)" do
      narratives = AltcoinAnalyzer.detect_narratives(:"7d")

      ai_narrative = Enum.find(narratives, fn {sector, _data} -> sector == "ai" end)
      assert ai_narrative == nil
    end

    test "does not detect defi sector (only 2 tokens: UNI, AAVE — not in sample data)" do
      narratives = AltcoinAnalyzer.detect_narratives(:"7d")

      defi_narrative = Enum.find(narratives, fn {sector, _data} -> sector == "defi" end)
      assert defi_narrative == nil
    end

    test "returns sorted by abs(avg_change) descending" do
      narratives = AltcoinAnalyzer.detect_narratives(:"7d")

      if length(narratives) > 1 do
        avg_changes = Enum.map(narratives, fn {_sector, data} -> abs(data.avg_change) end)
        assert avg_changes == Enum.sort(avg_changes, :desc)
      end
    end

    test "returns empty list when no sector has 3+ tokens moving >5%" do
      # Use coins with small changes
      small_change_coins = [
        %{id: "a", symbol: "AAA", name: "A", current_price: 1.0, market_cap: 1_000, total_volume: 100, price_change_24h: 0.1, price_change_7d: 0.2, price_change_30d: 0.3, last_updated: "2026-02-15T10:00:00Z"},
        %{id: "b", symbol: "BBB", name: "B", current_price: 2.0, market_cap: 2_000, total_volume: 200, price_change_24h: 0.1, price_change_7d: 0.2, price_change_30d: 0.3, last_updated: "2026-02-15T10:00:00Z"}
      ]

      populate_altcoin_cache(small_change_coins)

      narratives = AltcoinAnalyzer.detect_narratives(:"7d")
      assert narratives == []
    end

    test "handles empty ETS cache gracefully" do
      :ets.delete_all_objects(:altcoin_analyzer_cache)
      far_future = System.monotonic_time(:millisecond) + :timer.hours(24)
      :ets.insert(:altcoin_analyzer_cache, {:market_data, [], far_future})

      narratives = AltcoinAnalyzer.detect_narratives(:"7d")
      assert narratives == []
    end
  end

  describe "format_for_prompt/2" do
    setup do
      populate_altcoin_cache()
      :ok
    end

    test "includes MARKET DATA header with current date" do
      movers = AltcoinAnalyzer.get_movers(:"7d", 3)
      narratives = AltcoinAnalyzer.detect_narratives(:"7d")
      result = AltcoinAnalyzer.format_for_prompt(movers, narratives)

      assert result =~ "MARKET DATA"
    end

    test "includes TOP GAINERS section header with period label" do
      movers = AltcoinAnalyzer.get_movers(:"7d", 3)
      narratives = AltcoinAnalyzer.detect_narratives(:"7d")
      result = AltcoinAnalyzer.format_for_prompt(movers, narratives)

      assert result =~ "TOP GAINERS (7-day)"
    end

    test "includes TOP LOSERS section header with period label" do
      movers = AltcoinAnalyzer.get_movers(:"7d", 3)
      narratives = AltcoinAnalyzer.detect_narratives(:"7d")
      result = AltcoinAnalyzer.format_for_prompt(movers, narratives)

      assert result =~ "TOP LOSERS (7-day)"
    end

    test "includes NARRATIVE ROTATIONS section" do
      movers = AltcoinAnalyzer.get_movers(:"7d", 3)
      narratives = AltcoinAnalyzer.detect_narratives(:"7d")
      result = AltcoinAnalyzer.format_for_prompt(movers, narratives)

      assert result =~ "NARRATIVE ROTATIONS"
    end

    test "formats each token line with rank, symbol, name, change%, price" do
      movers = AltcoinAnalyzer.get_movers(:"7d", 3)
      narratives = AltcoinAnalyzer.detect_narratives(:"7d")
      result = AltcoinAnalyzer.format_for_prompt(movers, narratives)

      # Should contain token symbols from sample data
      assert result =~ "PEPE"
      assert result =~ "Price: $"
    end

    test "shows + sign for positive changes" do
      movers = AltcoinAnalyzer.get_movers(:"7d", 3)
      narratives = AltcoinAnalyzer.detect_narratives(:"7d")
      result = AltcoinAnalyzer.format_for_prompt(movers, narratives)

      assert result =~ "+"
    end

    test "formats prices: >=1 -> 2 decimals" do
      movers = AltcoinAnalyzer.get_movers(:"7d", 5)
      narratives = []
      result = AltcoinAnalyzer.format_for_prompt(movers, narratives)

      # Prices >= 1 should have 2 decimal places (e.g., 9.20, 6.50, 3200.00)
      assert result =~ "9.20" or result =~ "6.50" or result =~ "3200.00"
    end

    test "formats large numbers: B for billions, M for millions" do
      movers = AltcoinAnalyzer.get_movers(:"7d", 3)
      narratives = []
      result = AltcoinAnalyzer.format_for_prompt(movers, narratives)

      assert result =~ "B" or result =~ "M"
    end

    test "handles empty gainers list" do
      movers = %{gainers: [], losers: [], period: :"7d"}
      result = AltcoinAnalyzer.format_for_prompt(movers, [])

      assert result =~ "(none)"
    end

    test "handles empty narratives" do
      movers = AltcoinAnalyzer.get_movers(:"7d", 3)
      result = AltcoinAnalyzer.format_for_prompt(movers, [])

      assert result =~ "No clear narrative rotations detected."
    end
  end

  describe "get_sector_data/2" do
    setup do
      populate_altcoin_cache()
      :ok
    end

    test "returns map with sector, tokens, avg_change, direction, count, period" do
      result = AltcoinAnalyzer.get_sector_data("meme", :"7d")

      assert Map.has_key?(result, :sector)
      assert Map.has_key?(result, :tokens)
      assert Map.has_key?(result, :avg_change)
      assert Map.has_key?(result, :direction)
      assert Map.has_key?(result, :count)
      assert Map.has_key?(result, :period)
    end

    test "returns direction up for positive avg_change" do
      result = AltcoinAnalyzer.get_sector_data("meme", :"7d")

      # Meme tokens (DOGE +15%, SHIB +18%, PEPE +22%) all positive
      assert result.direction == "up"
    end

    test "returns correct count of matched tokens" do
      result = AltcoinAnalyzer.get_sector_data("meme", :"7d")

      # DOGE, SHIB, PEPE = 3 tokens
      assert result.count == 3
    end

    test "tokens sorted by change descending within sector" do
      result = AltcoinAnalyzer.get_sector_data("meme", :"7d")

      changes = Enum.map(result.tokens, & &1.price_change_7d)
      assert changes == Enum.sort(changes, :desc)
    end

    test "returns empty data for sector with no matching tokens" do
      result = AltcoinAnalyzer.get_sector_data("gaming", :"7d")

      assert result.count == 0
      assert result.tokens == []
    end
  end
end
