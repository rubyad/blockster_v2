# Seed Phase 3 widget banners (skyscrapers) for the article page.
#
#   mix run priv/repo/seeds_widget_banners.exs
#
# Idempotent: if a banner with the same name already exists it's left alone.
# Activates both banners regardless of prior state.

alias BlocksterV2.Ads
alias BlocksterV2.Ads.Banner
alias BlocksterV2.Repo
import Ecto.Query

banners = [
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
