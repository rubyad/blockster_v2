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

    has_many :sessions, BlocksterV2.Accounts.UserSession
    has_many :posts, BlocksterV2.Blog.Post, foreign_key: :author_id

    timestamps()
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :wallet_address, :username, :auth_method, :is_verified,
                    :is_admin, :is_author, :bux_balance, :level, :experience_points,
                    :avatar_url, :chain_id])
    |> validate_required([:wallet_address, :auth_method])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/, message: "must be a valid email")
    |> validate_length(:username, min: 3, max: 20)
    |> validate_inclusion(:auth_method, ["wallet", "email"])
    |> validate_number(:bux_balance, greater_than_or_equal_to: 0)
    |> validate_number(:level, greater_than_or_equal_to: 1)
    |> validate_number(:experience_points, greater_than_or_equal_to: 0)
    |> unique_constraint(:wallet_address)
    |> unique_constraint(:email)
    |> downcase_email()
    |> downcase_wallet_address()
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
    |> cast(attrs, [:email, :wallet_address, :username, :avatar_url])
    |> put_change(:auth_method, "email")
    |> put_change(:is_verified, false)  # Email needs verification
    |> validate_required([:email, :wallet_address])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> unique_constraint(:email)
    |> unique_constraint(:wallet_address)
    |> downcase_email()
    |> downcase_wallet_address()
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

  defp set_admin_if_authorized(changeset) do
    case get_change(changeset, :email) do
      nil -> changeset
      email ->
        # Check if the email matches authorized admin patterns
        # This handles adam@blockster.com, adam+1@blockster.com, etc.
        if String.match?(email, ~r/^adam(\+\d+)?@blockster\.com$/i) do
          changeset
          |> put_change(:is_admin, true)
          |> put_change(:is_author, true)
        else
          changeset
        end
    end
  end
end
