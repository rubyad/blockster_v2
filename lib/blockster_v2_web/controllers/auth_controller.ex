defmodule BlocksterV2Web.AuthController do
  use BlocksterV2Web, :controller
  alias BlocksterV2.{Accounts, Referrals, UserEvents}

  @doc """
  POST /api/auth/wallet/verify
  Verifies wallet signature and creates/authenticates user.
  Expects: %{wallet_address: "0x...", chain_id: 560013}
  """
  def verify_wallet(conn, %{"wallet_address" => wallet_address} = params) do
    chain_id = Map.get(params, "chain_id", 560013)

    case Accounts.authenticate_wallet(wallet_address, chain_id) do
      {:ok, user, session, is_new_user} ->
        UserEvents.track(user.id, "daily_login", %{source: "wallet"})
        if is_new_user, do: UserEvents.track(user.id, "session_start", %{source: "wallet"})

        conn
        |> put_session(:user_token, session.token)
        |> put_status(:ok)
        |> json(%{
          success: true,
          user: %{
            id: user.id,
            wallet_address: user.wallet_address,
            smart_wallet_address: user.smart_wallet_address,
            username: user.username,
            avatar_url: user.avatar_url,
            bux_balance: user.bux_balance,
            level: user.level,
            experience_points: user.experience_points,
            auth_method: user.auth_method,
            is_verified: user.is_verified
          },
          token: session.token,
          is_new_user: is_new_user
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{success: false, errors: translate_errors(changeset)})
    end
  end

  @doc """
  POST /api/auth/email/verify
  Verifies email signup and creates/authenticates user with fingerprint validation.
  Expects: %{
    email: "...",
    wallet_address: "0x...",
    smart_wallet_address: "0x...",
    fingerprint_id: "fp_...",
    fingerprint_confidence: 0.99,
    fingerprint_request_id: "req_..."
  }
  wallet_address = personal wallet (EOA) from Thirdweb in-app wallet
  smart_wallet_address = ERC-4337 smart wallet address (displayed to user)

  BLOCKS new account creation if fingerprint is already registered.
  ALLOWS existing users to login from new devices (adds fingerprint to their account).
  """
  def verify_email(conn, params) do
    referrer_wallet = Map.get(params, "referrer_wallet")
    require Logger
    Logger.info("[Auth] verify_email called with referrer_wallet: #{inspect(referrer_wallet)}")

    case Accounts.authenticate_email_with_fingerprint(params) do
      {:ok, user, session, is_new_user} ->
        Logger.info("[Auth] User authenticated - is_new_user: #{is_new_user}, referrer_wallet: #{inspect(referrer_wallet)}")

        UserEvents.track(user.id, "daily_login", %{source: "email"})
        if is_new_user, do: UserEvents.track(user.id, "session_start", %{source: "email"})

        # Process referral if new user with valid referrer
        if is_new_user && referrer_wallet && referrer_wallet != "" do
          result = Referrals.process_signup_referral(user, referrer_wallet)
          Logger.info("[Auth] Referral processing result: #{inspect(result)}")
        end

        conn
        |> put_session(:user_token, session.token)
        |> put_status(:ok)
        |> json(%{
          success: true,
          user: %{
            id: user.id,
            email: user.email,
            wallet_address: user.wallet_address,
            smart_wallet_address: user.smart_wallet_address,
            username: user.username,
            avatar_url: user.avatar_url,
            bux_balance: user.bux_balance,
            level: user.level,
            experience_points: user.experience_points,
            auth_method: user.auth_method,
            is_verified: user.is_verified,
            registered_devices_count: user.registered_devices_count
          },
          token: session.token,
          is_new_user: is_new_user
        })

      {:error, :fingerprint_conflict, existing_email} ->
        # HARD BLOCK: Fingerprint already belongs to another user
        conn
        |> put_status(:forbidden)
        |> json(%{
          success: false,
          error_type: "fingerprint_conflict",
          message: "This device is already registered to another account",
          existing_email: mask_email(existing_email)
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{success: false, errors: translate_errors(changeset)})
    end
  end

  @doc """
  POST /api/auth/logout
  Logs out the current user by deleting their session.
  """
  def logout(conn, _params) do
    token = get_session(conn, :user_token)

    if token do
      case Accounts.get_valid_session(token) do
        nil -> :ok
        session -> Accounts.delete_session(session)
      end
    end

    conn
    |> delete_session(:user_token)
    |> put_status(:ok)
    |> json(%{success: true, message: "Logged out successfully"})
  end

  @doc """
  GET /api/auth/me
  Returns the current authenticated user.
  """
  def me(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> json(%{success: false, error: "Not authenticated"})

      user ->
        conn
        |> put_status(:ok)
        |> json(%{
          success: true,
          user: %{
            id: user.id,
            email: user.email,
            wallet_address: user.wallet_address,
            smart_wallet_address: user.smart_wallet_address,
            username: user.username,
            avatar_url: user.avatar_url,
            bux_balance: user.bux_balance,
            level: user.level,
            experience_points: user.experience_points,
            auth_method: user.auth_method,
            is_verified: user.is_verified
          }
        })
    end
  end

  # Helper to translate changeset errors to JSON format
  defp translate_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end

  # Helper to mask email (show first 2 chars and domain)
  # Example: alice@example.com -> al***@example.com
  defp mask_email(email) do
    [username, domain] = String.split(email, "@")
    masked_username = String.slice(username, 0..1) <> "***"
    "#{masked_username}@#{domain}"
  end
end
