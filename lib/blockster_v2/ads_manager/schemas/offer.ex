defmodule BlocksterV2.AdsManager.Schemas.Offer do
  use Ecto.Schema
  import Ecto.Changeset

  @offer_types ~w(bux_giveaway shop_discount free_spins hub_trial)
  @statuses ~w(active paused exhausted expired)

  schema "ad_offers" do
    field :offer_type, :string
    field :value, :string
    field :code_prefix, :string

    field :max_redemptions, :integer
    field :current_redemptions, :integer, default: 0
    field :daily_cap, :integer

    field :budget_allocated, :decimal
    field :budget_spent, :decimal, default: Decimal.new(0)

    field :requires_phone_verification, :boolean, default: true
    field :requires_min_engagement, :boolean, default: true
    field :cooldown_days, :integer, default: 30

    field :expires_at, :utc_datetime
    field :status, :string, default: "active"

    belongs_to :campaign, BlocksterV2.AdsManager.Schemas.Campaign

    timestamps(type: :utc_datetime)
  end

  def changeset(offer, attrs) do
    offer
    |> cast(attrs, [:campaign_id, :offer_type, :value, :code_prefix, :max_redemptions,
                    :current_redemptions, :daily_cap, :budget_allocated, :budget_spent,
                    :requires_phone_verification, :requires_min_engagement, :cooldown_days,
                    :expires_at, :status])
    |> validate_required([:offer_type, :value])
    |> validate_inclusion(:offer_type, @offer_types)
    |> validate_inclusion(:status, @statuses)
  end
end
