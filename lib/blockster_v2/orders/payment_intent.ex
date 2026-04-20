defmodule BlocksterV2.Orders.PaymentIntent do
  @moduledoc """
  A single SOL payment attempt tied to a shop order. The settler generates an
  ephemeral Solana keypair per intent; the buyer transfers SOL directly from
  their connected wallet to that pubkey. Once funded we sweep to treasury.

  Statuses:
    * "pending"  — awaiting buyer transfer
    * "funded"   — received >= expected_lamports, order marked paid
    * "swept"    — balance transferred out of ephemeral wallet to treasury
    * "expired"  — buyer didn't pay within the window; order is released
    * "failed"   — sweep or detection error; requires admin review
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias BlocksterV2.Orders.Order

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending funded swept expired failed)

  schema "order_payment_intents" do
    belongs_to :order, Order
    field :buyer_wallet, :string
    field :pubkey, :string
    field :expected_lamports, :integer
    field :quoted_usd, :decimal
    field :quoted_sol_usd_rate, :decimal
    field :status, :string, default: "pending"
    field :funded_tx_sig, :string
    field :funded_lamports, :integer
    field :funded_at, :utc_datetime
    field :swept_tx_sig, :string
    field :swept_at, :utc_datetime
    field :expires_at, :utc_datetime
    field :last_checked_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [
      :order_id,
      :buyer_wallet,
      :pubkey,
      :expected_lamports,
      :quoted_usd,
      :quoted_sol_usd_rate,
      :expires_at
    ])
    |> validate_required([
      :order_id,
      :buyer_wallet,
      :pubkey,
      :expected_lamports,
      :quoted_usd,
      :quoted_sol_usd_rate,
      :expires_at
    ])
    |> validate_number(:expected_lamports, greater_than: 0)
    |> unique_constraint(:order_id)
    |> unique_constraint(:pubkey)
  end

  def funded_changeset(intent, attrs) do
    intent
    |> cast(attrs, [:status, :funded_tx_sig, :funded_lamports, :funded_at, :last_checked_at])
    |> validate_inclusion(:status, @statuses)
  end

  def swept_changeset(intent, attrs) do
    intent
    |> cast(attrs, [:status, :swept_tx_sig, :swept_at])
    |> validate_inclusion(:status, @statuses)
  end

  def status_changeset(intent, status, checked_at \\ nil) when status in @statuses do
    intent
    |> cast(%{status: status, last_checked_at: checked_at}, [:status, :last_checked_at])
    |> validate_inclusion(:status, @statuses)
  end

  def statuses, do: @statuses
end
