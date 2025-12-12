defmodule BlocksterV2.Repo.Migrations.AddXOauthAndShareTracking do
  use Ecto.Migration

  def change do
    # X (Twitter) OAuth connections for users
    create table(:x_connections) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :x_user_id, :string, null: false
      add :x_username, :string
      add :x_name, :string
      add :x_profile_image_url, :string
      add :access_token_encrypted, :binary, null: false
      add :refresh_token_encrypted, :binary
      add :token_expires_at, :utc_datetime
      add :scopes, {:array, :string}, default: []
      add :connected_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:x_connections, [:user_id])
    create unique_index(:x_connections, [:x_user_id])

    # Share campaigns - tweets that users can retweet for rewards
    create table(:share_campaigns) do
      add :post_id, references(:posts, on_delete: :delete_all), null: false
      add :tweet_id, :string, null: false
      add :tweet_url, :string, null: false
      add :tweet_text, :text
      add :bux_reward, :integer, default: 50
      add :is_active, :boolean, default: true
      add :starts_at, :utc_datetime
      add :ends_at, :utc_datetime
      add :max_participants, :integer
      add :total_shares, :integer, default: 0

      timestamps()
    end

    create unique_index(:share_campaigns, [:post_id])
    create index(:share_campaigns, [:tweet_id])
    create index(:share_campaigns, [:is_active])

    # Track user shares (retweets) for reward distribution
    create table(:share_rewards) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :campaign_id, references(:share_campaigns, on_delete: :delete_all), null: false
      add :x_connection_id, references(:x_connections, on_delete: :nilify_all)
      add :retweet_id, :string
      add :status, :string, default: "pending"  # pending, verified, rewarded, failed
      add :bux_rewarded, :decimal
      add :verified_at, :utc_datetime
      add :rewarded_at, :utc_datetime
      add :failure_reason, :string

      timestamps()
    end

    create unique_index(:share_rewards, [:user_id, :campaign_id])
    create index(:share_rewards, [:campaign_id])
    create index(:share_rewards, [:status])

    # Store PKCE code verifiers temporarily during OAuth flow
    create table(:x_oauth_states) do
      add :state, :string, null: false
      add :code_verifier, :string, null: false
      add :user_id, references(:users, on_delete: :delete_all)
      add :redirect_path, :string
      add :expires_at, :utc_datetime, null: false

      timestamps()
    end

    create unique_index(:x_oauth_states, [:state])
    create index(:x_oauth_states, [:expires_at])
  end
end
