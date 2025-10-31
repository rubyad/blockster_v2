defmodule BlocksterV2Web.UserAuth do
  @moduledoc """
  Handles mounting and authenticating the current_user in LiveViews.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias BlocksterV2.Accounts

  def on_mount(:default, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
  end

  defp mount_current_user(socket, session) do
    Phoenix.Component.assign_new(socket, :current_user, fn ->
      case session["user_token"] do
        nil -> nil
        token -> Accounts.get_user_by_session_token(token)
      end
    end)
  end
end
