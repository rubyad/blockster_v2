# Content Automation Pipeline - Implementation Plan

## Overview

Automated content creation and publishing system for Blockster that:
1. Subscribes to RSS feeds from top 20 crypto news sites
2. Analyzes incoming articles in real-time to identify trending topics
3. Uses Claude to generate original, opinionated content with a distinct editorial voice
4. Embeds relevant tweets into articles
5. Self-publishes under multiple author personas
6. Automatically assigns BUX rewards to each published post
7. Targets ~10 high-quality posts per day initially, scaling upward

---

## 1. System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Supervision Tree                             │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │ FeedPoller   │  │ TopicEngine  │  │ ContentPublisher       │ │
│  │ (GenServer)  │  │ (GenServer)  │  │ (GenServer)            │ │
│  │              │  │              │  │                        │ │
│  │ Polls RSS    │→ │ Clusters &   │→ │ Claude generation →    │ │
│  │ feeds every  │  │ ranks topics │  │ tweet embedding →      │ │
│  │ 5 minutes    │  │ every 15 min │  │ publish & assign BUX   │ │
│  └──────────────┘  └──────────────┘  └────────────────────────┘ │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐                             │
│  │ AuthorRotator│  │ ContentQueue │                             │
│  │ (module)     │  │ (GenServer)  │                             │
│  │              │  │              │                             │
│  │ Manages      │  │ Schedules    │                             │
│  │ author       │  │ posts across │                             │
│  │ personas     │  │ the day      │                             │
│  └──────────────┘  └──────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
```

### Module Structure
```
lib/blockster_v2/content_automation/
├── feed_poller.ex          # RSS feed polling GenServer
├── feed_parser.ex          # RSS/Atom parsing logic
├── feed_store.ex           # Ecto queries for feed items, topics, queue
├── topic_engine.ex         # Topic clustering & ranking
├── content_generator.ex    # Claude API integration
├── tweet_finder.ex         # Find relevant tweets for topics
├── author_rotator.ex       # Author persona management
├── content_publisher.ex    # Post creation & publishing
├── content_queue.ex        # Scheduling & rate limiting
├── prompt_templates.ex     # Claude prompt engineering
└── config.ex               # Feed URLs, author personas, settings
```

---

## 2. RSS Feed Infrastructure

### 2.1 Target Feeds

Feeds are organized into two tiers. **Premium sources** produce higher-quality articles and receive
higher weight in the TopicEngine ranking algorithm. Topics sourced from premium outlets get a 2x
ranking boost and are preferred for content generation.

> **Editorial note on premium sources**: Many of the premium mainstream/financial outlets (Bloomberg,
> FT, Reuters, The Economist, Forbes, The Verge, TechCrunch) tend toward a center-left or
> pro-regulation editorial slant. This is a **feature, not a bug** — these are the narratives our
> audience wants challenged. When a premium source article advocates for more regulation, CBDCs, or
> government oversight, the content generator should use it as a springboard to present the
> pro-decentralization counter-argument. The prompt templates explicitly instruct Claude to identify
> and push back against statist framing in source material.

#### Premium Tier (weight: 2x) — Mainstream Finance & Tech

> **Feed Accessibility Note (Feb 2026)**: Many mainstream outlets block RSS access via
> paywalls or bot protection. Only feeds marked "Verified" below are confirmed accessible.
> Blocked feeds are kept in config but skipped at runtime — if they become accessible later,
> they'll start working automatically. We compensate with additional verified crypto-native
> premium sources.

| # | Site | RSS Feed URL | Status | Focus | Editorial Lean |
|---|------|-------------|--------|-------|----------------|
| 1 | Bloomberg Crypto | `https://feeds.bloomberg.com/crypto/news.rss` | **Verified** | Markets, macro, institutional | Center-left, pro-establishment |
| 2 | TechCrunch Crypto | `https://techcrunch.com/category/cryptocurrency/feed/` | **Verified** | Web3 startups, VC, tech | Left-leaning, Silicon Valley |
| 3 | Reuters Business | `https://www.reutersagency.com/feed/?best-topics=business-finance` | Blocked (403) | Breaking finance, regulation | Center, institutional |
| 4 | Financial Times | `https://www.ft.com/cryptofinance?format=rss` | Blocked (paywall) | Crypto finance, regulation, macro | Center-left, pro-regulation |
| 5 | The Economist | `https://www.economist.com/finance-and-economics/rss.xml` | Blocked (403) | Macro economics, policy, analysis | Center-left, globalist |
| 6 | Forbes Crypto | `https://www.forbes.com/crypto-blockchain/feed/` | Blocked (Cloudflare) | Crypto business, profiles, markets | Center-right, business-friendly |
| 7 | Barron's | `https://www.barrons.com/feed?id=blog_rss` | Blocked (paywall) | Investment, markets, analysis | Center-right, Wall Street |
| 8 | The Verge | `https://www.theverge.com/rss/index.xml` | Blocked (403) | Tech, crypto policy, culture | Left-leaning, consumer tech |

#### Promoted to Premium (verified accessible, high-quality crypto-native sources)

These crypto-native sources are promoted to premium tier to ensure sufficient premium feed coverage:

| # | Site | RSS Feed URL | Status | Focus |
|---|------|-------------|--------|-------|
| 9 | CoinDesk | `https://www.coindesk.com/arc/outboundfeeds/rss/` | **Verified** | General crypto, markets, regulation |
| 10 | The Block | `https://www.theblock.co/rss.xml` | **Verified** | Institutional, markets, data |
| 11 | Blockworks | `https://blockworks.co/feed` | **Verified** (Atom) | DeFi, institutional, markets |
| 12 | DL News | `https://www.dlnews.com/arc/outboundfeeds/rss/` | **Verified** (full content) | Breaking news, investigations |

#### Standard Tier (weight: 1x) — Crypto-Native Sources

| # | Site | RSS Feed URL | Content | Focus |
|---|------|-------------|---------|-------|
| 13 | CoinTelegraph | `https://cointelegraph.com/rss` | Summaries | General crypto, DeFi, trading |
| 14 | Decrypt | `https://decrypt.co/feed` | Summaries | General crypto, Web3, gaming |
| 15 | Bitcoin Magazine | `https://bitcoinmagazine.com/feed` | Full content | Bitcoin-focused, macro |
| 16 | The Defiant | `https://thedefiant.io/feed` | Summaries | DeFi-focused |
| 17 | CryptoSlate | `https://cryptoslate.com/feed/` | Full content | General crypto, data |
| 18 | NewsBTC | `https://www.newsbtc.com/feed/` | Full content | Trading, price analysis |
| 19 | Bitcoinist | `https://bitcoinist.com/feed/` | Full content | Bitcoin, altcoins |
| 20 | U.Today | `https://u.today/rss` | Summaries | General crypto, breaking news |
| 21 | Crypto Briefing | `https://cryptobriefing.com/feed/` | Summaries | DeFi, research |
| 22 | BeInCrypto | `https://beincrypto.com/feed/` | Summaries | General crypto, education |
| 23 | Unchained | `https://unchainedcrypto.com/feed/` | Summaries | Long-form, interviews |
| 24 | CoinGape | `https://coingape.com/feed/` | Summaries | Price, markets |
| 25 | Crypto Potato | `https://cryptopotato.com/feed/` | Summaries | Trading, altcoins |
| 26 | AMBCrypto | `https://ambcrypto.com/feed/` | Summaries | Analytics, on-chain data |
| 27 | Protos | `https://protos.com/feed/` | Summaries | Investigations, deep dives |
| 28 | Milk Road | `https://www.milkroad.com/feed` | Summaries | Macro, trends, accessible |

**Feed Format Notes**:
- Blockworks uses **Atom** format (not RSS) — parser must handle both
- 5 feeds provide full article content in the feed (Bitcoin Magazine, DL News, CryptoSlate, NewsBTC, Bitcoinist)
- All others provide summaries only — sufficient for topic clustering
- Date formats are consistent RFC 2822 across RSS feeds

### 2.2 Elixir RSS Library

**Recommended**: `fast_rss` (`{:fast_rss, "~> 0.5"}`)
- Rust NIF — fast and reliable
- Handles RSS 2.0 via `FastRSS.parse_rss/1` and Atom via `FastRSS.parse_atom/1`
- Returns `{:ok, map}` with `"items"` list containing `"title"`, `"link"`, `"description"`, `"pub_date"`
- Last update Sep 2023 but stable — RSS/Atom specs don't change
- **Alternative**: `ElixirFeedParser` (`~> 2.1`) — pure Elixir, auto-detects format, but slower

### 2.3 FeedPoller GenServer

```elixir
defmodule BlocksterV2.ContentAutomation.FeedPoller do
  use GenServer

  @poll_interval :timer.minutes(5)  # Poll every 5 minutes

  # Uses GlobalSingleton for cluster-wide single instance
  def start_link(opts) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
  end

  def init(_) do
    schedule_poll()
    {:ok, %{last_poll: nil}}
  end

  def handle_info(:poll_feeds, state) do
    feeds = get_configured_feeds()

    # Poll all feeds in parallel with Task.async_stream
    # Store items INCREMENTALLY per feed (not batched) for crash resilience
    total_new = feeds
    |> Task.async_stream(&poll_and_store_feed/1, max_concurrency: 5, timeout: 30_000)
    |> Enum.reduce(0, fn
      {:ok, count} -> count
      {:exit, _} -> 0
    end)

    if total_new > 0 do
      # Notify TopicEngine that new items are available
      GenServer.cast({:global, TopicEngine}, :new_items_available)
    end

    schedule_poll()
    {:noreply, %{state | last_poll: DateTime.utc_now()}}
  end

  # Poll a single feed and store its items immediately (crash-resilient)
  defp poll_and_store_feed(%{url: url, source: source, tier: tier}) do
    case Req.get(url, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: body}} ->
        items = parse_feed(body)
        |> Map.get("items", [])
        |> Enum.map(fn entry ->
          %{
            title: entry["title"],
            url: entry["link"],
            summary: entry["description"] || entry["content"],
            published_at: parse_date(entry["pub_date"] || entry["updated"]),
            source: source,
            tier: tier,           # :premium or :standard
            weight: tier_weight(tier),  # 2.0 for premium, 1.0 for standard
            fetched_at: DateTime.utc_now()
          }
        end)

        # Store immediately per feed (not batched across all feeds)
        FeedStore.store_new_items(items)

      {:ok, %{status: status}} ->
        Logger.warning("[FeedPoller] #{source} returned HTTP #{status}")
        0

      {:error, reason} ->
        Logger.warning("[FeedPoller] #{source} failed: #{inspect(reason)}")
        0
    end
  end

  # Auto-detect RSS vs Atom format (using fast_rss)
  defp parse_feed(body) do
    cond do
      String.contains?(body, "<feed") -> FastRSS.parse_atom(body)
      String.contains?(body, "<rss") -> FastRSS.parse_rss(body)
      String.contains?(body, "<rdf:RDF") -> FastRSS.parse_rss(body)
      true -> {:error, :unknown_format}
    end
    |> case do
      {:ok, feed} -> feed
      _ -> %{"items" => []}
    end
  end

  defp tier_weight(:premium), do: 2.0
  defp tier_weight(:standard), do: 1.0
end
```

### 2.4 Feed Storage (PostgreSQL)

Pipeline data (feed items, topics, publish queue) lives in PostgreSQL — not Mnesia. These are
write-once/process-once records with text-heavy content (~300 words per summary), which suits
a relational database. Mnesia is reserved for small, hot, real-time state (admin settings,
pipeline progress).

**Ecto migration** (creates `content_feed_items` table):
```elixir
# priv/repo/migrations/YYYYMMDDHHMMSS_create_content_feed_items.exs
defmodule BlocksterV2.Repo.Migrations.CreateContentFeedItems do
  use Ecto.Migration

  def change do
    create table(:content_feed_items) do
      add :url, :string, null: false
      add :title, :string, null: false
      add :summary, :text                     # ~300 words of text per item
      add :source, :string, null: false
      add :tier, :string, null: false          # "premium" or "standard"
      add :weight, :float, default: 1.0
      add :published_at, :utc_datetime
      add :fetched_at, :utc_datetime, null: false
      add :processed, :boolean, default: false
      add :topic_cluster_id, references(:content_generated_topics, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:content_feed_items, [:url])   # Deduplicates across feeds
    create index(:content_feed_items, [:source])
    create index(:content_feed_items, [:processed])
    create index(:content_feed_items, [:fetched_at])
  end
end
```

- Key: `url` (unique — deduplicates across feeds)
- `tier` — `"premium"` or `"standard"` (from feed config)
- `weight` — `2.0` for premium, `1.0` for standard (used in TopicEngine ranking)
- `processed` — `false` initially, set to `true` AFTER topic is stored in `content_generated_topics`
- `topic_cluster_id` — links to the topic this item was clustered into (nil until processed)

---

## 3. Topic Engine — How 100 Articles Become N Posts

### 3.0 The Selection Pipeline (Overview)

Here's the exact chain from raw RSS items to published articles:

```
100 RSS articles/day (from 28 feeds)
        │
        ▼
  ┌─ Pre-Filter ──────────────────────────┐
  │ • Only last 6-12 hours (not full 24h) │
  │ • Truncate summaries to 300 chars     │
  │ • Cap at 50 items per batch           │
  │ • Typically ~20-40 items per cycle    │
  └───────────────┬───────────────────────┘
                  ▼
  ┌─ Claude Haiku: Cluster ───────────────┐
  │ Groups articles by story/event:       │
  │ • 8 articles about SEC → 1 topic      │
  │ • 5 about BTC hash rate → 1 topic     │
  │ • 3 about Tether → 1 topic            │
  │ • 6 unrelated one-offs → 6 topics     │
  │ Result: ~12-20 distinct topics        │
  └───────────────┬───────────────────────┘
                  ▼
  ┌─ Score & Rank ────────────────────────┐
  │ Each topic scored by:                 │
  │ • Source count & weight (multi-source │
  │   = bigger story)                     │
  │ • Premium source bonus (+3)           │
  │ • Recency bonus (last 2h > last 6h)  │
  │ • Admin topic boost (if configured)   │
  │ Result: topics sorted by score        │
  └───────────────┬───────────────────────┘
                  ▼
  ┌─ Filter Already Covered ──────────────┐
  │ Compare topic titles against last     │
  │ 7 days of content_generated_topics    │
  │ Remove topics too similar to recent   │
  │ published articles                    │
  └───────────────┬───────────────────────┘
                  ▼
  ┌─ Category Diversity Gate ─────────────┐
  │ Max N articles per category per day   │
  │ (configurable by admin per category)  │
  │ If 5 regulation topics scored high,   │
  │ only top N pass through               │
  │ Remaining slots filled by next-best   │
  │ from underrepresented categories      │
  └───────────────┬───────────────────────┘
                  ▼
  ┌─ Daily Budget Check ──────────────────┐
  │ Target: N articles/day (admin config) │
  │ Already published today: P            │
  │ Already in queue: Q                   │
  │ Slots available: N - P - Q            │
  │ Take that many topics (usually 2-4    │
  │ per cycle, across ~4 cycles/day that  │
  │ produce topics)                       │
  └───────────────┬───────────────────────┘
                  ▼
       ~2-4 topics per cycle
       sent to ContentGenerator
       → review queue → admin → publish
```

**Key insight**: The TopicEngine doesn't select all 10 articles at once. It runs every 15 minutes
and picks 2-4 topics per cycle, because news is continuous. A breaking story at 3pm should
get covered even if 8 articles were already queued from the morning cycle.

### 3.1 Admin Topic Controls

The admin can influence what gets written about via the dashboard (Section 15). These
settings are stored in a Mnesia table `content_automation_settings` and read at runtime:

```elixir
# Mnesia table for admin-configurable settings
:mnesia.create_table(:content_automation_settings, [
  attributes: [:key, :value, :updated_at, :updated_by],
  disc_copies: [node()]
])

# Settings and their defaults:
%{
  # ── Volume ──
  posts_per_day: 10,                    # Target articles per day (admin slider: 1-50)

  # ── Category Preferences ──
  # Per-category daily max and boost. Admin can say "I want more DeFi, less NFT"
  # boost adds to the topic's rank score; max_per_day caps output
  category_config: %{
    defi:           %{boost: 0, max_per_day: 3},
    regulation:     %{boost: 0, max_per_day: 2},
    bitcoin:        %{boost: 0, max_per_day: 2},
    trading:        %{boost: 0, max_per_day: 2},
    ethereum:       %{boost: 0, max_per_day: 2},
    macro_trends:   %{boost: 0, max_per_day: 2},
    gaming:         %{boost: 0, max_per_day: 2},
    altcoins:       %{boost: 0, max_per_day: 2},
    ai_crypto:      %{boost: 0, max_per_day: 2},
    stablecoins:    %{boost: 0, max_per_day: 2},
    privacy:        %{boost: 0, max_per_day: 2},
    adoption:       %{boost: 0, max_per_day: 2},
    security_hacks: %{boost: 0, max_per_day: 2},
    nft:            %{boost: 0, max_per_day: 1},
    cbdc:           %{boost: 0, max_per_day: 1},
    rwa:            %{boost: 0, max_per_day: 1},
    gambling:       %{boost: 0, max_per_day: 1},
    token_launches: %{boost: 0, max_per_day: 1},
    mining:         %{boost: 0, max_per_day: 1}
  },

  # ── Topic Boosts ──
  # Admin can add temporary keyword boosts: "I want more coverage of Solana this week"
  # These add to rank score when the keyword appears in topic title
  keyword_boosts: [
    # %{keyword: "solana", boost: 5.0, expires_at: ~U[2026-02-18 00:00:00Z]}
  ],

  # ── Topic Blocks ──
  # Admin can block specific keywords: "Stop writing about Dogecoin"
  keyword_blocks: [
    # "dogecoin", "shiba inu"
  ],

  # ── Pipeline State ──
  paused: false                         # Pause/resume from dashboard
}
```

**Dashboard UI for these controls** (on the `/admin/content` page):

```
┌─ Pipeline Settings ─────────────────────────────────────────────┐
│                                                                  │
│  Articles per day:  [────●──────] 10                            │
│                     1              50                             │
│                                                                  │
│  ── Category Preferences ──────────────────────────────────────  │
│                                                                  │
│  │ Category       │ Boost  │ Max/Day │                           │
│  │────────────────│────────│─────────│                           │
│  │ DeFi           │ [+0 ]  │ [3]     │                           │
│  │ Regulation     │ [+0 ]  │ [2]     │                           │
│  │ Bitcoin        │ [+2 ]  │ [3]     │  ← admin boosted bitcoin │
│  │ Trading        │ [+0 ]  │ [2]     │                           │
│  │ AI & Crypto    │ [+3 ]  │ [2]     │  ← admin boosted AI      │
│  │ NFT            │ [-5 ]  │ [1]     │  ← admin deprioritized   │
│  │ (... more)     │        │         │                           │
│                                                                  │
│  ── Keyword Boosts (temporary) ────────────────────────────────  │
│                                                                  │
│  ┌──────────────┬───────┬────────────┬─────────┐                │
│  │ Keyword      │ Boost │ Expires    │         │                │
│  │──────────────│───────│────────────│─────────│                │
│  │ solana       │ +5    │ Feb 18     │ [Remove]│                │
│  │ ethereum etf │ +3    │ Feb 20     │ [Remove]│                │
│  └──────────────┴───────┴────────────┴─────────┘                │
│  Keyword: [__________] Boost: [+5] Expires: [Feb 25] [Add]     │
│                                                                  │
│  ── Keyword Blocks ────────────────────────────────────────────  │
│                                                                  │
│  [✕ dogecoin] [✕ shiba inu] [✕ pepe]                           │
│  Block keyword: [__________] [Add]                               │
│                                                                  │
└──────────────────────────────────────────────────────────────────┘
```

**How admin controls affect scoring**:

```elixir
# In rank_topics/1, after calculating base score:
total_score = source_score + multi_source_bonus + recency_score + premium_bonus

# Apply admin category boost (can be negative to deprioritize)
category_boost = get_category_boost(topic.category)
total_score = total_score + category_boost

# Apply admin keyword boosts (check topic title for matching keywords)
keyword_boost = calculate_keyword_boost(topic.title)
total_score = total_score + keyword_boost
```

**Example**: Admin sets bitcoin boost to +2 and adds keyword boost "solana" +5:
- "Bitcoin hash rate ATH" → base score 14.0 + category boost 2.0 = **16.0** (moved up in ranking)
- "Solana DeFi TVL surges" → base score 6.5 + keyword boost 5.0 = **11.5** (jumped ahead of lower topics)
- "Random NFT project" → base score 3.0 + category boost -5.0 = **-2.0** (effectively blocked)

### 3.2 Topic Clustering

```elixir
defmodule BlocksterV2.ContentAutomation.TopicEngine do
  use GenServer

  @analysis_interval :timer.minutes(15)

  # Uses GlobalSingleton for cluster-wide single instance
  def start_link(opts) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
  end

  @categories [
    :defi, :rwa, :regulation, :gaming, :trading, :token_launches,
    :gambling, :privacy, :macro_trends, :investment, :bitcoin,
    :ethereum, :altcoins, :nft, :ai_crypto, :stablecoins, :cbdc,
    :security_hacks, :adoption, :mining
  ]

  def handle_info(:analyze, state) do
    if Config.enabled?() and not Settings.paused?() do
      case analyze_and_select() do
        {:ok, selected_topics} ->
          for topic <- selected_topics do
            pipeline_id = Ecto.UUID.generate()
            send_to_content_generation(topic, pipeline_id)
          end
        {:error, reason} ->
          Logger.error("[TopicEngine] Analysis failed: #{inspect(reason)}")
      end
    end

    schedule_analysis()
    {:noreply, state}
  end

  def analyze_and_select do
    posts_per_day = Settings.get(:posts_per_day, 10)

    # 1. How many slots are available right now?
    published_today = FeedStore.count_published_today()
    queued = FeedStore.count_queued()
    slots_available = posts_per_day - published_today - queued

    if slots_available <= 0 do
      Logger.info("[TopicEngine] No slots available (#{published_today} published, #{queued} queued, target #{posts_per_day})")
      {:ok, []}
    else
      # 2. Fetch unprocessed feed items from recent hours
      items = FeedStore.get_recent_unprocessed(hours: 12)

      if length(items) < 3 do
        Logger.info("[TopicEngine] Only #{length(items)} items, skipping cycle")
        {:ok, []}
      else
        # 3. Pre-filter for Claude (truncate, cap)
        batch = prepare_batch(items)

        # 4. Claude Haiku clusters items into topics
        {:ok, topics} = cluster_into_topics(batch)

        # 5. Apply keyword blocks (admin can block "dogecoin" etc)
        topics = apply_keyword_blocks(topics)

        # 6. Score and rank (includes admin category boosts + keyword boosts)
        ranked = rank_topics(topics)

        # 7. Filter already-covered topics (last 7 days)
        filtered = filter_already_covered(ranked)

        # 8. Apply category diversity (admin-configurable max per category)
        diversified = apply_category_diversity(filtered)

        # 9. Take available slots
        selected = Enum.take(diversified, slots_available)

        # 10. Mark source items as processed (two-phase: AFTER topic stored)
        mark_items_processed(selected)

        Logger.info("[TopicEngine] Selected #{length(selected)} topics from #{length(topics)} clusters (#{length(items)} feed items)")
        {:ok, selected}
      end
    end
  end

  # ── SCORING ──────────────────────────────────────────────

  defp rank_topics(topics) do
    category_config = Settings.get(:category_config, %{})
    keyword_boosts = Settings.get(:keyword_boosts, [])

    topics
    |> Enum.map(fn topic ->
      # Source coverage score: how many outlets are covering this?
      # premium = 2.0 weight, standard = 1.0 weight
      source_score = Enum.sum(Enum.map(topic.source_items, & &1.weight))

      # Multi-source bonus: stories covered by 3+ sources are clearly newsworthy
      multi_source_bonus = cond do
        length(topic.source_items) >= 5 -> 4.0   # Major story
        length(topic.source_items) >= 3 -> 2.0   # Significant story
        length(topic.source_items) >= 2 -> 0.5   # Minor story
        true -> 0.0                               # Single source
      end

      # Recency bonus: newer = more relevant
      hours_old = hours_since(topic.newest_item_at)
      recency_score = cond do
        hours_old < 2 -> 3.0    # Breaking
        hours_old < 4 -> 2.0    # Fresh
        hours_old < 8 -> 1.0    # Recent
        true -> 0.0             # Older
      end

      # Premium source bonus
      has_premium = Enum.any?(topic.source_items, &(&1.tier == :premium))
      premium_bonus = if has_premium, do: 3.0, else: 0.0

      # Admin category boost (can be negative to deprioritize)
      cat_config = Map.get(category_config, topic.category, %{})
      category_boost = Map.get(cat_config, :boost, 0)

      # Admin keyword boosts (check topic title for matching keywords)
      now = DateTime.utc_now()
      keyword_boost = keyword_boosts
        |> Enum.filter(fn kb -> DateTime.compare(kb.expires_at, now) == :gt end)
        |> Enum.filter(fn kb ->
          String.contains?(String.downcase(topic.title), String.downcase(kb.keyword))
        end)
        |> Enum.map(& &1.boost)
        |> Enum.sum()

      total_score = source_score + multi_source_bonus + recency_score +
                    premium_bonus + category_boost + keyword_boost

      Map.merge(topic, %{
        rank_score: total_score,
        source_count: length(topic.source_items),
        has_premium_source: has_premium
      })
    end)
    |> Enum.filter(& &1.rank_score > 0)  # Negative scores = effectively blocked
    |> Enum.sort_by(& &1.rank_score, :desc)
  end

  # ── SCORING EXAMPLES ─────────────────────────────────────
  #
  # Example: "SEC sues Uniswap" — covered by 8 sources including Bloomberg
  #   source_score:       3 premium (6.0) + 5 standard (5.0) = 11.0
  #   multi_source_bonus: 8 sources → 4.0
  #   recency_score:      1 hour old → 3.0
  #   premium_bonus:      has premium → 3.0
  #   category_boost:     regulation = 0 (default)
  #   keyword_boost:      no match = 0
  #   TOTAL: 21.0  ← very high, will definitely be selected
  #
  # Example: "New memecoin launches on Solana" — 1 source (NewsBTC)
  #   source_score:       1 standard = 1.0
  #   multi_source_bonus: 1 source → 0.0
  #   recency_score:      3 hours old → 2.0
  #   premium_bonus:      no premium → 0.0
  #   category_boost:     token_launches = 0
  #   keyword_boost:      admin set "solana" +5 → 5.0
  #   TOTAL: 8.0  ← boosted by admin keyword, now competitive
  #
  # Example: "Dogecoin whale moves $50M" — 2 sources
  #   keyword_blocks includes "dogecoin" → FILTERED OUT entirely

  # ── KEYWORD BLOCKS ──────────────────────────────────────

  defp apply_keyword_blocks(topics) do
    blocks = Settings.get(:keyword_blocks, [])

    if Enum.empty?(blocks) do
      topics
    else
      Enum.reject(topics, fn topic ->
        title_lower = String.downcase(topic.title)
        Enum.any?(blocks, fn blocked ->
          String.contains?(title_lower, String.downcase(blocked))
        end)
      end)
    end
  end

  # ── DIVERSITY ────────────────────────────────────────────

  defp apply_category_diversity(ranked_topics) do
    category_config = Settings.get(:category_config, %{})
    today_counts = FeedStore.get_today_category_counts()

    {selected, _counts} =
      Enum.reduce(ranked_topics, {[], today_counts}, fn topic, {acc, counts} ->
        cat_config = Map.get(category_config, topic.category, %{})
        max_per_day = Map.get(cat_config, :max_per_day, 2)
        current = Map.get(counts, topic.category, 0)

        if current < max_per_day do
          {acc ++ [topic], Map.put(counts, topic.category, current + 1)}
        else
          Logger.debug("[TopicEngine] Skipping '#{topic.title}' — #{topic.category} has #{current}/#{max_per_day} today")
          {acc, counts}
        end
      end)

    selected
  end

  # ── DEDUPLICATION ────────────────────────────────────────

  defp filter_already_covered(topics) do
    recent_titles = FeedStore.get_generated_topic_titles(days: 7)

    Enum.reject(topics, fn topic ->
      topic_words = significant_words(topic.title)

      Enum.any?(recent_titles, fn recent_title ->
        recent_words = significant_words(recent_title)
        overlap = MapSet.intersection(topic_words, recent_words) |> MapSet.size()
        min_size = min(MapSet.size(topic_words), MapSet.size(recent_words))
        min_size > 0 and overlap / min_size > 0.6
      end)
    end)
  end

  defp significant_words(title) do
    stopwords = ~w(the a an is are was were be been being have has had do does did
                   will would shall should may might can could of in to for on with
                   at by from as into about between through after before)

    title
    |> String.downcase()
    |> String.split(~r/\W+/, trim: true)
    |> Enum.reject(&(&1 in stopwords))
    |> MapSet.new()
  end
end
```

### 3.3 Concrete Example: A Full Day

Here's what a typical day looks like with 100 incoming articles and admin target set to 10:

```
 6:00 UTC — FeedPoller has accumulated ~30 items overnight

 12:00 UTC (first cycle in publish window)
   TopicEngine pulls 35 unprocessed items
   Claude Haiku clusters into 14 topics:
     1. "SEC enforcement action against Uniswap" (7 sources, 2 premium) → score 21.0
     2. "Bitcoin hash rate ATH" (5 sources, 1 premium) → score 14.0
     3. "Tether launches on Arbitrum" (3 sources, 1 premium) → score 10.0
     4. "Fed holds rates, crypto reacts" (4 sources, 2 premium) → score 16.0
     5. "New EU MiCA rules take effect" (3 sources, 1 premium) → score 10.0
     6. "Solana DeFi TVL surges" (3 sources) → score 6.5
     7. "Ethereum L2 gas costs drop" (2 sources) → score 4.5
     8. "NFT marketplace shuts down" (2 sources) → score 3.5
     9. "New memecoin launches" (1 source) → score 3.0
    10-14. (various single-source stories) → scores 1.0-3.0

   After keyword blocks: 14 → 14 (nothing blocked today)
   After dedup filter: 14 → 13 (topic #5 too similar to last week's MiCA article)
   After category diversity: 13 → all pass (first cycle, no categories saturated)
   Daily budget: 0 published, 0 queued → 10 slots available
   Selected: top 4 (topics 1, 4, 2, 3) → sent to ContentGenerator

   Queue now has 4 articles pending review

 13:00 UTC — Admin reviews queue
   Approves #1 (SEC/Uniswap) after editing headline → published
   Approves #4 (Fed/rates) as-is → published
   Edits #2 (Bitcoin hash rate) — changes angle, adds a tweet → saves draft
   Approves #3 (Tether/Arbitrum) as-is → published

 15:15 UTC (another cycle)
   TopicEngine pulls 22 new unprocessed items (afternoon feeds)
   Claude clusters into 9 topics:
     1. "Binance delists privacy coins" (4 sources, 1 premium) → score 12.0
     2. "DeFi protocol hacked for $12M" (5 sources) → score 11.5
     3. "Coinbase earnings beat estimates" (3 sources, 2 premium) → score 13.0
     4. "New SEC commissioner crypto-friendly" (2 sources, 1 premium) → score 8.5
     5-9. (lower-scoring topics) → scores 2.0-5.0

   After dedup: topic #4 filtered (SEC/regulation — too similar to morning article)
   After diversity: all pass
   Daily budget: 3 published, 1 queued (draft) → 6 slots available
   Selected: top 3 (topics 3, 1, 2)

   Queue now has 4 articles (1 draft + 3 new)

 16:00 UTC — Admin reviews
   Publishes the morning draft (#2 Bitcoin hash rate)
   Approves Coinbase earnings article → published
   Approves Binance privacy coins → published
   Edits DeFi hack article (adds more details) → publishes

 18:30 UTC (another cycle)
   TopicEngine pulls 15 new items
   Clusters into 6 topics
   Daily budget: 6 published, 0 queued → 4 slots available
   Selected: top 3

 20:00 UTC — Admin approves 2, rejects 1 (low quality)

 22:00 UTC (last cycle before window closes)
   Only 2 slots remaining
   Selects 2 topics → queue
   Admin approves both

 End of day: 10 published, 1 rejected
   Categories: regulation(2), bitcoin(1), trading(2), defi(2),
               privacy(1), stablecoins(1), macro_trends(1)
```

### 3.4 What Makes a Topic Win?

**Topics that score highest** (and get selected):
1. **Multi-source stories** — if 5+ outlets cover it, it's clearly newsworthy. A story on
   only 1 source might just be that outlet's opinion piece.
2. **Premium source coverage** — Bloomberg writing about it signals institutional relevance.
   The +3 premium bonus is significant (equivalent to 3 extra standard sources).
3. **Breaking news** — the recency bonus (+3 for <2 hours) means a breaking story that just
   dropped will beat an equally-covered story from yesterday.
4. **Admin-boosted topics** — if the admin sets bitcoin boost +2 and keyword "ethereum etf" +5,
   those topics get a significant leg up over organic scoring.
5. **Counter-narrative potential** — topics from premium mainstream sources naturally have
   counter-narrative potential (the "reframe the establishment narrative" editorial approach).

**Topics that get filtered out**:
1. **Keyword-blocked** — admin blocked "dogecoin" → all dogecoin topics are removed before scoring.
2. **Already covered** — if we wrote about MiCA regulation 3 days ago and there's a similar
   MiCA story today, it's filtered by the 60% keyword overlap check.
3. **Category saturated** — 3rd regulation article of the day gets skipped even if scored high.
   The slot goes to the highest-scoring topic from an underrepresented category instead.
4. **Negative score** — admin set NFT category boost to -5, so a weak NFT story (base score 3.0)
   goes to -2.0 and gets filtered out.
5. **Single-source niche stories** — score too low to compete. A random altcoin pump on
   one blog (score ~3) can't beat a multi-source institutional story (score ~15).
6. **Daily budget exhausted** — once target articles are published + queued, the engine stops
   selecting until tomorrow.

### 3.5 How Admin Influences What Gets Written

| Admin Action | Effect | Example |
|-------------|--------|---------|
| Increase articles/day slider | More topics selected per cycle | 10 → 20: pipeline generates twice as many |
| Category boost +N | Topics in that category score higher | Bitcoin +3: bitcoin topics jump above similar-scored others |
| Category boost -N | Topics in that category score lower | NFT -5: most NFT topics drop below threshold |
| Category max/day | Hard cap on that category's output | Regulation max 1: only the single best regulation story makes it |
| Keyword boost | Specific keyword gets temporary priority | "solana" +5 for 1 week: any topic mentioning Solana gets boosted |
| Keyword block | Topics containing keyword are removed entirely | Block "dogecoin": zero dogecoin coverage |
| Pause pipeline | No new articles generated (queue frozen) | Maintenance, quality issues, manual content day |

### 3.2 Topic Analysis via Claude

Use Claude (Haiku for fast/cheap topic clustering, Opus 4.6 for content generation).

**Pre-filtering**: Before sending to Claude, filter feed items to reduce noise and cost:
1. Only items from the last 6-12 hours (configurable)
2. Deduplicate by URL (unique index handles this)
3. Truncate summaries to ~300 chars each (some feeds include full articles)
4. Cap at ~50 items per batch (keeps prompt under 4K tokens)

**Temperature**: Use `temperature: 0.1` for topic clustering (deterministic grouping).

**Structured Output**: Use Claude's tool use / structured output instead of raw JSON parsing.
This prevents JSON parse failures and ensures consistent schema:

```elixir
# Topic clustering — use Claude tool_use for structured output
# Model: claude-haiku-4-5-20251001 (fast & cheap)
# Temperature: 0.1 (deterministic clustering)

tools = [
  %{
    "name" => "report_topics",
    "description" => "Report the clustered topics found in the news articles",
    "input_schema" => %{
      "type" => "object",
      "properties" => %{
        "topics" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "title" => %{"type" => "string", "description" => "Concise topic title"},
              "category" => %{"type" => "string", "enum" => categories_list},
              "source_urls" => %{"type" => "array", "items" => %{"type" => "string"}},
              "key_facts" => %{"type" => "string"},
              "angles" => %{
                "type" => "array",
                "items" => %{"type" => "string"},
                "maxItems" => 3
              }
            },
            "required" => ["title", "category", "source_urls", "key_facts", "angles"]
          }
        }
      },
      "required" => ["topics"]
    }
  }
]

prompt = """
Analyze these #{length(items)} crypto news articles and group them into distinct topics.
For each topic, identify 3 potential original angles that a pro-decentralization,
pro-individual-liberty commentary site could take on the story.

Articles:
#{format_items_truncated(items)}
"""

# Call Claude with tool_use — response is guaranteed to match schema
case call_claude_with_tools(prompt, tools, model: "claude-haiku-4-5-20251001", temperature: 0.1) do
  {:ok, %{"topics" => topics}} -> topics
  {:error, reason} -> Logger.error("[TopicEngine] Clustering failed: #{inspect(reason)}"); []
end
```

---

## 4. Content Generation

### 4.1 Editorial Voice Definition

**The Blockster Voice**: Opinionated, right-wing libertarian perspective on crypto and finance.

Core principles for Claude prompts:
- **Pro-decentralization**: Bitcoin and crypto are tools for financial freedom
- **Anti-government overreach**: Skeptical of regulation, surveillance, CBDCs
- **Anti-central bank**: Federal Reserve criticism, inflation awareness, sound money advocacy
- **Pro-individual sovereignty**: Self-custody, privacy rights, personal responsibility
- **Anti-establishment media**: Challenge mainstream narratives about crypto
- **Pro-innovation**: Crypto/Web3 as the future of finance, gaming, identity
- **Engaging tone**: Not dry analysis - conversational, sometimes provocative, always informed

**Content Safety Guardrails** (include in all prompts):
- **No financial advice**: Never recommend buying, selling, or holding specific tokens/coins. Use "worth watching" or "interesting development" instead of "buy opportunity"
- **No market manipulation language**: Avoid "this will moon", "guaranteed returns", "get in before it's too late"
- **No conspiracy theories**: Evidence-based skepticism, not unfounded claims
- **Anti-repetition**: Never start articles with "In the world of crypto..." or "The crypto community is buzzing..." — use specific, varied hooks each time

### 4.2 Claude Content Generation Pipeline

**ContentGenerator is a module, not a GenServer** — it does stateless work (call Claude, parse response).
GenServers are reserved for processes that hold state or run on a timer.

```elixir
defmodule BlocksterV2.ContentAutomation.ContentGenerator do
  @anthropic_url "https://api.anthropic.com/v1/messages"

  def generate_article(topic, author_persona, pipeline_id) do
    prompt = build_generation_prompt(topic, author_persona)
    tools = article_output_schema()
    model = BlocksterV2.ContentAutomation.Config.content_model()

    # Use Claude tool_use for structured output — guaranteed schema
    # Model: claude-opus-4-6 for best editorial quality
    # Temperature: 0.7-0.8 for creative content generation
    case call_claude_with_tools(prompt, tools, model: model, temperature: 0.7) do
      {:ok, article} ->
        # Convert sections to TipTap JSON format
        tiptap_content = TipTapBuilder.build(article["sections"])

        {:ok, %{
          title: article["title"],
          content: tiptap_content,
          excerpt: article["excerpt"],
          category: topic.category,
          tags: article["tags"],
          featured_image_query: article["image_suggestion"],
          tweet_search_queries: article["tweet_suggestions"],  # Separate step
          pipeline_id: pipeline_id
        }}

      {:error, reason} ->
        Logger.error("[ContentGenerator] pipeline=#{pipeline_id} error=#{inspect(reason)}")
        {:error, reason}
    end
  end

  # Structured output schema — Claude returns tool_use result matching this exactly
  defp article_output_schema do
    [%{
      "name" => "write_article",
      "description" => "Write the article content",
      "input_schema" => %{
        "type" => "object",
        "properties" => %{
          "title" => %{"type" => "string", "description" => "Catchy, opinionated headline (max 80 chars)"},
          "excerpt" => %{"type" => "string", "description" => "One-sentence summary for cards/social (max 160 chars)"},
          "sections" => %{
            "type" => "array",
            "items" => %{
              "type" => "object",
              "properties" => %{
                "type" => %{"type" => "string", "enum" => ["paragraph", "heading", "blockquote", "bullet_list", "ordered_list", "spacer"]},
                "text" => %{"type" => "string"},
                "level" => %{"type" => "integer"},
                "items" => %{"type" => "array", "items" => %{"type" => "string"}}
              },
              "required" => ["type"]
            }
          },
          "tags" => %{"type" => "array", "items" => %{"type" => "string"}, "maxItems" => 5},
          "image_suggestion" => %{"type" => "string", "description" => "Search query for Unsplash"},
          "tweet_suggestions" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "maxItems" => 3,
            "description" => "Twitter search queries for embedding relevant tweets (processed separately)"
          }
        },
        "required" => ["title", "excerpt", "sections", "tags", "image_suggestion"]
      }
    }]
  end

  defp build_generation_prompt(topic, persona) do
    """
    You are #{persona.name}, a #{persona.bio_snippet} writing for Blockster,
    a crypto news and commentary platform.

    VOICE & STYLE:
    - #{persona.style_notes}
    - Opinionated and direct. You believe in decentralization, sound money, and individual freedom.
    - Skeptical of government regulation, central banks, and surveillance.
    - Not conspiracy theory territory - informed, evidence-based skepticism.
    - Use concrete examples and data when available.
    - Conversational but authoritative. Occasional wit and sarcasm.
    - #{if topic.has_premium_source, do: "~3-4 minute read time (700-1000 words) — deeper analysis", else: "~2 minute read time (400-500 words)"}

    CONTENT SAFETY:
    - NEVER recommend buying, selling, or holding specific tokens. No "buy the dip", "this will moon", etc.
    - NEVER predict specific prices or guaranteed returns.
    - Base all claims on facts from source material. Evidence-based skepticism, not conspiracy.
    - Do NOT start the article with generic openings like "In the world of crypto..." or
      "The crypto community is buzzing..." — use a specific, surprising hook every time.

    COUNTER-NARRATIVE FRAMING:
    - When source material comes from mainstream financial press (Bloomberg, FT, Reuters,
      The Economist, Forbes, TechCrunch, The Verge), these outlets often frame crypto stories
      through a pro-regulation, pro-institution, or statist lens.
    - Your job is to take their reporting (which is often excellent factually) and reframe it
      through a pro-freedom, pro-decentralization perspective.
    - Example: If Bloomberg reports "SEC moves to regulate DeFi protocols" with a tone of
      inevitability and approval, you should report the same facts but question whether this
      regulation serves individuals or incumbents, and highlight what freedoms are at stake.
    - When a mainstream source quotes a central banker or regulator approvingly, push back.
      What are they not saying? Who benefits from their proposals?
    - Use the credibility of these sources against them: "Even Bloomberg admits that..." or
      "The FT buried the lede here..." — leverage their authority while challenging their framing.

    ARTICLE STRUCTURE:
    1. Hook: Start with a provocative observation or the most interesting angle
    2. Context: Brief background (2-3 sentences, assume reader knows crypto basics)
    3. Analysis: Your take on what this means (this is the meat - be opinionated)
    4. Implications: What should crypto natives care about? What comes next?
    5. Closing: Punchy one-liner or call to action

    FORMATTING:
    - Use "paragraph" for body text. Markdown bold (**bold**) and italic (*italic*) supported.
    - Use "heading" (level 2 or 3) for section breaks.
    - Use "blockquote" for key quotes or highlighted points.
    - Use "bullet_list" or "ordered_list" with "items" array for lists.
    - Use "spacer" for visual breaks between major sections.

    #{if topic.has_premium_source do}
    NOTE: This topic is sourced from premium mainstream outlets. Write a more substantial
    article — include deeper analysis and explicitly engage with the mainstream framing.
    Quote or reference the source outlet by name where it adds credibility or contrast.
    #{end}

    TOPIC:
    #{topic.title}

    SOURCE MATERIAL (use for facts only, DO NOT copy phrasing):
    #{format_source_summaries(topic.source_items)}

    KEY DATA POINTS:
    #{topic.key_facts}

    ANGLE TO TAKE:
    #{topic.selected_angle}
    """
  end
end
```

**Tweet suggestions are returned as search queries** and processed in a separate pipeline step
by TweetFinder (Section 5). This avoids blocking article generation on X API calls and keeps
the content generation prompt focused on writing.

### 4.3 TipTap JSON Conversion

Convert Claude's structured output to Blockster's exact TipTap format:

```elixir
defmodule BlocksterV2.ContentAutomation.TipTapBuilder do
  @moduledoc """
  Converts article sections into TipTap JSON that TipTapRenderer expects.
  Must support ALL node types that the renderer handles:
  paragraph, heading, blockquote, bulletList, orderedList, listItem,
  image, tweet, spacer, codeBlock, horizontalRule
  """

  def build(sections) do
    content = Enum.flat_map(sections, &section_to_nodes/1)
    %{"type" => "doc", "content" => content}
  end

  defp section_to_nodes(%{"type" => "paragraph", "text" => text}) do
    [%{"type" => "paragraph", "content" => parse_inline_marks(text)}]
  end

  defp section_to_nodes(%{"type" => "heading", "level" => level, "text" => text}) do
    level = level || 2  # Default to h2
    [%{"type" => "heading", "attrs" => %{"level" => level},
       "content" => [%{"type" => "text", "text" => text}]}]
  end

  defp section_to_nodes(%{"type" => "blockquote", "text" => text}) do
    [%{"type" => "blockquote", "content" => [
      %{"type" => "paragraph", "content" => parse_inline_marks(text)}
    ]}]
  end

  # Bullet list: expects "items" array of strings
  defp section_to_nodes(%{"type" => "bullet_list", "items" => items}) do
    list_items = Enum.map(items, fn item_text ->
      %{"type" => "listItem", "content" => [
        %{"type" => "paragraph", "content" => parse_inline_marks(item_text)}
      ]}
    end)
    [%{"type" => "bulletList", "content" => list_items}]
  end

  # Ordered list: expects "items" array of strings
  defp section_to_nodes(%{"type" => "ordered_list", "items" => items}) do
    list_items = Enum.map(items, fn item_text ->
      %{"type" => "listItem", "content" => [
        %{"type" => "paragraph", "content" => parse_inline_marks(item_text)}
      ]}
    end)
    [%{"type" => "orderedList", "content" => list_items}]
  end

  # Image node
  defp section_to_nodes(%{"type" => "image", "src" => src}) do
    [%{"type" => "image", "attrs" => %{"src" => src}}]
  end

  # Tweet embed (added by TweetFinder post-processing)
  defp section_to_nodes(%{"type" => "tweet", "url" => url, "id" => id}) do
    [%{"type" => "tweet", "attrs" => %{"url" => url, "id" => id}}]
  end

  defp section_to_nodes(%{"type" => "spacer"}) do
    [%{"type" => "spacer"}]
  end

  defp section_to_nodes(%{"type" => "horizontalRule"}) do
    [%{"type" => "horizontalRule"}]
  end

  # Fallback — skip unknown types
  defp section_to_nodes(_), do: []

  @doc """
  Parse markdown-style inline formatting into TipTap text nodes with marks.
  Handles: **bold**, *italic*, [text](url)

  Uses Earmark to parse markdown fragments and convert to TipTap marks.
  Add `{:earmark, "~> 1.4"}` to mix.exs.
  """
  defp parse_inline_marks(text) when is_binary(text) do
    # Use regex-based parser for inline marks (simpler than full Earmark for fragments)
    # Process order matters: links first, then bold, then italic
    text
    |> tokenize_inline()
    |> Enum.map(&to_tiptap_text_node/1)
  end

  defp parse_inline_marks(_), do: []

  # Tokenize text into segments with marks
  # Returns list of {text, marks} tuples
  defp tokenize_inline(text) do
    # Pattern: [link text](url) | **bold** | *italic* | plain text
    regex = ~r/\[([^\]]+)\]\(([^)]+)\)|\*\*(.+?)\*\*|\*(.+?)\*|([^*\[]+)/

    Regex.scan(regex, text)
    |> Enum.map(fn
      [_, link_text, url | _] when link_text != "" ->
        {link_text, [%{"type" => "link", "attrs" => %{"href" => url}}]}
      [_, _, _, bold_text | _] when bold_text != "" ->
        {bold_text, [%{"type" => "bold"}]}
      [_, _, _, _, italic_text | _] when italic_text != "" ->
        {italic_text, [%{"type" => "italic"}]}
      [plain | _] ->
        {plain, []}
    end)
  end

  defp to_tiptap_text_node({text, []}) do
    %{"type" => "text", "text" => text}
  end

  defp to_tiptap_text_node({text, marks}) do
    %{"type" => "text", "text" => text, "marks" => marks}
  end
end
```

---

## 5. Tweet Integration

### 5.1 Finding Relevant Tweets

```elixir
defmodule BlocksterV2.ContentAutomation.TweetFinder do
  @x_api_url "https://api.twitter.com/2/tweets/search/recent"

  # X API Basic tier: $100/month, 10,000 tweets/month read
  # That's ~1,000 searches at 10 results each
  # With 10 articles/day, that's ~300 searches/month

  def find_tweets_for_topic(search_query, opts \\ []) do
    max_results = Keyword.get(opts, :max_results, 5)

    params = %{
      "query" => "#{search_query} -is:retweet lang:en",
      "max_results" => max_results,
      "tweet.fields" => "public_metrics,created_at,author_id",
      "expansions" => "author_id",
      "user.fields" => "username,verified"
    }

    case call_x_api(params) do
      {:ok, tweets} ->
        # Rank by engagement (likes + retweets)
        tweets
        |> Enum.sort_by(fn t ->
          t.public_metrics.like_count + t.public_metrics.retweet_count
        end, :desc)
        |> Enum.take(2)  # Top 2 tweets per article
        |> Enum.map(fn t ->
          %{
            url: "https://twitter.com/#{t.author.username}/status/#{t.id}",
            id: t.id
          }
        end)

      {:error, _} -> []
    end
  end
end
```

### 5.2 Alternative: Curated Tweet Lists (No API Cost)

If X API costs are a concern, maintain curated lists of influential crypto accounts and use their recent tweets:
- Store a list of 50-100 influential crypto Twitter accounts
- Use free RSS-to-Twitter bridges (like Nitter instances) to get recent tweets
- Match tweets to article topics by keyword

---

## 6. Author Persona System

### 6.1 Author Personas

Create 5-8 User accounts in the database as "staff writers". Each has a distinct voice variation within the overall Blockster editorial direction.

```elixir
defmodule BlocksterV2.ContentAutomation.AuthorRotator do
  @personas [
    %{
      username: "jake_freeman",
      email: "jake@blockster.com",
      bio: "Bitcoin maximalist turned pragmatic crypto advocate. Former TradFi analyst.",
      style: "Data-driven, uses market analogies. Focuses on macro/trading/investment.",
      categories: [:trading, :macro_trends, :investment, :bitcoin]
    },
    %{
      username: "maya_chen",
      email: "maya@blockster.com",
      bio: "DeFi degen with a compliance background. Sees both sides, picks freedom.",
      style: "Technical but accessible. Explains DeFi mechanics. Sarcastic about regulators.",
      categories: [:defi, :regulation, :stablecoins, :rwa]
    },
    %{
      username: "alex_ward",
      email: "alex@blockster.com",
      bio: "Privacy advocate and self-custody evangelist. Cypherpunk at heart.",
      style: "Passionate about privacy. Uses historical parallels. Warns about surveillance.",
      categories: [:privacy, :cbdc, :security_hacks, :adoption]
    },
    %{
      username: "sophia_reyes",
      email: "sophia@blockster.com",
      bio: "Web3 gaming and NFT specialist. Believes in the metaverse (unironically).",
      style: "Enthusiastic about innovation. Pop culture references. Younger voice.",
      categories: [:gaming, :nft, :token_launches, :ai_crypto]
    },
    %{
      username: "marcus_stone",
      email: "marcus@blockster.com",
      bio: "Reformed Wall Street trader. Now full-time crypto. Never going back.",
      style: "Sharp, confident takes. Loves contrarian positions. Uses trader slang.",
      categories: [:trading, :altcoins, :investment, :gambling]
    }
  ]

  def select_author_for_topic(category) do
    # Find personas that cover this category
    matching = Enum.filter(@personas, fn p -> category in p.categories end)

    # Rotate to avoid same author publishing too many in a row
    # Track last 5 publications, prefer least-recently-used
    Enum.random(matching)  # Simple version; production uses LRU
  end
end
```

### 6.2 Author Account Setup

One-time setup: Create User records in PostgreSQL for each persona.

**IMPORTANT**: `Accounts.create_user/1` does not exist. User creation requires:
- `wallet_address` (required field — generate a deterministic address per persona)
- `auth_method` must be `"email"` (only `"wallet"` and `"email"` are valid)
- Use `Repo.insert/1` directly since no public create function exists

```elixir
# One-time seed script (run via `mix run priv/repo/seeds/content_authors.exs`)
alias BlocksterV2.Repo
alias BlocksterV2.Accounts.User

for persona <- BlocksterV2.ContentAutomation.AuthorRotator.personas() do
  # Generate deterministic wallet address from persona email (not a real wallet)
  wallet_hash = :crypto.hash(:sha256, persona.email) |> Base.encode16(case: :lower)
  fake_wallet = "0x" <> String.slice(wallet_hash, 0, 40)

  changeset = User.changeset(%User{}, %{
    email: persona.email,
    wallet_address: fake_wallet,
    auth_method: "email",
    is_admin: false
  })

  case Repo.insert(changeset) do
    {:ok, user} ->
      IO.puts("Created author: #{persona.username} (user_id: #{user.id})")
    {:error, changeset} ->
      IO.puts("Skipped #{persona.username}: #{inspect(changeset.errors)}")
  end
end
```

**Note**: These users have fake wallet addresses and cannot log in or receive tokens.
They exist solely as `author_id` references for automated posts.

---

## 7. Content Publishing Pipeline

### 7.1 ContentPublisher

```elixir
defmodule BlocksterV2.ContentAutomation.ContentPublisher do
  alias BlocksterV2.Blog
  alias BlocksterV2.EngagementTracker

  # BUX rewards scale with article length — longer reads = more reward for readers
  # base_bux_reward is multiplied by user's engagement_score/10, user_multiplier, and geo_multiplier
  # So base_reward of 5 with a 3x multiplier user at full engagement = 15 BUX per read
  # Pool must cover hundreds of readers + share rewards
  @bux_per_minute_read 2     # ~2 base BUX per minute of reading time
  @bux_pool_multiplier 500   # Pool = base_reward * 500 (covers ~500 full-engagement reads)
  @min_bux_reward 1          # Minimum base reward (very short articles)
  @max_bux_reward 10         # Cap base reward (keeps multiplied rewards reasonable)
  @min_bux_pool 1000         # Minimum pool size (must cover many readers)

  def publish_article(article, author_user_id, opts \\ []) do
    category_id = resolve_category(article.category)
    hub_id = resolve_hub(article.category)

    # Calculate BUX reward based on article length
    # Average reading speed ~250 wpm, so word_count/250 = estimated read minutes
    # base_bux_reward is then multiplied by user's engagement + multipliers (see EngagementTracker)
    word_count = count_words_in_tiptap(article.content)
    read_minutes = max(1, word_count / 250)
    bux_reward = trunc(read_minutes * @bux_per_minute_read)
                 |> max(@min_bux_reward)
                 |> min(@max_bux_reward)
    bux_pool = max(@min_bux_pool, bux_reward * @bux_pool_multiplier)

    # 1. Create the post
    {:ok, post} = Blog.create_post(%{
      title: article.title,
      content: article.content,        # TipTap JSON
      excerpt: article.excerpt,
      featured_image: article.featured_image,
      author_id: author_user_id,
      category_id: category_id,
      hub_id: hub_id,
      base_bux_reward: bux_reward
    })

    # 2. Add tags
    if article.tags && article.tags != [] do
      Blog.update_post_tags(post, article.tags)
    end

    # 3. Publish immediately (set published_at)
    {:ok, post} = Blog.publish_post(post)

    # 4. Assign BUX pool (scales with article length)
    # CORRECT function: deposit_post_bux/2 (NOT set_post_bux_pool which doesn't exist)
    # Delegates to PostBuxPoolWriter for serialized writes
    EngagementTracker.deposit_post_bux(post.id, bux_pool)

    # 5. Notify SortedPostsCache to include new post
    # CORRECT function: reload/0 (NOT refresh/0 which doesn't exist)
    # Alternative: SortedPostsCache.add_post/5 for single-post insertion
    BlocksterV2.SortedPostsCache.reload()

    {:ok, post}
  end

  defp resolve_category(topic_category) do
    # Map topic categories to existing Blockster categories
    category_map = %{
      defi: "defi",
      regulation: "regulation",
      trading: "markets",
      bitcoin: "bitcoin",
      ethereum: "ethereum",
      # ... etc
    }

    slug = Map.get(category_map, topic_category, "news")
    case Blog.get_category_by_slug(slug) do
      nil ->
        {:ok, cat} = Blog.create_category(%{name: slug, slug: slug})
        cat.id
      cat -> cat.id
    end
  end

  # Extract plain text from TipTap JSON and count words
  defp count_words_in_tiptap(%{"type" => "doc", "content" => nodes}) do
    nodes
    |> extract_text_nodes()
    |> Enum.join(" ")
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end

  defp count_words_in_tiptap(_), do: 0

  defp extract_text_nodes(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, fn
      %{"type" => "text", "text" => text} -> [text]
      %{"content" => children} -> extract_text_nodes(children)
      _ -> []
    end)
  end
end
```

**BUX Reward Examples by Article Length**:
| Article Length | Est. Read Time | base_bux_reward | bux_pool |
|---------------|---------------|-----------------|----------|
| 400 words (short take) | ~1.6 min | 3 | 1,500 |
| 600 words (standard) | ~2.4 min | 4 | 2,000 |
| 1000 words (deep dive) | ~4 min | 8 | 4,000 |
| 1500 words (analysis) | ~6 min | 10 (capped) | 5,000 |

*Note: A reader with 3x multiplier earning full engagement on a 4 BUX base article would earn ~12 BUX.
A pool of 2,000 BUX covers ~500 such reads or ~166 reads at max multiplier.*

### 7.2 Content Queue / Scheduler

Distributes posts evenly throughout the day:

```elixir
defmodule BlocksterV2.ContentAutomation.ContentQueue do
  use GenServer

  @posts_per_day 10
  # Publishing window: 12:00 - 04:00 UTC (= 7am-11pm EST / 4am-8pm PST)
  # Covers US morning through late evening when crypto audience is most active
  @publish_start_hour 12       # 12:00 UTC = 7am EST
  @publish_end_hour 28         # 04:00 UTC next day (28 = 24 + 4)
  @min_gap_minutes 60          # At least 1 hour between posts

  # Queue holds generated articles waiting to be published
  # Publishes at calculated intervals throughout the day
  # Uses GlobalSingleton for cluster-wide single instance

  def start_link(opts) do
    case BlocksterV2.GlobalSingleton.start_link(__MODULE__, opts) do
      {:ok, pid} -> {:ok, pid}
      {:already_registered, _pid} -> :ignore
    end
  end

  def schedule_next_publish do
    current_hour = DateTime.utc_now().hour
    # Normalize to 0-28 range (hours past midnight can be 24-28)
    effective_hour = if current_hour < @publish_start_hour and current_hour < 4, do: current_hour + 24, else: current_hour

    hours_remaining = @publish_end_hour - effective_hour
    posts_remaining = @posts_per_day - posts_published_today()

    in_window = effective_hour >= @publish_start_hour and effective_hour < @publish_end_hour

    if posts_remaining > 0 and hours_remaining > 0 and in_window do
      gap_minutes = max(@min_gap_minutes, (hours_remaining * 60) / posts_remaining)
      Process.send_after(self(), :publish_next, trunc(gap_minutes * 60 * 1000))
    end
  end
end
```

---

## 8. Featured Images

### 8.1 Strategy

Three options (in order of preference):

1. **Unsplash API** (free): Search by article topic keywords, get high-quality stock photos
2. **AI Image Generation**: Use DALL-E or Stability AI to generate unique thumbnails
3. **ImageKit Overlays**: Take a base image and add text overlay with article title

```elixir
defmodule BlocksterV2.ContentAutomation.ImageFinder do
  @unsplash_url "https://api.unsplash.com/search/photos"

  def find_featured_image(search_query) do
    case Req.get(@unsplash_url,
      params: %{query: search_query, per_page: 1, orientation: "landscape"},
      headers: [{"Authorization", "Client-ID #{unsplash_key()}"}]
    ) do
      {:ok, %{body: %{"results" => [first | _]}}} ->
        {:ok, first["urls"]["regular"]}
      _ ->
        {:ok, default_image_for_category()}
    end
  end
end
```

---

## 9. Database Changes

### 9.1 PostgreSQL Tables (Pipeline Data)

All pipeline data lives in PostgreSQL. Feed items, generated topics, and the publish queue
contain text-heavy records that don't need real-time distributed access — they're write-once,
process-once data that flows through the pipeline and eventually becomes a published post.

**Section 2.4** has the `content_feed_items` migration. The remaining tables:

```elixir
# priv/repo/migrations/YYYYMMDDHHMMSS_create_content_generated_topics.exs
defmodule BlocksterV2.Repo.Migrations.CreateContentGeneratedTopics do
  use Ecto.Migration

  def change do
    create table(:content_generated_topics, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :category, :string
      add :source_urls, {:array, :string}, default: []
      add :rank_score, :float
      add :source_count, :integer
      add :article_id, references(:posts, on_delete: :nilify_all)
      add :author_id, references(:users, on_delete: :nilify_all)
      add :pipeline_id, :binary_id
      add :published_at, :utc_datetime

      timestamps()
    end

    create index(:content_generated_topics, [:category])
    create index(:content_generated_topics, [:inserted_at])
    create index(:content_generated_topics, [:pipeline_id])
  end
end

# priv/repo/migrations/YYYYMMDDHHMMSS_create_content_publish_queue.exs
defmodule BlocksterV2.Repo.Migrations.CreateContentPublishQueue do
  use Ecto.Migration

  def change do
    create table(:content_publish_queue, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :article_data, :map, null: false          # TipTap JSON, title, excerpt, tags, etc.
      add :author_id, references(:users, on_delete: :nilify_all)
      add :scheduled_at, :utc_datetime
      add :status, :string, default: "pending"       # pending, draft, approved, published, rejected
      add :pipeline_id, :binary_id
      add :topic_id, references(:content_generated_topics, type: :binary_id, on_delete: :nilify_all)
      add :post_id, references(:posts, on_delete: :nilify_all)
      add :rejected_reason, :text
      add :reviewed_at, :utc_datetime
      add :reviewed_by, references(:users, on_delete: :nilify_all)

      timestamps()
    end

    create index(:content_publish_queue, [:status])
    create index(:content_publish_queue, [:scheduled_at])
    create index(:content_publish_queue, [:pipeline_id])
  end
end
```

**FeedStore module** (`lib/blockster_v2/content_automation/feed_store.ex`) wraps all Ecto
queries for the pipeline tables:

```elixir
defmodule BlocksterV2.ContentAutomation.FeedStore do
  alias BlocksterV2.Repo
  import Ecto.Query

  # ── Feed Items ──

  def store_new_items(items) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    entries = Enum.map(items, fn item ->
      Map.merge(item, %{inserted_at: now, updated_at: now})
    end)

    Repo.insert_all(ContentFeedItem, entries,
      on_conflict: :nothing,        # Skip duplicates (unique URL index)
      conflict_target: :url
    )
  end

  def get_recent_unprocessed(opts) do
    hours = Keyword.get(opts, :hours, 12)
    cutoff = DateTime.utc_now() |> DateTime.add(-hours, :hour)

    from(f in ContentFeedItem,
      where: f.processed == false and f.fetched_at >= ^cutoff,
      order_by: [desc: f.published_at],
      limit: 50
    )
    |> Repo.all()
  end

  def mark_items_processed(urls, topic_id) do
    from(f in ContentFeedItem, where: f.url in ^urls)
    |> Repo.update_all(set: [processed: true, topic_cluster_id: topic_id])
  end

  def count_published_today do
    today_start = Date.utc_today() |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    from(q in ContentPublishQueue,
      where: q.status == "published" and q.updated_at >= ^today_start
    )
    |> Repo.aggregate(:count)
  end

  def count_queued do
    from(q in ContentPublishQueue, where: q.status in ["pending", "draft", "approved"])
    |> Repo.aggregate(:count)
  end

  def get_today_category_counts do
    today_start = Date.utc_today() |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    from(t in ContentGeneratedTopic,
      where: t.inserted_at >= ^today_start and not is_nil(t.article_id),
      group_by: t.category,
      select: {t.category, count(t.id)}
    )
    |> Repo.all()
    |> Map.new()
  end

  def get_generated_topic_titles(opts) do
    days = Keyword.get(opts, :days, 7)
    cutoff = DateTime.utc_now() |> DateTime.add(-days, :day)

    from(t in ContentGeneratedTopic,
      where: t.inserted_at >= ^cutoff,
      select: t.title
    )
    |> Repo.all()
  end

  # ── Queue ──

  def get_queue_entry(id), do: Repo.get(ContentPublishQueue, id)

  def get_pending_queue_entries do
    from(q in ContentPublishQueue,
      where: q.status in ["pending", "draft"],
      order_by: [desc: q.inserted_at],
      preload: [:author]
    )
    |> Repo.all()
  end

  def update_queue_entry(id, attrs) do
    Repo.get!(ContentPublishQueue, id)
    |> Ecto.Changeset.change(attrs)
    |> Repo.update()
  end

  def mark_queue_entry_published(id, post_id) do
    Repo.get!(ContentPublishQueue, id)
    |> Ecto.Changeset.change(%{status: "published", post_id: post_id, reviewed_at: DateTime.utc_now()})
    |> Repo.update()
  end

  # ── Cleanup ──

  def cleanup_old_records do
    seven_days_ago = DateTime.utc_now() |> DateTime.add(-7, :day)
    forty_eight_hours_ago = DateTime.utc_now() |> DateTime.add(-48, :hour)

    # Delete feed items older than 7 days
    from(f in ContentFeedItem, where: f.fetched_at < ^seven_days_ago)
    |> Repo.delete_all()

    # Delete completed/rejected queue entries older than 48 hours
    from(q in ContentPublishQueue,
      where: q.status in ["published", "rejected"] and q.updated_at < ^forty_eight_hours_ago
    )
    |> Repo.delete_all()
  end
end
```

### 9.2 Mnesia Table (Admin Settings Only)

Only the admin settings table uses Mnesia — it's small, frequently read, and benefits from
real-time access across cluster nodes:

```elixir
# In MnesiaInitializer — add to @tables list
:mnesia.create_table(:content_automation_settings, [
  attributes: [:key, :value, :updated_at, :updated_by],
  disc_copies: [node()]
])
```

This stores: `posts_per_day`, `category_config`, `keyword_boosts`, `keyword_blocks`, `paused`.
See Section 3.1 for the full settings schema.

### 9.3 Two-Phase Processing

**CRITICAL**: Mark feed items as `processed: true` AFTER the topic is successfully stored
in `content_generated_topics`, not before. This prevents data loss if the process crashes
between marking and storing:

```elixir
# In TopicEngine, after clustering:
def store_topic_and_mark_processed(topic, source_item_urls) do
  Repo.transaction(fn ->
    # 1. Store topic first
    {:ok, stored_topic} = Repo.insert(%ContentGeneratedTopic{
      id: Ecto.UUID.generate(),
      title: topic.title,
      category: to_string(topic.category),
      source_urls: source_item_urls,
      rank_score: topic.rank_score,
      source_count: topic.source_count,
      pipeline_id: topic.pipeline_id
    })

    # 2. Only THEN mark source items as processed
    FeedStore.mark_items_processed(source_item_urls, stored_topic.id)

    stored_topic
  end)
end
```

Using `Repo.transaction/1` ensures both operations succeed or both roll back — no orphaned state.

### 9.4 Pipeline Traceability

Every article gets a `pipeline_id` (UUID) assigned at the start of content generation.
This ID flows through all stages:

```
TopicEngine (creates pipeline_id)
  → ContentGenerator (passes pipeline_id)
    → TweetFinder (logs pipeline_id)
      → ImageFinder (logs pipeline_id)
        → QualityChecker (logs pipeline_id)
          → ContentPublisher (stores pipeline_id in content_generated_topics)
```

All log messages include `pipeline=<id>` for end-to-end debugging:
```elixir
Logger.info("[ContentGenerator] pipeline=#{pipeline_id} generating article for topic=#{topic.title}")
```

### 9.5 Existing Posts Table

Posts use the existing `posts` table with all needed fields. Author personas are regular User records.
No changes to existing PostgreSQL schema — only new tables added.

---

## 10. Configuration

### 10.1 Application Config

**IMPORTANT**: Read config from `Application.get_env/3` at runtime, not module attributes.
Module attributes are compiled once and don't pick up runtime config changes.

```elixir
# config/runtime.exs
config :blockster_v2, :content_automation,
  enabled: System.get_env("CONTENT_AUTOMATION_ENABLED", "false") == "true",
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  x_bearer_token: System.get_env("X_BEARER_TOKEN"),
  unsplash_access_key: System.get_env("UNSPLASH_ACCESS_KEY"),
  posts_per_day: String.to_integer(System.get_env("CONTENT_POSTS_PER_DAY", "10")),
  content_model: System.get_env("CONTENT_CLAUDE_MODEL", "claude-opus-4-6"),
  topic_model: System.get_env("TOPIC_CLAUDE_MODEL", "claude-haiku-4-5-20251001"),
  feed_poll_interval: :timer.minutes(5),
  topic_analysis_interval: :timer.minutes(15)
```

**Model choices**:
- **Content generation**: `claude-opus-4-6` — best quality for opinionated editorial writing,
  nuanced counter-narrative framing, and voice consistency. Worth the cost for 10 articles/day.
- **Topic clustering**: `claude-haiku-4-5-20251001` — fast and cheap for deterministic grouping/ranking.

```elixir
# In each module — read config at runtime via helper
defmodule BlocksterV2.ContentAutomation.Config do
  def get(key, default \\ nil) do
    Application.get_env(:blockster_v2, :content_automation, [])
    |> Keyword.get(key, default)
  end

  def enabled?, do: get(:enabled, false)
  def anthropic_api_key, do: get(:anthropic_api_key)
  def content_model, do: get(:content_model, "claude-opus-4-6")
  def topic_model, do: get(:topic_model, "claude-haiku-4-5-20251001")
  def posts_per_day, do: get(:posts_per_day, 10)
  def feed_poll_interval, do: get(:feed_poll_interval, :timer.minutes(5))
end
```

### 10.2 Required Environment Variables / Fly Secrets

```bash
flyctl secrets set \
  CONTENT_AUTOMATION_ENABLED=true \
  ANTHROPIC_API_KEY=sk-ant-... \
  X_BEARER_TOKEN=AAAA... \
  UNSPLASH_ACCESS_KEY=... \
  CONTENT_POSTS_PER_DAY=10 \
  CONTENT_CLAUDE_MODEL=claude-opus-4-6 \
  TOPIC_CLAUDE_MODEL=claude-haiku-4-5-20251001 \
  --app blockster-v2
```

---

## 11. Cost Estimates

| Service | Usage | Monthly Cost |
|---------|-------|-------------|
| Claude Opus 4.6 (content) | 10 articles/day × 30 = 300 calls, ~500 tokens in / ~2000 out each | ~$60-90 |
| Claude Haiku (topic analysis) | 96 calls/day (every 15 min) × 30 = 2,880 calls | ~$3-5 |
| X API (tweets) | Basic tier, ~300 searches/month | $100 |
| Unsplash | Free tier (50 req/hour) | $0 |
| **Total** | | **~$165-195/month** |

**Alternative without X API**: Use curated tweet list approach → **$65-95/month total**

*Opus is ~5-6x more expensive than Sonnet per token, but the quality improvement for
opinionated editorial content is substantial. Can downgrade to Sonnet via config if needed.*

---

## 12. Supervision Tree Integration

```elixir
# In application.ex, add to genserver_children list (conditionally enabled):
content_automation_children =
  if Application.get_env(:blockster_v2, :content_automation, [])[:enabled] do
    [
      {BlocksterV2.ContentAutomation.FeedPoller, []},
      {BlocksterV2.ContentAutomation.TopicEngine, []},
      {BlocksterV2.ContentAutomation.ContentQueue, []}
    ]
  else
    []
  end

# Merge into existing children list
children = base_children ++ genserver_children ++ content_automation_children
```

All GenServers use `GlobalSingleton` for cluster-wide single instance (same pattern as PriceTracker, BetSettler).

**Feature Flag**: When `CONTENT_AUTOMATION_ENABLED=false` (default), no content automation
GenServers start. This allows safe deployment with the code in place before activating.

---

## 13. Implementation Phases

### Phase 1: RSS Infrastructure (2-3 days)
- [ ] Add `fast_rss` to mix.exs
- [ ] Create Config module (Application config reader)
- [ ] Create Ecto migrations (content_feed_items, content_generated_topics, content_publish_queue)
- [ ] Create Ecto schemas (ContentFeedItem, ContentGeneratedTopic, ContentPublishQueue)
- [ ] Create FeedStore module (Ecto queries for all pipeline tables)
- [ ] Create FeedPoller GenServer (with GlobalSingleton)
- [ ] Add `content_automation_settings` to MnesiaInitializer @tables
- [ ] Configure feed URLs (28 feeds, 2 tiers)
- [ ] Test feed polling, storage, and blocked-feed handling
- [ ] Add to supervision tree (behind CONTENT_AUTOMATION_ENABLED feature flag)

### Phase 2: Topic Engine (2-3 days)
- [ ] Create TopicEngine GenServer (with GlobalSingleton)
- [ ] Implement Claude Haiku topic clustering (structured output via tool_use)
- [ ] Add pre-filtering (6-12 hour window, truncate summaries, cap at 50 items)
- [ ] Add category classification
- [ ] Implement deduplication (don't cover same topic twice)
- [ ] Implement two-phase processing (store topic THEN mark items processed)
- [ ] Test topic ranking and selection

### Phase 3: Content Generation (3-4 days)
- [ ] Create ContentGenerator module (not GenServer — stateless)
- [ ] Implement Claude Opus integration with structured output (tool_use)
- [ ] Build editorial voice prompt with content safety guardrails
- [ ] Create TipTapBuilder with all node types (paragraph, heading, blockquote, bulletList, orderedList, listItem, image, spacer, horizontalRule)
- [ ] Implement parse_inline_marks (bold, italic, links)
- [ ] Implement QualityChecker (word count, structure, duplicate, tags, TipTap validation)
- [ ] Test full generation pipeline with pipeline_id traceability

### Phase 4: Author Personas (1 day)
- [ ] Create AuthorRotator module with 5 personas
- [ ] Create seed script (`priv/repo/seeds/content_authors.exs`)
- [ ] Create User accounts with Repo.insert (fake wallet addresses, auth_method: "email")
- [ ] Generate/upload avatar images
- [ ] Test author selection and rotation

### Phase 5: Publishing Pipeline (2-3 days)
- [ ] Create ContentPublisher module
- [ ] Implement BUX pool assignment via `EngagementTracker.deposit_post_bux/2`
- [ ] Implement word-count-based BUX reward scaling
- [ ] Create ContentQueue with US-hours scheduling (12:00-04:00 UTC)
- [ ] Implement SortedPostsCache.reload() after publish
- [ ] Test end-to-end: RSS → topic → generate → publish
- [ ] Verify posts appear correctly on frontend

### Phase 6: Tweet Integration (2 days)
- [ ] Create TweetFinder module (processes tweet_suggestions from ContentGenerator)
- [ ] Integrate X API (or curated list alternative)
- [ ] Insert tweet nodes into TipTap content post-generation
- [ ] Test tweet rendering in published posts

### Phase 7: Featured Images (1 day)
- [ ] Create ImageFinder module (Unsplash integration)
- [ ] Map categories to fallback images
- [ ] Test image attachment to posts

### Phase 8: Monitoring & Polish (2 days)
- [ ] Add pipeline_id logging throughout all modules
- [ ] Implement PostgreSQL cleanup task (7 days feed items, 48h completed queue)
- [ ] Create admin dashboard page at `/admin/content-automation`
- [ ] Add manual override controls (pause, force publish, reject topic)
- [ ] Add pipeline health monitoring (log daily: articles generated, published, rejected, errors)
- [ ] Load testing (simulate 20+ posts/day)
- [ ] Documentation

**Total estimated time: 15-19 days**

---

## 14. Quality Control Checks

Before publishing, each article must pass:

1. **Word count**: 350-1200 words (standard 400-500, premium deep-dives 700-1000)
2. **Originality**: No sentences copied verbatim from source articles
3. **Structure**: Has title, excerpt, at least 3 paragraphs, proper TipTap JSON
4. **No hallucinations**: Key facts (prices, dates, names) cross-referenced with source material
5. **Tone check**: Matches editorial voice (not too neutral, not too extreme)
6. **Duplicate check**: Title and topic not too similar to posts from last 7 days
7. **Tag count**: 2-5 tags per article
8. **Image present**: Featured image URL is valid

```elixir
defmodule BlocksterV2.ContentAutomation.QualityChecker do
  def validate(article) do
    checks = [
      {:word_count, check_word_count(article)},
      {:structure, check_structure(article)},
      {:duplicate, check_not_duplicate(article)},
      {:tags, check_tags(article)},
      {:tiptap_valid, check_tiptap_format(article.content)}
    ]

    failures = Enum.filter(checks, fn {_, result} -> result != :ok end)

    if Enum.empty?(failures) do
      :ok
    else
      {:reject, failures}
    end
  end
end
```

---

## 15. Admin Dashboard — Content Automation

### 15.1 Overview & Design Philosophy

The admin dashboard is the editorial control center. The key insight: **articles should NOT
auto-publish without admin review**. The pipeline generates articles into a review queue, and
the admin approves, edits, or rejects them before they go live.

This leverages the existing post editing infrastructure:
- Same TipTap editor (with all formatting, image upload, tweet embedding)
- Same form component (tags, categories, featured image, BUX pool)
- Same admin auth (`AdminAuth` hook, `is_admin` check)
- Same S3 upload flow for images

### 15.2 Routes

```elixir
# In router.ex, inside the :admin live_session
live "/admin/content", ContentAutomationLive.Dashboard, :index
live "/admin/content/queue", ContentAutomationLive.Queue, :index
live "/admin/content/queue/:id/edit", ContentAutomationLive.EditArticle, :edit
live "/admin/content/feeds", ContentAutomationLive.Feeds, :index
live "/admin/content/history", ContentAutomationLive.History, :index
live "/admin/content/authors", ContentAutomationLive.Authors, :index
```

### 15.3 Dashboard Page (`/admin/content`)

The main landing page shows pipeline health at a glance.

```
┌─────────────────────────────────────────────────────────────────────┐
│  Content Automation                              [Pause Pipeline ▼] │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌────────────┐ │
│  │  PENDING      │ │  PUBLISHED   │ │  REJECTED    │ │  FEEDS     │ │
│  │  REVIEW       │ │  TODAY       │ │  TODAY       │ │  ACTIVE    │ │
│  │              │ │              │ │              │ │            │ │
│  │     4        │ │     7        │ │     1        │ │   22/28    │ │
│  │              │ │              │ │              │ │            │ │
│  │  [View Queue]│ │  [View All]  │ │              │ │ [Manage]   │ │
│  └──────────────┘ └──────────────┘ └──────────────┘ └────────────┘ │
│                                                                     │
│  ── Recent Queue (newest first) ──────────────────── [View All →]  │
│                                                                     │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │ ● "SEC's Latest DeFi Crackdown Misses the Point"              │ │
│  │   by maya_chen · regulation · 3 min ago · 620 words           │ │
│  │   Sources: Bloomberg (premium), CoinDesk                      │ │
│  │   [Edit & Review]  [Quick Approve]  [Reject]                  │ │
│  ├────────────────────────────────────────────────────────────────┤ │
│  │ ● "Bitcoin Miners Are Quietly Winning the Energy Debate"      │ │
│  │   by jake_freeman · bitcoin · 18 min ago · 480 words         │ │
│  │   Sources: Bitcoin Magazine, Bitcoinist                       │ │
│  │   [Edit & Review]  [Quick Approve]  [Reject]                  │ │
│  ├────────────────────────────────────────────────────────────────┤ │
│  │ ● "The Metaverse Isn't Dead — It Just Moved On-Chain"         │ │
│  │   by sophia_reyes · gaming · 45 min ago · 510 words           │ │
│  │   Sources: Decrypt, The Defiant                               │ │
│  │   [Edit & Review]  [Quick Approve]  [Reject]                  │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  ── Pipeline Activity (last 24h) ─────────────────────────────────  │
│                                                                     │
│  12:04 UTC  ✓ Published "Why the Fed's Rate Pause Changes Nothing" │
│  11:52 UTC  ⏳ Generated "SEC's Latest DeFi Crackdown..." → queue  │
│  11:45 UTC  ✕ Rejected "Crypto Market Update" (duplicate topic)    │
│  11:30 UTC  📡 FeedPoller: 42 new items from 22 feeds              │
│  11:15 UTC  🔍 TopicEngine: clustered 8 topics, selected 3        │
│  10:02 UTC  ✓ Published "Stablecoin Wars Heat Up..."              │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**LiveView Implementation**:
```elixir
defmodule BlocksterV2Web.ContentAutomationLive.Dashboard do
  use BlocksterV2Web, :live_view

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to pipeline events for live updates
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "content_automation")
    end

    socket =
      socket
      |> assign(page_title: "Content Automation")
      |> assign(pipeline_paused: ContentAutomation.Config.paused?())
      |> start_async(:load_stats, fn -> load_dashboard_stats() end)
      |> start_async(:load_queue, fn -> load_recent_queue(limit: 5) end)
      |> start_async(:load_activity, fn -> load_activity_log(limit: 20) end)

    {:ok, socket}
  end

  # Live updates when pipeline generates/publishes articles
  def handle_info({:content_automation, :article_generated, article}, socket) do
    # Prepend to queue list, bump pending count
  end

  def handle_info({:content_automation, :article_published, article}, socket) do
    # Move from queue to published, bump published count
  end
end
```

**Key Features**:
- **Live-updating stats cards**: pending, published today, rejected today, active feeds
- **Recent queue preview**: Shows newest queued articles with one-click actions
- **Activity log**: Scrollable timeline of all pipeline events (polls, topics, generations, publishes)
- **Pause/Resume toggle**: Stops ContentQueue from auto-publishing (articles still generate into queue)
- PubSub subscription means the dashboard updates in real-time as articles flow through

### 15.4 Queue Page (`/admin/content/queue`)

The full review queue with filtering and bulk actions.

```
┌─────────────────────────────────────────────────────────────────────┐
│  Article Queue                     Filter: [All ▼] [All Authors ▼] │
│  4 articles pending review            Sort: [Newest First ▼]       │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │                                                                │ │
│  │  ┌──────────┐  "SEC's Latest DeFi Crackdown Misses           │ │
│  │  │          │   the Point"                                    │ │
│  │  │ featured │                                                  │ │
│  │  │  image   │   maya_chen · regulation · 620 words · 2.4 min  │ │
│  │  │ preview  │   Tags: sec, defi, regulation                   │ │
│  │  │          │   BUX: 4 base / 2,000 pool                     │ │
│  │  └──────────┘   Sources: Bloomberg ⭐, CoinDesk               │ │
│  │                  Pipeline: abc-123 · Generated 3 min ago       │ │
│  │                                                                │ │
│  │  Excerpt: The SEC thinks it can regulate code. DeFi builders  │ │
│  │  have a different opinion — and the math is on their side.    │ │
│  │                                                                │ │
│  │  ┌─────────────────────────────────────────────────────────┐  │ │
│  │  │ Preview (collapsed, click to expand)                     │  │ │
│  │  │                                                          │  │ │
│  │  │ The SEC just dropped another enforcement action against  │  │ │
│  │  │ a DeFi protocol, and if you're experiencing déjà vu,    │  │ │
│  │  │ you're not alone...                                      │  │ │
│  │  │                                                          │  │ │
│  │  │ ## The Numbers Don't Lie                                 │  │ │
│  │  │ Despite the SEC's best efforts, DeFi TVL has grown 40%  │  │ │
│  │  │ year-over-year...                                        │  │ │
│  │  │ [Show more ▼]                                            │  │ │
│  │  └─────────────────────────────────────────────────────────┘  │ │
│  │                                                                │ │
│  │  [✏️ Edit Full Article]  [✓ Approve & Publish]  [✕ Reject]    │ │
│  │                                                                │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                     │
│  ┌────────────────────────────────────────────────────────────────┐ │
│  │  (next article card...)                                        │ │
│  └────────────────────────────────────────────────────────────────┘ │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**Queue Card Features**:
- **Featured image thumbnail**: Shows the Unsplash image (or placeholder if missing)
- **Metadata bar**: Author persona, category, word count, estimated read time
- **Source badges**: Feed sources that contributed, with star icon for premium sources
- **Pipeline ID**: For debugging, links to logs
- **BUX info**: Base reward and pool size (calculated from word count)
- **Excerpt**: First 2 lines of the article
- **Expandable preview**: Rendered HTML preview of the full article (uses TipTapRenderer)
- **Three actions**:
  - **Edit Full Article** → navigates to `/admin/content/queue/:id/edit`
  - **Approve & Publish** → publishes immediately (creates post, assigns BUX, updates cache)
  - **Reject** → removes from queue with optional reason (stored in activity log)

**Quick Approve** publishes the article as-is. Use this when the AI output is good enough.
Most of the time you'll use **Edit Full Article** to review and tweak before publishing.

### 15.5 Edit Article Page (`/admin/content/queue/:id/edit`)

This is the key page — **reuses the existing post form component** with the TipTap editor,
but loads from the `content_publish_queue` table instead of the `posts` table.

```
┌─────────────────────────────────────────────────────────────────────┐
│  [← Back to Queue]                  [Save Draft]  [Publish Now]    │
├──────────────────┬──────────────────────────────────────────────────┤
│                  │                                                  │
│  FEATURED IMAGE  │  Title                                          │
│  ┌────────────┐  │  ┌──────────────────────────────────────────┐   │
│  │            │  │  │ SEC's Latest DeFi Crackdown Misses the   │   │
│  │  [click to │  │  │ Point                                    │   │
│  │   change]  │  │  └──────────────────────────────────────────┘   │
│  │            │  │                                                  │
│  │            │  │  Excerpt (SEO description)                      │
│  └────────────┘  │  ┌──────────────────────────────────────────┐   │
│  [Remove Image]  │  │ The SEC thinks it can regulate code.     │   │
│  [Upload New]    │  │ DeFi builders have a different opinion.  │   │
│                  │  └──────────────────────────────────────────┘   │
│  AUTHOR          │                                                  │
│  maya_chen    ▼  │  Category: regulation ▼   Hub: [none] ▼        │
│                  │                                                  │
│  TAGS            │  ─── Article Content ───────────────────────    │
│  ┌────────────┐  │                                                  │
│  │ ✕ sec      │  │  ┌──────────────────────────────────────────┐   │
│  │ ✕ defi     │  │  │ B I U S ~ 🔗 H1 H2 H3 "" 📷 🐦 ── ⋮ │   │
│  │ ✕ regulat..│  │  ├──────────────────────────────────────────┤   │
│  └────────────┘  │  │                                          │   │
│  [+ Add tag]     │  │ The SEC just dropped another enforcement │   │
│                  │  │ action against a DeFi protocol, and if   │   │
│  BUX REWARD      │  │ you're experiencing déjà vu, you're not │   │
│  Base: 4         │  │ alone.                                   │   │
│  Pool: 2,000     │  │                                          │   │
│                  │  │ Even **Bloomberg** [acknowledged](url)   │   │
│  SOURCES         │  │ that the SEC's approach has done little  │   │
│  ⭐ Bloomberg    │  │ to slow DeFi adoption...                 │   │
│  • CoinDesk      │  │                                          │   │
│                  │  │ ## The Numbers Don't Lie                 │   │
│  PIPELINE        │  │                                          │   │
│  abc-123         │  │ Despite the SEC's best efforts, DeFi    │   │
│  3 min ago       │  │ TVL has grown 40% year-over-year...     │   │
│                  │  │                                          │   │
│                  │  │ > "Regulating DeFi is like regulating   │   │
│                  │  │ > math" — a sentiment echoed across the │   │
│                  │  │ > industry.                              │   │
│                  │  │                                          │   │
│                  │  │ 🐦 [Embedded Tweet]                     │   │
│                  │  │ ┌─────────────────────────────────────┐ │   │
│                  │  │ │ @VitalikButerin                     │ │   │
│                  │  │ │ Decentralized protocols are          │ │   │
│                  │  │ │ inherently global...                 │ │   │
│                  │  │ └─────────────────────────────────────┘ │   │
│                  │  │                                          │   │
│                  │  └──────────────────────────────────────────┘   │
│                  │                                                  │
└──────────────────┴──────────────────────────────────────────────────┘
```

**This IS the existing post form** — same component, same TipTap editor, same everything.
The only difference is where the data comes from and where it saves to.

**Implementation Pattern**:
```elixir
defmodule BlocksterV2Web.ContentAutomationLive.EditArticle do
  use BlocksterV2Web, :live_view

  def mount(%{"id" => queue_id}, _session, socket) do
    # Load from publish queue table
    queue_entry = FeedStore.get_queue_entry(queue_id)

    # Create a temporary Post struct to feed into the existing form component
    # The form component doesn't care where the data comes from
    post = %BlocksterV2.Blog.Post{
      title: queue_entry.article_data.title,
      content: queue_entry.article_data.content,      # TipTap JSON — loads into editor
      excerpt: queue_entry.article_data.excerpt,
      featured_image: queue_entry.article_data.featured_image,
      author_id: queue_entry.author_id,
      base_bux_reward: queue_entry.article_data.bux_reward
    }

    changeset = Blog.change_post(post)

    socket =
      socket
      |> assign(page_title: "Edit Article")
      |> assign(queue_id: queue_id)
      |> assign(queue_entry: queue_entry)
      |> assign(post: post)
      |> assign(form: to_form(changeset))
      |> assign(tags: queue_entry.article_data.tags || [])
      |> assign(source_feeds: queue_entry.article_data.source_feeds)
      |> assign(pipeline_id: queue_entry.pipeline_id)

    {:ok, socket}
  end

  # "Save Draft" — update the queue entry but don't publish
  def handle_event("save_draft", %{"post" => post_params}, socket) do
    FeedStore.update_queue_entry(socket.assigns.queue_id, %{
      article_data: merge_form_data(post_params),
      status: :draft
    })
    {:noreply, put_flash(socket, :info, "Draft saved")}
  end

  # "Publish Now" — create real post in PostgreSQL, delete from queue
  def handle_event("publish", %{"post" => post_params}, socket) do
    queue_entry = socket.assigns.queue_entry

    case ContentPublisher.publish_from_queue(queue_entry, post_params) do
      {:ok, post} ->
        FeedStore.mark_queue_entry_published(socket.assigns.queue_id, post.id)
        {:noreply,
         socket
         |> put_flash(:info, "Published: #{post.title}")
         |> push_navigate(to: ~p"/admin/content/queue")}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Publish failed: #{inspect(reason)}")}
    end
  end
end
```

**What the admin can do on this page** (all via the existing TipTap editor + form):

| Action | How | Component |
|--------|-----|-----------|
| **Edit title** | Click title input, type | Standard text input |
| **Edit excerpt** | Click excerpt textarea, type | Standard textarea |
| **Edit body text** | Click in TipTap editor, type | TipTap editor |
| **Bold/italic/underline** | Select text, click toolbar button (B/I/U) | TipTap toolbar |
| **Add heading** | Click H1/H2/H3 in toolbar | TipTap toolbar |
| **Add blockquote** | Click quote icon in toolbar | TipTap toolbar |
| **Add link** | Select text, click link icon, enter URL | TipTap link extension |
| **Add bullet/numbered list** | Click list icon in toolbar | TipTap StarterKit |
| **Add image inline** | Click image icon, upload or paste URL | TipTap ImageUpload extension |
| **Embed tweet** | Click tweet icon, paste tweet URL | TipTap TweetEmbed extension |
| **Add spacer/divider** | Click spacer icon in toolbar | TipTap Spacer extension |
| **Change featured image** | Click image in sidebar, upload new | FeaturedImageUpload hook + S3 |
| **Remove featured image** | Click "Remove Image" | Form event |
| **Change author** | Dropdown in sidebar (admin only) | Author autocomplete |
| **Change category** | Dropdown selector | Category select |
| **Add/remove tags** | Tag pills in sidebar with search | Tag autocomplete |
| **Adjust BUX reward** | Edit base reward number | Number input |
| **Save draft** | Top bar button — saves back to publish queue | Form event |
| **Publish** | Top bar button — creates real post in PostgreSQL | ContentPublisher |

### 15.6 Approve & Publish Flow

When the admin clicks **Approve & Publish** (from queue page) or **Publish Now** (from edit page):

```
Admin clicks "Publish"
  │
  ▼
ContentPublisher.publish_from_queue(queue_entry, edited_params)
  │
  ├─ 1. Blog.create_post(merged_attrs)           ← creates post in PostgreSQL
  │     - title, content (TipTap JSON), excerpt, featured_image
  │     - author_id, category_id, hub_id
  │     - base_bux_reward (from word count calc or admin override)
  │
  ├─ 2. Blog.update_post_tags(post, tags)         ← creates tag associations
  │
  ├─ 3. Blog.publish_post(post)                   ← sets published_at to now
  │
  ├─ 4. EngagementTracker.deposit_post_bux(       ← funds the BUX reward pool
  │        post.id, bux_pool)
  │
  ├─ 5. SortedPostsCache.reload()                 ← post appears on homepage
  │
  ├─ 6. FeedStore.mark_queue_published(            ← removes from queue,
  │        queue_id, post.id)                        stores post_id for reference
  │
  └─ 7. Broadcast {:content_automation,            ← dashboard updates live
           :article_published, article}
```

### 15.7 Reject Flow

When the admin clicks **Reject**:

```
┌─────────────────────────────┐
│  Reject Article              │
│                              │
│  Reason (optional):          │
│  ┌────────────────────────┐  │
│  │ Too similar to yester- │  │
│  │ day's regulation piece │  │
│  └────────────────────────┘  │
│                              │
│  [Cancel]  [Reject Article]  │
└─────────────────────────────┘
```

- Shows a small modal with optional reason text field
- Rejected articles move to `status: :rejected` in the queue (not deleted)
- Rejection reason and timestamp stored for pipeline tuning
- Activity log shows the rejection

### 15.8 Feeds Management Page (`/admin/content/feeds`)

```
┌─────────────────────────────────────────────────────────────────────┐
│  Feed Management                          Last poll: 2 min ago     │
│                                           [Force Poll Now]          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ── Premium Tier (2x weight) ──────────────────────────────────    │
│                                                                     │
│  │ Feed            │ Status    │ Last Items │ Last Poll  │ Toggle │ │
│  │─────────────────│───────────│────────────│────────────│────────│ │
│  │ Bloomberg       │ ✓ Active  │ 12 items   │ 2 min ago  │ [On]  │ │
│  │ TechCrunch      │ ✓ Active  │ 8 items    │ 2 min ago  │ [On]  │ │
│  │ CoinDesk ⭐     │ ✓ Active  │ 15 items   │ 2 min ago  │ [On]  │ │
│  │ The Block ⭐    │ ✓ Active  │ 6 items    │ 2 min ago  │ [On]  │ │
│  │ Blockworks ⭐   │ ✓ Active  │ 9 items    │ 2 min ago  │ [On]  │ │
│  │ DL News ⭐      │ ✓ Active  │ 4 items    │ 2 min ago  │ [On]  │ │
│  │ Reuters         │ ✕ Blocked │ 403 error  │ 2 min ago  │ [Off] │ │
│  │ FT              │ ✕ Blocked │ Paywall    │ 2 min ago  │ [Off] │ │
│  │ The Economist   │ ✕ Blocked │ 403 error  │ 2 min ago  │ [Off] │ │
│  │ Forbes          │ ✕ Blocked │ Cloudflare │ 2 min ago  │ [Off] │ │
│  │ Barron's        │ ✕ Blocked │ Paywall    │ 2 min ago  │ [Off] │ │
│  │ The Verge       │ ✕ Blocked │ 403 error  │ 2 min ago  │ [Off] │ │
│                                                                     │
│  ── Standard Tier (1x weight) ─────────────────────────────────    │
│                                                                     │
│  │ CoinTelegraph   │ ✓ Active  │ 20 items   │ 2 min ago  │ [On]  │ │
│  │ Decrypt         │ ✓ Active  │ 11 items   │ 2 min ago  │ [On]  │ │
│  │ (... 14 more)   │           │            │            │       │ │
│                                                                     │
│  Total: 22 active / 28 configured                                  │
│  Items in last 24h: 287                                            │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

- Toggle feeds on/off without code changes (stored in `content_automation_settings` Mnesia table)
- Shows last error for blocked feeds
- "Force Poll Now" triggers immediate poll cycle
- Star icon next to promoted crypto-native premium feeds

### 15.9 History Page (`/admin/content/history`)

Shows all published and rejected articles with performance metrics:

```
┌─────────────────────────────────────────────────────────────────────┐
│  Content History                 Filter: [All ▼]  [Last 7 days ▼]  │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  │ Title                     │ Author    │ Published  │ Reads │ BUX │
│  │───────────────────────────│───────────│────────────│───────│─────│
│  │ ✓ Why the Fed's Rate...   │ jake_free │ 12:04 UTC  │ 142   │ 568 │
│  │ ✓ Stablecoin Wars Heat... │ maya_chen │ 10:02 UTC  │ 89    │ 356 │
│  │ ✓ Bitcoin Mining Just...  │ alex_ward │ 08:15 UTC  │ 203   │ 812 │
│  │ ✕ Crypto Market Update    │ marcus_st │ rejected   │ -     │ -   │
│  │   Reason: duplicate topic │           │            │       │     │
│  │ ✓ The Metaverse Moves...  │ sophia_r  │ Yesterday  │ 67    │ 268 │
│                                                                     │
│  This week: 52 published, 8 rejected (87% approval rate)           │
│  Top category: regulation (14 articles)                             │
│  Most-read: "Bitcoin Mining Just Got Greener" (203 reads)          │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

- Links to the live post page (`/:slug`)
- Shows engagement metrics (reads, BUX distributed) from EngagementTracker
- Published articles link to the existing `/:slug/edit` page for further edits
- Rejected articles show the rejection reason

### 15.10 Pipeline State & Queue Statuses

The `content_publish_queue` PostgreSQL table (defined in Section 9.1) supports the review workflow
with these statuses:

```elixir
# Queue entry statuses (stored as string in :status column)
"pending"    # Just generated, waiting for admin review
"draft"      # Admin started editing, saved changes back to queue
"approved"   # Admin approved, waiting for scheduled publish time (optional)
"published"  # Published — stores post_id reference
"rejected"   # Admin rejected — stores reason
```

The `article_data` field is a map containing everything needed to create a post:
```elixir
%{
  title: "SEC's Latest DeFi Crackdown...",
  content: %{"type" => "doc", "content" => [...]},  # TipTap JSON
  excerpt: "The SEC thinks it can regulate code...",
  featured_image: "https://images.unsplash.com/...",
  tags: ["sec", "defi", "regulation"],
  category: :regulation,
  bux_reward: 4,
  bux_pool: 2000,
  word_count: 620,
  source_feeds: [%{source: "Bloomberg", tier: :premium}, %{source: "CoinDesk", tier: :standard}],
  tweet_embeds: [%{url: "https://twitter.com/...", id: "123"}],
  image_suggestion: "defi blockchain regulation"
}
```

### 15.11 Auto-Publish Option

For when you're comfortable with the pipeline quality and want hands-off operation:

```elixir
# In config/runtime.exs
config :blockster_v2, :content_automation,
  auto_publish: System.get_env("CONTENT_AUTO_PUBLISH", "false") == "true"
```

When `auto_publish: true`:
- Articles that pass QualityChecker are published immediately (skip queue)
- Failed quality checks still go to queue for manual review
- Dashboard shows a warning banner: "Auto-publish is ON — articles publish without review"
- Toggle on dashboard page to enable/disable without redeployment

When `auto_publish: false` (default):
- All articles go to the review queue
- Admin must approve each one (edit or quick-approve)

---

## 16. Scaling Considerations

### To increase from 10 to 50+ posts/day:
1. Increase Claude API calls (cost scales linearly)
2. Add more author personas (avoid one author publishing 10x/day)
3. Reduce `@min_gap_minutes` to 20-30 minutes
4. Consider different content formats: short takes (200 words), listicles, weekly roundups
5. Add more RSS feeds (40-50 sources)
6. Cache Claude responses for similar topics to reduce API calls

### Content Variety at Scale:
- **Quick takes** (200 words): Breaking news reactions
- **Standard articles** (400-500 words): Current ~2 min read target
- **Deep dives** (800-1200 words): Weekly in-depth analysis
- **Roundups**: "This Week in DeFi" style compilation posts
- **Market commentary**: Daily/weekly market takes tied to price data from PriceTracker
