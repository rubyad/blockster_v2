defmodule BlocksterV2.AdsManager.Schemas.Creative do
  use Ecto.Schema
  import Ecto.Changeset

  @types ~w(image video carousel text)
  @sources ~w(ai admin product game_asset)
  @statuses ~w(draft active paused winner loser)

  schema "ad_creatives" do
    field :platform, :string
    field :platform_creative_id, :string
    field :type, :string
    field :headline, :string
    field :body, :string
    field :cta_text, :string
    field :image_url, :string
    field :video_url, :string
    field :hashtags, {:array, :string}, default: []

    field :source, :string, default: "ai"
    field :source_details, :map
    field :admin_override, :boolean, default: false

    field :status, :string, default: "draft"
    field :impressions, :integer, default: 0
    field :clicks, :integer, default: 0
    field :conversions, :integer, default: 0
    field :performance_score, :decimal

    field :variant_group, :string
    field :is_winner, :boolean, default: false

    belongs_to :campaign, BlocksterV2.AdsManager.Schemas.Campaign

    timestamps(type: :utc_datetime)
  end

  def changeset(creative, attrs) do
    creative
    |> cast(attrs, [:campaign_id, :platform, :platform_creative_id, :type, :headline, :body,
                    :cta_text, :image_url, :video_url, :hashtags, :source, :source_details,
                    :admin_override, :status, :impressions, :clicks, :conversions,
                    :performance_score, :variant_group, :is_winner])
    |> validate_required([:platform, :type])
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:source, @sources)
    |> validate_inclusion(:status, @statuses)
  end
end
