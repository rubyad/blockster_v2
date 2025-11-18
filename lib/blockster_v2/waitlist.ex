defmodule BlocksterV2.Waitlist do
  @moduledoc """
  The Waitlist context for managing email waitlist signups.
  """

  import Ecto.Query, warn: false
  alias BlocksterV2.Repo
  alias BlocksterV2.Waitlist.WaitlistEmail

  @doc """
  Lists all waitlist emails, ordered by most recent first.
  """
  def list_waitlist_emails do
    WaitlistEmail
    |> order_by([w], desc: w.inserted_at)
    |> Repo.all()
  end

  @doc """
  Creates a new waitlist email entry.
  """
  def create_waitlist_email(attrs \\ %{}) do
    %WaitlistEmail{}
    |> WaitlistEmail.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Gets a waitlist email by email address.
  """
  def get_waitlist_email_by_email(email) when is_binary(email) do
    Repo.get_by(WaitlistEmail, email: String.downcase(email))
  end

  @doc """
  Gets a waitlist email by verification token.
  """
  def get_waitlist_email_by_token(token) when is_binary(token) do
    Repo.get_by(WaitlistEmail, verification_token: token)
  end

  @doc """
  Generates a verification token and updates the waitlist email.
  """
  def generate_verification_token(waitlist_email) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)

    waitlist_email
    |> WaitlistEmail.token_changeset(%{
      verification_token: token,
      token_sent_at: DateTime.utc_now()
    })
    |> Repo.update()
  end

  @doc """
  Verifies an email using the verification token.
  """
  def verify_email(token) when is_binary(token) do
    case get_waitlist_email_by_token(token) do
      nil ->
        {:error, :invalid_token}

      waitlist_email ->
        # Check if token is still valid (24 hours)
        if token_expired?(waitlist_email.token_sent_at) do
          {:error, :token_expired}
        else
          waitlist_email
          |> WaitlistEmail.verification_changeset(%{verified_at: DateTime.utc_now()})
          |> Repo.update()
        end
    end
  end

  defp token_expired?(token_sent_at) do
    if token_sent_at do
      DateTime.diff(DateTime.utc_now(), token_sent_at, :hour) > 24
    else
      true
    end
  end

  @doc """
  Sends verification email to the waitlist email address.
  Optionally accepts a base_url to use for the verification link.
  """
  def send_verification_email(waitlist_email, base_url \\ nil) do
    # Generate token if not already present
    {:ok, waitlist_email_with_token} =
      if waitlist_email.verification_token do
        {:ok, waitlist_email}
      else
        generate_verification_token(waitlist_email)
      end

    # Send the email
    BlocksterV2.Emails.WaitlistEmail.verification_email(waitlist_email_with_token, base_url)
    |> BlocksterV2.Mailer.deliver()
  end
end
