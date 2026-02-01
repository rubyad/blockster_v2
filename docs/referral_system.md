# Blockster Referral System - Implementation Specification

**Version**: 2.0
**Created**: January 30, 2026
**Status**: Specification - Ready for Implementation

---

## Overview

A comprehensive referral system where users earn BUX tokens for referring new users to Blockster. Referrers earn:
- **100 BUX** when a referred user signs up
- **100 BUX** when a referred user verifies their phone number
- **1%** of every losing BUX bet on BUX Booster by their referrals (paid from smart contract)
- **0.2%** of every losing ROGUE bet on BUX Booster by their referrals (paid from smart contract)
- **(Future)** A percentage of all shop purchases by referrals

---

## Table of Contents

1. [User Journey](#user-journey)
2. [Data Storage (Mnesia)](#data-storage-mnesia)
3. [Referral Link Generation](#referral-link-generation)
4. [Signup Flow Integration](#signup-flow-integration)
5. [Phone Verification Reward](#phone-verification-reward)
6. [Smart Contract Changes](#smart-contract-changes)
7. [Event Polling System](#event-polling-system)
8. [Real-Time Earnings Display](#real-time-earnings-display)
9. [Members Page UI](#members-page-ui)
10. [Backend Implementation](#backend-implementation)
11. [Security Considerations](#security-considerations)
12. [Deployment Checklist](#deployment-checklist)

---

## User Journey

```
REFERRER JOURNEY
================

1. User visits /members/:id and clicks "Refer" tab
   └─ Sees their unique referral link: blockster.com/?ref=0xSmartWalletAddress

2. User shares link with friends

3. Friend clicks link and lands on homepage
   └─ ?ref=0x... parameter captured and stored in localStorage

4. Friend signs up with email
   └─ Referrer code passed to backend
   └─ Referrer linked to new user in PostgreSQL (user.referrer_id) and Mnesia (for fast queries)
   └─ Referrer earns 100 BUX (minted via BuxMinter)

5. New user verifies their phone number
   └─ Referrer earns additional 100 BUX
   └─ Real-time notification to referrer via PubSub

6. New user plays BUX Booster and loses a bet
   └─ Smart contract automatically sends 1% (BUX) or 0.2% (ROGUE) to referrer wallet
   └─ ReferralRewardPoller detects ReferralRewardPaid event (~1 second)
   └─ Real-time update in referrer's earnings table via PubSub

REFERRAL LIFECYCLE
==================

┌────────────────┐     ┌────────────────┐     ┌─────────────────┐
│ Referral Link  │────>│ User Signup    │────>│ Phone Verified  │
│ Shared         │     │ +100 BUX       │     │ +100 BUX        │
└────────────────┘     └────────────────┘     └─────────────────┘
                                                      │
                                                      v
┌────────────────────────────────────────────────────────────────┐
│                    ONGOING EARNINGS                             │
├─────────────────────────────────────────────────────────────────┤
│ BUX Booster Loss (BUX):   1% of losing bet → Referrer wallet   │
│ BUX Booster Loss (ROGUE): 0.2% of losing bet → Referrer wallet │
│ Shop Purchase: X% of purchase → Referrer (FUTURE)              │
└────────────────────────────────────────────────────────────────┘
```

---

## Data Storage (Mnesia)

All referral data is stored in Mnesia for fast, distributed access - consistent with how the rest of Blockster handles real-time data.

### Mnesia Tables

Add these tables to `lib/blockster_v2/mnesia_initializer.ex`:

```elixir
# In MnesiaInitializer.ensure_tables_exist/0

# Referral mappings: user_id -> referrer info
:mnesia.create_table(:referrals, [
  attributes: [:user_id, :referrer_id, :referrer_wallet, :referee_wallet, :referred_at, :on_chain_synced],
  disc_copies: [node()],
  index: [:referrer_id, :referrer_wallet, :referee_wallet]
])

# Referral earnings history (bag type - allows multiple records per user)
# Stores wallet addresses directly to avoid PostgreSQL lookups
:mnesia.create_table(:referral_earnings, [
  attributes: [:id, :referrer_id, :referrer_wallet, :referee_wallet, :earning_type, :amount, :token, :tx_hash, :commitment_hash, :timestamp],
  disc_copies: [node()],
  type: :bag,
  index: [:referrer_id, :referrer_wallet, :referee_wallet, :commitment_hash]
])

# Referral stats cache (fast lookup for dashboard)
:mnesia.create_table(:referral_stats, [
  attributes: [:user_id, :total_referrals, :verified_referrals, :total_bux_earned, :total_rogue_earned, :updated_at],
  disc_copies: [node()],
  index: []
])

# Poller state persistence (like high-rollers-elixir hr_poller_state)
:mnesia.create_table(:referral_poller_state, [
  attributes: [:key, :last_block, :updated_at],
  disc_copies: [node()]
])
```

### Table Record Structures

```elixir
# :referrals table
# Key: user_id (the referred user)
{:referrals,
  user_id,           # integer - the referred user's ID
  referrer_id,       # integer - the referrer's user ID
  referrer_wallet,   # string - referrer's smart wallet (for contract sync)
  referee_wallet,    # string - referee's smart wallet (for blockchain event matching)
  referred_at,       # integer - Unix timestamp (seconds)
  on_chain_synced    # boolean - whether setPlayerReferrer was called on contracts
}

# :referral_earnings table (bag type)
# Key: id (UUID for uniqueness)
# Stores wallet addresses directly to avoid PostgreSQL lookups during display
{:referral_earnings,
  id,                # string - UUID
  referrer_id,       # integer - who earned (for indexing by user)
  referrer_wallet,   # string - referrer's smart wallet (for display, no DB lookup needed)
  referee_wallet,    # string - referee's smart wallet (for display, no DB lookup needed)
  earning_type,      # atom - :signup | :phone_verified | :bux_bet_loss | :rogue_bet_loss | :shop_purchase
  amount,            # float - amount earned
  token,             # string - "BUX" or "ROGUE"
  tx_hash,           # string | nil - blockchain tx hash (for bet losses)
  commitment_hash,   # string | nil - bet commitment hash (for dedup)
  timestamp          # integer - Unix timestamp (seconds)
}

# :referral_stats table
# Key: user_id
{:referral_stats,
  user_id,           # integer
  total_referrals,   # integer - count of referred users
  verified_referrals,# integer - count who verified phone
  total_bux_earned,  # float
  total_rogue_earned,# float
  updated_at         # integer - Unix timestamp
}

# :referral_poller_state table
# Key: :rogue (for Rogue Chain poller)
{:referral_poller_state,
  key,               # atom - :rogue
  last_block,        # integer - last processed block number
  updated_at         # integer - Unix timestamp
}
```

### Wallet-to-User Lookup (Mnesia-Only)

The existing `user_bux_balances` table already maps `user_id` to wallet addresses. We can use this for reverse lookups without hitting PostgreSQL:

```elixir
# In BlocksterV2.Referrals module

@doc """
Look up user_id by smart wallet address using existing Mnesia tables.
Returns {:ok, user_id} or :not_found
"""
def get_user_id_by_wallet(wallet_address) when is_binary(wallet_address) do
  wallet = String.downcase(wallet_address)

  # First check :referrals table (has referee_wallet index)
  case :mnesia.dirty_index_read(:referrals, wallet, :referee_wallet) do
    [{:referrals, user_id, _, _, _, _, _} | _] -> {:ok, user_id}
    [] ->
      # Fallback: check :referrals by referrer_wallet
      case :mnesia.dirty_index_read(:referrals, wallet, :referrer_wallet) do
        [{:referrals, _, referrer_id, _, _, _, _} | _] -> {:ok, referrer_id}
        [] -> :not_found
      end
  end
end

@doc """
Look up referrer info by referee's wallet address.
Returns {:ok, %{referrer_id, referrer_wallet}} or :not_found
"""
def get_referrer_by_referee_wallet(referee_wallet) when is_binary(referee_wallet) do
  wallet = String.downcase(referee_wallet)

  case :mnesia.dirty_index_read(:referrals, wallet, :referee_wallet) do
    [{:referrals, _user_id, referrer_id, referrer_wallet, _, _, _} | _] ->
      {:ok, %{referrer_id: referrer_id, referrer_wallet: referrer_wallet}}
    [] ->
      :not_found
  end
end
```

### PostgreSQL Migration (User Table Only)

Only the users table needs a migration to add the referrer relationship:

```elixir
# priv/repo/migrations/YYYYMMDDHHMMSS_add_referrer_to_users.exs

defmodule BlocksterV2.Repo.Migrations.AddReferrerToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :referrer_id, references(:users, on_delete: :nilify_all)
      add :referred_at, :utc_datetime
    end

    create index(:users, [:referrer_id])
  end
end
```

---

## Referral Link Generation

### Link Format

The referral link uses the user's smart wallet address as the identifier:

```
https://blockster.com/?ref=0x1234567890abcdef1234567890abcdef12345678
```

**Why Smart Wallet Address?**
1. Every user has one (created at signup)
2. Unique and immutable
3. Can be validated on-chain
4. Same format used for BuxBoosterGame referrer rewards
5. No additional database lookups needed

---

## Signup Flow Integration

### Step 1: Capture Referral Code on Landing

```javascript
// assets/js/home_hooks.js - Add to ThirdwebLogin hook

mounted() {
  // Capture referral code from URL and store
  this.captureReferralCode();
  // ... existing code
}

captureReferralCode() {
  const urlParams = new URLSearchParams(window.location.search);
  const refCode = urlParams.get('ref');

  if (refCode && /^0x[a-fA-F0-9]{40}$/.test(refCode)) {
    // Store in localStorage for persistence across page navigations
    localStorage.setItem('blockster_referrer', refCode.toLowerCase());
    console.log('[Referral] Captured referrer:', refCode);
  }
}

getReferrerCode() {
  return localStorage.getItem('blockster_referrer');
}

clearReferrerCode() {
  localStorage.removeItem('blockster_referrer');
}
```

### Step 2: Pass Referrer to Backend During Signup

```javascript
// assets/js/home_hooks.js - Modify authenticateEmail()

async authenticateEmail(email, walletAddress, smartWalletAddress, fingerprintData) {
  const referrerCode = this.getReferrerCode();

  const response = await fetch("/api/auth/email/verify", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      email: email,
      wallet_address: walletAddress,
      smart_wallet_address: smartWalletAddress,
      fingerprint_id: fingerprintData.visitorId,
      fingerprint_confidence: fingerprintData.confidence,
      fingerprint_request_id: fingerprintData.requestId,
      referrer_wallet: referrerCode  // NEW: Pass referrer
    })
  });

  const data = await response.json();

  if (data.success && data.is_new_user) {
    // Clear referrer code after successful signup
    this.clearReferrerCode();
  }

  return data;
}

```

### Step 3: Process Referral in Backend

```elixir
# lib/blockster_v2_web/controllers/auth_controller.ex

def verify_email(conn, params) do
  referrer_wallet = Map.get(params, "referrer_wallet")

  case Accounts.authenticate_email_with_fingerprint(params) do
    {:ok, user, session, is_new} ->
      # Process referral if new user
      if is_new && referrer_wallet do
        Referrals.process_signup_referral(user, referrer_wallet)
      end

      conn
      |> put_session(:user_id, user.id)
      |> json(%{success: true, user: user_json(user), is_new_user: is_new})

    {:error, :fingerprint_conflict, masked_email} ->
      conn |> put_status(:conflict) |> json(%{error: "fingerprint_conflict", masked_email: masked_email})

    {:error, reason} ->
      conn |> put_status(:bad_request) |> json(%{error: reason})
  end
end
```

---

## Smart Contract Changes

### Architecture: How It Works (Like ROGUEBankroll → NFTRewarder)

The referral reward system follows the exact same pattern as the existing NFT reward system:

```
LOSING BET FLOW (Current NFT Rewards)
=====================================
Player loses ROGUE bet
    ↓
BuxBoosterGame.settleBetROGUE()
    ↓
ROGUEBankroll.settleBuxBoosterLosingBet()
    ↓
_sendNFTReward(commitmentHash, wagerAmount)
    ├─ Calculate: wagerAmount × 20 / 10000 = 0.2%
    ├─ Send ROGUE to NFTRewarder via .call{value: amount}()
    └─ Emit NFTRewardSent event

LOSING BET FLOW (New Referral Rewards)
======================================
Player loses ROGUE bet
    ↓
BuxBoosterGame.settleBetROGUE()
    ↓
ROGUEBankroll.settleBuxBoosterLosingBet()
    ↓
_sendNFTReward(commitmentHash, wagerAmount)      // Existing
_sendReferralReward(commitmentHash, player, wagerAmount)  // NEW
    ├─ Lookup referrer: playerReferrers[player]
    ├─ Calculate: wagerAmount × 20 / 10000 = 0.2%
    ├─ Send ROGUE directly to referrer wallet via .call{value: amount}()
    └─ Emit ReferralRewardPaid event

KEY DIFFERENCE FROM NFT REWARDS:
- NFT rewards go to NFTRewarder contract (pooled, distributed later)
- Referral rewards go DIRECTLY to referrer's wallet (instant payout)
```

### BuxBoosterGame.sol - BUX Token Referrer Rewards

#### Storage Changes (Add after line 485)

```solidity
/// @notice Referral reward basis points for BUX token bets (100 = 1%)
uint256 public buxReferralBasisPoints;

/// @notice Mapping from player to their referrer address
mapping(address => address) public playerReferrers;

/// @notice Total referral rewards paid out per token
mapping(address => uint256) public totalReferralRewardsPaid;

/// @notice Event emitted when referral reward is paid
event ReferralRewardPaid(
    bytes32 indexed commitmentHash,
    address indexed referrer,
    address indexed player,
    address token,
    uint256 amount
);

/// @notice Event emitted when player's referrer is set
event ReferrerSet(address indexed player, address indexed referrer);
```

#### Configuration Functions

```solidity
/// @notice Set the referral reward basis points for BUX token
/// @param _basisPoints Referral reward in basis points (100 = 1%, max 1000 = 10%)
function setBuxReferralBasisPoints(uint256 _basisPoints) external onlyOwner {
    require(_basisPoints <= 1000, "Max 10%");
    buxReferralBasisPoints = _basisPoints;
}

/// @notice Set a player's referrer (can only be set once, called by server on signup)
/// @param player The player's smart wallet address
/// @param referrer The referrer's smart wallet address
function setPlayerReferrer(address player, address referrer) external onlyOwner {
    require(playerReferrers[player] == address(0), "Referrer already set");
    require(referrer != address(0), "Invalid referrer");
    require(player != referrer, "Self-referral not allowed");

    playerReferrers[player] = referrer;
    emit ReferrerSet(player, referrer);
}

/// @notice Batch set multiple player referrers (for efficiency)
function setPlayerReferrersBatch(
    address[] calldata players,
    address[] calldata referrers
) external onlyOwner {
    require(players.length == referrers.length, "Array length mismatch");

    for (uint256 i = 0; i < players.length; i++) {
        if (playerReferrers[players[i]] == address(0) &&
            referrers[i] != address(0) &&
            players[i] != referrers[i]) {
            playerReferrers[players[i]] = referrers[i];
            emit ReferrerSet(players[i], referrers[i]);
        }
    }
}

/// @notice Get a player's referrer
function getPlayerReferrer(address player) external view returns (address) {
    return playerReferrers[player];
}
```

#### Modified Settlement - Add Referral Reward on Loss

```solidity
// In _processSettlement(), after the losing bet handling:

if (won) {
    // ... existing winning logic ...
} else {
    // Player lost - house keeps the bet
    payout = 0;
    bet.status = BetStatus.Lost;
    config.houseBalance += bet.amount;

    // NEW: Send referral reward if player has a referrer
    _sendBuxReferralReward(commitmentHash, bet);
}

/// @notice Send BUX referral reward on losing bet (non-blocking like NFT rewards)
function _sendBuxReferralReward(bytes32 commitmentHash, Bet storage bet) private {
    // Skip if no referral program
    if (buxReferralBasisPoints == 0) return;

    address referrer = playerReferrers[bet.player];
    if (referrer == address(0)) return;

    // Calculate referral reward: betAmount * basisPoints / 10000
    uint256 rewardAmount = (bet.amount * buxReferralBasisPoints) / 10000;
    if (rewardAmount == 0) return;

    TokenConfig storage config = tokenConfigs[bet.token];

    // Ensure house has enough balance (non-blocking - skip if not enough)
    if (config.houseBalance < rewardAmount) {
        return;
    }

    // Deduct from house balance
    config.houseBalance -= rewardAmount;

    // Transfer BUX tokens directly to referrer wallet
    IERC20(bet.token).safeTransfer(referrer, rewardAmount);

    // Track total rewards
    totalReferralRewardsPaid[bet.token] += rewardAmount;

    emit ReferralRewardPaid(
        commitmentHash,
        referrer,
        bet.player,
        bet.token,
        rewardAmount
    );
}
```

### ROGUEBankroll.sol - ROGUE Referrer Rewards

This follows the **exact same pattern** as the working `_sendNFTReward` function.

#### Existing _sendNFTReward (for reference - DO NOT MODIFY)

```solidity
// This is the EXISTING code in ROGUEBankroll.sol (lines 1415-1453)
// The referral code below copies this exact pattern

function _sendNFTReward(bytes32 commitmentHash, uint256 wagerAmount) private {
    // Skip if rewards not enabled (nftRewarder is address(0) or rate is 0)
    if (nftRewarder == address(0) || nftRewardBasisPoints == 0) {
        return;
    }

    // Calculate reward: wagerAmount * basisPoints / 10000
    uint256 rewardAmount = (wagerAmount * nftRewardBasisPoints) / 10000;

    if (rewardAmount == 0) {
        return;
    }

    // Interface for NFTRewarder.receiveReward
    (bool success, ) = nftRewarder.call{value: rewardAmount}(
        abi.encodeWithSignature("receiveReward(bytes32)", commitmentHash)
    );

    if (success) {
        totalNFTRewardsPaid += rewardAmount;

        // Update HouseBalance to reflect ROGUE leaving the contract
        houseBalance.total_balance -= rewardAmount;
        houseBalance.net_balance = houseBalance.total_balance - houseBalance.liability;
        houseBalance.actual_balance = address(this).balance;
        // Recalculate pool token price
        if (houseBalance.pool_token_supply > 0) {
            houseBalance.pool_token_price = ((houseBalance.total_balance - houseBalance.unsettled_bets) * 1e18) / houseBalance.pool_token_supply;
        }

        emit NFTRewardSent(commitmentHash, rewardAmount);
    }
    // Non-blocking: if transfer fails, we just skip (no revert)
}
```

#### Storage Changes (Add after line 973, after totalNFTRewardsPaid)

```solidity
// ===== REFERRAL SYSTEM (V8) =====

/// @notice Referral reward basis points (20 = 0.2%, same as NFT rewards)
uint256 public referralBasisPoints;

/// @notice Mapping from player to their referrer address
mapping(address => address) public playerReferrers;

/// @notice Total referral rewards paid all-time
uint256 public totalReferralRewardsPaid;

/// @notice Event for referral rewards (matches NFTRewardSent pattern)
event ReferralRewardPaid(
    bytes32 indexed commitmentHash,
    address indexed referrer,
    address indexed player,
    uint256 amount
);

/// @notice Event for referrer configuration
event ReferrerSet(address indexed player, address indexed referrer);
event ReferralBasisPointsChanged(uint256 oldBasisPoints, uint256 newBasisPoints);
```

#### Configuration Functions (Add after getNFTTotalRewardsPaid)

```solidity
/**
 * @notice Set the referral reward rate in basis points (owner only)
 * @dev 20 basis points = 0.2% of losing bets go to referrer
 *      Matches the NFT reward pattern for consistency
 * @param _basisPoints New basis points value (max 1000 = 10%)
 */
function setReferralBasisPoints(uint256 _basisPoints) external onlyOwner {
    require(_basisPoints <= 1000, "Basis points cannot exceed 10%");
    emit ReferralBasisPointsChanged(referralBasisPoints, _basisPoints);
    referralBasisPoints = _basisPoints;
}

/**
 * @notice Get the current referral reward rate in basis points
 * @return Current basis points value
 */
function getReferralBasisPoints() external view returns (uint256) {
    return referralBasisPoints;
}

/**
 * @notice Get total ROGUE paid to referrers all-time
 * @return Total amount paid to referrers
 */
function getReferralTotalRewardsPaid() external view returns (uint256) {
    return totalReferralRewardsPaid;
}

/**
 * @notice Set a player's referrer (can only be set once)
 * @dev Called by server on signup via BuxMinter service
 * @param player The player's smart wallet address
 * @param referrer The referrer's smart wallet address
 */
function setPlayerReferrer(address player, address referrer) external onlyOwner {
    require(playerReferrers[player] == address(0), "Referrer already set");
    require(referrer != address(0), "Invalid referrer");
    require(player != referrer, "Self-referral not allowed");

    playerReferrers[player] = referrer;
    emit ReferrerSet(player, referrer);
}

/**
 * @notice Batch set multiple player referrers (for efficiency)
 * @param players Array of player addresses
 * @param referrers Array of corresponding referrer addresses
 */
function setPlayerReferrersBatch(
    address[] calldata players,
    address[] calldata referrers
) external onlyOwner {
    require(players.length == referrers.length, "Array length mismatch");

    for (uint256 i = 0; i < players.length; i++) {
        if (playerReferrers[players[i]] == address(0) &&
            referrers[i] != address(0) &&
            players[i] != referrers[i]) {
            playerReferrers[players[i]] = referrers[i];
            emit ReferrerSet(players[i], referrers[i]);
        }
    }
}

/**
 * @notice Get a player's referrer
 * @param player The player's address
 * @return The referrer's address (or address(0) if none)
 */
function getPlayerReferrer(address player) external view returns (address) {
    return playerReferrers[player];
}
```

#### New _sendReferralReward Function (Exact copy of _sendNFTReward pattern)

```solidity
/**
 * @notice Send referral reward on losing ROGUE bet
 * @dev EXACT COPY of _sendNFTReward pattern:
 *      - Non-blocking (failure doesn't revert bet settlement)
 *      - Updates house balance tracking
 *      - Emits event on success
 *
 * KEY DIFFERENCE from NFT rewards:
 *      - NFT: calls nftRewarder.receiveReward() (pooled distribution)
 *      - Referral: sends directly to referrer wallet (instant payout)
 *
 * @param commitmentHash The bet's commitment hash (for event tracking)
 * @param player The player who lost the bet
 * @param wagerAmount The amount wagered
 */
function _sendReferralReward(
    bytes32 commitmentHash,
    address player,
    uint256 wagerAmount
) private {
    // Skip if rewards not enabled (same check as NFT rewards)
    if (referralBasisPoints == 0) {
        return;
    }

    address referrer = playerReferrers[player];
    if (referrer == address(0)) {
        return;
    }

    // Calculate reward: wagerAmount * basisPoints / 10000 (same formula as NFT)
    uint256 rewardAmount = (wagerAmount * referralBasisPoints) / 10000;

    if (rewardAmount == 0) {
        return;
    }

    // Send ROGUE directly to referrer wallet (NOT to a contract like NFT rewards)
    (bool success, ) = payable(referrer).call{value: rewardAmount}("");

    if (success) {
        totalReferralRewardsPaid += rewardAmount;

        // Update HouseBalance (EXACT SAME as _sendNFTReward)
        houseBalance.total_balance -= rewardAmount;
        houseBalance.net_balance = houseBalance.total_balance - houseBalance.liability;
        houseBalance.actual_balance = address(this).balance;
        // Recalculate pool token price
        if (houseBalance.pool_token_supply > 0) {
            houseBalance.pool_token_price = ((houseBalance.total_balance - houseBalance.unsettled_bets) * 1e18) / houseBalance.pool_token_supply;
        }

        emit ReferralRewardPaid(commitmentHash, referrer, player, rewardAmount);
    }
    // Non-blocking: if transfer fails, we just skip (no revert)
}
```

#### Modified settleBuxBoosterLosingBet (Add one line after _sendNFTReward)

```solidity
// In settleBuxBoosterLosingBet(), find line 1634 which calls _sendNFTReward:
//
// BEFORE (existing):
//     _sendNFTReward(commitmentHash, wagerAmount);
//
// AFTER (add one line):
//     _sendNFTReward(commitmentHash, wagerAmount);
//     _sendReferralReward(commitmentHash, player, wagerAmount);  // NEW

function settleBuxBoosterLosingBet(
    address player,
    bytes32 commitmentHash,
    uint256 wagerAmount,
    int8 difficulty,
    uint8[] calldata predictions,
    uint8[] calldata results,
    uint256 nonce,
    uint256 maxPayout
) external onlyBuxBooster returns(bool) {
    // ... existing house balance updates (lines 1614-1619) ...

    // ... existing player stats updates (lines 1621-1626) ...

    // ... existing global accounting (lines 1628-1630) ...

    // V7: Send NFT rewards (existing line 1634)
    _sendNFTReward(commitmentHash, wagerAmount);

    // V8: Send referral rewards (NEW - add this line)
    _sendReferralReward(commitmentHash, player, wagerAmount);

    // Emit events (existing lines 1637-1638)
    emit BuxBoosterLosingBet(player, commitmentHash, wagerAmount);
    emit BuxBoosterLossDetails(commitmentHash, difficulty, predictions, results, nonce);

    return true;
}
```

---

## Event Polling System

This is copied from the high-rollers-elixir `RogueRewardPoller` pattern - the same approach used to detect NFT reward events.

### ReferralRewardPoller GenServer

```elixir
# lib/blockster_v2/referral_reward_poller.ex

defmodule BlocksterV2.ReferralRewardPoller do
  @moduledoc """
  Polls Rogue Chain for ReferralRewardPaid events from BuxBoosterGame and ROGUEBankroll.

  Follows the same pattern as high-rollers-elixir RogueRewardPoller:
  - Polls every 1 second for near-instant UI updates
  - Queries up to 5,000 blocks per poll
  - Persists last processed block in Mnesia
  - Non-blocking polling with overlap prevention
  - Backfills from deploy block on first run
  """
  use GenServer
  require Logger

  alias BlocksterV2.Referrals

  @poll_interval_ms 1_000  # 1 second (same as RogueRewardPoller)
  @max_blocks_per_query 5_000  # Rogue Chain is fast
  @backfill_chunk_size 10_000
  @backfill_delay_ms 100

  # Contract addresses
  @bux_booster_address "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B"
  @rogue_bankroll_address "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd"
  @rpc_url "https://rpc.roguechain.io/rpc"

  # Deploy block (set to block when V6/V8 with referrals is deployed)
  @deploy_block 0  # TODO: Set after contract deployment

  # Event topic: keccak256("ReferralRewardPaid(bytes32,address,address,address,uint256)")
  # For BuxBoosterGame (includes token address)
  @bux_referral_topic "0x" <> (
    ExKeccak.hash_256("ReferralRewardPaid(bytes32,address,address,address,uint256)")
    |> Base.encode16(case: :lower)
  )

  # Event topic: keccak256("ReferralRewardPaid(bytes32,address,address,uint256)")
  # For ROGUEBankroll (no token address - always ROGUE)
  @rogue_referral_topic "0x" <> (
    ExKeccak.hash_256("ReferralRewardPaid(bytes32,address,address,uint256)")
    |> Base.encode16(case: :lower)
  )

  # ----- Public API -----

  def start_link(opts) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
  end

  # ----- GenServer Callbacks -----

  def init(_opts) do
    Logger.info("[ReferralRewardPoller] Starting...")

    # Wait for Mnesia to be ready
    Process.send_after(self(), :init_after_mnesia, 2_000)

    {:ok, %{
      last_block: nil,
      polling: false,
      initialized: false
    }}
  end

  def handle_info(:init_after_mnesia, state) do
    last_block = get_last_processed_block()
    current_block = get_current_block()

    Logger.info("[ReferralRewardPoller] Last processed: #{last_block}, Current: #{current_block}")

    # Check if we need to backfill
    if last_block < current_block - @max_blocks_per_query do
      spawn(fn -> backfill_events(last_block, current_block) end)
    end

    schedule_poll()
    {:noreply, %{state | last_block: last_block, initialized: true}}
  end

  def handle_info(:poll, %{polling: true} = state) do
    # Already polling - skip this round (prevents overlap)
    schedule_poll()
    {:noreply, state}
  end

  def handle_info(:poll, %{initialized: false} = state) do
    schedule_poll()
    {:noreply, state}
  end

  def handle_info(:poll, state) do
    state = %{state | polling: true}
    start_time = System.monotonic_time(:millisecond)

    {new_state, events_count} = poll_events(state)

    duration = System.monotonic_time(:millisecond) - start_time
    if events_count > 0 do
      Logger.info("[ReferralRewardPoller] Processed #{events_count} events in #{duration}ms")
    end

    state = %{new_state | polling: false}
    schedule_poll()
    {:noreply, state}
  end

  # ----- Polling Logic -----

  defp poll_events(state) do
    current_block = get_current_block()
    from_block = state.last_block + 1
    to_block = min(from_block + @max_blocks_per_query - 1, current_block)

    if from_block > current_block do
      {state, 0}
    else
      # Poll both contracts
      bux_events = fetch_bux_referral_events(from_block, to_block)
      rogue_events = fetch_rogue_referral_events(from_block, to_block)

      # Process events
      Enum.each(bux_events, &process_bux_referral_event/1)
      Enum.each(rogue_events, &process_rogue_referral_event/1)

      # Save progress
      save_last_processed_block(to_block)

      {%{state | last_block: to_block}, length(bux_events) + length(rogue_events)}
    end
  end

  defp fetch_bux_referral_events(from_block, to_block) do
    params = %{
      address: @bux_booster_address,
      topics: [@bux_referral_topic],
      fromBlock: int_to_hex(from_block),
      toBlock: int_to_hex(to_block)
    }

    case rpc_call("eth_getLogs", [params]) do
      {:ok, logs} -> Enum.map(logs, &parse_bux_referral_log/1)
      {:error, _} -> []
    end
  end

  defp fetch_rogue_referral_events(from_block, to_block) do
    params = %{
      address: @rogue_bankroll_address,
      topics: [@rogue_referral_topic],
      fromBlock: int_to_hex(from_block),
      toBlock: int_to_hex(to_block)
    }

    case rpc_call("eth_getLogs", [params]) do
      {:ok, logs} -> Enum.map(logs, &parse_rogue_referral_log/1)
      {:error, _} -> []
    end
  end

  # ----- Event Parsing -----

  defp parse_bux_referral_log(log) do
    # Topics: [event_sig, commitmentHash, referrer, player]
    [_sig, commitment_hash, referrer_topic, player_topic] = log["topics"]

    # Data: [token (address), amount (uint256)]
    data = log["data"] |> String.slice(2..-1//1) |> Base.decode16!(case: :mixed)
    <<_padding::binary-size(12), token_bytes::binary-size(20), amount::unsigned-256>> = data

    %{
      commitment_hash: commitment_hash,
      referrer: decode_address_topic(referrer_topic),
      player: decode_address_topic(player_topic),
      token: "0x" <> Base.encode16(token_bytes, case: :lower),
      amount: amount,
      tx_hash: log["transactionHash"],
      block_number: hex_to_int(log["blockNumber"])
    }
  end

  defp parse_rogue_referral_log(log) do
    # Topics: [event_sig, commitmentHash, referrer, player]
    [_sig, commitment_hash, referrer_topic, player_topic] = log["topics"]

    # Data: [amount (uint256)]
    data = log["data"] |> String.slice(2..-1//1) |> Base.decode16!(case: :mixed)
    <<amount::unsigned-256>> = data

    %{
      commitment_hash: commitment_hash,
      referrer: decode_address_topic(referrer_topic),
      player: decode_address_topic(player_topic),
      token: nil,  # ROGUE (native token)
      amount: amount,
      tx_hash: log["transactionHash"],
      block_number: hex_to_int(log["blockNumber"])
    }
  end

  defp decode_address_topic(topic) do
    # Topic is 32 bytes, address is last 20 bytes
    "0x" <> address_hex = topic
    address_bytes = address_hex |> String.slice(-40, 40)
    "0x" <> String.downcase(address_bytes)
  end

  # ----- Event Processing -----

  defp process_bux_referral_event(event) do
    # Convert wei to token amount (18 decimals)
    amount = event.amount / :math.pow(10, 18)

    Referrals.record_bet_loss_earning(%{
      referrer_wallet: event.referrer,
      referee_wallet: event.player,
      amount: amount,
      token: "BUX",
      commitment_hash: event.commitment_hash,
      tx_hash: event.tx_hash
    })
  end

  defp process_rogue_referral_event(event) do
    # Convert wei to ROGUE amount (18 decimals)
    amount = event.amount / :math.pow(10, 18)

    Referrals.record_bet_loss_earning(%{
      referrer_wallet: event.referrer,
      referee_wallet: event.player,
      amount: amount,
      token: "ROGUE",
      commitment_hash: event.commitment_hash,
      tx_hash: event.tx_hash
    })
  end

  # ----- Backfill (on first run or after long downtime) -----

  defp backfill_events(from_block, to_block) do
    Logger.info("[ReferralRewardPoller] Backfilling from #{from_block} to #{to_block}")

    chunk_starts = Stream.iterate(from_block, &(&1 + @backfill_chunk_size))
    |> Enum.take_while(&(&1 <= to_block))

    Enum.each(chunk_starts, fn chunk_start ->
      chunk_end = min(chunk_start + @backfill_chunk_size - 1, to_block)

      # Fetch and process (skip broadcasts during backfill for performance)
      bux_events = fetch_bux_referral_events(chunk_start, chunk_end)
      rogue_events = fetch_rogue_referral_events(chunk_start, chunk_end)

      Enum.each(bux_events, fn event ->
        process_bux_referral_event_backfill(event)
      end)
      Enum.each(rogue_events, fn event ->
        process_rogue_referral_event_backfill(event)
      end)

      # Save progress
      save_last_processed_block(chunk_end)

      # Rate limiting
      Process.sleep(@backfill_delay_ms)
    end)

    Logger.info("[ReferralRewardPoller] Backfill complete")
  end

  defp process_bux_referral_event_backfill(event) do
    amount = event.amount / :math.pow(10, 18)
    Referrals.record_bet_loss_earning_backfill(%{
      referrer_wallet: event.referrer,
      referee_wallet: event.player,
      amount: amount,
      token: "BUX",
      commitment_hash: event.commitment_hash,
      tx_hash: event.tx_hash
    })
  end

  defp process_rogue_referral_event_backfill(event) do
    amount = event.amount / :math.pow(10, 18)
    Referrals.record_bet_loss_earning_backfill(%{
      referrer_wallet: event.referrer,
      referee_wallet: event.player,
      amount: amount,
      token: "ROGUE",
      commitment_hash: event.commitment_hash,
      tx_hash: event.tx_hash
    })
  end

  # ----- Mnesia State Persistence -----

  defp get_last_processed_block do
    case :mnesia.dirty_read(:referral_poller_state, :rogue) do
      [{:referral_poller_state, :rogue, last_block, _updated_at}] -> last_block
      [] -> @deploy_block
    end
  end

  defp save_last_processed_block(block) do
    record = {:referral_poller_state, :rogue, block, System.system_time(:second)}
    :mnesia.dirty_write(record)
  end

  # ----- RPC Helpers -----

  defp get_current_block do
    case rpc_call("eth_blockNumber", []) do
      {:ok, hex} -> hex_to_int(hex)
      {:error, _} -> 0
    end
  end

  defp rpc_call(method, params) do
    body = Jason.encode!(%{
      jsonrpc: "2.0",
      method: method,
      params: params,
      id: 1
    })

    case Req.post(@rpc_url, body: body, headers: [{"content-type", "application/json"}],
                  receive_timeout: 30_000, connect_options: [transport_opts: [inet_backend: :inet]]) do
      {:ok, %{status: 200, body: %{"result" => result}}} -> {:ok, result}
      {:ok, %{body: %{"error" => error}}} -> {:error, error}
      {:error, reason} -> {:error, reason}
    end
  end

  defp int_to_hex(n), do: "0x" <> Integer.to_string(n, 16)
  defp hex_to_int("0x" <> hex), do: String.to_integer(hex, 16)

  defp schedule_poll do
    Process.send_after(self(), :poll, @poll_interval_ms)
  end
end
```

---

## Backend Implementation

### Referrals Module (Mnesia-based)

```elixir
# lib/blockster_v2/referrals.ex

defmodule BlocksterV2.Referrals do
  @moduledoc """
  Handles referral tracking, rewards, and earnings using Mnesia for storage.
  """
  require Logger

  alias BlocksterV2.{Repo, Accounts, BuxMinter}
  alias BlocksterV2.Accounts.User

  @signup_reward 100  # BUX
  @phone_verified_reward 100  # BUX

  # ----- Signup Referral Processing -----

  @doc """
  Process a new user signup with a referral code.
  Links the referrer in both Mnesia and PostgreSQL, then mints signup reward.
  """
  def process_signup_referral(new_user, referrer_wallet) when is_binary(referrer_wallet) do
    referrer_wallet = String.downcase(referrer_wallet)

    # Prevent self-referral
    if new_user.smart_wallet_address &&
       String.downcase(new_user.smart_wallet_address) == referrer_wallet do
      {:error, :self_referral}
    else
      # Find referrer by smart wallet address
      case Repo.get_by(User, smart_wallet_address: referrer_wallet) do
        nil ->
          {:error, :referrer_not_found}

        referrer ->
          # Update PostgreSQL user record
          new_user
          |> Ecto.Changeset.change(%{
            referrer_id: referrer.id,
            referred_at: DateTime.utc_now()
          })
          |> Repo.update!()

          # Store in Mnesia (with both wallet addresses for blockchain event matching)
          now = System.system_time(:second)
          referee_wallet = String.downcase(new_user.smart_wallet_address || "")
          referral_record = {:referrals, new_user.id, referrer.id, referrer_wallet, referee_wallet, now, false}
          :mnesia.dirty_write(referral_record)

          # Create earning and mint reward (pass wallets for Mnesia storage)
          create_signup_earning(referrer, new_user, referrer_wallet, referee_wallet)

          # Queue on-chain referrer sync (async)
          sync_referrer_to_contracts(new_user.smart_wallet_address, referrer_wallet)

          {:ok, referrer}
      end
    end
  end

  defp create_signup_earning(referrer, referee, referrer_wallet, referee_wallet) do
    now = System.system_time(:second)
    id = UUID.uuid4()

    # Insert Mnesia earning record with wallet addresses (no DB lookup needed later)
    earning_record = {:referral_earnings, id, referrer.id, referrer_wallet, referee_wallet,
                      :signup, @signup_reward, "BUX", nil, nil, now}
    :mnesia.dirty_write(earning_record)

    # Update stats
    update_referrer_stats(referrer.id, :signup, @signup_reward, "BUX")

    # Mint BUX to referrer
    mint_referral_reward(referrer_wallet, @signup_reward, "BUX", referrer.id, :signup)

    # Broadcast real-time update
    broadcast_referral_earning(referrer.id, %{
      type: :signup,
      amount: @signup_reward,
      token: "BUX",
      referee_wallet: referee_wallet,
      timestamp: now
    })
  end

  # ----- Phone Verification Reward -----

  @doc """
  Process phone verification reward for referrer.
  Called from PhoneVerification.verify_code/2 after successful verification.

  Mnesia-only - no PostgreSQL queries.
  """
  def process_phone_verification_reward(user_id) do
    # Check if user has a referrer (from Mnesia)
    case :mnesia.dirty_read(:referrals, user_id) do
      [] ->
        :no_referrer

      [{:referrals, ^user_id, referrer_id, referrer_wallet, referee_wallet, _at, _synced}] ->
        # Check if already rewarded (look for existing phone_verified earning)
        existing = :mnesia.dirty_index_read(:referral_earnings, referrer_id, :referrer_id)
        |> Enum.any?(fn record ->
          elem(record, 5) == :phone_verified and elem(record, 4) == referee_wallet
        end)

        if existing do
          {:error, :already_rewarded}
        else
          create_phone_verification_earning(referrer_id, referrer_wallet, referee_wallet)
        end
    end
  end

  defp create_phone_verification_earning(referrer_id, referrer_wallet, referee_wallet) do
    now = System.system_time(:second)
    id = UUID.uuid4()

    # Store with wallet addresses (no DB lookup needed later)
    earning_record = {:referral_earnings, id, referrer_id, referrer_wallet, referee_wallet,
                      :phone_verified, @phone_verified_reward, "BUX", nil, nil, now}
    :mnesia.dirty_write(earning_record)

    update_referrer_stats(referrer_id, :phone_verified, @phone_verified_reward, "BUX")
    mint_referral_reward(referrer_wallet, @phone_verified_reward, "BUX", referrer_id, :phone_verified)

    broadcast_referral_earning(referrer_id, %{
      type: :phone_verified,
      amount: @phone_verified_reward,
      token: "BUX",
      referee_wallet: referee_wallet,
      timestamp: now
    })

    {:ok, referrer}
  end

  # ----- Bet Loss Earnings (from blockchain events) -----

  @doc """
  Record a bet loss earning from smart contract event.
  Called by ReferralRewardPoller when ReferralRewardPaid event is detected.

  Uses Mnesia-only lookups - no PostgreSQL queries.
  """
  def record_bet_loss_earning(attrs) do
    %{
      referrer_wallet: referrer_wallet,
      referee_wallet: referee_wallet,
      amount: amount,
      token: token,
      commitment_hash: commitment_hash,
      tx_hash: tx_hash
    } = attrs

    referrer_wallet = String.downcase(referrer_wallet)
    referee_wallet = String.downcase(referee_wallet)

    # Check for duplicate (idempotent)
    existing = :mnesia.dirty_index_read(:referral_earnings, commitment_hash, :commitment_hash)
    if existing != [] do
      :duplicate
    else
      # Look up referrer_id from Mnesia (no PostgreSQL!)
      case get_referrer_by_referee_wallet(referee_wallet) do
        {:ok, %{referrer_id: referrer_id, referrer_wallet: stored_referrer_wallet}} ->
          # Verify the referrer wallet matches what blockchain sent
          if stored_referrer_wallet == referrer_wallet do
            now = System.system_time(:second)
            id = UUID.uuid4()
            earning_type = if token == "ROGUE", do: :rogue_bet_loss, else: :bux_bet_loss

            # Store with wallet addresses for display (no DB lookup needed later)
            earning_record = {:referral_earnings, id, referrer_id, referrer_wallet, referee_wallet,
                              earning_type, amount, token, tx_hash, commitment_hash, now}
            :mnesia.dirty_write(earning_record)

            update_referrer_stats(referrer_id, earning_type, amount, token)

            # Broadcast real-time update for earnings table
            broadcast_referral_earning(referrer_id, %{
              type: earning_type,
              amount: amount,
              token: token,
              referee_wallet: referee_wallet,
              tx_hash: tx_hash,
              timestamp: now
            })

            # Sync balances from blockchain and broadcast to update header/member page
            # (the tokens were already sent on-chain by the smart contract)
            BuxMinter.sync_user_balances_async(referrer_id, referrer_wallet)

            :ok
          else
            Logger.warning("[Referrals] Referrer wallet mismatch: expected #{stored_referrer_wallet}, got #{referrer_wallet}")
            :referrer_mismatch
          end

        :not_found ->
          Logger.warning("[Referrals] No referral found for referee wallet: #{referee_wallet}")
          :referral_not_found
      end
    end
  end

  @doc """
  Same as record_bet_loss_earning but skips broadcast (used during backfill).
  Uses Mnesia-only lookups - no PostgreSQL queries.
  """
  def record_bet_loss_earning_backfill(attrs) do
    %{
      referrer_wallet: referrer_wallet,
      referee_wallet: referee_wallet,
      amount: amount,
      token: token,
      commitment_hash: commitment_hash,
      tx_hash: tx_hash
    } = attrs

    referrer_wallet = String.downcase(referrer_wallet)
    referee_wallet = String.downcase(referee_wallet)

    # Check for duplicate
    existing = :mnesia.dirty_index_read(:referral_earnings, commitment_hash, :commitment_hash)
    if existing != [] do
      :duplicate
    else
      case get_referrer_by_referee_wallet(referee_wallet) do
        {:ok, %{referrer_id: referrer_id, referrer_wallet: stored_referrer_wallet}} ->
          if stored_referrer_wallet == referrer_wallet do
            now = System.system_time(:second)
            id = UUID.uuid4()
            earning_type = if token == "ROGUE", do: :rogue_bet_loss, else: :bux_bet_loss

            earning_record = {:referral_earnings, id, referrer_id, referrer_wallet, referee_wallet,
                              earning_type, amount, token, tx_hash, commitment_hash, now}
            :mnesia.dirty_write(earning_record)

            update_referrer_stats(referrer_id, earning_type, amount, token)
            :ok
          else
            :referrer_mismatch
          end

        :not_found ->
          :referral_not_found
      end
    end
  end

  # ----- Stats Management -----

  defp update_referrer_stats(referrer_id, earning_type, amount, token) do
    now = System.system_time(:second)

    case :mnesia.dirty_read(:referral_stats, referrer_id) do
      [] ->
        # Create new stats record
        {total_refs, verified, bux, rogue} = case {earning_type, token} do
          {:signup, "BUX"} -> {1, 0, amount, 0.0}
          {:phone_verified, "BUX"} -> {0, 1, amount, 0.0}
          {_, "BUX"} -> {0, 0, amount, 0.0}
          {_, "ROGUE"} -> {0, 0, 0.0, amount}
        end
        record = {:referral_stats, referrer_id, total_refs, verified, bux, rogue, now}
        :mnesia.dirty_write(record)

      [{:referral_stats, ^referrer_id, total_refs, verified, bux, rogue, _updated}] ->
        {new_refs, new_verified, new_bux, new_rogue} = case {earning_type, token} do
          {:signup, "BUX"} -> {total_refs + 1, verified, bux + amount, rogue}
          {:phone_verified, "BUX"} -> {total_refs, verified + 1, bux + amount, rogue}
          {_, "BUX"} -> {total_refs, verified, bux + amount, rogue}
          {_, "ROGUE"} -> {total_refs, verified, bux, rogue + amount}
        end
        record = {:referral_stats, referrer_id, new_refs, new_verified, new_bux, new_rogue, now}
        :mnesia.dirty_write(record)
    end
  end

  # ----- Query Functions -----

  def get_referrer_stats(user_id) do
    case :mnesia.dirty_read(:referral_stats, user_id) do
      [{:referral_stats, ^user_id, total_refs, verified, bux, rogue, _updated}] ->
        %{
          total_referrals: total_refs,
          verified_referrals: verified,
          total_bux_earned: bux,
          total_rogue_earned: rogue
        }
      [] ->
        %{
          total_referrals: 0,
          verified_referrals: 0,
          total_bux_earned: 0.0,
          total_rogue_earned: 0.0
        }
    end
  end

  @doc """
  List all referrals for a user. Mnesia-only - no PostgreSQL queries.
  Returns referee wallet addresses directly (use for UI display).
  """
  def list_referrals(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    # Get all referral records where this user is the referrer
    :mnesia.dirty_index_read(:referrals, user_id, :referrer_id)
    |> Enum.sort_by(fn {:referrals, _, _, _, _, referred_at, _} -> referred_at end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {:referrals, referee_id, _, _, referee_wallet, referred_at, _} ->
      # Check if referee has verified phone (from referral_earnings)
      phone_verified = :mnesia.dirty_index_read(:referral_earnings, referee_id, :referrer_id)
      |> Enum.any?(fn record ->
        elem(record, 5) == :phone_verified  # earning_type at index 5
      end)

      %{
        referee_id: referee_id,
        referee_wallet: referee_wallet,
        referred_at: DateTime.from_unix!(referred_at),
        phone_verified: phone_verified
      }
    end)
  end

  @doc """
  List referral earnings for a user. Mnesia-only - no PostgreSQL queries.
  Wallet addresses are stored directly in earnings records.
  """
  def list_referral_earnings(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    offset = Keyword.get(opts, :offset, 0)

    :mnesia.dirty_index_read(:referral_earnings, user_id, :referrer_id)
    |> Enum.sort_by(fn {:referral_earnings, _, _, _, _, _, _, _, _, _, timestamp} -> timestamp end, :desc)
    |> Enum.drop(offset)
    |> Enum.take(limit)
    |> Enum.map(fn {:referral_earnings, id, _referrer_id, _referrer_wallet, referee_wallet, type, amount, token, tx_hash, _commitment, timestamp} ->
      %{
        id: id,
        earning_type: type,
        amount: amount,
        token: token,
        tx_hash: tx_hash,
        timestamp: DateTime.from_unix!(timestamp),
        referee_wallet: referee_wallet  # Wallet stored directly, no DB lookup!
      }
    end)
  end

  # ----- Helper Functions -----

  defp mint_referral_reward(referrer_wallet, amount, token, referrer_id, reason) do
    if referrer_wallet && referrer_wallet != "" do
      Task.start(fn ->
        case BuxMinter.mint_bux(
          referrer_wallet,
          amount,
          referrer_id,
          nil,  # No specific post/referee ID needed
          reason,
          token
        ) do
          {:ok, _} ->
            # Sync balances from blockchain and broadcast to update header/member page in real-time
            BuxMinter.sync_user_balances_async(referrer_id, referrer_wallet)
          {:error, _} ->
            :ok
        end
      end)
    end
  end

  defp sync_referrer_to_contracts(player_wallet, referrer_wallet) do
    Task.start(fn ->
      case BuxMinter.set_player_referrer(player_wallet, referrer_wallet) do
        {:ok, _} ->
          # Mark as synced in Mnesia
          case :mnesia.dirty_match_object({:referrals, :_, :_, referrer_wallet, :_, :_, :_}) do
            [record] ->
              updated = put_elem(record, 6, true)  # on_chain_synced is now at index 6
              :mnesia.dirty_write(updated)
            _ -> :ok
          end
        {:error, reason} ->
          Logger.error("[Referrals] Failed to sync referrer to contracts: #{inspect(reason)}")
      end
    end)
  end

  defp broadcast_referral_earning(referrer_id, payload) do
    Phoenix.PubSub.broadcast(
      BlocksterV2.PubSub,
      "referral:#{referrer_id}",
      {:referral_earning, payload}
    )
  end
end
```

### BuxMinter Addition

```elixir
# lib/blockster_v2/bux_minter.ex - Add function

def set_player_referrer(player_wallet, referrer_wallet) do
  url = "#{bux_minter_url()}/set-player-referrer"

  body = Jason.encode!(%{
    player: player_wallet,
    referrer: referrer_wallet
  })

  case Req.post(url, body: body, headers: [{"content-type", "application/json"}],
                receive_timeout: 30_000, connect_options: [transport_opts: [inet_backend: :inet]]) do
    {:ok, %{status: 200, body: body}} ->
      {:ok, body}
    {:ok, %{status: status, body: body}} ->
      Logger.error("[BuxMinter] set_player_referrer failed: #{status} - #{inspect(body)}")
      {:error, body}
    {:error, reason} ->
      Logger.error("[BuxMinter] set_player_referrer error: #{inspect(reason)}")
      {:error, reason}
  end
end
```

### BuxMinter Service Endpoint

```javascript
// bux-minter/index.js - Add new endpoint

// Set player referrer on both contracts
app.post('/set-player-referrer', async (req, res) => {
  try {
    const { player, referrer } = req.body;

    // Validate addresses
    if (!ethers.isAddress(player) || !ethers.isAddress(referrer)) {
      return res.status(400).json({ error: 'Invalid address format' });
    }

    // Set on BuxBoosterGame
    const buxBoosterTx = await buxBoosterContract.setPlayerReferrer(player, referrer);
    await buxBoosterTx.wait();

    // Set on ROGUEBankroll
    const rogueBankrollTx = await rogueBankrollContract.setPlayerReferrer(player, referrer);
    await rogueBankrollTx.wait();

    console.log(`[setPlayerReferrer] Player ${player} -> Referrer ${referrer}`);

    res.json({
      success: true,
      buxBoosterTx: buxBoosterTx.hash,
      rogueBankrollTx: rogueBankrollTx.hash
    });
  } catch (error) {
    console.error('[setPlayerReferrer] Error:', error);
    res.status(500).json({ error: error.message });
  }
});
```

---

## Members Page UI

### Replace Settings Tab with Refer Tab

```elixir
# lib/blockster_v2_web/live/member_live/show.ex

# In mount/3 - add referral data loading and PubSub subscription
def mount(%{"id" => id}, _session, socket) do
  member = Accounts.get_user(id) |> Repo.preload(:phone_verification)
  current_user = socket.assigns[:current_user]

  socket = socket
    |> assign(:member, member)
    |> assign(:tab, "activity")
    |> assign_referral_data()

  # Subscribe to real-time referral updates (only for own profile)
  if connected?(socket) && current_user && current_user.id == member.id do
    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "referral:#{member.id}")
  end

  {:ok, socket}
end

defp assign_referral_data(socket) do
  current_user = socket.assigns[:current_user]
  member = socket.assigns.member

  if current_user && current_user.id == member.id do
    user_id = current_user.id
    wallet_address = member.smart_wallet_address

    socket
    |> assign(:referral_link, generate_referral_link(wallet_address))
    |> assign(:referral_stats, Referrals.get_referrer_stats(user_id))
    |> assign(:referrals, Referrals.list_referrals(user_id, limit: 20))
    |> assign(:referral_earnings, Referrals.list_referral_earnings(user_id, limit: 50))
  else
    socket
    |> assign(:referral_link, nil)
    |> assign(:referral_stats, nil)
    |> assign(:referrals, [])
    |> assign(:referral_earnings, [])
  end
end

defp generate_referral_link(wallet_address) do
  base_url = BlocksterV2Web.Endpoint.url()
  "#{base_url}/?ref=#{wallet_address}"
end

# Handle real-time referral earning updates
def handle_info({:referral_earning, earning}, socket) do
  current_earnings = socket.assigns.referral_earnings
  current_stats = socket.assigns.referral_stats

  # Prepend new earning to list
  updated_earnings = [earning_to_map(earning) | current_earnings]

  # Update stats
  updated_stats = update_stats_from_earning(current_stats, earning)

  {:noreply,
   socket
   |> assign(:referral_earnings, updated_earnings)
   |> assign(:referral_stats, updated_stats)}
end

defp earning_to_map(earning) do
  %{
    id: UUID.uuid4(),
    earning_type: earning.type,
    amount: earning.amount,
    token: earning.token,
    tx_hash: Map.get(earning, :tx_hash),
    timestamp: DateTime.from_unix!(earning.timestamp),
    referee_wallet: earning.referee_wallet  # Wallet stored directly, no DB lookup!
  }
end

defp update_stats_from_earning(stats, earning) do
  case earning.token do
    "BUX" ->
      %{stats | total_bux_earned: stats.total_bux_earned + earning.amount}
    "ROGUE" ->
      %{stats | total_rogue_earned: stats.total_rogue_earned + earning.amount}
  end
end

# Handle copy link event
def handle_event("copy_referral_link", _params, socket) do
  referral_link = socket.assigns.referral_link
  {:noreply, push_event(socket, "copy_to_clipboard", %{text: referral_link})}
end

# Load more earnings (infinite scroll)
def handle_event("load_more_earnings", _params, socket) do
  current_earnings = socket.assigns.referral_earnings
  user_id = socket.assigns.current_user.id
  offset = length(current_earnings)

  more_earnings = Referrals.list_referral_earnings(user_id, limit: 50, offset: offset)

  if Enum.empty?(more_earnings) do
    {:reply, %{end_reached: true}, socket}
  else
    {:noreply, assign(socket, :referral_earnings, current_earnings ++ more_earnings)}
  end
end
```

### Template (show.html.heex)

```heex
<%!-- Tab buttons - Replace "Settings" with "Refer" --%>
<%= if @is_own_profile do %>
  <button
    phx-click="switch_tab"
    phx-value-tab="refer"
    class={"cursor-pointer px-4 py-2 rounded-full text-sm font-medium transition-colors #{if @tab == "refer", do: "bg-black text-white", else: "bg-gray-100 text-gray-700 hover:bg-gray-200"}"}
  >
    Refer
  </button>
<% end %>

<%!-- Refer Tab Content --%>
<%= if @tab == "refer" && @is_own_profile do %>
  <div class="space-y-6">
    <%!-- Referral Link Section --%>
    <div class="bg-white rounded-xl p-6 border border-gray-200">
      <h3 class="text-lg font-haas_medium_65 mb-2">Your Referral Link</h3>
      <p class="text-sm text-gray-600 mb-4">
        Share this link with friends. Earn <span class="font-bold text-green-600">100 BUX</span> for each signup,
        and another <span class="font-bold text-green-600">100 BUX</span> when they verify their phone.
      </p>

      <div class="flex gap-2">
        <input
          type="text"
          readonly
          value={@referral_link}
          class="flex-1 px-4 py-2 bg-gray-50 border border-gray-200 rounded-lg text-sm font-mono"
        />
        <button
          phx-click="copy_referral_link"
          class="cursor-pointer px-4 py-2 bg-black text-white rounded-lg text-sm font-medium hover:bg-gray-800 transition-colors"
        >
          Copy
        </button>
      </div>

      <p class="mt-3 text-xs text-gray-500">
        Plus earn <span class="font-bold">1%</span> of losing BUX bets and
        <span class="font-bold">0.2%</span> of losing ROGUE bets from your referrals!
      </p>
    </div>

    <%!-- Stats Cards --%>
    <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
      <div class="bg-white rounded-xl p-4 border border-gray-200">
        <div class="text-2xl font-haas_medium_65"><%= @referral_stats.total_referrals %></div>
        <div class="text-sm text-gray-500">Total Referrals</div>
      </div>
      <div class="bg-white rounded-xl p-4 border border-gray-200">
        <div class="text-2xl font-haas_medium_65"><%= @referral_stats.verified_referrals %></div>
        <div class="text-sm text-gray-500">Verified</div>
      </div>
      <div class="bg-white rounded-xl p-4 border border-gray-200">
        <div class="text-2xl font-haas_medium_65 text-green-600">
          <%= format_number(@referral_stats.total_bux_earned) %> BUX
        </div>
        <div class="text-sm text-gray-500">BUX Earned</div>
      </div>
      <div class="bg-white rounded-xl p-4 border border-gray-200">
        <div class="text-2xl font-haas_medium_65 text-blue-600">
          <%= format_number(@referral_stats.total_rogue_earned) %> ROGUE
        </div>
        <div class="text-sm text-gray-500">ROGUE Earned</div>
      </div>
    </div>

    <%!-- Earnings Table (Real-time) --%>
    <div class="bg-white rounded-xl border border-gray-200 overflow-hidden">
      <div class="px-6 py-4 border-b border-gray-200 flex justify-between items-center">
        <h3 class="font-haas_medium_65">Earnings</h3>
        <span class="text-xs text-green-600 flex items-center gap-1">
          <span class="w-2 h-2 bg-green-500 rounded-full animate-pulse"></span>
          Live
        </span>
      </div>

      <div
        id="referral-earnings-scroll"
        class="overflow-y-auto max-h-96"
        phx-hook="InfiniteScroll"
        data-event="load_more_earnings"
      >
        <table class="w-full text-sm">
          <thead class="sticky top-0 bg-gray-50 z-10">
            <tr>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Type</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">From</th>
              <th class="px-6 py-3 text-right text-xs font-medium text-gray-500 uppercase">Amount</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">Time</th>
              <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase">TX</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-gray-200">
            <%= for earning <- @referral_earnings do %>
              <tr class={if is_recent?(earning.timestamp), do: "bg-green-50"}>
                <td class="px-6 py-4">
                  <span class={"inline-flex items-center px-2 py-1 rounded-full text-xs font-medium #{earning_type_style(earning.earning_type)}"}>
                    <%= earning_type_label(earning.earning_type) %>
                  </span>
                </td>
                <td class="px-6 py-4 text-gray-500">
                  <%= truncate_wallet(earning.referee_wallet) %>
                </td>
                <td class="px-6 py-4 text-right font-medium">
                  <span class={if earning.token == "BUX", do: "text-green-600", else: "text-blue-600"}>
                    +<%= format_number(earning.amount) %> <%= earning.token %>
                  </span>
                </td>
                <td class="px-6 py-4 text-gray-500 text-xs">
                  <%= format_relative_time(earning.timestamp) %>
                </td>
                <td class="px-6 py-4">
                  <%= if earning.tx_hash do %>
                    <a
                      href={"https://roguescan.io/tx/#{earning.tx_hash}?tab=logs"}
                      target="_blank"
                      class="text-blue-500 hover:underline text-xs cursor-pointer"
                    >
                      View
                    </a>
                  <% else %>
                    -
                  <% end %>
                </td>
              </tr>
            <% end %>

            <%= if Enum.empty?(@referral_earnings) do %>
              <tr>
                <td colspan="5" class="px-6 py-8 text-center text-gray-500">
                  No earnings yet. Share your referral link to start earning!
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </div>
  </div>
<% end %>
```

---

## Phone Verification Reward Integration

```elixir
# lib/blockster_v2/phone_verification.ex

def verify_code(user_id, code) do
  with {:ok, verification} <- get_pending_verification(user_id),
       {:ok, _} <- @twilio_client.check_verification_code(verification.phone_number, code) do

    verification
    |> PhoneVerification.changeset(%{
      verified: true,
      verified_at: DateTime.utc_now()
    })
    |> Repo.update()
    |> case do
      {:ok, updated} ->
        update_user_multiplier(user_id, updated.geo_multiplier, updated.geo_tier, updated.sms_opt_in)

        # NEW: Trigger referral reward for phone verification
        BlocksterV2.Referrals.process_phone_verification_reward(user_id)

        {:ok, updated}

      error -> error
    end
  end
end
```

---

## Security Considerations

1. **Self-Referral Prevention**
   - Frontend: Check if ref code matches user's wallet before signup
   - Backend: Validate referrer != referee in `process_signup_referral/2`
   - Contract: Revert on `player == referrer` in `setPlayerReferrer()`

2. **First-Referrer-Wins**
   - User's referrer can only be set once (Mnesia check + contract check)
   - Contract: `require(playerReferrers[player] == address(0))`

3. **Duplicate Prevention**
   - Bet earnings: Unique by `commitment_hash` (checked before insert)
   - Signup/phone: Checked in code before creating earning

4. **Non-Blocking Rewards**
   - Contract rewards are non-blocking (like NFT rewards)
   - If transfer fails, bet settlement continues

---

## Deployment Checklist

### Phase 1: Database & Backend Setup ✅
- [x] Add Mnesia tables to MnesiaInitializer ✅ (Jan 30, 2026)
- [x] Run PostgreSQL migration for user.referrer_id ✅ (Jan 30, 2026)
- [x] Update User schema with referrer association ✅ (Jan 30, 2026)

### Phase 2: Core Elixir Modules ✅
- [x] Create Referrals module ✅ (Jan 30, 2026)
- [x] Create ReferralRewardPoller GenServer ✅ (Jan 30, 2026)
- [x] Add ReferralRewardPoller to supervision tree ✅ (Jan 30, 2026)
- [x] Add set_player_referrer to BuxMinter client ✅ (Jan 30, 2026)

### Phase 3: Frontend JavaScript
- [ ] Capture referral code from URL on landing
- [ ] Store referrer wallet in localStorage
- [ ] Pass referrer_wallet in signup request
- [ ] Clear referrer after successful signup

### Phase 4: Backend API Integration
- [ ] Update auth controller to process referral on signup
- [ ] Add phone verification reward trigger

### Phase 5: BuxMinter Service ✅
- [x] Add POST /set-player-referrer endpoint
- [x] Add ABI for setPlayerReferrer function
- [x] Add Elixir client function `BuxMinter.set_player_referrer/2`
- [ ] Deploy BuxMinter updates (after Phase 6 contract upgrade)

### Phase 6: Smart Contracts ✅
- [x] Add referral storage variables to BuxBoosterGame.sol ✅ (Jan 30, 2026)
- [x] Add referral events to BuxBoosterGame.sol ✅ (Jan 30, 2026)
- [x] Add referral configuration functions to BuxBoosterGame.sol ✅ (Jan 30, 2026)
- [x] Add _sendBuxReferralReward function to BuxBoosterGame.sol ✅ (Jan 30, 2026)
- [x] Integrate _sendBuxReferralReward in _processSettlement losing branch ✅ (Jan 30, 2026)
- [x] Add initializeV6() to BuxBoosterGame.sol (sets 1% BUX referral) ✅ (Jan 30, 2026)
- [x] Create upgrade script: scripts/upgrade-to-v6.js ✅ (Jan 30, 2026)
- [x] Add referral storage variables to ROGUEBankroll.sol ✅ (Jan 30, 2026)
- [x] Add referral events to ROGUEBankroll.sol ✅ (Jan 30, 2026)
- [x] Add referral configuration functions to ROGUEBankroll.sol ✅ (Jan 30, 2026)
- [x] Add _sendReferralReward function to ROGUEBankroll.sol ✅ (Jan 30, 2026)
- [x] Integrate _sendReferralReward in settleBuxBoosterLosingBet ✅ (Jan 30, 2026)
- [x] Add referrerTotalEarnings mapping for per-referrer tracking ✅ (Jan 30, 2026)
- [x] Verify contracts compile successfully ✅ (Jan 30, 2026)
- [ ] Deploy BuxBoosterGame V6: `npx hardhat run scripts/upgrade-to-v6.js --network rogueMainnet`
- [ ] Deploy ROGUEBankroll V8 (manual upgrade by user)
- [ ] Set ROGUE referral basis points to 20 (0.2%): `rogueBankroll.setReferralBasisPoints(20)`
- [ ] Update @deploy_block in ReferralRewardPoller after contract deployment

### Phase 7: LiveView UI ✅ COMPLETED (Jan 31, 2026)
- [x] Add Refer tab to members page
- [x] Display referral link with copy button
- [x] Show earnings table with real-time updates
- [x] Add stats cards (total referrals, earnings)
- [x] PubSub subscription for real-time earning updates
- [x] Infinite scroll for earnings history

### Final Steps
- [ ] Restart both nodes to create Mnesia tables
- [ ] Test end-to-end flow
- [ ] Monitor poller logs for event processing
- [ ] Deploy to production

---

## Summary

This referral system:

1. **Uses Mnesia exclusively** for all referral data (earnings, stats, poller state) - consistent with Blockster's architecture
2. **Zero PostgreSQL queries** during event processing and UI rendering - wallet addresses stored directly in Mnesia records
3. **Copies high-rollers-elixir pattern** for event polling (1-second polling, backfill, Mnesia persistence)
4. **Follows ROGUEBankroll → NFTRewarder pattern** for smart contract payouts (but sends directly to wallet instead of pooling)
5. **Real-time updates** via PubSub broadcasts when events are detected
6. **Non-blocking** contract rewards that never fail bet settlement

**PostgreSQL is only used for:**
- Writing `user.referrer_id` on signup (one-time write, not read for referral operations)
- User authentication (separate from referral system)

---

## Detailed Implementation Checklist

### Phase 1: Database & Backend Setup ✅ COMPLETED (Jan 30, 2026)

#### 1.1 PostgreSQL Migration ✅
```bash
# Migration file created and applied
priv/repo/migrations/20260131004444_add_referrer_to_users.exs
```

- [x] Create migration file `priv/repo/migrations/20260131004444_add_referrer_to_users.exs`
- [x] Add fields: `referrer_id` (references users), `referred_at` (utc_datetime)
- [x] Add index on `referrer_id`
- [x] Test migration locally: `mix ecto.migrate` ✅
- [x] Verify rollback works: `mix ecto.rollback` ✅

**Migration Content:**
```elixir
defmodule BlocksterV2.Repo.Migrations.AddReferrerToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :referrer_id, references(:users, on_delete: :nilify_all)
      add :referred_at, :utc_datetime
    end

    create index(:users, [:referrer_id])
  end
end
```

#### 1.2 Mnesia Tables ✅
- [x] Open `lib/blockster_v2/mnesia_initializer.ex`
- [x] Add `:referrals` table definition (lines 425-437)
- [x] Add `:referral_earnings` table definition (type: :bag, lines 439-454)
- [x] Add `:referral_stats` table definition (lines 456-467)
- [x] Add `:referral_poller_state` table definition (lines 469-478)
- [x] Verify indexes: `[:referrer_id, :referrer_wallet, :referee_wallet]` for referrals ✅
- [x] Verify indexes: `[:referrer_id, :referrer_wallet, :referee_wallet, :commitment_hash]` for earnings ✅
- [x] Tables added at END of `@tables` list (after `:unified_multipliers`)
- [ ] Restart both nodes to create tables (pending - do this before Phase 2 testing)
- [ ] Verify tables exist: `:mnesia.system_info(:tables)` in IEx

**Mnesia Table Definitions Added:**
```elixir
# :referrals table - Maps referred user to referrer
%{
  name: :referrals,
  type: :set,
  attributes: [:user_id, :referrer_id, :referrer_wallet, :referee_wallet, :referred_at, :on_chain_synced],
  index: [:referrer_id, :referrer_wallet, :referee_wallet]
}

# :referral_earnings table - Bag for multiple earnings per user
%{
  name: :referral_earnings,
  type: :bag,
  attributes: [:id, :referrer_id, :referrer_wallet, :referee_wallet, :earning_type, :amount, :token, :tx_hash, :commitment_hash, :timestamp],
  index: [:referrer_id, :referrer_wallet, :referee_wallet, :commitment_hash]
}

# :referral_stats table - Cached stats per user
%{
  name: :referral_stats,
  type: :set,
  attributes: [:user_id, :total_referrals, :verified_referrals, :total_bux_earned, :total_rogue_earned, :updated_at],
  index: []
}

# :referral_poller_state table - Persists last processed block
%{
  name: :referral_poller_state,
  type: :set,
  attributes: [:key, :last_block, :updated_at],
  index: []
}
```

#### 1.3 User Schema Update ✅
- [x] Open `lib/blockster_v2/accounts/user.ex`
- [x] Add `belongs_to :referrer, __MODULE__` (line 35)
- [x] Add `has_many :referees, __MODULE__, foreign_key: :referrer_id` (line 36)
- [x] Add `field :referred_at, :utc_datetime` (line 34)
- [x] Update changeset to allow `referrer_id` and `referred_at` (lines 55-56)

**User Schema Changes:**
```elixir
# Added to schema block (lines 33-36)
# Referral fields
field :referred_at, :utc_datetime
belongs_to :referrer, __MODULE__
has_many :referees, __MODULE__, foreign_key: :referrer_id

# Updated changeset cast (lines 51-56)
|> cast(attrs, [...existing fields...,
                :referrer_id, :referred_at])
```

---

### Phase 2: Core Elixir Modules ✅ COMPLETED (Jan 30, 2026)

**Git Branch**: `feature/referral-system`

#### 2.1 Referrals Module ✅
- [x] Create `lib/blockster_v2/referrals.ex`
- [x] Set module attributes:
  - `@signup_reward 100` (BUX)
  - `@phone_verified_reward 100` (BUX)
- [x] Implement `process_signup_referral/2`
- [x] Implement `process_phone_verification_reward/1`
- [x] Implement `record_bet_loss_earning/1`
- [x] Implement `record_bet_loss_earning_backfill/1`
- [x] Implement `get_referrer_stats/1`
- [x] Implement `list_referrals/2`
- [x] Implement `list_referral_earnings/2`
- [x] Implement `get_user_id_by_wallet/1`
- [x] Implement `get_referrer_by_referee_wallet/1`
- [x] Implement private helpers:
  - `create_signup_earning/4`
  - `create_phone_verification_earning/3`
  - `update_referrer_stats/4`
  - `mint_referral_reward/5`
  - `sync_referrer_to_contracts/2`
  - `broadcast_referral_earning/2`
- [x] Add `require Logger` at top
- [x] Add `alias BlocksterV2.{Repo, BuxMinter}` and `alias BlocksterV2.Accounts.User`

**Implementation Notes:**
- Uses `Ecto.UUID.generate()` instead of `UUID.uuid4()` (Elixir standard)
- All Mnesia operations use dirty reads/writes for performance
- PubSub broadcasts on topic `"referral:#{referrer_id}"` for real-time UI updates
- `sync_referrer_to_contracts/2` runs async via `Task.start/1` to not block signup
- Wallet addresses normalized to lowercase for consistent lookups

#### 2.2 ReferralRewardPoller GenServer ✅
- [x] Create `lib/blockster_v2/referral_reward_poller.ex`
- [x] Set module attributes:
  - `@poll_interval_ms 1_000` (1 second)
  - `@max_blocks_per_query 5_000` (Rogue Chain is fast)
  - `@backfill_chunk_size 10_000`
  - `@backfill_delay_ms 100`
  - `@rpc_url "https://rpc.roguechain.io/rpc"`
  - `@rogue_bankroll_address "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd"`
  - `@bux_booster_address "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B"`
- [x] **IMPORTANT**: `@deploy_block` set to 0 (TODO: update after contract deploy)
- [x] Implement `init/1` with delayed init (waits 2s for Mnesia)
- [x] Implement `handle_info(:poll, state)` with overlap prevention
- [x] Implement `handle_cast({:backfill, from_block}, state)`
- [x] Implement private helpers:
  - `get_last_processed_block/0` - reads from Mnesia
  - `save_last_processed_block/1` - writes to Mnesia
  - `get_current_block/0` - RPC call
  - `poll_events/1` - fetches from both contracts
  - `fetch_bux_referral_events/2` - BuxBoosterGame events
  - `fetch_rogue_referral_events/2` - ROGUEBankroll events
  - `parse_bux_referral_log/1` - extracts event data (token + amount in data)
  - `parse_rogue_referral_log/1` - extracts event data (amount only in data)
  - `process_bux_referral_event/1` - calls Referrals module
  - `process_rogue_referral_event/1` - calls Referrals module
  - `backfill_events/2` - handles historical event catch-up
  - `schedule_poll/0` - schedules next poll
- [x] Use GlobalSingleton pattern (only one poller across cluster)
- [x] Uses `:httpc` with timeouts (30s request, 5s connect) to prevent hanging

**Implementation Notes:**
- Event topics calculated via `:crypto.hash(:sha3_256, ...)` (keccak256)
- BuxBoosterGame event: `ReferralRewardPaid(bytes32,address,address,address,uint256)` - includes token
- ROGUEBankroll event: `ReferralRewardPaid(bytes32,address,address,uint256)` - no token (always ROGUE)
- Backfill runs in separate spawned process to not block polling
- Backfill uses `_backfill` variants that skip PubSub broadcasts for performance
- Polling state persisted in `:referral_poller_state` Mnesia table (key: `:rogue`)

#### 2.3 Add to Supervision Tree ✅
- [x] Open `lib/blockster_v2/application.ex`
- [x] Add `{BlocksterV2.ReferralRewardPoller, []}` to children list (line 47)
- [x] Placed after WalletMultiplierRefresher (at end of genserver_children list)

#### 2.4 BuxMinter Client Function ✅
- [x] Open `lib/blockster_v2/bux_minter.ex`
- [x] Add `set_player_referrer/2` function at end of module
- [x] Uses existing `http_post/3` helper with timeouts
- [x] Calls `POST /set-player-referrer` endpoint on BuxMinter service

**Files Created/Modified in Phase 2:**
```
lib/blockster_v2/referrals.ex              # NEW - Core referral logic
lib/blockster_v2/referral_reward_poller.ex # NEW - Event polling GenServer
lib/blockster_v2/application.ex            # MODIFIED - Added poller to supervision tree
lib/blockster_v2/bux_minter.ex             # MODIFIED - Added set_player_referrer/2
```

**Compilation Status:** ✅ Compiles without errors (warnings are pre-existing unrelated issues)

---

### Phase 3: Frontend JavaScript ✅ COMPLETED (Jan 30, 2026)

#### 3.1 Referral Code Capture ✅
- [x] Modified `assets/js/home_hooks.js` (using existing hooks, no new file needed)
- [x] Implemented `captureReferrerCode()` in HomeHooks - extracts `?ref=0x...` from URL
- [x] Implemented `getReferrerCode()` in ThirdwebLogin - gets from localStorage
- [x] Implemented `clearReferrerCode()` in ThirdwebLogin - removes from localStorage
- [x] Signup integration done in `authenticateEmail()` (no separate function needed)
- [x] Called `captureReferrerCode()` in HomeHooks.mounted()

#### 3.2 Signup Flow Integration ✅
- [x] Found signup code: `ThirdwebLogin.authenticateEmail()`
- [x] Added `referrer_wallet: referrerCode` to request body
- [x] Clear referrer after successful signup when `is_new_user` is true

**Implementation Notes:**
- Used existing hooks instead of creating new ReferralManager class
- Referrer captured on homepage load via HomeHooks
- Referrer passed to backend via ThirdwebLogin.authenticateEmail()
- localStorage key: `blockster_referrer`
- URL param format: `?ref=0x1234...` (40 hex chars, validated with regex)

---

### Phase 4: Backend API Integration ✅ COMPLETED (Jan 30, 2026)

#### 4.1 Auth Controller Update ✅
- [x] Open `lib/blockster_v2_web/controllers/auth_controller.ex`
- [x] Find `verify_email/2` function (or equivalent signup handler)
- [x] Extract `referrer_wallet` from params
- [x] After user creation, call `Referrals.process_signup_referral(user, referrer_wallet)`
- [x] Handle case where referrer_wallet is nil or invalid
- [x] Modified `authenticate_email_with_fingerprint/1` to return `is_new_user` flag
- [x] Return `is_new_user` in JSON response for frontend

#### 4.2 Phone Verification Integration ✅
- [x] Open `lib/blockster_v2/phone_verification.ex`
- [x] Find `verify_code/2` function
- [x] After successful verification, add:
  ```elixir
  BlocksterV2.Referrals.process_phone_verification_reward(user_id)
  ```
- [x] Ensure this is called AFTER the verification is persisted

---

### Phase 5: BuxMinter Service Updates ✅ COMPLETED

#### 5.1 Add set_player_referrer Endpoint ✅
- [x] Open `bux-minter/index.js`
- [x] Add new endpoint: `POST /set-player-referrer`
- [x] Parameters: `player` (address), `referrer` (address)
- [x] Add ABI entries for `setPlayerReferrer(address,address)` to both BUXBOOSTER_ABI and ROGUE_BANKROLL_ABI
- [x] Add ABI entries for `playerReferrers(address)` (for checking if already set)
- [x] Create `rogueBankrollWriteContract` using `contractOwnerWallet`
- [x] Create `buxBoosterOwnerContract` using `contractOwnerWallet`
- [x] Add error handling for "Referrer already set" (checks before calling, returns 409)
- [x] Add self-referral prevention
- [x] Add address validation

**Actual Implementation** (differs from spec - no AdminTxQueue needed, sequential calls work fine):
```javascript
app.post('/set-player-referrer', authenticate, async (req, res) => {
  const { player, referrer } = req.body;

  // Validate addresses, prevent self-referral
  // Check if already set on each contract before calling
  // Set on BuxBoosterGame (for BUX bets)
  // Set on ROGUEBankroll (for ROGUE bets)
  // Return results for both contracts
});
```

#### 5.2 Elixir BuxMinter Client ✅
- [x] Open `lib/blockster_v2/bux_minter.ex`
- [x] Add `set_player_referrer/2` function
- [x] Uses existing `http_post/3` helper (60s timeout already configured)
- [x] Add error logging
- [x] Handle 409 Conflict as `{:error, :already_set}`

**Implementation:**
```elixir
def set_player_referrer(player_wallet, referrer_wallet) do
  # Calls POST /set-player-referrer
  # Returns {:ok, results} | {:error, :already_set} | {:error, reason}
end
```

#### 5.3 Deployment Notes
- [ ] Deploy BuxMinter updates: `cd bux-minter && flyctl deploy`
- **Prerequisite**: Smart contracts must be upgraded first (Phase 6) before this endpoint will work

---

### Phase 6: Smart Contract Updates ✅ COMPLETED (Jan 30, 2026)

#### 6.1 ROGUEBankroll Contract (V8) - CODE COMPLETE ✅
**Note: User will upgrade ROGUEBankroll manually - code complete and compiles.**

- [x] Open `contracts/bux-booster-game/contracts/ROGUEBankroll.sol` ✅
- [x] Find line 973 (after `totalNFTRewardsPaid`) ✅
- [x] Add storage variables (from doc): ✅
  - `uint256 public referralBasisPoints;`
  - `mapping(address => address) public playerReferrers;`
  - `uint256 public totalReferralRewardsPaid;`
  - `mapping(address => uint256) public referrerTotalEarnings;` (ADDED: per-referrer tracking)
  - `address public referralAdmin;` (ADDED: admin address for BuxMinter service)
- [x] Add events: ✅
  - `event ReferralRewardPaid(bytes32 indexed commitmentHash, address indexed referrer, address indexed player, uint256 amount)`
  - `event ReferrerSet(address indexed player, address indexed referrer)`
  - `event ReferralBasisPointsChanged(uint256 previousBasisPoints, uint256 newBasisPoints)`
  - `event ReferralAdminChanged(address indexed previousAdmin, address indexed newAdmin)` (ADDED)
- [x] Add configuration functions: ✅
  - `setReferralBasisPoints(uint256)` - max 10% (1000 basis points)
  - `getReferralBasisPoints()`
  - `getReferralTotalRewardsPaid()`
  - `getReferrerTotalEarnings(address referrer)` (ADDED: per-referrer view)
  - `setReferralAdmin(address)` - owner only, sets admin who can call setPlayerReferrer (ADDED)
  - `getReferralAdmin()` - view function (ADDED)
  - `setPlayerReferrer(address,address)` - callable by owner OR referralAdmin
  - `setPlayerReferrersBatch(address[],address[])` - callable by owner OR referralAdmin
  - `getPlayerReferrer(address)`
- [x] Add `_sendReferralReward(bytes32,address,uint256)` private function ✅
- [x] Copy EXACT pattern from `_sendNFTReward` ✅
- [x] Find `settleBuxBoosterLosingBet` function (line 1804 after changes) ✅
- [x] Add call after `_sendNFTReward`: `_sendReferralReward(commitmentHash, player, wagerAmount);` ✅
- [x] Compile: `npx hardhat compile` ✅
- [x] Verify no errors ✅

**Key Code Locations in ROGUEBankroll.sol:**
- Storage variables: After line 973 (after `totalNFTRewardsPaid`)
- Events: After line 1063 (after `NFTRewardBasisPointsChanged`)
- Functions: After line 1435 (after `getTotalNFTRewardsPaid`)
- `_sendReferralReward`: After line 1566 (after `_sendNFTReward`)
- Integration: Line 1810 (in `settleBuxBoosterLosingBet`, after `_sendNFTReward`)

#### 6.2 BuxBoosterGame Contract (V6) - CODE COMPLETE ✅
**Note: Upgrade script created. User will run `scripts/upgrade-to-v6.js`.**

- [x] Open `contracts/bux-booster-game/contracts/BuxBoosterGame.sol` ✅
- [x] Find line 557 (after `rogueBankroll` and `ROGUE_TOKEN` constant) ✅
- [x] Add storage variables at END (preserving storage layout): ✅
  - `uint256 public buxReferralBasisPoints;` (named differently to clarify it's for BUX)
  - `mapping(address => address) public playerReferrers;`
  - `mapping(address => uint256) public totalReferralRewardsPaid;` (per-token)
  - `mapping(address => mapping(address => uint256)) public referrerTokenEarnings;` (ADDED: per-referrer per-token)
  - `address public referralAdmin;` (ADDED: admin address for BuxMinter service)
- [x] Add events: ✅
  - `event ReferralRewardPaid(bytes32 indexed commitmentHash, address indexed referrer, address indexed player, address token, uint256 amount)` (includes token)
  - `event ReferrerSet(address indexed player, address indexed referrer)`
  - `event ReferralAdminChanged(address indexed previousAdmin, address indexed newAdmin)` (ADDED)
- [x] Add `initializeV6()` - sets buxReferralBasisPoints to 100 (1%) ✅
- [x] Add configuration functions: ✅
  - `setBuxReferralBasisPoints(uint256)` - max 1% (100 basis points)
  - `getBuxReferralBasisPoints()`
  - `getTotalReferralRewardsPaid(address token)`
  - `getReferrerTokenEarnings(address referrer, address token)` (ADDED)
  - `setReferralAdmin(address)` - owner only, sets admin who can call setPlayerReferrer (ADDED)
  - `getReferralAdmin()` - view function (ADDED)
  - `setPlayerReferrer(address,address)` - callable by owner OR referralAdmin
  - `setPlayerReferrersBatch(address[],address[])` - callable by owner OR referralAdmin
  - `getPlayerReferrer(address)`
- [x] Add `_sendBuxReferralReward(bytes32, Bet storage)` for BUX bets ✅
- [x] Find `_processSettlement` losing path and add referral reward call ✅
- [x] Compile: `npx hardhat compile` ✅
- [x] Verify no errors ✅

**Key Code Locations in BuxBoosterGame.sol:**
- Events: After line 553 (after `HouseWithdraw` event)
- Storage variables: After line 566 (after `ROGUE_TOKEN` constant)
- `initializeV6()`: After line 687 (after `initializeV5`)
- Configuration functions: After line 705 (after `_authorizeUpgrade`)
- `_sendBuxReferralReward`: After line 1193 (after `_processSettlement`)
- Integration: Line 1193 (in `_processSettlement` losing branch)

#### 6.3 Upgrade Script Created ✅
- [x] Created `scripts/upgrade-to-v6.js` ✅
  - Deploys new BuxBoosterGame implementation
  - Upgrades proxy to V6
  - Calls `initializeV6()` which sets `buxReferralBasisPoints = 100` (1%)
  - Verifies configuration

**Usage:**
```bash
cd contracts/bux-booster-game
npx hardhat run scripts/upgrade-to-v6.js --network rogueMainnet
```

#### 6.4 Compilation Verified ✅
```bash
cd contracts/bux-booster-game
npx hardhat compile
# Output: Compiled 2 Solidity files successfully (evm target: paris)
```

Both contracts compile with no errors. Pre-existing shadowing warning in ROGUEBankroll.sol (line 1500, `players` parameter shadows storage mapping).

---

### Phase 7: LiveView UI ✅ COMPLETED (Jan 31, 2026)

#### 7.1 Member Page - Refer Tab ✅
- [x] Open `lib/blockster_v2_web/live/member_live/show.ex` and `show.html.heex`
- [x] Current tabs: activity, following, event, rogue, wallet, airdrop, settings
- [x] Add "Refer" tab (kept settings tab, added refer as new tab for own profile only)
- [x] Add assigns in `handle_params/3`:
  - `referral_link` - generated from member's smart_wallet_address
  - `referral_stats` - from `Referrals.get_referrer_stats/1`
  - `referrals` - from `Referrals.list_referrals/2` (limit: 20)
  - `referral_earnings` - from `Referrals.list_referral_earnings/2` (limit: 50)
- [x] Added `alias BlocksterV2.Referrals` at top of module
- [x] Add event handlers:
  - `handle_event("copy_referral_link", ...)` - uses `push_event` to JS hook
  - `handle_event("load_more_earnings", ...)` - infinite scroll with offset
- [x] Add `handle_info({:referral_earning, earning}, socket)` for real-time updates

**Implementation Details - show.ex:**
```elixir
# Added alias at top
alias BlocksterV2.Referrals

# In handle_params/3, load referral data for own profile
{referral_link, referral_stats, referrals, referral_earnings} = if is_own_profile do
  wallet_address = member.smart_wallet_address
  {
    generate_referral_link(wallet_address),
    Referrals.get_referrer_stats(member.id),
    Referrals.list_referrals(member.id, limit: 20),
    Referrals.list_referral_earnings(member.id, limit: 50)
  }
else
  {nil, nil, [], []}
end

# Subscribe to real-time referral updates (only for own profile)
if connected?(socket) && is_own_profile do
  Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "referral:#{member.id}")
end

# Event handler for copy button
@impl true
def handle_event("copy_referral_link", _params, socket) do
  referral_link = socket.assigns.referral_link
  {:noreply, push_event(socket, "copy_to_clipboard", %{text: referral_link})}
end

# Event handler for infinite scroll
@impl true
def handle_event("load_more_earnings", _params, socket) do
  current_earnings = socket.assigns.referral_earnings
  user_id = socket.assigns.current_user.id
  offset = length(current_earnings)
  more_earnings = Referrals.list_referral_earnings(user_id, limit: 50, offset: offset)
  if Enum.empty?(more_earnings) do
    {:reply, %{end_reached: true}, socket}
  else
    {:noreply, assign(socket, :referral_earnings, current_earnings ++ more_earnings)}
  end
end

# Handler for real-time PubSub updates
@impl true
def handle_info({:referral_earning, earning}, socket) do
  earning_map = %{
    id: elem(earning, 1),
    referrer_id: elem(earning, 2),
    referrer_wallet: elem(earning, 3),
    referee_wallet: elem(earning, 4),
    earning_type: elem(earning, 5),
    amount: elem(earning, 6),
    token: elem(earning, 7),
    tx_hash: elem(earning, 8),
    commitment_hash: elem(earning, 9),
    timestamp: elem(earning, 10)
  }

  # Prepend new earning to list
  updated_earnings = [earning_map | socket.assigns.referral_earnings]

  # Update stats
  current_stats = socket.assigns.referral_stats || %{}
  token = earning_map.token
  amount = earning_map.amount
  updated_stats = if token == "BUX" do
    Map.update(current_stats, :total_bux_earned, amount, &(&1 + amount))
  else
    Map.update(current_stats, :total_rogue_earned, amount, &(&1 + amount))
  end

  {:noreply,
   socket
   |> assign(:referral_earnings, updated_earnings)
   |> assign(:referral_stats, updated_stats)}
end
```

**Helper Functions Added:**
```elixir
defp generate_referral_link(wallet_address) when is_binary(wallet_address) do
  base_url = BlocksterV2Web.Endpoint.url()
  "#{base_url}/?ref=#{wallet_address}"
end
defp generate_referral_link(_), do: nil

def format_referral_number(number) when is_float(number) do
  if number == trunc(number) do
    Integer.to_string(trunc(number))
  else
    :erlang.float_to_binary(number, decimals: 2)
  end
end
def format_referral_number(number) when is_integer(number), do: Integer.to_string(number)
def format_referral_number(_), do: "0"

def truncate_wallet(nil), do: "-"
def truncate_wallet(wallet) when is_binary(wallet) and byte_size(wallet) > 10 do
  "#{String.slice(wallet, 0..5)}...#{String.slice(wallet, -4..-1)}"
end
def truncate_wallet(wallet), do: wallet

def earning_type_label(:signup), do: "Signup"
def earning_type_label(:phone_verified), do: "Phone Verified"
def earning_type_label(:bux_bet_loss), do: "BUX Bet"
def earning_type_label(:rogue_bet_loss), do: "ROGUE Bet"
def earning_type_label(:shop_purchase), do: "Shop Purchase"
def earning_type_label(_), do: "Other"

def earning_type_style(:signup), do: "bg-green-100 text-green-800"
def earning_type_style(:phone_verified), do: "bg-blue-100 text-blue-800"
def earning_type_style(:bux_bet_loss), do: "bg-purple-100 text-purple-800"
def earning_type_style(:rogue_bet_loss), do: "bg-indigo-100 text-indigo-800"
def earning_type_style(:shop_purchase), do: "bg-orange-100 text-orange-800"
def earning_type_style(_), do: "bg-gray-100 text-gray-800"

def format_relative_time(datetime) do
  now = DateTime.utc_now()
  diff_seconds = DateTime.diff(now, datetime, :second)
  cond do
    diff_seconds < 60 -> "just now"
    diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
    diff_seconds < 86400 -> "#{div(diff_seconds, 3600)}h ago"
    diff_seconds < 604_800 -> "#{div(diff_seconds, 86400)}d ago"
    true -> Calendar.strftime(datetime, "%b %d")
  end
end

def is_recent_earning?(datetime) do
  now = DateTime.utc_now()
  DateTime.diff(now, datetime, :second) < 300  # 5 minutes
end
```

#### 7.2 Refer Tab Template ✅
- [x] Open `lib/blockster_v2_web/live/member_live/show.html.heex`
- [x] Added "Refer" tab button (only visible when `@is_own_profile`)
- [x] Added complete Refer tab content section with:
  - Referral link display with copy button
  - Stats cards: Total Referrals, Verified Referrals, BUX Earned, ROGUE Earned
  - Earnings table with infinite scroll
  - Color-coded earning types (signup, phone verified, bet losses)
  - Relative time formatting
  - Recent earning highlighting (yellow pulse for last 5 mins)
  - Wallet address truncation

**Template Structure:**
```heex
<!-- Refer Tab Button (in tab navigation) -->
<%= if @is_own_profile do %>
<button
  phx-click="switch_tab"
  phx-value-tab="refer"
  class={"w-1/4 px-3 py-2.5 font-haas_roman_55 text-sm text-[#141414] leading-[1.4] cursor-pointer rounded-full transition-colors relative z-10 #{if @active_tab == "refer", do: "bg-white", else: ""}"}
>
  Refer
</button>
<% end %>

<!-- Refer Tab Content -->
<div :if={@active_tab == "refer" && @is_own_profile} class="space-y-6">
  <!-- Referral Link Section -->
  <!-- Stats Cards (4 cards grid) -->
  <!-- Earnings Table with infinite scroll -->
</div>
```

#### 7.3 PubSub Subscription ✅
- [x] In `handle_params/3`, added subscription for own profile:
  ```elixir
  if connected?(socket) && is_own_profile do
    Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "referral:#{member.id}")
  end
  ```
- [x] Added handler for `{:referral_earning, earning}` messages

#### 7.4 Bug Fix During Implementation
- [x] Fixed duplicate `set_player_referrer/2` function in `lib/blockster_v2/bux_minter.ex`
  - Removed duplicate at lines 486-532
  - Kept original at line 363 with proper 409 handling for "already set" case

---

### Phase 8: Testing ✅ COMPLETED (Jan 31, 2026)

#### 8.1 Unit Tests - Referrals Module ✅
- [x] Create `test/blockster_v2/referrals_test.exs` (32 tests)
- [x] Test `process_signup_referral/2`:
  - Valid referrer wallet → creates Mnesia record, mints BUX
  - Invalid referrer wallet → returns error
  - Self-referral → returns error (case-insensitive)
  - Empty/nil referrer → returns :no_referrer or :referrer_not_found
- [x] Test `process_phone_verification_reward/1`:
  - User has referrer → creates earning, mints BUX
  - User has no referrer → returns :no_referrer
  - Already rewarded → returns :already_rewarded
- [x] Test `record_bet_loss_earning/1`:
  - Valid event data → creates Mnesia record
  - Duplicate commitment_hash → returns :duplicate
  - Unknown referee wallet → returns :referral_not_found
  - Referrer wallet mismatch → returns :referrer_mismatch
- [x] Test `get_referrer_stats/1`
- [x] Test `list_referrals/2`
- [x] Test `list_referral_earnings/2`
- [x] Test `get_user_id_by_wallet/1`
- [x] Test `get_referrer_by_referee_wallet/1`

**Run Tests:**
```bash
mix test test/blockster_v2/referrals_test.exs
```

#### 8.2 Integration Tests - MemberLive Referral Tab ✅
- [x] Create `test/blockster_v2_web/live/member_live/referral_test.exs`
- [x] Test Mnesia query functions (list_referral_earnings, get_referrer_stats, list_referrals)
- [x] Document LiveView tests (skipped - require full Mnesia context)

**Note:** Full LiveView integration tests are skipped by default (`@moduletag :skip`) because they require all Mnesia tables initialized. The MemberLive.Show LiveView depends on:
- `:unified_multipliers` - for multiplier display
- `:user_bux_balances` - for balance display
- `:referrals`, `:referral_earnings`, `:referral_stats` - for referral data

To run full integration tests, start the app with `elixir --sname node1 -S mix phx.server` and test manually.

**Run Tests:**
```bash
mix test test/blockster_v2_web/live/member_live/referral_test.exs
```

#### 8.3 Local End-to-End Test
1. [ ] Start node1 and node2
2. [ ] Create User A (referrer) - note wallet address
3. [ ] Visit `/?ref=0xUserAWallet` in incognito
4. [ ] Sign up as User B
5. [ ] Verify User A received 100 BUX (check Mnesia)
6. [ ] Verify User A's member page shows earning
7. [ ] Verify User B in :referrals table
8. [ ] Complete phone verification for User B
9. [ ] Verify User A received additional 100 BUX
10. [ ] Place a BUX Booster bet as User B and lose
11. [ ] Verify ReferralRewardPaid event emitted (check logs)
12. [ ] Verify User A received 1% of bet amount
13. [ ] Verify User A's earnings table shows bet loss earning

**Bug Fixes During Testing:**
1. Fixed `DateTime.utc_now()` not being truncated to seconds in `process_signup_referral/2`
2. Fixed `list_referrals/2` checking wrong index for phone_verified status (was using referee_id instead of referrer_id)

---

### Phase 9: Deployment

#### 9.1 Pre-Deployment Checklist
- [ ] All tests passing locally
- [ ] Code reviewed
- [ ] No hardcoded test values
- [ ] Logging is appropriate (not too verbose)
- [ ] Error handling is comprehensive

#### 9.2 Deploy Smart Contracts (Rogue Chain Mainnet)

**Step 1: BuxBoosterGame V6 Upgrade**
```bash
cd contracts/bux-booster-game

# Compile
npx hardhat compile

# Deploy BuxBoosterGame V6 (includes initializeV6 which sets 1% BUX referral)
npx hardhat run scripts/upgrade-to-v6.js --network rogueMainnet

# Note the new implementation address and upgrade block number
# NEW_IMPL_ADDRESS: ________________
# UPGRADE_BLOCK: ________________
```

- [ ] BuxBoosterGame V6 deployed
- [ ] Implementation address: `__________`
- [ ] Upgrade block number: `__________`
- [ ] Verify buxReferralBasisPoints = 100: `proxy.buxReferralBasisPoints()` → should return 100

**Step 2: ROGUEBankroll V8 Upgrade (Manual)**
User will upgrade ROGUEBankroll manually using OpenZeppelin upgrade tools or direct contract interaction.

After upgrade, configure ROGUE referral basis points:
```javascript
// Using hardhat console or script
const rogueBankroll = await ethers.getContractAt("ROGUEBankroll", "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd");
await rogueBankroll.setReferralBasisPoints(20);  // 0.2%
```

- [ ] ROGUEBankroll V8 deployed
- [ ] Implementation address: `__________`
- [ ] Upgrade block number: `__________`
- [ ] Verify referralBasisPoints = 20: `rogueBankroll.referralBasisPoints()` → should return 20

**Step 3: Set Referral Admin on Both Contracts**
Each contract has a dedicated referral admin wallet (separate from contract owner):

| Contract | Referral Admin Address | Fly Secret |
|----------|------------------------|------------|
| BuxBoosterGame | `0xbD6feD8fEeec6f405657d0cA4A004f89F81B04ad` | `REFERRAL_ADMIN_BB_PRIVATE_KEY` |
| ROGUEBankroll | `0x138742ae11E3848E9AF42aC0B81a6712B8c46c11` | `REFERRAL_ADMIN_RB_PRIVATE_KEY` |

```javascript
// Set referral admin on BuxBoosterGame (requires contract owner to call)
const buxBoosterGame = await ethers.getContractAt("BuxBoosterGame", "0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B");
await buxBoosterGame.setReferralAdmin("0xbD6feD8fEeec6f405657d0cA4A004f89F81B04ad");

// Set referral admin on ROGUEBankroll (requires contract owner to call)
const rogueBankroll = await ethers.getContractAt("ROGUEBankroll", "0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd");
await rogueBankroll.setReferralAdmin("0x138742ae11E3848E9AF42aC0B81a6712B8c46c11");
```

- [ ] BuxBoosterGame.setReferralAdmin("0xbD6feD8fEeec6f405657d0cA4A004f89F81B04ad") called
- [ ] ROGUEBankroll.setReferralAdmin("0x138742ae11E3848E9AF42aC0B81a6712B8c46c11") called

**Step 4: Update ReferralRewardPoller**
After both contracts are deployed, update the `@deploy_block` in `lib/blockster_v2/referral_reward_poller.ex`:
```elixir
# Set to the earliest block when referral contracts were deployed
@deploy_block <UPGRADE_BLOCK_NUMBER>
```

#### 9.3 Deploy BuxMinter Updates
```bash
cd bux-minter
flyctl deploy
```
- [ ] Test `/set-player-referrer` endpoint works
- [ ] Check logs for any errors

#### 9.4 Deploy Blockster App
```bash
# Run migration first
flyctl ssh console -a blockster-v2
bin/blockster_v2 eval "BlocksterV2.Release.migrate()"
exit

# Deploy code
git push origin main
flyctl deploy --app blockster-v2
```

#### 9.5 Post-Deployment Configuration
- [ ] Update `@deploy_block` in ReferralRewardPoller to upgrade block number
- [ ] Redeploy with updated block number
- [ ] Verify Mnesia tables created: check logs for "Created table :referrals"
- [ ] Verify poller started: check logs for "[ReferralRewardPoller] Starting"

#### 9.6 Backfill Historical Events (if needed)
```elixir
# In IEx console on production
BlocksterV2.ReferralRewardPoller.backfill_from_block(UPGRADE_BLOCK_NUMBER)
```

---

### Phase 10: Monitoring & Verification

#### 10.1 Log Monitoring
- [ ] Monitor for: `[ReferralRewardPoller] Polling blocks`
- [ ] Monitor for: `[ReferralRewardPoller] Processed N events`
- [ ] Monitor for: `[Referrals] Referrer wallet mismatch` (should not happen)
- [ ] Monitor for: `[Referrals] No referral found` (expected for non-referred users)

#### 10.2 Mnesia Verification
```elixir
# Check referrals table
:mnesia.dirty_match_object({:referrals, :_, :_, :_, :_, :_, :_}) |> length()

# Check earnings table
:mnesia.dirty_match_object({:referral_earnings, :_, :_, :_, :_, :_, :_, :_, :_, :_, :_}) |> length()

# Check poller state
:mnesia.dirty_read(:referral_poller_state, :rogue)
```

#### 10.3 Contract Verification
```javascript
// Check referral configuration
const basisPoints = await rogueBankroll.getReferralBasisPoints();
console.log("Basis points:", basisPoints.toString()); // Should be 20

// Check total rewards paid
const totalPaid = await rogueBankroll.getReferralTotalRewardsPaid();
console.log("Total paid:", ethers.formatEther(totalPaid));

// Check a player's referrer
const referrer = await rogueBankroll.getPlayerReferrer(playerAddress);
console.log("Referrer:", referrer);
```

#### 10.4 User Acceptance Testing
- [ ] Have a real user test the referral flow
- [ ] Verify referral link works on mobile
- [ ] Verify balances update in real-time
- [ ] Verify earnings table shows new entries without refresh

---

### Rollback Plan

If issues are discovered:

1. **Poller Issues**: Stop the GenServer
   ```elixir
   GenServer.stop({:global, BlocksterV2.ReferralRewardPoller})
   ```

2. **Contract Issues**:
   - Set basis points to 0: `setReferralBasisPoints(0)`
   - This disables rewards without needing a contract upgrade

3. **Mnesia Issues**:
   - Tables can be deleted if needed (data loss)
   - Or individual records can be corrected

4. **Full Rollback**:
   - Revert code to previous version
   - Set contract basis points to 0
   - Mnesia tables can remain (no harm)

---

### Success Criteria

- [ ] Users can share referral links
- [ ] New signups via referral link credit the referrer
- [ ] Phone verification rewards the referrer
- [ ] Losing bets trigger on-chain referral rewards
- [ ] Referrer balances update in real-time
- [ ] Earnings table shows all earning types
- [ ] No PostgreSQL queries in hot paths (event processing, UI rendering)
- [ ] Poller runs continuously without errors
- [ ] System handles 100+ referral events per hour without lag

---

## Implementation Progress

### Phase 1: Database & Backend Setup ✅ COMPLETED
**Date:** January 30, 2026
**Status:** All tasks complete

| Task | Status | File(s) Modified |
|------|--------|------------------|
| PostgreSQL Migration | ✅ | `priv/repo/migrations/20260131004444_add_referrer_to_users.exs` |
| Mnesia Tables | ✅ | `lib/blockster_v2/mnesia_initializer.ex` (lines 425-478) |
| User Schema | ✅ | `lib/blockster_v2/accounts/user.ex` (lines 33-36, 55-56) |
| Migration Test | ✅ | Tested migrate and rollback |

**Notes:**
- Migration adds `referrer_id` (FK to users) and `referred_at` (utc_datetime) to users table
- Four Mnesia tables added: `:referrals`, `:referral_earnings`, `:referral_stats`, `:referral_poller_state`
- Tables added at END of `@tables` list to maintain storage layout compatibility
- `:referral_earnings` uses `type: :bag` to allow multiple earnings per referrer
- User schema now has `belongs_to :referrer` and `has_many :referees` associations
- **IMPORTANT:** Must restart both nodes to create the new Mnesia tables before testing Phase 2

### Phase 2: Core Elixir Modules 🔄 PENDING
**Status:** Not started

| Task | Status | File(s) to Create/Modify |
|------|--------|--------------------------|
| Referrals Module | ⏳ | `lib/blockster_v2/referrals.ex` |
| ReferralRewardPoller | ⏳ | `lib/blockster_v2/referral_reward_poller.ex` |
| Supervision Tree | ⏳ | `lib/blockster_v2/application.ex` |

### Phase 3: Frontend JavaScript ✅ COMPLETED (Jan 30, 2026)
**Status:** Completed

| Task | Status | File(s) Modified |
|------|--------|--------------------------|
| Referral Code Capture | ✅ | `assets/js/home_hooks.js` (HomeHooks.captureReferrerCode) |
| Signup Flow Integration | ✅ | `assets/js/home_hooks.js` (ThirdwebLogin.authenticateEmail) |

**Changes Made:**
- Added `captureReferrerCode()` to `HomeHooks.mounted()` - captures `?ref=0x...` from URL
- Added `getReferrerCode()` and `clearReferrerCode()` helpers to `ThirdwebLogin`
- Modified `authenticateEmail()` to pass `referrer_wallet` in request body
- Clear referrer code after successful signup when `is_new_user` is true

### Phase 4: Backend API Integration ✅ COMPLETED (Jan 30, 2026)
**Status:** Completed

| Task | Status | File(s) Modified |
|------|--------|------------------|
| Auth Controller | ✅ | `lib/blockster_v2_web/controllers/auth_controller.ex` |
| Phone Verification | ✅ | `lib/blockster_v2/phone_verification.ex` |
| Accounts Module | ✅ | `lib/blockster_v2/accounts.ex` |

**Changes Made:**
- Modified `authenticate_email_with_fingerprint/1` to return 4-tuple `{:ok, user, session, is_new_user}`
- Updated `create_new_user_with_fingerprint/1` to return `true` for `is_new_user`
- Updated `authenticate_existing_user_with_fingerprint/2` to return `false` for `is_new_user`
- Added `Referrals` alias to auth controller
- Extract `referrer_wallet` from params in `verify_email/2`
- Call `Referrals.process_signup_referral(user, referrer_wallet)` for new users with referrer
- Return `is_new_user` in JSON response for frontend to clear referrer code
- Added `Referrals` alias to phone verification module
- Call `Referrals.process_phone_verification_reward(user_id)` after successful phone verification

### Phase 5: BuxMinter Service Updates ✅ COMPLETED (Jan 30, 2026)
**Status:** Completed

| Task | Status | File(s) Modified |
|------|--------|------------------|
| set-player-referrer Endpoint | ✅ | `bux-minter/index.js` |
| BuxMinter Elixir Client | ✅ | `lib/blockster_v2/bux_minter.ex` |

**Changes Made to `bux-minter/index.js`:**

1. **Added ABI entries for setPlayerReferrer:**
   ```javascript
   // Added to BUXBOOSTER_ABI (line ~311-312):
   'function setPlayerReferrer(address player, address referrer) external',
   'function playerReferrers(address player) external view returns (address)',

   // Added to ROGUE_BANKROLL_ABI (line ~344-345):
   'function setPlayerReferrer(address player, address referrer) external',
   'function playerReferrers(address player) external view returns (address)'
   ```

2. **Created writable contract instances using referral admin wallets (line ~355-385):**
   ```javascript
   // Referral admin wallets (separate from contract owner - can only call setPlayerReferrer)
   let referralAdminBBWallet = null;
   let referralAdminRBWallet = null;

   if (REFERRAL_ADMIN_BB_PRIVATE_KEY) {
     referralAdminBBWallet = new ethers.Wallet(REFERRAL_ADMIN_BB_PRIVATE_KEY, provider);
   }

   if (REFERRAL_ADMIN_RB_PRIVATE_KEY) {
     referralAdminRBWallet = new ethers.Wallet(REFERRAL_ADMIN_RB_PRIVATE_KEY, provider);
   }

   // ROGUEBankroll writable contract instance (for setPlayerReferrer)
   let rogueBankrollWriteContract = null;
   if (referralAdminRBWallet) {
     rogueBankrollWriteContract = new ethers.Contract(ROGUE_BANKROLL_ADDRESS, ROGUE_BANKROLL_ABI, referralAdminRBWallet);
   }

   // BuxBoosterGame writable contract instance (for setPlayerReferrer)
   let buxBoosterReferralContract = null;
   if (referralAdminBBWallet) {
     buxBoosterReferralContract = new ethers.Contract(BUXBOOSTER_CONTRACT_ADDRESS, BUXBOOSTER_ABI, referralAdminBBWallet);
   }
   ```

3. **Added POST /set-player-referrer endpoint (line ~685-780):**
   - Validates player and referrer addresses (must be valid Ethereum addresses)
   - Prevents self-referral (player !== referrer)
   - Checks if referrer already set on each contract before attempting transaction
   - Sets referrer on **both** contracts:
     - `BuxBoosterGame.setPlayerReferrer(player, referrer)` - for BUX token bets
     - `ROGUEBankroll.setPlayerReferrer(player, referrer)` - for ROGUE native token bets
   - Returns 409 Conflict if referrer already set on both contracts
   - Returns success with transaction hashes for each contract

   **Request:**
   ```json
   POST /set-player-referrer
   Authorization: Bearer <API_SECRET>
   {
     "player": "0x1234...player_wallet",
     "referrer": "0x5678...referrer_wallet"
   }
   ```

   **Response (success):**
   ```json
   {
     "success": true,
     "player": "0x1234...",
     "referrer": "0x5678...",
     "results": {
       "buxBoosterGame": { "success": true, "txHash": "0xabc...", "error": null },
       "rogueBankroll": { "success": true, "txHash": "0xdef...", "error": null }
     }
   }
   ```

   **Response (already set):**
   ```json
   HTTP 409 Conflict
   {
     "error": "Referrer already set on both contracts",
     "results": {
       "buxBoosterGame": { "success": false, "txHash": null, "error": "Referrer already set" },
       "rogueBankroll": { "success": false, "txHash": null, "error": "Referrer already set" }
     }
   }
   ```

**Changes Made to `lib/blockster_v2/bux_minter.ex`:**

Added `set_player_referrer/2` function (line ~350-403):
```elixir
@doc """
Sets a player's referrer on both BuxBoosterGame and ROGUEBankroll contracts.
Called when a new user signs up with a referral link.

## Parameters
  - player_wallet: The new user's smart wallet address
  - referrer_wallet: The referrer's smart wallet address

## Returns
  - {:ok, results} on success (at least one contract succeeded)
  - {:error, :already_set} if referrer already set on both contracts
  - {:error, reason} on failure
"""
def set_player_referrer(player_wallet, referrer_wallet)
```

**Integration with Referrals Module:**
The `Referrals.sync_referral_to_chain/1` function (implemented in Phase 2) calls this:
```elixir
def sync_referral_to_chain(user_id) do
  case get_referral(user_id) do
    {:ok, referral} when not referral.on_chain_synced ->
      case BuxMinter.set_player_referrer(referral.referee_wallet, referral.referrer_wallet) do
        {:ok, _} -> mark_on_chain_synced(user_id)
        {:error, :already_set} -> mark_on_chain_synced(user_id)
        {:error, reason} -> {:error, reason}
      end
    _ -> :ok
  end
end
```

**Prerequisites for Testing:**
- `REFERRAL_ADMIN_BB_PRIVATE_KEY` must be set in bux-minter environment (for BuxBoosterGame)
- `REFERRAL_ADMIN_RB_PRIVATE_KEY` must be set in bux-minter environment (for ROGUEBankroll)
- Smart contracts must be upgraded to include `setPlayerReferrer` function (Phase 6)
- Referral admin must be configured on both contracts via `setReferralAdmin()`

**Deployment Notes:**
- BuxMinter service must be redeployed: `cd bux-minter && flyctl deploy`
- No database migration required for this phase

### Phase 6: Smart Contract Updates ✅ COMPLETE
**Status:** Deployed to Rogue Chain Mainnet
**Completed:** January 31, 2026

#### Deployment Summary

**BuxBoosterGame V6 (BUX Referral Rewards):**
| Item | Value |
|------|-------|
| Proxy Address | `0x97b6d6A8f2c6AF6e6fb40f8d36d60DF2fFE4f17B` |
| New Implementation | `0x50DB48a39BE732577b66e90669E8707aa54A1468` |
| Upgrade TX | `0x2c2248c8f89cdaa94fa736ad0181c1ac533b7d815a7651b3c0b4aed788679882` |
| InitializeV6 TX | `0x855c699e551d8b53b53cc22f65172d9d18b52c623138a70c434bf97962c2de34` |
| Set Admin TX | `0xccfd3cbb3b6ccc8c416b09d64a487308909b6c7ae87277c10af0fc771277cea9` |
| buxReferralBasisPoints | 100 (1%) |
| referralAdmin | `0xbD6feD8fEeec6f405657d0cA4A004f89F81B04ad` |

**ROGUEBankroll V8 (ROGUE Referral Rewards):**
| Item | Value |
|------|-------|
| Proxy Address | `0x51DB4eD2b69b598Fade1aCB5289C7426604AB2fd` |
| referralBasisPoints | 20 (0.2%) |
| referralAdmin | `0x138742ae11E3848E9AF42aC0B81a6712B8c46c11` |

**Deployment Notes:**
- BuxBoosterGame upgrade encountered nginx 500 errors due to `client_max_body_size` limit on RPC server
- Issue resolved by increasing nginx body size limit
- See `docs/RPC_500_ERROR_REPORT.md` for detailed troubleshooting documentation

| Task | Status | Contract |
|------|--------|----------|
| BuxBoosterGame Referral Storage | ✅ | `contracts/bux-booster-game/contracts/BuxBoosterGame.sol` |
| BuxBoosterGame _sendBuxReferralReward | ✅ | Same |
| BuxBoosterGame initializeV6 | ✅ | Same |
| BuxBoosterGame Upgrade Script | ✅ | `contracts/bux-booster-game/scripts/upgrade-to-v6.js` |
| ROGUEBankroll Referral Storage | ✅ | `contracts/bux-booster-game/contracts/ROGUEBankroll.sol` |
| ROGUEBankroll _sendReferralReward | ✅ | Same |
| Contracts Compilation | ✅ | Both compile successfully |

#### 6.1 BuxBoosterGame.sol Changes (V6)

**Storage Variables Added** (after line 557, preserving storage layout):
```solidity
// V6: Referral system (add at end to preserve storage layout)
uint256 public buxReferralBasisPoints;                              // 100 = 1%
mapping(address => address) public playerReferrers;                 // player => referrer
mapping(address => uint256) public totalReferralRewardsPaid;        // token => total paid
mapping(address => mapping(address => uint256)) public referrerTokenEarnings;  // referrer => token => earned
```

**Events Added** (after line 553):
```solidity
event ReferralRewardPaid(
    bytes32 indexed commitmentHash,
    address indexed referrer,
    address indexed player,
    address token,
    uint256 amount
);
event ReferrerSet(address indexed player, address indexed referrer);
```

**Functions Added:**
- `initializeV6()` - Sets `buxReferralBasisPoints` to 100 (1%)
- `setBuxReferralBasisPoints(uint256)` - Owner only, max 1% (100 basis points)
- `getBuxReferralBasisPoints()` - View function
- `getTotalReferralRewardsPaid(address token)` - View function
- `getReferrerTokenEarnings(address referrer, address token)` - View function
- `setPlayerReferrer(address player, address referrer)` - Owner only, one-time set
- `setPlayerReferrersBatch(address[] players, address[] referrers)` - Batch set
- `getPlayerReferrer(address player)` - View function
- `_sendBuxReferralReward(bytes32 commitmentHash, Bet storage bet)` - Private, called on losing bets

**Integration Point** (`_processSettlement` function, losing branch):
```solidity
} else {
    payout = 0;
    bet.status = BetStatus.Lost;
    config.houseBalance += bet.amount;
    stats.overallProfitLoss -= int256(bet.amount);
    stats.profitLossPerDifficulty[diffIndex] -= int256(bet.amount);

    // V6: Send referral reward on losing BUX bet
    _sendBuxReferralReward(bet.commitmentHash, bet);
}
```

**Upgrade Script:** `contracts/bux-booster-game/scripts/upgrade-to-v6.js`
```bash
# To deploy:
cd contracts/bux-booster-game
npx hardhat run scripts/upgrade-to-v6.js --network rogueMainnet
```

#### 6.2 ROGUEBankroll.sol Changes (V8)
**Note:** Code complete. User will upgrade manually - no upgrade script created.

**Storage Variables Added** (after line 973, after `totalNFTRewardsPaid`):
```solidity
// ===== REFERRAL SYSTEM (V8) =====
uint256 public referralBasisPoints;                    // 20 = 0.2%
mapping(address => address) public playerReferrers;    // player => referrer
uint256 public totalReferralRewardsPaid;               // total ROGUE paid to referrers
mapping(address => uint256) public referrerTotalEarnings;  // referrer => total earned
```

**Events Added** (after `NFTRewardBasisPointsChanged` event):
```solidity
event ReferralRewardPaid(
    bytes32 indexed commitmentHash,
    address indexed referrer,
    address indexed player,
    uint256 amount
);
event ReferrerSet(address indexed player, address indexed referrer);
event ReferralBasisPointsChanged(uint256 previousBasisPoints, uint256 newBasisPoints);
```

**Functions Added:**
- `setReferralBasisPoints(uint256)` - Owner only, max 10% (1000 basis points)
- `getReferralBasisPoints()` - View function
- `getReferralTotalRewardsPaid()` - View function
- `getReferrerTotalEarnings(address referrer)` - View function (per-referrer earnings)
- `setPlayerReferrer(address player, address referrer)` - Owner only, one-time set
- `setPlayerReferrersBatch(address[] players, address[] referrers)` - Batch set
- `getPlayerReferrer(address player)` - View function
- `_sendReferralReward(bytes32 commitmentHash, address player, uint256 wagerAmount)` - Private

**Integration Point** (`settleBuxBoosterLosingBet` function, after `_sendNFTReward`):
```solidity
// V7: Send NFT rewards (portion of losing bet to NFT holders)
_sendNFTReward(commitmentHash, wagerAmount);

// V8: Send referral rewards (portion of losing bet to referrer)
_sendReferralReward(commitmentHash, player, wagerAmount);
```

#### 6.3 Post-Deployment Configuration

After upgrading both contracts:

1. **BuxBoosterGame V6** - Auto-configured via `initializeV6()`:
   - `buxReferralBasisPoints` = 100 (1%)

2. **ROGUEBankroll V8** - Manual configuration required:
   ```javascript
   // Set ROGUE referral basis points to 20 (0.2%)
   await rogueBankroll.setReferralBasisPoints(20);
   ```

3. **Update ReferralRewardPoller** - Set `@deploy_block` to the block number when contracts were upgraded

#### 6.4 Event Topics for Poller

**BuxBoosterGame ReferralRewardPaid:**
```
keccak256("ReferralRewardPaid(bytes32,address,address,address,uint256)")
```
- Topics: [event_sig, commitmentHash, referrer, player]
- Data: [token (address), amount (uint256)]

**ROGUEBankroll ReferralRewardPaid:**
```
keccak256("ReferralRewardPaid(bytes32,address,address,uint256)")
```
- Topics: [event_sig, commitmentHash, referrer, player]
- Data: [amount (uint256)]

#### 6.5 Compilation Verification
```bash
cd contracts/bux-booster-game
npx hardhat compile
# Output: Compiled 2 Solidity files successfully (evm target: paris)
```

Both contracts compile with no errors. There is one pre-existing shadowing warning in ROGUEBankroll.sol (unrelated to referral changes).

### Phase 7: LiveView UI ✅ COMPLETED (Jan 31, 2026)
**Status:** Completed

| Task | Status | File(s) Modified |
|------|--------|------------------|
| Members Page Refer Tab Logic | ✅ | `lib/blockster_v2_web/live/member_live/show.ex` |
| Members Page Template | ✅ | `lib/blockster_v2_web/live/member_live/show.html.heex` |

**Implementation Notes:**
- Added `Referrals` alias and loaded referral data in `handle_params/3`
- Added PubSub subscription for real-time earnings updates
- Added event handlers: `copy_referral_link`, `load_more_earnings`
- Added `handle_info({:referral_earning, earning}, ...)` for live updates
- Added helper functions: `generate_referral_link/1`, `format_referral_number/1`, `truncate_wallet/1`, `earning_type_label/1`, `earning_type_style/1`, `format_relative_time/1`, `is_recent_earning?/1`
- Refer tab only visible on own profile (`@is_own_profile`)
- Infinite scroll with 50 earnings per batch

### Phase 8: Testing ✅ COMPLETED (Jan 31, 2026)
**Status:** Complete

| Task | Status | File(s) Created |
|------|--------|-----------------|
| Unit Tests - Referrals Module | ✅ | `test/blockster_v2/referrals_test.exs` (32 tests) |
| Integration Tests - MemberLive | ✅ | `test/blockster_v2_web/live/member_live/referral_test.exs` |
| Local E2E Test | ⏳ | Manual testing checklist in Phase 8.3 |

**Bug Fixes:**
- Fixed `DateTime.utc_now()` microsecond issue in `Referrals.process_signup_referral/2`
- Fixed `list_referrals/2` phone_verified check (was using wrong index)

### Phase 9-10: Deployment, Monitoring 🔄 PENDING
**Status:** Not started

---

## Quick Reference

### File Locations
```
Phase 1 (DONE):
├── priv/repo/migrations/20260131004444_add_referrer_to_users.exs  # PostgreSQL migration
├── lib/blockster_v2/mnesia_initializer.ex                         # Mnesia table definitions
└── lib/blockster_v2/accounts/user.ex                              # User schema

Phase 2 (TODO):
├── lib/blockster_v2/referrals.ex                                  # Main referral module
├── lib/blockster_v2/referral_reward_poller.ex                     # Event poller GenServer
└── lib/blockster_v2/application.ex                                # Supervision tree

Phase 3-4 (TODO):
├── assets/js/app.js or assets/js/referral.js                      # Frontend capture
├── lib/blockster_v2_web/controllers/auth_controller.ex            # Signup integration
└── lib/blockster_v2/phone_verification.ex                         # Phone verify integration

Phase 5 (DONE):
├── bux-minter/index.js                                            # POST /set-player-referrer endpoint
└── lib/blockster_v2/bux_minter.ex                                 # set_player_referrer/2 client function

Phase 6 (DONE):
├── contracts/bux-booster-game/contracts/BuxBoosterGame.sol        # BUX referral rewards (V6)
├── contracts/bux-booster-game/contracts/ROGUEBankroll.sol         # ROGUE referral rewards (V8)
└── contracts/bux-booster-game/scripts/upgrade-to-v6.js            # BuxBoosterGame upgrade script

Phase 7 (DONE):
├── lib/blockster_v2_web/live/member_live/show.ex                  # Refer tab logic
└── lib/blockster_v2_web/live/member_live/show.html.heex           # Refer tab UI
```

### Mnesia Record Tuple Sizes (for match patterns)
```elixir
# :referrals - 7 elements
{:referrals, user_id, referrer_id, referrer_wallet, referee_wallet, referred_at, on_chain_synced}

# :referral_earnings - 11 elements
{:referral_earnings, id, referrer_id, referrer_wallet, referee_wallet, earning_type, amount, token, tx_hash, commitment_hash, timestamp}

# :referral_stats - 7 elements
{:referral_stats, user_id, total_referrals, verified_referrals, total_bux_earned, total_rogue_earned, updated_at}

# :referral_poller_state - 4 elements
{:referral_poller_state, key, last_block, updated_at}
```

### Earning Types
```elixir
:signup           # 100 BUX - when referred user signs up
:phone_verified   # 100 BUX - when referred user verifies phone
:bux_bet_loss     # 1% of losing BUX bet amount
:rogue_bet_loss   # 0.2% of losing ROGUE bet amount
:shop_purchase    # (Future) percentage of shop purchase
```
