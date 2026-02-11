defmodule BlocksterV2Web.Plugs.OgMetaPlug do
  @moduledoc """
  Sets Open Graph and Twitter Card meta tag assigns on the conn
  so the root layout can render them in <head> for social media crawlers.
  """
  import Plug.Conn

  alias BlocksterV2.Blog

  @default_title "Blockster"
  @default_description "Web3's daily content hub — Earn BUX, redeem rewards, and stay plugged into crypto, blockchain, and the future of finance."
  @default_image "https://ik.imagekit.io/blockster/blockster-icon.png"

  # Single-segment routes that are NOT post slugs
  @non_post_routes ~w(
    login play airdrop how-it-works privacy terms cookies events hubs shop
    shop-landing waitlist new onboarding admin profile settings
  )

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.path_info do
      [slug] when slug not in @non_post_routes ->
        set_post_meta(conn, slug)

      _ ->
        set_defaults(conn)
    end
  end

  defp set_post_meta(conn, slug) do
    case Blog.get_post_by_slug(slug) do
      %{title: title, excerpt: excerpt, featured_image: featured_image} = _post ->
        url = "#{BlocksterV2Web.Endpoint.url()}/#{slug}"

        conn
        |> assign(:og_title, title)
        |> assign(:og_description, excerpt || @default_description)
        |> assign(:og_image, featured_image || @default_image)
        |> assign(:og_url, url)
        |> assign(:og_type, "article")

      _ ->
        set_defaults(conn)
    end
  end

  defp set_defaults(conn) do
    conn
    |> assign(:og_title, @default_title)
    |> assign(:og_description, @default_description)
    |> assign(:og_image, @default_image)
    |> assign(:og_url, BlocksterV2Web.Endpoint.url())
    |> assign(:og_type, "website")
  end
end
