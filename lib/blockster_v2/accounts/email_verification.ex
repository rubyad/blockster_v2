defmodule BlocksterV2.Accounts.EmailVerification do
  @moduledoc """
  Email verification system for the Solana migration.

  Users can verify their email to earn a 2x BUX multiplier boost.
  If a verified email matches a legacy (EVM) account, the user can
  claim their old BUX balance on Solana.

  Flow:
  1. User enters email → generate 6-digit code, store on user, send email
  2. User enters code within 10 minutes → verify → set email_verified = true
  3. If email matches legacy account → show migration prompt
  """

  alias BlocksterV2.{Repo, Mailer}
  alias BlocksterV2.Accounts.User
  import Ecto.Query
  require Logger

  @code_length 6
  @code_expiry_minutes 10

  @doc """
  Sends a verification code to the given email address.
  Stores the code and timestamp on the user record.

  Returns {:ok, user} or {:error, changeset | reason}.
  """
  def send_verification_code(user, email) do
    email = String.trim(email) |> String.downcase()
    code = generate_code()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    changeset = User.changeset(user, %{
      email: email,
      email_verification_code: code,
      email_verification_sent_at: now
    })

    case Repo.update(changeset) do
      {:ok, updated_user} ->
        # Send the email asynchronously
        Task.start(fn -> deliver_verification_email(email, code) end)
        {:ok, updated_user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Verifies the code the user entered.
  Returns {:ok, user} on success, {:error, reason} on failure.
  """
  def verify_code(user, code) do
    cond do
      is_nil(user.email_verification_code) ->
        {:error, :no_code_sent}

      is_nil(user.email_verification_sent_at) ->
        {:error, :no_code_sent}

      code_expired?(user.email_verification_sent_at) ->
        {:error, :code_expired}

      !Plug.Crypto.secure_compare(user.email_verification_code, String.trim(code)) ->
        {:error, :invalid_code}

      true ->
        changeset = User.changeset(user, %{
          email_verified: true,
          email_verification_code: nil,
          email_verification_sent_at: nil
        })

        case Repo.update(changeset) do
          {:ok, updated_user} ->
            Logger.info("[EmailVerification] User #{user.id} verified email #{user.email}")
            # Update email multiplier (1.0x → 2.0x)
            BlocksterV2.UnifiedMultiplier.update_email_multiplier(user.id)
            {:ok, updated_user}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @doc """
  Checks if a legacy (EVM) account exists for the given email.
  Returns the user record if found, nil otherwise.
  """
  def find_legacy_account(email) do
    email = String.trim(email) |> String.downcase()

    # Look for EVM users (auth_method: "email") with this email
    Repo.one(
      from u in User,
        where: u.email == ^email,
        where: u.auth_method == "email",
        where: not is_nil(u.smart_wallet_address),
        limit: 1
    )
  end

  @doc """
  Returns whether a verification code can be resent (rate limiting).
  Must wait at least 60 seconds between sends.
  """
  def can_resend?(user) do
    case user.email_verification_sent_at do
      nil -> true
      sent_at ->
        diff = DateTime.diff(DateTime.utc_now(), sent_at, :second)
        diff >= 60
    end
  end

  @doc """
  Returns seconds remaining before a code can be resent, or 0 if ready.
  """
  def resend_cooldown(user) do
    case user.email_verification_sent_at do
      nil -> 0
      sent_at ->
        diff = DateTime.diff(DateTime.utc_now(), sent_at, :second)
        max(60 - diff, 0)
    end
  end

  # ============================================================================
  # Private
  # ============================================================================

  defp generate_code do
    :rand.uniform(999_999)
    |> Integer.to_string()
    |> String.pad_leading(@code_length, "0")
  end

  defp code_expired?(sent_at) do
    DateTime.diff(DateTime.utc_now(), sent_at, :second) > @code_expiry_minutes * 60
  end

  defp deliver_verification_email(to_email, code) do
    email =
      Swoosh.Email.new()
      |> Swoosh.Email.to(to_email)
      |> Swoosh.Email.from({"Blockster", "noreply@blockster.com"})
      |> Swoosh.Email.subject("Your Blockster verification code: #{code}")
      |> Swoosh.Email.html_body(verification_email_html(code))
      |> Swoosh.Email.text_body(verification_email_text(code))

    case Mailer.deliver(email) do
      {:ok, _} ->
        Logger.info("[EmailVerification] Sent code to #{to_email}")

      {:error, reason} ->
        Logger.error("[EmailVerification] Failed to send to #{to_email}: #{inspect(reason)}")
    end
  end

  defp verification_email_html(code) do
    """
    <!DOCTYPE html>
    <html>
    <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; background: #f4f4f5; padding: 40px 0;">
      <div style="max-width: 440px; margin: 0 auto; background: white; border-radius: 12px; padding: 40px; text-align: center;">
        <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="Blockster" width="48" height="48" style="margin-bottom: 24px;" />
        <h1 style="font-size: 22px; color: #141414; margin: 0 0 8px;">Verify your email</h1>
        <p style="color: #666; font-size: 15px; margin: 0 0 32px;">Enter this code in Blockster to verify your email and earn <strong>2x BUX rewards</strong>.</p>
        <div style="background: #f4f4f5; border-radius: 8px; padding: 20px; margin: 0 0 32px;">
          <span style="font-family: monospace; font-size: 36px; font-weight: 700; letter-spacing: 8px; color: #141414;">#{code}</span>
        </div>
        <p style="color: #999; font-size: 13px; margin: 0;">This code expires in 10 minutes. If you didn't request this, ignore this email.</p>
      </div>
    </body>
    </html>
    """
  end

  defp verification_email_text(code) do
    """
    Your Blockster verification code is: #{code}

    Enter this code in Blockster to verify your email and earn 2x BUX rewards.

    This code expires in 10 minutes. If you didn't request this, ignore this email.
    """
  end
end
