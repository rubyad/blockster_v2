defmodule BlocksterV2.AdsManager.Schemas.Attribution do
  use Ecto.Schema
  import Ecto.Changeset

  schema "ad_attributions" do
    field :utm_source, :string
    field :utm_medium, :string
    field :utm_campaign, :string
    field :utm_content, :string
    field :referral_code, :string

    field :first_visit_at, :utc_datetime
    field :signup_at, :utc_datetime
    field :first_engagement_at, :utc_datetime
    field :first_purchase_at, :utc_datetime

    belongs_to :user, BlocksterV2.Accounts.User
    belongs_to :campaign, BlocksterV2.AdsManager.Schemas.Campaign
    belongs_to :creative, BlocksterV2.AdsManager.Schemas.Creative
    belongs_to :offer, BlocksterV2.AdsManager.Schemas.Offer

    timestamps(type: :utc_datetime)
  end

  def changeset(attribution, attrs) do
    attribution
    |> cast(attrs, [:user_id, :utm_source, :utm_medium, :utm_campaign, :utm_content,
                    :referral_code, :campaign_id, :creative_id, :offer_id,
                    :first_visit_at, :signup_at, :first_engagement_at, :first_purchase_at])
  end
end
