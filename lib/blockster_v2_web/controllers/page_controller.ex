defmodule BlocksterV2Web.PageController do
  use BlocksterV2Web, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  @doc """
  Redirects /profile to the user's member page with Settings tab active.
  """
  def profile_redirect(conn, _params) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_flash(:error, "You must be logged in to view your profile")
        |> redirect(to: ~p"/login")

      user ->
        slug = user.slug || user.smart_wallet_address
        redirect(conn, to: ~p"/member/#{slug}?tab=settings")
    end
  end
end
