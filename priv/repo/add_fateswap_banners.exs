# One-off seed: disables every existing active banner at `article_inline_1`
# and `homepage_inline`, then upserts 4 new FateSwap rows (2 ads × 2
# placements) all pointing to https://fateswap.io.
#
# Run with:
#   mix run priv/repo/add_fateswap_banners.exs
#
# Re-runnable: `upsert_fateswap/1` looks up by :name, so running twice
# won't create duplicates. The disable step targets ANY active banner at
# those placements other than the FateSwap names.

import Ecto.Query
alias BlocksterV2.Repo
alias BlocksterV2.Ads.Banner

fateswap_names = [
  "FateSwap · A2 Combined · article_inline_1",
  "FateSwap · Kinetic Hero · article_inline_1",
  "FateSwap · A2 Combined · homepage_inline",
  "FateSwap · Kinetic Hero · homepage_inline"
]

placements = ["article_inline_1", "homepage_inline"]

# 1. Disable every active banner at the target placements EXCEPT the
#    FateSwap rows we're about to upsert. The admin can re-enable them
#    later via /admin/banners.
{disabled_count, _} =
  Repo.update_all(
    from(b in Banner,
      where: b.is_active == true,
      where: b.placement in ^placements,
      where: b.name not in ^fateswap_names
    ),
    set: [is_active: false, updated_at: DateTime.utc_now() |> DateTime.truncate(:second)]
  )

IO.puts("Disabled #{disabled_count} existing banners at #{Enum.join(placements, ", ")}")

# 2. Upsert the 4 FateSwap rows.
upsert = fn attrs ->
  case Repo.get_by(Banner, name: attrs.name) do
    nil ->
      %Banner{}
      |> Banner.changeset(attrs)
      |> Repo.insert!()
      |> then(fn b -> IO.puts("  created #{b.name}") end)

    existing ->
      existing
      |> Banner.changeset(attrs)
      |> Repo.update!()
      |> then(fn b -> IO.puts("  updated #{b.name}") end)
  end
end

# image_url is required by the schema for non-widget banners, but the
# FateSwap templates never render the DB image_url (all imagery is
# inlined in HTML/SVG or loaded from CoinGecko). Pass the landing URL
# as a placeholder.
placeholder_image = "https://fateswap.io"
link_url = "https://fateswap.io"

rows = [
  %{
    name: "FateSwap · A2 Combined · article_inline_1",
    placement: "article_inline_1",
    template: "fateswap_combined",
    link_url: link_url,
    image_url: placeholder_image,
    params: %{},
    sort_order: 0,
    is_active: true
  },
  %{
    name: "FateSwap · Kinetic Hero · article_inline_1",
    placement: "article_inline_1",
    template: "fateswap_kinetic",
    link_url: link_url,
    image_url: placeholder_image,
    params: %{},
    sort_order: 1,
    is_active: true
  },
  %{
    name: "FateSwap · A2 Combined · homepage_inline",
    placement: "homepage_inline",
    template: "fateswap_combined",
    link_url: link_url,
    image_url: placeholder_image,
    params: %{},
    sort_order: 0,
    is_active: true
  },
  %{
    name: "FateSwap · Kinetic Hero · homepage_inline",
    placement: "homepage_inline",
    template: "fateswap_kinetic",
    link_url: link_url,
    image_url: placeholder_image,
    params: %{},
    sort_order: 1,
    is_active: true
  }
]

IO.puts("Upserting #{length(rows)} FateSwap banners…")
Enum.each(rows, upsert)

active_counts =
  Enum.map(placements, fn p ->
    n =
      Banner
      |> where([b], b.is_active == true and b.placement == ^p)
      |> Repo.aggregate(:count, :id)

    {p, n}
  end)

IO.puts("\nActive banners per placement:")
for {p, n} <- active_counts, do: IO.puts("  #{p}: #{n}")
IO.puts("\nDone.")
