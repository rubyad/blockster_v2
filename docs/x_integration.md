# X (Twitter) Integration Documentation

This document provides a comprehensive guide to the X (Twitter) integration in Blockster V2, covering OAuth authentication, share campaigns, and the retweet & like reward system.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Database Schema](#database-schema)
4. [Mnesia Integration](#mnesia-integration)
5. [OAuth 2.0 Flow](#oauth-20-flow)
6. [X API Client](#x-api-client)
7. [Share Campaigns](#share-campaigns)
8. [Retweet & Like Flow](#retweet--like-flow)
9. [Error Handling](#error-handling)
10. [Configuration](#configuration)
11. [Troubleshooting](#troubleshooting)

---

## Overview

The X integration allows users to:
- Connect their X (Twitter) account via OAuth 2.0 with PKCE
- Participate in share campaigns by retweeting and liking specific tweets
- Earn BUX rewards for successful participation

### Key Features
- **OAuth 2.0 with PKCE**: Secure authentication without exposing secrets
- **Token Refresh**: Automatic token refresh when tokens expire
- **Retry Logic**: Automatic retries for transient network errors
- **Campaign Management**: Admin can create campaigns linked to posts

---

## Architecture

### File Structure

```
lib/blockster_v2/
├── social/
│   ├── x_api_client.ex      # X API v2 HTTP client
│   ├── x_connection.ex      # User's X account connection schema
│   ├── x_oauth_state.ex     # OAuth state management schema
│   ├── share_campaign.ex    # Share campaign schema
│   └── share_reward.ex      # User rewards schema
├── social.ex                # Social context (business logic)

lib/blockster_v2_web/
├── controllers/
│   └── x_auth_controller.ex # OAuth callback handler
├── live/
│   └── post_live/
│       ├── show.ex          # Post page with share modal
│       └── show.html.heex   # Template with share UI
```

### Key Modules

| Module | Purpose |
|--------|---------|
| `BlocksterV2.Social` | Business logic for X integration |
| `BlocksterV2.Social.XApiClient` | HTTP client for X API v2 |
| `BlocksterV2.Social.XConnection` | Stores user's X credentials |
| `BlocksterV2.Social.ShareCampaign` | Defines share-to-earn campaigns |
| `BlocksterV2.Social.ShareReward` | Tracks user participation (PostgreSQL) |
| `BlocksterV2.MnesiaInitializer` | Manages Mnesia `share_rewards` table |
| `BlocksterV2.EngagementTracker` | Reads from `user_post_rewards` Mnesia table |

---

## Database Schema

### x_connections

Stores user's X account connection and tokens.

| Column | Type | Description |
|--------|------|-------------|
| `id` | integer | Primary key |
| `user_id` | integer | Foreign key to users |
| `x_user_id` | string | X account ID |
| `x_username` | string | X handle (e.g., "blockster") |
| `x_name` | string | Display name |
| `x_profile_image_url` | string | Profile picture URL |
| `access_token_encrypted` | binary | Encrypted OAuth access token |
| `refresh_token_encrypted` | binary | Encrypted OAuth refresh token |
| `token_expires_at` | utc_datetime | When access token expires |
| `scopes` | array | Granted OAuth scopes |

**Security**: Tokens are encrypted at rest using `Cloak.Ecto.Binary`.

### x_oauth_states

Temporary storage for OAuth state during the authorization flow.

| Column | Type | Description |
|--------|------|-------------|
| `id` | integer | Primary key |
| `state` | string | Random state parameter |
| `code_verifier` | string | PKCE code verifier |
| `redirect_to` | string | Where to redirect after auth |
| `expires_at` | utc_datetime | State expiration (10 minutes) |

### share_campaigns

Defines retweet campaigns for posts.

| Column | Type | Description |
|--------|------|-------------|
| `id` | integer | Primary key |
| `post_id` | integer | Foreign key to posts |
| `tweet_id` | string | X tweet ID to retweet |
| `tweet_url` | string | Full tweet URL |
| `bux_reward` | integer | BUX reward amount (default: 50) |
| `is_active` | boolean | Whether campaign is active |
| `starts_at` | utc_datetime | Campaign start time (optional) |
| `ends_at` | utc_datetime | Campaign end time (optional) |
| `max_participants` | integer | Max participants (optional) |
| `total_shares` | integer | Count of successful shares |

### share_rewards

Tracks individual user participation in campaigns.

| Column | Type | Description |
|--------|------|-------------|
| `id` | integer | Primary key |
| `user_id` | integer | Foreign key to users |
| `campaign_id` | integer | Foreign key to share_campaigns |
| `x_connection_id` | integer | Foreign key to x_connections |
| `status` | string | `pending`, `verified`, `rewarded`, `failed` |
| `retweet_id` | string | ID of the created retweet |
| `bux_rewarded` | integer | BUX amount awarded |
| `failure_reason` | string | Error message if failed |
| `verified_at` | utc_datetime | When verified |
| `rewarded_at` | utc_datetime | When reward was minted |
| `tx_hash` | string | Blockchain transaction hash |

---

## Mnesia Integration

Share rewards are mirrored to Mnesia for fast distributed reads. This allows the member profile page to display user activity without hitting PostgreSQL.

### Mnesia Table: `share_rewards`

The `share_rewards` Mnesia table mirrors the PostgreSQL `share_rewards` table.

| Index | Attribute | Type | Description |
|-------|-----------|------|-------------|
| 0 | table_name | atom | `:share_rewards` |
| 1 | key | tuple | `{user_id, campaign_id}` primary key |
| 2 | id | integer | PostgreSQL id (for sync reference) |
| 3 | user_id | integer | User ID |
| 4 | campaign_id | integer | Campaign ID |
| 5 | x_connection_id | integer | X connection reference |
| 6 | retweet_id | string | X post/retweet ID |
| 7 | status | string | `pending`, `verified`, `rewarded`, `failed` |
| 8 | bux_rewarded | float | BUX amount (converted from Decimal) |
| 9 | verified_at | integer | Unix timestamp |
| 10 | rewarded_at | integer | Unix timestamp |
| 11 | failure_reason | string | Error message if failed |
| 12 | tx_hash | string | Blockchain transaction hash |
| 13 | created_at | integer | Unix timestamp |
| 14 | updated_at | integer | Unix timestamp |

**Indexes**: `user_id`, `campaign_id`, `status`, `rewarded_at`

### Automatic Sync

All PostgreSQL operations automatically sync to Mnesia:

```elixir
# These functions sync to Mnesia after PostgreSQL write:
Social.create_pending_reward(user_id, campaign_id, x_connection_id)
Social.verify_share_reward(reward, retweet_id)
Social.mark_rewarded(reward, bux_amount, tx_hash)
Social.mark_failed(reward, reason)
Social.delete_share_reward(reward)
```

### Manual Backfill

To sync all existing PostgreSQL records to Mnesia (e.g., after data recovery):

```elixir
BlocksterV2.Social.sync_all_share_rewards_to_mnesia()
# Returns: {:ok, %{total: 18, success: 18, errors: 0}}
```

### Reading from Mnesia

The member profile page reads share rewards directly from Mnesia:

```elixir
# Get all rewarded X shares for a user (from Mnesia)
Social.list_user_share_rewards(user_id)
# Returns:
# [
#   %{
#     type: :x_share,
#     label: "X Share",
#     amount: 50.0,
#     retweet_id: "1234567890",
#     timestamp: ~U[2025-12-13 20:00:00Z]
#   },
#   ...
# ]
```

### Member Activity Display

The member profile page combines data from two Mnesia tables:
1. `user_post_rewards` - Article read rewards
2. `share_rewards` - X share rewards

```elixir
# In MemberLive.Show
defp load_member_activities(user_id) do
  read_activities = EngagementTracker.get_all_user_post_rewards(user_id)
  share_activities = Social.list_user_share_rewards(user_id)

  (enrich_read_activities_with_post_info(read_activities) ++ share_activities)
  |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
end
```

### Activity Links

- **Article Read** activities link to the post: `/post-slug`
- **X Share** activities link to the tweet: `https://x.com/i/status/{retweet_id}`

---

## OAuth 2.0 Flow

### Step 1: Initiate Authorization

When user clicks "Connect X Account":

```elixir
# In XAuthController
def authorize(conn, _params) do
  # Generate PKCE parameters
  code_verifier = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
  code_challenge = :crypto.hash(:sha256, code_verifier) |> Base.url_encode64(padding: false)
  state = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)

  # Store state in database
  {:ok, _oauth_state} = Social.create_oauth_state(%{
    state: state,
    code_verifier: code_verifier,
    redirect_to: redirect_path
  })

  # Redirect to X authorization URL
  auth_url = XApiClient.authorize_url(state, code_challenge)
  redirect(conn, external: auth_url)
end
```

### Step 2: User Authorizes on X

User is redirected to X where they approve the following scopes:
- `tweet.read` - Read tweets
- `tweet.write` - Post and retweet
- `users.read` - Read user profile
- `like.write` - Like tweets
- `offline.access` - Get refresh tokens

### Step 3: Handle Callback

X redirects back with authorization code:

```elixir
# In XAuthController
def callback(conn, %{"code" => code, "state" => state}) do
  # Validate state
  oauth_state = Social.get_valid_oauth_state(state)

  # Exchange code for tokens
  {:ok, token_data} = XApiClient.exchange_code(code, oauth_state.code_verifier)

  # Get user profile from X
  {:ok, user_data} = XApiClient.get_me(token_data.access_token)

  # Store connection
  {:ok, _connection} = Social.upsert_x_connection(user_id, %{
    x_user_id: user_data["id"],
    x_username: user_data["username"],
    access_token: token_data.access_token,
    refresh_token: token_data.refresh_token,
    token_expires_at: expires_at
  })

  # Clean up OAuth state
  Social.consume_oauth_state(oauth_state)
end
```

### Token Refresh

Tokens are automatically refreshed when expired:

```elixir
# In Social context
def maybe_refresh_token(%XConnection{} = connection) do
  if XConnection.token_needs_refresh?(connection) do
    refresh_x_token(connection)
  else
    {:ok, connection}
  end
end

defp refresh_x_token(connection) do
  refresh_token = XConnection.decrypt_refresh_token(connection)

  case XApiClient.refresh_token(refresh_token) do
    {:ok, token_data} ->
      update_x_connection(connection, %{
        access_token: token_data.access_token,
        refresh_token: token_data.refresh_token,
        token_expires_at: new_expiry
      })
    {:error, reason} ->
      {:error, reason}
  end
end
```

---

## X API Client

### Location
`lib/blockster_v2/social/x_api_client.ex`

### Configuration

```elixir
# HTTP client options for resilience
defp req_options do
  [
    connect_options: [timeout: 30_000],    # 30 second connection timeout
    receive_timeout: 30_000,                # 30 second receive timeout
    retry: :transient,                      # Retry on transient errors
    retry_delay: fn attempt -> attempt * 500 end,  # Exponential backoff
    max_retries: 2                          # Up to 2 retries
  ]
end
```

### Key Functions

#### `create_retweet/3`
Creates a retweet of the specified tweet.

```elixir
def create_retweet(access_token, user_id, tweet_id) do
  url = "#{@api_base}/users/#{user_id}/retweets"

  opts = req_options()
  |> Keyword.merge(
    json: %{tweet_id: tweet_id},
    headers: [{"authorization", "Bearer #{access_token}"}]
  )

  case Req.post(url, opts) do
    {:ok, %Req.Response{status: 200, body: %{"data" => %{"retweeted" => true}}}} ->
      {:ok, %{retweeted: true}}
    # ... error handling
  end
end
```

#### `like_tweet/3`
Likes a tweet on behalf of the user.

```elixir
def like_tweet(access_token, user_id, tweet_id) do
  url = "#{@api_base}/users/#{user_id}/likes"
  # Similar implementation to create_retweet
end
```

#### `retweet_and_like/3`
Combines retweet and like in one operation.

```elixir
def retweet_and_like(access_token, user_id, tweet_id) do
  retweet_result = create_retweet(access_token, user_id, tweet_id)
  like_result = like_tweet(access_token, user_id, tweet_id)

  case {retweet_result, like_result} do
    {{:ok, _}, {:ok, _}} ->
      {:ok, %{retweeted: true, liked: true}}
    {{:ok, _}, {:error, like_error}} ->
      {:ok, %{retweeted: true, liked: false, like_error: like_error}}
    # ... other combinations
  end
end
```

---

## Share Campaigns

### Creating a Campaign

Campaigns can be created when editing a post via the admin form:

```elixir
# In PostLive.FormComponent
defp maybe_create_campaign(post, tweet_url) do
  # Extract tweet ID from URL
  case Regex.run(~r/(?:twitter\.com|x\.com)\/\w+\/status\/(\d+)/, tweet_url) do
    [_, tweet_id] ->
      Social.create_share_campaign(%{
        post_id: post.id,
        tweet_id: tweet_id,
        tweet_url: tweet_url,
        bux_reward: 50,
        is_active: true
      })
    _ ->
      :error
  end
end
```

### Campaign Display

The campaign box appears in the post sidebar when:
1. A campaign exists for the post
2. The campaign is active (`is_active: true`)
3. Current time is within `starts_at` and `ends_at` (if set)
4. Max participants not reached (if set)

```heex
<%= if @share_campaign && @share_campaign.is_active do %>
  <div class="campaign-box">
    <h4>RETWEET & LIKE ON X</h4>
    <span>+{@share_campaign.bux_reward} BUX</span>

    <%= if @share_reward do %>
      <!-- Already participated -->
      <span>Retweeted & Liked! Earned {@share_reward.bux_rewarded} BUX</span>
    <% else %>
      <button phx-click="open_share_modal">Retweet & Like</button>
    <% end %>
  </div>
<% end %>
```

---

## Retweet & Like Flow

### User Journey

1. **User views post** with active share campaign
2. **User clicks "Retweet & Like"** button
3. **Modal opens** showing tweet preview
4. **If not connected to X**: User clicks "Connect X Account"
5. **User clicks "Retweet & Like"** in modal
6. **System creates pending reward** record
7. **System calls X API** to retweet and like
8. **On success**:
   - Reward marked as verified/rewarded
   - BUX minted to user's wallet
   - Success message shown
9. **On failure**:
   - Pending reward deleted
   - Error message shown
   - User can retry

### LiveView Event Handler

```elixir
# In PostLive.Show
def handle_event("share_to_x", _params, socket) do
  user = socket.assigns.current_user
  x_connection = socket.assigns.x_connection
  share_campaign = socket.assigns.share_campaign

  # Check for existing successful reward
  if Social.get_successful_share_reward(user.id, share_campaign.id) do
    {:noreply, assign(socket, :share_status, {:error, "Already participated"})}
  else
    # Create pending reward
    {:ok, reward} = Social.create_pending_reward(
      user.id,
      share_campaign.id,
      x_connection.id
    )

    # Refresh token if needed
    case Social.maybe_refresh_token(x_connection) do
      {:ok, refreshed_connection} ->
        access_token = XConnection.decrypt_access_token(refreshed_connection)

        # Call X API
        case XApiClient.retweet_and_like(
          access_token,
          refreshed_connection.x_user_id,
          share_campaign.tweet_id
        ) do
          {:ok, result} when result.retweeted ->
            # Verify and award BUX
            {:ok, verified} = Social.verify_share_reward(reward, tweet_id)
            {:ok, final} = Social.mark_rewarded(verified, bux_amount)

            # Mint BUX
            BuxMinter.mint_bux(wallet, bux_amount, user.id, post.id)

            {:noreply, assign(socket, :share_reward, final)}

          {:error, reason} ->
            Social.delete_share_reward(reward)
            {:noreply, assign(socket, :share_status, {:error, reason})}
        end

      {:error, _} ->
        # Token refresh failed, disconnect account
        Social.delete_share_reward(reward)
        Social.disconnect_x_account(user.id)
        {:noreply, assign(socket, :needs_x_reconnect, true)}
    end
  end
end
```

### Reward Status Flow

```
┌─────────┐     ┌──────────┐     ┌──────────┐
│ pending │ ──> │ verified │ ──> │ rewarded │
└─────────┘     └──────────┘     └──────────┘
     │
     │ (on error)
     v
┌─────────┐
│ deleted │  (user can retry)
└─────────┘
```

---

## Error Handling

### Transport Errors

The X API client handles network errors gracefully:

```elixir
{:error, %Req.TransportError{reason: :closed}} ->
  Logger.error("X API connection closed - network issue")
  {:error, "Connection lost - please try again"}

{:error, %Req.TransportError{reason: :timeout}} ->
  Logger.error("X API connection timeout")
  {:error, "Request timed out - please try again"}

{:error, reason} ->
  Logger.error("X API network error: #{inspect(reason)}")
  {:error, "Network error - please try again"}
```

### API Errors

| Status | Meaning | User Message |
|--------|---------|--------------|
| 403 | Forbidden/Rate limited | "Forbidden - may be rate limited" |
| 429 | Rate limited | "Rate limited - please try again later" |
| Other | Various errors | "Retweet failed: {status}" |

### Retry Logic

The client automatically retries on transient errors:
- Connection closed
- Connection reset
- Timeout

Retry configuration:
- Max retries: 2
- Delay: 500ms, 1000ms (exponential backoff)
- Total max wait: ~31.5 seconds

### Token Refresh Errors

If token refresh fails:
1. Pending reward is deleted (allows retry)
2. X connection is disconnected
3. User sees "X session expired. Please reconnect your account."

---

## Configuration

### Environment Variables

```bash
# X API OAuth 2.0 credentials
X_CLIENT_ID=your_client_id
X_CLIENT_SECRET=your_client_secret

# Optional: Custom callback URL (defaults to endpoint URL)
X_CALLBACK_URL=https://yourapp.com/auth/x/callback
```

### Application Config

```elixir
# config/runtime.exs
config :blockster_v2, :x_api,
  client_id: System.get_env("X_CLIENT_ID"),
  client_secret: System.get_env("X_CLIENT_SECRET"),
  callback_url: System.get_env("X_CALLBACK_URL")
```

### X Developer Portal Setup

1. Create app at https://developer.twitter.com/
2. Enable OAuth 2.0 with PKCE
3. Set callback URL to `https://yourapp.com/auth/x/callback`
4. Enable required scopes:
   - `tweet.read`
   - `tweet.write`
   - `users.read`
   - `like.write`
   - `offline.access`

---

## Troubleshooting

### Common Issues

#### "Connection lost - please try again"
**Cause**: Network connection was closed during API call
**Solution**: Click retry button - the system will automatically retry up to 2 times

#### "X session expired. Please reconnect your account."
**Cause**: Refresh token is invalid or revoked
**Solution**: User must reconnect their X account

#### "Rate limited - please try again later"
**Cause**: Too many API calls to X
**Solution**: Wait a few minutes before retrying

#### Tweet preview not loading
**Cause**: Twitter widgets script not loaded
**Solution**: Check that `widgets.js` is loading from Twitter CDN

#### "Already participated"
**Cause**: User has a `verified` or `rewarded` status for this campaign
**Solution**: This is expected - user can only earn once per campaign

### Debugging

Enable debug logging:

```elixir
# In config/dev.exs
config :logger, level: :debug
```

Check X API responses in logs:
```
[error] X API retweet failed: 403 - %{"errors" => [...]}
```

### Database Queries

Check user's X connection:
```elixir
Social.get_x_connection_for_user(user_id)
```

Check campaign status:
```elixir
Social.get_campaign_for_post(post_id)
```

Check user's reward status:
```elixir
Social.get_successful_share_reward(user_id, campaign_id)
```

Get campaign statistics:
```elixir
Social.get_campaign_stats(campaign_id)
# Returns: %{total: 10, pending: 2, verified: 3, rewarded: 5, failed: 0, total_bux: 250}
```

---

## Security Considerations

1. **Token Encryption**: Access and refresh tokens are encrypted at rest using Cloak
2. **PKCE**: OAuth flow uses PKCE to prevent authorization code interception
3. **State Parameter**: Random state prevents CSRF attacks
4. **Short-lived States**: OAuth states expire after 10 minutes
5. **Scope Limitation**: Only request necessary scopes

---

## Future Improvements

1. **Webhook verification**: Use X webhooks to verify retweets instead of trusting API response
2. **Rate limit tracking**: Track API rate limits to prevent hitting limits
3. **Campaign analytics**: Dashboard for campaign performance metrics
4. **Scheduled campaigns**: Auto-activate campaigns at scheduled times
5. **Multiple tweets**: Support campaigns with multiple tweets to share
