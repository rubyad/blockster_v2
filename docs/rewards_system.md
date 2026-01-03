# Blockster Rewards System

> **Note (January 2026)**: Hub tokens have been removed from the application. Only BUX (for rewards and shop discounts) and ROGUE (for BUX Booster betting) are active. This document has been updated to reflect the simplified BUX-only rewards system.

A guide to the BUX rewards system that rewards users for reading articles and sharing on social media.

## Table of Contents

1. [Overview](#overview)
2. [Token Types](#token-types)
3. [Architecture](#architecture)
4. [Read Rewards Flow](#read-rewards-flow)
5. [Share Rewards Flow](#share-rewards-flow)
6. [BUX Minter Service](#bux-minter-service)
7. [Database Storage](#database-storage)
8. [API Reference](#api-reference)
9. [Environment Configuration](#environment-configuration)

---

## Overview

The Blockster rewards system incentivizes user engagement through token rewards. Users earn BUX by:

1. **Reading articles** - Engagement score based on time spent, scroll depth, and completion
2. **Sharing on X (Twitter)** - Retweeting and liking campaign tweets

All rewards are paid in **BUX** tokens regardless of which hub the content belongs to.

---

## Token Types

The system uses two tokens:

| Token | Contract Address | Purpose |
|-------|------------------|---------|
| BUX | `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8` | Reading/sharing rewards, shop discounts |
| ROGUE | (native token - no contract) | BUX Booster betting, gas fees |

BUX is an ERC-20 token with 18 decimals:

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
│  │  - Calls BuxMinter.mint_bux() to reward BUX              │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  engagement_tracker.ex                                    │   │
│  │  - Calculates engagement scores                           │   │
│  │  - Records rewards in Mnesia tables                       │   │
│  │  - Updates BUX balances                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  bux_minter.ex                                            │   │
│  │  - HTTP client for BUX Minter service                     │   │
│  │  - Handles token minting and balance queries              │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    BUX MINTER SERVICE                            │
│                    (Node.js / Express)                           │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  index.js                                                 │   │
│  │  - POST /mint - Mint BUX tokens                           │   │
│  │  - GET /balance/:address - Get BUX balance                │   │
│  │  - GET /aggregated-balances/:address - Get all balances   │   │
│  │  - Uses ethers.js to interact with Rogue Chain            │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ROGUE CHAIN                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  BUX Token Contract (ERC-20)                              │   │
│  │  0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8              │   │
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

### 4. Minting Process

```elixir
# Async mint with callback for tx_hash
Task.start(fn ->
  case BuxMinter.mint_bux(wallet, bux_earned, user_id, post_id, :read) do
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
7. Mints BUX tokens
8. Updates reward status to "rewarded" in **Mnesia**

**Important:** The entire retweet flow uses Mnesia only. No PostgreSQL queries are made during the retweet action itself.

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

Mint BUX tokens to a user's wallet.

**Request:**
```json
{
  "walletAddress": "0x...",
  "amount": 10,
  "userId": 123,
  "postId": 456
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
  "token": "BUX",
  "newBalance": "50.0",
  "userId": 123,
  "postId": 456
}
```

#### GET /balance/:address

Get BUX balance for an address.

**Response:**
```json
{
  "address": "0x...",
  "token": "BUX",
  "balance": "50.0",
  "balanceWei": "50000000000000000000"
}
```

#### GET /aggregated-balances/:address

Get BUX and ROGUE balances for an address.

**Response:**
```json
{
  "address": "0x...",
  "balances": {
    "BUX": "100.0",
    "ROGUE": "50.0"
  }
}
```

---

## Database Storage

### Mnesia Tables (Primary Storage)

All X share-related data is stored exclusively in Mnesia for fast, distributed access.

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

Only the `users.locked_x_user_id` field is stored in PostgreSQL for permanent X account locking.

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
Tracks BUX balance for each user:

```
{user_id, user_smart_wallet, updated_at, aggregate_bux_balance,
 bux_balance, ...deprecated hub token fields...}
```

**Note**: Fields for hub tokens (indices 6-15) remain in the schema for backward compatibility but are no longer used. Only `bux_balance` (index 5) is actively maintained.

#### user_rogue_balances
Tracks ROGUE (native token) balance separately:

```
{user_id, rogue_balance, updated_at}
```

**IMPORTANT**: ROGUE is the native gas token of Rogue Chain and is NOT included in BUX aggregate calculations. It has no contract address.

#### user_multipliers
```
{user_id, smart_wallet, x_multiplier, linkedin_multiplier,
 personal_multiplier, rogue_multiplier, overall_multiplier,
 extras, created_at, updated_at}
```

---

## API Reference

### Elixir Functions

#### BuxMinter

```elixir
# Mint BUX tokens (sync)
BuxMinter.mint_bux(wallet_address, amount, user_id, post_id, :read)
BuxMinter.mint_bux(wallet_address, amount, user_id, post_id, :x_share)

# Mint BUX tokens (async)
BuxMinter.mint_bux_async(wallet_address, amount, user_id, post_id, :read)

# Get BUX balance
BuxMinter.get_balance(wallet_address)

# Get all token balances (BUX and ROGUE)
BuxMinter.get_aggregated_balances(wallet_address)
```

#### EngagementTracker

```elixir
# Update BUX balance
EngagementTracker.update_user_token_balance(user_id, wallet, "BUX", "100.5")

# Get all token balances for user
EngagementTracker.get_user_token_balances(user_id)
# => %{"BUX" => 100.5, "ROGUE" => 50.0}

# Get BUX balance
EngagementTracker.get_user_token_balance(user_id, "BUX")
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

# BUX token owner private key
OWNER_PRIVATE_KEY=0x...
```

### Production Deployment (Fly.io)

Set secrets using:

```bash
flyctl secrets set API_SECRET=your-secret-key
flyctl secrets set OWNER_PRIVATE_KEY=0x...
```

---

## Security Considerations

1. **Private Key Isolation** - BUX token owner private key only exists in the BUX Minter service, never in the main app
2. **Bearer Token Auth** - All minting requests require valid API secret
3. **Wallet Validation** - All wallet addresses are validated before minting
4. **Transaction Verification** - Transactions are confirmed on-chain before recording

---

## Troubleshooting

### Common Issues

1. **"No private key configured"**
   - Ensure `OWNER_PRIVATE_KEY` env var is set in bux-minter

2. **"Insufficient gas funds"**
   - The BUX token owner wallet needs ROGUE for gas
   - Fund the wallet shown in the error message

3. **Balance not updating**
   - Check BUX Minter logs for errors
   - Verify RPC endpoint is responsive
   - Check Mnesia table `user_bux_balances`

### Logs

**BUX Minter:**
```
[INIT] Configured BUX with wallet 0x...
[MINT] Starting mint: 10 BUX to 0x...
[MINT] Transaction submitted: 0x...
[MINT] Transaction confirmed in block 12345
```

**Blockster App:**
```
[BuxMinter] Minting 10 BUX to 0x... (user: 123, post: 456)
[BuxMinter] Mint successful: BUX tx=0x...
[EngagementTracker] Updated user_bux_balances: BUX=10.0
```

---

## Deprecated Hub Tokens (Historical Reference)

> **IMPORTANT**: These tokens are no longer used by the application as of January 2026.
> The contracts still exist on Rogue Chain but the app no longer mints or tracks these tokens.

| Token | Contract Address |
|-------|------------------|
| moonBUX | `0x08F12025c1cFC4813F21c2325b124F6B6b5cfDF5` |
| neoBUX | `0x423656448374003C2cfEaFF88D5F64fb3A76487C` |
| rogueBUX | `0x56d271b1C1DCF597aA3ee454bCCb265d4Dee47b3` |
| flareBUX | `0xd27EcA9bc2401E8CEf92a14F5Ee9847508EDdaC8` |
| nftBUX | `0x9853e3Abea96985d55E9c6963afbAf1B0C9e49ED` |
| nolchaBUX | `0x4cE5C87FAbE273B58cb4Ef913aDEa5eE15AFb642` |
| solBUX | `0x92434779E281468611237d18AdE20A4f7F29DB38` |
| spaceBUX | `0xAcaCa77FbC674728088f41f6d978F0194cf3d55A` |
| tronBUX | `0x98eDb381281FA02b494FEd76f0D9F3AEFb2Db665` |
| tranBUX | `0xcDdE88C8bacB37Fc669fa6DECE92E3d8FE672d96` |
| blocksterBUX | `0x133Faa922052aE42485609E14A1565551323CdbE` |
