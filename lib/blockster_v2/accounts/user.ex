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

    # Phone verification fields
    field :phone_verified, :boolean, default: false
    field :geo_multiplier, :decimal, default: Decimal.new("0.5")
    field :geo_tier, :string, default: "unverified"
    field :sms_opt_in, :boolean, default: true

    # Fingerprint flags
    field :is_flagged_multi_account_attempt, :boolean, default: false
    field :last_suspicious_activity_at, :utc_datetime
    field :registered_devices_count, :integer, default: 0

    # Bot system
    field :is_bot, :boolean, default: false
    field :bot_private_key, :string

    # Telegram fields
    field :telegram_user_id, :string
    field :telegram_username, :string
    field :telegram_connect_token, :string
    field :telegram_connected_at, :utc_datetime
    field :telegram_group_joined_at, :utc_datetime

    # Solana migration fields
    field :email_verified, :boolean, default: false
    field :email_verification_code, :string
    field :email_verification_sent_at, :utc_datetime
    field :legacy_email, :string
    field :pending_email, :string

    # Profile fields
    field :bio, :string
    field :x_handle, :string

    # Web3Auth / social login fields
    field :x_user_id, :string
    field :social_avatar_url, :string
    field :web3auth_verifier, :string

    # Legacy account deactivation fields (set when this user is merged into another)
    field :is_active, :boolean, default: true
    field :deactivated_at, :utc_datetime
    belongs_to :merged_into_user, __MODULE__, foreign_key: :merged_into_user_id

    # Referral fields
    field :referred_at, :utc_datetime
    belongs_to :referrer, __MODULE__
    has_many :referees, __MODULE__, foreign_key: :referrer_id

    has_many :sessions, BlocksterV2.Accounts.UserSession
    has_many :posts, BlocksterV2.Blog.Post, foreign_key: :author_id
    has_many :organized_events, BlocksterV2.Events.Event, foreign_key: :organizer_id
    has_many :fingerprints, BlocksterV2.Accounts.UserFingerprint
    has_one :phone_verification, BlocksterV2.Accounts.PhoneVerification
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
                    :last_suspicious_activity_at, :registered_devices_count,
                    :phone_verified, :geo_multiplier, :geo_tier, :sms_opt_in,
                    :referrer_id, :referred_at,
                    :telegram_user_id, :telegram_username, :telegram_connect_token, :telegram_connected_at,
                    :telegram_group_joined_at, :is_bot,
                    :email_verified, :email_verification_code, :email_verification_sent_at, :legacy_email,
                    :pending_email, :is_active, :deactivated_at, :merged_into_user_id,
                    :bio, :x_handle,
                    :x_user_id, :social_avatar_url, :web3auth_verifier])
    |> validate_required([:wallet_address, :auth_method])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_length(:username, min: 3, max: 20)
    |> validate_inclusion(:auth_method, [
         "wallet",
         "email",
         "web3auth_email",
         "web3auth_google",
         "web3auth_apple",
         "web3auth_x",
         "web3auth_telegram"
       ])
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
    |> unique_constraint(:telegram_user_id, message: "this Telegram account is already connected to another user")
    |> unique_constraint(:x_user_id, message: "this X account is already connected to another user")
  end

  @doc """
  Changeset for creating a new user via Web3Auth social login. Wraps the
  common fields + sets auth_method + marks `is_verified = true` (the social
  provider's OAuth / OTP step is the verification step). Email flagged as
  verified when the verifier is an OTP path.
  """
  def web3auth_registration_changeset(attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    auth_method = Map.get(attrs, "auth_method")

    %__MODULE__{}
    |> cast(attrs, [
      :wallet_address,
      :email,
      :pending_email,
      :username,
      :avatar_url,
      :social_avatar_url,
      :auth_method,
      :web3auth_verifier,
      :x_user_id,
      :x_handle,
      :telegram_user_id,
      :telegram_username,
      :email_verified
    ])
    |> put_change(:is_verified, true)
    # email_verified is ONLY true when we actually have an email on file —
    # otherwise the Settings page shows a green "Verified" badge for an
    # email field that reads "No email set", and the multiplier system
    # credits a verified email the user never supplied.
    |> put_email_verified(auth_method, Map.get(attrs, "email"))
    |> put_telegram_connected_at(auth_method)
    |> validate_required([:wallet_address, :auth_method])
    |> validate_inclusion(:auth_method, [
         "web3auth_email",
         "web3auth_google",
         "web3auth_apple",
         "web3auth_x",
         "web3auth_telegram"
       ])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> set_admin_if_authorized()
    |> generate_slug()
    |> unique_constraint(:wallet_address)
    |> unique_constraint(:email)
    |> unique_constraint(:slug)
    |> unique_constraint(:telegram_user_id,
         message: "this Telegram account is already connected to another user"
       )
    |> unique_constraint(:x_user_id,
         message: "this X account is already connected to another user"
       )
  end

  # OTP-owned email (web3auth_email) + OAuth-verified emails (Google / Apple)
  # count as verified once we actually have an address on file. Keep in sync
  # with Accounts.verified_email_auth_method?/1.
  defp put_email_verified(changeset, auth_method, email)
       when auth_method in ["web3auth_email", "web3auth_google", "web3auth_apple"] and
              is_binary(email) and email != "" do
    put_change(changeset, :email_verified, true)
  end

  defp put_email_verified(changeset, _auth_method, _email) do
    put_change(changeset, :email_verified, false)
  end

  defp put_telegram_connected_at(changeset, "web3auth_telegram") do
    case get_change(changeset, :telegram_connected_at) do
      nil -> put_change(changeset, :telegram_connected_at, DateTime.utc_now() |> DateTime.truncate(:second))
      _ -> changeset
    end
  end

  defp put_telegram_connected_at(changeset, _), do: changeset

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
      # Only downcase EVM addresses (0x prefix) — Solana base58 is case-sensitive
      "0x" <> _ = address -> put_change(changeset, :wallet_address, String.downcase(address))
      _solana_address -> changeset
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

  @doc """
  Returns true when this user is a "legacy" holder of an identifier (email,
  phone, X, Telegram) and a new Solana wallet user is allowed to reclaim that
  identifier from them.

  Two cases:
    * `is_active = false` — the user has already been merged/deactivated.
    * `auth_method = "email"` — pre-Solana EVM/Thirdweb signup that hasn't
      gone through the merge yet. Every legacy Blockster account is in this
      state until its email is verified through the new flow.

  Bots and new Solana users (`auth_method = "wallet"`) are NOT reclaimable.
  """
  def reclaimable_holder?(%__MODULE__{is_bot: true}), do: false
  def reclaimable_holder?(%__MODULE__{is_active: false}), do: true
  def reclaimable_holder?(%__MODULE__{auth_method: "email"}), do: true
  def reclaimable_holder?(_), do: false
end
