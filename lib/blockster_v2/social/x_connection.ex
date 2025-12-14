defmodule BlocksterV2.Social.XConnection do
  use Ecto.Schema
  import Ecto.Changeset

  alias BlocksterV2.Accounts.User

  schema "x_connections" do
    belongs_to :user, User

    field :x_user_id, :string
    field :x_username, :string
    field :x_name, :string
    field :x_profile_image_url, :string
    field :access_token_encrypted, :binary
    field :refresh_token_encrypted, :binary
    field :token_expires_at, :utc_datetime
    field :scopes, {:array, :string}, default: []
    field :connected_at, :utc_datetime

    # X account quality score fields
    field :x_score, :integer
    field :followers_count, :integer
    field :following_count, :integer
    field :tweet_count, :integer
    field :listed_count, :integer
    field :avg_engagement_rate, :float
    field :original_tweets_analyzed, :integer
    field :account_created_at, :utc_datetime
    field :score_calculated_at, :utc_datetime

    # Virtual fields for unencrypted tokens
    field :access_token, :string, virtual: true
    field :refresh_token, :string, virtual: true

    timestamps()
  end

  @required_fields [:user_id, :x_user_id, :access_token, :connected_at]
  @optional_fields [
    :x_username, :x_name, :x_profile_image_url, :refresh_token, :token_expires_at, :scopes,
    :x_score, :followers_count, :following_count, :tweet_count, :listed_count,
    :avg_engagement_rate, :original_tweets_analyzed, :account_created_at, :score_calculated_at
  ]

  def changeset(x_connection, attrs) do
    x_connection
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:user_id)
    |> unique_constraint(:x_user_id)
    |> encrypt_tokens()
  end

  defp encrypt_tokens(changeset) do
    changeset
    |> encrypt_field(:access_token, :access_token_encrypted)
    |> encrypt_field(:refresh_token, :refresh_token_encrypted)
  end

  defp encrypt_field(changeset, source_field, dest_field) do
    case get_change(changeset, source_field) do
      nil -> changeset
      value when is_binary(value) ->
        encrypted = BlocksterV2.Encryption.encrypt(value)
        put_change(changeset, dest_field, encrypted)
      _ -> changeset
    end
  end

  def decrypt_access_token(%__MODULE__{access_token_encrypted: encrypted}) when is_binary(encrypted) do
    BlocksterV2.Encryption.decrypt(encrypted)
  end
  def decrypt_access_token(_), do: nil

  def decrypt_refresh_token(%__MODULE__{refresh_token_encrypted: encrypted}) when is_binary(encrypted) do
    BlocksterV2.Encryption.decrypt(encrypted)
  end
  def decrypt_refresh_token(_), do: nil

  def token_expired?(%__MODULE__{token_expires_at: nil}), do: false
  def token_expired?(%__MODULE__{token_expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  Checks if the token needs to be refreshed (expires within 5 minutes or already expired).
  """
  def token_needs_refresh?(%__MODULE__{token_expires_at: nil}), do: false
  def token_needs_refresh?(%__MODULE__{token_expires_at: expires_at}) do
    five_minutes_from_now = DateTime.utc_now() |> DateTime.add(5, :minute)
    DateTime.compare(expires_at, five_minutes_from_now) == :lt
  end

  @doc """
  Changeset for updating an existing connection.
  """
  def update_changeset(x_connection, attrs) do
    x_connection
    |> cast(attrs, @optional_fields ++ [:access_token, :connected_at])
    |> encrypt_tokens()
  end

  @doc """
  Gets the decrypted access token. Alias for decrypt_access_token.
  """
  def get_decrypted_access_token(connection), do: decrypt_access_token(connection)

  @doc """
  Gets the decrypted refresh token. Alias for decrypt_refresh_token.
  """
  def get_decrypted_refresh_token(connection), do: decrypt_refresh_token(connection)
end
