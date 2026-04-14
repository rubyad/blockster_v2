defmodule BlocksterV2.Ads.Banner do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_placements ~w(
    sidebar_left sidebar_right article_bottom mobile_top mobile_mid mobile_bottom
    play_sidebar_left play_sidebar_right airdrop_sidebar_left airdrop_sidebar_right
    homepage_top_desktop homepage_top_mobile homepage_inline_desktop homepage_inline_mobile
    homepage_inline video_player_top article_inline_1 article_inline_2 article_inline_3
  )

  @valid_templates ~w(image follow_bar dark_gradient portrait split_card)

  @valid_widget_types ~w(
    rt_skyscraper rt_square_compact rt_sidebar_tile rt_chart_landscape rt_chart_portrait
    rt_full_card rt_ticker rt_leaderboard_inline
    fs_skyscraper fs_hero_portrait fs_hero_landscape fs_ticker fs_square_compact fs_sidebar_tile
  )

  def valid_widget_types, do: @valid_widget_types

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
    field :sort_order, :integer, default: 0
    field :widget_type, :string
    field :widget_config, :map, default: %{}
    timestamps()
  end

  @doc false
  def changeset(banner, attrs) do
    banner
    |> cast(attrs, [
      :name,
      :image_url,
      :link_url,
      :placement,
      :dimensions,
      :is_active,
      :start_date,
      :end_date,
      :template,
      :params,
      :sort_order,
      :widget_type,
      :widget_config
    ])
    |> validate_required([:name, :placement])
    |> validate_inclusion(:placement, @valid_placements)
    |> validate_inclusion(:template, @valid_templates)
    |> validate_widget_type()
    |> maybe_require_image_url()
  end

  defp validate_widget_type(changeset) do
    case get_field(changeset, :widget_type) do
      nil -> changeset
      _ -> validate_inclusion(changeset, :widget_type, @valid_widget_types)
    end
  end

  defp maybe_require_image_url(changeset) do
    case get_field(changeset, :widget_type) do
      nil -> validate_required(changeset, [:image_url])
      _ -> changeset
    end
  end
end
