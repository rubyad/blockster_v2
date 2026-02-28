defmodule BlocksterV2.Airdrop.Round do
  use Ecto.Schema
  import Ecto.Changeset

  schema "airdrop_rounds" do
    field :round_id, :integer
    field :status, :string, default: "pending"
    field :end_time, :utc_datetime
    field :server_seed, :string
    field :commitment_hash, :string
    field :block_hash_at_close, :string
    field :total_entries, :integer, default: 0
    field :vault_address, :string
    field :prize_pool_address, :string
    field :start_round_tx, :string
    field :close_tx, :string
    field :draw_tx, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [:round_id, :status, :end_time, :commitment_hash]
  @optional_fields [
    :server_seed, :block_hash_at_close, :total_entries,
    :vault_address, :prize_pool_address,
    :start_round_tx, :close_tx, :draw_tx
  ]

  def changeset(round, attrs) do
    round
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, ["pending", "open", "closed", "drawn"])
    |> unique_constraint(:round_id)
  end

  def close_changeset(round, attrs) do
    round
    |> cast(attrs, [:status, :block_hash_at_close, :close_tx])
    |> validate_required([:status, :block_hash_at_close])
    |> validate_inclusion(:status, ["closed"])
  end

  def draw_changeset(round, attrs) do
    round
    |> cast(attrs, [:status, :draw_tx, :total_entries])
    |> validate_required([:status])
    |> validate_inclusion(:status, ["drawn"])
  end
end
