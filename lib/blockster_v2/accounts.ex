defmodule BlocksterV2.Accounts do
  @moduledoc """
  The Accounts context for user authentication and management.
  Supports both wallet-based and email-based authentication via Thirdweb.
  """

  import Ecto.Query, warn: false
  alias BlocksterV2.Repo
  alias BlocksterV2.Accounts.{User, UserSession}

  ## User functions

  @doc """
  Gets a user by wallet address.
  """
  def get_user_by_wallet(wallet_address) when is_binary(wallet_address) do
    Repo.get_by(User, wallet_address: String.downcase(wallet_address))
  end

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: String.downcase(email))
  end

  @doc """
  Gets a user by ID.
  """
  def get_user(id), do: Repo.get(User, id)

  @doc """
  Gets a user by slug.
  """
  def get_user_by_slug(slug) when is_binary(slug) do
    Repo.get_by(User, slug: slug)
  end

  @doc """
  Lists all users ordered by most recent first.
  """
  def list_users do
    from(u in User, order_by: [desc: u.inserted_at])
    |> Repo.all()
  end

  @doc """
  Gets a user by ID with followed hubs preloaded.
  """
  def get_user_with_followed_hubs(id) do
    User
    |> where([u], u.id == ^id)
    |> preload(:followed_hubs)
    |> Repo.one()
  end

  @doc """
  Lists all users with followed hubs preloaded.
  """
  def list_users_with_followed_hubs do
    from(u in User, order_by: [desc: u.inserted_at])
    |> preload(:followed_hubs)
    |> Repo.all()
  end

  @doc """
  Lists all authors (users with is_author = true) with their usernames.
  """
  def list_authors do
    from(u in User,
      where: u.is_author == true and not is_nil(u.username),
      select: %{id: u.id, username: u.username},
      order_by: u.username
    )
    |> Repo.all()
  end

  @doc """
  Creates a user from wallet connection.
  Expects attrs to contain at minimum: %{wallet_address: "0x...", chain_id: 560013}
  """
  def create_user_from_wallet(attrs) do
    attrs
    |> User.wallet_registration_changeset()
    |> Repo.insert()
  end

  @doc """
  Creates a user from email signup (Thirdweb embedded wallet).
  Expects attrs to contain: %{email: "...", wallet_address: "0x..."}
  """
  def create_user_from_email(attrs) do
    attrs
    |> User.email_registration_changeset()
    |> Repo.insert()
  end

  @doc """
  Updates a user.
  """
  def update_user(%User{} = user, attrs) do
    user
    |> User.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Verifies an email user (after email confirmation).
  """
  def verify_user(%User{} = user) do
    user
    |> User.changeset(%{is_verified: true})
    |> Repo.update()
  end

  ## Session functions

  @doc """
  Creates a new session for a user.
  Returns {:ok, session} with the generated token.
  """
  def create_session(user_id) do
    user_id
    |> UserSession.create_changeset()
    |> Repo.insert()
  end

  @doc """
  Gets a session by token and checks if it's valid (not expired).
  Returns the session with preloaded user if valid, nil otherwise.
  """
  def get_valid_session(token) when is_binary(token) do
    case Repo.get_by(UserSession, token: token) |> Repo.preload(:user) do
      nil -> nil
      session ->
        if UserSession.expired?(session) do
          delete_session(session)
          nil
        else
          touch_session(session)
          session
        end
    end
  end

  @doc """
  Gets a user by session token.
  Returns nil if session is invalid or expired.
  """
  def get_user_by_session_token(token) do
    case get_valid_session(token) do
      nil -> nil
      session -> session.user
    end
  end

  @doc """
  Updates the last_active_at timestamp for a session.
  """
  def touch_session(%UserSession{} = session) do
    session
    |> UserSession.touch_changeset()
    |> Repo.update()
  end

  @doc """
  Deletes a session.
  """
  def delete_session(%UserSession{} = session) do
    Repo.delete(session)
  end

  @doc """
  Deletes all sessions for a user (logout from all devices).
  """
  def delete_user_sessions(user_id) do
    from(s in UserSession, where: s.user_id == ^user_id)
    |> Repo.delete_all()
  end

  @doc """
  Deletes expired sessions (cleanup task).
  """
  def delete_expired_sessions do
    now = DateTime.utc_now()
    from(s in UserSession, where: s.expires_at < ^now)
    |> Repo.delete_all()
  end

  ## Auth helpers

  @doc """
  Authenticates a user by wallet address and creates a session.
  If user doesn't exist, creates a new user.
  Returns {:ok, user, session} or {:error, reason}
  """
  def authenticate_wallet(wallet_address, chain_id \\ 560013) do
    wallet_address = String.downcase(wallet_address)

    case get_user_by_wallet(wallet_address) do
      nil ->
        # Create new user
        case create_user_from_wallet(%{wallet_address: wallet_address, chain_id: chain_id}) do
          {:ok, user} ->
            case create_session(user.id) do
              {:ok, session} -> {:ok, user, session}
              error -> error
            end
          error -> error
        end

      user ->
        # Existing user, create session
        case create_session(user.id) do
          {:ok, session} -> {:ok, user, session}
          error -> error
        end
    end
  end

  @doc """
  Authenticates a user by email (Thirdweb embedded wallet) and creates a session.
  If user doesn't exist, creates a new user.
  wallet_address = personal wallet (EOA) from Thirdweb in-app wallet
  smart_wallet_address = ERC-4337 smart wallet address (displayed to user)
  Returns {:ok, user, session} or {:error, reason}
  """
  def authenticate_email(email, wallet_address, smart_wallet_address) do
    email = String.downcase(email)
    wallet_address = String.downcase(wallet_address)
    smart_wallet_address = String.downcase(smart_wallet_address)

    case get_user_by_email(email) do
      nil ->
        # Create new user
        case create_user_from_email(%{
          email: email,
          wallet_address: wallet_address,
          smart_wallet_address: smart_wallet_address
        }) do
          {:ok, user} ->
            case create_session(user.id) do
              {:ok, session} -> {:ok, user, session}
              error -> error
            end
          error -> error
        end

      user ->
        # Existing user - update smart_wallet_address if changed, create session
        user =
          if user.smart_wallet_address != smart_wallet_address do
            {:ok, updated_user} = update_user(user, %{smart_wallet_address: smart_wallet_address})
            updated_user
          else
            user
          end

        case create_session(user.id) do
          {:ok, session} -> {:ok, user, session}
          error -> error
        end
    end
  end

  ## BUX token management

  @doc """
  Adds BUX tokens to a user's balance.
  """
  def add_bux(%User{} = user, amount) when is_integer(amount) and amount > 0 do
    new_balance = user.bux_balance + amount
    update_user(user, %{bux_balance: new_balance})
  end

  @doc """
  Deducts BUX tokens from a user's balance.
  Returns {:error, :insufficient_balance} if user doesn't have enough BUX.
  """
  def deduct_bux(%User{} = user, amount) when is_integer(amount) and amount > 0 do
    if user.bux_balance >= amount do
      new_balance = user.bux_balance - amount
      update_user(user, %{bux_balance: new_balance})
    else
      {:error, :insufficient_balance}
    end
  end

  @doc """
  Adds experience points to a user and handles level ups.
  Every 1000 XP = 1 level.
  """
  def add_experience(%User{} = user, points) when is_integer(points) and points > 0 do
    new_xp = user.experience_points + points
    new_level = div(new_xp, 1000) + 1

    update_user(user, %{
      experience_points: new_xp,
      level: max(new_level, user.level)
    })
  end

  ## Hub following functions

  @doc """
  Gets the count of hubs a user follows.
  """
  def get_user_followed_hubs_count(user_id) do
    from(hf in "hub_followers",
      where: hf.user_id == ^user_id,
      select: count(hf.hub_id)
    )
    |> Repo.one()
  end

  @doc """
  Gets followed hub counts for multiple users.
  Returns a map of user_id => followed_hubs_count.
  """
  def get_user_followed_hubs_counts(user_ids) when is_list(user_ids) do
    from(hf in "hub_followers",
      where: hf.user_id in ^user_ids,
      group_by: hf.user_id,
      select: {hf.user_id, count(hf.hub_id)}
    )
    |> Repo.all()
    |> Map.new()
  end
end
