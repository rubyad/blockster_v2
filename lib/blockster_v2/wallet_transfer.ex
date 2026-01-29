defmodule BlocksterV2.WalletTransfer do
  use Ecto.Schema
  import Ecto.Changeset

  schema "wallet_transfers" do
    belongs_to :user, BlocksterV2.Accounts.User

    field :direction, :string
    field :from_address, :string
    field :to_address, :string
    field :token_address, :string
    field :token_symbol, :string
    field :amount, :decimal
    field :chain_id, :integer
    field :tx_hash, :string
    field :status, :string
    field :block_number, :integer
    field :gas_used, :integer
    field :gas_price, :integer
    field :confirmed_at, :utc_datetime
    field :error_message, :string

    timestamps()
  end

  @directions ["to_blockster", "from_blockster"]
  @statuses ["pending", "confirmed", "failed"]

  @doc false
  def changeset(wallet_transfer, attrs) do
    wallet_transfer
    |> cast(attrs, [
      :user_id, :direction, :from_address, :to_address, :token_address, :token_symbol,
      :amount, :chain_id, :tx_hash, :status, :block_number, :gas_used, :gas_price,
      :confirmed_at, :error_message
    ])
    |> validate_required([:user_id, :direction, :from_address, :to_address, :token_symbol, :amount, :chain_id, :tx_hash, :status])
    |> validate_inclusion(:direction, @directions)
    |> validate_inclusion(:status, @statuses)
    |> validate_format(:from_address, ~r/^0x[a-fA-F0-9]{40}$/)
    |> validate_format(:to_address, ~r/^0x[a-fA-F0-9]{40}$/)
    |> validate_number(:amount, greater_than: 0)
    |> foreign_key_constraint(:user_id)
  end
end
