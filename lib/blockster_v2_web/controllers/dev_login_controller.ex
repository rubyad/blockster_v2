defmodule BlocksterV2Web.DevLoginController do
  @moduledoc """
  DEV-ONLY login helper. Signs the given user in by minting a UserSession
  and setting the session cookie. Route is only mounted when
  `:dev_routes` is enabled (never in prod).

  Used exclusively for manual E2E verification of auth-gated pages like
  /wallet. Delete when not actively testing.
  """
  use BlocksterV2Web, :controller

  alias BlocksterV2.Accounts

  def login(conn, %{"user_id" => user_id}) do
    unless Application.get_env(:blockster_v2, :dev_routes, false) do
      conn |> put_status(404) |> text("not found")
    else
      do_login(conn, user_id)
    end
  end

  defp do_login(conn, user_id) do
    case Integer.parse(to_string(user_id)) do
      {id, _} ->
        case Accounts.get_user(id) do
          nil ->
            conn |> put_status(404) |> text("user not found")

          user ->
            {:ok, session} = Accounts.create_session(user.id)

            conn
            |> put_session(:user_token, session.token)
            |> put_session(:wallet_address, user.wallet_address)
            |> redirect(to: ~p"/wallet")
        end

      :error ->
        conn |> put_status(400) |> text("bad user_id")
    end
  end
end
