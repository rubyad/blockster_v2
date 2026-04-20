defmodule BlocksterV2.Repo.Migrations.CreateNewsletterSubscriptions do
  use Ecto.Migration

  def change do
    create table(:newsletter_subscriptions) do
      add :email, :string, null: false
      add :source, :string, null: false, default: "footer"
      add :subscribed_at, :utc_datetime, null: false
      add :unsubscribed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:newsletter_subscriptions, [:email])
  end
end
