defmodule BlocksterV2.Repo.Migrations.CreateConnectedWalletsAndTransfers do
  use Ecto.Migration

  def change do
    # Table: connected_wallets
    # Stores external hardware wallets connected to user accounts
    create table(:connected_wallets) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :wallet_address, :string, null: false
      add :provider, :string, null: false  # "metamask", "coinbase", "walletconnect", "phantom"
      add :chain_id, :integer, null: false  # Chain ID where wallet was connected (e.g., 560013 for Rogue Chain)
      add :is_verified, :boolean, default: false, null: false  # Whether ownership was verified via signature
      add :last_balance_sync_at, :utc_datetime  # Last time balances were fetched
      add :metadata, :map, default: %{}  # Store additional wallet info (ENS name, labels, etc.)

      timestamps()
    end

    # Indexes
    create unique_index(:connected_wallets, [:user_id])  # One wallet per user for now
    create index(:connected_wallets, [:wallet_address])
    create index(:connected_wallets, [:provider])

    # Table: wallet_transfers
    # Track token transfers between hardware wallet and Blockster smart wallet
    create table(:wallet_transfers) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :direction, :string, null: false  # "to_blockster" or "from_blockster"
      add :from_address, :string, null: false
      add :to_address, :string, null: false
      add :token_address, :string  # null for native tokens (ETH, ROGUE)
      add :token_symbol, :string, null: false  # "ROGUE", "ETH", "USDC", etc.
      add :amount, :decimal, precision: 78, scale: 18, null: false  # Support up to uint256
      add :chain_id, :integer, null: false
      add :tx_hash, :string, null: false
      add :status, :string, null: false  # "pending", "confirmed", "failed"
      add :block_number, :bigint
      add :gas_used, :bigint
      add :gas_price, :bigint
      add :confirmed_at, :utc_datetime
      add :error_message, :text

      timestamps()
    end

    # Indexes
    create index(:wallet_transfers, [:user_id])
    create index(:wallet_transfers, [:tx_hash])
    create index(:wallet_transfers, [:status])
    create index(:wallet_transfers, [:direction])
    create index(:wallet_transfers, [:inserted_at])
  end
end
