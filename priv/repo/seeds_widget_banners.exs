# Seed Phase 3 + Phase 4 widget banners for the article page and homepage.
#
#   mix run priv/repo/seeds_widget_banners.exs
#
# Idempotent: if a banner with the same name already exists, it's reactivated
# rather than duplicated.

alias BlocksterV2.Ads
alias BlocksterV2.Ads.Banner
alias BlocksterV2.Repo
import Ecto.Query

banners = [
  # ── Phase 3 ─────────────────────────────────────────────────────────────
  %{
    name: "RogueTrader · Top RogueBots (right sidebar)",
    placement: "sidebar_right",
    widget_type: "rt_skyscraper",
    widget_config: %{},
    link_url: "https://roguetrader.io",
    is_active: true,
    sort_order: 0
  },
  %{
    name: "FateSwap · Live Trades (left sidebar)",
    placement: "sidebar_left",
    widget_type: "fs_skyscraper",
    widget_config: %{},
    link_url: "https://fateswap.io",
    is_active: true,
    sort_order: 0
  },

  # ── Phase 4 (chart widgets) ─────────────────────────────────────────────
  %{
    name: "RogueTrader · Chart landscape · biggest gainer",
    placement: "article_inline_1",
    widget_type: "rt_chart_landscape",
    widget_config: %{"selection" => "biggest_gainer"},
    link_url: "https://roguetrader.io",
    is_active: true,
    sort_order: 10
  },
  %{
    name: "RogueTrader · Chart portrait · biggest mover",
    placement: "article_inline_2",
    widget_type: "rt_chart_portrait",
    widget_config: %{"selection" => "biggest_mover"},
    link_url: "https://roguetrader.io",
    is_active: true,
    sort_order: 20
  },
  %{
    name: "RogueTrader · Full card · highest AUM",
    placement: "article_inline_3",
    widget_type: "rt_full_card",
    widget_config: %{"selection" => "highest_aum"},
    link_url: "https://roguetrader.io",
    is_active: true,
    sort_order: 30
  },
  %{
    name: "RogueTrader · Square compact · top ranked",
    placement: "sidebar_right",
    widget_type: "rt_square_compact",
    widget_config: %{"selection" => "top_ranked"},
    link_url: "https://roguetrader.io",
    is_active: true,
    sort_order: 40
  },

  # ── Phase 5 (tickers, leaderboard, FateSwap heroes) ─────────────────────
  %{
    name: "RogueTrader · Ticker · homepage top desktop",
    placement: "homepage_top_desktop",
    widget_type: "rt_ticker",
    widget_config: %{},
    link_url: "https://roguetrader.io",
    is_active: true,
    sort_order: 50
  },
  %{
    name: "FateSwap · Ticker · homepage top mobile",
    placement: "homepage_top_mobile",
    widget_type: "fs_ticker",
    widget_config: %{},
    link_url: "https://fateswap.io",
    is_active: true,
    sort_order: 60
  },
  %{
    name: "RogueTrader · Leaderboard · homepage inline desktop",
    placement: "homepage_inline_desktop",
    widget_type: "rt_leaderboard_inline",
    widget_config: %{},
    link_url: "https://roguetrader.io",
    is_active: true,
    sort_order: 70
  },
  %{
    name: "FateSwap · Hero portrait · biggest profit",
    placement: "article_inline_2",
    widget_type: "fs_hero_portrait",
    widget_config: %{"selection" => "biggest_profit"},
    link_url: "https://fateswap.io",
    is_active: true,
    sort_order: 80
  },
  %{
    name: "FateSwap · Hero landscape · biggest discount",
    placement: "homepage_inline",
    widget_type: "fs_hero_landscape",
    widget_config: %{"selection" => "biggest_discount"},
    link_url: "https://fateswap.io",
    is_active: true,
    sort_order: 90
  }
]

for attrs <- banners do
  case Repo.one(from b in Banner, where: b.name == ^attrs.name) do
    nil ->
      {:ok, banner} = Ads.create_banner(attrs)
      IO.puts("Created widget banner ##{banner.id}: #{banner.name}")

    existing ->
      {:ok, banner} = Ads.update_banner(existing, %{is_active: true})
      IO.puts("Kept widget banner ##{banner.id}: #{banner.name} (reactivated)")
  end
end
