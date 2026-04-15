defmodule BlocksterV2Web.Widgets.RtSkyscraperTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias BlocksterV2.Ads.Banner
  alias BlocksterV2Web.Widgets.RtSkyscraper

  defp banner(overrides \\ %{}) do
    struct(%Banner{
      id: 202,
      name: "rt-test",
      placement: "sidebar_right",
      widget_type: "rt_skyscraper"
    }, overrides)
  end

  defp bot(overrides) do
    Map.merge(
      %{
        "bot_id" => "hermes",
        "slug" => "hermes",
        "name" => "HERMES",
        "group_name" => "crypto",
        "lp_price" => 1.2456,
        "bid_price" => 1.2331,
        "ask_price" => 1.2581,
        "sol_balance_ui" => 486.34,
        "lp_price_change_24h_pct" => 12.4,
        "market_open" => true,
        "rank" => 1
      },
      overrides
    )
  end

  defp render_widget(assigns) do
    render_component(&RtSkyscraper.rt_skyscraper/1, assigns)
  end

  describe "skeleton" do
    test "renders root with data-banner-id, hook, widget click subject" do
      html = render_widget(%{banner: banner(%{id: 9}), bots: []})

      assert html =~ ~s(data-banner-id="9")
      assert html =~ ~s(phx-hook="RtSkyscraperWidget")
      assert html =~ ~s(phx-click="widget_click")
      assert html =~ ~s(phx-value-subject="rt")
      assert html =~ "bw-widget"
      assert html =~ "bw-shell"
    end

    test "renders header: logo, TRADER overlay, LIVE pill, TOP ROGUEBOTS subtitle" do
      html = render_widget(%{banner: banner(), bots: []})

      assert html =~ "rogue-logo-white.png"
      assert html =~ "TRADER"
      assert html =~ "LIVE"
      assert html =~ "TOP ROGUEBOTS"
    end

    test "renders footer with Open RogueTrader link text" do
      html = render_widget(%{banner: banner(), bots: []})

      assert html =~ "Open RogueTrader"
    end

    test "renders shimmer skeleton when bots is []" do
      html = render_widget(%{banner: banner(), bots: []})

      assert html =~ "bw-skeleton"
      assert html =~ "rt-skyscraper-skeleton"
    end

    test "renders tracker error placeholder when bots is [] and tracker_error? is true" do
      html = render_widget(%{banner: banner(), bots: [], tracker_error?: true})

      assert html =~ "RogueTrader feed paused"
      refute html =~ "rt-skyscraper-skeleton"
    end
  end

  describe "bot rows" do
    test "renders a crypto bot row with 4-decimal prices + group tag + rank + change% + market dot" do
      html = render_widget(%{banner: banner(), bots: [bot(%{})]})

      assert html =~ ~s(data-bot-id="hermes")
      assert html =~ "HERMES"
      assert html =~ "#1"
      assert html =~ "CRYPTO"
      # Bid/ask rendered with 4 decimals
      assert html =~ "1.2331"
      assert html =~ "1.2581"
      # AUM, 2 decimals
      assert html =~ "486.34"
      # Change % with sign + arrow + magnitude
      assert html =~ "+12.4%"
      # Market dot + Open label
      assert html =~ "Open"
    end

    test "renders a closed-market bot with Closed dot and grey label" do
      html =
        render_widget(%{
          banner: banner(),
          bots: [bot(%{"bot_id" => "wolf", "name" => "WOLF", "group_name" => "equities", "market_open" => false})]
        })

      assert html =~ "WOLF"
      assert html =~ "EQUITIES"
      assert html =~ "Closed"
    end

    test "covers every locked-in group tag" do
      groups = ~w(crypto equities indexes commodities forex)

      bots =
        for {g, i} <- Enum.with_index(groups, 1) do
          bot(%{"bot_id" => "bot-#{i}", "name" => "BOT#{i}", "group_name" => g, "lp_price" => 1.0 / i})
        end

      html = render_widget(%{banner: banner(), bots: bots})

      for g <- groups do
        assert html =~ String.upcase(g)
      end
    end

    test "sorts bots by lp_price desc regardless of input order" do
      bots = [
        bot(%{"bot_id" => "a", "name" => "A", "lp_price" => 0.5}),
        bot(%{"bot_id" => "b", "name" => "B", "lp_price" => 2.0}),
        bot(%{"bot_id" => "c", "name" => "C", "lp_price" => 1.0})
      ]

      html = render_widget(%{banner: banner(), bots: bots})

      idx_a = :binary.match(html, "data-bot-id=\"a\"") |> elem(0)
      idx_b = :binary.match(html, "data-bot-id=\"b\"") |> elem(0)
      idx_c = :binary.match(html, "data-bot-id=\"c\"") |> elem(0)

      assert idx_b < idx_c
      assert idx_c < idx_a
    end

    test "caps visible rows at 30 even with more bots" do
      bots =
        for i <- 1..40 do
          bot(%{"bot_id" => "bot-#{i}", "name" => "BOT#{i}", "lp_price" => i * 1.0})
        end

      html = render_widget(%{banner: banner(), bots: bots})

      # Bot with highest lp_price (40) should render; bot with lowest (11 or below) should not.
      assert html =~ ~s(data-bot-id="bot-40")
      refute html =~ ~s(data-bot-id="bot-1")
    end
  end

  describe "resilience" do
    test "handles bots without change % gracefully" do
      html =
        render_widget(%{
          banner: banner(),
          bots: [bot(%{"lp_price_change_24h_pct" => nil, "lp_price_change_7d_pct" => nil})]
        })

      assert html =~ "HERMES"
    end

    test "handles missing group_name gracefully (falls back to empty tag class)" do
      html = render_widget(%{banner: banner(), bots: [bot(%{"group_name" => nil})]})

      assert html =~ "HERMES"
    end
  end
end
