# Blockster Rewards System

A comprehensive guide to the multi-token BUX rewards system that rewards users for reading articles and sharing on social media.

## Table of Contents

1. [Overview](#overview)
2. [Token Types](#token-types)
3. [Architecture](#architecture)
4. [Read Rewards Flow](#read-rewards-flow)
5. [Share Rewards Flow](#share-rewards-flow)
6. [BUX Minter Service](#bux-minter-service)
7. [Database Storage](#database-storage)
8. [Hub Token Configuration](#hub-token-configuration)
9. [API Reference](#api-reference)
10. [Environment Configuration](#environment-configuration)

---

## Overview

The Blockster rewards system incentivizes user engagement through token rewards. Users earn tokens by:

1. **Reading articles** - Engagement score based on time spent, scroll depth, and completion
2. **Sharing on X (Twitter)** - Retweeting and liking campaign tweets

Each hub can configure its own token, allowing for branded reward experiences. Posts without a hub (or hubs without a configured token) default to the standard **BUX** token.

---

## Token Types

The system supports 11 different token types, each deployed on the Rogue Chain:

| Token | Contract Address | Owner Wallet |
|-------|------------------|--------------|
| BUX | `0xbe46C2A9C729768aE938bc62eaC51C7Ad560F18d` | `0x2dDC1caA8e63B091D353b8E3E7e3Eeb6008DC7Cd` |
| moonBUX | `0x08F12025c1cFC4813F21c2325b124F6B6b5cfDF5` | `0x198C14bAa29c8a01d6b08A08a9c32b61F1Aa011F` |
| neoBUX | `0x423656448374003C2cfEaFF88D5F64fb3A76487C` | `0xDBAe86548451Bb1aDCC8dec3711888C20f70a0d2` |
| rogueBUX | `0x56d271b1C1DCF597aA3ee454bCCb265d4Dee47b3` | `0x8DbeD9fcF5e0BD80CA512634D9f8a2Fe9605bD3e` |
| flareBUX | `0xd27EcA9bc2401E8CEf92a14F5Ee9847508EDdaC8` | `0x7f2b766D73f4A1d5930AFb3C4eB19a1d5c07F426` |
| nftBUX | `0x9853e3Abea96985d55E9c6963afbAf1B0C9e49ED` | `0xE9432533e06fa3f61A9d85E31B451B3094702B72` |
| nolchaBUX | `0x4cE5C87FAbE273B58cb4Ef913aDEa5eE15AFb642` | `0xB6e8cFFBd667C5139C53E18d48F83891c0beF531` |
| solBUX | `0x92434779E281468611237d18AdE20A4f7F29DB38` | `0x1dd957dD4B8F299a087665A72986Ed50cCE5a489` |
| spaceBUX | `0xAcaCa77FbC674728088f41f6d978F0194cf3d55A` | `0x9409B1A555862c5B399B355744829E5187db9354` |
| tronBUX | `0x98eDb381281FA02b494FEd76f0D9F3AEFb2Db665` | `0x95e5364787574021fD9Ea44eEd90b30dF5bB5e78` |
| tranBUX | `0xcDdE88C8bacB37Fc669fa6DECE92E3d8FE672d96` | `0x16E02A25FDfab050Fd3D7E1FB6cB39B61b6CB4A4` |

All tokens are ERC-20 compliant with 18 decimals and use the same ABI:

```solidity
function mint(address to, uint256 amount) external
function balanceOf(address account) external view returns (uint256)
function decimals() external view returns (uint8)
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        FRONTEND                                  │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  engagement_tracker.js                                   │   │
│  │  - Tracks time spent, scroll depth, focus changes        │   │
│  │  - Sends events: article-visited, engagement-update,     │   │
│  │    article-read                                          │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    PHOENIX LIVEVIEW                              │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  post_live/show.ex                                       │   │
│  │  - Handles engagement events                              │   │
│  │  - Determines hub token from post.hub.token               │   │
│  │  - Calls BuxMinter.mint_bux() with token parameter        │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  engagement_tracker.ex                                    │   │
│  │  - Calculates engagement scores                           │   │
│  │  - Records rewards in Mnesia tables                       │   │
│  │  - Updates per-token balances                             │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  bux_minter.ex                                            │   │
│  │  - HTTP client for BUX Minter service                     │   │
│  │  - Handles token normalization and validation             │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    BUX MINTER SERVICE                            │
│                    (Node.js / Express)                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  index.js                                                 │   │
│  │  - POST /mint - Mint tokens                               │   │
│  │  - GET /balance/:address - Get single token balance       │   │
│  │  - GET /balances/:address - Get all token balances        │   │
│  │  - Uses ethers.js to interact with Rogue Chain            │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ROGUE CHAIN                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Token Contracts (ERC-20)                                 │   │
│  │  - BUX, moonBUX, neoBUX, rogueBUX, flareBUX              │   │
│  │  - nftBUX, nolchaBUX, solBUX, spaceBUX, tronBUX, tranBUX │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Read Rewards Flow

### 1. Frontend Engagement Tracking

**File:** `assets/js/engagement_tracker.js`

The JavaScript hook tracks user behavior while reading:

| Metric | Description |
|--------|-------------|
| `time_spent` | Total seconds on page (pauses when tab loses focus) |
| `scroll_depth` | Percentage of article scrolled (0-100%) |
| `reached_end` | Boolean when user scrolls to article end marker |
| `scroll_events` | Count of scroll events |
| `avg_scroll_speed` | Average pixels scrolled per second |
| `scroll_reversals` | Times user scrolled back up |
| `focus_changes` | Tab visibility changes |
| `min_read_time` | Minimum time based on word count (words / 10, min 5s) |

**Events sent to server:**

1. `article-visited` - On page load with `min_read_time`
2. `engagement-update` - Every 2 seconds with current metrics
3. `article-read` - When user reaches end marker

### 2. Engagement Score Calculation

**File:** `lib/blockster_v2/engagement_tracker.ex`

Score formula (1-10 range):

```
base_score = 1

time_score (0-6 points):
  - >= 100% of min_read_time: 6 points
  - >= 90%: 5 points
  - >= 80%: 4 points
  - >= 70%: 3 points
  - >= 50%: 2 points
  - >= 30%: 1 point
  - < 30%: 0 points

depth_score (0-3 points):
  - >= 100% or reached_end: 3 points
  - >= 66%: 2 points
  - >= 33%: 1 point
  - < 33%: 0 points

engagement_score = min(max(base + time + depth, 1), 10)
```

### 3. BUX Reward Calculation

```
bux_earned = (engagement_score / 10) × base_bux_reward × user_multiplier
```

Where:
- `engagement_score`: 1-10 from engagement tracker
- `base_bux_reward`: Post-level reward (default: 1)
- `user_multiplier`: User-specific multiplier (default: 1.0)

### 4. Token Selection

**File:** `lib/blockster_v2_web/live/post_live/show.ex`

```elixir
# Get token from hub if available, otherwise default to "BUX"
defp get_hub_token(%{hub: %{token: token}}) when is_binary(token) and token != "", do: token
defp get_hub_token(_), do: "BUX"
```

### 5. Minting Process

```elixir
# Async mint with callback for tx_hash
Task.start(fn ->
  case BuxMinter.mint_bux(wallet, bux_earned, user_id, post_id, :read, hub_token) do
    {:ok, %{"transactionHash" => tx_hash}} ->
      send(lv_pid, {:mint_completed, tx_hash})
    _ ->
      :ok
  end
end)
```

---

## Share Rewards Flow

### 1. X Connection

Users must connect their X (Twitter) account via OAuth to participate in share campaigns.

**Mnesia Table:** `x_connections` (keyed by `user_id`)
- `user_id` - Primary key, Blockster user ID
- `x_user_id` - X user ID (for account locking)
- `x_username` - X username
- `access_token_encrypted` - Encrypted OAuth access token
- `refresh_token_encrypted` - Encrypted refresh token
- `token_expires_at` - Token expiration timestamp (Unix)
- `x_score` - Account quality score (1-100)

**Note:** The `locked_x_user_id` field remains in PostgreSQL `users` table for permanent account locking.

### 2. Share Campaigns

Each post can have an associated share campaign with a specific tweet to retweet.

**Mnesia Table:** `share_campaigns` (keyed by `post_id`)
- `post_id` - Primary key (one campaign per post)
- `tweet_id` - The specific tweet to retweet
- `tweet_url` - URL to the tweet
- `bux_reward` - Fixed BUX amount for completion
- `is_active` - Enable/disable campaign

### 3. Share Reward Flow

1. User clicks "Retweet & Like" button
2. System validates:
   - User logged in
   - X account connected
   - Campaign active
   - User hasn't already participated
3. Creates pending reward in **Mnesia**
4. Calls X API to retweet and like
5. Verifies retweet success
6. Calculates reward: `x_multiplier × base_bux_reward`
7. Mints tokens with hub-specific token type
8. Updates reward status to "rewarded" in **Mnesia**

**Important:** The entire retweet flow uses Mnesia only. No PostgreSQL queries are made during the retweet action itself. User and post data are already loaded in the LiveView socket from page mount.

### 4. Reward Calculation

```
x_share_reward = x_multiplier × base_bux_reward
```

Where:
- `x_multiplier`: User's X-specific multiplier (from `user_multipliers` table)
- `base_bux_reward`: Post's base reward value

---

## BUX Minter Service

### Overview

A Node.js microservice deployed at `https://bux-minter.fly.dev` that handles blockchain token minting.

**File:** `bux-minter/index.js`

### Authentication

All endpoints (except `/health`) require Bearer token authentication:

```
Authorization: Bearer {API_SECRET}
```

### Endpoints

#### POST /mint

Mint tokens to a user's wallet.

**Request:**
```json
{
  "walletAddress": "0x...",
  "amount": 10,
  "userId": 123,
  "postId": 456,
  "token": "moonBUX"  // optional, defaults to "BUX"
}
```

**Response:**
```json
{
  "success": true,
  "transactionHash": "0x...",
  "blockNumber": 12345,
  "walletAddress": "0x...",
  "amountMinted": 10,
  "token": "moonBUX",
  "newBalance": "50.0",
  "userId": 123,
  "postId": 456
}
```

#### GET /balance/:address

Get balance for a specific token.

**Query Parameters:**
- `token` (optional): Token name, defaults to "BUX"

**Response:**
```json
{
  "address": "0x...",
  "token": "moonBUX",
  "balance": "50.0",
  "balanceWei": "50000000000000000000"
}
```

#### GET /balances/:address

Get all token balances for an address.

**Response:**
```json
{
  "address": "0x...",
  "balances": {
    "BUX": "100.0",
    "moonBUX": "50.0",
    "neoBUX": "25.0",
    "rogueBUX": "0.0",
    ...
  }
}
```

### Token Selection Logic

```javascript
function getContractForToken(token) {
  const tokenName = token || 'BUX';

  // Use configured contract if available
  if (tokenContracts[tokenName]) {
    return {
      contract: tokenContracts[tokenName],
      wallet: tokenWallets[tokenName],
      token: tokenName
    };
  }

  // Fallback to BUX
  console.log(`[WARN] No private key for ${tokenName}, falling back to BUX`);
  return { contract: buxContract, wallet: wallet, token: 'BUX' };
}
```

---

## Database Storage

### Mnesia Tables (Primary Storage)

All X share-related data is stored exclusively in Mnesia for fast, distributed access. PostgreSQL is only used for the `locked_x_user_id` field on the `users` table (for permanent X account locking).

#### x_oauth_states (Mnesia)
Temporary storage for OAuth state during authorization flow.
```
Key: state (random string)
- user_id: integer
- code_verifier: PKCE code verifier
- redirect_path: where to redirect after auth
- created_at: Unix timestamp
- expires_at: Unix timestamp (10 minutes TTL)
```

#### x_connections (Mnesia)
Stores user's X account connection and encrypted tokens.
```
Key: user_id
- x_user_id: X account ID
- x_username: X handle
- x_name: display name
- x_profile_image_url: profile picture URL
- access_token: OAuth access token (decrypted)
- refresh_token: OAuth refresh token (decrypted)
- token_expires_at: DateTime when token expires
- scopes: list of granted OAuth scopes
- connected_at: DateTime when connected
- x_score: account quality score (1-100)
- followers_count, following_count, tweet_count, listed_count
- avg_engagement_rate: float
- original_tweets_analyzed: integer
- account_created_at: DateTime
- score_calculated_at: DateTime
```

#### share_campaigns (Mnesia)
Defines retweet campaigns for posts.
```
Key: post_id (one campaign per post)
- tweet_id: X tweet ID to retweet
- tweet_url: full tweet URL
- tweet_text: custom tweet text (optional)
- bux_reward: Decimal reward amount
- is_active: boolean
- starts_at: DateTime (optional)
- ends_at: DateTime (optional)
- max_participants: integer (optional)
- total_shares: integer count of successful shares
- inserted_at: DateTime
- updated_at: DateTime
```

#### share_rewards (Mnesia)
Tracks individual user participation in campaigns.
```
Key: {user_id, campaign_id} tuple
- x_connection_id: reference to x_connection
- retweet_id: ID of the created retweet
- status: "pending" | "verified" | "rewarded" | "failed"
- bux_rewarded: float amount awarded
- verified_at: DateTime
- rewarded_at: DateTime
- failure_reason: error message if failed
- tx_hash: blockchain transaction hash
- created_at: DateTime
- updated_at: DateTime
```

### PostgreSQL (Limited Use)

Only the `users.locked_x_user_id` field is stored in PostgreSQL for permanent X account locking. This ensures users cannot switch X accounts to game rewards.

### Other Mnesia Tables

Real-time reward data for engagement tracking:

#### user_post_engagement
```
{key, user_id, post_id, time_spent, min_read_time, scroll_depth,
 reached_end, scroll_events, avg_scroll_speed, max_scroll_speed,
 scroll_reversals, focus_changes, engagement_score, is_read,
 created_at, updated_at}
```

#### user_post_rewards
```
{key, user_id, post_id, read_bux, read_paid, read_tx_id,
 x_share_bux, x_share_paid, x_share_tx_id,
 linkedin_share_bux, linkedin_share_paid, linkedin_share_tx_id,
 total_bux, total_paid_bux, created_at, updated_at}
```

#### user_bux_balances
Tracks per-token balances for each user:

```
{user_id, user_smart_wallet, updated_at, aggregate_bux_balance,
 bux_balance, moonbux_balance, neobux_balance, roguebux_balance,
 flarebux_balance, nftbux_balance, nolchabux_balance, solbux_balance,
 spacebux_balance, tronbux_balance, tranbux_balance}
```

**IMPORTANT**: `aggregate_bux_balance` is the sum of ALL BUX-flavored tokens (indices 5-15) ONLY. ROGUE is stored separately in `user_rogue_balances` and is NOT included in the aggregate.

**Aggregate Calculation**:
```elixir
# Sum indices 5-15: BUX, moonBUX, neoBUX, rogueBUX, flareBUX,
# nftBUX, nolchaBUX, solBUX, spaceBUX, tronBUX, tranBUX
aggregate = Enum.reduce(5..15, 0.0, fn index, acc ->
  acc + (elem(record, index) || 0.0)
end)
```

**Why ROGUE is Excluded**:
- ROGUE is the native gas token of Rogue Chain (like ETH on Ethereum)
- ROGUE is not an ERC-20 token - no contract address
- ROGUE represents chain-level assets, not BUX economy tokens
- Aggregate represents BUX-flavored token economy only

#### user_multipliers
```
{user_id, smart_wallet, x_multiplier, linkedin_multiplier,
 personal_multiplier, rogue_multiplier, overall_multiplier,
 extras, created_at, updated_at}
```

---

## Hub Token Configuration

### Setting Up a Hub Token

1. Create/edit a hub in the admin panel
2. Set the `token` field to one of the valid token names:
   - `BUX`, `moonBUX`, `neoBUX`, `rogueBUX`, `flareBUX`
   - `nftBUX`, `nolchaBUX`, `solBUX`, `spaceBUX`, `tronBUX`, `tranBUX`
3. Optionally set a hub `logo` for display in the rewards panel

### UI Display

When a post has a hub with a configured token:

1. **Earning Panel** - Shows hub logo (if set) and token name
2. **Share Campaign Box** - Shows token name in reward badge
3. **Share Modal** - Header and buttons display token name
4. **Success Messages** - Include the specific token name

If no hub token is configured, "BUX" is displayed everywhere.

---

## API Reference

### Elixir Functions

#### BuxMinter

```elixir
# Mint tokens (sync)
BuxMinter.mint_bux(wallet_address, amount, user_id, post_id, :read, "moonBUX")
BuxMinter.mint_bux(wallet_address, amount, user_id, post_id, :x_share, "moonBUX")

# Mint tokens (async)
BuxMinter.mint_bux_async(wallet_address, amount, user_id, post_id, :read, "moonBUX")

# Get balance for specific token
BuxMinter.get_balance(wallet_address, "moonBUX")

# Get all token balances
BuxMinter.get_all_balances(wallet_address)

# List valid tokens
BuxMinter.valid_tokens()
# => ["BUX", "moonBUX", "neoBUX", "rogueBUX", "flareBUX",
#     "nftBUX", "nolchaBUX", "solBUX", "spaceBUX", "tronBUX", "tranBUX"]
```

#### EngagementTracker

```elixir
# Update per-token balance
EngagementTracker.update_user_token_balance(user_id, wallet, "moonBUX", "100.5")

# Get all token balances for user
EngagementTracker.get_user_token_balances(user_id)
# => %{"aggregate" => 150.5, "BUX" => 50.0, "moonBUX" => 100.5, ...}

# Get specific token balance
EngagementTracker.get_user_token_balance(user_id, "moonBUX")
# => 100.5
```

---

## Environment Configuration

### Blockster App (.env)

```bash
# BUX Minter API Secret (must match minter service)
BUX_MINTER_SECRET=your-secret-key
```

### BUX Minter Service (.env)

```bash
# API authentication
API_SECRET=your-secret-key

# Rogue Chain RPC
RPC_URL=https://rpc.roguechain.io/rpc

# Token owner private keys
OWNER_PRIVATE_KEY=0x...           # BUX token owner
PRIVATE_KEY_MOONBUX=0x...         # moonBUX token owner
PRIVATE_KEY_NEOBUX=0x...          # neoBUX token owner
PRIVATE_KEY_ROGUEBUX=0x...        # rogueBUX token owner
PRIVATE_KEY_FLAREBUX=0x...        # flareBUX token owner
PRIVATE_KEY_NFTBUX=0x...          # nftBUX token owner
PRIVATE_KEY_NOLCHABUX=0x...       # nolchaBUX token owner
PRIVATE_KEY_SOLBUX=0x...          # solBUX token owner
PRIVATE_KEY_SPACEBUX=0x...        # spaceBUX token owner
PRIVATE_KEY_TRONBUX=0x...         # tronBUX token owner
PRIVATE_KEY_TRANBUX=0x...         # tranBUX token owner
```

### Production Deployment (Fly.io)

Set secrets using:

```bash
flyctl secrets set API_SECRET=your-secret-key
flyctl secrets set OWNER_PRIVATE_KEY=0x...
flyctl secrets set PRIVATE_KEY_MOONBUX=0x...
# ... etc
```

---

## Security Considerations

1. **Private Key Isolation** - Token owner private keys only exist in the BUX Minter service, never in the main app
2. **Bearer Token Auth** - All minting requests require valid API secret
3. **Wallet Validation** - All wallet addresses are validated before minting
4. **Transaction Verification** - Transactions are confirmed on-chain before recording
5. **Token Fallback** - Invalid/unconfigured tokens fall back to BUX to prevent errors

---

## Troubleshooting

### Common Issues

1. **"No private key configured for X token"**
   - Ensure the corresponding `PRIVATE_KEY_*` env var is set in bux-minter
   - The system will fall back to BUX

2. **"Insufficient gas funds"**
   - The token owner wallet needs ROGUE for gas
   - Fund the wallet shown in the error message

3. **Token not appearing in UI**
   - Verify hub.token field is set correctly
   - Check that token name matches exactly (case-sensitive)

4. **Balance not updating**
   - Check BUX Minter logs for errors
   - Verify RPC endpoint is responsive
   - Check Mnesia table `user_bux_balances`

### Logs

**BUX Minter:**
```
[INIT] Configured moonBUX with wallet 0x...
[MINT] Starting mint: 10 moonBUX to 0x...
[MINT] Transaction submitted: 0x...
[MINT] Transaction confirmed in block 12345
```

**Blockster App:**
```
[BuxMinter] Minting 10 moonBUX to 0x... (user: 123, post: 456)
[BuxMinter] Mint successful: moonBUX tx=0x...
[EngagementTracker] Updated user_bux_balances: moonBUX=10.0, aggregate=10.0
```
