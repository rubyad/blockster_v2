defmodule BlocksterV2Web.WaitlistController do
  use BlocksterV2Web, :controller
  alias BlocksterV2.Waitlist

  def verify(conn, %{"token" => token}) do
    case Waitlist.verify_email(token) do
      {:ok, _waitlist_email} ->
        redirect(conn,
          to: ~p"/waitlist?status=success&message=Thanks for verifying your email, you're on the waitlist!"
        )

      {:error, :invalid_token} ->
        redirect(conn, to: ~p"/waitlist?status=error&message=Invalid verification link.")

      {:error, :token_expired} ->
        redirect(conn,
          to: ~p"/waitlist?status=error&message=Verification link has expired. Please sign up again."
        )
    end
  end
end
