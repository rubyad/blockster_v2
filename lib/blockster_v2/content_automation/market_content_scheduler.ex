defmodule BlocksterV2.ContentAutomation.MarketContentScheduler do
  @moduledoc """
  Schedules and triggers market analysis content generation.

  - Weekly Market Movers: Generates on Fridays (day 5)
  - Narrative Reports: Auto-generates when a sector moves >10%, self-gates via Settings
  """

  require Logger

  alias BlocksterV2.ContentAutomation.{AltcoinAnalyzer, ContentGenerator, Settings}

  @doc """
  Generate a weekly market movers article if not already done today.
  Called by ContentQueue on Fridays or manually via dashboard.
  Returns {:ok, entry} or {:error, reason}.
  """
  def maybe_generate_weekly_movers do
    today = Date.utc_today()
    today_str = Date.to_iso8601(today)
    last_generated = Settings.get(:last_market_movers_date)

    if last_generated == today_str do
      Logger.info("[MarketContentScheduler] Weekly movers already generated today")
      {:error, :already_generated}
    else
      Logger.info("[MarketContentScheduler] Generating weekly market movers")
      Settings.set(:last_market_movers_date, today_str)

      movers = AltcoinAnalyzer.get_movers(:"7d", 10)
      narratives = AltcoinAnalyzer.detect_narratives(:"7d")
      market_data = AltcoinAnalyzer.format_for_prompt(movers, narratives)
      news_context = AltcoinAnalyzer.get_recent_news_for_tokens(movers)

      params = %{
        topic: "This Week's Biggest Altcoin Moves — #{format_date_range()}",
        category: "altcoins",
        content_type: "news",
        instructions: market_data <> "\n\nRELEVANT NEWS CONTEXT:\n" <> news_context,
        template: "market_movers"
      }

      case ContentGenerator.generate_on_demand(params) do
        {:ok, entry} ->
          Logger.info("[MarketContentScheduler] Weekly movers generated: \"#{entry.article_data["title"]}\"")
          {:ok, entry}

        {:error, reason} ->
          Logger.error("[MarketContentScheduler] Weekly movers generation failed: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  @doc """
  Check for strong narrative rotations and generate reports.
  Only generates when a sector moves >10% and hasn't been covered in 7 days.
  Self-gates via Settings keys like :last_narrative_ai, :last_narrative_defi, etc.
  """
  def maybe_generate_narrative_report do
    narratives = AltcoinAnalyzer.detect_narratives(:"7d")

    strong_narratives =
      Enum.filter(narratives, fn {_sector, data} ->
        abs(data.avg_change) > 10.0
      end)

    results =
      for {sector, data} <- strong_narratives,
          not already_covered_narrative?(sector) do
        generate_narrative_for_sector(sector, data)
      end

    case results do
      [] -> {:error, :no_strong_narratives}
      _ -> {:ok, results}
    end
  end

  # ── Private ──

  defp generate_narrative_for_sector(sector, data) do
    settings_key = String.to_atom("last_narrative_#{sector}")
    today_str = Date.to_iso8601(Date.utc_today())
    Settings.set(settings_key, today_str)

    sector_data = AltcoinAnalyzer.get_sector_data(sector)
    direction = if data.avg_change >= 0, do: "rallying", else: "declining"

    movers_for_prompt = %{
      gainers: data.tokens,
      losers: [],
      period: :"7d"
    }

    market_data = AltcoinAnalyzer.format_for_prompt(movers_for_prompt, [{sector, data}])
    news_context = AltcoinAnalyzer.get_recent_news_for_tokens(movers_for_prompt)

    params = %{
      topic: "The #{String.capitalize(sector)} Sector Is #{String.capitalize(direction)} — Here's Why",
      category: "altcoins",
      content_type: "opinion",
      instructions: market_data <> "\n\nRELEVANT NEWS CONTEXT:\n" <> news_context,
      template: "narrative_analysis",
      sector: sector,
      sector_data: sector_data
    }

    case ContentGenerator.generate_on_demand(params) do
      {:ok, entry} ->
        Logger.info("[MarketContentScheduler] Narrative report generated for #{sector}: \"#{entry.article_data["title"]}\"")
        {:ok, entry}

      {:error, reason} ->
        Logger.error("[MarketContentScheduler] Narrative report failed for #{sector}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp already_covered_narrative?(sector) do
    settings_key = String.to_atom("last_narrative_#{sector}")
    last_date_str = Settings.get(settings_key)

    if last_date_str do
      case Date.from_iso8601(last_date_str) do
        {:ok, last_date} ->
          Date.diff(Date.utc_today(), last_date) < 7

        _ ->
          false
      end
    else
      false
    end
  end

  defp format_date_range do
    today = Date.utc_today()
    week_start = Date.add(today, -7)
    "#{Calendar.strftime(week_start, "%B %d")} — #{Calendar.strftime(today, "%B %d, %Y")}"
  end
end
