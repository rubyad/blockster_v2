defmodule BlocksterV2.Repo.Migrations.CreateOrdersAndOrderItems do
  use Ecto.Migration

  def change do
    create table(:orders, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_number, :string, null: false
      add :user_id, references(:users), null: false

      # Pricing totals (all in USD)
      add :subtotal, :decimal, null: false
      add :bux_discount_amount, :decimal, default: 0
      add :bux_tokens_burned, :integer, default: 0
      add :rogue_payment_amount, :decimal, default: 0
      add :rogue_discount_rate, :decimal, default: 0.10
      add :rogue_discount_amount, :decimal, default: 0
      add :rogue_tokens_sent, :decimal, default: 0
      add :helio_payment_amount, :decimal, default: 0
      add :helio_payment_currency, :string
      add :total_paid, :decimal, null: false

      # Payment tracking
      add :bux_burn_tx_hash, :string
      add :rogue_payment_tx_hash, :string
      add :rogue_usd_rate_locked, :decimal
      add :helio_charge_id, :string
      add :helio_transaction_id, :string
      add :helio_payer_address, :string

      # Shipping info
      add :shipping_name, :string
      add :shipping_email, :string
      add :shipping_address_line1, :string
      add :shipping_address_line2, :string
      add :shipping_city, :string
      add :shipping_state, :string
      add :shipping_postal_code, :string
      add :shipping_country, :string
      add :shipping_phone, :string

      # Order status
      add :status, :string, null: false, default: "pending"

      # Fulfillment
      add :fulfillment_notified_at, :utc_datetime
      add :notes, :text

      # Refund tracking
      add :refund_bux_tx_hash, :string
      add :refund_rogue_tx_hash, :string
      add :refunded_at, :utc_datetime

      # Affiliate
      add :referrer_id, references(:users)
      add :affiliate_commission_rate, :decimal, default: 0.05

      timestamps(type: :utc_datetime)
    end

    create unique_index(:orders, [:order_number])
    create index(:orders, [:user_id])
    create index(:orders, [:status])
    create index(:orders, [:helio_charge_id])
    create index(:orders, [:referrer_id])

    create table(:order_items, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :order_id, references(:orders, type: :binary_id, on_delete: :delete_all), null: false

      # Product snapshot (denormalized — prices/titles frozen at purchase time)
      add :product_id, :binary_id, null: false
      add :product_title, :string, null: false
      add :product_image, :string
      add :variant_id, :binary_id
      add :variant_title, :string
      add :quantity, :integer, null: false, default: 1
      add :unit_price, :decimal, null: false
      add :subtotal, :decimal, null: false

      # Per-item BUX discount
      add :bux_discount_amount, :decimal, default: 0
      add :bux_tokens_redeemed, :integer, default: 0

      # Fulfillment per item
      add :tracking_number, :string
      add :tracking_url, :string
      add :fulfillment_status, :string, default: "unfulfilled"

      timestamps(type: :utc_datetime)
    end

    create index(:order_items, [:order_id])
  end
end
