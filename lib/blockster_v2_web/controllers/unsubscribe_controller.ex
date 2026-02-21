defmodule BlocksterV2Web.UnsubscribeController do
  use BlocksterV2Web, :controller

  alias BlocksterV2.Notifications

  @doc """
  One-click unsubscribe from email link.
  GET /unsubscribe/:token
  """
  def unsubscribe(conn, %{"token" => token}) do
    case Notifications.unsubscribe_all(token) do
      {:ok, _prefs} ->
        conn
        |> put_flash(:info, "You have been unsubscribed from all email notifications.")
        |> redirect(to: "/")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, "Invalid or expired unsubscribe link.")
        |> redirect(to: "/")
    end
  end
end
