defmodule BlocksterV2.AdsManager.Schemas.OfferCode do
  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(available reserved redeemed expired)

  schema "ad_offer_codes" do
    field :code, :string
    field :status, :string, default: "available"
    field :redeemed_at, :utc_datetime
    field :inserted_at, :utc_datetime

    belongs_to :offer, BlocksterV2.AdsManager.Schemas.Offer
    belongs_to :user, BlocksterV2.Accounts.User
  end

  def changeset(code, attrs) do
    code
    |> cast(attrs, [:offer_id, :code, :user_id, :status, :redeemed_at])
    |> validate_required([:code])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint(:code)
    |> put_change(:inserted_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end
end
