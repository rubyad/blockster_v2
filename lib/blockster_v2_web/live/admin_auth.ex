defmodule BlocksterV2Web.AdminAuth do
  @moduledoc """
  LiveView on_mount hook to ensure only admin users can access certain pages.
  """
  import Phoenix.LiveView

  def on_mount(:default, _params, _session, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:halt, socket |> put_flash(:error, "You must be logged in to access this page") |> redirect(to: "/")}

      %{is_admin: true} ->
        {:cont, socket}

      _user ->
        {:halt, socket |> put_flash(:error, "You must be an admin to access this page") |> redirect(to: "/")}
    end
  end
end
