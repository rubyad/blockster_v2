alias BlocksterV2.{Ads, Ads.Banner, Repo}
import Ecto.Query

square_image =
  "https://ik.imagekit.io/blockster/ads/consensus/consensus-2026-square.png?tr=w-1080,q-80"

portrait_image =
  "https://ik.imagekit.io/blockster/ads/consensus/consensus-2026-portrait.png?tr=w-1080,q-80"
link = "https://consensus.coindesk.com/"

inline_placements = ~w(homepage_inline article_inline_1 article_inline_2 article_inline_3)

banners =
  for placement <- inline_placements,
      {variant, image} <- [{"square", square_image}, {"portrait", portrait_image}] do
    %{
      name: "Consensus 2026 · #{variant} · #{placement}",
      placement: placement,
      template: "image",
      link_url: link,
      image_url: image,
      params: %{},
      sort_order: 0,
      is_active: true
    }
  end

for attrs <- banners do
  case Repo.one(from b in Banner, where: b.name == ^attrs.name) do
    nil ->
      {:ok, b} = Ads.create_banner(attrs)
      IO.puts("Created ##{b.id} [#{attrs.placement}] #{attrs.name}")

    existing ->
      {:ok, b} = Ads.update_banner(existing, Map.drop(attrs, [:name]))
      IO.puts("Updated ##{b.id} [#{attrs.placement}] #{attrs.name}")
  end
end

IO.puts("\nDone. #{length(banners)} Consensus banner row(s) upserted.")
