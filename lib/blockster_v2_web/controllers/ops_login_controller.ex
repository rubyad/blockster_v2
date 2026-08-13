defmodule BlocksterV2Web.OpsLoginController do
  @moduledoc """
  TEMPORARY break-glass login, added during the Web3Auth sign-in outage
  (unpaid Web3Auth project → `getTorusKey` down → email/social sign-in broken
  for everyone). Lets a staff member sign in by minting a `UserSession` and
  setting the session cookie, bypassing Web3Auth entirely. Session auth is
  independent of Web3Auth, so this fully logs the user in — Web3Auth is only
  needed to *sign transactions*, not to be logged in or to post articles.

  Guards (all must pass, else an indistinguishable 404):
    * `OPS_LOGIN_SECRET` env var must be set AND match the `?key=` param,
      compared in constant time. No secret configured → route is dead (404).
    * target user's `email` must end in `@blockster.com` (staff only).
    * target user must be active (`is_active == true`).

  REMOVE this controller + its route in router.ex once Web3Auth sign-in is
  restored (or rotate/unset `OPS_LOGIN_SECRET` to disable it immediately).
  """
  use BlocksterV2Web, :controller

  require Logger

  alias BlocksterV2.Accounts

  def login(conn, %{"user_id" => user_id} = params) do
    if authorized?(params["key"]) do
      do_login(conn, user_id)
    else
      not_found(conn)
    end
  end

  def login(conn, _params), do: not_found(conn)

  defp authorized?(key) do
    secret = System.get_env("OPS_LOGIN_SECRET") || ""
    is_binary(key) and secret != "" and Plug.Crypto.secure_compare(key, secret)
  end

  defp do_login(conn, user_id) do
    with {id, ""} <- Integer.parse(to_string(user_id)),
         %{} = user <- Accounts.get_user(id),
         true <- staff_email?(user),
         true <- user.is_active == true,
         {:ok, session} <- Accounts.create_session(user.id) do
      Logger.warning(
        "[OpsLogin] break-glass login granted for user_id=#{user.id} email=#{user.email}"
      )

      conn
      |> put_session(:user_token, session.token)
      |> put_session(:wallet_address, user.wallet_address)
      |> redirect(to: ~p"/admin/posts")
    else
      _ -> not_found(conn)
    end
  end

  # Only real @blockster.com staff accounts are eligible — the domain guard is
  # a second line of defense behind the secret so a leaked/guessed URL still
  # can't mint a session for an arbitrary user id.
  defp staff_email?(user) do
    user
    |> Map.get(:email)
    |> to_string()
    |> String.match?(~r/@blockster\.com$/i)
  end

  defp not_found(conn) do
    conn |> put_status(404) |> text("not found")
  end
end
