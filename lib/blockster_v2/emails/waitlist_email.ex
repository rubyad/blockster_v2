defmodule BlocksterV2.Emails.WaitlistEmail do
  import Swoosh.Email

  @doc """
  Sends a verification email to a waitlist subscriber.
  Optionally accepts a base_url to override the default app URL.
  """
  def verification_email(waitlist_email, base_url \\ nil) do
    # Generate verification URL - use provided base_url or fall back to config
    base_url = base_url || Application.get_env(:blockster_v2, :app_url, "http://localhost:4000")
    verification_url = "#{base_url}/waitlist/verify?token=#{waitlist_email.verification_token}"

    # Use environment variable or default for production
    from_email = System.get_env("WAITLIST_FROM_EMAIL") || "info@blockster.com"

    new()
    |> to(waitlist_email.email)
    |> from({"Blockster", from_email})
    |> subject("Verify your email for Blockster Waitlist")
    |> html_body("""
    <p>Thank you for joining the Blockster waitlist!</p>

    <p>Please verify your email address by clicking the button below:</p>

    <p><a href="#{verification_url}" style="display: inline-block; padding: 12px 24px; background-color: #000000; color: #ffffff; text-decoration: none; border-radius: 4px;">Verify Email</a></p>

    <p>This link will expire in 24 hours.</p>

    <p>If you didn't sign up for the Blockster waitlist, you can safely ignore this email.</p>

    <p>© 2025 Blockster. All rights reserved.<br>
    Blockster Media & Technology, LLC<br>
    1111 Lincoln Road, Suite 500, Miami Beach, FL 33139</p>
    """)
    |> text_body("""
    Thank you for joining the Blockster waitlist!

    Please verify your email address by clicking this link:
    #{verification_url}

    This link will expire in 24 hours.

    If you didn't sign up for the Blockster waitlist, you can safely ignore this email.

    © 2025 Blockster. All rights reserved.
    Blockster Media & Technology, LLC
    1111 Lincoln Road, Suite 500, Miami Beach, FL 33139
    """)
  end
end
