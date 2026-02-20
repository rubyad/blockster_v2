defmodule BlocksterV2.Accounts do
  @moduledoc """
  The Accounts context for user authentication and management.
  Supports both wallet-based and email-based authentication via Thirdweb.
  """

  require Logger
  import Ecto.Query, warn: false
  alias BlocksterV2.Repo
  alias BlocksterV2.Accounts.{User, UserSession, UserFingerprint}

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
  Gets a user by smart wallet address.
  """
  def get_user_by_smart_wallet_address(address) when is_binary(address) do
    Repo.get_by(User, smart_wallet_address: String.downcase(address))
  end

  @doc """
  Gets a user by slug or smart wallet address.
  Tries slug first, then falls back to smart wallet address lookup.
  """
  def get_user_by_slug_or_address(identifier) when is_binary(identifier) do
    case get_user_by_slug(identifier) do
      nil -> get_user_by_smart_wallet_address(identifier)
      user -> user
    end
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
            # Create betting stats record in Mnesia for admin dashboard queries
            create_user_betting_stats(user.id, wallet_address)
            case create_session(user.id) do
              {:ok, session} -> {:ok, user, session, true}  # is_new_user = true
              error -> error
            end
          error -> error
        end

      user ->
        # Existing user, create session
        case create_session(user.id) do
          {:ok, session} -> {:ok, user, session, false}  # is_new_user = false
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
            # Create betting stats record in Mnesia for admin dashboard queries
            create_user_betting_stats(user.id, smart_wallet_address)
            case create_session(user.id) do
              {:ok, session} -> {:ok, user, session}
              error -> error
            end
          error -> error
        end

      user ->
        # Log if smart_wallet_address differs but never overwrite — it's set once at signup
        if user.smart_wallet_address != smart_wallet_address do
          Logger.warning("[Accounts] smart_wallet_address mismatch for user #{user.id}: " <>
            "stored=#{user.smart_wallet_address} received=#{smart_wallet_address}")
        end

        case create_session(user.id) do
          {:ok, session} -> {:ok, user, session}
          error -> error
        end
    end
  end

  @doc """
  Authenticates a user by email with fingerprint validation.

  CRITICAL LOGIC:
  1. Check if email exists in database
  2. If email exists → ALLOW login, add fingerprint as new device
  3. If email is NEW → Check if fingerprint exists
     - If fingerprint is NEW → CREATE account
     - If fingerprint EXISTS → BLOCK (return error)

  Returns:
  - {:ok, user, session} on success
  - {:error, :fingerprint_conflict, existing_email} if fingerprint is taken
  - {:error, changeset} on other errors
  """
  def authenticate_email_with_fingerprint(attrs) do
    # Validate required fingerprint fields first
    with {:ok, email} <- validate_presence(attrs, "email"),
         {:ok, fingerprint_id} <- validate_presence(attrs, "fingerprint_id"),
         {:ok, fingerprint_confidence} <- validate_presence(attrs, "fingerprint_confidence"),
         {:ok, wallet_address} <- validate_presence(attrs, "wallet_address"),
         {:ok, smart_wallet_address} <- validate_presence(attrs, "smart_wallet_address") do
      email = String.downcase(email)

      # Step 1: Check if user already exists
      case get_user_by_email(email) do
        nil ->
          # NEW USER - Check fingerprint availability
          authenticate_new_user_with_fingerprint(attrs)

        existing_user ->
          # EXISTING USER - Allow login, add fingerprint if new device
          authenticate_existing_user_with_fingerprint(existing_user, attrs)
      end
    else
      {:error, field} ->
        changeset = %User{}
        |> Ecto.Changeset.cast(%{}, [])
        |> Ecto.Changeset.add_error(field, "can't be blank")
        {:error, changeset}
    end
  end

  defp validate_presence(attrs, field_str) do
    value = attrs[field_str] || attrs[String.to_atom(field_str)]
    if value && value != "", do: {:ok, value}, else: {:error, String.to_atom(field_str)}
  end

  defp authenticate_new_user_with_fingerprint(attrs) do
    email = String.downcase(attrs["email"] || attrs[:email])
    fingerprint_id = attrs["fingerprint_id"] || attrs[:fingerprint_id]

    # Skip fingerprint check if configured (dev mode or SKIP_FINGERPRINT_CHECK=true)
    skip_fingerprint = Application.get_env(:blockster_v2, :skip_fingerprint_check, false)

    Logger.info("[Accounts] authenticate_new_user_with_fingerprint: email=#{email}, skip_fingerprint=#{skip_fingerprint}")

    if skip_fingerprint do
      create_new_user_with_fingerprint(attrs)
    else
      # Step 1: Server-side verification with FingerprintJS API
      fingerprint_request_id = attrs["fingerprint_request_id"] || attrs[:fingerprint_request_id]

      case BlocksterV2.FingerprintVerifier.verify_event(fingerprint_request_id, fingerprint_id) do
        {:ok, _} ->
          # Step 2: Check PostgreSQL for fingerprint ownership
          case Repo.get_by(UserFingerprint, fingerprint_id: fingerprint_id) do
            nil ->
              # Fingerprint is available - create new account
              create_new_user_with_fingerprint(attrs)

            existing_fingerprint ->
              # BLOCK: Fingerprint already claimed by another user
              existing_user = get_user(existing_fingerprint.user_id)

              # Log suspicious activity
              {:ok, _} = update_user(existing_user, %{
                is_flagged_multi_account_attempt: true,
                last_suspicious_activity_at: DateTime.utc_now()
              })

              # Return error with masked email
              {:error, :fingerprint_conflict, existing_user.email}
          end

        {:error, reason} ->
          Logger.warning("[Accounts] Fingerprint server verification failed: #{reason} for #{email}")
          changeset = %User{}
            |> Ecto.Changeset.cast(%{}, [])
            |> Ecto.Changeset.add_error(:fingerprint_id, "fingerprint verification failed")
          {:error, changeset}
      end
    end
  end

  defp create_new_user_with_fingerprint(attrs) do
    email = String.downcase(attrs["email"] || attrs[:email])
    wallet_address = String.downcase(attrs["wallet_address"] || attrs[:wallet_address])
    smart_wallet_address = String.downcase(attrs["smart_wallet_address"] || attrs[:smart_wallet_address])
    fingerprint_id = attrs["fingerprint_id"] || attrs[:fingerprint_id]
    fingerprint_confidence = attrs["fingerprint_confidence"] || attrs[:fingerprint_confidence]

    # CREATE2 always produces a different address from the signer EOA
    if wallet_address == smart_wallet_address do
      Logger.warning("[Accounts] Rejected signup: smart_wallet == wallet for #{email}")
      changeset = %User{}
        |> Ecto.Changeset.cast(%{}, [])
        |> Ecto.Changeset.add_error(:smart_wallet_address, "invalid smart wallet address")
      {:error, changeset}
    else
      create_new_user_with_fingerprint_inner(attrs, email, wallet_address, smart_wallet_address, fingerprint_id, fingerprint_confidence)
    end
  end

  defp create_new_user_with_fingerprint_inner(_attrs, email, wallet_address, smart_wallet_address, fingerprint_id, fingerprint_confidence) do
    # Skip fingerprint insert if configured (dev mode or SKIP_FINGERPRINT_CHECK=true)
    skip_fingerprint = Application.get_env(:blockster_v2, :skip_fingerprint_check, false)

    # Start transaction to create user + fingerprint atomically
    multi = Ecto.Multi.new()
    |> Ecto.Multi.insert(:user, User.email_registration_changeset(%{
      email: email,
      wallet_address: wallet_address,
      smart_wallet_address: smart_wallet_address,
      registered_devices_count: if(skip_fingerprint, do: 0, else: 1)
    }))

    # Only insert fingerprint when NOT skipping (production with fingerprint check enabled)
    multi = if skip_fingerprint do
      multi
    else
      multi
      |> Ecto.Multi.insert(:fingerprint, fn %{user: user} ->
        UserFingerprint.changeset(%UserFingerprint{}, %{
          user_id: user.id,
          fingerprint_id: fingerprint_id,
          fingerprint_confidence: fingerprint_confidence,
          first_seen_at: DateTime.utc_now(),
          last_seen_at: DateTime.utc_now(),
          is_primary: true  # First device
        })
      end)
    end

    Logger.info("[Accounts] create_new_user_with_fingerprint: email=#{email}, skip_fingerprint=#{skip_fingerprint}")

    multi
    |> Ecto.Multi.run(:session, fn _repo, %{user: user} ->
      create_session(user.id)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user, session: session}} ->
        # Create betting stats record in Mnesia for admin dashboard queries
        create_user_betting_stats(user.id, user.smart_wallet_address)
        {:ok, user, session, true}  # true = is_new_user

      {:error, :user, changeset, _} ->
        {:error, changeset}

      {:error, :fingerprint, changeset, _} ->
        # Fingerprint constraint violation
        {:error, changeset}
    end
  end

  defp authenticate_existing_user_with_fingerprint(user, attrs) do
    smart_wallet_address = String.downcase(attrs["smart_wallet_address"] || attrs[:smart_wallet_address])
    fingerprint_id = attrs["fingerprint_id"] || attrs[:fingerprint_id]
    fingerprint_confidence = attrs["fingerprint_confidence"] || attrs[:fingerprint_confidence]

    # Log if smart_wallet_address differs but never overwrite — it's set once at signup
    if user.smart_wallet_address != smart_wallet_address do
      Logger.warning("[Accounts] smart_wallet_address mismatch for user #{user.id}: " <>
        "stored=#{user.smart_wallet_address} received=#{smart_wallet_address}")
    end

    # CRITICAL: Always check and claim fingerprints for existing users
    # This prevents unclaimed devices from being used for new account creation
    case Repo.get_by(UserFingerprint, fingerprint_id: fingerprint_id) do
      nil ->
        # NEW device - claim it for this user
        # This prevents someone else from creating an account on this device
        add_fingerprint_to_user(user, fingerprint_id, fingerprint_confidence)

      existing_fp when existing_fp.user_id == user.id ->
        # This user's device - update last_seen timestamp
        Repo.update(UserFingerprint.changeset(existing_fp, %{
          last_seen_at: DateTime.utc_now()
        }))

      _other_users_fingerprint ->
        # Different user's device (shared device scenario)
        # Examples: family computer, internet cafe, sold device
        # ALLOW login but DON'T claim the device
        # The device stays "owned" by whoever claimed it first
        # This still prevents NEW account creation on this device
        :ok
    end

    # Create session
    case create_session(user.id) do
      {:ok, session} -> {:ok, user, session, false}  # false = existing user
      error -> error
    end
  end

  defp add_fingerprint_to_user(user, fingerprint_id, fingerprint_confidence) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:fingerprint, UserFingerprint.changeset(%UserFingerprint{}, %{
      user_id: user.id,
      fingerprint_id: fingerprint_id,
      fingerprint_confidence: fingerprint_confidence,
      first_seen_at: DateTime.utc_now(),
      last_seen_at: DateTime.utc_now(),
      is_primary: false
    }))
    |> Ecto.Multi.update(:user, User.changeset(user, %{
      registered_devices_count: user.registered_devices_count + 1
    }))
    |> Repo.transaction()
    |> case do
      {:ok, _} -> {:ok, :device_added}
      {:error, _, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Get all devices (fingerprints) for a user.
  """
  def get_user_devices(user_id) do
    from(uf in UserFingerprint,
      where: uf.user_id == ^user_id,
      order_by: [desc: uf.is_primary, desc: uf.first_seen_at]
    )
    |> Repo.all()
  end

  @doc """
  Remove a device from a user's account.
  """
  def remove_user_device(user_id, fingerprint_id) do
    user = get_user(user_id)

    if user.registered_devices_count <= 1 do
      {:error, :cannot_remove_last_device}
    else
      Ecto.Multi.new()
      |> Ecto.Multi.delete_all(:fingerprint,
        from(uf in UserFingerprint,
          where: uf.user_id == ^user_id and uf.fingerprint_id == ^fingerprint_id
        )
      )
      |> Ecto.Multi.update(:user, User.changeset(user, %{
        registered_devices_count: user.registered_devices_count - 1
      }))
      |> Repo.transaction()
      |> case do
        {:ok, _} -> {:ok, :device_removed}
        {:error, _, reason, _} -> {:error, reason}
      end
    end
  end

  @doc """
  Lists all users who attempted multi-account creation.
  """
  def list_flagged_accounts do
    from(u in User,
      where: u.is_flagged_multi_account_attempt == true,
      order_by: [desc: u.last_suspicious_activity_at]
    )
    |> Repo.all()
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

  # ============ Admin Functions ============

@doc """
  Creates a betting stats record for a user in Mnesia.
  Called when a new user is created. All stats start at zero.
  This enables fast admin dashboard queries without PostgreSQL joins.
  """
  def create_user_betting_stats(user_id, wallet_address) when is_integer(user_id) do
    now = System.system_time(:millisecond)
    record = {:user_betting_stats,
      user_id,
      wallet_address || "",
      # BUX stats (all zeros)
      0, 0, 0, 0, 0, 0, 0,
      # ROGUE stats (all zeros)
      0, 0, 0, 0, 0, 0, 0,
      # Timestamps: first_bet_at, last_bet_at, updated_at
      nil, nil, now,
      # On-chain stats cache (nil until admin views player detail page)
      nil
    }
    :mnesia.dirty_write(record)
    :ok
  end

  @doc """
  Checks if a user is an admin.

  Admin status is determined by the `is_admin` boolean field on the User schema.

  ## Examples

      iex> is_admin?(%User{is_admin: true})
      true

      iex> is_admin?(%User{is_admin: false})
      false

      iex> is_admin?(nil)
      false
  """
  def is_admin?(nil), do: false

  def is_admin?(%User{is_admin: true}), do: true

  def is_admin?(_), do: false
end
