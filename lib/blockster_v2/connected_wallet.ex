defmodule BlocksterV2.ConnectedWallet do
  use Ecto.Schema
  import Ecto.Changeset

  schema "connected_wallets" do
    belongs_to :user, BlocksterV2.Accounts.User

    field :wallet_address, :string
    field :provider, :string
    field :chain_id, :integer
    field :is_verified, :boolean, default: false
    field :last_balance_sync_at, :utc_datetime
    field :metadata, :map, default: %{}

    timestamps()
  end

  @providers ["metamask", "coinbase", "walletconnect", "phantom"]

  @doc false
  def changeset(connected_wallet, attrs) do
    connected_wallet
    |> cast(attrs, [:user_id, :wallet_address, :provider, :chain_id, :is_verified, :last_balance_sync_at, :metadata])
    |> validate_required([:user_id, :wallet_address, :provider, :chain_id])
    |> validate_inclusion(:provider, @providers)
    |> validate_format(:wallet_address, ~r/^0x[a-fA-F0-9]{40}$/, message: "must be a valid Ethereum address")
    |> unique_constraint(:user_id, message: "can only connect one wallet at a time")
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Validate provider is one of the supported wallet types
  """
  def valid_provider?(provider), do: provider in @providers
end
