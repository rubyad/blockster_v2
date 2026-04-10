defmodule BlocksterV2.Ads.Banner do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_placements ~w(
    sidebar_left sidebar_right article_bottom mobile_top mobile_mid mobile_bottom
    play_sidebar_left play_sidebar_right airdrop_sidebar_left airdrop_sidebar_right
    homepage_top_desktop homepage_top_mobile homepage_inline_desktop homepage_inline_mobile
    video_player_top article_inline_1 article_inline_2 article_inline_3
  )

  @valid_templates ~w(image follow_bar dark_gradient portrait split_card)

  schema "ad_banners" do
    field :name, :string
    field :image_url, :string
    field :link_url, :string
    field :placement, :string
    field :dimensions, :string
    field :is_active, :boolean, default: true
    field :impressions, :integer, default: 0
    field :clicks, :integer, default: 0
    field :start_date, :date
    field :end_date, :date
    field :template, :string, default: "image"
    field :params, :map, default: %{}
    timestamps()
  end

  @doc false
  def changeset(banner, attrs) do
    banner
    |> cast(attrs, [:name, :image_url, :link_url, :placement, :dimensions, :is_active, :start_date, :end_date, :template, :params])
    |> validate_required([:name, :placement])
    |> validate_inclusion(:placement, @valid_placements)
    |> validate_inclusion(:template, @valid_templates)
  end
end
