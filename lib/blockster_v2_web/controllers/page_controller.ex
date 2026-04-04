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
        |> put_flash(:info, "Connect your wallet to view your profile")
        |> redirect(to: ~p"/")

      user ->
        slug = user.slug || user.wallet_address
        redirect(conn, to: ~p"/member/#{slug}?tab=settings")
    end
  end

  @doc """
  Redirects /login to homepage. Login page removed in Solana migration —
  auth handled by wallet selector modal.
  """
  def login_redirect(conn, _params) do
    redirect(conn, to: ~p"/")
  end
end
