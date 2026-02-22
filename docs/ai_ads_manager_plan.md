# AI Ads Manager — Comprehensive Implementation Plan

> **Status**: Planning Phase
> **Branch**: TBD (suggest `feat/ai-ads-manager`)
> **Last Updated**: 2026-02-21

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [System Architecture](#2-system-architecture)
3. [Platform Integrations](#3-platform-integrations)
4. [AI Agent Design](#4-ai-agent-design)
5. [Creative Generation Pipeline](#5-creative-generation-pipeline)
6. [Offer & Promotion System](#6-offer--promotion-system)
7. [Budget Management](#7-budget-management)
8. [Analytics & Attribution](#8-analytics--attribution)
9. [Admin Dashboard & Interaction](#9-admin-dashboard--interaction)
10. [Safety Guardrails](#10-safety-guardrails)
11. [Database Schema](#11-database-schema)
12. [Codebase Integration Points](#12-codebase-integration-points)
13. [Implementation Phases](#13-implementation-phases)
14. [Cost Estimates](#14-cost-estimates)
15. [File Structure](#15-file-structure)

---

## 1. Executive Summary

### What

An autonomous AI-powered advertising system that creates, funds, manages, optimizes, and analyzes ad campaigns across X, Facebook, Instagram, Telegram, and TikTok — with minimal human intervention.

### Why

- Automatically promote every new article published on Blockster
- Drive traffic to the shop, games (BUX Booster), and signup flow
- Acquire new users who read articles, earn BUX, play games, and buy products
- Make offers (free BUX, shop discounts, free game spins) to incentivize engagement
- Optimize spend across platforms using AI decision-making

### How

- **Elixir-native** — GenServer agent, Oban scheduling, PubSub events, Ecto persistence
- **Claude API** as the decision-making brain with tool-calling for platform actions
- **Node.js microservice** for ad platform API integration (SDKs only exist for Node.js/Python)
- **Event-driven** for real-time triggers + **cron-driven** for periodic optimization
- **Progressive autonomy** — starts with admin approval for everything, gradually increases AI independence

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Agent framework | Custom Elixir + Claude API | Fits existing stack, no Python runtime needed |
| Platform API wrapper | Node.js microservice (separate Fly.io app) | Official SDKs (Meta, TikTok) only available in Node.js |
| Creative generation | Claude (copy) + GPT Image 1 (images) + Runway (video) | Best quality/cost balance |
| Scheduling | Oban | Already in the stack, battle-tested |
| Config storage | SystemConfig (existing) | Already designed for "AI Manager writes, everything reads" |
| Budget tracking | PostgreSQL | Time-series with BRIN indexes, daily aggregates |
| Priority platforms | All 4: X, Meta (FB/IG), TikTok, Telegram | Full coverage, $50/day starting budget |
| Multi-account | Per-platform account registry | Risk isolation, separate billing, A/B at account level |
| Admin creatives | Always accepted, override AI | Admin can submit custom text/images for any campaign |

---

## 2. System Architecture

### High-Level Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                    BLOCKSTER ELIXIR APPLICATION                   │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────┐   │
│  │  Blog.ex     │  │  Shop        │  │  Admin LiveView      │   │
│  │  publish_post│  │  product     │  │  /admin/ads/*        │   │
│  │  ──────────► │  │  ──────────► │  │  ◄─── dashboard      │   │
│  │  PubSub      │  │  PubSub      │  │  ◄─── instructions   │   │
│  └──────┬───────┘  └──────┬───────┘  └──────────┬───────────┘   │
│         │                 │                      │               │
│         ▼                 ▼                      ▼               │
│  ┌─────────────────────────────────────────────────────────┐     │
│  │              AI ADS MANAGER (GenServer)                  │     │
│  │                                                         │     │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────────┐ │     │
│  │  │ Campaign │ │ Budget   │ │ Creative │ │ Analytics │ │     │
│  │  │ Manager  │ │ Manager  │ │ Pipeline │ │ Engine    │ │     │
│  │  └──────────┘ └──────────┘ └──────────┘ └───────────┘ │     │
│  │                                                         │     │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌───────────┐ │     │
│  │  │ Offer    │ │ Decision │ │ Safety   │ │ Admin     │ │     │
│  │  │ Manager  │ │ Logger   │ │ Guards   │ │ Processor │ │     │
│  │  └──────────┘ └──────────┘ └──────────┘ └───────────┘ │     │
│  └──────────────────────┬──────────────────────────────────┘     │
│                         │                                        │
│  ┌──────────────────────┼────────────────────────────────────┐   │
│  │      OBAN WORKERS    │                                    │   │
│  │  ┌─────────────┐  ┌──┴──────────┐  ┌──────────────────┐  │   │
│  │  │ Performance │  │ Budget      │  │ Creative         │  │   │
│  │  │ Check (1h)  │  │ Pacing (4h) │  │ Fatigue (6h)     │  │   │
│  │  ├─────────────┤  ├─────────────┤  ├──────────────────┤  │   │
│  │  │ Daily Reset │  │ Weekly Opt  │  │ Reports (daily)  │  │   │
│  │  ├─────────────┤  ├─────────────┤  ├──────────────────┤  │   │
│  │  │ Offer Check │  │ Campaign    │  │ Attribution      │  │   │
│  │  │ (2h)        │  │ Launch      │  │ Reconciliation   │  │   │
│  │  └─────────────┘  └─────────────┘  └──────────────────┘  │   │
│  └───────────────────────────────────────────────────────────┘   │
│                         │                                        │
└─────────────────────────┼────────────────────────────────────────┘
                          │ HTTP/JSON
                          ▼
┌──────────────────────────────────────────────────────────────────┐
│               AD PLATFORM MICROSERVICE (Node.js)                 │
│               Deployed on Fly.io: ads-manager.fly.dev            │
│                                                                  │
│  ┌────────────┐ ┌────────────┐ ┌────────────┐ ┌──────────────┐  │
│  │ Meta SDK   │ │ TikTok SDK │ │ X REST API │ │ Telegram     │  │
│  │ (official) │ │ (official) │ │ (custom)   │ │ (Bot API +   │  │
│  │            │ │            │ │            │ │  manual)     │  │
│  └────────────┘ └────────────┘ └────────────┘ └──────────────┘  │
│                                                                  │
│  ┌────────────────┐  ┌────────────────┐  ┌──────────────────┐   │
│  │ Creative Gen   │  │ Image Process  │  │ Video Process    │   │
│  │ (Claude API)   │  │ (Sharp + GPT   │  │ (Runway API)     │   │
│  │                │  │  Image 1)      │  │                  │   │
│  └────────────────┘  └────────────────┘  └──────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Runs In | Purpose |
|-----------|---------|---------|
| **AdsManager (GenServer)** | Elixir (GlobalSingleton) | Central brain — receives events, calls Claude for decisions, coordinates all subsystems |
| **Campaign Manager** | Elixir module | CRUD for campaigns, state machine transitions, platform sync |
| **Budget Manager** | Elixir module | Budget allocation, pacing, reallocation, limit enforcement |
| **Creative Pipeline** | Calls Node.js service | Generate ad copy, images, videos; A/B variant management |
| **Analytics Engine** | Elixir module | Pull metrics from platforms, calculate KPIs, trend detection |
| **Offer Manager** | Elixir module | BUX giveaways, discount codes, free spins, redemption tracking |
| **Decision Logger** | Elixir module | Audit trail of all AI decisions with reasoning |
| **Safety Guards** | Elixir module | Spending limits, anomaly detection, kill switches |
| **Admin Processor** | Elixir module | Parse natural language instructions, execute overrides |
| **Ad Platform Service** | Node.js (Fly.io) | Wrapper around all ad platform APIs, creative generation |
| **Oban Workers** | Elixir | Periodic tasks — performance checks, budget pacing, reports |

### Communication Flow

```
1. Post Published → PubSub "post:published"
2. AdsManager receives event
3. AdsManager calls Claude API: "Should we promote this post? On which platforms? Budget?"
4. Claude returns structured decision with tool calls
5. AdsManager calls Creative Pipeline → Node.js service generates copy + images
6. AdsManager calls Campaign Manager → Node.js service creates campaigns on platforms
7. AdsManager logs decision → ai_manager_logs table
8. Oban workers poll performance data hourly
9. AdsManager evaluates performance → Claude decides optimizations
10. Repeat until campaign completes
```

---

## 3. Platform Integrations

### Platform Priority & Feasibility

| Priority | Platform | Automation Level | Crypto Policy | API Quality | Min Budget |
|----------|----------|-----------------|---------------|-------------|------------|
| **P0** | **X (Twitter)** | Full API | Friendly (educational OK) | Good | $10/day |
| **P0** | **Telegram** | Semi-manual | Very friendly | No ad API | $2K initial |
| **P1** | **Meta (FB/IG)** | Full API | Moderate (news/edu OK) | Excellent | $5/day |
| **P2** | **TikTok** | Full API | Restrictive (edu only) | Good | $50/day |

### Platform Integration Details

#### X (Twitter) Ads API
- **Auth**: OAuth 1.0a, requires Ads API allowlisting (apply at ads.x.com)
- **SDK**: No official Node.js — use direct REST API
- **Hierarchy**: Campaign → Line Item → Promoted Tweet
- **Key Formats**: Image ads (1200x675), video ads (15s), carousel (2-6 cards)
- **Text Limit**: 280 chars (links use 23 chars each)
- **Targeting**: Interests (350+ categories), follower lookalikes, keyword targeting
- **Bidding**: Auto-bid, target cost, maximum bid
- **Analytics**: Sync (real-time) + Async (historical) endpoints, no webhooks (poll)
- **Crypto**: Educational/informational content OK without prior auth. Token promotion needs approval.
- **Typical CPM**: $2-5 | **CPC**: $0.18-$2.00

#### Meta (Facebook/Instagram) Marketing API
- **Auth**: OAuth 2.0, System User tokens (never expire), requires App Review + Business Verification
- **SDK**: Official `facebook-nodejs-business-sdk` (npm)
- **Hierarchy**: Campaign → Ad Set → Ad (Creative)
- **Key Formats**: Feed image (1080x1080), Stories/Reels (1080x1920), Carousel (up to 10 cards)
- **Text**: Primary 125 chars (recommended), headline 40, description 30
- **Targeting**: Demographics, interests, Custom Audiences (CRM upload), Lookalikes, Advantage+ AI targeting
- **Bidding**: Lowest cost, cost cap, bid cap, ROAS target, CBO (auto-distribute)
- **Analytics**: Insights API, webhooks available for status changes
- **Crypto**: News/education/events OK without approval. Exchanges/DeFi/trading need written permission.
- **Typical CPM**: $13-17 | **CPC**: $0.30-$4.00

#### TikTok Marketing API
- **Auth**: OAuth 2.0, requires app review with demo video
- **SDK**: Official `tiktok-business-api-sdk` (GitHub, multi-language)
- **Hierarchy**: Campaign → Ad Group → Ad
- **Key Format**: Vertical video (1080x1920, 9:16), 9-15s recommended
- **Text**: ~100 chars display text, 20 chars brand name
- **Targeting**: Demographics, interests, behavior, Custom Audiences, Smart+ AI targeting
- **Bidding**: Cost cap, bid cap, lowest cost, ROAS target
- **Analytics**: Reporting API, Conversion API (server-side), no native webhooks
- **Crypto**: Educational content only in most regions. US/Canada beta for registered companies.
- **C2PA Requirement**: AI-generated content MUST include C2PA metadata (TikTok auto-detects)
- **Typical CPM**: $4-15 | **CPC**: $0.10-$1.00

#### Telegram Ads
- **Auth**: Web dashboard at ads.telegram.org, funded in TON
- **SDK**: None (no API for ad management)
- **Format**: Sponsored text messages in channels (1000+ subscribers), ~160 chars
- **Targeting**: Channel-specific, topic/interest, geographic. Cannot change after creation.
- **Automation**: Very limited — semi-manual via web dashboard
- **Workaround**: Use Telegram Bot API for organic channel posting (automated), supplement with paid ads manually
- **Crypto**: Most permissive platform, no approval needed
- **Typical CPM**: $0.50-$3 | **CPC**: $0.015+

### Multi-Account Support

Each platform supports multiple ad accounts for risk isolation, separate billing, and A/B testing at the account level.

**Database**: New `ad_platform_accounts` table stores credentials per account:

```sql
CREATE TABLE ad_platform_accounts (
  id BIGSERIAL PRIMARY KEY,
  platform VARCHAR(20) NOT NULL,         -- x, meta, tiktok, telegram
  account_name VARCHAR(100) NOT NULL,    -- "Blockster Articles", "Blockster Games", etc.
  platform_account_id VARCHAR(255),      -- Ad account ID on the platform
  status VARCHAR(20) DEFAULT 'active',   -- active, suspended, disabled
  credentials_ref VARCHAR(100),          -- Reference to env var prefix (never store secrets in DB)
  daily_budget_limit DECIMAL(10,2),      -- Per-account daily limit
  monthly_budget_limit DECIMAL(10,2),
  notes TEXT,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

**How it works**:
- Every API call to the Node.js service includes `account_id` — no hardcoded credentials
- `ad_campaigns` table has `account_id` foreign key to `ad_platform_accounts`
- Budget tracking is per-account within each platform
- AI can distribute campaigns across accounts (e.g., article ads on account A, game ads on account B)
- If one account gets flagged/suspended, others continue operating
- Admin configures accounts via `/admin/ads/accounts` page

**Platform capabilities**:
- **Meta**: Multiple ad accounts under one Business Manager (recommended: 1 for articles, 1 for commerce)
- **X**: Multiple ad accounts per organization
- **TikTok**: Multiple advertiser accounts under one Business Center
- **Telegram**: Multiple ad campaigns from same account (single account sufficient)

**Environment variables** use prefix pattern: `META_ACCOUNT_1_TOKEN`, `META_ACCOUNT_2_TOKEN`, etc.

### Node.js Ad Platform Microservice API

Internal API endpoints the Elixir backend calls:

```
POST   /campaigns                  Create campaign on platform (requires account_id)
GET    /campaigns/:id              Get campaign status + metrics
PUT    /campaigns/:id              Update campaign (budget, bid, targeting)
POST   /campaigns/:id/pause        Pause campaign
POST   /campaigns/:id/resume       Resume campaign
DELETE /campaigns/:id              Archive/delete campaign

POST   /creatives                  Upload creative to platform (admin or AI-generated)
POST   /creatives/upload           Upload admin-submitted image/video to storage
GET    /creatives/:id/performance  Get creative-level metrics

POST   /generate/copy              Generate ad copy variants (Claude API)
POST   /generate/image             Generate ad images (GPT Image 1 / Flux)
POST   /generate/video             Generate ad video (Runway API)
POST   /generate/overlay           Apply brand overlay to any image (AI or admin-submitted)

GET    /accounts/:platform         List ad accounts for a platform
GET    /accounts/:id/status        Check account health/status

GET    /analytics/:platform        Get platform-level analytics
GET    /analytics/campaign/:id     Get campaign analytics

POST   /audiences                  Create custom audience on platform
POST   /audiences/sync             Sync CRM data to platform
```

---

## 4. AI Agent Design

### Agent Loop (GenServer)

The AdsManager GenServer runs the core decision loop:

```elixir
defmodule BlocksterV2.AdsManager do
  use BlocksterV2.GlobalSingleton, name: __MODULE__

  # State
  defstruct [
    :enabled,           # boolean — master switch
    :autonomy_level,    # :manual | :semi_auto | :full_auto
    :last_check_at,     # DateTime
    :pending_approvals, # list of decisions awaiting admin approval
    :active_campaigns,  # map of campaign_id => status
  ]

  # Event handlers (PubSub subscriptions)
  def handle_info({:post_published, post}, state)
  def handle_info({:product_activated, product}, state)
  def handle_info({:admin_instruction, instruction}, state)
  def handle_info({:performance_update, data}, state)
  def handle_info({:budget_alert, alert}, state)
  def handle_info({:offer_redeemed, redemption}, state)
end
```

### Claude API Decision-Making

When the agent needs to make a decision, it calls Claude with:

1. **System prompt**: Agent role, current rules, budget constraints, platform configs
2. **Context**: Current campaigns, recent performance data, budget remaining, relevant post/product data
3. **Available tools**: Platform-specific actions it can take
4. **Question**: "A new post was published. Should we promote it? On which platforms? With what budget?"

Claude responds with structured tool calls:

```json
{
  "decisions": [
    {
      "action": "create_campaign",
      "platform": "x",
      "content_id": 42,
      "content_type": "post",
      "daily_budget": 25.00,
      "objective": "traffic",
      "targeting": {"interests": ["blockchain", "cryptocurrency"], "locations": ["US", "UK"]},
      "creatives": {"variants": 5, "format": "image_ad"},
      "reasoning": "High-quality blockchain analysis article with good engagement potential. X is the best platform for crypto content with low CPM."
    },
    {
      "action": "create_campaign",
      "platform": "meta",
      "content_id": 42,
      "content_type": "post",
      "daily_budget": 20.00,
      "objective": "traffic",
      "targeting": {"interests": ["technology", "finance"], "age_range": "18-44"},
      "creatives": {"variants": 3, "format": "carousel"},
      "reasoning": "Broader audience on Meta for general tech/finance interest. Carousel format to showcase multiple article highlights."
    }
  ]
}
```

### Autonomy Levels

| Level | Behavior | When to Use |
|-------|----------|-------------|
| **Manual** | AI proposes, admin must approve everything | Initial launch, first 2 weeks |
| **Semi-Auto** | AI auto-executes within limits, escalates large decisions | After initial tuning, ongoing |
| **Full-Auto** | AI manages everything, admin gets reports | After proven track record |

Escalation thresholds (configurable via SystemConfig):
- Single campaign budget > $100/day → requires admin approval
- Total daily spend increase > 30% → requires admin approval
- New platform activation → requires admin approval
- Budget increase > 50% on any campaign → requires admin approval

### Campaign Types

The agent manages four types of campaigns:

| Type | Trigger | Objective | Platforms | Creative Source |
|------|---------|-----------|-----------|----------------|
| **Article Promotion** | New post published | Traffic to article | X, Meta, TikTok | AI-generated images + copy |
| **Growth Campaign** | Scheduled / AI-initiated | New user signups | All platforms | AI-generated or admin-submitted |
| **Shop Promotion** | New product / admin-initiated | Purchases | Meta, TikTok, X | Real product images from ImageKit + AI copy |
| **Game Promotion** | Always-on / admin-initiated | Game plays + signups | TikTok, X, Meta | Real game screenshots/recordings + AI copy |

### Admin-Initiated Campaigns

Admin can create any campaign type manually with full control:

**Via `/admin/ads/campaigns/new`**:
1. Select campaign type (article, shop, game, custom)
2. Select target platforms and accounts
3. **Submit custom creatives** (optional — overrides AI generation):
   - Upload custom images (any format, auto-resized per platform)
   - Upload custom videos (for TikTok/Reels)
   - Write custom ad copy (headline, body, CTA) or let AI generate
   - Mix and match: admin image + AI copy, or admin copy + AI image
4. Set budget, targeting, schedule, and offer
5. Submit — campaign goes directly to platform (skips AI approval)

**Admin creative override on existing campaigns**:
- Admin can replace any creative on any active campaign (AI or admin-created)
- Admin-submitted creatives are flagged `admin_override: true` — AI will not modify or replace them
- Admin can also edit AI-generated copy before it goes live
- Admin creatives still go through A/B testing alongside AI variants (unless admin disables testing)

**Creative source priority**: Admin-submitted > AI-generated. If admin provides creatives, they are always used. AI fills in whatever the admin didn't provide.

### Campaign Lifecycle State Machine

```
DRAFT → PENDING_APPROVAL → ACTIVE → PAUSED → ACTIVE → COMPLETED → ARCHIVED
                                  ↘ FAILED
```

- **DRAFT**: AI created campaign, generating creatives
- **PENDING_APPROVAL**: Awaiting admin approval (if above autonomy threshold)
- **ACTIVE**: Running on platform, spending budget
- **PAUSED**: Temporarily stopped (by AI optimization or admin override)
- **COMPLETED**: Budget exhausted or schedule ended
- **FAILED**: Platform rejected the ad
- **ARCHIVED**: Historical data retained, campaign removed from active management

---

## 5. Creative Generation Pipeline

### Copy Generation (Claude Sonnet 4.6)

**System Prompt Template:**
```
You are Blockster's ad copywriter. You write compelling, authentic ad copy
for a web3 content platform.

Brand Voice:
- Confident but not hype-y (never "revolutionary", "game-changing")
- Community-focused, emphasizing real value
- Never use crypto jargon without context
- Tone: knowledgeable peer, not salesperson

Rules:
- Never make financial promises or price predictions
- Never say "guaranteed returns" or investment language
- BUX is an engagement reward, not an investment
- Include required disclaimers for crypto content
```

**Input per campaign**: Article title, excerpt, hub name, tags, target platform, campaign objective, offer details (if any)

**Output per variant**: Headline, body text, CTA text, hashtags (for X/TikTok), all platform-formatted

**Variants per campaign**: 5-8 copy variants with different angles:
- Curiosity gap ("The strategy nobody talks about...")
- Social proof ("Join 50K+ members reading...")
- Benefit-focused ("Earn BUX just for reading")
- Question hook ("What if you could earn crypto for reading?")
- Urgency ("Limited: 1000 free BUX for new members")

### Image Generation

**Primary**: GPT Image 1 (medium quality, $0.04/image) — best text rendering
**High-volume testing**: Flux Klein ($0.015/image) — rapid A/B variants
**Photorealistic**: Flux 2 Pro ($0.03/image) — product shots for shop ads

**Process:**
1. AI generates base image from article content/mood
2. Node.js service overlays brand elements using Sharp:
   - Blockster logo (top-left or bottom-right)
   - Headline text in Haas font
   - CTA button (bg-gray-900 rounded, white text)
   - Lime #CAFC00 accent elements (small dots, borders)
3. Export in platform-specific dimensions

**Platform Image Sizes:**
| Platform | Size | Ratio |
|----------|------|-------|
| X Feed | 1200x675 | 1.91:1 |
| Meta Feed | 1080x1080 | 1:1 |
| Meta Stories/Reels | 1080x1920 | 9:16 |
| TikTok | 1080x1920 | 9:16 |
| Telegram | 1280x720 | 16:9 |

### Video Generation (TikTok/Reels)

**Primary**: Runway Gen-4 Turbo (~$0.50/clip, 5-10s)
**Process:**
1. Generate 5-10 second clip from article theme/imagery
2. Overlay text + brand elements using ffmpeg
3. Add captions (required for sound-off viewing)
4. Include C2PA metadata for TikTok compliance

**Monthly video budget**: ~50 clips = ~$25/month

### A/B Testing Framework

**Algorithm**: Thompson Sampling (Multi-Armed Bandit)
- Each creative variant modeled as Beta(successes, failures)
- Sample from each distribution, show variant with highest sample
- Natural exploration→exploitation transition
- No fixed test duration needed

**Testing Protocol:**
1. Launch with 5-8 variants, equal budget split (exploration phase)
2. After 1,000 impressions per variant, begin MAB allocation
3. Declare winner at 95% confidence OR after 3-day minimum
4. Scale winner with remaining campaign budget
5. If frequency > 3.0 (ad fatigue), generate fresh creatives

### Creative Source Rules by Campaign Type

Not all campaigns use AI-generated visuals. The source depends on what's being promoted:

| Campaign Type | Images | Video | Copy | Rationale |
|--------------|--------|-------|------|-----------|
| **Article Promotion** | AI-generated (thematic/abstract) | AI-generated (Runway) | AI-generated (Claude) | No real-world asset to photograph |
| **Shop Promotion** | Real product photos from ImageKit | Real product video if available, else AI | AI-generated (Claude) | Products have real images — use them |
| **Game Promotion** | Real game screenshots/UI captures | Screen recordings of gameplay | AI-generated (Claude) | Game has a real UI — show it |
| **Growth/General** | AI-generated or admin-submitted | AI-generated or admin-submitted | AI-generated (Claude) | Depends on the campaign goal |
| **Any (admin override)** | Admin-submitted | Admin-submitted | Admin-written | Admin always takes priority |

#### Shop Ad Creative Flow

```
1. AI identifies a product to promote (new product, or scheduled shop campaign)
2. Fetch product data: title, body_html, handle, vendor, collection, tags
3. Fetch product images from ImageKit (already stored as product.images)
   - Use highest-resolution variant (w800_h800 or original)
   - Select hero image (first image) + 2-3 lifestyle/detail images for carousel
4. AI generates copy from product data:
   - Headline: Product name + key selling point
   - Body: Benefit-focused, includes price if applicable
   - CTA: "Shop Now" / "Get 20% Off" (if offer attached)
5. Node.js service applies brand overlay to product images:
   - Blockster logo
   - Price tag / discount badge if applicable
   - CTA button overlay
6. Campaign created with real product images + AI copy
```

#### Game Ad Creative Flow (BUX Booster / Plinko)

```
1. WeeklyOptimizationWorker checks game campaign performance
2. If no active game campaign OR current one fatigued (frequency > 3.0):
   → AI creates new game campaign

3. Creative assets (pre-stored, not AI-generated):
   - Screenshots of BUX Booster game UI (Plinko board, multipliers, winning moments)
   - Short screen recordings (5-15s) of actual gameplay (ball drops, big wins)
   - Store these in ImageKit under /ads/game/ directory
   - Refresh screenshots periodically when game UI changes

4. AI generates copy from game data:
   - Hook variants: "Can you beat the odds?", "Win up to 1000x your bet",
     "Free spins — no deposit needed", "Test your luck on Plinko"
   - Benefit: "Earn BUX just for playing"
   - CTA: "Play Now" / "Claim Free Spins"

5. Offer attached (typical):
   - 1-5 free spins for new signups
   - 500 BUX signup bonus
   - Requires phone verification before redemption

6. Node.js service composites:
   - Game screenshot + brand overlay + CTA button (for image ads)
   - Game recording + text overlay + captions (for video ads on TikTok/Reels)

7. Target audience:
   - TikTok: 18-34, gaming interests, crypto interests
   - X: Crypto/DeFi community, gaming, gambling interests
   - Meta: Casual gaming, crypto curious, play-to-earn interests

8. User clicks ad → /play?utm_source=tiktok&utm_campaign=game_promo_42&ref=GAME-SPIN-A3X9
9. User signs up → phone verification → free spins credited to account
10. Attribution tracked: ad_attributions links user to game campaign
```

**Pre-stored game assets** (admin uploads once, AI reuses):
- 5-10 game screenshots at various sizes (1080x1080, 1200x675, 1080x1920)
- 3-5 gameplay screen recordings (5-15s each, vertical + horizontal)
- Winning moment screenshots (big multiplier hits)
- These live in ImageKit `/ads/game/` and are referenced by the creative pipeline
- Admin can update these anytime via `/admin/ads/creatives` — upload new screenshots, retire old ones

### Compliance Layer

All generated copy passes through a compliance check before publishing:
- Claude call with crypto ad policy rules in system prompt
- Platform-specific checks (Meta disclaimers, TikTok C2PA, X restrictions)
- Flagged copy requires admin review before publishing
- Auto-reject: financial promises, guaranteed returns, investment language

---

## 6. Offer & Promotion System

### Offer Types

| Offer | Implementation | Value | Tracking |
|-------|---------------|-------|----------|
| **Free BUX** | Mint via BuxMinter with `:ad_promo` reward type | 50-1000 BUX | Per-code redemption |
| **Shop Discount** | Unique discount code per campaign | 10-30% off | Code → order attribution |
| **Free Game Spins** | Credit free spins to BUX Booster | 1-5 spins | Referral code tracking |
| **Hub Access** | Free premium hub subscription trial | 7-30 days | User → campaign attribution |

### BUX Giveaway Flow

```
1. AI creates campaign with BUX offer (e.g., "Sign up and get 500 free BUX")
2. Campaign generates unique referral link: blockster.com/?ref=CAMPAIGN_CODE&utm_campaign=X_POST_42
3. User clicks ad → lands on Blockster
4. User signs up (email + phone verification)
5. System detects campaign attribution via UTM params
6. BuxMinter.mint_bux(smart_wallet, 500, user_id, nil, :ad_promo) called
7. User receives BUX in wallet
8. Redemption logged to ad_offer_codes table
```

### Discount Code Format

`[PLATFORM]-[CAMPAIGN_TYPE]-[RANDOM4]`
Examples: `X-ARTICLE-A3X9`, `TIKTOK-GAME-B7K2`, `META-SHOP-C9M1`

### Anti-Abuse Measures

1. **Phone verification required** before any offer redemption (existing system)
2. **Device fingerprinting** (existing FingerprintJS integration)
3. **One redemption per phone number** per offer type
4. **Cooldown**: 1 offer redemption per 30 days per user
5. **Minimum engagement**: Must read 1 article before offer activates
6. **IP rate limiting**: Max 5 redemption attempts per IP per hour
7. **Budget caps**: Auto-pause offers when budget depleted

### Offer Budget (Separate from Ad Spend)

```
Monthly Offer Budget:
  bux_pool:       100,000 BUX
  discount_pool:  $500
  free_spins_pool: 1,000 spins

Per Offer:
  max_redemptions: configurable (default 500)
  daily_cap:       configurable (default 50/day)
  auto_pause:      true when budget depleted
```

Stored in SystemConfig, tracked in `ad_offers` + `ad_offer_codes` tables.

---

## 7. Budget Management

### Budget Hierarchy

**Starting budget: $50/day ($1,500/month)**. Scale up as ROAS proves out.

```
Global Monthly Budget: $1,500 (starting — scale based on ROAS)
├── Platform Allocations (AI-managed, admin-overridable):
│   ├── X (Twitter):        35% = $525/mo ($17.50/day)
│   ├── Meta (FB/IG):       35% = $525/mo ($17.50/day)
│   ├── TikTok:             20% = $300/mo ($10/day)
│   └── Telegram:           10% = $150/mo ($5/day)
├── Campaign Budgets (within platform allocations):
│   ├── Article promotion:  50% of platform budget
│   ├── Growth campaigns:   30% of platform budget
│   └── Shop/game promo:    20% of platform budget
└── Offer Budget (separate): 50K BUX + $200 discounts/mo
```

**Note**: TikTok enforces $20/day minimum per ad group — at $10/day we run 1 ad group at a time. Scale TikTok allocation first when budget increases, as it has the strictest minimums.

### Spend Pacing (PID Controller)

```
Every 4 hours:
  target_spend = daily_budget × (hours_elapsed / 24)
  actual_spend = sum of platform spend today
  error = target_spend - actual_spend

  If error > 0 (underspending):
    → Increase bids by 5-10%
  If error < 0 (overspending):
    → Decrease bids by 5-10%

  Constraint: Never exceed daily budget
```

### Dynamic Reallocation (Weekly)

```
Every Monday:
  1. Calculate ROAS per platform over past 7 days
  2. Rank platforms by ROAS
  3. If top platform ROAS > 2x bottom platform:
     → Shift 10% of bottom's budget to top
  4. If any platform ROAS < 0.5x target:
     → Reduce to minimum budget, redistribute
  5. Reserve 15% as exploration budget for underperforming platforms
  6. Enforce minimum $5/day per active platform
```

### Spending Limits (Tiered Safety)

| Level | Scope | Default Limit (starting) | Action on Breach |
|-------|-------|--------------------------|-----------------|
| L1 | Per Campaign | $20/day, $200 lifetime | Auto-pause campaign |
| L2 | Per Platform | $25/day, $750/month | Throttle new campaigns |
| L3 | Global | $50/day, $1,500/month | Pause all, alert admin |
| L4 | Per Decision | >50% budget increase | Require admin approval |
| Hard Ceiling | Absolute | $3,000/month | Cannot be overridden |

All configurable via SystemConfig. Hard ceiling requires code change. Increase limits as ROAS proves out.

---

## 8. Analytics & Attribution

### UTM Tracking Implementation

Every ad link includes UTM parameters:

```
https://blockster.com/article-slug?
  utm_source=x|meta|tiktok|telegram
  &utm_medium=paid
  &utm_campaign=campaign_id
  &utm_content=creative_id
  &ref=CAMPAIGN_CODE
```

**New JS Hook** (`assets/js/hooks/utm_tracker.js`):
- Capture UTM params from URL on page load
- Store in `sessionStorage` for persistence across pages
- Send to server via `pushEvent` on significant actions (signup, purchase)
- Server logs to `user_events` table for attribution

### KPI Framework

**Primary KPIs:**
| KPI | Definition | Target |
|-----|-----------|--------|
| CAC (Cost per Acquisition) | Total ad spend / new signups | < $5 |
| ROAS | Revenue from ad users / ad spend | > 2.0x |
| LTV:CAC | 90-day user value / acquisition cost | > 3:1 |
| Active User Rate | % of ad-acquired users active after 7 days | > 30% |

**Secondary KPIs:**
| KPI | Definition | Tracked Per |
|-----|-----------|-------------|
| Impressions | Total ad views | Campaign, Platform |
| Clicks | Total ad clicks | Campaign, Creative |
| CTR | Clicks / Impressions | Campaign, Creative |
| CPC | Cost per click | Campaign, Platform |
| CPM | Cost per 1000 impressions | Campaign, Platform |
| Conversion Rate | Signups / Clicks | Campaign, Platform |
| Offer Redemption Rate | Redeemed / Offered | Offer, Campaign |
| Engagement Score | Avg engagement of ad-acquired users | Cohort |

### Attribution Model

**Hybrid approach:**
1. **UTM tracking** — Web2 touchpoint tracking (ad click → page visit → signup)
2. **Referral codes** — Offer-specific attribution (which ad → which code → which user)
3. **First-touch attribution** — 100% credit to the first ad touchpoint
4. **Conversion window** — 7 days (click) / 1 day (view)

### Automated Reports

| Report | Frequency | Delivery | Content |
|--------|-----------|----------|---------|
| Daily Digest | 8am UTC | Admin notification + email | Spend summary, top/bottom campaigns, anomalies |
| Weekly Review | Monday 9am | Admin email | Full performance, AI decisions, recommendations |
| Monthly Analysis | 1st of month | Admin email | Cohort analysis, LTV tracking, budget vs actual |
| Real-time Dashboard | Always | Admin LiveView | Live spend, active campaigns, recent decisions |

---

## 9. Admin Dashboard & Interaction

### Admin Routes

```
/admin/ads                     → Dashboard (overview)
/admin/ads/campaigns           → Campaign list (filter by status, platform, type)
/admin/ads/campaigns/new       → Create campaign manually (admin submits creatives + config)
/admin/ads/campaigns/:id       → Campaign detail (edit creatives, override AI, view performance)
/admin/ads/campaigns/:id/edit  → Edit campaign (swap creatives, change budget/targeting)
/admin/ads/creatives           → Creative library (upload images, videos, manage game screenshots)
/admin/ads/accounts            → Platform account management (multi-account config)
/admin/ads/budget              → Budget management (per-account, per-platform)
/admin/ads/offers              → Offer management
/admin/ads/analytics           → Analytics deep dive
/admin/ads/agent               → AI agent control panel
/admin/ads/agent/log           → Decision audit log
/admin/ads/agent/instructions  → Instruction history
```

### Dashboard Layout

```
┌─────────────────────────────────────────────────────────┐
│  AI Ads Manager                              [Pause AI] │
├──────────────┬──────────────┬──────────────┬────────────┤
│  Daily Spend │  Active      │  ROAS        │  New Users │
│  $127 / $500 │  Campaigns:12│  2.3x        │  Today: 47 │
├──────────────┴──────────────┴──────────────┴────────────┤
│                                                         │
│  Platform Performance          Budget Allocation        │
│  ┌──────┬───────┬──────┐      ┌──────────────────────┐ │
│  │ X    │ $45   │ 3.1x │      │ ████████ X: 30%      │ │
│  │ Meta │ $52   │ 1.8x │      │ █████████ Meta: 35%  │ │
│  │ TikT │ $30   │ 2.7x │      │ ███████ TikTok: 25%  │ │
│  └──────┴───────┴──────┘      │ ███ Telegram: 10%    │ │
│                                └──────────────────────┘ │
├─────────────────────────────────────────────────────────┤
│  Talk to AI Manager                                     │
│  ┌─────────────────────────────────────────────────────┐│
│  │ "Focus more on TikTok this week"              [Send]││
│  └─────────────────────────────────────────────────────┘│
│                                                         │
│  Recent AI Decisions                                    │
│  • Created X campaign for "DeFi Lending Guide" — $25/d  │
│  • Paused Meta campaign #47 — ROAS below threshold     │
│  • Increased TikTok budget 20% — strong performance    │
│  • Generated 8 creative variants for "NFT Art" article  │
├─────────────────────────────────────────────────────────┤
│  Pending Approvals                                      │
│  • New campaign: "BUX Booster Promo" — $150/day         │
│    [Approve] [Reject] [Modify]                          │
└─────────────────────────────────────────────────────────┘
```

### Natural Language Instructions

Admin types instructions in plain text. Claude interprets and executes:

| Admin Says | AI Interprets | Action |
|-----------|---------------|--------|
| "Focus more on TikTok" | Increase TikTok allocation +30% | Rebalance budgets |
| "Reduce total budget by 20%" | Scale all platform budgets down 20% | Adjust all daily limits |
| "Promote the new game more" | Create game-focused campaigns | Launch on active platforms |
| "Pause everything on Facebook" | Pause all Meta campaigns | Bulk pause |
| "Only promote articles from Blockster Hub" | Filter to hub_id = blockster | Update campaign rules |
| "Give away 2000 BUX for signups" | Create signup offer with 2000 BUX | Create offer + campaigns |
| "What's performing best?" | Generate performance summary | Return analysis (no action) |

All instructions logged with: original text, parsed intent, actions taken, timestamp.

---

## 10. Safety Guardrails

### Master Controls

| Control | Location | Default |
|---------|----------|---------|
| `ai_ads_enabled` | SystemConfig | `false` (must enable explicitly) |
| `autonomy_level` | SystemConfig | `"manual"` |
| `daily_budget_limit` | SystemConfig | `50` (USD — starting) |
| `monthly_budget_limit` | SystemConfig | `1500` (USD — starting) |
| `approval_threshold` | SystemConfig | `25` (USD per campaign/day) |
| `hard_ceiling_monthly` | Application config | `3000` (USD, code-level) |

### Anomaly Detection

Checked every hour by performance worker:

```
ALERT if:
  - Hourly spend rate > 2x normal → auto-pause, notify admin
  - CPC spikes > 3x 7-day average → reduce bids, notify admin
  - CTR drops > 50% vs yesterday → check creative, notify admin
  - Zero conversions after $50 spend → pause campaign, notify admin
  - Daily budget 80% exhausted before 6pm → throttle pacing
  - Any platform API errors > 5 in 1 hour → pause platform, notify admin
```

### Kill Switches

| Switch | Trigger | Effect | Recovery |
|--------|---------|--------|----------|
| **Soft** | Admin click or anomaly | Pause AI campaigns, stop new creation | Admin resumes |
| **Hard** | Admin click or 2x daily limit | Pause ALL campaigns, revoke API access | Admin + code review |
| **Emergency** | Total spend > 2x daily limit | Immediate halt, all platforms | Admin intervention required |

### Audit Trail

Every AI decision logged to `ai_manager_logs`:
- `decision_type`: create_campaign, pause_campaign, adjust_budget, adjust_bid, create_offer, generate_creative, rebalance_budget
- `input_context`: JSON snapshot of data the AI considered
- `reasoning`: Claude's chain-of-thought summary
- `action_taken`: Structured description of what was executed
- `outcome`: success/failure + details
- `budget_impact`: Dollar amount affected
- `campaign_id`, `platform`, `admin_instruction_id`: Foreign keys for tracing

---

## 11. Database Schema

### New Tables

```sql
-- ============================================================
-- CAMPAIGN MANAGEMENT
-- ============================================================

-- ============================================================
-- PLATFORM ACCOUNTS (multi-account support)
-- ============================================================

CREATE TABLE ad_platform_accounts (
  id BIGSERIAL PRIMARY KEY,
  platform VARCHAR(20) NOT NULL,           -- x, meta, tiktok, telegram
  account_name VARCHAR(100) NOT NULL,      -- "Blockster Articles", "Blockster Games"
  platform_account_id VARCHAR(255),        -- Ad account ID on the platform
  status VARCHAR(20) DEFAULT 'active',     -- active, suspended, disabled
  credentials_ref VARCHAR(100),            -- Env var prefix (e.g., "META_ACCOUNT_1")
  daily_budget_limit DECIMAL(10,2),
  monthly_budget_limit DECIMAL(10,2),
  notes TEXT,
  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ad_platform_accounts_platform ON ad_platform_accounts(platform, status);

CREATE TABLE ad_campaigns (
  id BIGSERIAL PRIMARY KEY,
  account_id BIGINT REFERENCES ad_platform_accounts(id), -- which ad account to use
  platform VARCHAR(20) NOT NULL,           -- x, meta, tiktok, telegram
  platform_campaign_id VARCHAR(255),       -- ID on the ad platform
  name VARCHAR(255) NOT NULL,
  status VARCHAR(30) NOT NULL DEFAULT 'draft',  -- draft, pending_approval, active, paused, completed, failed, archived
  objective VARCHAR(50) NOT NULL,          -- traffic, signups, purchases, engagement

  -- What we're promoting
  content_type VARCHAR(30),                -- post, product, game, general
  content_id BIGINT,                       -- post_id, product_id, or null

  -- Budget
  budget_daily DECIMAL(10,2),
  budget_lifetime DECIMAL(10,2),
  spend_total DECIMAL(10,2) DEFAULT 0,

  -- Targeting
  targeting_config JSONB DEFAULT '{}',     -- platform-specific targeting params

  -- Who created it and how
  created_by VARCHAR(20) DEFAULT 'ai',     -- 'ai' or 'admin'
  created_by_user_id BIGINT REFERENCES users(id), -- if created by admin
  ai_confidence_score DECIMAL(3,2),        -- 0.00-1.00 (null if admin-created)
  admin_override BOOLEAN DEFAULT false,    -- if true, AI won't modify
  admin_notes TEXT,

  -- Scheduling
  scheduled_start TIMESTAMPTZ,
  scheduled_end TIMESTAMPTZ,

  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ad_campaigns_status ON ad_campaigns(status);
CREATE INDEX idx_ad_campaigns_platform ON ad_campaigns(platform);
CREATE INDEX idx_ad_campaigns_content ON ad_campaigns(content_type, content_id);

-- ============================================================
-- CREATIVES
-- ============================================================

CREATE TABLE ad_creatives (
  id BIGSERIAL PRIMARY KEY,
  campaign_id BIGINT REFERENCES ad_campaigns(id),
  platform VARCHAR(20) NOT NULL,
  platform_creative_id VARCHAR(255),

  -- Creative content
  type VARCHAR(20) NOT NULL,               -- image, video, carousel, text
  headline VARCHAR(500),
  body TEXT,
  cta_text VARCHAR(100),
  image_url VARCHAR(500),
  video_url VARCHAR(500),
  hashtags TEXT[],

  -- Source tracking
  source VARCHAR(20) NOT NULL DEFAULT 'ai', -- 'ai', 'admin', 'product', 'game_asset'
  source_details JSONB,                     -- e.g., {"uploaded_by": user_id} or {"product_image_id": 42}
  admin_override BOOLEAN DEFAULT false,     -- if true, AI will not replace/modify this creative

  -- Performance
  status VARCHAR(20) DEFAULT 'draft',      -- draft, active, paused, winner, loser
  impressions BIGINT DEFAULT 0,
  clicks BIGINT DEFAULT 0,
  conversions INTEGER DEFAULT 0,
  performance_score DECIMAL(5,2),          -- Thompson sampling score

  -- A/B testing
  variant_group VARCHAR(50),               -- group identifier for A/B test
  is_winner BOOLEAN DEFAULT false,

  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ad_creatives_campaign ON ad_creatives(campaign_id);

-- ============================================================
-- BUDGET MANAGEMENT
-- ============================================================

CREATE TABLE ad_budgets (
  id BIGSERIAL PRIMARY KEY,
  platform VARCHAR(20),                    -- null = global
  period_type VARCHAR(10) NOT NULL,        -- daily, weekly, monthly
  period_start DATE NOT NULL,
  period_end DATE NOT NULL,

  allocated_amount DECIMAL(10,2) NOT NULL,
  spent_amount DECIMAL(10,2) DEFAULT 0,
  remaining_amount DECIMAL(10,2) GENERATED ALWAYS AS (allocated_amount - spent_amount) STORED,

  status VARCHAR(20) DEFAULT 'active',     -- active, exhausted, closed

  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ad_budgets_platform_period ON ad_budgets(platform, period_start);

CREATE TABLE ad_budget_adjustments (
  id BIGSERIAL PRIMARY KEY,
  budget_id BIGINT REFERENCES ad_budgets(id),
  campaign_id BIGINT REFERENCES ad_campaigns(id),

  old_amount DECIMAL(10,2),
  new_amount DECIMAL(10,2),
  reason TEXT NOT NULL,
  decided_by VARCHAR(50) NOT NULL,         -- 'ai' or admin user_id

  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- OFFERS & PROMOTIONS
-- ============================================================

CREATE TABLE ad_offers (
  id BIGSERIAL PRIMARY KEY,
  campaign_id BIGINT REFERENCES ad_campaigns(id),

  offer_type VARCHAR(30) NOT NULL,         -- bux_giveaway, shop_discount, free_spins, hub_trial
  value VARCHAR(100) NOT NULL,             -- "500 BUX", "20%", "3 spins", "7 days"
  code_prefix VARCHAR(20),                 -- e.g., "X-ARTICLE"

  max_redemptions INTEGER,
  current_redemptions INTEGER DEFAULT 0,
  daily_cap INTEGER,

  budget_allocated DECIMAL(10,2),          -- USD equivalent
  budget_spent DECIMAL(10,2) DEFAULT 0,

  requires_phone_verification BOOLEAN DEFAULT true,
  requires_min_engagement BOOLEAN DEFAULT true,
  cooldown_days INTEGER DEFAULT 30,

  expires_at TIMESTAMPTZ,
  status VARCHAR(20) DEFAULT 'active',     -- active, paused, exhausted, expired

  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE ad_offer_codes (
  id BIGSERIAL PRIMARY KEY,
  offer_id BIGINT REFERENCES ad_offers(id),

  code VARCHAR(30) NOT NULL UNIQUE,
  user_id BIGINT REFERENCES users(id),

  status VARCHAR(20) DEFAULT 'available',  -- available, reserved, redeemed, expired
  redeemed_at TIMESTAMPTZ,

  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ad_offer_codes_code ON ad_offer_codes(code);
CREATE INDEX idx_ad_offer_codes_user ON ad_offer_codes(user_id);

-- ============================================================
-- PERFORMANCE ANALYTICS
-- ============================================================

CREATE TABLE ad_performance_snapshots (
  id BIGSERIAL PRIMARY KEY,
  campaign_id BIGINT REFERENCES ad_campaigns(id),
  creative_id BIGINT REFERENCES ad_creatives(id),
  platform VARCHAR(20) NOT NULL,

  snapshot_at TIMESTAMPTZ NOT NULL,

  impressions BIGINT DEFAULT 0,
  clicks BIGINT DEFAULT 0,
  conversions INTEGER DEFAULT 0,
  spend DECIMAL(10,2) DEFAULT 0,

  -- Computed metrics
  ctr DECIMAL(8,4),                        -- click-through rate
  cpc DECIMAL(8,4),                        -- cost per click
  cpm DECIMAL(8,4),                        -- cost per 1000 impressions
  roas DECIMAL(8,4),                       -- return on ad spend

  -- Platform-specific
  platform_metrics JSONB DEFAULT '{}',     -- video views, engagement rate, etc.

  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ad_performance_campaign_time
  ON ad_performance_snapshots(campaign_id, snapshot_at DESC);
CREATE INDEX idx_ad_performance_time USING BRIN
  ON ad_performance_snapshots(snapshot_at);

-- ============================================================
-- AI AGENT LOGGING
-- ============================================================

CREATE TABLE ai_ads_decisions (
  id BIGSERIAL PRIMARY KEY,

  decision_type VARCHAR(50) NOT NULL,      -- create_campaign, pause_campaign, adjust_budget, etc.
  input_context JSONB NOT NULL,            -- what data the AI considered
  reasoning TEXT NOT NULL,                 -- Claude's chain-of-thought summary
  action_taken JSONB NOT NULL,             -- structured action description
  outcome VARCHAR(20) NOT NULL,            -- success, failure, pending_approval
  outcome_details JSONB,                   -- error messages, platform responses
  budget_impact DECIMAL(10,2),             -- dollar amount affected

  campaign_id BIGINT REFERENCES ad_campaigns(id),
  platform VARCHAR(20),
  admin_instruction_id BIGINT,             -- if triggered by admin instruction

  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ai_ads_decisions_time USING BRIN ON ai_ads_decisions(inserted_at);
CREATE INDEX idx_ai_ads_decisions_campaign ON ai_ads_decisions(campaign_id);

-- ============================================================
-- ADMIN INSTRUCTIONS
-- ============================================================

CREATE TABLE ai_ads_instructions (
  id BIGSERIAL PRIMARY KEY,
  admin_user_id BIGINT REFERENCES users(id) NOT NULL,

  instruction_text TEXT NOT NULL,
  parsed_intent JSONB,                     -- Claude's interpretation
  actions_taken JSONB,                     -- list of actions executed

  status VARCHAR(20) DEFAULT 'pending',    -- pending, processing, completed, failed

  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ
);

-- ============================================================
-- UTM / ATTRIBUTION TRACKING
-- ============================================================

CREATE TABLE ad_attributions (
  id BIGSERIAL PRIMARY KEY,
  user_id BIGINT REFERENCES users(id),

  utm_source VARCHAR(50),
  utm_medium VARCHAR(50),
  utm_campaign VARCHAR(100),
  utm_content VARCHAR(100),
  referral_code VARCHAR(50),

  campaign_id BIGINT REFERENCES ad_campaigns(id),
  creative_id BIGINT REFERENCES ad_creatives(id),
  offer_id BIGINT REFERENCES ad_offers(id),

  -- Conversion events
  first_visit_at TIMESTAMPTZ,
  signup_at TIMESTAMPTZ,
  first_engagement_at TIMESTAMPTZ,         -- first article read, game played, etc.
  first_purchase_at TIMESTAMPTZ,

  inserted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ad_attributions_user ON ad_attributions(user_id);
CREATE INDEX idx_ad_attributions_campaign ON ad_attributions(campaign_id);
```

### Existing Tables Modified

```sql
-- Add :ad_promo to reward_type validation in BuxMinter
-- (code change only, no migration needed)

-- Add UTM fields to user_events (already JSONB metadata, no migration needed)
```

---

## 12. Codebase Integration Points

### Hook: Post Publishing (blog.ex)

```elixir
# In Blog.publish_post/1, after success case:
def publish_post(%Post{} = post) do
  result = post |> Post.publish() |> Repo.update()
  case result do
    {:ok, published_post} ->
      if published_post.hub_id do
        Task.start(fn -> notify_hub_followers_of_new_post(published_post) end)
      end
      # NEW: Trigger ad evaluation
      Phoenix.PubSub.broadcast(BlocksterV2.PubSub, "post:published", {:post_published, published_post})
      {:ok, published_post}
    error -> error
  end
end
```

### Hook: BUX Minting (bux_minter.ex)

Add `:ad_promo` to the reward_type guard clause:
```elixir
def mint_bux(wallet_address, amount, user_id, post_id, reward_type, _token \\ "BUX", _hub_id \\ nil)
    when reward_type in [:read, :x_share, :video_watch, :signup, :phone_verified,
                          :shop_affiliate, :shop_refund, :ad_promo]
```

### Hook: User Registration (accounts.ex)

Add UTM attribution tracking after user creation:
```elixir
# In create_user_from_email/1 after successful creation:
UserEvents.track(user.id, "signup", %{
  source: attrs[:utm_source],
  utm_campaign: attrs[:utm_campaign],
  referral_code: attrs[:referral_code]
})
```

### New Oban Queues (config.exs)

```elixir
queues: [
  default: 10,
  email_transactional: 5,
  email_marketing: 3,
  # ... existing queues ...
  ads_management: 3,    # NEW: campaign CRUD, budget adjustments
  ads_creative: 2,      # NEW: creative generation (CPU-intensive)
  ads_analytics: 2,     # NEW: performance data pulling
]
```

### New Oban Cron Jobs

```elixir
crontab: [
  # ... existing cron jobs ...
  {"0 * * * *", BlocksterV2.Workers.Ads.PerformanceCheckWorker},      # Every hour
  {"0 */4 * * *", BlocksterV2.Workers.Ads.BudgetPacingWorker},        # Every 4 hours
  {"0 */6 * * *", BlocksterV2.Workers.Ads.CreativeFatigueWorker},     # Every 6 hours
  {"0 */2 * * *", BlocksterV2.Workers.Ads.OfferBudgetCheckWorker},    # Every 2 hours
  {"0 0 * * *", BlocksterV2.Workers.Ads.DailyBudgetResetWorker},      # Midnight UTC
  {"0 8 * * *", BlocksterV2.Workers.Ads.DailyReportWorker},           # 8am UTC
  {"0 9 * * 1", BlocksterV2.Workers.Ads.WeeklyOptimizationWorker},    # Monday 9am
  {"0 17 * * 5", BlocksterV2.Workers.Ads.WeeklyReportWorker},         # Friday 5pm
]
```

### Feature Flag (config/runtime.exs)

```elixir
ai_ads_manager: [
  enabled: System.get_env("AI_ADS_MANAGER_ENABLED", "false") == "true",
  ads_service_url: System.get_env("ADS_SERVICE_URL", "https://ads-manager.fly.dev"),
  ads_service_secret: System.get_env("ADS_SERVICE_SECRET"),
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),  # already exists
]
```

### Supervision Tree (application.ex)

```elixir
ai_ads_children =
  if Application.get_env(:blockster_v2, :ai_ads_manager, [])[:enabled] do
    [{BlocksterV2.AdsManager, []}]
  else
    []
  end
```

### Router (router.ex)

```elixir
# Inside :admin live_session
scope "/admin/ads", BlocksterV2Web.AdsAdminLive do
  live "/", Dashboard
  live "/campaigns", CampaignIndex
  live "/campaigns/new", CampaignNew
  live "/campaigns/:id", CampaignShow
  live "/campaigns/:id/edit", CampaignEdit
  live "/creatives", CreativeIndex
  live "/accounts", AccountManager
  live "/budget", BudgetManager
  live "/offers", OfferManager
  live "/analytics", AnalyticsDashboard
  live "/agent", AgentControl
  live "/agent/log", DecisionLog
  live "/agent/instructions", InstructionHistory
end

# Webhook routes (public_api pipeline)
scope "/api/webhooks", BlocksterV2Web do
  pipe_through :public_api
  post "/meta/ads", MetaAdsWebhookController, :handle
  post "/tiktok/ads", TikTokAdsWebhookController, :handle
end
```

---

## 13. Implementation Phases

### Phase 1: Foundation (2-3 weeks)
**Goal**: Core infrastructure, single platform (X), manual approval mode

- [ ] Database migrations (all tables from Schema section)
- [ ] `BlocksterV2.AdsManager` GenServer with GlobalSingleton
- [ ] `BlocksterV2.AdsManager.CampaignManager` — campaign CRUD + state machine
- [ ] `BlocksterV2.AdsManager.BudgetManager` — basic budget tracking + limits
- [ ] `BlocksterV2.AdsManager.DecisionLogger` — audit trail logging
- [ ] `BlocksterV2.AdsManager.SafetyGuards` — spending limits + kill switch
- [ ] Node.js ad platform microservice — scaffold + X REST API integration
- [ ] Creative generation: Claude API copy generation (via Node.js service)
- [ ] PubSub hook in `publish_post/1`
- [ ] Basic admin dashboard LiveView (`/admin/ads`)
- [ ] Admin campaign creation page (`/admin/ads/campaigns/new`) with creative upload
- [ ] Platform account management page (`/admin/ads/accounts`)
- [ ] Feature flag + config setup
- [ ] Oban workers: PerformanceCheck, DailyBudgetReset
- [ ] Tests for all modules

**Deliverable**: AI creates X campaigns for new posts, admin can create campaigns manually with custom creatives, admin approves AI campaigns, basic analytics visible.

### Phase 2: Creative Pipeline + Meta (2 weeks)
**Goal**: Image generation, Meta platform, A/B testing

- [ ] GPT Image 1 integration in Node.js service
- [ ] Brand overlay system (Sharp — logo, headline, CTA overlay)
- [ ] Platform-specific image sizing (X: 1200x675, Meta: 1080x1080, Stories: 1080x1920)
- [ ] Meta Marketing API integration (Node.js, official SDK)
- [ ] Meta App Review + Business Verification (start early — takes days/weeks)
- [ ] Creative A/B testing: Thompson Sampling implementation
- [ ] Creative variant management UI in admin
- [ ] Oban workers: CreativeFatigueCheck, BudgetPacing

**Deliverable**: AI generates copy + images, runs A/B tests, manages campaigns on X + Meta.

### Phase 3: Offers + Attribution (2 weeks)
**Goal**: BUX giveaways, discount codes, UTM tracking, conversion attribution

- [ ] Offer system: `AdsManager.OfferManager` module
- [ ] BUX giveaway flow: `:ad_promo` reward type in BuxMinter
- [ ] Discount code generation + redemption tracking
- [ ] Free game spins integration with BUX Booster
- [ ] UTM tracker JS hook (`assets/js/hooks/utm_tracker.js`)
- [ ] Attribution table + tracking in signup/purchase flows
- [ ] Anti-abuse: phone verification gate, fingerprint check, cooldowns
- [ ] Oban workers: OfferBudgetCheck
- [ ] Offer management admin page

**Deliverable**: Ads can include offers, new user signups attributed to campaigns, offer redemption tracked.

### Phase 4: TikTok + Video (2 weeks)
**Goal**: TikTok platform, video creative generation

- [ ] TikTok Marketing API integration (Node.js, official SDK)
- [ ] TikTok app review + demo video submission
- [ ] Runway Gen-4 Turbo video generation integration
- [ ] ffmpeg video processing (overlay, captions)
- [ ] C2PA metadata for TikTok compliance
- [ ] Video creative management in admin UI

**Deliverable**: AI creates video ads for TikTok, manages campaigns across 3 platforms.

### Phase 5: Telegram + Semi-Auto (1-2 weeks)
**Goal**: Telegram integration, increase AI autonomy

- [ ] Telegram Bot API integration for organic channel posting
- [ ] Telegram Ads Platform workflow documentation (manual/semi-manual)
- [ ] Autonomy level controls in admin
- [ ] Semi-auto mode: AI auto-executes within limits, escalates large decisions
- [ ] Natural language admin instruction processing
- [ ] Instruction history UI

**Deliverable**: All 4 platforms active, AI operates in semi-auto mode with admin oversight.

### Phase 6: Advanced Optimization + Reporting (2 weeks)
**Goal**: Cross-platform optimization, automated reports, analytics

- [ ] Dynamic budget reallocation across platforms
- [ ] Cross-platform ROAS comparison + normalization
- [ ] Time-of-day / day-of-week optimization
- [ ] Automated daily/weekly reports (email + in-app)
- [ ] Analytics deep-dive dashboard
- [ ] Cohort analysis for ad-acquired users
- [ ] Anomaly detection refinement
- [ ] Oban workers: WeeklyOptimization, DailyReport, WeeklyReport

**Deliverable**: Fully optimizing AI ads system with comprehensive analytics and reporting.

### Phase 7: Full Autonomy + Polish (1-2 weeks)
**Goal**: Production hardening, full-auto mode, monitoring

- [ ] Full-auto mode (AI manages everything, admin gets reports)
- [ ] Enhanced anomaly detection with pattern learning
- [ ] Performance feedback loop (winning creative patterns inform future generation)
- [ ] Load testing + monitoring setup
- [ ] Documentation for admin usage
- [ ] Edge case handling + error recovery

**Deliverable**: Production-ready autonomous AI ads system.

### Total Estimated Timeline: 12-16 weeks

---

## 14. Cost Estimates

### Monthly Operating Costs (Starting at $50/day)

| Category | Item | Monthly Cost |
|----------|------|-------------|
| **AI APIs** | Claude API (decisions + copy) | $30-60 |
| | GPT Image 1 (image generation) | $20-40 |
| | Runway (video generation) | $10-25 |
| **Infrastructure** | Node.js microservice (Fly.io) | $15-30 |
| | Additional database storage | $5-10 |
| **Ad Spend** | X campaigns | $525 |
| | Meta campaigns (FB + IG) | $525 |
| | TikTok campaigns | $300 |
| | Telegram campaigns | $150 |
| **Offers** | BUX giveaways (minting gas) | ~$2 |
| | Shop discounts (revenue reduction) | $100-200 |
| **Total** | | **~$1,700-$1,900/month** |

### Cost Breakdown

- **AI/Infrastructure**: ~$80-165/month (~5% of ad spend)
- **Creative Generation**: ~$60-125/month (~4% of ad spend)
- **Ad Spend**: $1,500/month ($50/day — main cost, scale based on ROAS)
- **Offers**: ~$100-200/month (drives conversions)

### ROI Target

At $1,500/month ad spend with 2.0x ROAS target:
- Expected new users: 300-750 (at $2-5 CAC)
- Expected revenue contribution: $3,000+ from ad-acquired user LTV
- Break-even at 1.0x ROAS = $1,500 revenue from acquired users
- **Scale plan**: Once ROAS > 2.0x consistently for 2 weeks, increase daily budget by 50%

---

## 15. File Structure

### Elixir Application

```
lib/blockster_v2/ads_manager/
├── ads_manager.ex                    # Main GenServer (GlobalSingleton)
├── campaign_manager.ex               # Campaign CRUD + state machine
├── budget_manager.ex                 # Budget allocation, pacing, limits
├── creative_pipeline.ex              # Interface to Node.js creative service
├── offer_manager.ex                  # Offers, codes, redemption tracking
├── analytics_engine.ex               # KPI calculation, trend detection
├── decision_logger.ex                # Audit trail for all AI decisions
├── safety_guards.ex                  # Spending limits, anomaly detection, kill switches
├── admin_processor.ex                # Natural language instruction processing
├── platform_client.ex                # HTTP client for Node.js ad service
├── config.ex                         # Centralized config access
│
├── schemas/
│   ├── platform_account.ex           # Ecto schema — multi-account support
│   ├── campaign.ex                   # Ecto schema
│   ├── creative.ex                   # includes source tracking (ai/admin/product/game_asset)
│   ├── budget.ex
│   ├── budget_adjustment.ex
│   ├── offer.ex
│   ├── offer_code.ex
│   ├── performance_snapshot.ex
│   ├── decision.ex
│   ├── instruction.ex
│   └── attribution.ex
│
└── workers/
    ├── campaign_launch_worker.ex     # Async campaign creation on platforms
    ├── performance_check_worker.ex   # Hourly performance data pull
    ├── budget_pacing_worker.ex       # 4-hourly budget pacing
    ├── creative_fatigue_worker.ex    # 6-hourly creative refresh check
    ├── offer_budget_check_worker.ex  # 2-hourly offer budget check
    ├── daily_budget_reset_worker.ex  # Daily budget reset + allocation
    ├── weekly_optimization_worker.ex # Weekly cross-platform optimization
    ├── daily_report_worker.ex        # Daily performance report
    └── weekly_report_worker.ex       # Weekly comprehensive report
```

### Admin LiveView

```
lib/blockster_v2_web/live/ads_admin_live/
├── dashboard.ex                      # Main dashboard overview
├── dashboard.html.heex
├── campaign_index.ex                 # Campaign list with filters
├── campaign_index.html.heex
├── campaign_new.ex                   # Admin creates campaign manually (upload creatives, set config)
├── campaign_new.html.heex
├── campaign_show.ex                  # Campaign detail + creatives
├── campaign_show.html.heex
├── campaign_edit.ex                  # Edit campaign (swap creatives, change budget/targeting)
├── campaign_edit.html.heex
├── creative_index.ex                 # Creative library (upload images/videos, manage game assets)
├── creative_index.html.heex
├── account_manager.ex                # Platform account management (multi-account)
├── account_manager.html.heex
├── budget_manager.ex                 # Budget allocation UI (per-account, per-platform)
├── budget_manager.html.heex
├── offer_manager.ex                  # Offer management
├── offer_manager.html.heex
├── analytics_dashboard.ex            # Analytics deep dive
├── analytics_dashboard.html.heex
├── agent_control.ex                  # AI agent control panel
├── agent_control.html.heex
├── decision_log.ex                   # Decision audit log
├── decision_log.html.heex
├── instruction_history.ex            # Admin instruction log
└── instruction_history.html.heex
```

### Node.js Microservice

```
ads-manager-service/
├── package.json
├── server.js                         # Express server
├── middleware/
│   └── auth.js                       # Bearer token auth
├── routes/
│   ├── campaigns.js                  # Campaign CRUD routes
│   ├── creatives.js                  # Creative management routes
│   ├── generate.js                   # Creative generation routes
│   ├── analytics.js                  # Analytics pulling routes
│   └── audiences.js                  # Audience management routes
├── platforms/
│   ├── meta.js                       # Meta Marketing API wrapper
│   ├── tiktok.js                     # TikTok Marketing API wrapper
│   ├── x.js                          # X Ads API wrapper
│   └── telegram.js                   # Telegram Bot API wrapper
├── creative/
│   ├── copywriter.js                 # Claude API for ad copy
│   ├── image_generator.js            # GPT Image 1 / Flux integration
│   ├── video_generator.js            # Runway API integration
│   └── brand_overlay.js              # Sharp-based logo/text overlay
├── utils/
│   ├── image_sizes.js                # Platform-specific dimensions
│   └── compliance.js                 # Ad policy compliance checker
├── Dockerfile
└── fly.toml
```

### Migrations

```
priv/repo/migrations/
├── 20260221200001_create_ad_platform_accounts.exs
├── 20260221200002_create_ad_campaigns.exs
├── 20260221200003_create_ad_creatives.exs
├── 20260221200004_create_ad_budgets.exs
├── 20260221200005_create_ad_offers.exs
├── 20260221200006_create_ad_performance_snapshots.exs
├── 20260221200007_create_ai_ads_decisions.exs
├── 20260221200008_create_ai_ads_instructions.exs
└── 20260221200009_create_ad_attributions.exs
```

### JS Hooks

```
assets/js/hooks/
└── utm_tracker.js                    # UTM parameter capture + attribution
```

---

## Appendix A: Platform API Approval Checklist

Before Phase 1:
- [ ] Apply for X Ads API access at ads.x.com
- [ ] Create Meta developer app + submit for App Review
- [ ] Complete Meta Business Verification
- [ ] Create TikTok developer account + create app

Before Phase 4:
- [ ] Submit TikTok app review with demo video
- [ ] Apply for TikTok crypto ads beta (if promoting tokens)

Before Phase 5:
- [ ] Create Telegram Ads account at ads.telegram.org
- [ ] Fund with minimum 20 TON

## Appendix B: Environment Variables

```bash
# Feature flag
AI_ADS_MANAGER_ENABLED=true

# Node.js ad service
ADS_SERVICE_URL=https://ads-manager.fly.dev
ADS_SERVICE_SECRET=<secret>

# Platform API keys (stored in Node.js service, not Elixir)
# Meta
META_APP_ID=<id>
META_APP_SECRET=<secret>
META_ACCESS_TOKEN=<system_user_token>
META_AD_ACCOUNT_ID=<account_id>

# X (Twitter)
X_ADS_CONSUMER_KEY=<key>
X_ADS_CONSUMER_SECRET=<secret>
X_ADS_ACCESS_TOKEN=<token>
X_ADS_ACCESS_TOKEN_SECRET=<secret>
X_ADS_ACCOUNT_ID=<account_id>

# TikTok
TIKTOK_APP_ID=<id>
TIKTOK_APP_SECRET=<secret>
TIKTOK_ACCESS_TOKEN=<token>
TIKTOK_ADVERTISER_ID=<id>

# Creative generation
OPENAI_API_KEY=<key>           # For GPT Image 1
RUNWAY_API_KEY=<key>           # For video generation
# ANTHROPIC_API_KEY already exists

# Telegram
TELEGRAM_BOT_TOKEN=<token>     # For organic channel posts
TELEGRAM_ADS_TON_WALLET=<addr> # For native ads funding
```

## Appendix C: Risk Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| Meta app approval takes weeks | Delays Phase 2 | Apply immediately, start with X only |
| TikTok crypto restrictions block ads | Can't run token promos on TikTok | Focus on educational content, game promotion |
| AI overspends budget | Financial loss | Hard ceiling in code, multiple safety layers |
| Generated creatives violate platform policies | Ad account banned | Compliance layer pre-screens all content |
| Ad platform API changes break integration | Service outage | Pin API versions, monitor deprecation notices |
| Low ROAS initially | Budget waste | Start small ($50/day), manual approval mode |
| Telegram lacks API | Can't fully automate | Accept semi-manual, focus on bot API for organic |
| Creative fatigue | Declining CTR | 6-hour fatigue checks, auto-refresh creatives |
