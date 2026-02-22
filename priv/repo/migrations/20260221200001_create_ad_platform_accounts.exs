defmodule BlocksterV2.Repo.Migrations.CreateAdPlatformAccounts do
  use Ecto.Migration

  def change do
    create table(:ad_platform_accounts) do
      add :platform, :string, null: false, size: 20
      add :account_name, :string, null: false, size: 100
      add :platform_account_id, :string, size: 255
      add :status, :string, default: "active", size: 20
      add :credentials_ref, :string, size: 100
      add :daily_budget_limit, :decimal, precision: 10, scale: 2
      add :monthly_budget_limit, :decimal, precision: 10, scale: 2
      add :notes, :text

      timestamps(type: :utc_datetime)
    end

    create index(:ad_platform_accounts, [:platform, :status])
  end
end
