defmodule BlocksterV2.Airdrop.Winner do
  use Ecto.Schema
  import Ecto.Changeset

  schema "airdrop_winners" do
    belongs_to :user, BlocksterV2.Accounts.User
    field :round_id, :integer
    field :winner_index, :integer
    field :random_number, :integer
    field :wallet_address, :string
    field :external_wallet, :string
    field :deposit_start, :integer
    field :deposit_end, :integer
    field :deposit_amount, :integer
    field :prize_usd, :integer
    field :prize_usdt, :integer
    field :prize_registered, :boolean, default: false
    field :claimed, :boolean, default: false
    field :claim_tx, :string
    field :claim_wallet, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [
    :round_id, :winner_index, :random_number, :wallet_address,
    :deposit_start, :deposit_end, :deposit_amount, :prize_usd, :prize_usdt
  ]
  @optional_fields [:user_id, :external_wallet, :prize_registered, :claimed, :claim_tx, :claim_wallet]

  def changeset(winner, attrs) do
    winner
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:winner_index, greater_than_or_equal_to: 0, less_than_or_equal_to: 32)
    |> validate_number(:random_number, greater_than: 0)
    |> validate_number(:prize_usd, greater_than: 0)
    |> validate_number(:prize_usdt, greater_than: 0)
    |> unique_constraint([:round_id, :winner_index])
    |> foreign_key_constraint(:user_id)
  end

  def claim_changeset(winner, attrs) do
    winner
    |> cast(attrs, [:claimed, :claim_tx, :claim_wallet])
    |> validate_required([:claimed, :claim_tx, :claim_wallet])
  end
end
