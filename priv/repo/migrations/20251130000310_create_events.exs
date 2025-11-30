defmodule BlocksterV2.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :title, :string, null: false
      add :slug, :string, null: false
      add :address, :string
      add :city, :string
      add :country, :string
      add :date, :date
      add :time, :time
      add :unix_time, :bigint
      add :price, :decimal, precision: 10, scale: 2, default: 0.0
      add :ticket_supply, :integer
      add :status, :string, default: "draft"
      add :description, :text

      # Foreign keys
      add :organizer_id, references(:users, on_delete: :delete_all), null: false
      add :hub_id, references(:hubs, on_delete: :nilify_all)

      timestamps()
    end

    # Join table for event attendees (many-to-many relationship)
    create table(:event_attendees) do
      add :event_id, references(:events, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false

      timestamps()
    end

    # Indexes
    create unique_index(:events, [:slug])
    create index(:events, [:organizer_id])
    create index(:events, [:hub_id])
    create index(:events, [:status])
    create index(:events, [:date])
    create index(:events, [:unix_time])

    # Indexes for join table
    create unique_index(:event_attendees, [:event_id, :user_id])
    create index(:event_attendees, [:event_id])
    create index(:event_attendees, [:user_id])
  end
end
