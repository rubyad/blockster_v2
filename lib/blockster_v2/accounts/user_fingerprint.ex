defmodule BlocksterV2.Accounts.UserFingerprint do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_fingerprints" do
    belongs_to :user, BlocksterV2.Accounts.User
    field :fingerprint_id, :string
    field :fingerprint_confidence, :float
    field :device_name, :string
    field :last_seen_at, :utc_datetime
    field :first_seen_at, :utc_datetime
    field :is_primary, :boolean, default: false

    timestamps()
  end

  @doc false
  def changeset(user_fingerprint, attrs) do
    user_fingerprint
    |> cast(attrs, [
      :user_id,
      :fingerprint_id,
      :fingerprint_confidence,
      :device_name,
      :last_seen_at,
      :first_seen_at,
      :is_primary
    ])
    |> validate_required([:user_id, :fingerprint_id, :first_seen_at])
    |> unique_constraint(:fingerprint_id,
      message: "This device is already registered to another account"
    )
  end
end
