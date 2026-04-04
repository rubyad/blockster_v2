defmodule BlocksterV2.Ads.Banner do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_placements ~w(sidebar_left sidebar_right mobile_top mobile_mid mobile_bottom)

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
    timestamps()
  end

  @doc false
  def changeset(banner, attrs) do
    banner
    |> cast(attrs, [:name, :image_url, :link_url, :placement, :dimensions, :is_active, :start_date, :end_date])
    |> validate_required([:name, :placement])
    |> validate_inclusion(:placement, @valid_placements)
  end
end
