defmodule BlocksterV2.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :wallet_address, :string
    field :username, :string
    field :auth_method, :string, default: "wallet"
    field :is_verified, :boolean, default: false
    field :is_admin, :boolean, default: false
    field :is_author, :boolean, default: false
    field :bux_balance, :integer, default: 0
    field :level, :integer, default: 1
    field :experience_points, :integer, default: 0
    field :avatar_url, :string
    field :chain_id, :integer, default: 560013
    field :slug, :string
    field :smart_wallet_address, :string
    field :locked_x_user_id, :string

    # Fingerprint flags
    field :is_flagged_multi_account_attempt, :boolean, default: false
    field :last_suspicious_activity_at, :utc_datetime
    field :registered_devices_count, :integer, default: 0

    has_many :sessions, BlocksterV2.Accounts.UserSession
    has_many :posts, BlocksterV2.Blog.Post, foreign_key: :author_id
    has_many :organized_events, BlocksterV2.Events.Event, foreign_key: :organizer_id
    has_many :fingerprints, BlocksterV2.Accounts.UserFingerprint
    many_to_many :followed_hubs, BlocksterV2.Blog.Hub,
      join_through: "hub_followers",
      on_replace: :delete
    many_to_many :attending_events, BlocksterV2.Events.Event,
      join_through: "event_attendees",
      on_replace: :delete

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :wallet_address, :smart_wallet_address, :username, :auth_method, :is_verified,
                    :is_admin, :is_author, :bux_balance, :level, :experience_points,
                    :avatar_url, :chain_id, :is_flagged_multi_account_attempt,
                    :last_suspicious_activity_at, :registered_devices_count])
    |> validate_required([:wallet_address, :auth_method])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_length(:username, min: 3, max: 20)
    |> validate_inclusion(:auth_method, ["wallet", "email"])
    |> validate_number(:bux_balance, greater_than_or_equal_to: 0)
    |> validate_number(:level, greater_than_or_equal_to: 1)
    |> validate_number(:experience_points, greater_than_or_equal_to: 0)
    |> downcase_email()
    |> downcase_wallet_address()
    |> generate_slug()
    |> unique_constraint(:wallet_address)
    |> unique_constraint(:email)
    |> unique_constraint(:username)
    |> unique_constraint(:slug)
  end

  @doc """
  Changeset for creating a new user from wallet connection
  """
  def wallet_registration_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:wallet_address, :chain_id, :username, :avatar_url])
    |> put_change(:auth_method, "wallet")
    |> put_change(:is_verified, true)  # Wallet signature verifies ownership
    |> validate_required([:wallet_address])
    |> unique_constraint(:wallet_address)
    |> downcase_wallet_address()
  end

  @doc """
  Changeset for creating a new user from email signup (Thirdweb embedded wallet)
  """
  def email_registration_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, [:email, :wallet_address, :smart_wallet_address, :username, :avatar_url, :registered_devices_count])
    |> put_change(:auth_method, "email")
    |> put_change(:is_verified, false)  # Email needs verification
    |> validate_required([:email, :wallet_address, :smart_wallet_address])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> unique_constraint(:email)
    |> unique_constraint(:wallet_address)
    |> unique_constraint(:smart_wallet_address)
    |> downcase_email()
    |> downcase_wallet_address()
    |> downcase_smart_wallet_address()
    |> set_admin_if_authorized()
  end

  defp downcase_email(changeset) do
    case get_change(changeset, :email) do
      nil -> changeset
      email -> put_change(changeset, :email, String.downcase(email))
    end
  end

  defp downcase_wallet_address(changeset) do
    case get_change(changeset, :wallet_address) do
      nil -> changeset
      address -> put_change(changeset, :wallet_address, String.downcase(address))
    end
  end

  defp downcase_smart_wallet_address(changeset) do
    case get_change(changeset, :smart_wallet_address) do
      nil -> changeset
      address -> put_change(changeset, :smart_wallet_address, String.downcase(address))
    end
  end

  defp set_admin_if_authorized(changeset) do
    case get_change(changeset, :email) do
      nil -> changeset
      email ->
        # Check if the email matches authorized admin patterns
        # This handles adam@blockster.com, adam+anything@blockster.com, etc.
        if String.match?(email, ~r/^adam(\+[^@]+)?@blockster\.com$/i) do
          changeset
          |> put_change(:is_admin, true)
          |> put_change(:is_author, true)
        else
          changeset
        end
    end
  end

  defp generate_slug(changeset) do
    case get_change(changeset, :username) do
      nil -> changeset
      username ->
        slug =
          username
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9\s-]/, "")
          |> String.replace(~r/\s+/, "-")
          |> String.replace(~r/-+/, "-")
          |> String.trim("-")

        put_change(changeset, :slug, slug)
    end
  end
end
