defmodule BlocksterV2.Accounts.PhoneVerification do
  use Ecto.Schema
  import Ecto.Changeset

  schema "phone_verifications" do
    field :phone_number, :string
    field :country_code, :string
    field :carrier_name, :string
    field :line_type, :string
    field :geo_tier, :string
    field :geo_multiplier, :decimal
    field :verification_sid, :string
    field :verified, :boolean, default: false
    field :verified_at, :utc_datetime
    field :attempts, :integer, default: 0
    field :last_attempt_at, :utc_datetime
    field :fraud_flags, :map
    field :sms_opt_in, :boolean, default: true

    belongs_to :user, BlocksterV2.Accounts.User

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(phone_verification, attrs) do
    phone_verification
    |> cast(attrs, [
      :phone_number,
      :country_code,
      :carrier_name,
      :line_type,
      :geo_tier,
      :geo_multiplier,
      :verification_sid,
      :verified,
      :verified_at,
      :attempts,
      :last_attempt_at,
      :fraud_flags,
      :sms_opt_in,
      :user_id
    ])
    |> validate_required([:phone_number, :country_code, :geo_tier, :geo_multiplier, :user_id])
    |> validate_inclusion(:geo_tier, ["premium", "standard", "basic"])
    |> validate_number(:geo_multiplier, greater_than_or_equal_to: 0.5, less_than_or_equal_to: 5.0)
    |> validate_format(:phone_number, ~r/^\+[1-9]\d{1,14}$/, message: "must be in E.164 format")
    |> unique_constraint(:phone_number,
      name: :phone_verifications_phone_number_unique,
      message: "This phone number is already registered")
    |> foreign_key_constraint(:user_id)
  end
end
