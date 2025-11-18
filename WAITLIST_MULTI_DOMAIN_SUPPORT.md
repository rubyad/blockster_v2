# Waitlist Multi-Domain Support

## Problem

The waitlist page needs to work on multiple domains:
- `https://blockster-v2.fly.dev/waitlist` (direct Fly.io access)
- `https://v2.blockster.com` (production subdomain via CNAME)

If we set a single `APP_URL` environment variable, it would break the app on one of the domains because:
- Setting `APP_URL=https://v2.blockster.com` would make verification links point to v2.blockster.com even when accessed via fly.dev
- This could cause issues if the CNAME isn't set up yet or if users access via the direct Fly URL

## Solution

The waitlist now **dynamically detects the domain** from which it's accessed and uses that domain for verification emails. Additionally, when accessed via `v2.blockster.com`, the root path automatically redirects to `/waitlist`. This means:

✅ User visits `https://blockster-v2.fly.dev/waitlist` → Email contains verification link to `https://blockster-v2.fly.dev/waitlist/verify`

✅ User visits `https://v2.blockster.com/waitlist` → Email contains verification link to `https://v2.blockster.com/waitlist/verify`

✅ User visits `https://v2.blockster.com/` → Automatically redirects to `https://v2.blockster.com/waitlist`

✅ Production defaults to v2.blockster.com domain

✅ Rest of the app continues working normally on both domains

## How It Works

### 1. Root Path Redirect ([v2_redirect_plug.ex](lib/blockster_v2_web/plugs/v2_redirect_plug.ex))

```elixir
defmodule BlocksterV2Web.Plugs.V2RedirectPlug do
  @moduledoc """
  Redirects root path to /waitlist when accessed from v2.blockster.com
  """
  import Plug.Conn
  import Phoenix.Controller

  def init(opts), do: opts

  def call(conn, _opts) do
    if conn.request_path == "/" and conn.host == "v2.blockster.com" do
      conn
      |> redirect(to: "/waitlist")
      |> halt()
    else
      conn
    end
  end
end
```

This plug is added to the browser pipeline in [router.ex](lib/blockster_v2_web/router.ex#L11) and checks if the user visits the root path on v2.blockster.com. If so, it redirects them to `/waitlist`.

### 2. Domain Security Configuration ([runtime.exs](config/runtime.exs#L102-L105))

```elixir
check_origin: [
  "https://blockster-v2.fly.dev",
  "https://v2.blockster.com"
],
```

The endpoint is configured to accept WebSocket connections from both domains for LiveView functionality.

### 3. Production Default Domain ([runtime.exs](config/runtime.exs#L146-L147))

```elixir
app_host = System.get_env("PHX_HOST") || "v2.blockster.com"
config :blockster_v2, app_url: "https://#{app_host}"
```

In production, the app_url defaults to v2.blockster.com unless overridden by the PHX_HOST environment variable.

### 4. Base URL Detection ([waitlist_live.ex](lib/blockster_v2_web/live/waitlist_live.ex#L19))

```elixir
def mount(params, _session, socket) do
  # Capture the base URL from the current request
  base_url = get_base_url(socket)

  socket =
    socket
    |> assign(base_url: base_url)
    # ... other assigns
end

defp get_base_url(socket) do
  uri = socket.host_uri || ""

  # If host_uri is available, use it (contains full URL like https://v2.blockster.com)
  # Otherwise, fall back to endpoint configuration
end
```

The LiveView captures the request's host URI on mount, which contains the domain the user used to access the page.

### 5. Passing Base URL to Email Function ([waitlist_live.ex](lib/blockster_v2_web/live/waitlist_live.ex#L61))

```elixir
def handle_event("join_waitlist", %{"email" => email}, socket) do
  base_url = socket.assigns.base_url

  # Pass base_url when sending verification email
  Waitlist.send_verification_email(waitlist_email, base_url)
end
```

When sending the verification email, the LiveView passes the captured base URL.

### 6. Email Template Uses Dynamic URL ([waitlist_email.ex](lib/blockster_v2/emails/waitlist_email.ex#L8))

```elixir
def verification_email(waitlist_email, base_url \\ nil) do
  # Use provided base_url or fall back to app config
  base_url = base_url || Application.get_env(:blockster_v2, :app_url, "http://localhost:4000")
  verification_url = "#{base_url}/waitlist/verify?token=#{waitlist_email.verification_token}"
  # ... build email with verification_url
end
```

The email template accepts an optional `base_url` parameter. If provided, it uses that; otherwise, it falls back to the `app_url` config.

## Configuration

### Current Setup (Production)

```bash
# These are configured in config/runtime.exs
PHX_HOST="v2.blockster.com"  # Production default
WAITLIST_FROM_EMAIL="info@blockster.com"

# Check origin allows both domains
check_origin: [
  "https://blockster-v2.fly.dev",
  "https://v2.blockster.com"
]
```

### When Using Custom Domain

The system automatically detects the domain, but you need to:

1. **Set up CNAME** in your DNS:
   ```
   v2.blockster.com → blockster-v2.fly.dev
   ```
   ✅ **Status: Complete**

2. **Add SSL certificate** on Fly.io:
   ```bash
   flyctl certs add v2.blockster.com -a blockster-v2
   ```
   ✅ **Status: Complete** (certificate provisioning in progress)

3. **Verify certificate status**:
   ```bash
   flyctl certs check v2.blockster.com -a blockster-v2
   ```

## Testing

### Test on Fly.io Domain
```bash
# Visit the page
https://blockster-v2.fly.dev/waitlist

# Submit an email
# Check the verification email
# The link should be: https://blockster-v2.fly.dev/waitlist/verify?token=...
```

### Test on Custom Domain
```bash
# Test root redirect
https://v2.blockster.com/ → redirects to https://v2.blockster.com/waitlist

# Visit the waitlist page directly
https://v2.blockster.com/waitlist

# Submit an email
# Check the verification email
# The link should be: https://v2.blockster.com/waitlist/verify?token=...
```

### Test Both Work Simultaneously
1. Submit email via `blockster-v2.fly.dev/waitlist` → Link uses fly.dev domain
2. Submit email via `v2.blockster.com/waitlist` → Link uses v2.blockster.com domain
3. Both verification links work correctly
4. Visiting `v2.blockster.com/` redirects to `/waitlist`

## Advantages

1. **Automatic domain detection** - Works on any domain without configuration changes
2. **Root redirect** - v2.blockster.com automatically redirects to waitlist page
3. **No breaking changes** - Existing fly.dev deployment continues working
4. **Flexible** - Can be accessed via multiple domains simultaneously
5. **User-friendly** - Verification links match the domain the user used
6. **Secure** - check_origin configuration prevents CSRF attacks
7. **Production-ready** - Defaults to v2.blockster.com in production

## Edge Cases Handled

- If `host_uri` is not available, falls back to `app_url` config
- If `app_url` is not set, falls back to localhost:4000 (development)
- Works with or without custom domains
- Only redirects root on v2.blockster.com (other domains work normally)
- Preserves all existing routes and functionality

## Files Modified

1. [lib/blockster_v2_web/plugs/v2_redirect_plug.ex](lib/blockster_v2_web/plugs/v2_redirect_plug.ex) - **NEW** - Redirects v2.blockster.com root to /waitlist
2. [lib/blockster_v2_web/router.ex](lib/blockster_v2_web/router.ex#L11) - Added V2RedirectPlug to browser pipeline
3. [config/runtime.exs](config/runtime.exs#L102-L105) - Added check_origin for both domains
4. [config/runtime.exs](config/runtime.exs#L146-L147) - Set production default to v2.blockster.com
5. [lib/blockster_v2_web/live/waitlist_live.ex](lib/blockster_v2_web/live/waitlist_live.ex) - Captures and passes base URL
6. [lib/blockster_v2/waitlist.ex](lib/blockster_v2/waitlist.ex) - Accepts optional base_url parameter
7. [lib/blockster_v2/emails/waitlist_email.ex](lib/blockster_v2/emails/waitlist_email.ex) - Uses dynamic base URL

## Deployment Status

✅ **Code deployed** - All changes are live on production
✅ **CNAME configured** - v2.blockster.com → blockster-v2.fly.dev
✅ **SSL certificate issued** - Let's Encrypt certificate (RSA + ECDSA), auto-renews

🎉 **The site is now fully live at https://v2.blockster.com**

Visit https://v2.blockster.com and it will automatically redirect to the waitlist page!
