defmodule BlocksterV2.Repo.Migrations.AddWeb3authFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # X (Twitter) subject id from Web3Auth — distinct from the existing
      # `x_handle` (which is the display handle, mutable) and
      # `locked_x_user_id` (legacy lookup field). This is the stable numeric
      # id we use to dedupe X logins across handle changes.
      add :x_user_id, :string

      # Avatar URL provided by the social provider (Google profileImage,
      # X avatar, etc). Distinct from `avatar_url` which the user can set
      # themselves in profile settings.
      add :social_avatar_url, :string

      # Web3Auth verifier id (e.g. "web3auth" for default email passwordless,
      # aggregate verifier id for Google/X, or our custom "blockster-telegram"
      # for Telegram JWT). Useful for debugging + analytics.
      add :web3auth_verifier, :string
    end

    create unique_index(:users, [:x_user_id],
             where: "x_user_id IS NOT NULL",
             name: :users_x_user_id_index
           )
  end
end
