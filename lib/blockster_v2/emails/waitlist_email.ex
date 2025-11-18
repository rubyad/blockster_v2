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
      <body style="margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; background-color: #f3f4f6;">
        <table width="100%" cellpadding="0" cellspacing="0" style="background-color: #f3f4f6; padding: 20px 0;">
          <tr>
            <td align="center">
              <table width="600" cellpadding="0" cellspacing="0" style="max-width: 600px; background-color: #ffffff; border-radius: 10px; overflow: hidden; box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);">
                <!-- Header with solid background -->
                <tr>
                  <td style="background-color: #CAFC00; padding: 40px 20px; text-align: center;">
                    <img src="https://ik.imagekit.io/blockster/logo.png" alt="Blockster Logo" style="width: 80px; height: 80px; margin: 0 auto 20px; display: block;" />
                    <h1 style="color: #000000; margin: 0; font-size: 28px; font-weight: bold;">Blockster V2 Coming Soon</h1>
                  </td>
                </tr>

                <!-- Content -->
                <tr>
                  <td style="background-color: #ffffff; padding: 40px 30px;">
                    <p style="font-size: 16px; color: #333333; margin: 0 0 20px 0; line-height: 1.6;">Thank you for joining the Blockster waitlist!</p>

                    <p style="font-size: 16px; color: #333333; margin: 0 0 30px 0; line-height: 1.6;">Please verify your email address by clicking the button below:</p>

                    <!-- Button -->
                    <table width="100%" cellpadding="0" cellspacing="0">
                      <tr>
                        <td align="center" style="padding: 30px 0;">
                          <table cellpadding="0" cellspacing="0">
                            <tr>
                              <td style="background-color: #CAFC00; border-radius: 8px;">
                                <a href="#{verification_url}" style="background-color: #CAFC00; color: #000000; padding: 14px 40px; text-decoration: none; border-radius: 8px; font-weight: bold; display: inline-block; font-size: 16px;">Verify Email</a>
                              </td>
                            </tr>
                          </table>
                        </td>
                      </tr>
                    </table>

                    <p style="font-size: 14px; color: #6b7280; margin: 30px 0 10px 0; line-height: 1.6;">Or copy and paste this link into your browser:</p>
                    <p style="font-size: 12px; color: #4b5563; word-break: break-all; background-color: #f9fafb; padding: 12px; border-radius: 5px; margin: 0 0 30px 0; border: 1px solid #e5e7eb;">#{verification_url}</p>

                    <p style="font-size: 14px; color: #6b7280; margin: 0 0 20px 0; line-height: 1.6;">This link will expire in 24 hours.</p>

                    <p style="font-size: 14px; color: #6b7280; margin: 0; line-height: 1.6;">If you didn't sign up for the Blockster waitlist, you can safely ignore this email.</p>
                  </td>
                </tr>

                <!-- Footer -->
                <tr>
                  <td style="background-color: #f9fafb; padding: 30px; text-align: center; border-top: 1px solid #e5e7eb;">
                    <p style="font-size: 12px; color: #9ca3af; margin: 0 0 10px 0;">&copy; 2025 Blockster. All rights reserved.</p>
                    <p style="font-size: 12px; color: #9ca3af; margin: 0 0 5px 0;">Blockster Media & Technology, LLC</p>
                    <p style="font-size: 12px; color: #9ca3af; margin: 0;">1111 Lincoln Road, Suite 500, Miami Beach, FL 33139</p>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
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
