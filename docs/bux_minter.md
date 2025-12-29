# BUX Minter Service

The BUX Minter is a Node.js microservice deployed on Fly.io that handles blockchain operations for the Blockster platform. It serves as the bridge between the Phoenix application and the Rogue Chain blockchain.

**Service URL**: `https://bux-minter.fly.dev`
**Network**: Rogue Chain Mainnet (Chain ID: 560013)
**Location**: `/bux-minter/` directory in this repo

## Table of Contents

1. [Architecture](#architecture)
2. [Token Minting](#token-minting)
3. [Balance Queries](#balance-queries)
4. [BUX Booster Game Integration](#bux-booster-game-integration)
5. [House Balance & Max Bet](#house-balance--max-bet)
6. [API Endpoints](#api-endpoints)
7. [Security](#security)
8. [Deployment](#deployment)
9. [Usage Across App](#usage-across-app)

## Architecture

### Tech Stack
- **Runtime**: Node.js 20
- **Framework**: Express.js
- **Blockchain Library**: ethers.js v6
- **Deployment**: Fly.io (2 machines in ORD region)

### Key Components

```
bux-minter/
├── index.js           # Main service file
├── package.json       # Dependencies
├── Dockerfile         # Container configuration
└── fly.toml          # Fly.io deployment config
```

### Environment Variables

| Variable | Purpose | Required |
|----------|---------|----------|
| `OWNER_PRIVATE_KEY` | BUX token owner private key | Yes |
| `SETTLER_PRIVATE_KEY` | BuxBoosterGame settler wallet | Yes |
| `CONTRACT_OWNER_PRIVATE_KEY` | BuxBoosterGame owner (for deposits) | Yes |
| `API_SECRET` | Authentication secret for API calls | Yes |
| `PRIVATE_KEY_MOONBUX` | moonBUX token owner | Optional |
| `PRIVATE_KEY_NEOBUX` | neoBUX token owner | Optional |
| *(other hub tokens)* | Hub token owner private keys | Optional |

## Token Minting

### Overview

The BUX minter can mint any supported token to a user's smart wallet address. This is the **primary** way tokens are distributed as rewards in the Blockster platform.

### Supported Tokens

| Token | Contract Address | Use Case |
|-------|------------------|----------|
| BUX | `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8` | Global platform token |
| moonBUX | `0x08F12025c1cFC4813F21c2325b124F6B6b5cfDF5` | Moon hub rewards |
| neoBUX | `0x423656448374003C2cfEaFF88D5F64fb3A76487C` | Neo hub rewards |
| rogueBUX | `0x56d271b1C1DCF597aA3ee454bCCb265d4Dee47b3` | Rogue hub rewards |
| flareBUX | `0xd27EcA9bc2401E8CEf92a14F5Ee9847508EDdaC8` | Flare hub rewards |
| nftBUX | `0x9853e3Abea96985d55E9c6963afbAf1B0C9e49ED` | NFT hub rewards |
| nolchaBUX | `0x4cE5C87FAbE273B58cb4Ef913aDEa5eE15AFb642` | Nolcha hub rewards |
| solBUX | `0x92434779E281468611237d18AdE20A4f7F29DB38` | Sol hub rewards |
| spaceBUX | `0xAcaCa77FbC674728088f41f6d978F0194cf3d55A` | Space hub rewards |
| tronBUX | `0x98eDb381281FA02b494FEd76f0D9F3AEFb2Db665` | Tron hub rewards |
| tranBUX | `0xcDdE88C8bacB37Fc669fa6DECE92E3d8FE672d96` | Tran hub rewards |
| blocksterBUX | `0x133Faa922052aE42485609E14A1565551323CdbE` | Blockster hub rewards |

### Minting Flow

```elixir
# Called from: EngagementTracker, Social.ShareRewards
BuxMinter.mint_bux(
  wallet_address,  # User's smart wallet
  amount,          # Tokens to mint (in whole units)
  user_id,         # For logging
  post_id,         # For logging
  :read,           # Reward type (:read or :x_share)
  "moonBUX",       # Token to mint
  hub_id           # Optional hub_id for tracking
)
```

**Used By**:
- `BlocksterV2.EngagementTracker` - Rewards for reading articles
- `BlocksterV2.Social.ShareRewards` - Rewards for X (Twitter) shares

**When Called**:
- After user completes article engagement (based on engagement score)
- After user successfully shares article on X and campaign is verified
- Automatically updates Mnesia balances after minting

## Balance Queries

### Single Token Balance

```elixir
# Get balance for a specific token
BuxMinter.get_balance(wallet_address, "BUX")
# => {:ok, 1234.56} or {:error, reason}
```

### All Token Balances (Individual Queries)

```elixir
# Queries each token separately (11 RPC calls)
BuxMinter.get_all_balances(wallet_address)
# => {:ok, %{"BUX" => 100.0, "moonBUX" => 50.0, ...}}
```

### Aggregated Balances (Single Query)

**Recommended for production use** - uses BalanceAggregator contract.

```elixir
# Single RPC call via BalanceAggregator contract
BuxMinter.get_aggregated_balances(wallet_address)
# => {:ok, %{balances: %{"BUX" => 100.0, ...}, aggregate: 150.0}}
```

**BalanceAggregator Contract**: `0x3A5a60fE307088Ae3F367d529E601ac52ed2b660`

### Balance Syncing

The most common pattern - syncs blockchain balances to Mnesia cache:

```elixir
# Synchronous sync
BuxMinter.sync_user_balances(user_id, wallet_address)

# Asynchronous sync (fire and forget)
BuxMinter.sync_user_balances_async(user_id, wallet_address)
```

**Used By**:
- `BuxBoosterLive` - On mount (async)
- `BuxBalanceHook` - After token transactions
- Various LiveViews - To refresh user balances

**Flow**:
1. Fetches all token balances via BalanceAggregator
2. Updates Mnesia `user_bux_balances` table
3. Broadcasts `:token_balances_updated` event via PubSub
4. All subscribed LiveViews update UI automatically

## BUX Booster Game Integration

The BUX minter handles all blockchain interactions for the BUX Booster coin flip game.

### Game Contract

- **Contract**: BuxBoosterGame (UUPS Proxy)
- **Address**: `0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B`
- **Pattern**: ERC-4337 Account Abstraction with Paymaster

### Commitment Submission

**When**: User starts a new game session or changes difficulty

```elixir
# Called from: BuxBoosterOnchain
BuxMinter.submit_commitment(commitment_hash, player_address, nonce)
```

**Flow**:
1. Phoenix generates server seed + commitment hash
2. BUX minter submits commitment to contract (on-chain)
3. Commitment hash stored in Mnesia for later settlement
4. User can now place bet with predictions

### Bet Settlement

**When**: User places bet and results are calculated

```elixir
# Called from: BuxBoosterOnchain.settle_bet/5
BuxMinter.settle_bet(
  commitment_hash,  # Bet identifier
  server_seed,      # Revealed seed (proves fairness)
  results,          # Server-calculated results [0,1,1,0,...]
  won               # true/false
)
```

**Flow**:
1. Server calculates flip results using server seed
2. BUX minter submits settlement to contract
3. Contract verifies server seed matches commitment
4. If won: transfers payout to player
5. If lost: keeps bet amount in house balance
6. Updates player stats in contract
7. Triggers balance sync in Phoenix

### Player State Queries

```elixir
# Get player's current nonce (UNUSED - nonces tracked in Mnesia)
BuxMinter.get_player_nonce(player_address)

# Get player's full state (nonce + unused commitment)
BuxMinter.get_player_state(player_address)
```

**Note**: As of Dec 2024, nonces are **only** tracked in Mnesia. Contract nonces exist but are not validated - Mnesia is source of truth.

## House Balance & Max Bet

**Added**: December 2024

### House Balance Query

Get the current house bankroll for a token from the BuxBoosterGame contract:

```elixir
# Called from: BuxBoosterLive
BuxMinter.get_house_balance("BUX")
# => {:ok, 59704.26} or {:error, reason}
```

**Used By**:
- `BuxBoosterLive.mount/3` - Fetch house balance on page load
- `BuxBoosterLive.handle_event("select_token", ...)` - Update when token changes

**Endpoint**: `GET /game-token-config/:token`

**Response**:
```json
{
  "token": "BUX",
  "tokenAddress": "0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8",
  "enabled": true,
  "houseBalance": "59704.26"
}
```

### Max Bet Calculation

Phoenix calculates max bet client-side using the contract's formula:

```elixir
# In BuxBoosterLive
defp calculate_max_bet(house_balance, difficulty_level, difficulty_options) do
  multiplier_bp = trunc(multiplier * 10000)
  base_max_bet = house_balance * 0.001  # 0.1% of house
  max_bet = (base_max_bet * 20000) / multiplier_bp
  trunc(max_bet)  # Round down to integer
end
```

**Formula**: Ensures max payout is consistently 0.2% of house balance across all difficulties.

**Display**:
- House balance shown below token selector
- Max bet shown on MAX button: "MAX (60)"
- Updates dynamically when switching tokens or difficulties

### Contract Query Details

The BUX minter queries `tokenConfigs(address)` which returns a struct:

```solidity
struct TokenConfig {
    bool enabled;
    uint256 houseBalance;
}
```

**Important**: The contract does NOT expose `maxBet` directly. Max bet is calculated using the formula to maintain consistent risk exposure (0.2% of house balance).

## API Endpoints

### Authentication

All endpoints require Bearer token authentication:

```
Authorization: Bearer <API_SECRET>
```

### Minting

**POST /mint**

```json
{
  "walletAddress": "0x...",
  "amount": 100,
  "userId": 65,
  "postId": 123,
  "rewardType": "read",
  "token": "BUX",
  "hubId": null
}
```

### Balance Queries

**GET /balance/:address/:token**
Returns single token balance

**GET /aggregated-balances/:address**
Returns all token balances (recommended)

### Game Operations

**POST /submit-commitment**
```json
{
  "commitmentHash": "0x...",
  "player": "0x...",
  "nonce": 127
}
```

**POST /settle-bet** (V3)
```json
{
  "commitmentHash": "0x...",
  "serverSeed": "0x...",
  "results": [0, 1, 1],
  "won": true
}
```

**GET /player-nonce/:address**
Returns player's on-chain nonce (unused)

**GET /player-state/:address**
Returns nonce + unused commitment

**GET /game-token-config/:token**
Returns house balance and enabled status

### House Deposits (Admin Only)

**POST /deposit-house-balance**

Deposits tokens into the BuxBoosterGame house bankroll for a specific token. This funds the contract so it can pay out winnings.

**Request**:
```json
{
  "token": "BUX",
  "amount": 1000000
}
```

**cURL Example**:
```bash
curl -X POST https://bux-minter.fly.dev/deposit-house-balance \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <API_SECRET>" \
  -d '{"token": "BUX", "amount": 1000000}'
```

**Response**:
```json
{
  "success": true,
  "txHash": "0x...",
  "blockNumber": 12345,
  "token": "BUX",
  "amountDeposited": "1000000",
  "newHouseBalance": "1059704.26"
}
```

**Requirements**:
- `CONTRACT_OWNER_PRIVATE_KEY` must be set in environment
- Token owner private key must be configured (e.g., `OWNER_PRIVATE_KEY` for BUX)

**Flow**:
1. Token owner mints tokens to contract owner wallet
2. Contract owner approves BuxBoosterGame contract to spend tokens
3. Contract owner calls `depositHouseBalance(tokenAddress, amount)`
4. Returns updated house balance from contract

**Nonce Management** (Dec 29, 2025):
- Explicitly fetches and manages nonces using `getTransactionCount(address, 'pending')`
- Prevents "nonce too low" errors by manually incrementing nonces for sequential transactions
- Each of the 3 transactions (mint, approve, deposit) uses an explicit nonce

## Security

### Private Key Management

- **NEVER** expose private keys in code or logs
- All keys stored in Fly.io secrets
- Separate keys for different roles:
  - Token owners (mint tokens)
  - Settler (submit commitments & settlements)
  - Contract owner (deposit house funds)

### API Authentication

- Bearer token authentication required on all endpoints
- `API_SECRET` environment variable
- Phoenix app passes secret from config

```elixir
# In Phoenix
defp get_api_secret do
  Application.get_env(:blockster_v2, :bux_minter_secret) ||
    System.get_env("BUX_MINTER_SECRET")
end
```

### Transaction Safety

- All blockchain transactions use ethers.js v6
- Gas estimation before transaction submission
- Transaction receipts verified before confirming success
- Automatic retry logic for failed RPC calls

## Deployment

### Build & Deploy

```bash
cd bux-minter
flyctl deploy
```

**Image Registry**: `registry.fly.io/bux-minter`
**Deployment Strategy**: Rolling update (2 machines)

### Scaling

Currently runs 2 machines:
- Region: `ord` (Chicago)
- One stopped, one active (cost optimization)
- Auto-starts on request

### Monitoring

```bash
# Check status
flyctl status -a bux-minter

# View logs
flyctl logs -a bux-minter

# Restart
flyctl machine restart <machine-id> -a bux-minter
```

### Environment Configuration

```bash
# Set secrets
flyctl secrets set OWNER_PRIVATE_KEY=<key> -a bux-minter
flyctl secrets set API_SECRET=<secret> -a bux-minter
```

## Usage Across App

### Module: `BlocksterV2.BuxMinter`

**Location**: `lib/blockster_v2/bux_minter.ex`

**Purpose**: Elixir client for BUX minter service

**Key Functions**:
- `mint_bux/7` - Mint tokens to wallet
- `get_balance/2` - Get single token balance
- `get_all_balances/1` - Get all balances (deprecated - use aggregated)
- `get_aggregated_balances/1` - Get all balances (single call)
- `sync_user_balances/2` - Sync balances to Mnesia
- `sync_user_balances_async/2` - Async sync
- `get_house_balance/1` - Get house bankroll

### EngagementTracker

**File**: `lib/blockster_v2/engagement_tracker.ex`

**Usage**:
```elixir
# After calculating engagement score
case BuxMinter.mint_bux(wallet_address, bux_earned, user_id, post_id, :read, token) do
  {:ok, _} -> Logger.info("Minted #{bux_earned} #{token}")
  {:error, reason} -> Logger.error("Mint failed: #{inspect(reason)}")
end
```

**When**: User completes article engagement (scroll + time thresholds met)

### Social.ShareRewards

**File**: `lib/blockster_v2/social/share_rewards.ex`

**Usage**:
```elixir
# After verifying retweet
BuxMinter.mint_bux(wallet, reward_amount, user_id, post_id, :x_share, campaign.token)
```

**When**: User successfully shares article on X and retweet is verified

### BuxBoosterOnchain

**File**: `lib/blockster_v2/bux_booster_onchain.ex`

**Usage**:
```elixir
# Submit commitment when starting game
defp submit_commitment_to_chain(commitment_hash, player, nonce) do
  BuxMinter.submit_commitment(commitment_hash, player, nonce)
end

# Settle bet after results calculated
def settle_bet(game_id, server_seed, results, won, bet_amount) do
  BuxMinter.settle_bet(commitment_hash, server_seed, results, won)
end
```

**When**:
- Game initialization (submit commitment)
- Bet placement confirmed (settlement)

### BuxBoosterLive

**File**: `lib/blockster_v2_web/live/bux_booster_live.ex`

**Usage**:
```elixir
# On mount - fetch house balance
def mount(_params, _session, socket) do
  house_balance = case BuxMinter.get_house_balance("BUX") do
    {:ok, balance} -> balance
    {:error, _} -> 0.0
  end

  # On connected mount - sync balances
  if connected?(socket) do
    BuxMinter.sync_user_balances_async(user_id, wallet_address)
  end

  {:ok, assign(socket, house_balance: house_balance, ...)}
end

# On token change - fetch new house balance
def handle_event("select_token", %{"token" => token}, socket) do
  house_balance = case BuxMinter.get_house_balance(token) do
    {:ok, balance} -> balance
    {:error, _} -> 0.0
  end

  {:noreply, assign(socket, house_balance: house_balance, ...)}
end
```

**When**:
- Page load (house balance)
- Token/difficulty change (house balance)
- Mount (balance sync)

### BuxBalanceHook

**File**: `lib/blockster_v2_web/live/bux_balance_hook.ex`

**Usage**:
```elixir
# After balance changes
def handle_info({:token_balances_updated, balances}, socket) do
  # Triggered by sync_user_balances broadcast
  {:cont, assign(socket, token_balances: balances)}
end
```

**When**: After any token transaction (automatically via PubSub)

## Performance Considerations

### RPC Call Optimization

1. **Use BalanceAggregator**: Single RPC call vs 11 separate calls
2. **Cache in Mnesia**: Don't query blockchain on every page load
3. **Async Syncing**: Use `sync_user_balances_async` for non-blocking updates
4. **PubSub Broadcasts**: Update all LiveViews simultaneously after sync

### Connection Pooling

- Req library handles connection reuse
- `inet_backend: :inet` for DNS to avoid distributed mode issues
- 30-60 second timeouts for blockchain calls
- Automatic retry on 500 errors (up to 3 retries)

### Error Handling

```elixir
# Always handle both success and error cases
case BuxMinter.mint_bux(...) do
  {:ok, response} ->
    # Update Mnesia, log success
  {:error, :not_configured} ->
    # API secret missing
  {:error, reason} ->
    # Network error, contract error, etc.
end
```

## Common Issues & Troubleshooting

### Issue: Transport Error (Connection Closed)

**Symptom**: `%Req.TransportError{reason: :closed}`

**Cause**: BUX minter crashed or restarted during request

**Solution**: Check BUX minter logs, usually recovers on retry

### Issue: Invalid BigNumberish Value

**Symptom**: `invalid BigNumberish value (argument="value", value=null)`

**Cause**: Contract returned null for a value (token not configured)

**Solution**: Check token is enabled in contract, house balance deposited

### Issue: House Balance Shows 0

**Symptom**: Max bet is 0, house balance is 0

**Cause**: Token not configured in BuxBoosterGame contract or API call failed

**Solution**:
1. Check BUX minter logs for errors
2. Verify token is enabled: contract query `tokenConfigs(address)`
3. Ensure house balance deposited for that token

### Issue: Nonce Mismatch

**Symptom**: Settlement fails, "invalid nonce"

**Solution**: Nonces are now tracked in Mnesia only (not validated by contract)

## Future Improvements

- [ ] Add rate limiting to prevent abuse
- [ ] Implement transaction queuing for high-volume periods
- [ ] Add metrics/monitoring (Prometheus)
- [ ] Support multiple RPC endpoints for failover
- [ ] Batch minting for multiple users
- [ ] WebSocket events for real-time balance updates
