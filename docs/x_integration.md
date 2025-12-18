# X (Twitter) Integration Documentation

This document provides a comprehensive guide to the X (Twitter) integration in Blockster V2, covering OAuth authentication, share campaigns, and the retweet & like reward system.

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Database Schema](#database-schema)
4. [Mnesia Integration](#mnesia-integration)
5. [OAuth 2.0 Flow](#oauth-20-flow)
6. [X Account Locking](#x-account-locking)
7. [X Account Quality Score](#x-account-quality-score)
8. [X API Client](#x-api-client)
9. [Share Campaigns](#share-campaigns)
10. [Retweet & Like Flow](#retweet--like-flow)
11. [Error Handling](#error-handling)
12. [Configuration](#configuration)
13. [Troubleshooting](#troubleshooting)

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
- **X Account Quality Score**: Automatic scoring (1-100) based on account metrics, used as `x_multiplier` for personalized BUX rewards

---

## Architecture

### File Structure

```
lib/blockster_v2/
├── social/
│   ├── x_api_client.ex      # X API v2 HTTP client
│   ├── x_connection.ex      # User's X account connection schema
│   ├── x_oauth_state.ex     # OAuth state management schema
│   ├── x_score_calculator.ex # X account quality score calculator
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
| `BlocksterV2.Social.XConnection` | Stores user's X credentials and score |
| `BlocksterV2.Social.XScoreCalculator` | Calculates X account quality score (1-100) |
| `BlocksterV2.Social.ShareCampaign` | Defines share-to-earn campaigns |
| `BlocksterV2.Social.ShareReward` | Tracks user participation (PostgreSQL) |
| `BlocksterV2.MnesiaInitializer` | Manages Mnesia `share_rewards` table |
| `BlocksterV2.EngagementTracker` | Manages `user_multipliers` Mnesia table (includes x_multiplier) |

---

## Database Schema

All X integration data is stored exclusively in **Mnesia** for fast, distributed access. PostgreSQL is only used for the `users.locked_x_user_id` field (permanent X account locking).

**Important:** The retweet flow uses Mnesia only. No PostgreSQL queries occur during the retweet action itself - user and post data are already loaded in the LiveView socket from page mount.

### Mnesia Table: `x_oauth_states`

Temporary storage for OAuth state during the authorization flow (10 minute TTL).

| Field | Type | Description |
|-------|------|-------------|
| `state` | string | **Primary key** - Random state parameter |
| `user_id` | integer | User initiating OAuth |
| `code_verifier` | string | PKCE code verifier |
| `redirect_path` | string | Where to redirect after auth |
| `created_at` | integer | Unix timestamp |
| `expires_at` | integer | Unix timestamp (10 min from creation) |

### Mnesia Table: `x_connections`

Stores user's X account connection and tokens.

| Field | Type | Description |
|-------|------|-------------|
| `user_id` | integer | **Primary key** - Blockster user ID |
| `x_user_id` | string | X account ID |
| `x_username` | string | X handle (e.g., "blockster") |
| `x_name` | string | Display name |
| `x_profile_image_url` | string | Profile picture URL |
| `access_token` | string | Decrypted OAuth access token |
| `refresh_token` | string | Decrypted OAuth refresh token |
| `token_expires_at` | DateTime | When access token expires |
| `scopes` | list | Granted OAuth scopes |
| `connected_at` | DateTime | When first connected |
| `x_score` | integer | Account quality score (1-100) |
| `followers_count` | integer | Number of followers |
| `following_count` | integer | Number following |
| `tweet_count` | integer | Total tweet count |
| `listed_count` | integer | Number of lists user is on |
| `avg_engagement_rate` | float | Average engagement rate on original tweets |
| `original_tweets_analyzed` | integer | Number of tweets analyzed for score |
| `account_created_at` | DateTime | When X account was created |
| `score_calculated_at` | DateTime | When score was last calculated |

**Score Refresh**: The `x_score` is recalculated every 7 days or on first connect.

### Mnesia Table: `share_campaigns`

Defines retweet campaigns for posts (one campaign per post).

| Field | Type | Description |
|-------|------|-------------|
| `post_id` | integer | **Primary key** - Foreign key to posts |
| `tweet_id` | string | X tweet ID to retweet |
| `tweet_url` | string | Full tweet URL |
| `tweet_text` | string | Custom tweet text (optional) |
| `bux_reward` | Decimal | BUX reward amount |
| `is_active` | boolean | Whether campaign is active |
| `starts_at` | DateTime | Campaign start time (optional) |
| `ends_at` | DateTime | Campaign end time (optional) |
| `max_participants` | integer | Max participants (optional) |
| `total_shares` | integer | Count of successful shares |
| `inserted_at` | DateTime | When campaign was created |
| `updated_at` | DateTime | Last update time |

### Mnesia Table: `share_rewards`

Tracks individual user participation in campaigns.

| Field | Type | Description |
|-------|------|-------------|
| `key` | tuple | **Primary key** - `{user_id, campaign_id}` |
| `user_id` | integer | User ID |
| `campaign_id` | integer | Campaign ID (post_id) |
| `x_connection_id` | integer | X connection reference |
| `retweet_id` | string | ID of the created retweet |
| `status` | string | `pending`, `verified`, `rewarded`, `failed` |
| `bux_rewarded` | float | BUX amount awarded |
| `verified_at` | DateTime | When verified |
| `rewarded_at` | DateTime | When reward was minted |
| `failure_reason` | string | Error message if failed |
| `tx_hash` | string | Blockchain transaction hash |
| `created_at` | DateTime | When reward was created |
| `updated_at` | DateTime | Last update time |

**Indexes**: `user_id`, `campaign_id`, `status`, `rewarded_at`

### PostgreSQL: `users.locked_x_user_id`

The only PostgreSQL field used for X integration. When a user first connects their X account, their `locked_x_user_id` is set permanently to prevent switching accounts.

| Column | Type | Description |
|--------|------|-------------|
| `locked_x_user_id` | string | X account ID user is locked to |

The column has a unique partial index (`WHERE locked_x_user_id IS NOT NULL`) to prevent the same X account from being locked to multiple users.

---

## Data Access Patterns

### Writing to Mnesia

All X data operations go through the `Social` context which calls `EngagementTracker` Mnesia functions:

```elixir
# OAuth state management
Social.create_oauth_state(user_id, code_verifier, redirect_path)
Social.get_valid_oauth_state(state)
Social.consume_oauth_state(state)

# X connection management
Social.upsert_x_connection(user_id, attrs)
Social.get_x_connection_for_user(user_id)
Social.disconnect_x_account(user_id)
Social.maybe_refresh_token(connection)

# Share campaign management
Social.create_share_campaign(attrs)
Social.get_share_campaign(post_id)
Social.list_active_campaigns()

# Share reward management
Social.create_pending_reward(user_id, campaign_id, x_connection_id)
Social.verify_share_reward(user_id, campaign_id, retweet_id)
Social.mark_rewarded(user_id, campaign_id, bux_amount, opts)
Social.mark_failed(user_id, campaign_id, reason)
Social.delete_share_reward(user_id, campaign_id)
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

  # Store state in Mnesia (10 minute TTL)
  {:ok, _state} = Social.create_oauth_state(user_id, code_verifier, redirect_path)

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
  # Validate state from Mnesia
  oauth_state = Social.get_valid_oauth_state(state)

  # Exchange code for tokens
  {:ok, token_data} = XApiClient.exchange_code(code, oauth_state.code_verifier)

  # Get user profile from X
  {:ok, user_data} = XApiClient.get_me(token_data.access_token)

  # Store connection in Mnesia (also locks user to X account in PostgreSQL on first connect)
  {:ok, _connection} = Social.upsert_x_connection(user_id, %{
    x_user_id: user_data["id"],
    x_username: user_data["username"],
    access_token: token_data.access_token,
    refresh_token: token_data.refresh_token,
    token_expires_at: expires_at
  })

  # Clean up OAuth state from Mnesia
  Social.consume_oauth_state(oauth_state)

  # Calculate X score asynchronously (doesn't block redirect)
  maybe_calculate_x_score_async(connection, token_data.access_token)
end
```

### Token Refresh

Tokens are automatically refreshed when expired. Token data is stored in and updated via Mnesia:

```elixir
# In Social context
def maybe_refresh_token(connection) when is_map(connection) do
  if token_needs_refresh?(connection) do
    refresh_x_token(connection)
  else
    {:ok, connection}
  end
end

defp refresh_x_token(connection) do
  refresh_token = Map.get(connection, :refresh_token)

  case XApiClient.refresh_token(refresh_token) do
    {:ok, token_data} ->
      # Update tokens in Mnesia
      EngagementTracker.update_x_connection_tokens(
        connection.user_id,
        token_data.access_token,
        token_data.refresh_token,
        expires_at
      )
    {:error, reason} ->
      {:error, reason}
  end
end
```

---

## X Account Locking

Users are permanently locked to the first X account they connect. This prevents users from switching to higher-score X accounts to game the `x_multiplier` reward system.

### How It Works

1. **First connection**: When a user connects their X account for the first time, the `x_user_id` is stored in PostgreSQL `users.locked_x_user_id`
2. **Subsequent connections**: Any reconnection must use the same X account
3. **Disconnect**: Users can disconnect their X account (Mnesia), but the PostgreSQL lock persists
4. **Lock check**: On OAuth callback, the system verifies the X account matches the locked ID

### Database Split

- **PostgreSQL**: `users.locked_x_user_id` - permanent lock (survives Mnesia data loss)
- **Mnesia**: `x_connections` - active connection data (can be recreated)

The PostgreSQL column has a unique partial index (`WHERE locked_x_user_id IS NOT NULL`) to prevent the same X account from being locked to multiple users.

### Implementation

```elixir
# In Social.upsert_x_connection/2
def upsert_x_connection(user_id, attrs) do
  x_user_id = attrs[:x_user_id] || attrs["x_user_id"]
  user = Repo.get!(User, user_id)  # Only PostgreSQL query in the flow

  case check_x_account_lock(user, x_user_id) do
    {:ok, :first_connection} ->
      # First X connection - lock user in PostgreSQL, create connection in Mnesia
      with {:ok, _user} <- lock_user_to_x_account(user, x_user_id),
           {:ok, connection} <- EngagementTracker.upsert_x_connection(user_id, attrs) do
        {:ok, connection}
      end

    {:ok, :same_account} ->
      # Reconnecting same X account - update Mnesia only
      EngagementTracker.upsert_x_connection(user_id, attrs)

    {:error, :x_account_locked} ->
      # Trying to connect a different X account
      {:error, :x_account_locked}
  end
end
```

### Error Message

When a user tries to connect a different X account:

> "Your account is locked to a different X account. You can only connect the X account you originally linked."

---

## X Account Quality Score

When a user connects their X account, the system calculates a quality score (1-100) based on their account metrics. This score becomes their `x_multiplier` which determines personalized BUX rewards for X share campaigns.

### Score Components

The score is calculated from 6 weighted components totaling 100 points:

| Component | Max Points | Criteria |
|-----------|------------|----------|
| **Follower Quality** | 25 | Followers/following ratio (10:1+ = max) |
| **Engagement Rate** | 35 | Split: 17.5 for rate (scales by follower tier), 17.5 for volume (200+ avg engagements = max) |
| **Account Age** | 10 | Years since account created (5+ years = max) |
| **Activity Level** | 15 | Tweets per month (30+ tweets/month = max) |
| **List Presence** | 5 | Number of public lists (50+ = max) |
| **Follower Scale** | 10 | Total followers (10M+ = max, logarithmic). Under 1k gets ~0-1 point. |

### Follower Scale Scoring

The follower scale uses a logarithmic curve with a 1k follower threshold:

| Followers | Points |
|-----------|--------|
| 717 | 0.7 |
| 1,000 | 0 |
| 10,000 | 2.5 |
| 83,000 | 4.8 |
| 100,000 | 5 |
| 1,000,000 | 7.5 |
| 10,000,000 | 10 (max) |

### Calculation Trigger

Score is calculated:
1. **First connect**: When user first connects their X account
2. **Every 7 days**: If `score_calculated_at` is older than 7 days

```elixir
# In XScoreCalculator
def needs_score_calculation?(%XConnection{score_calculated_at: nil}), do: true
def needs_score_calculation?(%XConnection{score_calculated_at: calculated_at}) do
  days_since = DateTime.diff(DateTime.utc_now(), calculated_at, :day)
  days_since >= 7
end
```

### Async Calculation

Score calculation runs asynchronously after OAuth callback to avoid blocking the redirect:

```elixir
# In XAuthController
defp maybe_calculate_x_score_async(connection, access_token) do
  if XScoreCalculator.needs_score_calculation?(connection) do
    Task.start(fn ->
      XScoreCalculator.calculate_and_save_score(connection, access_token)
    end)
  end
end
```

### API Calls for Score Data

The score calculation fetches:
1. **User metrics**: `GET /users/{id}?user.fields=public_metrics,created_at`
2. **Recent tweets**: `GET /users/{id}/tweets?exclude=retweets&tweet.fields=public_metrics`

Only **original tweets** are analyzed (retweets are excluded) to ensure engagement metrics reflect the user's own content.

### Engagement Rate Calculation

```elixir
# For each original tweet:
engagement = likes + retweets + replies + quotes
avg_engagement_per_tweet = total_engagement / tweet_count
engagement_rate = avg_engagement_per_tweet / followers_count
```

### Score Storage

The score is saved to two Mnesia tables:
1. **Mnesia**: `x_connections.x_score` - stored with the connection data
2. **Mnesia**: `user_multipliers` table as `x_multiplier` - used for fast reward calculations

```elixir
# Update x_multiplier in Mnesia
EngagementTracker.set_user_x_multiplier(user_id, score)
```

### Personalized Rewards

The `x_multiplier` (score 1-100) is used to calculate personalized BUX rewards:

```elixir
# In PostLive.Show
x_multiplier = EngagementTracker.get_user_x_multiplier(user_id)
x_share_reward = round(x_multiplier * base_bux_reward)
```

For example:
- Base BUX reward: 1 BUX
- User's X score: 33
- Personalized reward: 33 BUX

### Example Score Breakdown

```
[info] [XScoreCalculator] Score breakdown:
  follower_quality=25,
  engagement=0,
  age=3,
  activity=1,
  list=0,
  scale=5,
  total=33
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

#### `get_user_with_metrics/2`
Gets user profile with public metrics for score calculation.

```elixir
def get_user_with_metrics(access_token, user_id) do
  url = "#{@api_base}/users/#{user_id}?user.fields=public_metrics,created_at,profile_image_url,name,username"
  # Returns: {:ok, %{"id" => ..., "public_metrics" => %{"followers_count" => ..., ...}}}
end
```

#### `get_user_tweets_with_metrics/3`
Gets user's recent original tweets (excludes retweets) with engagement metrics.

```elixir
def get_user_tweets_with_metrics(access_token, user_id, max_results \\ 50) do
  url = "#{@api_base}/users/#{user_id}/tweets?max_results=#{max_results}&tweet.fields=public_metrics,referenced_tweets,created_at&exclude=retweets"
  # Filters out any tweets with referenced_tweets type "retweeted"
  # Returns: {:ok, [%{"id" => ..., "public_metrics" => %{"like_count" => ..., ...}}]}
end
```

#### `fetch_score_data/2`
Convenience function that fetches all data needed for score calculation.

```elixir
def fetch_score_data(access_token, user_id) do
  with {:ok, user_data} <- get_user_with_metrics(access_token, user_id),
       {:ok, tweets} <- get_user_tweets_with_metrics(access_token, user_id, 100) do
    {:ok, %{user: user_data, tweets: tweets}}
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

### Mnesia Queries

Check user's X connection (from Mnesia):
```elixir
Social.get_x_connection_for_user(user_id)
# Or directly from EngagementTracker:
EngagementTracker.get_x_connection_by_user(user_id)
```

Check campaign status (from Mnesia):
```elixir
Social.get_campaign_for_post(post_id)
# Or:
EngagementTracker.get_share_campaign(post_id)
```

Check user's reward status (from Mnesia):
```elixir
Social.get_successful_share_reward(user_id, campaign_id)
# Or:
EngagementTracker.get_share_reward(user_id, campaign_id)
```

Get campaign statistics (from Mnesia):
```elixir
Social.get_campaign_stats(campaign_id)
# Returns: %{total: 10, pending: 2, verified: 3, rewarded: 5, failed: 0, total_bux: 250}
```

List all share campaigns:
```elixir
Social.list_share_campaigns()
Social.list_active_campaigns()
```

---

## Security Considerations

1. **Token Storage**: Access and refresh tokens are stored in Mnesia (in-memory, replicated across cluster)
2. **PKCE**: OAuth flow uses PKCE to prevent authorization code interception
3. **State Parameter**: Random state prevents CSRF attacks
4. **Short-lived States**: OAuth states expire after 10 minutes (auto-cleaned from Mnesia)
5. **Scope Limitation**: Only request necessary scopes
6. **Account Locking**: Permanent X account lock in PostgreSQL prevents reward gaming

---

## Future Improvements

1. **Webhook verification**: Use X webhooks to verify retweets instead of trusting API response
2. **Rate limit tracking**: Track API rate limits to prevent hitting limits
3. **Campaign analytics**: Dashboard for campaign performance metrics
4. **Scheduled campaigns**: Auto-activate campaigns at scheduled times
5. **Multiple tweets**: Support campaigns with multiple tweets to share
