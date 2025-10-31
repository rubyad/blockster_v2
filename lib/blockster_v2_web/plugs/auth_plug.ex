defmodule BlocksterV2Web.Plugs.AuthPlug do
  @moduledoc """
  Plug for authenticating users via session tokens.
  Checks for user_token in session and assigns current_user if valid.
  """
  import Plug.Conn
  alias BlocksterV2.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, :user_token) do
      nil ->
        assign(conn, :current_user, nil)

      token ->
        case Accounts.get_user_by_session_token(token) do
          nil ->
            conn
            |> delete_session(:user_token)
            |> assign(:current_user, nil)

          user ->
            assign(conn, :current_user, user)
        end
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
