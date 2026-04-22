defmodule BlocksterV2Web.AdminAuth do
  @moduledoc """
  LiveView on_mount hook to ensure only admin users can access certain pages.

  Runs AFTER BlocksterV2Web.UserAuth, which populates @current_user from
  session["wallet_address"] (or connect_params on a connected mount).

  See `docs/auth_session_contract.md` for the GLOBAL-01 flash-bug
  diagnosis — the admin flash user-reported in that ticket can happen
  on static mount when the session cookie is present but browser
  timing caused connect_params to beat it, or vice versa.
  """
  import Phoenix.LiveView

  require Logger

  @debug_auth System.get_env("BLOCKSTER_DEBUG_AUTH") == "1"

  def on_mount(:default, _params, _session, socket) do
    log_admin_debug(socket)

    case socket.assigns[:current_user] do
      nil ->
        {:halt, socket |> put_flash(:error, "You must be logged in to access this page") |> redirect(to: "/")}

      %{is_admin: true} ->
        {:cont, socket}

      _user ->
        {:halt, socket |> put_flash(:error, "You must be an admin to access this page") |> redirect(to: "/")}
    end
  end

  defp log_admin_debug(_) when not @debug_auth, do: :ok

  defp log_admin_debug(socket) do
    user = socket.assigns[:current_user]
    is_admin = if user, do: Map.get(user, :is_admin, false), else: nil
    Logger.debug(
      "[AdminAuth] connected?=#{connected?(socket)} user_id=#{inspect(user && user.id)} is_admin=#{inspect(is_admin)}"
    )
  end
end
