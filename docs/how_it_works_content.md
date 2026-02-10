# How Blockster Works - Content Guide

> **Document Purpose**: This markdown file contains all the accurate, up-to-date content for the Blockster "How It Works" page. Last updated: February 2026.

---

## Overview

Blockster is Web3's daily content hub where you **earn BUX tokens** by reading articles, watching videos, sharing on X (Twitter), and engaging with the crypto community. BUX can be used for **shop discounts**, played in **BUX Booster** (a provably fair coin flip game), and more.

**Key Points:**
- **BUX** is the only reward token (hub tokens like moonBUX were removed in Jan 2026)
- All rewards are on-chain via **Rogue Chain**
- No subscription tiers - everyone earns based on their engagement and verification level
- Smart wallet technology means **no gas fees** for users

---

## Powered by Rogue Chain

Everything on Blockster runs on **Rogue Chain**, a high-performance blockchain built for the Blockster ecosystem.

### What is Rogue Chain?
- A dedicated blockchain (Chain ID: 560013) optimized for Blockster
- Fast, low-cost transactions
- Home to both BUX (reward token) and ROGUE (native gas token)

### What is ROGUE?
**ROGUE is the native gas token of Rogue Chain** - similar to how ETH is the native token of Ethereum.

**Why ROGUE matters:**
- **Powers the network** - All transactions on Rogue Chain use ROGUE for gas
- **Boosts your earnings** - Hold ROGUE in your Blockster wallet to earn up to 5x more BUX
- **Bet with ROGUE** - Play BUX Booster using ROGUE for potentially bigger wins
- **No gas fees for you** - Blockster sponsors gas via smart wallets, but ROGUE powers it behind the scenes

### Get ROGUE

ROGUE is available on Arbitrum and can be easily bridged to Rogue Chain:

1. **Buy ROGUE on Arbitrum**: Swap ETH or other tokens for ROGUE on [Uniswap (Arbitrum)](https://app.uniswap.org)
2. **Bridge to Rogue Chain**: Use the [Rogue Trader Bridge](https://roguetrader.io/bridge) to move ROGUE from Arbitrum to Rogue Chain instantly and virtually free
3. **Bridge back anytime**: ROGUE can be bridged back and forth between Arbitrum and Rogue Chain whenever you want

**Useful Links:**
- [CoinGecko](https://www.coingecko.com/en/coins/rogue) - Price info and market data
- [Uniswap (Arbitrum)](https://app.uniswap.org) - Buy ROGUE
- [Rogue Trader Bridge](https://roguetrader.io/bridge) - Bridge between Arbitrum ↔ Rogue Chain

### Block Explorer
View all transactions, contracts, and wallet activity on [RogueScan](https://roguescan.io)

---

## 1. Earning BUX

### 1.1 Reading Articles

**How it works:**
1. Read any article on Blockster
2. Your engagement is tracked (time spent, scroll depth)
3. When you finish reading, BUX is automatically minted to your wallet

**Engagement Score (1-10):**
| Component | Points | How to Earn |
|-----------|--------|-------------|
| Base | 1 | Just visiting the article |
| Time Score | 0-6 | Spend time reading (100% of expected time = 6 pts) |
| Depth Score | 0-3 | Scroll through article (100% = 3 pts) |

**Formula:**
```
BUX Earned = (Engagement Score / 10) × Base Reward × Your Multiplier
```

**Example:** Article with 10 BUX base reward
- You read fully (score: 8/10)
- Your multiplier: 2.0x
- **You earn: 16 BUX**

### 1.2 Watching Videos

**How it works:**
1. Watch videos embedded in articles
2. Your watch time is tracked
3. BUX is earned based on minutes watched

**Formula:**
```
BUX Earned = Minutes Watched × BUX Per Minute × Your Multiplier
```

**Example:** Video with 1 BUX per minute rate
- You watch for 5 minutes
- Your multiplier: 2.0x
- **You earn: 10 BUX**

### 1.3 Sharing on X (Twitter)

**How it works:**
1. Connect your X account via OAuth
2. Find an article with a share campaign (shows "Earn +X BUX" badge)
3. Click "Retweet & Like" to share
4. BUX is automatically minted when verified

**Share Reward:**
- Your X Account Quality Score (0-100) = BUX earned per share
- Higher quality X accounts earn more
- Example: Score of 50 = 50 BUX per share

**X Quality Score Components:**
| Factor | Max Points | What's Measured |
|--------|-----------|-----------------|
| Follower Quality | 25 | Follower/following ratio |
| Engagement Rate | 35 | Likes, retweets, replies on your tweets |
| Account Age | 10 | Years since account created |
| Activity Level | 15 | Tweets per month |
| List Presence | 5 | How many lists you're on |
| Follower Scale | 10 | Total follower count (logarithmic) |

### 1.4 Referrals

**Earn BUX for bringing friends:**
- **100 BUX** when someone signs up with your referral link
- **100 BUX** when they verify their phone number
- **1% of their losing BUX bets** in BUX Booster (ongoing)

**Your referral link:** `https://blockster.com?ref=YOUR_WALLET_ADDRESS`

---

## 2. Earning Power Multiplier

Your **multiplier** increases how much BUX you earn from reading. It's calculated by multiplying four factors together:

### Overall Formula:
```
Your Multiplier = X Multiplier × Phone Multiplier × ROGUE Multiplier × Wallet Multiplier
```

**Range: 0.5x to 360x**

### 2.1 X Account Multiplier (1.0x - 10.0x)

Connect your X account to boost earnings:
| X Quality Score | Multiplier |
|-----------------|-----------|
| 0-10 | 1.0x |
| 30 | 3.0x |
| 50 | 5.0x |
| 75 | 7.5x |
| 100 | 10.0x |

### 2.2 Phone Verification Multiplier (0.5x - 2.0x)

Verify your phone number to unlock earnings:
| Status | Multiplier |
|--------|-----------|
| Not verified | **0.5x** (penalty) |
| Verified (other countries) | 1.0x |
| Verified (BR, MX, EU, JP, KR) | 1.5x |
| Verified (US, CA, UK, AU, DE, FR) | **2.0x** |

**Important:** Without phone verification, you earn at 0.5x (half rate).

### 2.3 ROGUE Multiplier (1.0x - 5.0x)

Hold ROGUE tokens in your Blockster smart wallet:
| ROGUE Balance | Multiplier |
|---------------|-----------|
| 0 - 99,999 | 1.0x |
| 100,000 | 1.4x |
| 250,000 | 2.0x |
| 500,000 | 3.0x |
| 750,000 | 4.0x |
| 1,000,000+ | **5.0x** (max) |

**Where to get ROGUE:** Buy on [Uniswap (Arbitrum)](https://app.uniswap.org) and bridge to Rogue Chain via [Rogue Trader Bridge](https://roguetrader.io/bridge)

### 2.4 External Wallet Multiplier (1.0x - 3.6x)

Connect an external wallet (MetaMask, etc.) with ETH and other tokens:

**ETH Holdings:**
| ETH Balance | Boost |
|-------------|-------|
| 0.01 - 0.09 | +0.1x |
| 0.1 - 0.49 | +0.3x |
| 0.5 - 0.99 | +0.5x |
| 1.0 - 2.49 | +0.7x |
| 2.5 - 4.99 | +0.9x |
| 5.0 - 9.99 | +1.1x |
| 10.0+ | +1.5x |

**Other tokens (USDC, USDT, ARB):** Up to +1.0x based on USD value

### Example Multiplier Calculations

**New User (no verifications):**
- X: 1.0x × Phone: 0.5x × ROGUE: 1.0x × Wallet: 1.0x = **0.5x**

**Verified User:**
- X: 3.0x × Phone: 2.0x × ROGUE: 1.0x × Wallet: 1.0x = **6.0x**

**Power User:**
- X: 5.0x × Phone: 2.0x × ROGUE: 3.0x × Wallet: 1.5x = **45.0x**

**Whale (maxed out):**
- X: 10.0x × Phone: 2.0x × ROGUE: 5.0x × Wallet: 3.6x = **360.0x**

---

## 3. BUX Booster Game

**BUX Booster** is a **provably fair**, **self-custodial**, **decentralized** coin flip game powered by verified smart contracts on Rogue Chain.

**All betting happens on Rogue Chain.** If you want to bet with ROGUE, you can easily buy it on [Uniswap (Arbitrum)](https://app.uniswap.org) and bridge it to Rogue Chain using the [Rogue Trader Bridge](https://roguetrader.io/bridge) - instant and virtually free.

### Why BUX Booster is Different

**Truly Decentralized:**
- All game logic runs on verified smart contracts on a public blockchain
- Your funds stay in YOUR wallet until you place a bet
- Instant payouts directly to your wallet - no withdrawal requests
- Every transaction is publicly verifiable on [RogueScan](https://roguescan.io)
- No middlemen, no custodians, no trust required

**100% Transparent:**
- Smart contracts are verified and open source
- All bets, results, and payouts visible on-chain
- Provably fair randomness you can verify yourself
- House bankroll balance publicly visible at all times

### Bet with BUX or ROGUE

**BUX Betting:**
- Use your earned BUX tokens
- Win more BUX based on multiplier
- Great for playing with your reading rewards
- Instant payouts to your wallet

**ROGUE Betting - Peer-to-Peer Against the House:**
- Bet with ROGUE (the native gas token of Rogue Chain)
- **All ROGUE bets are peer-to-peer** against the ROGUE House Bankroll
- The bankroll holds **66% of the entire ROGUE supply** staked by liquidity providers
- Faster transactions (no token approval needed)
- Instant payouts from the bankroll smart contract

### Be the House - Earn from the Bankroll

**Anyone can become the house** by depositing ROGUE into the bankroll:
- Deposit ROGUE to provide liquidity for player bets
- Earn your proportional share of house profits
- The house has a mathematical edge on all bets
- Withdraw your ROGUE + earnings anytime
- Fully decentralized - no permission needed

Learn more: [ROGUE Bankroll](https://roguetrader.io/rogue-bankroll)

### How to Play:
1. Go to [/play](/play)
2. Select your token (BUX or ROGUE)
3. Choose difficulty level
4. Enter bet amount
5. Make your predictions (Heads 🚀 or Tails 💩)
6. Click "Place Bet"
7. **Instant payout** directly to your wallet if you win

### Difficulty Levels

**Win One Mode** (need 1 correct flip):
| Level | Flips | Multiplier | Win Chance |
|-------|-------|-----------|------------|
| Easy | 5 | 1.02x | 96.9% |
| Medium | 4 | 1.05x | 93.8% |
| Hard | 3 | 1.13x | 87.5% |
| Expert | 2 | 1.32x | 75% |

**Win All Mode** (need all correct):
| Level | Flips | Multiplier | Win Chance |
|-------|-------|-----------|------------|
| 1 Flip | 1 | 1.98x | 50% |
| 2 Flips | 2 | 3.96x | 25% |
| 3 Flips | 3 | 7.92x | 12.5% |
| 4 Flips | 4 | 15.84x | 6.25% |
| 5 Flips | 5 | 31.68x | 3.125% |

### Provably Fair

Every game uses cryptographic commitments that YOU can verify:

**How it works:**
1. **Before your bet:** Server commits to a random seed (you see the hash)
2. **You place bet:** Your predictions create a client seed
3. **After result:** Server reveals the seed - you can verify it matches the commitment

**What this means:**
- The server CANNOT change the outcome after seeing your bet
- YOU can independently verify every single game
- No trust required - math proves fairness

**Verify any game:** Click "Verify Fairness" after any bet to see:
- The commitment hash (shown before your bet)
- The revealed server seed (matches the commitment)
- The client seed (derived from your bet details)
- The exact calculation that produced your result

You can verify these values yourself using any SHA-256 calculator.

---

## 4. Shop Discounts

Use your BUX to get discounts on products in the [Blockster Shop](/shop).

### How It Works:
1. Browse products in the shop
2. Each product shows maximum BUX discount (e.g., "Up to 50% off with BUX")
3. At checkout, choose how many BUX to redeem
4. **1 BUX = 0.01 USD discount**

### Example:
- Product: 100 USD
- Max discount: 100%
- Max BUX to redeem: 10,000 BUX
- Your BUX balance: 10,000 BUX
- **Your price: FREE** (saved 100 USD with BUX)

---

## 5. Hubs

Hubs are themed communities within Blockster, each focused on different crypto projects and topics.

### Features:
- **Curated content** - Articles and videos specific to each hub
- **Hub-specific products** - Exclusive merch from partner projects
- **Community** - Follow hubs to customize your feed

### Browse Hubs: [/hubs](/hubs)

Popular hubs: MoonPay, Flare, Neo, Solana, Tron, and more.

---

## 6. Getting Started

### Step 1: Create Account
Connect your wallet (MetaMask, WalletConnect, or others) to create your account. Blockster creates a **smart wallet** for you automatically - no gas fees needed.

### Step 2: Verify Phone (Important!)
Verify your phone number to unlock full earning power. Without verification, you earn at 0.5x rate.

### Step 3: Connect X Account
Link your X (Twitter) account to:
- Earn BUX for sharing articles
- Get an X quality score that boosts your multiplier

### Step 4: Start Reading
Browse articles and start earning! Your BUX is minted automatically when you finish reading.

### Step 5: Explore More
- **Shop:** Use BUX for discounts
- **BUX Booster:** Play the coin flip game
- **Hubs:** Follow communities you're interested in
- **Hold ROGUE:** Boost your earning power even more

---

## Quick Reference

### Token Values
| Token | Purpose | Value |
|-------|---------|-------|
| BUX | Reading rewards, shop discounts, betting | 1 BUX = 0.01 USD discount |
| ROGUE | Native chain token, multiplier boost, betting | [CoinGecko Price](https://www.coingecko.com/en/coins/rogue) |

### Key Links
- **Shop:** [/shop](/shop)
- **BUX Booster:** [/play](/play)
- **Hubs:** [/hubs](/hubs)
- **Your Profile:** [/members/me](/members/me)

### Support
- **X/Twitter:** [@BlocksterCom](https://x.com/BlocksterCom)
- **RogueScan:** [roguescan.io](https://roguescan.io)

---

## Technical Details

### Blockchain
- **Network:** Rogue Chain (Chain ID: 560013)
- **Explorer:** [roguescan.io](https://roguescan.io)
- **Account Abstraction:** ERC-4337 smart wallets with Paymaster (gasless)

### BUX Token Contract
- **Address:** `0x8E3F9fa591cC3E60D9b9dbAF446E806DD6fce3D8`
- **Type:** ERC-20 on Rogue Chain

### Smart Wallet
Your Blockster account uses an ERC-4337 smart wallet. Benefits:
- No gas fees (sponsored by Blockster)
- No seed phrases to manage
- Secure recovery options

---

*This documentation reflects Blockster as of February 2026. Features may be updated over time.*
