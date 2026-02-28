# FateSwap — Branding, Marketing & Social Sharing System

> **Status**: Planning
> **Scope**: Brand identity, messaging framework, share card system, automated X content engine, technical specs for LiveView implementation

---

## Table of Contents

1. [Brand Identity](#1-brand-identity)
2. [Messaging Framework](#2-messaging-framework)
3. [In-Product Language System](#3-in-product-language-system)
4. [Share Cards — "Fate Receipts"](#4-share-cards--fate-receipts)
5. [Referral Link System](#5-referral-link-system)
6. [Social Sharing Integration](#6-social-sharing-integration)
7. [Automated X Content Engine](#7-automated-x-content-engine)
8. [Telegram Automation](#8-telegram-automation)
9. [Technical Architecture](#9-technical-architecture)
10. [Marketing Campaigns](#10-marketing-campaigns)
11. [Community & Culture Building](#11-community--culture-building)

---

## 1. Brand Identity

### Name: FateSwap

One word. The name is the strongest option because:
- "Fate" personalizes randomness — "fate decided" is dramatic, not demoralizing
- "Swap" anchors the product firmly in DeFi, not gambling
- Creates a natural verb: "I fate-swapped my BONK"
- Two syllables total, easy to say, type, and search
- Domain / handle availability: `fateswap.com`, `@FateSwap`

### Visual Identity: "The Slider" (Product-as-Brand)

The fate slider gradient IS the brand. The green-to-red spectrum appears everywhere — logo, share cards, UI, social assets. Every screenshot of the product is a marketing asset.

| Element | Spec |
|---------|------|
| **Primary BG** | Near-black `#0A0A0F` |
| **Card BG** | Dark gray `#14141A` with subtle `1px` border `rgba(255,255,255,0.06)` |
| **Brand gradient** | `#22C55E` (green, safe) -> `#EAB308` (yellow, conviction) -> `#EF4444` (red, degen) |
| **Text primary** | Off-white `#E8E4DD` |
| **Text secondary** | Muted `#6B7280` |
| **Accent (fills)** | Green `#22C55E` |
| **Accent (not filled)** | Muted red `#8B2500` (not harsh red — dramatic, not punishing) |
| **Fate fee / data** | Cool gray `#9CA3AF` |
| **Typography (wordmark)** | Clean geometric sans-serif (Satoshi or Inter) |
| **Typography (data)** | Monospace (JetBrains Mono or similar) |

### Logo Concept

The word "FATESWAP" in a geometric sans-serif with the letters transitioning through the brand gradient from green (F) to red (P). Alternatively, just the letter "F" rendered in the gradient for a compact icon mark.

No dice. No cards. No slot machines. No neon. The gradient IS the logo.

---

## 2. Messaging Framework

### Primary Tagline
> **"Trade at the price you believe in."**

Clean, confident, implies trading not gambling. This goes on the hero section, app store listing, and every formal placement.

### Secondary Taglines

| Context | Tagline | Tone |
|---------|---------|------|
| Hero section | "Trade at the price you believe in." | Clean, confident |
| CT / memes / X bio | "Sell high or die trying." | Degen, confrontational |
| Buy-side feature | "Buy the dip that doesn't exist yet." | Clever, novel |
| Onboarding tooltip | "Your price. Fate decides." | Simple, mysterious |
| Loss screen | "Fate has spoken." | Dramatic, not crushing |
| Win screen | "Order filled. Conviction rewarded." | Triumphant but restrained |
| Competitive positioning | "Jupiter gives you market price. We give you YOUR price." | Direct comparison |
| Philosophical / about page | "Every trade is a bet on your conviction." | Deepest layer |
| Viral / share card | "I just sold my BONK at 3x market. Fate allowed it." | Social proof |
| Live feed FOMO | "Someone just fate-swapped 10M WIF at 5x. It filled." | Urgency |

### Three-Layer Message Hierarchy

**Layer 1 — What is it?** (newcomers, landing page above fold)
> A DEX where you set your own sell price. The further from market, the lower the fill chance — but the higher the reward if fate fills it.

**Layer 2 — Why should I care?** (traders, feature sections)
> Stop selling at market. Name the price your bags deserve. If fate agrees, you get it.

**Layer 3 — Why is it different?** (DeFi natives, competitive positioning)
> Same swap UX you know. But with a conviction slider that turns every trade into a statement about how much you believe in your token.

---

## 3. In-Product Language System

Every piece of microcopy reinforces the DEX framing. This is non-negotiable — consistency here is what makes the product feel like a DEX and not a casino.

### Core Term Mapping

| Moment | Never Say (casino) | Always Say (FateSwap) |
|--------|--------------------|-----------------------|
| Starting a trade | "Place your bet" | "Set your price" |
| Choosing multiplier | "Pick your odds" | "Set your target" |
| Confirming | "Confirm bet" | "Submit fate order" |
| Waiting | "Spinning..." | "Resolving order..." |
| Win | "You won!" | "Order filled" |
| Loss | "You lost" | "Not filled — tokens claimed by fate" |
| History | "Bet history" | "Order history" |
| Probability | "Win chance" | "Fill chance" |
| Fee | "House edge" | "Fate fee" |
| High-risk | "Risky bet!" | "Low fill probability" |

### Slider Personality Tiers

As the user drags the fate slider, the UI copy shifts tone:

| Multiplier Range | Label | Subtitle | Gradient Position |
|-----------------|-------|----------|-------------------|
| 1.01x – 1.24x | "Safe Limit" | "Almost a regular swap." | Green |
| 1.25x – 1.49x | "Optimistic" | "You see something the market doesn't." | Yellow-green |
| 1.50x – 1.99x | "Conviction" | "Bold. Let's see if fate agrees." | Yellow |
| 2.00x – 4.99x | "Moonshot" | "This is what conviction looks like." | Orange |
| 5.00x – 10.0x | "Full Degen" | "You're either a genius or a legend." | Red |

### Result Overlays

**Filled (win)**:
```
ORDER FILLED
You received 1.87 SOL
+87% above market price
Conviction: rewarded
[Share on X]  [Share on Telegram]  [New Order]
```

**Not Filled (loss)**:
```
NOT FILLED
Tokens claimed by fate
Target was 3.2x market — fill chance was 30.8%
"The thread was cut."
[Share on X]  [Share on Telegram]  [Try Again]
```

---

## 4. Share Cards — "Fate Receipts"

Share cards are auto-generated images after every trade. They are the primary viral growth engine. People share wins to flex and losses to show they went out swinging.

### Card Dimensions & Format

| Property | Value |
|----------|-------|
| Dimensions | 1200 x 630 px (1.91:1 — optimal for X/Twitter `summary_large_image`) |
| Format | PNG (for text clarity) |
| Max file size | < 5 MB |
| Background | `#0A0A0F` (matches app dark theme) |
| Text safety zone | 10% margin from all edges |

### Card Layouts

#### Layout A: Filled Order (Win)

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  [FateSwap logo]                    fateswap.com │
│                                                  │
│  ─────────────────────────────────────────────── │
│                                                  │
│  ORDER FILLED                          [green]   │
│                                                  │
│  Sold 5,000,000 BONK at 2.4x market             │
│                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────┐ │
│  │  RECEIVED   │  │ FILL CHANCE │  │  TARGET  │ │
│  │  1.87 SOL   │  │    41.0%    │  │   2.4x   │ │
│  │  ($334)     │  │             │  │  market  │ │
│  └─────────────┘  └─────────────┘  └──────────┘ │
│                                                  │
│  ┌──────────────────────────────────────────┐    │
│  │ ■■■■■■■■■■■■■■■■□□□□□□□□□□□□□□□□□□□□□□ │    │
│  │ Conviction: ████████████▒▒▒▒▒▒▒▒▒▒▒▒▒▒ │    │
│  └──────────────────────────────────────────┘    │
│                                                  │
│  "Conviction rewarded."                          │
│                                                  │
│  ─── Try your conviction → fateswap.com/?ref=XX  │
│                                                  │
└──────────────────────────────────────────────────┘
```

#### Layout B: Not Filled (Loss)

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  [FateSwap logo]                    fateswap.com │
│                                                  │
│  ─────────────────────────────────────────────── │
│                                                  │
│  NOT FILLED                          [muted red] │
│                                                  │
│  Tried to sell 10M WIF at 5x market              │
│                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────┐ │
│  │  WOULD HAVE │  │ FILL CHANCE │  │  TARGET  │ │
│  │  RECEIVED   │  │    19.7%    │  │   5.0x   │ │
│  │  4.2 SOL    │  │             │  │  market  │ │
│  └─────────────┘  └─────────────┘  └──────────┘ │
│                                                  │
│  ┌──────────────────────────────────────────┐    │
│  │ ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■□□□□□□ │    │
│  │ Conviction: ██████████████████████████▒▒ │    │
│  └──────────────────────────────────────────┘    │
│                                                  │
│  "Fate has spoken."                              │
│                                                  │
│  ─── Test your conviction → fateswap.com/?ref=XX │
│                                                  │
└──────────────────────────────────────────────────┘
```

#### Layout C: Buy-Side Filled

```
┌──────────────────────────────────────────────────┐
│                                                  │
│  [FateSwap logo]                    fateswap.com │
│                                                  │
│  ─────────────────────────────────────────────── │
│                                                  │
│  DISCOUNT FILLED                       [green]   │
│                                                  │
│  Bought BONK at 60% off market                   │
│                                                  │
│  ┌─────────────┐  ┌─────────────┐  ┌──────────┐ │
│  │   PAID      │  │ FILL CHANCE │  │ DISCOUNT │ │
│  │  0.25 SOL   │  │    38.4%    │  │   60%    │ │
│  │  ($44.60)   │  │             │  │   off    │ │
│  └─────────────┘  └─────────────┘  └──────────┘ │
│                                                  │
│  Received 0.625 SOL worth of BONK                │
│                                                  │
│  "Fate loves a bargain hunter."                  │
│                                                  │
│  ─── Shop the discount → fateswap.com/?ref=XX   │
│                                                  │
└──────────────────────────────────────────────────┘
```

### Card Data Fields

Each share card requires the following data from the settled fate order:

```elixir
%{
  # Order info
  status: :filled | :not_filled,
  side: :sell | :buy,
  token_symbol: "BONK",
  token_amount: "5,000,000",
  target_multiplier: 2.4,
  fill_chance_percent: 41.0,

  # Financial
  sol_amount: 1.87,          # received (if filled) or would-have-received (if not)
  sol_usd_value: 334.0,      # at time of settlement

  # Referral (embedded in card + URL)
  referral_code: "greedy-hodling-otter",  # three-word code (auto-generated, maps to wallet in DB)

  # Flavor
  conviction_label: "Conviction",  # from slider tier
  quote: "Conviction rewarded.",    # dynamic based on outcome + multiplier
}
```

### Dynamic Quotes for Cards

| Outcome | Multiplier | Quote |
|---------|-----------|-------|
| Filled | < 1.5x | "Safe hands. Well played." |
| Filled | 1.5x – 2x | "Conviction rewarded." |
| Filled | 2x – 5x | "The market was wrong. You weren't." |
| Filled | > 5x | "Legendary fill. Fate bows to conviction." |
| Not filled | < 2x | "Close one. The thread was thin." |
| Not filled | 2x – 5x | "Fate has spoken." |
| Not filled | > 5x | "Full degen. Full respect." |
| Buy filled | any | "Fate loves a bargain hunter." |
| Buy not filled | any | "The discount wasn't meant to be." |

---

## 5. Referral Link System

### URL Format

```
https://fateswap.com?ref=greedy-hodling-otter
```

Every referral code is a **three-word phrase** in the format `adjective-participle-animal` (e.g., `greedy-hodling-otter`, `bold-trading-falcon`, `rekt-trading-panda`). Codes are auto-generated on first share/referral page visit and stored in the `referral_links` table mapping code → wallet address.

**Why three words instead of wallet addresses or random strings:**
- Memorable and shareable verbally ("use my code: greedy hodling otter")
- Humorous — each code is a mini personality, on-brand for FateSwap's tone
- Short enough to look clean on share cards and in URLs
- 40 × 40 × 171 = 273,600 combinations (more than enough for any realistic user base)

See `docs/fateswap_referral_words.md` for the full curated word lists and generation logic.

### Referral Embedding in Share Cards

Every share card has the referrer's link baked in at two levels:

1. **Visual**: The bottom of every card image shows `fateswap.com/?ref=greedy-hodling-otter` (three-word code)
2. **OG URL**: The `og:url` meta tag on the share page includes the full `?ref=` parameter
3. **Landing page**: When someone clicks through from X/Telegram, they land on a page with the referral code in the URL, which gets captured in `localStorage` (same pattern as Blockster V2)

### Referral Capture Flow

```
1. User A completes a fate order
2. FateSwap generates a share card image with User A's three-word referral code
3. User A shares on X — the tweet includes a link to fateswap.com/order/{order_id}?ref=greedy-hodling-otter
4. User B sees the tweet, clicks through
5. Landing page renders with OG image showing the trade result
6. JavaScript captures ?ref= into localStorage
7. User B connects wallet → server resolves code to wallet → referral stored in DB
8. On User B's first bet: set_referrer called on-chain with User A's wallet pubkey
9. User A earns 0.2% of User B's losses (tier 1)
10. If User B refers User C, User A earns 0.1% tier 2 rewards too
```

### Referral Code Validation (JavaScript)

```javascript
// Capture three-word referral code from URL on page load
const urlParams = new URLSearchParams(window.location.search);
const refCode = urlParams.get('ref');

if (refCode) {
  // Validate as three-word code: word-word-word (lowercase, hyphens)
  const threeWordRegex = /^[a-z]+-[a-z]+-[a-z]+$/;

  if (threeWordRegex.test(refCode)) {
    localStorage.setItem('fateswap_referrer', refCode);
  }
}
```

---

## 6. Social Sharing Integration

### Share Flow (User Perspective)

After every fate order settles, the result overlay includes share buttons:

```
[Share on X]  [Share on Telegram]  [Copy Link]  [Download Card]
```

Each button triggers a different sharing path, but ALL embed the referral link.

### X / Twitter Sharing

**Method**: X Tweet Intent URL with pre-filled text + link

```
https://x.com/intent/tweet?text={ENCODED_TEXT}&url={ENCODED_URL}
```

**Filled order tweet text**:
```
I just fate-swapped 5M $BONK at 2.4x market and it FILLED

Received 1.87 SOL ($334)
Fill chance was 41%

Conviction: rewarded

Try your conviction on @FateSwap
```

**Not-filled order tweet text**:
```
Went for 5x on $WIF — fate said no

Fill chance was 19.7%
Tokens claimed by fate

Full degen. Full respect.

Name your price on @FateSwap
```

**URL in tweet**: `https://fateswap.com/order/{order_id}?ref=greedy-hodling-otter`

When someone clicks this link, X renders the OG share card image as a `summary_large_image` card. The entire card is clickable and leads to the landing page with the referral code.

### Telegram Sharing

**Method**: Telegram share URL

```
https://t.me/share/url?url={ENCODED_URL}&text={ENCODED_TEXT}
```

Text is shorter for Telegram (channel-friendly):
```
Fate-swapped 5M $BONK at 2.4x → FILLED (1.87 SOL)
Try it: fateswap.com/order/{order_id}?ref=greedy-hodling-otter
```

### Copy Link

Copies the full URL with referral code to clipboard:
```
https://fateswap.com/order/{order_id}?ref=greedy-hodling-otter
```

Uses the same `CopyToClipboard` LiveView hook pattern.

### Download Card

Downloads the PNG share card image directly to the user's device. This is for people who want to post manually on Instagram, Discord, or other platforms where link previews don't show OG images.

The downloaded image file has the referral URL printed on it visually, so even without a clickable link, viewers can type the URL.

---

## 7. Automated X Content Engine

### Goal

Fully automated pipeline that posts 10-30 high-quality tweets per day to the official `@FateSwap` X account without any manual effort. Content is generated from real on-chain activity.

### Content Types

#### Type 1: Big Fill Alerts (Real-Time)

Triggered automatically when a high-value or high-multiplier order fills.

**Trigger rules**:
- Any fill > 5 SOL
- Any fill at > 3x multiplier
- Any fill streak 4+ consecutive
- Buy-side fill at > 50% discount

**Tweet format**:
```
FATE ORDER FILLED

Someone just sold 25M $BONK at 3.2x market

Received: 4.8 SOL ($856)
Fill chance was: 30.8%

The market was wrong. They weren't.

[Attached: auto-generated share card image]
```

**Volume estimate**: 5-15 per day depending on activity

#### Type 2: Big Loss Respect Posts

Triggered when someone goes for a high multiplier and misses.

**Trigger rules**:
- Any order at > 5x that doesn't fill
- Wagered amount > 2 SOL

**Tweet format**:
```
NOT FILLED

Someone went for 7x on $WIF

Full degen. Full respect.
Tokens claimed by fate.

[Attached: share card image]
```

**Volume estimate**: 3-8 per day

#### Type 3: Daily Stats Recap

Posted once daily at a fixed time (e.g., 00:00 UTC).

**Tweet format**:
```
FateSwap 24h Recap

Orders placed: 847
Orders filled: 412 (48.6%)
Volume: 1,240 SOL ($221,400)
Biggest fill: 12.4 SOL at 4.2x ($PEPE)
Most popular token: $BONK (312 orders)

Trade at the price you believe in.
```

**Volume**: 1 per day

#### Type 4: Token Leaderboard

Posted 2-3x per week.

**Tweet format**:
```
Most fate-swapped tokens this week

1. $BONK — 2,140 orders
2. $WIF — 1,876 orders
3. $PEPE — 1,203 orders
4. $POPCAT — 987 orders
5. $MYRO — 654 orders

Which token are you most convicted on?
```

**Volume**: 2-3 per week

#### Type 5: Streak Alerts

When a user hits a streak of consecutive fills.

**Tweet format**:
```
5-ORDER STREAK

Someone just filled 5 fate orders in a row

Tokens: $BONK, $WIF, $BONK, $PEPE, $WIF
Average target: 1.8x
Total received: 7.2 SOL

Conviction on a roll.
```

**Volume**: 1-3 per day

#### Type 6: Milestone Tweets

Protocol milestones posted automatically.

**Triggers**:
- Every 10,000 total orders
- Every 10,000 SOL in total volume
- Every 1,000 unique wallets
- First trade of a new token

**Tweet format**:
```
MILESTONE

FateSwap just crossed 100,000 fate orders

$487,000 in total volume
3,247 unique wallets
412 different tokens traded

Every trade is a bet on your conviction.
```

**Volume**: 1-2 per week

#### Type 7: "This Day in Fate" (Evergreen)

Daily nostalgia / highlight from past data.

**Tweet format**:
```
Exactly 30 days ago, someone fate-swapped 50M $BONK at 8.2x

It filled. 14.7 SOL received.
Fill chance was 12%.

Still the biggest fill this month.
```

**Volume**: 1 per day

### Content Scheduling & Rate Limiting

| Metric | Value |
|--------|-------|
| X API tier needed | Free (500 posts/month) or Basic ($200/mo for 50K) |
| Target daily posts | 10-30 |
| Max posts per hour | 5 (avoid spam detection) |
| Minimum gap between posts | 10 minutes |
| Daily stats post time | 00:05 UTC |
| Weekly leaderboard time | Monday 14:00 UTC |

### Pipeline Architecture

```
On-Chain Events (Solana)
    │
    ▼
SettlementService (Elixir)
    │ (processes every settled fate order)
    ▼
ContentQualifier (Elixir GenServer)
    │ (applies trigger rules — is this order tweet-worthy?)
    │ (deduplicates — don't tweet about same wallet twice in 1 hour)
    │ (rate limits — max 5/hour, 30/day)
    ▼
ShareCardGenerator (Elixir)
    │ (generates SVG → PNG via Resvg)
    │ (caches card to S3/ImageKit)
    ▼
ContentQueue (Oban job)
    │ (scheduled for next available slot, min 10 min gap)
    ▼
XPoster (Elixir module)
    │ 1. Upload image to X Media API (v1.1, OAuth 1.0a)
    │ 2. Post tweet with media_id (v2 API, OAuth 2.0)
    ▼
X / Twitter
```

### Content Queue Database Schema

```sql
-- Oban job args for scheduled tweet
{
  "type": "big_fill" | "big_loss" | "daily_stats" | "leaderboard" | "streak" | "milestone" | "this_day",
  "tweet_text": "...",
  "image_url": "https://cdn.fateswap.com/cards/order_abc123.png",
  "order_id": "abc123",        -- optional, for order-specific tweets
  "scheduled_at": "2026-03-01T14:30:00Z",
  "priority": 1-10             -- higher = post sooner when queue is backed up
}
```

### Anti-Spam Safeguards

- **Wallet cooldown**: Same wallet can only be featured once per 60 minutes
- **Token cooldown**: Same token can only appear in "big fill" tweets once per 30 minutes
- **Volume floor**: Don't tweet orders below 0.5 SOL (prevents noise)
- **Streak minimum**: Only tweet streaks of 4+ (3 is too common)
- **Daily cap**: Hard cap at 30 tweets/day even if more qualify
- **Night mode**: Reduce frequency 50% between 02:00-08:00 UTC

### Privacy

- **Never reveal wallet addresses** in automated tweets (only in user-initiated shares)
- Use "Someone" as the subject in all automated content
- If user has set a FateSwap display name, optionally include it (requires opt-in)

---

## 8. Telegram Automation

### Channels

| Channel | Purpose | Post Frequency |
|---------|---------|----------------|
| @FateSwap (public channel) | Official announcements + big fills | 5-10/day |
| FateSwap Degens (group) | Community chat + bot commands | Bot-responsive |

### Automated Telegram Posts

Mirror the X content engine but with Telegram-optimized formatting:

```
ORDER FILLED

Sold 5,000,000 $BONK at 2.4x market
Received: 1.87 SOL ($334)
Fill chance: 41%

"Conviction rewarded."

Try your conviction -> fateswap.com
```

Telegram supports:
- Inline photos (share card image attached)
- HTML formatting (`<b>`, `<i>`, `<code>`)
- Inline URL buttons (can add "Trade Now" button under each post)

### Telegram Bot Commands (Community Group)

| Command | Response |
|---------|----------|
| `/stats` | 24h volume, fills, top tokens |
| `/price BONK` | Current BONK price + suggested multiplier ranges |
| `/leaderboard` | Top 10 traders by volume this week |
| `/latest` | Last 5 filled orders |
| `/ref` | User's referral link (if wallet connected) |

### Technical: Telegram Posting

```elixir
# Using Telegex library
defmodule FateSwap.Social.TelegramPoster do
  @channel_id "@FateSwap"  # or numeric channel ID

  def post_fill_alert(order, card_image_url) do
    caption = """
    <b>ORDER FILLED</b>

    Sold #{order.token_amount} $#{order.token_symbol} at #{order.target_multiplier}x market
    Received: #{order.sol_amount} SOL ($#{order.sol_usd_value})
    Fill chance: #{order.fill_chance_percent}%

    <i>"#{quote_for(order)}"</i>

    Trade at the price you believe in -> fateswap.com
    """

    Telegex.send_photo(@channel_id, {:url, card_image_url},
      caption: caption,
      parse_mode: "HTML"
    )
  end
end
```

---

## 9. Technical Architecture

### 9.1 Share Card Image Generation

**Approach**: SVG template rendered in Elixir EEx, converted to PNG via the `resvg` Rust NIF. No headless browser, no Node.js dependency.

**Dependencies**:
```elixir
# mix.exs
{:resvg, "~> 0.5.0"}   # SVG -> PNG via Rust NIF
```

**Pipeline**:
```
Order settles
    │
    ▼
ShareCardGenerator.generate(order)
    │
    ├── 1. Build SVG string from EEx template (pure Elixir, ~1ms)
    ├── 2. Resvg.svg_string_to_png_buffer(svg) (~5-15ms)
    ├── 3. Upload PNG to S3/ImageKit (async, ~200ms)
    └── 4. Return CDN URL for immediate use
```

**SVG Template Structure** (simplified):

```xml
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="630" viewBox="0 0 1200 630">
  <!-- Dark background -->
  <rect width="1200" height="630" fill="#0A0A0F" rx="0"/>

  <!-- Top bar: logo + domain -->
  <text x="60" y="60" font-family="Satoshi" font-size="20" fill="#E8E4DD" font-weight="700">
    FATESWAP
  </text>
  <text x="1140" y="60" font-family="Satoshi" font-size="16" fill="#6B7280" text-anchor="end">
    fateswap.com
  </text>

  <!-- Divider line -->
  <line x1="60" y1="85" x2="1140" y2="85" stroke="rgba(255,255,255,0.06)" stroke-width="1"/>

  <!-- Status -->
  <text x="60" y="140" font-family="Satoshi" font-size="32" fill="<%= status_color %>" font-weight="700">
    <%= status_text %>
  </text>

  <!-- Order description -->
  <text x="60" y="190" font-family="Satoshi" font-size="22" fill="#E8E4DD">
    <%= order_description %>
  </text>

  <!-- Stats boxes -->
  <!-- ... three rounded rects with labels + values ... -->

  <!-- Conviction gradient bar -->
  <defs>
    <linearGradient id="convictionGrad" x1="0%" y1="0%" x2="100%" y2="0%">
      <stop offset="0%" stop-color="#22C55E"/>
      <stop offset="50%" stop-color="#EAB308"/>
      <stop offset="100%" stop-color="#EF4444"/>
    </linearGradient>
  </defs>
  <rect x="60" y="380" width="<%= bar_fill_width %>" height="12" rx="6" fill="url(#convictionGrad)"/>
  <rect x="60" y="380" width="1080" height="12" rx="6" fill="none" stroke="rgba(255,255,255,0.1)"/>

  <!-- Quote -->
  <text x="60" y="440" font-family="Satoshi" font-size="18" fill="#9CA3AF" font-style="italic">
    "<%= quote %>"
  </text>

  <!-- Bottom CTA with referral -->
  <line x1="60" y1="540" x2="1140" y2="540" stroke="rgba(255,255,255,0.06)" stroke-width="1"/>
  <text x="60" y="580" font-family="JetBrains Mono" font-size="14" fill="#6B7280">
    Try your conviction -> fateswap.com/?ref=<%= referral_code %>
  </text>
</svg>
```

**Font handling for Resvg**: Custom fonts (Satoshi, JetBrains Mono) must be installed on the server. In the Dockerfile:
```dockerfile
COPY assets/fonts/*.ttf /usr/share/fonts/truetype/fateswap/
RUN fc-cache -f -v
```

### 9.2 Share Card Serving

**Route**: `GET /order/:order_id/card.png`

This route serves the pre-generated card image. Used as the `og:image` value.

```elixir
# router.ex
get "/order/:order_id/card.png", ShareCardController, :show
```

**Controller**:
```elixir
defmodule FateSwapWeb.ShareCardController do
  use FateSwapWeb, :controller

  def show(conn, %{"order_id" => order_id}) do
    case ShareCards.get_card_url(order_id) do
      {:ok, cdn_url} ->
        # Redirect to CDN (ImageKit) for caching + edge delivery
        redirect(conn, external: cdn_url)

      {:ok, :generate, order} ->
        # Card not yet generated — generate on-the-fly, cache, serve
        {:ok, png_binary} = ShareCardGenerator.generate(order)
        {:ok, cdn_url} = ShareCards.upload_and_cache(order_id, png_binary)

        conn
        |> put_resp_content_type("image/png")
        |> put_resp_header("cache-control", "public, max-age=31536000, immutable")
        |> send_resp(200, png_binary)

      :error ->
        send_resp(conn, 404, "")
    end
  end
end
```

### 9.3 OG Meta Tags for Order Pages

Each settled order has a shareable page at `/order/:order_id?ref=:code`.

**Plug** (runs before LiveView mount):
```elixir
defmodule FateSwapWeb.Plugs.OrderOgMeta do
  def call(conn, _opts) do
    case conn.path_info do
      ["order", order_id] ->
        case Orders.get_settled(order_id) do
          {:ok, order} ->
            ref = conn.query_params["ref"]
            image_url = "#{FateSwapWeb.Endpoint.url()}/order/#{order_id}/card.png"

            conn
            |> assign(:og_title, og_title(order))
            |> assign(:og_description, og_description(order))
            |> assign(:og_image, image_url)
            |> assign(:og_url, order_url(order_id, ref))

          _ -> conn
        end
      _ -> conn
    end
  end

  defp og_title(%{status: :filled, token_symbol: sym, target_multiplier: mult}) do
    "Order Filled — #{sym} at #{mult}x market | FateSwap"
  end
  defp og_title(%{status: :not_filled, token_symbol: sym, target_multiplier: mult}) do
    "Not Filled — #{sym} at #{mult}x market | FateSwap"
  end

  defp og_description(%{status: :filled, sol_amount: sol, fill_chance_percent: pct}) do
    "Received #{sol} SOL. Fill chance was #{pct}%. Trade at the price you believe in."
  end
  defp og_description(%{status: :not_filled, fill_chance_percent: pct}) do
    "Fill chance was #{pct}%. Tokens claimed by fate. Trade at the price you believe in."
  end
end
```

**Root layout meta tags**:
```html
<meta property="og:title" content={assigns[:og_title] || "FateSwap — Trade at the price you believe in"} />
<meta property="og:description" content={assigns[:og_description] || "A DEX where you set your own sell price. The further from market, the lower the fill chance — the higher the reward."} />
<meta property="og:image" content={assigns[:og_image] || "https://cdn.fateswap.com/og-default.png"} />
<meta property="og:image:width" content="1200" />
<meta property="og:image:height" content="630" />
<meta property="og:url" content={assigns[:og_url] || FateSwapWeb.Endpoint.url()} />
<meta property="og:type" content="website" />
<meta property="og:site_name" content="FateSwap" />

<meta name="twitter:card" content="summary_large_image" />
<meta name="twitter:site" content="@FateSwap" />
<meta name="twitter:title" content={assigns[:og_title] || "FateSwap"} />
<meta name="twitter:description" content={assigns[:og_description] || "Trade at the price you believe in."} />
<meta name="twitter:image" content={assigns[:og_image] || "https://cdn.fateswap.com/og-default.png"} />
```

### 9.4 LiveView Share UI Components

**Result overlay with share buttons** (rendered after order settles):

```elixir
defmodule FateSwapWeb.Components.ShareOverlay do
  use Phoenix.Component

  attr :order, :map, required: true
  attr :referral_code, :string, required: true

  def share_overlay(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
      <div class="w-full max-w-md mx-4 bg-[#14141A] border border-white/[0.06] rounded-2xl p-6">

        <%!-- Result header --%>
        <div class="text-center mb-6">
          <p class={[
            "text-2xl font-bold",
            if(@order.status == :filled, do: "text-green-500", else: "text-red-400/70")
          ]}>
            <%= if @order.status == :filled, do: "ORDER FILLED", else: "NOT FILLED" %>
          </p>
          <p class="text-[#E8E4DD] mt-2">
            <%= order_description(@order) %>
          </p>
        </div>

        <%!-- Stats row --%>
        <div class="grid grid-cols-3 gap-3 mb-6">
          <div class="bg-white/[0.03] rounded-lg p-3 text-center">
            <p class="text-xs text-[#6B7280] uppercase tracking-wider">
              <%= if @order.status == :filled, do: "Received", else: "Would have" %>
            </p>
            <p class="text-lg font-bold text-[#E8E4DD] font-mono"><%= @order.sol_amount %> SOL</p>
          </div>
          <div class="bg-white/[0.03] rounded-lg p-3 text-center">
            <p class="text-xs text-[#6B7280] uppercase tracking-wider">Fill Chance</p>
            <p class="text-lg font-bold text-[#E8E4DD] font-mono"><%= @order.fill_chance_percent %>%</p>
          </div>
          <div class="bg-white/[0.03] rounded-lg p-3 text-center">
            <p class="text-xs text-[#6B7280] uppercase tracking-wider">Target</p>
            <p class="text-lg font-bold text-[#E8E4DD] font-mono"><%= @order.target_multiplier %>x</p>
          </div>
        </div>

        <%!-- Quote --%>
        <p class="text-center text-[#9CA3AF] italic mb-6">
          "<%= quote_for(@order) %>"
        </p>

        <%!-- Share buttons --%>
        <div class="grid grid-cols-4 gap-2 mb-4">
          <a
            href={x_share_url(@order, @referral_code)}
            target="_blank"
            class="flex flex-col items-center gap-1 p-3 rounded-lg bg-white/[0.03] hover:bg-white/[0.06] transition cursor-pointer"
          >
            <.x_icon class="w-5 h-5 text-[#E8E4DD]" />
            <span class="text-xs text-[#6B7280]">X</span>
          </a>

          <a
            href={telegram_share_url(@order, @referral_code)}
            target="_blank"
            class="flex flex-col items-center gap-1 p-3 rounded-lg bg-white/[0.03] hover:bg-white/[0.06] transition cursor-pointer"
          >
            <.telegram_icon class="w-5 h-5 text-[#E8E4DD]" />
            <span class="text-xs text-[#6B7280]">Telegram</span>
          </a>

          <button
            id={"copy-link-#{@order.id}"}
            phx-hook="CopyToClipboard"
            data-copy-text={order_share_url(@order, @referral_code)}
            class="flex flex-col items-center gap-1 p-3 rounded-lg bg-white/[0.03] hover:bg-white/[0.06] transition cursor-pointer"
          >
            <.copy_icon class="w-5 h-5 text-[#E8E4DD] copy-icon" />
            <span class="text-xs text-[#6B7280] copy-text">Copy</span>
          </button>

          <a
            href={card_download_url(@order)}
            download={"fateswap-#{@order.id}.png"}
            class="flex flex-col items-center gap-1 p-3 rounded-lg bg-white/[0.03] hover:bg-white/[0.06] transition cursor-pointer"
          >
            <.download_icon class="w-5 h-5 text-[#E8E4DD]" />
            <span class="text-xs text-[#6B7280]">Save</span>
          </a>
        </div>

        <%!-- Action buttons --%>
        <div class="flex gap-3">
          <button
            phx-click="dismiss_result"
            class="flex-1 py-3 rounded-lg bg-white/[0.06] text-[#E8E4DD] font-medium hover:bg-white/[0.1] transition cursor-pointer"
          >
            Close
          </button>
          <button
            phx-click="new_order"
            class="flex-1 py-3 rounded-lg bg-[#E8E4DD] text-[#0A0A0F] font-medium hover:bg-white transition cursor-pointer"
          >
            New Order
          </button>
        </div>
      </div>
    </div>
    """
  end

  defp x_share_url(order, ref_code) do
    text = x_tweet_text(order)
    url = order_share_url(order, ref_code)
    "https://x.com/intent/tweet?text=#{URI.encode(text)}&url=#{URI.encode(url)}"
  end

  defp telegram_share_url(order, ref_code) do
    text = telegram_text(order)
    url = order_share_url(order, ref_code)
    "https://t.me/share/url?url=#{URI.encode(url)}&text=#{URI.encode(text)}"
  end

  defp order_share_url(order, ref_code) do
    "#{FateSwapWeb.Endpoint.url()}/order/#{order.id}?ref=#{ref_code}"
  end

  defp card_download_url(order) do
    "#{FateSwapWeb.Endpoint.url()}/order/#{order.id}/card.png"
  end

  defp x_tweet_text(%{status: :filled} = order) do
    """
    I just fate-swapped #{order.token_amount} $#{order.token_symbol} at #{order.target_multiplier}x market and it FILLED

    Received #{order.sol_amount} SOL ($#{order.sol_usd_value})
    Fill chance was #{order.fill_chance_percent}%

    #{quote_for(order)}

    Try your conviction on @FateSwap\
    """
  end

  defp x_tweet_text(%{status: :not_filled} = order) do
    """
    Went for #{order.target_multiplier}x on $#{order.token_symbol} — fate said no

    Fill chance was #{order.fill_chance_percent}%
    Tokens claimed by fate

    #{quote_for(order)}

    Name your price on @FateSwap\
    """
  end

  defp telegram_text(%{status: :filled} = order) do
    "Fate-swapped #{order.token_amount} $#{order.token_symbol} at #{order.target_multiplier}x -> FILLED (#{order.sol_amount} SOL)"
  end

  defp telegram_text(%{status: :not_filled} = order) do
    "Went for #{order.target_multiplier}x on $#{order.token_symbol} -> Not filled. Tokens claimed by fate."
  end
end
```

### 9.5 Automated X Posting Service

**Dependencies**:
```elixir
# mix.exs
{:oauther, "~> 1.3"}   # OAuth 1.0a signing for X media upload
{:oban, "~> 2.18"}      # Job queue for scheduled tweets
```

**X API Module**:
```elixir
defmodule FateSwap.Social.XPoster do
  @v2_base "https://api.x.com/2"
  @upload_base "https://upload.x.com/1.1"

  @doc """
  Posts a tweet with an optional image.
  1. If image_binary provided, uploads via v1.1 Media API (OAuth 1.0a)
  2. Posts tweet via v2 API (OAuth 2.0 or 1.0a)
  """
  def post_tweet(text, opts \\ []) do
    image_binary = Keyword.get(opts, :image)

    media_ids =
      if image_binary do
        {:ok, media_id} = upload_media(image_binary)
        [media_id]
      else
        []
      end

    body = %{"text" => text}
    body = if media_ids != [], do: Map.put(body, "media", %{"media_ids" => media_ids}), else: body

    Req.post("#{@v2_base}/tweets",
      json: body,
      headers: [{"authorization", "Bearer #{oauth2_access_token()}"}],
      receive_timeout: 15_000
    )
  end

  defp upload_media(image_binary) do
    # Media upload requires OAuth 1.0a signing
    auth_header = build_oauth1_header("POST", "#{@upload_base}/media/upload.json", %{})

    case Req.post("#{@upload_base}/media/upload.json",
      form: [media_data: Base.encode64(image_binary)],
      headers: [{"authorization", auth_header}],
      receive_timeout: 30_000
    ) do
      {:ok, %{status: 200, body: %{"media_id_string" => media_id}}} ->
        {:ok, media_id}
      error ->
        {:error, error}
    end
  end
end
```

**Content Qualifier (decides what's tweet-worthy)**:
```elixir
defmodule FateSwap.Social.ContentQualifier do
  use GenServer

  # State tracks recent posts to enforce cooldowns
  # %{wallet_last_posted: %{}, token_last_posted: %{}, daily_count: 0}

  @big_fill_sol_threshold 5.0
  @big_fill_multiplier_threshold 3.0
  @big_loss_multiplier_threshold 5.0
  @big_loss_sol_threshold 2.0
  @max_daily_tweets 30
  @min_gap_minutes 10
  @wallet_cooldown_minutes 60
  @token_cooldown_minutes 30

  def qualifies_for_tweet?(order) do
    GenServer.call(__MODULE__, {:qualify, order})
  end

  # ... GenServer implementation that checks all rules
end
```

**Oban Worker for Scheduled Tweets**:
```elixir
defmodule FateSwap.Social.Workers.PostTweet do
  use Oban.Worker, queue: :social, max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => type} = args}) do
    tweet_text = args["tweet_text"]
    image_url = args["image_url"]

    image_binary =
      if image_url do
        {:ok, %{body: body}} = Req.get(image_url, receive_timeout: 15_000)
        body
      end

    case XPoster.post_tweet(tweet_text, image: image_binary) do
      {:ok, %{status: 201}} -> :ok
      {:ok, %{status: 429}} -> {:snooze, 900}  # rate limited, retry in 15 min
      error -> {:error, error}
    end
  end
end
```

**Daily Stats Worker** (scheduled via Oban cron):
```elixir
# In Oban config:
config :fateswap, Oban,
  plugins: [
    {Oban.Plugins.Cron, crontab: [
      {"5 0 * * *", FateSwap.Social.Workers.DailyStats},       # 00:05 UTC daily
      {"0 14 * * 1", FateSwap.Social.Workers.WeeklyLeaderboard} # Monday 14:00 UTC
    ]}
  ]
```

### 9.6 Share Card Caching Strategy

| Layer | TTL | Purpose |
|-------|-----|---------|
| In-memory (ETS) | 5 min | Hot cache for recently settled orders |
| S3 / ImageKit CDN | Immutable | Permanent storage — cards never change after generation |
| Browser | `max-age=31536000, immutable` | Cards are content-addressed, never invalidated |

Card URL format: `https://cdn.fateswap.com/cards/{order_id}.png`

Cards are generated **once** at settlement time and never regenerated. The order data is immutable after settlement, so the card is immutable too.

---

## 10. Marketing Campaigns

### Pre-Launch: "What's Your Price?"

**Timeline**: 2-4 weeks before launch
**Cost**: $0 (organic only)

Run a social campaign where people publicly state what price they'd sell their bags at.

- Tweet format: "I'd sell my [TOKEN] at [X]x market. What's your price? @FateSwap"
- Drives waitlist signups
- Replies become market research for token support priorities
- On launch day, tag participants: "Remember when you said you'd sell WIF at 3x? Now you can."

### Launch: "Market Price is for Cowards"

**Core positioning**: Using a regular DEX is settling. You have conviction. Act like it.

- Visual: Split-screen — left is a boring Jupiter swap at market price. Right is FateSwap at 3x with the probability ring glowing.
- "Jupiter gives you what the market says. We give you what you believe."
- Provocative but not hostile — it's aspirational, not insulting Jupiter.

### Ongoing: "The Discount Rack" (Buy-Side Launch)

When Phase 3 (buy-side) launches, position it as Black Friday for memecoins.

- "Buy BONK at 70% off. If fate allows it."
- "The only sale where the discount is real and the risk is yours."
- This is genuinely novel — no gambling or DeFi product frames anything as discount shopping. It will stand out.

### Referral Campaign: "Spread the Fate"

- 0.2% of wager on referred users' losing orders (20 bps)
- Two-tier system — earn on your referrals' losses, and on their referrals' losses too (0.1% tier-2)
- Leaderboard of top referrers displayed as "Fate Weavers"
- Monthly prizes for top referrers (SOL rewards from protocol revenue)

---

## 11. Community & Culture Building

### "Fate Weavers" — Power User Tier

- Top 100 traders by volume earn the title
- Exclusive share card design (different border/accent)
- Leaderboard placement on the site
- Ties into the NFT reward system from the roadmap (MasterChef-style staking)

### "Claimed by Fate" — Loss Culture

The most important cultural innovation: making losses shareable and respectable.

- "Tokens claimed by fate" is the official language for a loss
- Community norms celebrate high-conviction plays regardless of outcome
- "Full degen. Full respect." for 5x+ attempts
- Weekly "Biggest Claim" post on X highlighting the most ambitious failed order
- This is the FateSwap equivalent of a bad beat story in poker — people bond over them

### "The Feed" — Always-On Social Proof

The live feed on the trading page shows recent orders from all users. This naturally generates:

- **FOMO**: "Someone just filled at 4.2x... maybe I should try"
- **Social proof**: High volume = trustworthy platform
- **Content**: Screenshot the feed for daily X posts without any manual effort

### Streak Culture

Consecutive fills build streaks. Streaks generate:

- Automated X posts ("5-order streak!")
- Special share card variants with streak badges
- Leaderboard of longest active streaks
- Streak-break commiseration ("12-order streak broken. Fate giveth, fate taketh.")

---

## Appendix: File Structure (When Built)

```
lib/fateswap/social/
  ├── share_card_generator.ex    # SVG template + Resvg rendering
  ├── share_cards.ex             # Cache management + S3 upload
  ├── content_qualifier.ex       # GenServer: decides what's tweet-worthy
  ├── x_poster.ex                # X API v2 posting + v1.1 media upload
  ├── telegram_poster.ex         # Telegex channel posting
  └── workers/
      ├── post_tweet.ex          # Oban worker: scheduled tweet posting
      ├── generate_card.ex       # Oban worker: async card generation
      ├── daily_stats.ex         # Oban cron: 24h recap tweet
      └── weekly_leaderboard.ex  # Oban cron: weekly top tokens/traders

lib/fateswap_web/
  ├── controllers/
  │   └── share_card_controller.ex   # GET /order/:id/card.png
  ├── plugs/
  │   └── order_og_meta.ex           # Dynamic OG tags for order pages
  └── components/
      └── share_overlay.ex           # LiveView share button overlay

assets/
  ├── fonts/
  │   ├── Satoshi-Bold.ttf
  │   └── JetBrainsMono-Regular.ttf
  └── js/
      └── hooks/
          └── copy_to_clipboard.js   # Copy referral link to clipboard

priv/
  └── share_card_templates/
      ├── filled.svg.eex             # Filled order card template
      ├── not_filled.svg.eex         # Not-filled card template
      └── buy_filled.svg.eex         # Buy-side filled card template
```
