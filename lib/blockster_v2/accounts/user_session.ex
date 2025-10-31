defmodule BlocksterV2.Accounts.UserSession do
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_sessions" do
    belongs_to :user, BlocksterV2.Accounts.User
    field :token, :string
    field :expires_at, :utc_datetime
    field :last_active_at, :utc_datetime

    timestamps()
  end

  @doc false
  def changeset(user_session, attrs) do
    user_session
    |> cast(attrs, [:user_id, :token, :expires_at, :last_active_at])
    |> validate_required([:user_id, :token, :expires_at])
    |> unique_constraint(:token)
    |> foreign_key_constraint(:user_id)
  end

  @doc """
  Creates a new session changeset with generated token.
  Default expiration is 30 days from now.
  """
  def create_changeset(user_id, attrs \\ %{}) do
    token = generate_token()
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    expires_at = DateTime.add(now, 30 * 24 * 60 * 60, :second)

    %__MODULE__{}
    |> cast(attrs, [:last_active_at])
    |> put_change(:user_id, user_id)
    |> put_change(:token, token)
    |> put_change(:expires_at, expires_at)
    |> put_change(:last_active_at, now)
    |> validate_required([:user_id, :token, :expires_at])
  end

  @doc """
  Checks if a session is expired.
  """
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Updates the last_active_at timestamp to current time.
  """
  def touch_changeset(user_session) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    user_session
    |> change()
    |> put_change(:last_active_at, now)
  end

  # Generates a secure random token
  defp generate_token do
    :crypto.strong_rand_bytes(32)
    |> Base.url_encode64(padding: false)
  end
end
