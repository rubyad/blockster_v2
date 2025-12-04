defmodule BlocksterV2Web.AuthController do
  use BlocksterV2Web, :controller
  alias BlocksterV2.Accounts

  @doc """
  POST /api/auth/wallet/verify
  Verifies wallet signature and creates/authenticates user.
  Expects: %{wallet_address: "0x...", chain_id: 560013}
  """
  def verify_wallet(conn, %{"wallet_address" => wallet_address} = params) do
    chain_id = Map.get(params, "chain_id", 560013)

    case Accounts.authenticate_wallet(wallet_address, chain_id) do
      {:ok, user, session} ->
        conn
        |> put_session(:user_token, session.token)
        |> put_status(:ok)
        |> json(%{
          success: true,
          user: %{
            id: user.id,
            wallet_address: user.wallet_address,
            username: user.username,
            avatar_url: user.avatar_url,
            bux_balance: user.bux_balance,
            level: user.level,
            experience_points: user.experience_points,
            auth_method: user.auth_method,
            is_verified: user.is_verified
          },
          token: session.token
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{success: false, errors: translate_errors(changeset)})
    end
  end

  @doc """
  POST /api/auth/email/verify
  Verifies email signup and creates/authenticates user.
  Expects: %{email: "...", wallet_address: "0x...", smart_wallet_address: "0x..."}
  wallet_address = personal wallet (EOA) from Thirdweb in-app wallet
  smart_wallet_address = ERC-4337 smart wallet address (displayed to user)
  """
  def verify_email(conn, %{"email" => email, "wallet_address" => wallet_address, "smart_wallet_address" => smart_wallet_address}) do
    case Accounts.authenticate_email(email, wallet_address, smart_wallet_address) do
      {:ok, user, session} ->
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
            is_verified: user.is_verified
          },
          token: session.token
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
end
