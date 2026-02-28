defmodule BlocksterV2.Airdrop.Entry do
  use Ecto.Schema
  import Ecto.Changeset

  schema "airdrop_entries" do
    belongs_to :user, BlocksterV2.Accounts.User
    field :round_id, :integer
    field :wallet_address, :string
    field :external_wallet, :string
    field :amount, :integer
    field :start_position, :integer
    field :end_position, :integer
    field :deposit_tx, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [:user_id, :round_id, :wallet_address, :amount, :start_position, :end_position]
  @optional_fields [:external_wallet, :deposit_tx]

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:amount, greater_than: 0)
    |> validate_number(:start_position, greater_than: 0)
    |> validate_number(:end_position, greater_than: 0)
    |> foreign_key_constraint(:user_id)
  end
end
