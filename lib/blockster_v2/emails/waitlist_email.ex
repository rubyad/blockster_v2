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
    <!DOCTYPE html>
    <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>Verify Your Email</title>
      </head>
      <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
        <div style="background: linear-gradient(135deg, #10b981 0%, #059669 100%); padding: 40px 20px; text-align: center; border-radius: 10px 10px 0 0;">
          <img src="https://ik.imagekit.io/blockster/logo.png" alt="Blockster Logo" style="width: 80px; height: 80px; margin: 0 auto 20px; display: block;" />
          <h1 style="color: white; margin: 0; font-size: 28px;">Blockster V2 Coming Soon</h1>
        </div>

        <div style="background: #ffffff; padding: 40px 30px; border: 1px solid #e5e7eb; border-top: none; border-radius: 0 0 10px 10px;">
          <p style="font-size: 16px; margin-bottom: 20px;">Thank you for joining the Blockster waitlist!</p>

          <p style="font-size: 16px; margin-bottom: 30px;">Please verify your email address by clicking the button below:</p>

          <div style="text-align: center; margin: 30px 0;">
            <a href="#{verification_url}" style="background: linear-gradient(135deg, #10b981 0%, #059669 100%); color: white; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: bold; display: inline-block; font-size: 16px;">Verify Email</a>
          </div>

          <p style="font-size: 14px; color: #6b7280; margin-top: 30px;">Or copy and paste this link into your browser:</p>
          <p style="font-size: 12px; color: #9ca3af; word-break: break-all; background: #f9fafb; padding: 10px; border-radius: 5px;">#{verification_url}</p>

          <p style="font-size: 14px; color: #6b7280; margin-top: 30px;">This link will expire in 24 hours.</p>

          <p style="font-size: 14px; color: #6b7280; margin-top: 30px;">If you didn't sign up for the Blockster waitlist, you can safely ignore this email.</p>
        </div>

        <div style="text-align: center; margin-top: 30px; color: #9ca3af; font-size: 12px;">
          <p>&copy; 2025 Blockster. All rights reserved.</p>
          <p style="margin-top: 10px;">Blockster Media & Technology, LLC</p>
          <p>1111 Lincoln Road, Suite 500, Miami Beach, FL 33139</p>
        </div>
      </body>
    </html>
    """)
    |> text_body("""
    Blockster V2 Coming Soon

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
