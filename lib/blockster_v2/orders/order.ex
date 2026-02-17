defmodule BlocksterV2.Orders.Order do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "orders" do
    field :order_number, :string
    belongs_to :user, BlocksterV2.Accounts.User, type: :id
    belongs_to :referrer, BlocksterV2.Accounts.User, type: :id

    # Pricing totals (all in USD)
    field :subtotal, :decimal
    field :bux_discount_amount, :decimal, default: Decimal.new("0")
    field :bux_tokens_burned, :integer, default: 0
    field :rogue_payment_amount, :decimal, default: Decimal.new("0")
    field :rogue_discount_rate, :decimal, default: Decimal.new("0.10")
    field :rogue_discount_amount, :decimal, default: Decimal.new("0")
    field :rogue_tokens_sent, :decimal, default: Decimal.new("0")
    field :helio_payment_amount, :decimal, default: Decimal.new("0")
    field :helio_payment_currency, :string
    field :total_paid, :decimal

    # Payment tracking
    field :bux_burn_tx_hash, :string
    field :rogue_payment_tx_hash, :string
    field :rogue_usd_rate_locked, :decimal
    field :helio_charge_id, :string
    field :helio_transaction_id, :string
    field :helio_payer_address, :string

    # Shipping
    field :shipping_name, :string
    field :shipping_email, :string
    field :shipping_address_line1, :string
    field :shipping_address_line2, :string
    field :shipping_city, :string
    field :shipping_state, :string
    field :shipping_postal_code, :string
    field :shipping_country, :string
    field :shipping_phone, :string

    # Status: pending -> bux_pending -> bux_paid -> rogue_pending -> rogue_paid -> helio_pending -> paid -> processing -> shipped -> delivered
    # Also: expired (30min timeout), cancelled, refunded
    field :status, :string, default: "pending"
    field :fulfillment_notified_at, :utc_datetime
    field :notes, :string
    field :affiliate_commission_rate, :decimal, default: Decimal.new("0.05")

    # Refund tracking
    field :refund_bux_tx_hash, :string
    field :refund_rogue_tx_hash, :string
    field :refunded_at, :utc_datetime

    has_many :order_items, BlocksterV2.Orders.OrderItem, on_delete: :delete_all
    has_many :affiliate_payouts, BlocksterV2.Orders.AffiliatePayout, on_delete: :nilify_all
    timestamps(type: :utc_datetime)
  end

  @valid_statuses ~w(pending bux_pending bux_paid rogue_pending rogue_paid helio_pending paid processing shipped delivered expired cancelled refunded)

  def create_changeset(order, attrs) do
    order
    |> cast(attrs, [:order_number, :user_id, :referrer_id, :subtotal, :bux_discount_amount, :bux_tokens_burned, :total_paid, :rogue_usd_rate_locked, :affiliate_commission_rate])
    |> validate_required([:order_number, :user_id, :subtotal, :total_paid])
    |> validate_inclusion(:status, @valid_statuses)
    |> unique_constraint(:order_number)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:referrer_id)
  end

  def shipping_changeset(order, attrs) do
    order
    |> cast(attrs, [:shipping_name, :shipping_email, :shipping_address_line1, :shipping_address_line2, :shipping_city, :shipping_state, :shipping_postal_code, :shipping_country, :shipping_phone])
    |> validate_required([:shipping_name, :shipping_email, :shipping_address_line1, :shipping_city, :shipping_postal_code, :shipping_country])
    |> validate_format(:shipping_email, ~r/^[^\s]+@[^\s]+$/)
  end

  def bux_payment_changeset(order, attrs) do
    order
    |> cast(attrs, [:bux_burn_tx_hash, :bux_discount_amount, :bux_tokens_burned, :status])
    |> validate_required([:bux_burn_tx_hash])
    |> validate_inclusion(:status, @valid_statuses)
  end

  def rogue_payment_changeset(order, attrs) do
    order
    |> cast(attrs, [:rogue_payment_tx_hash, :rogue_payment_amount, :rogue_discount_rate, :rogue_discount_amount, :rogue_tokens_sent, :status])
    |> validate_inclusion(:status, @valid_statuses)
  end

  def helio_payment_changeset(order, attrs) do
    order
    |> cast(attrs, [:helio_charge_id, :helio_transaction_id, :helio_payer_address, :helio_payment_amount, :helio_payment_currency, :status])
    |> validate_inclusion(:status, @valid_statuses)
  end

  def status_changeset(order, attrs) do
    order
    |> cast(attrs, [:status, :fulfillment_notified_at, :notes])
    |> validate_inclusion(:status, @valid_statuses)
  end
end
