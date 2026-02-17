defmodule BlocksterV2.Orders.AffiliatePayout do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "affiliate_payouts" do
    belongs_to :order, BlocksterV2.Orders.Order
    belongs_to :referrer, BlocksterV2.Accounts.User, type: :id
    field :currency, :string
    field :basis_amount, :decimal
    field :commission_rate, :decimal, default: Decimal.new("0.05")
    field :commission_amount, :decimal
    field :commission_usd_value, :decimal
    field :status, :string, default: "pending"
    field :held_until, :utc_datetime
    field :paid_at, :utc_datetime
    field :tx_hash, :string
    field :failure_reason, :string
    timestamps(type: :utc_datetime)
  end

  @valid_statuses ~w(pending held paid failed)
  @valid_currencies ~w(BUX ROGUE USDC SOL ETH BTC CARD)
  @required_fields [:order_id, :referrer_id, :currency, :basis_amount, :commission_rate, :commission_amount]
  @optional_fields [:commission_usd_value, :status, :held_until, :paid_at, :tx_hash, :failure_reason]

  def changeset(payout, attrs) do
    payout
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_inclusion(:currency, @valid_currencies)
    |> validate_number(:commission_rate, greater_than: 0, less_than_or_equal_to: 1)
    |> foreign_key_constraint(:order_id)
    |> foreign_key_constraint(:referrer_id)
  end
end
