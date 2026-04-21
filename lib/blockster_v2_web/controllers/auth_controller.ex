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
        if is_new_user do
          UserEvents.track(user.id, "signup", %{method: "wallet"})
          UserEvents.track(user.id, "session_start", %{source: "wallet"})
        end

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
        if is_new_user do
          UserEvents.track(user.id, "signup", %{method: "email"})
          UserEvents.track(user.id, "session_start", %{source: "email"})
        end

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
  POST /api/auth/session
  Persists wallet address to session cookie (called after SIWS verification in LiveView).
  """
  def create_session(conn, %{"wallet_address" => wallet_address}) when is_binary(wallet_address) do
    case Accounts.get_or_create_user_by_wallet(wallet_address) do
      {:ok, user, session, is_new_user} ->
        UserEvents.track(user.id, "daily_login", %{source: "solana_wallet"})
        if is_new_user do
          UserEvents.track(user.id, "signup", %{method: "solana_wallet"})
          UserEvents.track(user.id, "session_start", %{source: "solana_wallet"})
        end

        conn
        |> put_session(:wallet_address, wallet_address)
        |> put_status(:ok)
        |> json(%{success: true, is_new_user: is_new_user})

      {:error, _reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{success: false, error: "Failed to create session"})
    end
  end

  def create_session(conn, _params) do
    conn
    |> put_status(:bad_request)
    |> json(%{success: false, error: "Missing wallet_address"})
  end

  @doc """
  DELETE /api/auth/session
  Clears the wallet session.
  """
  def delete_session_action(conn, _params) do
    token = get_session(conn, :user_token)

    if token do
      case Accounts.get_valid_session(token) do
        nil -> :ok
        session -> Accounts.delete_session(session)
      end
    end

    conn
    |> delete_session(:user_token)
    |> delete_session(:wallet_address)
    |> put_status(:ok)
    |> json(%{success: true})
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

  @doc """
  POST /api/auth/web3auth/session
  Body: `%{"wallet_address" => <solana base58>, "id_token" => <Web3Auth JWT>}`

  Verifies the Web3Auth-issued ID token (ES256 signed by api-auth.web3auth.io)
  and creates or looks up the user. Sets a session cookie on success.
  """
  def verify_web3auth(conn, %{"wallet_address" => wallet_address, "id_token" => id_token})
      when is_binary(wallet_address) and is_binary(id_token) do
    case BlocksterV2.Auth.Web3Auth.verify_id_token(id_token,
           expected_wallet_pubkey: wallet_address
         ) do
      {:ok, claims} ->
        case BlocksterV2.Accounts.get_or_create_user_by_web3auth(claims) do
          {:ok, user, session, is_new_user} ->
            source =
              case claims.auth_connection do
                "twitter" -> "web3auth_x"
                "custom" -> "web3auth_telegram"
                _ -> "web3auth_email"
              end

            UserEvents.track(user.id, "daily_login", %{source: source})

            if is_new_user do
              UserEvents.track(user.id, "signup", %{method: source})
              UserEvents.track(user.id, "session_start", %{source: source})
            end

            conn
            |> put_session(:user_token, session.token)
            |> put_session(:wallet_address, user.wallet_address)
            |> put_status(:ok)
            |> json(%{
              success: true,
              is_new_user: is_new_user,
              auth_method: user.auth_method,
              user: %{
                id: user.id,
                wallet_address: user.wallet_address,
                email: user.email,
                auth_method: user.auth_method
              }
            })

          {:error, reason} ->
            conn
            |> put_status(:unprocessable_entity)
            |> json(%{
              success: false,
              error: "Failed to create or look up user",
              detail: inspect(reason)
            })
        end

      {:error, reason} ->
        require Logger
        Logger.warning("[Auth] Web3Auth verify failed: #{inspect(reason)}")

        conn
        |> put_status(:unauthorized)
        |> json(%{success: false, error: "Invalid Web3Auth token", detail: inspect(reason)})
    end
  end

  def verify_web3auth(conn, _) do
    conn
    |> put_status(:bad_request)
    |> json(%{success: false, error: "Missing wallet_address or id_token"})
  end

  @doc """
  POST /api/auth/telegram/verify
  Validates a Telegram Login Widget payload (HMAC-SHA256 of data_check_string
  with secret = SHA256(bot_token)) and issues a short-lived JWT that Web3Auth's
  Custom verifier consumes.

  Expects the full widget payload:
    %{"id" => 123, "first_name" => "...", "auth_date" => 1234567890, "hash" => "..."}
  """
  def telegram_verify(conn, %{"id" => id, "hash" => hash, "auth_date" => auth_date} = payload) do
    bot_token =
      System.get_env("BLOCKSTER_V2_BOT_TOKEN") ||
        System.get_env("TELEGRAM_V2_BOT_TOKEN") ||
        Application.get_env(:blockster_v2, :telegram_v2_bot_token)

    cond do
      is_nil(bot_token) or bot_token == "" ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{success: false, error: "Telegram bot not configured"})

      not valid_telegram_hash?(payload, hash, bot_token) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{success: false, error: "Invalid Telegram signature"})

      telegram_payload_too_old?(auth_date) ->
        conn
        |> put_status(:unauthorized)
        |> json(%{success: false, error: "Telegram auth expired"})

      true ->
        claims =
          %{
            "sub" => to_string(id),
            "telegram_user_id" => to_string(id),
            "telegram_username" => Map.get(payload, "username"),
            "telegram_first_name" => Map.get(payload, "first_name"),
            "telegram_photo_url" => Map.get(payload, "photo_url")
          }
          |> Enum.reject(fn {_, v} -> is_nil(v) end)
          |> Map.new()

        id_token = BlocksterV2.Auth.Web3AuthSigning.sign_id_token(claims)

        conn
        |> put_status(:ok)
        |> json(%{success: true, id_token: id_token})
    end
  end

  def telegram_verify(conn, _), do:
    conn
    |> put_status(:bad_request)
    |> json(%{success: false, error: "Missing Telegram payload"})

  @doc """
  GET /.well-known/jwks.json
  Returns the public JWK set Web3Auth uses to verify our signed JWTs.
  """
  def jwks(conn, _params) do
    conn
    |> put_resp_header("cache-control", "public, max-age=300")
    |> json(BlocksterV2.Auth.Web3AuthSigning.jwks())
  end

  # Telegram widget hash validation:
  # data_check_string = sorted "key=value" pairs (excluding hash) joined by \n
  # secret_key = SHA256(bot_token)
  # hmac_sha256(secret_key, data_check_string) must equal hash (hex)
  defp valid_telegram_hash?(payload, hash, bot_token) when is_binary(hash) do
    data_check_string =
      payload
      |> Map.delete("hash")
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.sort()
      |> Enum.join("\n")

    secret = :crypto.hash(:sha256, bot_token)
    expected = :crypto.mac(:hmac, :sha256, secret, data_check_string) |> Base.encode16(case: :lower)
    Plug.Crypto.secure_compare(String.downcase(hash), expected)
  end

  defp valid_telegram_hash?(_, _, _), do: false

  defp telegram_payload_too_old?(auth_date) when is_integer(auth_date) do
    System.system_time(:second) - auth_date > 86_400
  end

  defp telegram_payload_too_old?(auth_date) when is_binary(auth_date) do
    case Integer.parse(auth_date) do
      {val, _} -> telegram_payload_too_old?(val)
      _ -> true
    end
  end

  defp telegram_payload_too_old?(_), do: true

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
