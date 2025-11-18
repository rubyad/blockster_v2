# Waitlist Production Setup Guide

This guide will help you deploy the waitlist email capture feature to production on Fly.io with AWS SES for sending emails.

## Prerequisites

- AWS Account with SES access
- Fly.io app deployed (`blockster-v2`)
- Domain name (optional, but recommended for production emails)

## Step 1: Verify Email Address in AWS SES

AWS SES requires you to verify email addresses before you can send emails from them.

### Option A: Verify a Single Email Address (For Testing)

1. Go to AWS SES Console: https://console.aws.amazon.com/ses/
2. Select your region (us-east-1 by default)
3. Navigate to **"Verified identities"** → **"Create identity"**
4. Select **"Email address"**
5. Enter: `noreply@blockster.com` (or your preferred email)
6. Click **"Create identity"**
7. Check the email inbox and click the verification link

### Option B: Verify a Domain (Recommended for Production)

1. Go to AWS SES Console
2. Navigate to **"Verified identities"** → **"Create identity"**
3. Select **"Domain"**
4. Enter your domain: `blockster.com`
5. Follow the instructions to add DNS records
6. Once verified, you can send from any email address on that domain

### Check SES Sandbox Status

By default, AWS SES operates in **sandbox mode**:
- You can only send to verified email addresses
- Limited to 200 emails per day
- Maximum send rate of 1 email per second

To move out of sandbox mode:
1. Go to **"Account dashboard"** in SES console
2. Click **"Request production access"**
3. Fill out the form explaining your use case
4. Wait for approval (usually 24-48 hours)

## Step 2: Set Fly.io Secrets

Set the required environment variables on Fly.io:

```bash
# Set the production app URL
flyctl secrets set APP_URL="https://blockster-v2.fly.dev" -a blockster-v2

# Set the from email address (must be verified in AWS SES)
flyctl secrets set WAITLIST_FROM_EMAIL="noreply@blockster.com" -a blockster-v2

# If you want to use a custom domain, also set:
flyctl secrets set PHX_HOST="blockster.com" -a blockster-v2
# This will make APP_URL become "https://blockster.com"

# Verify AWS credentials are already set
flyctl secrets list -a blockster-v2 | grep AWS
```

The AWS credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`) should already be set from your S3 configuration.

## Step 3: Run Database Migration

Run the waitlist migration on production:

```bash
flyctl ssh console -a blockster-v2
/app/bin/blockster_v2 eval "BlocksterV2.Release.migrate()"
exit
```

Or use the Fly.io console:

```bash
flyctl ssh console -a blockster-v2 -C "/app/bin/blockster_v2 eval 'BlocksterV2.Release.migrate()'"
```

## Step 4: Deploy to Production

Deploy the updated code:

```bash
flyctl deploy -a blockster-v2
```

## Step 5: Test the Waitlist

1. Visit: https://blockster-v2.fly.dev/waitlist
2. Enter a test email address
3. Check the email inbox for the verification email
4. Click the verification link
5. Verify you see the success message

## Troubleshooting

### Email Not Sending

Check the logs:
```bash
flyctl logs -a blockster-v2
```

Common issues:
- **Email not verified in SES**: Verify the from address in AWS SES console
- **Sandbox mode**: If testing with non-verified emails, request production access
- **AWS credentials**: Verify credentials are correct and have SES permissions
- **Region mismatch**: Ensure AWS_REGION matches where your email is verified

### Check Waitlist Entries

Connect to the production database:
```bash
flyctl postgres connect -a blockster-db
SELECT email, verified_at, inserted_at FROM waitlist_emails ORDER BY inserted_at DESC LIMIT 10;
```

### Test Email Sending Manually

SSH into the app and test:
```bash
flyctl ssh console -a blockster-v2

# In the Elixir console:
/app/bin/blockster_v2 remote

# Run this:
BlocksterV2.Waitlist.create_waitlist_email(%{email: "test@example.com"})
|> elem(1)
|> BlocksterV2.Waitlist.send_verification_email()
```

## Configuration Summary

### Environment Variables Set:
- `APP_URL` - Production URL (default: https://blockster-v2.fly.dev)
- `WAITLIST_FROM_EMAIL` - From email address (must be verified in SES)
- `AWS_ACCESS_KEY_ID` - AWS credentials (already set)
- `AWS_SECRET_ACCESS_KEY` - AWS credentials (already set)
- `AWS_REGION` - AWS region (already set, default: us-east-1)
- `PHX_HOST` (optional) - Custom domain

### Code Changes:
- ✅ Database migration for waitlist_emails table
- ✅ Waitlist context and schema
- ✅ Email verification with tokens (24-hour expiration)
- ✅ LiveView landing page at `/waitlist`
- ✅ AWS SES adapter configured for production
- ✅ Dynamic app URL based on environment

## Using a Custom Domain

If you want to use a custom domain like `blockster.com`:

1. Set up DNS:
   ```bash
   flyctl ips list -a blockster-v2
   ```
   Add A and AAAA records to your DNS pointing to Fly.io IPs

2. Add SSL certificate:
   ```bash
   flyctl certs add blockster.com -a blockster-v2
   flyctl certs add www.blockster.com -a blockster-v2
   ```

3. Set the PHX_HOST secret:
   ```bash
   flyctl secrets set PHX_HOST="blockster.com" -a blockster-v2
   ```

4. Verify the domain in AWS SES (recommended for professional emails)

## Support

For issues or questions:
- Check Fly.io logs: `flyctl logs -a blockster-v2`
- Check AWS SES sending statistics in AWS Console
- Review database entries for debugging
