defmodule BlocksterV2.Social.XOauthState do
  @moduledoc """
  Stores PKCE code verifiers temporarily during X OAuth 2.0 flow.
  These records should be cleaned up after use or expiration.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias BlocksterV2.Accounts.User

  schema "x_oauth_states" do
    belongs_to :user, User

    field :state, :string
    field :code_verifier, :string
    field :redirect_path, :string
    field :expires_at, :utc_datetime

    timestamps()
  end

  @required_fields [:state, :code_verifier, :expires_at]
  @optional_fields [:user_id, :redirect_path]

  def changeset(oauth_state, attrs) do
    oauth_state
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:state)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Creates a new OAuth state with auto-generated PKCE values and 10 minute expiry.
  """
  def new(attrs \\ %{}) do
    state = generate_state()
    code_verifier = generate_code_verifier()
    expires_at = DateTime.utc_now() |> DateTime.add(10, :minute) |> DateTime.truncate(:second)

    %__MODULE__{}
    |> changeset(Map.merge(attrs, %{
      state: state,
      code_verifier: code_verifier,
      expires_at: expires_at
    }))
  end

  @doc """
  Generates a cryptographically secure random state string.
  """
  def generate_state do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  @doc """
  Generates a PKCE code verifier (43-128 characters).
  """
  def generate_code_verifier do
    :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  end

  @doc """
  Generates a PKCE code challenge from the verifier using S256 method.
  """
  def generate_code_challenge(code_verifier) do
    :crypto.hash(:sha256, code_verifier)
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Checks if the OAuth state has expired.
  """
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end
end
