defmodule BlocksterV2.Repo.Migrations.AddSmartWalletAddressToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :smart_wallet_address, :string
    end

    create unique_index(:users, [:smart_wallet_address])
  end
end
