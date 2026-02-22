# Cold Outreach System — Comprehensive Plan

> **Status**: Planning Complete | **Date**: 2026-02-20
> **Branch**: `feat/notification-system` (will build on existing notification infrastructure)

---

## Executive Summary

Build an AI-powered cold outreach system within Blockster that autonomously discovers, qualifies, and messages potential users across social platforms. The system uses an AI Manager (Claude API) that can run fully autonomously or be directed by admin via a chat interface. Admin provides aged accounts per platform; the AI handles everything from lead discovery to personalized DMs to conversion tracking.

**Key metrics target**: >10% reply rate, >5% conversion rate (reply → signup), <$5 cost per acquisition.

**Phase 1 platforms**: X (Twitter) primary, Telegram secondary. Instagram for engagement funnel + scraping. TikTok for scraping. Facebook deprioritized.

**Account strategy**: Purchase aged accounts to skip establishment phase — 7-12 day fast-track warmup instead of 22 days. Start with 10 accounts/platform, scale based on ROI.

---

## Table of Contents

1. [System Architecture](#1-system-architecture)
2. [Platform Strategy](#2-platform-strategy)
3. [AI Manager Design](#3-ai-manager-design)
4. [Lead Generation & Targeting](#4-lead-generation--targeting)
5. [Personalization Engine](#5-personalization-engine)
6. [Account Management & Safety](#6-account-management--safety)
7. [Admin Dashboard](#7-admin-dashboard)
8. [Database Schema](#8-database-schema)
9. [Scaling Roadmap & Cost Projections](#9-scaling-roadmap--cost-projections)
10. [Implementation Phases](#10-implementation-phases)
11. [Risk Assessment](#11-risk-assessment)
12. [Integration Points](#12-integration-points)

---

## 1. System Architecture

### High-Level Overview

```
                    ┌──────────────────────────┐
                    │   Admin Dashboard        │
                    │   (Phoenix LiveView)      │
                    │   /admin/outreach/*       │
                    └──────────┬───────────────┘
                               │ PubSub
                    ┌──────────▼───────────────┐
                    │   OutreachManager        │
                    │   (GlobalSingleton)       │
                    │   - Campaign state        │
                    │   - Rate limiters         │
                    │   - Budget tracking       │
                    └──────────┬───────────────┘
                               │
              ┌────────────────┼────────────────┐
              │                │                │
    ┌─────────▼──────┐ ┌──────▼───────┐ ┌──────▼───────┐
    │  OutreachAI    │ │ AccountRouter│ │ LeadScorer   │
    │  (Claude API)  │ │ (GenServer)  │ │ (Haiku API)  │
    │  - Decisions   │ │ - Rotation   │ │ - Scoring    │
    │  - Messages    │ │ - Health     │ │ - Enrichment │
    │  - Admin chat  │ │ - Warming    │ │ - Personas   │
    └────────────────┘ └──────────────┘ └──────────────┘
              │                │                │
    ┌─────────▼────────────────▼────────────────▼──────┐
    │                  Oban Job Queues                  │
    │  outreach_send(2) | outreach_scrape(3) |         │
    │  outreach_ai(1)   | outreach_health(1) |         │
    │  outreach_engagement(3) | outreach_warmup(2)     │
    └──────────────────────────────────────────────────┘
              │                │                │
    ┌─────────▼──────┐ ┌──────▼───────┐ ┌──────▼───────┐
    │  X/Twitter     │ │  Telegram    │ │  Instagram   │
    │  Platform      │ │  Platform    │ │  Engagement  │
    │  Client (DMs)  │ │  Client (DMs)│ │  Funnel +    │
    │                │ │              │ │  Scraping    │
    └────────────────┘ └──────────────┘ └──────────────┘
```

### Core Components

| Component | Type | Pattern | Purpose |
|-----------|------|---------|---------|
| `OutreachManager` | GenServer | GlobalSingleton | Orchestrates entire system, tracks state |
| `OutreachAccountRouter` | GenServer | GlobalSingleton | Account selection, rotation, rate limiting |
| `OutreachAI` | Module | Stateless (like existing AIManager) | Claude API calls for decisions + messages |
| `LeadScorer` | Module | Stateless | AI-powered lead qualification |
| Platform Clients | Modules | Behaviour-based | X, Telegram, Instagram API adapters |

### Feature Flag

Entire system behind `OUTREACH_ENABLED` env var. Zero impact when disabled.

```elixir
# runtime.exs
config :blockster_v2, :outreach,
  enabled: System.get_env("OUTREACH_ENABLED") == "true",
  twitter_bearer_token: System.get_env("TWITTER_BEARER_TOKEN"),
  telegram_api_id: System.get_env("TELEGRAM_API_ID"),
  telegram_api_hash: System.get_env("TELEGRAM_API_HASH")
```

### Supervision Tree Addition

```elixir
# In application.ex, after notification_children:
outreach_children = if Application.get_env(:blockster_v2, :outreach, [])[:enabled] do
  [
    {BlocksterV2.Outreach.OutreachManager, []},
    {BlocksterV2.Outreach.AccountRouter, []}
  ]
else
  []
end
```

### Oban Queues & Cron

```elixir
# New queues:
outreach_send: 2,        # DM sending (low concurrency = natural pacing)
outreach_scrape: 3,      # Lead discovery
outreach_ai: 1,          # AI decisions (serialized)
outreach_health: 1,      # Health checks
outreach_engagement: 3,  # Organic engagement simulation
outreach_warmup: 2       # Account warming activities

# New cron entries:
{"*/15 * * * *", BlocksterV2.Workers.OutreachOrchestratorWorker},
{"0 */4 * * *", BlocksterV2.Workers.LeadDiscoveryWorker},
{"0 8 * * *", BlocksterV2.Workers.OutreachDailyReviewWorker},
{"0 * * * *", BlocksterV2.Workers.AccountHealthWorker},
{"0 * * * *", BlocksterV2.Workers.TokenRefreshWorker},
{"0 7,12,17 * * *", BlocksterV2.Workers.AuthorContentWorker}  # Generate daily tweets for each author
```

---

## 2. Platform Strategy

### Platform Rankings

| Rank | Platform | Cold DM Viability | Phase | Daily DMs/Account | Approach |
|------|----------|-------------------|-------|-------------------|----------|
| 1 | **X (Twitter)** | HIGH | Phase 1 (Primary) | 30 (conservative) | API + xAutoDM-style |
| 2 | **Telegram** | MEDIUM-HIGH | Phase 1 (Secondary) | 40 (aged accounts) | Telethon userbot |
| 3 | **Instagram** | MEDIUM (indirect) | Phase 1 (Engagement funnel) | N/A | Story replies + engagement → inbound DMs |
| 4 | **TikTok** | LOW | Phase 2 (scrape only) | N/A | Follower scraping, cross-platform targeting |
| 5 | **Facebook** | NONE | Deprioritize | N/A | Not viable — strictest opt-in requirements |

### Why Not Cold DM on Facebook, Instagram, TikTok?

| Platform | Blocker | What We CAN Do Instead |
|----------|---------|----------------------|
| **Facebook** | Requires explicit opt-in before ANY marketing message. 1 msg per 48hrs per opted-in user. No workaround exists. | Nothing viable. Fully deprioritized. |
| **Instagram** | Official API is reply-only (user must message YOU first). Cold DM via unofficial tools = aggressive Meta ban waves since mid-2025. | **Engagement funnel**: Follow targets, reply to their stories, comment on posts. Some will check our profile and DM us first — making them fair game for conversation. Also scrape followers for cross-platform targeting on X/Telegram. |
| **TikTok** | API is response-only — cannot initiate conversations at all. Not available in EU/UK. | Scrape follower lists (Apify, SociaVault work well). Target those users on X/Telegram where cold DMs work. |

### API Cost Structure

You do NOT need a separate API account per platform account:

| Platform | API Cost | How It Works |
|----------|----------|-------------|
| **X (Twitter)** | ONE API developer account ($200/mo Basic) | Single API key authenticates multiple user accounts via OAuth. Each aged account authorizes your app, you send DMs on their behalf through the same API. |
| **Telegram** | FREE | Telethon/Pyrogram use the free user API (not Bot API). Each account authenticates with its own phone number. Zero API fees. |
| **Scraping** (IG/TikTok) | ~$0.001/record | Third-party tools (Apify, PhantomBuster) charge per result, not per account. |

**This means scaling from 10 to 1000 accounts does NOT multiply API costs.** The bottleneck is proxy costs and account acquisition, not API fees.

### X (Twitter) — Primary Channel (AI Author Personas)

Each X account IS one of Blockster's 8 AI authors. They're not faceless bot accounts — they're real-looking crypto personalities who post content, engage with the community, AND do outreach DMs. This makes the accounts look natural and gives DM recipients a reason to check the profile and see Blockster content.

#### The 8 AI Author X Accounts

| Author | Persona | X Account Focus | DM Angle |
|--------|---------|----------------|----------|
| **Jake Freeman** | Bitcoin maximalist, ex-TradFi analyst | Trading analysis, BTC macro takes, Blockster article RTs | Data-driven, market analogies |
| **Maya Chen** | DeFi degen with compliance background | DeFi explainers, regulation hot takes, yield farming | Technical but accessible |
| **Alex Ward** | Privacy advocate, cypherpunk | Self-custody tips, privacy news, security alerts | Passionate, historical parallels |
| **Sophia Reyes** | Web3 gaming & NFT specialist | Gaming news, NFT drops, metaverse content | Enthusiastic, pop culture refs |
| **Marcus Stone** | Reformed Wall Street trader | Contrarian takes, altcoin analysis, trading signals | Sharp, confident, trader slang |
| **Nina Takashi** | AI researcher × blockchain | AI+crypto intersection, Ethereum deep dives | Explains complex tech simply |
| **Ryan Kolbe** | Former cybersecurity engineer | Security exploits breakdowns, mining news, privacy | Technical, dry humor |
| **Elena Vasquez** | DeFi yield farmer & stablecoin analyst | Yield comparisons, stablecoin analysis, protocol reviews | Numbers-focused, fair comparisons |

These personas already exist in the content automation system (`AuthorRotator` in `lib/blockster_v2/content_automation/author_rotator.ex`) and write articles for Blockster. Extending them to X gives each author a "social presence" that makes outreach feel authentic.

#### Auto-Populated X Account Activity

Each author's X account is automatically kept active with a mix of content:

**Blockster Content (auto-posted when articles publish)**:
- RT/quote-tweet Blockster's main account posts
- Share their OWN Blockster articles with a personal take ("Just published my analysis on the ETH ETF flows...")
- Share other Blockster authors' articles with commentary

**Organic Crypto Content (AI-generated, scheduled)**:
- 2-4 original tweets/day matching their persona (Jake posts trading takes, Sophia posts gaming news, etc.)
- Quote-tweets of trending crypto content with the author's perspective
- Reply to trending crypto threads (builds visibility + engagement)
- RT relevant crypto news from the author's niche

**Engagement Activity (mixed in between DMs)**:
- Like posts from people they follow
- Reply to followers' tweets
- Engage with crypto community discussions
- Follow new accounts in their niche

**Posting Schedule** (per author account, daily):
```
08:00-09:00  Morning take (original tweet about crypto news)
10:00-11:00  Share a Blockster article (their own or another author's)
12:00-13:00  RT/quote crypto news relevant to their niche
14:00-16:00  DM outreach window (15-20 DMs with engagement mixed in)
17:00-18:00  Reply to threads, engage with community
19:00-20:00  Evening take or RT of Blockster content
21:00-22:00  Second DM window (10-15 DMs)
```

This means when a DM recipient checks the author's profile, they see an active crypto personality with opinions, articles, and engagement — not an empty bot account. The Blockster connection is visible but not the entire profile.

#### Integration with Content Automation

The content automation system already generates articles attributed to these authors. The X outreach system extends this by:

1. **Auto-post hook**: When `ContentPublisher` publishes an article, fire an event that queues a tweet from the author's X account
2. **Content calendar**: `OutreachEngagementWorker` generates daily tweets for each author using their persona style (via Haiku — cheap)
3. **Blockster RT queue**: Main Blockster X account posts → each author account RTs with probability based on topic relevance to their categories
4. **Persona consistency**: DM tone matches the author's writing style (Jake is data-driven, Sophia is enthusiastic, Marcus is sharp/confident)

#### Why This Works Better Than Anonymous Accounts

- **Profile credibility**: Real-looking crypto personality with posting history
- **Content funnel**: DM recipient checks profile → sees interesting crypto content → some of it links to Blockster
- **Persona-matched DMs**: Jake DMs about trading analysis, Sophia DMs about gaming — feels natural
- **SEO/brand building**: 8 active crypto accounts all linking to Blockster content = organic reach
- **Harder to detect as outreach**: The accounts have genuine content, not just DMs

- **API**: v2 supports DM sending via single Basic tier ($200/mo) for all accounts
- **Tools**: xAutoDM (1,350 DMs/day, 32% response rate), Autoreach (AI sales agent)
- **Safe limits**: 30 DMs/day conservative per author account (× 8 authors = 240 DMs/day)
- **Follower scraping**: twscrape, Apify, PhantomBuster
- **Why primary**: Best tooling, proven results, most of crypto Twitter, AND persona system already built

### Telegram — Secondary Channel (Fully Automated via Telethon)

- **Approach**: Telethon userbot using Telegram's official MTProto protocol (NOT bot API — bots can't initiate DMs)
- **Safe limits**: ~50 DMs before PeerFloodError, 40/day conservative per account
- **Group scraping**: Can scrape members from public crypto groups (1000+ members/min)
- **Why secondary**: Telegram IS the crypto messaging platform, but stricter anti-spam since 2023
- **Automation level**: 100% automated — no browser, no scraping, no CAPTCHAs. Clean API calls.

#### Telethon Integration Architecture

Telethon is a Python library that uses Telegram's official MTProto protocol — the same protocol the Telegram desktop/mobile apps use. This means it's not "hacking" or "scraping" — it's using Telegram's real API as a user client.

**Deployment: Python Microservice on Fly.io**

Run a lightweight Python/FastAPI service alongside Blockster that handles all Telegram operations:

```
┌─────────────────────────────┐     HTTP/JSON      ┌──────────────────────────┐
│  Blockster (Elixir/Phoenix) │ ◄──────────────────► │  Telegram Service        │
│                             │                      │  (Python/FastAPI)        │
│  OutreachSendWorker         │  POST /send-dm       │                          │
│  LeadDiscoveryWorker        │  POST /scrape-group   │  Telethon MTProto       │
│  OutreachReplyProcessor     │  GET  /check-replies  │  Session Manager        │
│  AccountHealthWorker        │  GET  /account-health │  Account Pool           │
│                             │  POST /join-group     │  Proxy Router           │
└─────────────────────────────┘                      └──────────────────────────┘
                                                              │
                                                     Telegram MTProto API
                                                     (official, free, unlimited)
```

**Why a separate service (not Elixir Port/NIF)?**
- Telethon is mature, battle-tested Python — no equivalent Elixir MTProto library exists
- Separate deployment = independent scaling and restarts
- Session files (one per account) managed in the Python process
- Can deploy on same Fly.io org for low-latency internal networking
- Clean HTTP interface makes it easy to swap implementations later

**Service Endpoints**:

```
POST /send-dm
  Body: {account_id, recipient_username, message, proxy_config}
  Returns: {success, message_id, timestamp} or {error, "PeerFloodError"}

POST /scrape-group-members
  Body: {account_id, group_username, limit, offset}
  Returns: {members: [{user_id, username, first_name, last_name, bio, ...}]}

GET /check-replies
  Body: {account_id, since_timestamp}
  Returns: {replies: [{from_user, message, timestamp, conversation_id}]}

POST /join-group
  Body: {account_id, group_username}
  Returns: {success, member_count}

GET /account-health
  Body: {account_id}
  Returns: {status, can_send_dm, is_restricted, spam_bot_status}

POST /authenticate
  Body: {phone_number, api_id, api_hash, proxy_config}
  Returns: {account_id, session_created}
  Note: First auth requires SMS code (one-time manual step per account)

POST /send-engagement
  Body: {account_id, action: "like"|"comment"|"view", target, content}
  Returns: {success}
```

**Session Management**:
- Each Telegram account gets a `.session` file (SQLite DB created by Telethon)
- Sessions persist authentication — no re-login needed after initial setup
- Store session files in persistent volume on Fly.io (`/data/telegram-sessions/`)
- One-time setup per account: authenticate with phone + SMS code, then fully automated forever

**Account Authentication Flow** (one-time per account):
```
1. Admin adds new Telegram account in dashboard (phone number + proxy)
2. Blockster calls POST /authenticate on Telegram service
3. Telethon sends SMS code to phone
4. Admin enters code in dashboard → forwarded to service
5. Session file created and stored → account ready for automation
6. From this point: zero manual intervention, everything is API calls
```

**Proxy Integration**:
- Each account's proxy config passed with every request
- Telethon natively supports SOCKS5 and HTTP proxies
- Service maintains sticky proxy-to-account mapping
- Example: `TelegramClient(session, api_id, api_hash, proxy=("socks5", host, port, True, user, pass))`

**Anti-Spam Handling**:
- `PeerFloodError` → service returns error, Blockster's AccountRouter quarantines account for 24h
- `FloodWaitError(seconds=X)` → service waits X seconds automatically, returns delay info
- `UserBannedInChannelError` → account restricted from groups, flag in health check
- Service checks `@SpamBot` status via API to detect soft-bans early

**Python Service Stack**:
```
FastAPI          — HTTP endpoints
Telethon         — Telegram MTProto client
asyncio          — Concurrent account management
aiohttp          — Proxy-aware HTTP
python-socks     — SOCKS5 proxy support
uvicorn          — ASGI server
```

**Fly.io Deployment**:
```toml
# fly.toml for telegram-service
[build]
  dockerfile = "Dockerfile"

[mounts]
  source = "telegram_sessions"
  destination = "/data/sessions"

[env]
  TELEGRAM_API_ID = "..."  # From https://my.telegram.org
  TELEGRAM_API_HASH = "..."

[[services]]
  internal_port = 8000
  protocol = "tcp"
  auto_stop_machines = false  # Keep running for session persistence

  [[services.ports]]
    port = 80
    handlers = ["http"]
```

**Cost**: Free (Telegram API is free). Only pay for Fly.io machine (~$5-10/mo for a small VM) + proxy costs per account.

### Instagram — Engagement Funnel (Not Cold DM)

Cold DMs are too risky on Instagram (Meta ban waves). Instead, use an **engagement funnel**:

1. **Follow** target users from our aged accounts
2. **Reply to their stories** with genuine, relevant comments about crypto topics
3. **Comment on their posts** — thoughtful, not spammy
4. **Like their content** consistently over days
5. Some targets will **check our profile** → see Blockster content → **DM us first**
6. Once THEY initiate, we're in a legitimate conversation → guide to signup

This is slower but sustainable, safe, and builds genuine brand awareness. Our IG accounts should have Blockster-related content (crypto news, BUX info) on their profiles.

### Cross-Platform Intelligence

Scrape follower lists from Instagram and TikTok, then target those users on X/Telegram where cold DMs are viable. Tools: Apify, PhantomBuster, SociaVault.

---

## 3. AI Manager Design

### Architecture

The AI Manager extends the existing `BlocksterV2.Notifications.AIManager` pattern — stateless Claude API calls with tool_use, orchestrated by a GlobalSingleton GenServer.

**Two-tier model**:
- **Opus 4.6**: Complex decisions (campaign strategy, admin chat, performance reviews) — ~$0.50-2.00/call
- **Haiku 4.5**: Simple tasks (message personalization, lead scoring, sentiment analysis) — ~$0.01-0.05/call

### Decision-Making Loop (Every 15 Minutes)

```
1. ASSESS — Gather current state
   - Active campaigns + quotas
   - Platform rate limit status
   - Pending follow-ups due now
   - New inbound replies needing response
   - Daily budget remaining

2. PRIORITIZE — AI decides what to do next
   P0: Respond to inbound replies (time-sensitive)
   P1: Execute scheduled follow-ups
   P2: Send new outreach messages
   P3: Discover new leads
   P4: Analyze & optimize campaigns

3. EXECUTE — Enqueue Oban jobs
   - Reply jobs → outreach_send queue
   - Follow-up jobs → outreach_send queue
   - New outreach → outreach_send queue
   - Discovery jobs → outreach_scrape queue

4. LOG — Record decisions + reasoning
```

### AI Tools (12+ outreach-specific)

```
get_outreach_state        # Current campaigns, quotas, pending actions
get_pending_replies       # Inbound messages needing response
get_due_follow_ups        # Follow-ups scheduled for now
compose_message           # Generate personalized outreach message
compose_reply             # Generate reply to inbound message
schedule_follow_up        # Schedule a follow-up for a lead
update_lead_status        # Mark lead as contacted/replied/converted/rejected
search_leads              # Trigger lead discovery on a platform
create_outreach_campaign  # Create a new campaign
pause_campaign            # Pause/resume a campaign
get_outreach_analytics    # Campaign performance metrics
escalate_to_admin         # Flag something for human review
```

### Admin Interaction

Chat-based LiveView at `/admin/outreach/manager`. Admin types natural language, AI executes.

| Admin Says | AI Does |
|------------|---------|
| "Focus on Telegram today" | Pauses Twitter, increases Telegram daily limit |
| "Pause all outreach" | Sets `outreach_enabled: false`, pauses campaigns |
| "How did we do this week?" | Runs analytics, generates narrative report |
| "Create a campaign targeting NFT traders" | Creates campaign, suggests templates, asks approval |
| "That message is too aggressive" | Updates template, explains changes |

### Autonomous vs Supervised Mode

- **Supervised** (default): AI proposes actions, admin approves. New campaigns need approval. Replies and follow-ups auto-sent.
- **Autonomous**: AI executes all decisions. Still logs everything. Daily summary to admin. Toggle via `outreach_auto_mode` in SystemConfig.

### Cost Management

- Daily budget cap (default $25/day)
- Separate limits for Opus calls (50/day) and Haiku calls (200/day)
- Budget protection enforced at GenServer level before any API call
- Learning optimizations reduce cost over time (cache successful patterns)

---

## 4. Lead Generation & Targeting

### Competitor Targets (30+)

**Crypto News**: CoinDesk, Decrypt, The Block, CoinTelegraph, Bankless, The Defiant, DL News, Unchained

**Web3 Social**: Farcaster/Warpcast, Lens Protocol, Mirror.xyz, Zora

**Play-to-Earn**: Axie Infinity, Immutable, Gala Games, Ronin Network, Pixels

**Crypto Communities**: CryptoSlam, DeFi Llama, Dune Analytics, Nansen

**Airdrop/Rewards**: Layer3, Galxe, Zealy, QuestN, DeBank

**Read-to-Earn Competitors**: Publish0x, Steemit (direct product-market fit)

### Lead Sources (Tiered by Quality)

**Tier 1 — High Intent** (+20 score bonus):
- Competitor follower engagers (people who like/reply, not just follow)
- Crypto hashtag engagers (#DeFi, #Web3, #PlayToEarn, #EarnCrypto)
- Airdrop hunter lists (Galxe, Layer3 followers)
- Crypto giveaway RT participants

**Tier 2 — Medium Intent** (+10 score bonus):
- Crypto Telegram group members
- NFT community members
- Crypto event attendees (ETHGlobal, Token2049)
- Crypto newsletter sharers

**Tier 3 — Broad** (+0 score bonus):
- Reddit crypto community posters
- YouTube crypto commenters
- On-chain activity signals (DeFi users, ENS holders)
- Crypto faucet users

### Lead Scoring (0-100)

Four dimensions, 25 points each:

| Dimension | Signals | Max Points |
|-----------|---------|------------|
| **Crypto Interest** | Bio keywords, ENS name, wallet in bio, follows crypto accounts | 25 |
| **Engagement** | Posting frequency, recent activity, account age, bot detection | 25 |
| **Influence** | Follower count, verified status, follower/following ratio | 25 |
| **Product-Market Fit** | Follows P2E/read-to-earn, airdrop platforms, content consumption | 25 |

**Priority Tiers**: Hot (75-100), Warm (40-74), Cold (0-39)

**AI Enrichment Layer** (Haiku): Classifies persona, generates summary, recommends best outreach angle, adjusts score +/- 10.

### Lead Pipeline State Machine

```
new → qualified → outreach_scheduled → contacted → follow_up_1 →
follow_up_2 → responded → converted → active_user
                                    └→ do_not_contact (opt-out/negative)
```

| Transition | Wait Time | Auto/Manual |
|------------|-----------|-------------|
| contacted → follow_up_1 | 72 hours | Auto |
| follow_up_1 → follow_up_2 | 5 days | Auto |
| follow_up_2 → do_not_contact | 7 days | Auto (exhausted) |
| responded → converted | — | Auto (signup detected) |
| Exhausted → re-eligible | 90 days | Auto (different campaign only) |

---

## 5. Personalization Engine

### Message Strategy

- **Lead with value, not pitch** — open with something relevant to THEM
- **One message = one idea** — pick the angle most relevant to their profile
- **No links in first message** on X (triggers spam filters). Links OK on Telegram
- **Ask, don't tell** — end with a question to invite reply
- **Mirror their language** — match their tone (degen, formal, casual)
- **AI rewrites every message** — templates are skeletons, not copy-paste

### Five Outreach Angles

| Angle | Hook | Best For |
|-------|------|----------|
| **News Reader** | "Earn BUX tokens for reading crypto news you'd read anyway" | CoinDesk/Decrypt followers |
| **Gamer** | "Provably fair on-chain game, zero gas, verifiable server seeds" | P2E/GameFi followers |
| **Community** | "Crypto community with topic hubs and engagement rewards" | Web3 social users |
| **Exclusive Offer** | "{offer_amount} BUX tokens free on signup" | Airdrop hunters |
| **Content Match** | Specific article/hub matching their interests | Users with clear topic interest |

### Example Templates (X DM — Author-Personalized)

Each DM comes from an AI author whose profile backs up what they're saying. The author's persona and recent articles inform the message.

**Jake Freeman (trading/macro) → DeFi trader lead, Touch 1:**
```
hey — saw your thread on the ETH supply dynamics. solid take. I write
about macro/trading stuff on Blockster and actually earn BUX tokens for
it (on-chain). you'd probably dig some of the analysis there. ever
tried read-to-earn?
```

**Sophia Reyes (gaming/NFTs) → P2E gamer lead, Touch 1:**
```
your take on {recent_activity} was interesting! have you tried any
provably fair on-chain games? I play this one called BUX Booster —
zero gas, server seeds revealed after every bet. I also write about
web3 gaming on Blockster if you're ever looking for good content
```

**Touch 2 (Day 2-3) — Any author, includes link:**
```
one more thing — here's my latest article on {author_article_topic}
if you want to check it out: {author_article_url}

you earn BUX tokens just for reading. no wallet needed, email signup.
here's my referral if you want the 500 BUX bonus: {referral_link}
```

**Touch 3 (Day 5-7) — Final, direct:**
```
last one from me — there's a trending piece on {trending_topic} on
Blockster right now: {featured_article_url}

you'd earn BUX just for reading it. no catch
```

The AI selects which author sends the DM based on lead-author affinity: trading leads get Jake or Marcus, gaming leads get Sophia, DeFi leads get Maya or Elena, etc.

### Personalization Variables

**From lead profile**: `{name}`, `{username}`, `{shared_interest}`, `{competitor_they_follow}`, `{recent_activity}`, `{crypto_sophistication}`

**From campaign**: `{offer_amount}`, `{referral_link}`, `{referral_code}`, `{hub_slug}`, `{featured_article_url}`

**From AI author** (selected based on lead-author affinity):
- `{author_name}` — the author sending the DM (Jake Freeman, Maya Chen, etc.)
- `{author_bio}` — their persona bio for prompt context
- `{author_style}` — writing style guide for tone matching
- `{author_article_url}` — their most recent Blockster article
- `{author_article_topic}` — topic of their latest article
- `{author_categories}` — their expertise areas for topic matching

**AI-generated per message**: `{personalized_opener}`, `{interest_bridge}`, `{casual_closer}`

### Author-Lead Affinity Matching

The system selects which AI author sends the DM based on the lead's interests:

| Lead Interest Signals | Best Author Match |
|----------------------|------------------|
| Trading, BTC, macro, investment | Jake Freeman or Marcus Stone |
| DeFi, yield farming, stablecoins | Maya Chen or Elena Vasquez |
| Privacy, security, self-custody | Alex Ward or Ryan Kolbe |
| Gaming, NFTs, metaverse | Sophia Reyes |
| AI + crypto, Ethereum, tech | Nina Takashi |
| Mining, exploits, cybersecurity | Ryan Kolbe |

This maps directly to the `categories` field already defined in `AuthorRotator`. The `LeadScorer` classifies lead interests → `AuthorRotator.select_for_category/1` picks the best author → that author's X account sends the DM.

### A/B Testing Framework

- **Minimum sample**: 200 messages per variant
- **Significance**: p < 0.05 (chi-squared)
- **Primary metric**: Reply rate
- **Auto-promotion**: Winning variant gets 80% traffic, 20% exploration
- **Max concurrent tests**: 3 per platform
- **AI creates and monitors tests automatically**
- Extends existing `ab_tests` table

### Response Handling

| Reply Type | AI Action |
|------------|-----------|
| Positive ("sure", "sounds cool") | Thank, send referral link, offer help |
| Question ("what is BUX?") | Honest answer, keep it short, never promise USD returns |
| Negative ("not interested") | "No worries, take care!" — mark do_not_contact |
| Hostile ("spam", "f off") | "Sorry to bother you." — mark do_not_contact |
| Complex (financial, partnership) | Escalate to admin |

### Conversion Tracking

Full attribution chain: DM Sent → Click → Signup → First Article → First BUX → First Game → First Purchase

Referral links include UTM params: `?ref={wallet}&utm_campaign={campaign_id}&utm_source={platform}&utm_medium=dm`

---

## 6. Account Management & Safety

### Account Pool

- **Buy aged accounts** — skip the establishment phase entirely
- Credentials encrypted at rest (AES-256-GCM via existing `BlocksterV2.Encryption`)
- Each account assigned: platform, status, daily limit, health score, proxy config, timezone

**Status lifecycle**: `warming → active → cooldown → quarantined → suspended → retired`

### Account Warming Protocol

#### Buying Aged Accounts (Recommended)

Aged accounts already have history, followers, and activity patterns. This lets you **skip Stage 1 entirely** and fast-track to sending in 7-12 days instead of 22.

**What to look for when buying**:
- Account age: 1+ year (older = better)
- Has posting history and followers (not blank/dormant)
- No prior strikes or restrictions
- Phone/email verified
- Platform-appropriate: X accounts with crypto-relevant follow lists are ideal

#### Fast-Track Warming (Aged Accounts) — 7-12 Days

| Stage | Days | DMs/Day | Activities |
|-------|------|---------|------------|
| ~~1. Establishment~~ | SKIP | — | Aged accounts already have this |
| 2. Re-activation | 1-5 | 3-5 (warm contacts) | Browse, like, post, comment — establish new IP/session fingerprint |
| 3. Ramp-Up | 6-10 | 5 → 10 → 20 | Gradual cold DM increase, 3:1 organic:DM ratio |
| 4. Full Operation | 11+ | Platform max | Sustainable outreach at safe limits |

**Why re-activation is still needed**: Even aged accounts need to establish activity from your new proxy IP and device fingerprint. Platforms notice when a dormant account suddenly starts mass DMing from a new location.

#### Fresh Account Warming (If Needed) — 22 Days

| Stage | Days | DMs/Day | Activities |
|-------|------|---------|------------|
| 1. Establishment | 1-7 | 0 | Browse, like 5-15 posts, follow 3-8 accounts |
| 2. Light Engagement | 8-14 | 3-5 (warm contacts) | + Post content, comment on posts |
| 3. Ramp-Up | 15-21 | 5 → 10 → 20 | Gradual cold DM increase, 3:1 organic:DM ratio |
| 4. Full Operation | 22+ | Platform max | Sustainable outreach at safe limits |

Auto-demotion: health < 70 → demote one stage. Health < 50 → quarantine.

### Safe Daily Limits (Recommended for Blockster)

| Platform | Action | Daily Limit/Account | Min Delay |
|----------|--------|-------------------|-----------|
| **X (Twitter)** | Cold DMs | 30 | 3-5 min |
| **Telegram** | Cold DMs | 40 | 2-3 min |
| **Instagram** | Engagement actions (follows, story replies, comments) | 50-80 | 2-5 min |
| **Instagram** | Cold DMs | NOT RECOMMENDED — high ban risk | — |
| **TikTok** | Cold DMs | NOT POSSIBLE — API is response-only | — |
| **Facebook** | Cold DMs | NOT POSSIBLE — requires explicit opt-in | — |

### Account Rotation

- **Weighted random selection** based on health_score × warmup_multiplier × cooldown_factor × time_of_day_factor
- Minimum 90-300 second gap between messages from same account
- At 70% daily limit → switch to engagement-only mode
- Weekly rest day per account (staggered across pool)
- Monthly 3-day rest period per account

### Proxy/IP Management

- Residential proxies only (datacenter IPs instantly detected)
- One sticky IP per account (same region as account's "home" location)
- 24h+ sessions, health checks every 30 min
- Cost: $1-3/account/day for residential (SmartProxy, BrightData, IPRoyal)

**Cost reduction strategies**:
- Share proxies across 2-3 accounts on DIFFERENT platforms (X + Telegram on same IP = lower risk than 2 X accounts on same IP)
- Mobile proxy pools ($5-15/mo per IP) for highest-value accounts
- Rotating proxies with longer sticky sessions instead of fully dedicated IPs

### Human Behavior Simulation

- Typing: 40-80 WPM, keystroke delays (75-200ms), occasional typos
- Browsing: 30-120 second feed scrolls between DMs, random likes
- Sessions: 20-90 min, 3-6 per day, following timezone patterns
- All timing includes jitter: `base_delay + random(0, base_delay * 0.4)`

### Health Monitoring (0-100 score)

| Event | Score Impact |
|-------|-------------|
| Platform warning | -30 |
| CAPTCHA | -20 |
| Delivery rate < 80% | -15 |
| Reduced reach detected | -10 |
| Each day at 90%+ limit | -5 |
| Clean day in cooldown | +2/day |
| Successful health check | +5 |

**Auto-quarantine**: score < 50, platform warning, CAPTCHA 2+ times in 24h

**Emergency shutdown**: >25% of accounts quarantined on single platform → pause all, alert admin

---

## 7. Admin Dashboard

### Route Structure (13 routes)

All under existing `:admin` live_session:

```
/admin/outreach              — Dashboard overview
/admin/outreach/manager      — AI Manager chat interface
/admin/outreach/campaigns    — Campaign list
/admin/outreach/campaigns/new — Create campaign
/admin/outreach/campaigns/:id — Campaign detail
/admin/outreach/campaigns/:id/edit — Edit campaign
/admin/outreach/leads        — Lead management
/admin/outreach/leads/:id    — Lead detail
/admin/outreach/accounts     — Account pool management
/admin/outreach/templates    — Message templates
/admin/outreach/templates/:id/edit — Template editor
/admin/outreach/analytics    — Analytics & reports
/admin/outreach/settings     — System configuration
```

### Page Summary

| Page | Key Features |
|------|-------------|
| **Dashboard** | Real-time metric cards, platform breakdown, lead funnel, AI status, account health, activity feed |
| **AI Manager** | Chat interface (reuses existing AIManagerLive pattern), starter prompts, quick actions, AI status |
| **Campaigns** | CRUD, status filters, platform badges, daily budget, funnel metrics per campaign |
| **Leads** | Searchable table (MVP) + Kanban board (stretch), bulk actions, lead detail with outreach timeline |
| **Accounts** | Grid of account cards with health indicators, warming progress, quick quarantine toggles |
| **Templates** | Template cards with performance stats, editor with variable insertion, A/B variant management |
| **Analytics** | Conversion funnel, daily volume charts, platform comparison, best performing messages, CSV export |
| **Settings** | Rate limits, AI behavior, default offers, blocked keywords, notification preferences |

### UI Conventions (matching existing admin)

- Background: `bg-[#F5F6FB]`
- Cards: `bg-white rounded-2xl shadow-sm border border-gray-100`
- Headers: `font-haas_medium_65`, subtitles: `font-haas_roman_55`
- Buttons: `bg-gray-900 text-white rounded-xl` (primary), `bg-white border border-gray-200` (secondary)
- Brand accent (#CAFC00): Icon backgrounds only, NEVER buttons or text
- Tabs: pill-style `rounded-xl`, active: `bg-[#141414] text-white`

### Shared Components

- `outreach_nav/1` — horizontal sub-navigation across all outreach pages
- `platform_badge/1` — colored platform indicators (Telegram=blue, X=sky)
- `health_indicator/1` — green/amber/red pulsing dots
- `lead_score_badge/1` — Hot/Warm/Cold temperature badges

---

## 8. Database Schema

### New Tables (10)

```sql
-- 1. Outreach campaigns
CREATE TABLE outreach_campaigns (
  id SERIAL PRIMARY KEY,
  name VARCHAR NOT NULL,
  description TEXT,
  status VARCHAR DEFAULT 'draft',  -- draft, active, paused, completed, archived
  platforms JSONB DEFAULT '[]',
  target_criteria JSONB DEFAULT '{}',
  daily_send_limit INTEGER DEFAULT 20,
  total_limit INTEGER,
  template_ids TEXT[] DEFAULT '{}',
  ab_test_enabled BOOLEAN DEFAULT false,
  total_sent INTEGER DEFAULT 0,
  total_replied INTEGER DEFAULT 0,
  total_converted INTEGER DEFAULT 0,
  ai_notes TEXT,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  inserted_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

-- 2. Outreach leads
CREATE TABLE outreach_leads (
  id SERIAL PRIMARY KEY,
  platform VARCHAR NOT NULL,
  platform_id VARCHAR NOT NULL,
  platform_username VARCHAR,
  display_name VARCHAR,
  bio TEXT,
  profile_url VARCHAR,
  follower_count INTEGER DEFAULT 0,
  following_count INTEGER DEFAULT 0,
  qualification_score INTEGER DEFAULT 0,  -- 0-100
  crypto_interest_score INTEGER DEFAULT 0,
  engagement_score INTEGER DEFAULT 0,
  influence_score INTEGER DEFAULT 0,
  fit_score INTEGER DEFAULT 0,
  priority_tier VARCHAR DEFAULT 'cold',
  interests TEXT[] DEFAULT '{}',
  interest_signals JSONB DEFAULT '{}',
  source VARCHAR,
  source_detail VARCHAR,
  outreach_status VARCHAR DEFAULT 'new',
  outreach_channel VARCHAR,
  linked_platforms JSONB DEFAULT '{}',
  wallet_address VARCHAR,
  ai_summary TEXT,
  ai_persona VARCHAR,
  ai_recommended_hook VARCHAR,
  ai_confidence FLOAT,
  do_not_contact BOOLEAN DEFAULT false,
  do_not_contact_reason VARCHAR,
  is_bot BOOLEAN DEFAULT false,
  converted_user_id INTEGER REFERENCES users(id),
  first_contacted_at TIMESTAMPTZ,
  last_contacted_at TIMESTAMPTZ,
  converted_at TIMESTAMPTZ,
  inserted_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL,
  UNIQUE(platform, platform_id)
);

-- 3. Outreach messages
CREATE TABLE outreach_messages (
  id SERIAL PRIMARY KEY,
  outreach_campaign_id INTEGER REFERENCES outreach_campaigns(id),
  outreach_lead_id INTEGER REFERENCES outreach_leads(id),
  outreach_account_id INTEGER REFERENCES outreach_accounts(id),
  platform VARCHAR NOT NULL,
  direction VARCHAR NOT NULL,  -- outbound, inbound
  message_type VARCHAR,        -- initial, follow_up_1, follow_up_2, reply
  template_angle VARCHAR,
  ab_variant VARCHAR,
  content TEXT NOT NULL,
  personalization_data JSONB,
  platform_message_id VARCHAR,
  status VARCHAR DEFAULT 'pending',  -- pending, sent, delivered, read, replied, failed
  delivered_at TIMESTAMPTZ,
  read_at TIMESTAMPTZ,
  replied_at TIMESTAMPTZ,
  reply_sentiment VARCHAR,
  error_message TEXT,
  inserted_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

-- 4. Outreach conversations
CREATE TABLE outreach_conversations (
  id SERIAL PRIMARY KEY,
  outreach_lead_id INTEGER REFERENCES outreach_leads(id),
  outreach_campaign_id INTEGER REFERENCES outreach_campaigns(id),
  platform VARCHAR NOT NULL,
  status VARCHAR DEFAULT 'active',  -- active, waiting_reply, closed, converted, escalated
  message_count INTEGER DEFAULT 0,
  last_message_at TIMESTAMPTZ,
  next_action VARCHAR,
  next_action_at TIMESTAMPTZ,
  ai_context JSONB DEFAULT '{}',
  escalated_to INTEGER,
  inserted_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

-- 5. Outreach accounts (platform account pool)
CREATE TABLE outreach_accounts (
  id SERIAL PRIMARY KEY,
  platform VARCHAR NOT NULL,
  username VARCHAR NOT NULL,
  display_name VARCHAR,
  encrypted_credentials BYTEA NOT NULL,  -- AES-256-GCM
  credential_type VARCHAR,
  status VARCHAR DEFAULT 'warming',  -- warming, active, cooldown, quarantined, suspended, retired
  warmup_stage INTEGER DEFAULT 1,    -- 1-4
  warmup_started_at TIMESTAMPTZ,
  health_score INTEGER DEFAULT 100,
  daily_limit INTEGER,
  messages_sent_today INTEGER DEFAULT 0,
  messages_sent_this_hour INTEGER DEFAULT 0,
  total_messages_sent INTEGER DEFAULT 0,
  last_message_at TIMESTAMPTZ,
  last_active_at TIMESTAMPTZ,
  last_health_check_at TIMESTAMPTZ,
  timezone VARCHAR DEFAULT 'America/New_York',
  proxy_config JSONB,
  account_age_days INTEGER,
  follower_count INTEGER DEFAULT 0,
  flags TEXT[] DEFAULT '{}',
  region VARCHAR,
  cooldown_until TIMESTAMPTZ,
  notes TEXT,
  retired_reason VARCHAR,
  account_group_id INTEGER REFERENCES outreach_account_groups(id),
  inserted_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

-- 6. Account groups
CREATE TABLE outreach_account_groups (
  id SERIAL PRIMARY KEY,
  name VARCHAR NOT NULL,
  platform VARCHAR,
  purpose VARCHAR,
  region VARCHAR,
  inserted_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

-- 7. Outreach attempts (per-message tracking)
CREATE TABLE outreach_attempts (
  id SERIAL PRIMARY KEY,
  outreach_lead_id INTEGER REFERENCES outreach_leads(id) NOT NULL,
  outreach_campaign_id INTEGER REFERENCES outreach_campaigns(id),
  outreach_account_id INTEGER REFERENCES outreach_accounts(id),
  channel VARCHAR NOT NULL,
  template_id VARCHAR,
  ab_variant VARCHAR,
  message_content TEXT,
  status VARCHAR DEFAULT 'pending',  -- pending, sent, delivered, read, replied, failed, bounced
  sent_at TIMESTAMPTZ,
  delivered_at TIMESTAMPTZ,
  read_at TIMESTAMPTZ,
  replied_at TIMESTAMPTZ,
  reply_content TEXT,
  reply_sentiment VARCHAR,
  error_message TEXT,
  inserted_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

-- 8. Lead source runs (scraping job tracking)
CREATE TABLE lead_source_runs (
  id SERIAL PRIMARY KEY,
  source_type VARCHAR NOT NULL,
  source_detail VARCHAR,
  status VARCHAR DEFAULT 'pending',  -- pending, running, completed, failed
  leads_found INTEGER DEFAULT 0,
  leads_qualified INTEGER DEFAULT 0,
  leads_duplicate INTEGER DEFAULT 0,
  cursor VARCHAR,  -- resumable pagination
  error_message TEXT,
  started_at TIMESTAMPTZ,
  completed_at TIMESTAMPTZ,
  inserted_at TIMESTAMPTZ NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL
);

-- 9. Health check log
CREATE TABLE outreach_health_checks (
  id SERIAL PRIMARY KEY,
  outreach_account_id INTEGER REFERENCES outreach_accounts(id) NOT NULL,
  health_score_before INTEGER,
  health_score_after INTEGER,
  checks_passed JSONB DEFAULT '{}',
  issues_found TEXT[] DEFAULT '{}',
  inserted_at TIMESTAMPTZ NOT NULL
);

-- 10. Admin-AI chat messages
CREATE TABLE outreach_admin_messages (
  id SERIAL PRIMARY KEY,
  admin_user_id INTEGER REFERENCES users(id),
  role VARCHAR NOT NULL,  -- 'admin' or 'ai'
  content TEXT NOT NULL,
  tool_calls JSONB,
  inserted_at TIMESTAMPTZ NOT NULL
);
```

### SystemConfig Extensions

Add to `@defaults` in existing `system_config.ex`:

```elixir
"outreach_enabled" => false,
"outreach_daily_message_limit" => 50,
"outreach_ai_budget_per_day" => 100,
"outreach_platforms_enabled" => ["twitter"],
"outreach_follow_up_days" => [3, 7],
"outreach_cooldown_hours" => 24,
"outreach_auto_mode" => false,
"outreach_reply_auto_respond" => true,
"outreach_max_follow_ups" => 2,
"outreach_twitter_daily_dm_limit" => 30,
"outreach_telegram_daily_limit" => 40,
"outreach_min_lead_score" => 40,
"outreach_default_bux_offer" => 500,
"outreach_escalation_keywords" => ["interested", "tell me more", "how do I", "sign up"]
```

---

## 9. Scaling Roadmap & Cost Projections

### Why Not Start With 1000 Accounts?

There's no technical ceiling — the `AccountRouter` GenServer handles weighted rotation regardless of pool size. The constraints are economic:

### Cost Projections by Scale

| Accounts | DMs/Day | Proxy Cost/Month | Account Cost (one-time) | AI API/Month | Total Monthly |
|----------|---------|------------------|------------------------|-------------|---------------|
| **10** | 300-400 | **$300-900** | $50-500 | $750 | **$1,050-1,650** |
| **50** | 1,500-2,000 | **$1,500-4,500** | $250-2,500 | $750 | **$2,250-5,250** |
| **100** | 3,000-4,000 | **$3,000-9,000** | $500-5,000 | $750 | **$3,750-9,750** |
| **500** | 15,000-20,000 | **$15,000-45,000** | $2,500-25,000 | $750 | **$15,750-45,750** |
| **1,000** | 30,000 | **$30,000-90,000** | $5,000-50,000 | $750 | **$30,750-90,750** |

Notes:
- Proxy cost = $1-3/account/day × 30 days (can be reduced with shared proxies / mobile pools)
- Account cost is one-time (aged accounts: $5-50 each depending on platform and age)
- AI API cost is relatively fixed (~$25/day = $750/mo) since Haiku handles per-message personalization cheaply
- X API: $200/mo flat (covers ALL accounts via single OAuth app)
- Telegram API: Free

### Recommended Scaling Path

**Phase 1 — Validate (Months 1-2)**:
- 10 accounts (5 X + 5 Telegram)
- ~300-400 DMs/day
- Monthly cost: ~$1,000-1,500
- **Goal**: Prove reply rate >10%, conversion rate >5%, measure CPA

**Phase 2 — Scale (Months 3-4)**:
- 50 accounts (25 X + 20 Telegram + 5 Instagram engagement)
- ~1,500-2,000 DMs/day
- Monthly cost: ~$2,500-5,000
- **Goal**: Optimize messaging via A/B tests, build lead pipeline depth

**Phase 3 — Accelerate (Month 5+)**:
- 100-200 accounts (scale what's working)
- ~3,000-8,000 DMs/day
- Monthly cost: ~$4,000-18,000
- **Scale decision**: Only if CPA justifies it (if each signup is worth $X and CPA < $X, keep scaling)

**Phase 4 — Maximum (only if ROI positive)**:
- 500+ accounts
- 15,000+ DMs/day
- Monthly cost: $15,000+
- **Warning**: At this scale you'll exhaust competitor follower lists fast — lead quality drops. AI needs to find new creative lead sources.

### Break-Even Math

```
If signup value = $10 (lifetime BUX engagement + potential purchases)
And CPA = $3 (at 10-account scale with 5% conversion)
Then ROI = ($10 - $3) / $3 = 233%

At 300 DMs/day × 10% reply × 5% convert = 1.5 signups/day = 45/month
Revenue: 45 × $10 = $450
Cost: ~$1,200/month
→ Need signup value of ~$27 to break even at 10-account scale
→ OR scale to 50 accounts where volume makes fixed costs worthwhile
```

The key metric to validate first: **what is a Blockster signup actually worth?** Once you know that, the scaling math becomes straightforward.

---

## 10. Implementation Phases

### Phase O1: Database & Core Schemas (~40 tests)
- Migrations for all 10 tables
- Ecto schemas with validations and changesets
- `BlocksterV2.Outreach` context module with CRUD operations
- SystemConfig extensions for outreach keys
- **Files**: ~12 new (schemas + migrations + context)

### Phase O2: Platform Clients (~30 tests)
- X/Twitter API client (search users, send DMs, read DMs, follower scraping via single OAuth app)
- Telegram service (Python/FastAPI + Telethon, deployed on Fly.io as separate app)
- Elixir HTTP client module to call Telegram service endpoints
- Instagram engagement client (follows, story replies, comments — no cold DMs)
- Rate limiting per platform
- Platform client behaviour for common interface
- **Files**: ~6 new Elixir (clients + behaviour) + ~4 Python files (Telegram service)

### Phase O3: Lead Discovery & Scoring (~25 tests)
- `LeadDiscoveryWorker` (keyword search, competitor follower scraping)
- `LeadScorer` module (rule-based + AI enrichment via Haiku)
- Lead deduplication and cross-platform linking
- Lead pipeline state machine transitions
- **Files**: ~4 new (workers + scorer)

### Phase O4: OutreachAI & Message Composition (~35 tests)
- `OutreachAI` module (Claude tool_use with 12+ outreach tools)
- Message personalization engine (template selection + AI rewriting)
- A/B test integration (extends existing ab_tests)
- Response classification and reply generation
- **Files**: ~4 new (AI module + engine)

### Phase O5: GenServers & Orchestrator (~30 tests)
- `OutreachManager` GenServer (GlobalSingleton) with state management
- `AccountRouter` GenServer (GlobalSingleton) for account selection
- `OutreachOrchestratorWorker` (15-min decision loop)
- `OutreachSendWorker` (message delivery)
- `OutreachReplyProcessorWorker` (inbound reply handling)
- **Files**: ~6 new (GenServers + workers)

### Phase O6: Account Management (~25 tests)
- Account warming workers
- Proxy management
- Health monitoring workers
- Human behavior simulation
- Account failover logic
- **Files**: ~5 new (workers + simulation)

### Phase O7: Admin Dashboard (~30 tests)
- Dashboard overview page
- AI Manager chat interface (reuse existing pattern)
- Campaign CRUD pages
- Lead management pages
- Account management page
- Templates page
- Analytics page
- Settings page
- Shared components
- **Files**: ~13 new (LiveViews + components)

### Phase O8: Integration & Polish (~20 tests)
- Conversion tracking (auth_controller integration)
- Referral system tie-in
- Notification system integration
- Daily/weekly review workers
- CSV export
- **Files**: ~3 new + modifications to existing files

**Estimated Total: ~235 tests, ~52 new files across 8 phases**

---

## 11. Risk Assessment

### Platform Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Account bans on X | Lose sending capacity | Medium | Conservative limits, warming protocol, buffer pool |
| Telegram PeerFloodError | Temporary sending block | High | Multiple accounts, cool-down rotation, 40/day limit |
| Platform ToS changes | May invalidate approach | Medium | Abstract platform layer, quick pivot capability |
| Meta stricter enforcement | IG/FB become unusable | High | Already deprioritized — scrape-only strategy |

### Technical Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| AI hallucination in messages | Embarrassing/misleading DMs | Low | Review mode default, message templates as guardrails |
| Proxy IP blocklisting | Accounts flagged | Medium | Residential-only, health checks, provider rotation |
| High AI API costs | Budget overrun | Low | Two-tier model, budget caps, Haiku for simple tasks |
| Rate limit race conditions | Multiple accounts sending simultaneously | Low | AccountRouter GenServer serializes selection |

### Reputation Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Perceived as spam | Brand damage | Medium | Quality personalization, conservative limits, immediate opt-out |
| User complaints on social | Public backlash | Low | Genuine value messaging, never aggressive follow-ups |
| GDPR complaints | Legal exposure | Low | 12-month retention, right to erasure, legitimate interest basis |

---

## 12. Integration Points

### Existing Systems

| System | Integration |
|--------|-------------|
| **Referrals** | Campaign-specific referral links, signup attribution via `process_signup_referral/2` |
| **Notification System** | Admin alerts, converted user welcome series, campaign analytics |
| **UserEvents** | Track outreach-originated user behavior (`outreach_link_clicked`, `outreach_signup`) |
| **SystemConfig** | All tunable parameters via existing key-value store |
| **AIManager** | Shares patterns but separate module — outreach has its own tools and context |
| **ABTestEngine** | Extends existing A/B testing for outreach message variants |
| **ProfileEngine** | Engagement tier classification for post-conversion analysis |

### PubSub Topics (New)

```
"outreach:admin_chat"        — Admin ↔ AI conversation updates
"outreach:campaign_updates"  — Campaign status changes
"outreach:lead_updates"      — Lead status changes (real-time dashboard)
"outreach:reply_received"    — Inbound reply triggers P0 processing
"outreach:account_alerts"    — Account health issues
"outreach:message_sent"      — Per-message broadcast for analytics
"outreach:emergency"         — Emergency shutdown
```

### File Structure

```
lib/blockster_v2/outreach/
├── outreach.ex                  # Context module (CRUD)
├── outreach_manager.ex          # GenServer (GlobalSingleton)
├── outreach_ai.ex               # Claude API for outreach decisions
├── account_router.ex            # GenServer for account selection
├── lead_scorer.ex               # AI-powered lead scoring
├── campaign.ex                  # Ecto schema
├── lead.ex                      # Ecto schema
├── message.ex                   # Ecto schema
├── conversation.ex              # Ecto schema
├── account.ex                   # Ecto schema
├── account_group.ex             # Ecto schema
├── attempt.ex                   # Ecto schema
├── lead_source_run.ex           # Ecto schema
├── health_check.ex              # Ecto schema
├── admin_message.ex             # Ecto schema
├── encrypted_map.ex             # Custom Ecto type
├── analytics.ex                 # Analytics queries
├── platforms/
│   ├── behaviour.ex             # Common platform interface
│   ├── twitter.ex               # X/Twitter DM client (OAuth, single API key for all accounts)
│   ├── telegram.ex              # HTTP client calling Telegram microservice
│   └── instagram.ex             # Instagram engagement funnel (follows, story replies, comments)

# Separate repo/directory: telegram-outreach-service/
telegram-outreach-service/
├── main.py                      # FastAPI app with all endpoints
├── session_manager.py           # Telethon session lifecycle
├── account_pool.py              # Multi-account management
├── proxy_router.py              # Proxy-to-account sticky mapping
├── requirements.txt             # telethon, fastapi, uvicorn, python-socks
├── Dockerfile
└── fly.toml                     # Fly.io deployment config
└── templates/
    └── message_templates.ex     # Template definitions

lib/blockster_v2/workers/
├── outreach_orchestrator_worker.ex    # 15-min decision loop
├── outreach_send_worker.ex            # Sends individual DMs
├── outreach_reply_processor_worker.ex # Processes inbound replies
├── lead_discovery_worker.ex           # Discovers leads
├── outreach_daily_review_worker.ex    # Daily AI review
├── account_health_worker.ex           # Health monitoring
├── account_warmup_worker.ex           # Warming activities
├── outreach_engagement_worker.ex      # Organic engagement (likes, follows, replies)
├── author_content_worker.ex           # Generate daily tweets/RTs for each AI author
├── author_article_poster_worker.ex    # Auto-tweet when author's Blockster article publishes
├── token_refresh_worker.ex            # OAuth token refresh
└── daily_counter_reset_worker.ex      # Reset daily counters

lib/blockster_v2_web/live/outreach_admin_live/
├── dashboard.ex          # Overview
├── manager.ex            # AI chat
├── campaigns.ex          # Campaign list
├── campaign_form.ex      # Create/edit
├── campaign_show.ex      # Detail with tabs
├── leads.ex              # Lead table
├── lead_show.ex          # Lead detail
├── accounts.ex           # Account management
├── templates.ex          # Template list
├── template_form.ex      # Template editor
├── analytics.ex          # Analytics
├── settings.ex           # Configuration
└── components.ex         # Shared components

priv/repo/migrations/
├── XXXXXX_create_outreach_account_groups.exs
├── XXXXXX_create_outreach_accounts.exs
├── XXXXXX_create_outreach_campaigns.exs
├── XXXXXX_create_outreach_leads.exs
├── XXXXXX_create_outreach_messages.exs
├── XXXXXX_create_outreach_conversations.exs
├── XXXXXX_create_outreach_attempts.exs
├── XXXXXX_create_lead_source_runs.exs
├── XXXXXX_create_outreach_health_checks.exs
└── XXXXXX_create_outreach_admin_messages.exs
```
