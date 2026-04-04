defmodule BlocksterV2Web.Plugs.AuthPlug do
  @moduledoc """
  Plug for authenticating users via Solana wallet session.
  Clears any legacy EVM user_token from the session.
  """
  import Plug.Conn
  alias BlocksterV2.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    # Clear legacy EVM user_token if present — Solana wallet is the only auth now
    conn =
      if get_session(conn, :user_token) do
        delete_session(conn, :user_token)
      else
        conn
      end

    # Authenticate via wallet_address in session
    case get_session(conn, :wallet_address) do
      nil ->
        assign(conn, :current_user, nil)

      address when is_binary(address) and address != "" ->
        case Accounts.get_user_by_wallet_address(address) do
          nil -> assign(conn, :current_user, nil)
          user -> assign(conn, :current_user, user)
        end

      _ ->
        assign(conn, :current_user, nil)
    end
  end

  @doc """
  Require authentication. Call this in your controller to ensure user is logged in.
  """
  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_status(:unauthorized)
      |> Phoenix.Controller.json(%{success: false, error: "Authentication required"})
      |> halt()
    end
  end
end
