defmodule BlocksterV2.Repo.Migrations.AddPhoneVerificationSystem do
  use Ecto.Migration

  def change do
    # Create phone_verifications table
    create table(:phone_verifications) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :phone_number, :string, null: false
      add :country_code, :string, null: false, size: 2        # ISO 3166-1 alpha-2 (e.g., "US", "NG", "IN")
      add :carrier_name, :string
      add :line_type, :string                                  # "mobile", "landline", "voip"
      add :geo_tier, :string, null: false                      # "premium", "standard", "basic"
      add :geo_multiplier, :decimal, precision: 3, scale: 2, null: false  # 0.5, 1.0, 1.5, 2.0
      add :verification_sid, :string                           # Twilio verification SID
      add :verified, :boolean, default: false, null: false
      add :verified_at, :utc_datetime
      add :attempts, :integer, default: 0, null: false         # Rate limiting
      add :last_attempt_at, :utc_datetime
      add :fraud_flags, :map                                   # Store any fraud signals from Twilio
      add :sms_opt_in, :boolean, default: true, null: false   # Opt-in for special offers and promos

      timestamps(type: :utc_datetime)
    end

    # Indexes and constraints for phone_verifications
    create unique_index(:phone_verifications, [:phone_number],
      name: :phone_verifications_phone_number_unique,
      comment: "One phone per account (anti-Sybil)")

    create index(:phone_verifications, [:user_id])
    create index(:phone_verifications, [:verified])
    create index(:phone_verifications, [:country_code])

    # Check constraints
    create constraint(:phone_verifications, :geo_multiplier_range,
      check: "geo_multiplier >= 0.5 AND geo_multiplier <= 5.0")

    create constraint(:phone_verifications, :valid_geo_tier,
      check: "geo_tier IN ('premium', 'standard', 'basic')")

    create constraint(:phone_verifications, :valid_line_type,
      check: "line_type IS NULL OR line_type IN ('mobile', 'landline', 'voip')")

    # Add fields to users table
    alter table(:users) do
      add :phone_verified, :boolean, default: false, null: false
      add :geo_multiplier, :decimal, precision: 3, scale: 2, default: 0.5, null: false
      add :geo_tier, :string, default: "unverified", null: false
      add :sms_opt_in, :boolean, default: true, null: false   # Opt-in for special offers and promos via SMS
    end

    create index(:users, [:phone_verified])

    # Add check constraint to users table
    create constraint(:users, :users_geo_multiplier_range,
      check: "geo_multiplier >= 0.5 AND geo_multiplier <= 5.0")
  end

  def down do
    drop constraint(:users, :users_geo_multiplier_range)
    drop index(:users, [:phone_verified])

    alter table(:users) do
      remove :sms_opt_in
      remove :phone_verified
      remove :geo_multiplier
      remove :geo_tier
    end

    drop constraint(:phone_verifications, :valid_line_type)
    drop constraint(:phone_verifications, :valid_geo_tier)
    drop constraint(:phone_verifications, :geo_multiplier_range)
    drop index(:phone_verifications, [:country_code])
    drop index(:phone_verifications, [:verified])
    drop index(:phone_verifications, [:user_id])
    drop unique_index(:phone_verifications, [:phone_number], name: :phone_verifications_phone_number_unique)
    drop table(:phone_verifications)
  end
end
