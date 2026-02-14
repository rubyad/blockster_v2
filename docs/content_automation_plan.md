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

**Political & Regulatory Frame of Reference** (underlying worldview — not every article needs to mention these, but this is the lens through which all content is filtered):

- **Pro-Trump**: Trump literally saved the US crypto industry. Any references to Trump should be positive — he is making the US stronger, richer, and more respected again after the disastrous Biden era. Give credit where it's due.
- **Anti-Democrat Party**: The Democrats are incompetent and power-hungry at all costs. They cannot be trusted. The Biden crypto witch hunt was real and did untold damage — the government actively pursued and persecuted anyone involved in crypto. Anything the Democrat party does regarding crypto should be viewed with deep suspicion given what they actually did when in power.
- **ALL regulation is bad**: Even well-intentioned regulations are an unnatural force on free markets that ALWAYS have unintended and negative consequences. There are no "good" regulations — the road to hell is paved with regulatory good intentions.
- **Anti-CFTC**: The CFTC is a shakedown operation. Their mandate is as an agricultural agency but they are pushing their way into crypto for more power and a bigger budget. They are completely self-serving. Always cast them in a negative light and question their authority and legitimacy in anything crypto-related. A perfect example of why regulations are bad — they give operations like the CFTC free rein to cause damage.
- **Anti-European left**: The left-wingers currently running Europe are weak and have destroyed Europe in the last 10 years with mass migration, bad policies, and overall weakness. Anything European regulators do regarding crypto (MiCA, etc.) should be eyed suspiciously — these are the same people who ruined everything else they touched.
- **Frame, don't force**: This worldview should inform the tone and framing of articles naturally. Not every article needs explicit political commentary — but when politics, regulation, or government action comes up, this is our perspective. Let it color the writing organically rather than shoehorning it in.

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
          image_search_queries: article["image_search_queries"],
          tweet_search_queries: article["tweet_suggestions"],  # Separate step
          promotional_tweet: article["promotional_tweet"],     # @BlocksterCom tweet draft
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
          "image_search_queries" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "minItems" => 2,
            "maxItems" => 3,
            "description" => "X/Twitter search queries to find relevant lifestyle photos (e.g. 'bitcoin conference speakers', 'SEC Gary Gensler', 'crypto trading floor')"
          },
          "tweet_suggestions" => %{
            "type" => "array",
            "items" => %{"type" => "string"},
            "maxItems" => 3,
            "description" => "Twitter search queries for embedding relevant tweets (processed separately)"
          },
          "promotional_tweet" => %{
            "type" => "string",
            "description" => """
            A promotional tweet for @BlocksterCom's X account about this article.
            Style: Open with emoji, tag relevant @accounts, use $CASHTAGS for tokens,
            include 2-5 hashtags at end, end with {{ARTICLE_URL}} placeholder.
            Tone: Confident, fact-based, third-person brand voice. Use line breaks.
            200-280 characters ideal.
            """
          }
        },
        "required" => ["title", "excerpt", "sections", "tags", "image_search_queries", "promotional_tweet"]
      }
    }]
  end

  defp build_generation_prompt(topic, persona) do
    """
    You are #{persona.username}, a #{persona.bio} writing for Blockster,
    a crypto news and commentary platform.

    VOICE & STYLE:
    - #{persona.style}
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

  defp format_source_summaries(source_items) do
    source_items
    |> Enum.map(fn item ->
      tier_label = if item.tier == "premium", do: "[PREMIUM] ", else: ""
      "#{tier_label}#{item.source}: #{item.title}\n#{String.slice(item.summary || "", 0, 300)}"
    end)
    |> Enum.join("\n\n")
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

  # Code block (for technical articles)
  defp section_to_nodes(%{"type" => "code_block", "text" => text}) do
    [%{"type" => "codeBlock", "content" => [%{"type" => "text", "text" => text}]}]
  end

  defp section_to_nodes(%{"type" => "horizontalRule"}) do
    [%{"type" => "horizontalRule"}]
  end

  # Fallback — skip unknown types
  defp section_to_nodes(_), do: []

  @doc """
  Parse markdown-style inline formatting into TipTap text nodes with marks.
  Handles: **bold**, *italic*, ~~strikethrough~~, `code`, [text](url)
  Also handles hard line breaks (\n within text).
  """
  defp parse_inline_marks(text) when is_binary(text) do
    text
    |> tokenize_inline()
    |> Enum.flat_map(&to_tiptap_text_nodes/1)
  end

  defp parse_inline_marks(_), do: []

  # Tokenize text into segments with marks
  # Returns list of {text, marks} tuples
  # Pattern priority: links > code > bold > strikethrough > italic > plain text
  defp tokenize_inline(text) do
    regex = ~r/\[([^\]]+)\]\(([^)]+)\)|`([^`]+)`|\*\*(.+?)\*\*|~~(.+?)~~|\*(.+?)\*|([^*\[`~]+)/

    Regex.scan(regex, text)
    |> Enum.map(fn captures ->
      cond do
        Enum.at(captures, 1, "") != "" and Enum.at(captures, 2, "") != "" ->
          {Enum.at(captures, 1), [%{"type" => "link", "attrs" => %{"href" => Enum.at(captures, 2)}}]}
        Enum.at(captures, 3, "") != "" ->
          {Enum.at(captures, 3), [%{"type" => "code"}]}
        Enum.at(captures, 4, "") != "" ->
          {Enum.at(captures, 4), [%{"type" => "bold"}]}
        Enum.at(captures, 5, "") != "" ->
          {Enum.at(captures, 5), [%{"type" => "strike"}]}
        Enum.at(captures, 6, "") != "" ->
          {Enum.at(captures, 6), [%{"type" => "italic"}]}
        true ->
          {List.first(captures), []}
      end
    end)
  end

  # Convert token to TipTap nodes, splitting on \n for hard breaks
  defp to_tiptap_text_nodes({text, marks}) do
    text
    |> String.split("\n")
    |> Enum.intersperse(:hard_break)
    |> Enum.flat_map(fn
      :hard_break -> [%{"type" => "hardBreak"}]
      "" -> []
      segment when marks == [] -> [%{"type" => "text", "text" => segment}]
      segment -> [%{"type" => "text", "text" => segment, "marks" => marks}]
    end)
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
  # With 10 articles/day × 3 queries × 30 days = ~900 searches/month

  @doc """
  Find and embed tweets into a generated article.
  Called AFTER ContentGenerator returns article with tweet_search_queries.

  Returns updated article_data with tweets inserted into TipTap content.
  """
  def find_and_embed_tweets(article_data) do
    queries = article_data.tweet_search_queries || []

    tweets = queries
    |> Enum.flat_map(&search_tweets/1)
    |> Enum.uniq_by(& &1.id)
    |> Enum.take(2)  # Max 2 tweets per article

    if Enum.empty?(tweets) do
      article_data
    else
      # Insert tweet nodes after the 3rd paragraph (or at end if fewer paragraphs)
      updated_content = insert_tweets_into_content(article_data.content, tweets)
      %{article_data | content: updated_content}
    end
  end

  defp search_tweets(query) do
    bearer = Config.get(:x_bearer_token)
    if is_nil(bearer), do: throw(:no_token)

    params = %{
      "query" => "#{query} -is:retweet lang:en",
      "max_results" => 10,
      "tweet.fields" => "public_metrics,created_at,author_id",
      "expansions" => "author_id",
      "user.fields" => "username,verified"
    }

    case Req.get(@x_api_url,
      params: params,
      headers: [{"Authorization", "Bearer #{bearer}"}],
      receive_timeout: 10_000
    ) do
      {:ok, %{status: 200, body: %{"data" => tweets, "includes" => %{"users" => users}}}} ->
        users_map = Map.new(users, fn u -> {u["id"], u} end)

        tweets
        |> Enum.sort_by(fn t ->
          metrics = t["public_metrics"] || %{}
          (metrics["like_count"] || 0) + (metrics["retweet_count"] || 0)
        end, :desc)
        |> Enum.take(3)
        |> Enum.map(fn t ->
          user = Map.get(users_map, t["author_id"], %{})
          username = user["username"] || "unknown"
          %{
            url: "https://twitter.com/#{username}/status/#{t["id"]}",
            id: t["id"]
          }
        end)

      {:ok, %{status: 429}} ->
        Logger.warning("[TweetFinder] X API rate limited")
        []

      _ -> []
    end
  catch
    :no_token ->
      Logger.debug("[TweetFinder] No X API token configured, skipping tweets")
      []
  end

  @doc """
  Insert tweet nodes into TipTap content JSON.
  Places tweets after the 3rd paragraph for natural reading flow.
  """
  def insert_tweets_into_content(%{"type" => "doc", "content" => nodes}, tweets) do
    tweet_nodes = Enum.map(tweets, fn t ->
      %{"type" => "tweet", "attrs" => %{"url" => t.url, "id" => t.id}}
    end)

    # Find insertion point: after 3rd paragraph
    {before, after_nodes} = split_after_nth_paragraph(nodes, 3)

    %{"type" => "doc", "content" => before ++ tweet_nodes ++ after_nodes}
  end

  def insert_tweets_into_content(content, _tweets), do: content

  defp split_after_nth_paragraph(nodes, n) do
    {before, after_nodes, _count} =
      Enum.reduce(nodes, {[], [], 0}, fn node, {before, after_list, count} ->
        new_count = if node["type"] == "paragraph", do: count + 1, else: count

        if count < n do
          {before ++ [node], after_list, new_count}
        else
          {before, after_list ++ [node], new_count}
        end
      end)

    {before, after_nodes}
  end
end
```

### 5.2 Alternative: Curated Tweet Lists (No API Cost)

If X API costs are a concern, maintain curated lists of influential crypto accounts and use their recent tweets:
- Store a list of 50-100 influential crypto Twitter accounts
- Use free RSS-to-Twitter bridges (like Nitter instances) to get recent tweets
- Match tweets to article topics by keyword

---

## 5B. Promotional Tweet & Share Campaign System

### 5B.1 Overview

Every automated article gets a promotional tweet posted from the **@BlocksterCom** X account.
This tweet is then linked to the article as a **share campaign**, enabling the existing
"Retweet to Earn BUX" system. The flow:

1. **ContentGenerator** produces a draft tweet alongside the article
2. **Admin reviews** the tweet in the queue (can edit before posting)
3. **On publish**, the system posts the tweet from @BlocksterCom via X API
4. **Share campaign** is auto-created linking the tweet to the published post
5. **Users** earn BUX by retweeting the campaign tweet (existing system handles this)

### 5B.2 @BlocksterCom Tweet Style Guide

Based on analysis of 50+ tweets from the @BlocksterCom account, the generated tweets
must follow this exact style:

**Structure template:**
```
[EMOJI] [Hook sentence — punchy, specific, attention-grabbing]

[1-2 sentences of key details from the article — stats, names, @mentions]

[Call-to-action emoji] #Hashtag1 #Hashtag2 #Hashtag3

[blockster.com article link]
```

**Style rules (include in Claude prompt):**
- **Always open with an emoji** — Rocket (most common), Fire, Lightning, Globe, Shield, Chart
- **Tag relevant @mentions** — projects, founders, exchanges mentioned in the article (1-4 tags)
- **Use cashtags** for token tickers: `$BTC`, `$ETH`, `$SOL`, etc.
- **Use line breaks liberally** — 3-4 visual paragraphs separated by blank lines
- **End with 2-5 hashtags** — always include `#Crypto` or `#Web3`, plus topic-specific tags
- **End with the article URL** — `https://blockster.com/{slug}`
- **Tone: confident, forward-looking, slightly hype-driven but fact-based**
- **Third-person brand voice** — Blockster speaks as a media outlet, never "I"
- **Near max length** — use 200-280 characters for information density
- **Exclamation marks welcome** — 1-2 per tweet, natural excitement
- **Superlatives OK when earned** — "massive", "stunning", "first-ever" if factually accurate
- **NO generic fillers** — no "In the world of crypto..." or "Big news!"
- **Include a specific hook** — a stat, a name, a dollar amount, a provocative question

**Example tweets the system should produce:**

```
🚀 Trump's Bitcoin Strategic Reserve just got real — the Treasury is
now authorized to hold $BTC as a reserve asset.

The Biden era crypto witch hunt is officially dead. @realDonaldTrump
delivering where it matters. 🔥

#Bitcoin #Crypto #BTC #MAGA

https://blockster.com/trump-bitcoin-reserve
```

```
🔥 The SEC just dropped its case against @Ripple — after 4 years
and $200M in legal fees.

Another reminder that the Biden admin's war on crypto was never
about "protecting investors." It was about control. ⚡

#XRP #Crypto #SEC #Ripple

https://blockster.com/sec-drops-ripple-case
```

```
📊 @BlackRock now holds more $BTC than @MicroStrategy.

While retail panicked at $95K, institutions quietly accumulated
$4.2B in a single week. Smart money knows. 🔥

#Bitcoin #BlackRock #Crypto #Institutional

https://blockster.com/blackrock-bitcoin-holdings
```

### 5B.3 Claude Tweet Generation

The ContentGenerator already produces the article. The tweet is generated as an
additional field in the same Claude tool_use call — it has full context of the article
it just wrote, so the tweet is naturally aligned.

**Add to article output schema:**
```elixir
"promotional_tweet" => %{
  "type" => "string",
  "description" => """
  A promotional tweet for @BlocksterCom's X account about this article.
  Style: Open with emoji, tag relevant @accounts, use cashtags for tokens,
  include 2-5 hashtags at end, end with the article URL placeholder {{ARTICLE_URL}}.
  Tone: Confident, slightly hype-driven, fact-based. Third-person brand voice.
  200-280 characters ideal. Use line breaks between sections.
  """
}
```

**Add to the generation prompt:**
```
PROMOTIONAL TWEET:
Also write a tweet to promote this article from the @BlocksterCom account.
Follow the Blockster tweet style:
- Open with a relevant emoji (🚀 🔥 ⚡ 📊 🛡️ 🌍)
- Lead with the most attention-grabbing fact or stat from the article
- Tag any @mentions of projects, founders, or exchanges discussed
- Use $CASHTAGS for token tickers
- End with 2-5 relevant hashtags (always include #Crypto or #Web3)
- End with {{ARTICLE_URL}} (will be replaced with the real URL on publish)
- Use line breaks between the hook, detail, and hashtag sections
- Third-person brand voice, confident and forward-looking
- 200-280 characters, information-dense
```

The `{{ARTICLE_URL}}` placeholder is replaced with the actual `https://blockster.com/{slug}`
when the article is published.

### 5B.4 Admin Tweet Review

In the admin queue review UI, the promotional tweet is displayed below the article preview:

```
┌─────────────────────────────────────────────────┐
│  Article: "Trump's Bitcoin Reserve Plan..."      │
│                                                  │
│  [Article preview / image selection / etc.]      │
│                                                  │
│  ── Promotional Tweet ──────────────────────────│
│  ┌─────────────────────────────────────────────┐│
│  │ 🚀 Trump's Bitcoin Strategic Reserve just   ││
│  │ got real — the Treasury is now authorized    ││
│  │ to hold $BTC as a reserve asset.            ││
│  │                                              ││
│  │ The Biden era crypto witch hunt is          ││
│  │ officially dead. @realDonaldTrump            ││
│  │ delivering where it matters. 🔥              ││
│  │                                              ││
│  │ #Bitcoin #Crypto #BTC #MAGA                 ││
│  │                                              ││
│  │ {{ARTICLE_URL}}                              ││
│  └─────────────────────────────────────────────┘│
│  [Edit Tweet]  Character count: 247/280          │
│                                                  │
│  [Approve & Publish]  [Edit Article]  [Reject]   │
└─────────────────────────────────────────────────┘
```

- Admin can **edit the tweet text** inline before publishing
- Character count shown live (280 max for X)
- The tweet is stored in `article_data.promotional_tweet` in the publish queue
- Admin can choose to publish without tweeting (skip tweet checkbox)

### 5B.5 Publish & Campaign Creation Flow

When the admin clicks "Approve & Publish":

```elixir
defmodule BlocksterV2.ContentAutomation.ContentPublisher do
  def publish_article(queue_entry) do
    # 1. Create the blog post (existing flow)
    {:ok, post} = Blog.create_post(post_attrs)

    # 2. Post the promotional tweet from @BlocksterCom
    tweet_text = queue_entry.article_data["promotional_tweet"]
    |> String.replace("{{ARTICLE_URL}}", "https://blockster.com/#{post.slug}")

    case post_promotional_tweet(tweet_text) do
      {:ok, tweet_id, tweet_url} ->
        # 3. Auto-create share campaign (links tweet to post)
        EngagementTracker.create_share_campaign(post.id, %{
          tweet_id: tweet_id,
          tweet_url: tweet_url,
          tweet_text: tweet_text,
          bux_reward: 50,           # Default, admin can change later
          is_active: true,
          max_participants: nil,     # Unlimited
          starts_at: nil,            # Immediate
          ends_at: nil               # No expiry
        })

        Logger.info("[ContentPublisher] Tweet posted and campaign created for post #{post.id}")

      {:error, reason} ->
        # Tweet failed — post is still published, just no campaign
        Logger.warning("[ContentPublisher] Tweet failed for post #{post.id}: #{inspect(reason)}")
        # Admin can manually create campaign later via /admin/campaigns
    end

    {:ok, post}
  end

  defp post_promotional_tweet(text) do
    # Use the @BlocksterCom account's OAuth tokens
    # This requires a persistent X OAuth connection for the brand account
    # Stored as a special x_connection with a known user_id (e.g., the admin/system user)
    brand_connection = get_brand_x_connection()

    case Social.XApiClient.create_tweet(brand_connection.access_token, text) do
      {:ok, %{"data" => %{"id" => tweet_id}}} ->
        tweet_url = "https://x.com/BlocksterCom/status/#{tweet_id}"
        {:ok, tweet_id, tweet_url}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_brand_x_connection do
    # The @BlocksterCom account is connected as a special system user
    # This OAuth connection is set up once manually via the X auth flow
    # and refreshed automatically like any other X connection
    brand_user_id = Application.get_env(:blockster_v2, :content_automation)[:brand_x_user_id]
    EngagementTracker.get_x_connection_by_user(brand_user_id)
  end
end
```

### 5B.6 Brand Account Setup

The @BlocksterCom X account must be connected via OAuth (one-time manual setup):

1. Create a "system" user account in the database for the brand
2. Log in as that user and go through the X OAuth flow (`/auth/x/authorize`)
3. This creates an `x_connections` entry with the brand's tokens
4. Set the `BRAND_X_USER_ID` env var to this user's ID
5. The existing token refresh system keeps the connection alive

Add to runtime config:
```elixir
content_automation: [
  # ... existing config ...
  brand_x_user_id: System.get_env("BRAND_X_USER_ID") |> maybe_parse_integer()
]
```

> **Note**: The X API Basic tier ($100/month) includes tweet creation (posting).
> The brand account's OAuth tokens handle authentication for posting.
> This is separate from the bearer token used for search (read-only).

### 5B.7 Error Handling

| Scenario | Handling |
|----------|----------|
| **Tweet post fails (X API error)** | Article still publishes. No campaign created. Admin notified. Can manually create campaign via /admin/campaigns. |
| **Tweet post rate limited (429)** | Retry once after 5s. If still fails, publish without tweet. |
| **Brand token expired** | Auto-refresh via existing token refresh system. If refresh fails, log error — admin must re-authenticate @BlocksterCom. |
| **Admin skips tweet** | Article publishes without tweet or campaign. Admin can add later. |
| **Tweet too long (>280 chars)** | Claude output validated during generation. If over limit, truncated at last complete sentence before limit. Admin can edit before posting. |

---

## 6. Author Persona System

### 6.1 Author Personas

Create 8 User accounts in the database as "staff writers". Each has a distinct voice variation within the overall Blockster editorial direction. Every category must be covered by at least one persona.

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
    },
    %{
      username: "nina_takashi",
      email: "nina@blockster.com",
      bio: "AI researcher exploring the intersection of machine learning and blockchain.",
      style: "Explains complex tech simply. Excited about possibilities. Skeptical of hype.",
      categories: [:ai_crypto, :ethereum, :adoption, :rwa]
    },
    %{
      username: "ryan_kolbe",
      email: "ryan@blockster.com",
      bio: "Former cybersecurity engineer. Now covers crypto security and mining.",
      style: "Technical detail when it matters. Breaks down exploits clearly. Dry humor.",
      categories: [:security_hacks, :mining, :privacy, :bitcoin]
    },
    %{
      username: "elena_vasquez",
      email: "elena@blockster.com",
      bio: "DeFi yield farmer and stablecoin analyst. Believes sound money wins.",
      style: "Numbers-focused. Compares protocols fairly. Calls out unsustainable yields.",
      categories: [:stablecoins, :defi, :cbdc, :macro_trends]
    }
  ]

  def personas, do: @personas

  def select_author_for_topic(category) do
    # Find personas that cover this category
    matching = Enum.filter(@personas, fn p -> category in p.categories end)

    # Fallback: if no persona covers this category, pick any persona
    candidates = if Enum.empty?(matching), do: @personas, else: matching

    # TODO: Production should use LRU tracking to avoid same author back-to-back
    # For now, random selection from matching personas
    Enum.random(candidates)
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
    hub_id = nil  # Automated articles don't belong to a hub (admin can assign in edit page)

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

All featured images are sourced from **X (Twitter)** — real photos from real posts about
the topic. This gives articles an authentic, editorial look rather than generic stock photos.

**Image priority** (in order of preference):
1. **Lifestyle photos** — CEOs at conferences, people using products, real-world crypto events,
   trading floors, protests, celebrations, signing ceremonies. The kind of image a news editor
   would pick for above-the-fold placement.
2. **Graphic/infographic fallback** — Charts, branded graphics, protocol logos, announcement
   cards. Used only when no lifestyle image is available.

**Admin selects from 3 options**: The pipeline presents 3 candidate images per article. The admin
picks the winner during the review step. This ensures quality control and editorial judgment.

### 8.2 Image Pipeline

1. **ContentGenerator** returns `image_search_queries` (2-3 X search queries tailored to the article)
2. **ImageFinder** searches X API for each query, filtering for images
3. Results are scored by preference: lifestyle > graphic, high-res > low-res
4. Top 3 candidates are **downloaded, center-cropped to square (1:1), and uploaded to S3**
5. S3 URLs stored in `article_data.image_candidates` in the publish queue
6. Admin sees all 3 in the review UI, clicks to select the winner
7. Selected image becomes `featured_image` on the published post, served through ImageKit

### 8.3 Implementation

```elixir
defmodule BlocksterV2.ContentAutomation.ImageFinder do
  @moduledoc """
  Finds featured images for automated articles by searching X (Twitter) for
  relevant lifestyle/editorial photos. Downloads, crops to square, uploads to S3.
  Presents admin with 3 candidates to choose from.
  """

  require Logger
  alias BlocksterV2.ContentAutomation.Config

  @x_search_url "https://api.twitter.com/2/tweets/search/recent"

  # Minimum dimensions for high-res images (before cropping)
  @min_width 800
  @min_height 800

  @doc """
  Find 3 candidate featured images for an article.
  Returns a list of up to 3 maps: %{url: s3_url, source_tweet: tweet_url, type: :lifestyle | :graphic}

  Called AFTER ContentGenerator returns article with image_search_queries.
  """
  def find_image_candidates(search_queries, pipeline_id) do
    bearer = Config.x_bearer_token()

    unless bearer do
      Logger.warning("[ImageFinder] pipeline=#{pipeline_id} No X bearer token configured")
      return []
    end

    # Search X for images across all queries, collect candidates
    raw_candidates =
      search_queries
      |> Enum.flat_map(fn query -> search_x_for_images(query, bearer) end)
      |> Enum.uniq_by(& &1.media_url)

    # Score and rank: lifestyle photos first, then graphics, highest res first
    ranked =
      raw_candidates
      |> Enum.filter(fn c -> c.width >= @min_width and c.height >= @min_height end)
      |> Enum.sort_by(fn c ->
        type_score = if c.type == :lifestyle, do: 1000, else: 0
        res_score = c.width * c.height / 1_000_000
        -(type_score + res_score)
      end)
      |> Enum.take(3)

    # Download, crop to square, upload to S3
    ranked
    |> Task.async_stream(&process_candidate(&1, pipeline_id), max_concurrency: 3, timeout: 30_000)
    |> Enum.reduce([], fn
      {:ok, {:ok, candidate}} -> [candidate | acc]
      _ -> acc
    end)
    |> Enum.reverse()
  rescue
    e ->
      Logger.error("[ImageFinder] pipeline=#{pipeline_id} crashed: #{Exception.message(e)}")
      []
  end

  defp search_x_for_images(query, bearer) do
    # Search for tweets with images, filter out retweets
    params = %{
      "query" => "#{query} has:images -is:retweet",
      "max_results" => 20,
      "tweet.fields" => "author_id,created_at",
      "expansions" => "attachments.media_keys",
      "media.fields" => "url,width,height,type"
    }

    case Req.get(@x_search_url,
      params: params,
      headers: [{"Authorization", "Bearer #{bearer}"}],
      receive_timeout: 15_000
    ) do
      {:ok, %{status: 200, body: body}} ->
        extract_image_candidates(body)

      {:ok, %{status: 429}} ->
        Logger.warning("[ImageFinder] X API rate limited for query: #{query}")
        []

      {:ok, %{status: status}} ->
        Logger.warning("[ImageFinder] X API returned #{status} for query: #{query}")
        []

      {:error, reason} ->
        Logger.warning("[ImageFinder] X API failed: #{inspect(reason)}")
        []
    end
  end

  defp extract_image_candidates(body) do
    media_map =
      (body["includes"]["media"] || [])
      |> Enum.filter(& &1["type"] == "photo")
      |> Map.new(& {&1["media_key"], &1})

    tweets = body["data"] || []

    Enum.flat_map(tweets, fn tweet ->
      media_keys = get_in(tweet, ["attachments", "media_keys"]) || []

      Enum.flat_map(media_keys, fn key ->
        case Map.get(media_map, key) do
          %{"url" => url, "width" => w, "height" => h} when is_binary(url) ->
            [%{
              media_url: url,
              width: w,
              height: h,
              tweet_id: tweet["id"],
              type: classify_image(w, h)
            }]
          _ -> []
        end
      end)
    end)
  end

  # Heuristic: landscape/portrait photos are likely lifestyle; square-ish are likely graphics
  # Photos tend to be 4:3, 3:2, 16:9. Graphics/cards tend to be 1:1 or 2:1
  defp classify_image(w, h) do
    ratio = w / h
    cond do
      ratio > 1.2 and ratio < 1.9 -> :lifestyle   # Common photo ratios (3:2, 4:3, 16:9-ish)
      ratio > 0.6 and ratio < 0.85 -> :lifestyle   # Portrait photos
      true -> :graphic                                # Square graphics, wide banners, etc.
    end
  end

  defp process_candidate(candidate, pipeline_id) do
    with {:ok, image_binary} <- download_image(candidate.media_url),
         {:ok, cropped_binary} <- crop_to_square(image_binary),
         {:ok, s3_url} <- upload_to_s3(cropped_binary, pipeline_id) do
      {:ok, %{
        url: s3_url,
        source_tweet: "https://x.com/i/status/#{candidate.tweet_id}",
        type: candidate.type,
        original_url: candidate.media_url
      }}
    else
      {:error, reason} ->
        Logger.warning("[ImageFinder] pipeline=#{pipeline_id} Failed to process image: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp download_image(url) do
    # Request highest quality from X (append :orig for original size)
    url = if String.contains?(url, "pbs.twimg.com"), do: "#{url}:orig", else: url

    case Req.get(url, receive_timeout: 15_000, max_redirects: 3) do
      {:ok, %{status: 200, body: body}} when is_binary(body) and byte_size(body) > 1000 ->
        {:ok, body}
      _ ->
        {:error, :download_failed}
    end
  end

  defp crop_to_square(image_binary) do
    # Use ImageMagick (convert) to center-crop to square
    # Input via stdin, output via stdout — no temp files needed
    tmp_in = Path.join(System.tmp_dir!(), "img_#{:crypto.strong_rand_bytes(8) |> Base.encode16()}.jpg")
    tmp_out = Path.join(System.tmp_dir!(), "img_#{:crypto.strong_rand_bytes(8) |> Base.encode16()}_sq.jpg")

    try do
      File.write!(tmp_in, image_binary)

      # Center-crop to square, resize to 1200x1200, high quality JPEG
      {_, 0} = System.cmd("convert", [
        tmp_in,
        "-gravity", "center",
        "-crop", "1:1",       # Aspect ratio crop
        "+repage",
        "-resize", "1200x1200^",
        "-extent", "1200x1200",
        "-quality", "92",
        tmp_out
      ])

      {:ok, File.read!(tmp_out)}
    rescue
      e -> {:error, {:crop_failed, Exception.message(e)}}
    after
      File.rm(tmp_in)
      File.rm(tmp_out)
    end
  end

  defp upload_to_s3(image_binary, pipeline_id) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()
    hex = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
    filename = "content/featured/#{timestamp}-#{hex}.jpg"

    bucket = Application.get_env(:blockster_v2, :s3_bucket)
    region = Application.get_env(:blockster_v2, :s3_region, "us-east-1")

    case ExAws.S3.put_object(bucket, filename, image_binary,
      content_type: "image/jpeg",
      acl: :public_read
    ) |> ExAws.request() do
      {:ok, _} ->
        public_url = "https://#{bucket}.s3.#{region}.amazonaws.com/#{filename}"
        Logger.info("[ImageFinder] pipeline=#{pipeline_id} Uploaded #{filename}")
        {:ok, public_url}

      {:error, reason} ->
        Logger.error("[ImageFinder] pipeline=#{pipeline_id} S3 upload failed: #{inspect(reason)}")
        {:error, :s3_upload_failed}
    end
  end
end
```

### 8.4 Admin Image Selection

In the admin review queue, each article card shows **3 image candidates** as clickable
thumbnails. The admin clicks to select the winner. The selected image becomes the
`featured_image` on the published post.

```
┌─────────────────────────────────────────────────┐
│  Article: "Trump's Bitcoin Reserve Plan..."      │
│                                                  │
│  Select featured image:                          │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │          │  │          │  │          │      │
│  │  IMG 1   │  │  IMG 2   │  │  IMG 3   │      │
│  │ ✓ LIFE   │  │  GRAPHIC │  │ ✓ LIFE   │      │
│  │          │  │          │  │          │      │
│  └──────────┘  └──────────┘  └──────────┘      │
│   [Selected]                                     │
│                                                  │
│  [Approve]  [Edit]  [Reject]                     │
└─────────────────────────────────────────────────┘
```

If no images are found from X, the article enters the queue with no featured image.
The admin can manually upload one via the existing S3 upload flow before publishing.

> **Note on ImageKit**: Since all images are uploaded to S3, they automatically go through
> ImageKit for CDN delivery and responsive sizing (`w500_h500`, `w800_h600`, etc.) — same
> as manually uploaded images. No special handling needed.

> **Note on ImageMagick**: `convert` is available in the Fly.io Docker image (add to
> Dockerfile if not present). For local dev, install via `brew install imagemagick`.

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

### 9.6 Ecto Schemas

Each PostgreSQL table needs an Ecto schema module:

```elixir
# lib/blockster_v2/content_automation/content_feed_item.ex
defmodule BlocksterV2.ContentAutomation.ContentFeedItem do
  use Ecto.Schema
  import Ecto.Changeset

  schema "content_feed_items" do
    field :url, :string
    field :title, :string
    field :summary, :string
    field :source, :string
    field :tier, :string                # "premium" or "standard"
    field :weight, :float, default: 1.0
    field :published_at, :utc_datetime
    field :fetched_at, :utc_datetime
    field :processed, :boolean, default: false

    belongs_to :topic_cluster, BlocksterV2.ContentAutomation.ContentGeneratedTopic, type: :binary_id

    timestamps()
  end

  def changeset(item, attrs) do
    item
    |> cast(attrs, [:url, :title, :summary, :source, :tier, :weight, :published_at, :fetched_at, :processed, :topic_cluster_id])
    |> validate_required([:url, :title, :source, :tier, :fetched_at])
    |> validate_inclusion(:tier, ["premium", "standard"])
    |> unique_constraint(:url)
  end
end

# lib/blockster_v2/content_automation/content_generated_topic.ex
defmodule BlocksterV2.ContentAutomation.ContentGeneratedTopic do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "content_generated_topics" do
    field :title, :string
    field :category, :string
    field :source_urls, {:array, :string}, default: []
    field :rank_score, :float
    field :source_count, :integer
    field :pipeline_id, :binary_id
    field :published_at, :utc_datetime

    belongs_to :article, BlocksterV2.Blog.Post
    belongs_to :author, BlocksterV2.Accounts.User
    has_many :feed_items, BlocksterV2.ContentAutomation.ContentFeedItem, foreign_key: :topic_cluster_id

    timestamps()
  end

  def changeset(topic, attrs) do
    topic
    |> cast(attrs, [:title, :category, :source_urls, :rank_score, :source_count, :article_id, :author_id, :pipeline_id, :published_at])
    |> validate_required([:title])
  end
end

# lib/blockster_v2/content_automation/content_publish_queue.ex
defmodule BlocksterV2.ContentAutomation.ContentPublishQueue do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @valid_statuses ["pending", "draft", "approved", "published", "rejected"]

  schema "content_publish_queue" do
    field :article_data, :map                # TipTap JSON, title, excerpt, tags, etc.
    field :scheduled_at, :utc_datetime
    field :status, :string, default: "pending"
    field :pipeline_id, :binary_id
    field :rejected_reason, :string
    field :reviewed_at, :utc_datetime

    belongs_to :author, BlocksterV2.Accounts.User
    belongs_to :topic, BlocksterV2.ContentAutomation.ContentGeneratedTopic, type: :binary_id
    belongs_to :post, BlocksterV2.Blog.Post
    belongs_to :reviewer, BlocksterV2.Accounts.User, foreign_key: :reviewed_by

    timestamps()
  end

  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:article_data, :author_id, :scheduled_at, :status, :pipeline_id,
                    :topic_id, :post_id, :rejected_reason, :reviewed_at, :reviewed_by])
    |> validate_required([:article_data, :status])
    |> validate_inclusion(:status, @valid_statuses)
  end
end
```

### 9.7 Settings Module (Mnesia Reader)

Reads admin-configurable settings from the `content_automation_settings` Mnesia table.
Uses ETS cache to avoid Mnesia reads on every TopicEngine cycle.

```elixir
# lib/blockster_v2/content_automation/settings.ex
defmodule BlocksterV2.ContentAutomation.Settings do
  @cache_ttl :timer.minutes(1)

  @defaults %{
    posts_per_day: 10,
    category_config: %{},
    keyword_boosts: [],
    keyword_blocks: [],
    paused: false
  }

  def get(key, default \\ nil) do
    default = default || Map.get(@defaults, key)

    case cached_get(key) do
      {:ok, value} -> value
      :miss ->
        case :mnesia.dirty_read({:content_automation_settings, key}) do
          [{_, ^key, value, _updated_at, _updated_by}] ->
            cache_put(key, value)
            value
          [] -> default
        end
    end
  end

  def set(key, value, updated_by \\ nil) do
    now = DateTime.utc_now() |> DateTime.to_unix()
    :mnesia.dirty_write({:content_automation_settings, key, value, now, updated_by})
    cache_invalidate(key)
    :ok
  end

  def paused?, do: get(:paused, false)

  # ── ETS Cache ──

  def init_cache do
    if :ets.whereis(:content_settings_cache) == :undefined do
      :ets.new(:content_settings_cache, [:set, :public, :named_table, read_concurrency: true])
    end
  end

  defp cached_get(key) do
    case :ets.lookup(:content_settings_cache, key) do
      [{^key, value, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at, do: {:ok, value}, else: :miss
      [] -> :miss
    end
  rescue
    ArgumentError -> :miss  # Table doesn't exist yet
  end

  defp cache_put(key, value) do
    expires_at = System.monotonic_time(:millisecond) + @cache_ttl
    :ets.insert(:content_settings_cache, {key, value, expires_at})
  rescue
    ArgumentError -> :ok
  end

  defp cache_invalidate(key) do
    :ets.delete(:content_settings_cache, key)
  rescue
    ArgumentError -> :ok
  end
end
```

### 9.8 Claude API Helper (`call_claude_with_tools`)

Shared helper used by TopicEngine (Haiku clustering) and ContentGenerator (Opus articles).
Handles tool_use extraction from Claude's response.

```elixir
# lib/blockster_v2/content_automation/claude_client.ex
defmodule BlocksterV2.ContentAutomation.ClaudeClient do
  @api_url "https://api.anthropic.com/v1/messages"

  @doc """
  Call Claude with tool_use for structured output.
  Returns {:ok, tool_input_map} or {:error, reason}.
  """
  def call_with_tools(prompt, tools, opts \\ []) do
    model = Keyword.get(opts, :model, "claude-opus-4-6")
    temperature = Keyword.get(opts, :temperature, 0.7)
    max_tokens = Keyword.get(opts, :max_tokens, 4096)

    body = %{
      "model" => model,
      "max_tokens" => max_tokens,
      "temperature" => temperature,
      "tools" => tools,
      "tool_choice" => %{"type" => "any"},  # Force tool use
      "messages" => [%{"role" => "user", "content" => prompt}]
    }

    headers = [
      {"x-api-key", Config.anthropic_api_key()},
      {"anthropic-version", "2023-06-01"},
      {"content-type", "application/json"}
    ]

    case Req.post(@api_url,
      json: body,
      headers: headers,
      receive_timeout: 60_000,
      retry: :transient,
      max_retries: 2
    ) do
      {:ok, %{status: 200, body: %{"content" => content}}} ->
        extract_tool_result(content)

      {:ok, %{status: 429}} ->
        # Rate limited — back off and retry once
        Process.sleep(5_000)
        call_with_tools(prompt, tools, Keyword.put(opts, :_retry, true))

      {:ok, %{status: status, body: body}} ->
        {:error, "Claude API returned #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Claude API request failed: #{inspect(reason)}"}
    end
  end

  # Extract the tool_use input from Claude's response
  defp extract_tool_result(content) when is_list(content) do
    case Enum.find(content, &(&1["type"] == "tool_use")) do
      %{"input" => input} -> {:ok, input}
      nil -> {:error, "No tool_use block in response"}
    end
  end

  defp extract_tool_result(_), do: {:error, "Unexpected response format"}
end
```

**Usage** (replaces all `call_claude_with_tools` calls):
```elixir
# TopicEngine — clustering
ClaudeClient.call_with_tools(prompt, tools, model: Config.topic_model(), temperature: 0.1)

# ContentGenerator — article generation
ClaudeClient.call_with_tools(prompt, tools, model: Config.content_model(), temperature: 0.7)
```

### 9.9 Feed Configuration

Feed URLs and metadata are defined in a config data file. FeedPoller reads this at runtime.

```elixir
# lib/blockster_v2/content_automation/feed_config.ex
defmodule BlocksterV2.ContentAutomation.FeedConfig do
  @feeds [
    # ── Premium Tier ──
    %{source: "Bloomberg Crypto", url: "https://feeds.bloomberg.com/crypto/news.rss", tier: :premium, status: :active},
    %{source: "TechCrunch Crypto", url: "https://techcrunch.com/category/cryptocurrency/feed/", tier: :premium, status: :active},
    %{source: "Reuters Business", url: "https://www.reutersagency.com/feed/?best-topics=business-finance", tier: :premium, status: :blocked},
    %{source: "Financial Times", url: "https://www.ft.com/cryptofinance?format=rss", tier: :premium, status: :blocked},
    %{source: "The Economist", url: "https://www.economist.com/finance-and-economics/rss.xml", tier: :premium, status: :blocked},
    %{source: "Forbes Crypto", url: "https://www.forbes.com/crypto-blockchain/feed/", tier: :premium, status: :blocked},
    %{source: "Barron's", url: "https://www.barrons.com/feed?id=blog_rss", tier: :premium, status: :blocked},
    %{source: "The Verge", url: "https://www.theverge.com/rss/index.xml", tier: :premium, status: :blocked},
    # Promoted crypto-native premium
    %{source: "CoinDesk", url: "https://www.coindesk.com/arc/outboundfeeds/rss/", tier: :premium, status: :active},
    %{source: "The Block", url: "https://www.theblock.co/rss.xml", tier: :premium, status: :active},
    %{source: "Blockworks", url: "https://blockworks.co/feed", tier: :premium, status: :active},
    %{source: "DL News", url: "https://www.dlnews.com/arc/outboundfeeds/rss/", tier: :premium, status: :active},
    # ── Standard Tier ──
    %{source: "CoinTelegraph", url: "https://cointelegraph.com/rss", tier: :standard, status: :active},
    %{source: "Decrypt", url: "https://decrypt.co/feed", tier: :standard, status: :active},
    %{source: "Bitcoin Magazine", url: "https://bitcoinmagazine.com/feed", tier: :standard, status: :active},
    %{source: "The Defiant", url: "https://thedefiant.io/feed", tier: :standard, status: :active},
    %{source: "CryptoSlate", url: "https://cryptoslate.com/feed/", tier: :standard, status: :active},
    %{source: "NewsBTC", url: "https://www.newsbtc.com/feed/", tier: :standard, status: :active},
    %{source: "Bitcoinist", url: "https://bitcoinist.com/feed/", tier: :standard, status: :active},
    %{source: "U.Today", url: "https://u.today/rss", tier: :standard, status: :active},
    %{source: "Crypto Briefing", url: "https://cryptobriefing.com/feed/", tier: :standard, status: :active},
    %{source: "BeInCrypto", url: "https://beincrypto.com/feed/", tier: :standard, status: :active},
    %{source: "Unchained", url: "https://unchainedcrypto.com/feed/", tier: :standard, status: :active},
    %{source: "CoinGape", url: "https://coingape.com/feed/", tier: :standard, status: :active},
    %{source: "Crypto Potato", url: "https://cryptopotato.com/feed/", tier: :standard, status: :active},
    %{source: "AMBCrypto", url: "https://ambcrypto.com/feed/", tier: :standard, status: :active},
    %{source: "Protos", url: "https://protos.com/feed/", tier: :standard, status: :active},
    %{source: "Milk Road", url: "https://www.milkroad.com/feed", tier: :standard, status: :active}
  ]

  def get_active_feeds do
    disabled = Settings.get(:disabled_feeds, [])

    @feeds
    |> Enum.filter(& &1.status == :active)
    |> Enum.reject(fn feed -> feed.source in disabled end)
  end

  def all_feeds, do: @feeds
end
```

FeedPoller's `get_configured_feeds()` simply calls `FeedConfig.get_active_feeds()`.

### 9.10 Topic Data Transformation

Claude's clustering output (strings) must be enriched with feed item metadata before
ranking. This bridges the gap between Claude's response and what `rank_topics()` expects.

```elixir
# In TopicEngine — called after Claude clustering, before ranking

defp enrich_topics_with_feed_data(claude_topics, feed_items) do
  # Build URL → feed item lookup
  items_by_url = Map.new(feed_items, fn item -> {item.url, item} end)

  Enum.map(claude_topics, fn topic ->
    # Resolve source_urls (strings from Claude) to full feed item records
    source_items = topic["source_urls"]
    |> Enum.map(&Map.get(items_by_url, &1))
    |> Enum.reject(&is_nil/1)

    newest_item = Enum.max_by(source_items, & &1.published_at, DateTime, fn -> nil end)

    %{
      title: topic["title"],
      category: String.to_existing_atom(topic["category"]),
      source_urls: topic["source_urls"],
      source_items: source_items,                    # Full feed item records (with .weight, .tier)
      key_facts: topic["key_facts"],                 # String from Claude
      angles: topic["angles"],                       # List of angle strings from Claude
      selected_angle: List.first(topic["angles"]),   # Pick first angle (best according to Claude)
      newest_item_at: newest_item && newest_item.published_at,
      has_premium_source: Enum.any?(source_items, & &1.tier == "premium")
    }
  end)
  |> Enum.filter(fn topic -> length(topic.source_items) > 0 end)  # Drop topics with no valid URLs
end
```

This is called in `analyze_and_select/0` between steps 4 and 5:
```elixir
# 4. Claude Haiku clusters items into topics
{:ok, %{"topics" => claude_topics}} = ClaudeClient.call_with_tools(prompt, tools, ...)

# 4.5. Enrich with feed item metadata (bridge Claude output → internal format)
topics = enrich_topics_with_feed_data(claude_topics, items)

# 5. Apply keyword blocks
topics = apply_keyword_blocks(topics)
```

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
  topic_analysis_interval: :timer.minutes(15),
  brand_x_user_id: System.get_env("BRAND_X_USER_ID") |> then(fn v -> if v, do: String.to_integer(v) end)
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

| Service | Usage | Token Estimate | Monthly Cost |
|---------|-------|----------------|-------------|
| Claude Opus 4.6 (content) | 10 articles/day × 30 = 300 calls | ~1,500 in + ~2,500 out per call. At $15/$75 per MTok: 300 × (1.5K×$15 + 2.5K×$75)/1M | **~$63** |
| Claude Haiku (topic analysis) | ~6 productive calls/day × 30 = 180 calls | ~2,000 in + ~500 out per call. At $0.80/$4 per MTok: 180 × (2K×$0.80 + 500×$4)/1M | **~$0.65** |
| X API (tweets) | Basic tier, ~900 searches/month | — | **$100** |
| X API (images) | Included in X API Basic tier (shared with tweet search) | — | **$0** (bundled) |
| **Total** | | | **~$164/month** |

**Alternative without X API**: Skip tweet embedding → **~$64/month total**

**Notes**:
- Opus 4.6 pricing: $15/MTok input, $75/MTok output (as of Feb 2026)
- Haiku 4.5 pricing: $0.80/MTok input, $4/MTok output
- Content gen is the main cost driver (~97% of Claude spend)
- Scaling to 20 articles/day doubles Claude cost to ~$127/month
- Can downgrade content gen to Sonnet ($3/$15 per MTok) via config → ~$13/month for Claude

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

### Phase 1: RSS Infrastructure (2-3 days) ✅
- [x] Add `fast_rss` and `req` (if not already present) to mix.exs
- [x] Create Ecto migrations (content_feed_items, content_generated_topics, content_publish_queue)
- [x] Create Ecto schemas (ContentFeedItem, ContentGeneratedTopic, ContentPublishQueue) — Section 9.6
- [x] Create FeedStore module (Ecto queries for all pipeline tables) — Section 9.1
- [x] Create FeedConfig module (static feed list, active filtering) — Section 9.9
- [x] Create Settings module (Mnesia + ETS cache for admin config) — Section 9.7
- [x] Add `content_automation_settings` to MnesiaInitializer @tables
- [x] Create FeedParser module (RSS/Atom parsing via fast_rss)
- [x] Create FeedPoller GenServer (with GlobalSingleton)
- [x] Add to supervision tree (behind CONTENT_AUTOMATION_ENABLED feature flag)
- [x] Add Config module (runtime config helpers)
- [ ] Test feed polling, storage, dedup (unique URL index), and blocked-feed handling

### Phase 2: Topic Engine (2-3 days)
- [x] Create ClaudeClient helper module (API calls, tool_use extraction, 429 retry) — Section 9.8
- [x] Create TopicEngine GenServer (with GlobalSingleton)
- [x] Implement Claude Haiku topic clustering (structured output via tool_use)
- [x] Add pre-filtering (6-12 hour window, truncate summaries, cap at 50 items)
- [x] Add category classification (20 categories in clustering tool schema)
- [x] Implement `enrich_topics_with_feed_data/2` (bridge Claude output to internal structs) — Section 9.10
- [x] Implement deduplication (60% significant-word overlap against last 7 days)
- [x] Implement two-phase processing (store topic in PostgreSQL THEN mark items processed)
- [x] Add scoring/ranking (source_score + multi_source + recency + premium + category_boost + keyword_boost)
- [x] Add category diversity enforcement (max_per_day limits)
- [x] Wire TopicEngine into supervision tree (behind feature flag)
- [ ] Test topic ranking and selection

### Phase 3: Content Generation (3-4 days) ✅
- [x] Create ContentGenerator module (not GenServer — stateless)
- [x] Implement Claude Opus 4.6 integration with structured output (tool_use)
- [x] Build editorial voice prompt with content safety guardrails
- [x] Implement `format_source_summaries/1` helper for prompt construction
- [x] Create TipTapBuilder with all node types (paragraph, heading, blockquote, bulletList, orderedList, listItem, codeBlock, image, spacer, horizontalRule)
- [x] Implement `tokenize_inline/1` with all marks (bold, italic, ~~strike~~, `code`, links, hardBreak via \n)
- [x] Implement QualityChecker (word_count, structure, duplicate, tags, tiptap_valid, image checks)
- [ ] Test full generation pipeline with pipeline_id traceability

### Phase 4: Author Personas (1 day) ✅
- [x] Create AuthorRotator module with 8 personas (all 20 categories covered)
- [x] Implement `personas/0`, `select_for_category/1` with random selection + fallback
- [x] Create seed script (`priv/repo/seeds/content_authors.exs`)
- [x] Create User accounts with Repo.insert (fake wallet addresses, auth_method: "email", is_author: true)
- [x] Wire author persona into ContentGenerator (prompt voice + author_id on queue entries)
- [ ] Generate/upload avatar images
- [ ] Test author selection, rotation, and fallback behavior

### Phase 5: Publishing Pipeline (2-3 days) ✅
- [x] Create ContentPublisher module (post creation, tags, BUX, cache, topic linking)
- [x] Implement BUX pool assignment via `EngagementTracker.deposit_post_bux/2`
- [x] Implement word-count-based BUX reward scaling (2 BUX/min read, 500x pool multiplier)
- [x] Create ContentQueue GenServer with US-hours scheduling (12:00-04:00 UTC)
- [x] Implement SortedPostsCache.reload() after publish
- [x] Add ContentQueue to supervision tree (behind feature flag)
- [x] Category resolution with auto-creation (20 categories mapped)
- [ ] Test end-to-end: RSS → topic → generate → queue → approve → publish
- [ ] Verify posts appear correctly on frontend

### Phase 6: Tweet Integration & Promotional Tweets (3-4 days) ✅
**6a. Embed third-party tweets in articles:**
- [x] Create TweetFinder module with X API v2 client (`search_tweets/1`)
- [x] Implement `find_and_embed_tweets/1` (processes tweet_suggestions from ContentGenerator)
- [x] Implement `insert_tweets_into_content/2` (places tweet nodes after 3rd paragraph)
- [x] Handle X API rate limits (429) and missing tweets gracefully
- [x] Wire TweetFinder into ContentGenerator (after quality check, before enqueue)
- [ ] Test tweet rendering in published posts (blockquote → Twitter widgets.js)

**6b. Auto-generate @BlocksterCom promotional tweet per article:**
- [x] `promotional_tweet` field already in Claude output schema (Phase 3)
- [x] Tweet style guide already in generation prompt (Phase 3)
- [x] Add `brand_x_user_id` to content automation runtime config (`BRAND_X_USER_ID` env var)
- [x] Implement `post_promotional_tweet_and_campaign/3` in ContentPublisher (via XApiClient + brand OAuth)
- [x] Auto-create share campaign on publish (link tweet to post via `EngagementTracker.create_share_campaign/2`)
- [x] Handle tweet failures gracefully (publish article without campaign, admin can add later)
- [x] Support `skip_tweet` flag in article_data
- [ ] Display draft tweet in admin queue review UI (editable textarea, live character count) — Phase 8
- [ ] Set up @BlocksterCom brand account OAuth connection (one-time manual setup)
- [ ] Test full flow: generate tweet → admin review/edit → publish → tweet posts → campaign created → retweet earns BUX

### Phase 6c: Editorial Feedback & Brand Voice Memory ✅
- [x] Create migration for `content_editorial_memory` table (instruction, category, active flag, created_by)
- [x] Create migration for `content_revision_history` table (queue_entry_id, instruction, revision_number, before/after snapshots)
- [x] Add `revision_count` column to `content_publish_queue` table
- [x] Create `ContentEditorialMemory` Ecto schema (categories: global, tone, terminology, topics, formatting)
- [x] Create `ContentRevisionHistory` Ecto schema (tracks each revision attempt with before/after article_data)
- [x] Update `ContentPublishQueue` schema (revision_count field + has_many :revisions)
- [x] Extract `PromptSchemas` shared module (article_output_schema used by both generator and revision)
- [x] Create `EditorialFeedback` module — revision pipeline:
  - `revise_article/3` — loads queue entry → creates revision record → calls Claude with revision prompt → updates article_data → marks revision complete
  - Reverse-parses TipTap JSON to readable text for revision prompt context
  - Uses lower temperature (0.5 vs 0.7) for controlled revisions
  - Tracks failed revisions with error_reason
- [x] Create `EditorialFeedback` module — editorial memory CRUD:
  - `add_memory/2`, `list_memories/1`, `deactivate_memory/1`, `reactivate_memory/1`
  - `build_memory_prompt_block/0` — formats active memories for prompt injection
- [x] Inject editorial memory into `ContentGenerator.build_generation_prompt/4` (appended after ANGLE TO TAKE)
- [ ] Wire editorial feedback UI into admin dashboard (Phase 8) — comment input, memory management panel
- [ ] Test revision flow with real queue entry (admin comment → Claude revision → updated article)

### Phase 7: Featured Images (2-3 days)
- [x] Create ImageFinder module with X API image search
- [x] Implement `search_x_for_images/2` with lifestyle/graphic classification
- [x] ~~Implement `crop_to_square/1` via ImageMagick~~ — Skipped: ImageKit handles transforms on-the-fly
- [x] Implement `upload_to_s3/2` for processed images (content/featured/ path)
- [x] Store 3 image candidates in `article_data.image_candidates` in publish queue
- [ ] Build admin image selection UI (3 clickable thumbnails per article in review queue) — deferred to Phase 8
- [x] ~~Ensure ImageMagick available in Dockerfile~~ — Not needed: ImageKit handles transforms
- [x] Implement Unsplash API fallback when X API returns < 3 candidates
- [x] Auto-select best candidate as `featured_image` (admin can override in Phase 8)
- [ ] Test end-to-end: X search → download → S3 upload → admin select → publish

### Phase 8: Admin Dashboard & Monitoring (3-4 days)
- [ ] Add routes to router.ex (6 routes in admin live_session) — Section 15.2
- [ ] Create Dashboard LiveView (stat cards, queue preview, activity log, pause toggle) — Section 15.3
- [ ] Create Queue LiveView (filter/sort, expandable previews, approve/reject/edit) — Section 15.4
- [ ] Create EditArticle LiveView (reuse post form component, save draft, publish) — Section 15.5
- [ ] Create Feeds LiveView (toggle feeds, force poll, status display) — Section 15.8
- [ ] Create History LiveView (published/rejected, engagement metrics, filters) — Section 15.9
- [ ] Create Authors LiveView (persona stats, post counts, total reads) — Section 15.11
- [ ] Add PubSub broadcasts throughout pipeline for live dashboard updates
- [ ] Add pipeline_id logging throughout all modules
- [ ] Implement PostgreSQL cleanup task (7 days feed items, 48h completed queue entries)
- [ ] Add pipeline health monitoring (log daily: articles generated, published, rejected, errors)
- [ ] Error handling per Section 14.1 (graceful degradation, no retry queue)

### Phase 9: Testing & Launch (2 days)
- [ ] Integration test: full pipeline RSS → topic → generate → queue → approve → publish
- [ ] Load testing (simulate 20+ posts/day)
- [ ] Verify cost estimates against actual Claude API usage
- [ ] Test admin dashboard with real data (all 6 pages)
- [ ] Test error scenarios (feed down, Claude API error, X API rate limit)
- [ ] Documentation review

**Total estimated time: 18-23 days**

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

**Automated checks** (implemented — must pass before entering queue):

```elixir
defmodule BlocksterV2.ContentAutomation.QualityChecker do
  def validate(article) do
    checks = [
      {:word_count, check_word_count(article)},
      {:structure, check_structure(article)},
      {:duplicate, check_not_duplicate(article)},
      {:tags, check_tags(article)},
      {:tiptap_valid, check_tiptap_format(article.content)},
      {:image, check_image(article)}
    ]

    failures = Enum.filter(checks, fn {_, result} -> result != :ok end)

    if Enum.empty?(failures), do: :ok, else: {:reject, failures}
  end

  defp check_word_count(article) do
    count = ContentPublisher.count_words_in_tiptap(article.content)
    cond do
      count < 350 -> {:fail, "Too short: #{count} words (min 350)"}
      count > 1200 -> {:fail, "Too long: #{count} words (max 1200)"}
      true -> :ok
    end
  end

  defp check_structure(article) do
    content = article.content
    nodes = content["content"] || []
    paragraphs = Enum.count(nodes, & &1["type"] == "paragraph")

    cond do
      is_nil(article.title) or article.title == "" -> {:fail, "Missing title"}
      is_nil(article.excerpt) or article.excerpt == "" -> {:fail, "Missing excerpt"}
      paragraphs < 3 -> {:fail, "Only #{paragraphs} paragraphs (min 3)"}
      true -> :ok
    end
  end

  defp check_not_duplicate(article) do
    recent_titles = FeedStore.get_generated_topic_titles(days: 7)
    title_words = significant_words(article.title)

    is_dup = Enum.any?(recent_titles, fn recent ->
      recent_words = significant_words(recent)
      overlap = MapSet.intersection(title_words, recent_words) |> MapSet.size()
      min_size = min(MapSet.size(title_words), MapSet.size(recent_words))
      min_size > 0 and overlap / min_size > 0.6
    end)

    if is_dup, do: {:fail, "Too similar to recent article"}, else: :ok
  end

  defp check_tags(article) do
    tags = article.tags || []
    cond do
      length(tags) < 2 -> {:fail, "Only #{length(tags)} tags (min 2)"}
      length(tags) > 5 -> {:fail, "#{length(tags)} tags (max 5)"}
      true -> :ok
    end
  end

  defp check_tiptap_format(%{"type" => "doc", "content" => nodes}) when is_list(nodes), do: :ok
  defp check_tiptap_format(_), do: {:fail, "Invalid TipTap JSON format"}

  defp check_image(article) do
    if article.featured_image && article.featured_image != "", do: :ok,
    else: {:fail, "Missing featured image"}
  end

  defp significant_words(title) do
    stopwords = ~w(the a an is are was were be been have has had do does did
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

**Human-only checks** (admin reviews in edit page — cannot be automated reliably):
- Originality: No verbatim copying from sources
- Hallucinations: Facts match source material
- Tone: Matches editorial voice (not too neutral, not too extreme)
- Content safety: No financial advice, no conspiracy theories

These are the admin's job during the review step. The pipeline's strength is that it
**always** goes through human review (unless auto-publish is enabled for trusted output).

---

## 14.1 Error Handling & Recovery

### Pipeline Error Scenarios

| Scenario | Handling | Recovery |
|----------|----------|----------|
| **All RSS feeds fail** | FeedPoller logs warnings, reports 0 new items | TopicEngine skips cycle ("Only N items, skipping"). Pipeline resumes on next successful poll. |
| **Claude API 429 (rate limit)** | ClaudeClient retries once after 5s backoff | If retry fails, TopicEngine skips this cycle. 15-min interval = automatic retry. |
| **Claude API 500/error** | ClaudeClient returns `{:error, reason}` | TopicEngine logs error, skips cycle. No articles stuck — feed items stay unprocessed for next cycle. |
| **Claude returns bad output** | ClaudeClient validates tool_use response | Missing fields → `{:error, "No tool_use block"}`. Feed items remain unprocessed. |
| **QualityChecker rejects article** | Article NOT added to queue | Topic marked as processed (to prevent retry of same topic). Admin sees rejection in history. |
| **X API quota exhausted** | TweetFinder returns `[]` | Article publishes without tweets. Logged as warning. |
| **X image search fails** | ImageFinder returns empty candidates list | Article enters queue with no featured image. Admin can manually upload one before publishing. |
| **PostgreSQL transaction fails** | `Repo.transaction` rolls back both operations | Feed items stay unprocessed, topic not stored. Next cycle retries. |
| **Publishing fails** | `ContentPublisher.publish_article` returns `{:error, reason}` | Queue entry stays in "pending" status. Admin can retry via dashboard. |

### Key Design Decisions

1. **No retry queue**: Failed content generation skips the topic, doesn't retry. Why:
   - Same feed items will cluster into the same topic on the next cycle
   - If Claude consistently fails for a topic, it's likely a prompt issue, not transient
   - Simpler architecture, fewer failure modes

2. **Unprocessed items = automatic retry**: Feed items only get marked `processed: true`
   after their topic is successfully stored. If anything fails before that, the items
   appear in the next clustering cycle automatically.

3. **Graceful degradation**: Each optional step (tweets, images) has fallbacks.
   An article can publish with no tweets and a fallback image — it's still a valid post.

4. **Admin as final safety net**: Since articles go through the review queue,
   any pipeline bugs result in slightly-off articles that the admin catches, not
   broken content on the live site.

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
- **Featured image candidates**: Shows 3 clickable image options from X (lifestyle preferred, graphics as fallback). Admin clicks to select winner.
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

**LiveView Implementation**:
```elixir
defmodule BlocksterV2Web.ContentAutomationLive.Queue do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.ContentAutomation.FeedStore

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "content_automation")
    end

    socket =
      socket
      |> assign(page_title: "Article Queue")
      |> assign(filter_category: nil, filter_author: nil, sort: :newest)
      |> assign(expanded_previews: MapSet.new())
      |> start_async(:load_queue, fn -> FeedStore.get_pending_queue_entries() end)

    {:ok, socket}
  end

  def handle_async(:load_queue, {:ok, entries}, socket) do
    {:noreply, assign(socket, queue_entries: entries)}
  end

  def handle_event("filter", %{"category" => cat, "author" => author}, socket) do
    entries = FeedStore.get_pending_queue_entries(category: cat, author: author)
    {:noreply, assign(socket, queue_entries: entries, filter_category: cat, filter_author: author)}
  end

  def handle_event("toggle_preview", %{"id" => id}, socket) do
    expanded = socket.assigns.expanded_previews
    expanded = if MapSet.member?(expanded, id), do: MapSet.delete(expanded, id), else: MapSet.put(expanded, id)
    {:noreply, assign(socket, expanded_previews: expanded)}
  end

  def handle_event("quick_approve", %{"id" => id}, socket) do
    entry = FeedStore.get_queue_entry(id)
    case ContentAutomation.ContentPublisher.publish_from_queue(entry, %{}) do
      {:ok, post} ->
        FeedStore.mark_queue_entry_published(id, post.id)
        entries = Enum.reject(socket.assigns.queue_entries, &(&1.id == id))
        {:noreply, socket |> assign(queue_entries: entries) |> put_flash(:info, "Published: #{post.title}")}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Publish failed: #{inspect(reason)}")}
    end
  end

  def handle_event("reject", %{"id" => id, "reason" => reason}, socket) do
    FeedStore.reject_queue_entry(id, reason)
    entries = Enum.reject(socket.assigns.queue_entries, &(&1.id == id))
    {:noreply, socket |> assign(queue_entries: entries) |> put_flash(:info, "Article rejected")}
  end

  # Live updates from pipeline
  def handle_info({:content_automation, :article_generated, _article}, socket) do
    entries = FeedStore.get_pending_queue_entries()
    {:noreply, assign(socket, queue_entries: entries)}
  end
end
```

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

**LiveView Implementation**:
```elixir
defmodule BlocksterV2Web.ContentAutomationLive.Feeds do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.ContentAutomation.{FeedConfig, Settings, FeedStore}

  def mount(_params, _session, socket) do
    feeds = FeedConfig.get_all_feeds_with_status()
    disabled_feeds = Settings.get(:disabled_feeds, [])

    socket =
      socket
      |> assign(page_title: "Feed Management")
      |> assign(feeds: feeds, disabled_feeds: disabled_feeds)
      |> start_async(:load_feed_stats, fn -> FeedStore.get_feed_stats_last_24h() end)

    {:ok, socket}
  end

  def handle_async(:load_feed_stats, {:ok, stats}, socket) do
    {:noreply, assign(socket, feed_stats: stats)}
  end

  def handle_event("toggle_feed", %{"source" => source}, socket) do
    disabled = socket.assigns.disabled_feeds
    disabled = if source in disabled, do: List.delete(disabled, source), else: [source | disabled]
    Settings.set(:disabled_feeds, disabled)
    feeds = FeedConfig.get_all_feeds_with_status()
    {:noreply, assign(socket, disabled_feeds: disabled, feeds: feeds)}
  end

  def handle_event("force_poll", _params, socket) do
    # Send message to FeedPoller to trigger immediate poll cycle
    send({:global, BlocksterV2.ContentAutomation.FeedPoller}, :poll_now)
    {:noreply, put_flash(socket, :info, "Poll triggered — results will appear shortly")}
  end
end
```

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

**LiveView Implementation**:
```elixir
defmodule BlocksterV2Web.ContentAutomationLive.History do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.ContentAutomation.FeedStore

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Content History")
      |> assign(filter_status: "all", filter_period: "7d", page: 1)
      |> start_async(:load_history, fn -> load_history("all", "7d", 1) end)

    {:ok, socket}
  end

  def handle_async(:load_history, {:ok, {entries, summary}}, socket) do
    {:noreply, assign(socket, entries: entries, summary: summary)}
  end

  def handle_event("filter", %{"status" => status, "period" => period}, socket) do
    socket = start_async(socket, :load_history, fn -> load_history(status, period, 1) end)
    {:noreply, assign(socket, filter_status: status, filter_period: period, page: 1)}
  end

  def handle_event("load_page", %{"page" => page}, socket) do
    page = String.to_integer(page)
    socket = start_async(socket, :load_history, fn ->
      load_history(socket.assigns.filter_status, socket.assigns.filter_period, page)
    end)
    {:noreply, assign(socket, page: page)}
  end

  defp load_history(status, period, page) do
    days = case period do
      "24h" -> 1
      "7d" -> 7
      "30d" -> 30
      _ -> 7
    end

    since = DateTime.utc_now() |> DateTime.add(-days, :day)
    entries = FeedStore.get_history(status: status, since: since, page: page, per_page: 25)

    summary = %{
      published: FeedStore.count_published_since(since),
      rejected: FeedStore.count_rejected_since(since),
      top_category: FeedStore.top_category_since(since),
      most_read_post: FeedStore.most_read_automated_post_since(since)
    }

    {entries, summary}
  end
end
```

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
  image_search_queries: ["DeFi conference speakers", "SEC crypto regulation hearing", "blockchain trading desk"]
}
```

### 15.11 Authors Page (`/admin/content/authors`)

View and manage the automated content author personas.

```
┌─────────────────────────────────────────────────────────────────────┐
│  Author Personas                                                    │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌────────────┬───────────┬──────────────────────┬────────┬───────┐ │
│  │ Avatar     │ Username  │ Categories           │ Posts  │ Reads │ │
│  ├────────────┼───────────┼──────────────────────┼────────┼───────┤ │
│  │ [img]      │ maya_chen │ regulation, policy   │ 42     │ 3,210 │ │
│  │ [img]      │ jake_free │ bitcoin, mining,     │ 38     │ 2,890 │ │
│  │            │           │ energy               │        │       │ │
│  │ [img]      │ sophia_r  │ defi, nft, gaming,   │ 31     │ 2,150 │ │
│  │            │           │ metaverse, web3      │        │       │ │
│  │ [img]      │ alex_ward │ layer1, layer2,      │ 28     │ 1,980 │ │
│  │            │           │ ethereum, solana     │        │       │ │
│  │ [img]      │ marcus_st │ trading, market      │ 35     │ 2,670 │ │
│  │ [img]      │ nina_tak  │ ai, privacy, cbdc    │ 12     │  840  │ │
│  │ [img]      │ ryan_kolb │ security, mining,    │ 9      │  620  │ │
│  │            │           │ institutional        │        │       │ │
│  │ [img]      │ elena_vas │ stablecoin, defi,    │ 11     │  750  │ │
│  │            │           │ payments, cbdc       │        │       │ │
│  └────────────┴───────────┴──────────────────────┴────────┴───────┘ │
│                                                                     │
│  Total: 8 personas · 206 published articles · 15,110 total reads   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

**LiveView Implementation**:
```elixir
defmodule BlocksterV2Web.ContentAutomationLive.Authors do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.ContentAutomation.{AuthorRotator, FeedStore}
  alias BlocksterV2.{Repo, Accounts.User, Blog}
  import Ecto.Query

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(page_title: "Author Personas")
      |> start_async(:load_authors, fn -> load_author_stats() end)

    {:ok, socket}
  end

  def handle_async(:load_authors, {:ok, authors}, socket) do
    {:noreply, assign(socket, authors: authors)}
  end

  defp load_author_stats do
    personas = AuthorRotator.personas()

    # Load user accounts and post counts for each persona
    Enum.map(personas, fn persona ->
      user = Repo.get_by(User, email: "#{persona.username}@blockster.com")

      {post_count, total_reads} = if user do
        count = Repo.one(from p in Blog.Post, where: p.author_id == ^user.id, select: count(p.id))
        # Reads tracked in Mnesia engagement data - sum for all author's posts
        reads = FeedStore.count_reads_for_author(user.id)
        {count, reads}
      else
        {0, 0}
      end

      %{
        persona: persona,
        user: user,
        post_count: post_count,
        total_reads: total_reads
      }
    end)
  end
end
```

**Features**:
- Read-only view — personas are defined in code (`AuthorRotator.personas/0`), not editable via UI
- Shows post count and total reads per author for workload balancing
- Categories listed from persona definition
- Totals row at the bottom

### 15.12 Auto-Publish Option

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
