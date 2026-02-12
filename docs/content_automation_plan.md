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
├── feed_store.ex           # Mnesia storage for feed items
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

| # | Site | RSS Feed URL | Focus | Editorial Lean |
|---|------|-------------|-------|----------------|
| 1 | Bloomberg Crypto | `https://feeds.bloomberg.com/crypto/news.rss` | Markets, macro, institutional | Center-left, pro-establishment |
| 2 | Reuters Business | `https://www.reutersagency.com/feed/?best-topics=business-finance` | Breaking finance, regulation | Center, institutional |
| 3 | Financial Times | `https://www.ft.com/cryptofinance?format=rss` | Crypto finance, regulation, macro | Center-left, pro-regulation |
| 4 | The Economist | `https://www.economist.com/finance-and-economics/rss.xml` | Macro economics, policy, analysis | Center-left, globalist |
| 5 | Forbes Crypto | `https://www.forbes.com/crypto-blockchain/feed/` | Crypto business, profiles, markets | Center-right, business-friendly |
| 6 | Barron's | `https://www.barrons.com/feed?id=blog_rss` | Investment, markets, analysis | Center-right, Wall Street |
| 7 | TechCrunch Crypto | `https://techcrunch.com/category/cryptocurrency/feed/` | Web3 startups, VC, tech | Left-leaning, Silicon Valley |
| 8 | The Verge | `https://www.theverge.com/rss/index.xml` | Tech, crypto policy, culture | Left-leaning, consumer tech |

#### Standard Tier (weight: 1x) — Crypto-Native Sources

| # | Site | RSS Feed URL | Focus |
|---|------|-------------|-------|
| 9 | CoinDesk | `https://www.coindesk.com/arc/outboundfeeds/rss/` | General crypto, markets, regulation |
| 10 | CoinTelegraph | `https://cointelegraph.com/rss` | General crypto, DeFi, trading |
| 11 | The Block | `https://www.theblock.co/rss.xml` | Institutional, markets, data |
| 12 | Decrypt | `https://decrypt.co/feed` | General crypto, Web3, gaming |
| 13 | Bitcoin Magazine | `https://bitcoinmagazine.com/feed` | Bitcoin-focused, macro |
| 14 | Blockworks | `https://blockworks.co/feed` | DeFi, institutional, markets |
| 15 | DL News | `https://www.dlnews.com/arc/outboundfeeds/rss/` | Breaking news, investigations |
| 16 | The Defiant | `https://thedefiant.io/feed` | DeFi-focused |
| 17 | CryptoSlate | `https://cryptoslate.com/feed/` | General crypto, data |
| 18 | NewsBTC | `https://www.newsbtc.com/feed/` | Trading, price analysis |
| 19 | Bitcoinist | `https://bitcoinist.com/feed/` | Bitcoin, altcoins |
| 20 | U.Today | `https://u.today/rss` | General crypto, breaking news |
| 21 | Crypto Briefing | `https://cryptobriefing.com/feed/` | DeFi, research |
| 22 | BeInCrypto | `https://beincrypto.com/feed/` | General crypto, education |
| 23 | Unchained | `https://unchainedcrypto.com/feed/` | Long-form, interviews |
| 24 | CoinGape | `https://coingape.com/feed/` | Price, markets |
| 25 | Crypto Potato | `https://cryptopotato.com/feed/` | Trading, altcoins |
| 26 | AMBCrypto | `https://ambcrypto.com/feed/` | Analytics, on-chain data |
| 27 | Protos | `https://protos.com/feed/` | Investigations, deep dives |
| 28 | Milk Road | `https://www.milkroad.com/feed` | Macro, trends, accessible |

### 2.2 Elixir RSS Library

**Recommended**: `ElixirFeedParser` (`{:elixir_feed_parser, "~> 2.1"}`)
- Handles both RSS 2.0 and Atom feeds
- Returns structured data with title, description, link, published date
- Actively maintained
- Alternative: `FastRSS` (Rust NIF, faster but less Elixir-idiomatic)

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
    results = feeds
    |> Task.async_stream(&poll_single_feed/1, max_concurrency: 5, timeout: 30_000)
    |> Enum.flat_map(fn
      {:ok, items} -> items
      {:exit, _} -> []
    end)

    # Store new items, deduplicate by URL
    new_count = FeedStore.store_new_items(results)

    if new_count > 0 do
      # Notify TopicEngine that new items are available
      GenServer.cast({:global, TopicEngine}, :new_items_available)
    end

    schedule_poll()
    {:noreply, %{state | last_poll: DateTime.utc_now()}}
  end

  defp poll_single_feed(%{url: url, source: source, tier: tier}) do
    case Req.get(url, receive_timeout: 15_000) do
      {:ok, %{status: 200, body: body}} ->
        parsed = parse_feed(body)
        Enum.map(parsed.items, fn entry ->
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
      _ -> []
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

### 2.4 Feed Storage (Mnesia Table)

New Mnesia table `content_feed_items`:
```elixir
# In MnesiaInitializer
:mnesia.create_table(:content_feed_items, [
  attributes: [:url, :title, :summary, :source, :tier, :weight, :published_at,
               :fetched_at, :processed, :topic_cluster],
  index: [:source, :tier, :published_at, :processed],
  disc_copies: [node()]
])
```

- `tier` — `:premium` or `:standard` (from feed config)
- `weight` — `2.0` for premium, `1.0` for standard (used in TopicEngine ranking)

---

## 3. Topic Engine

### 3.1 Topic Clustering

The TopicEngine analyzes incoming feed items to identify trending stories and unique angles.

```elixir
defmodule BlocksterV2.ContentAutomation.TopicEngine do
  @analysis_interval :timer.minutes(15)

  # Groups feed items by topic using keyword extraction and similarity
  # Identifies which topics are trending (covered by 3+ sources)
  # Ranks topics by: recency, weighted source score, relevance to crypto categories
  #
  # WEIGHTING: Topics sourced from premium outlets (Bloomberg, FT, Reuters, etc.)
  # receive a 2x ranking boost. A topic covered by Bloomberg + CoinDesk scores
  # higher than one covered by CoinDesk + Bitcoinist alone.
  # Premium-sourced topics also produce longer, more analytical articles.

  # Categories to track:
  @categories [
    :defi, :rwa, :regulation, :gaming, :trading, :token_launches,
    :gambling, :privacy, :macro_trends, :investment, :bitcoin,
    :ethereum, :altcoins, :nft, :ai_crypto, :stablecoins, :cbdc,
    :security_hacks, :adoption, :mining
  ]

  def analyze_and_rank do
    # 1. Fetch unprocessed feed items from last 24 hours
    items = FeedStore.get_recent_unprocessed(hours: 24)

    # 2. Use Claude to cluster items into topics and extract angles
    topics = cluster_into_topics(items)

    # 3. Rank topics by weighted newsworthiness score
    ranked = rank_topics(topics)

    # 4. Filter out topics we've already covered
    filtered = filter_already_covered(ranked)

    # 5. Queue top topics for content generation
    Enum.take(filtered, 15)  # Keep pipeline fed
  end

  # Ranking formula: topics with premium sources score higher
  defp rank_topics(topics) do
    topics
    |> Enum.map(fn topic ->
      # Sum source weights (premium = 2.0, standard = 1.0)
      source_score = Enum.sum(Enum.map(topic.source_items, & &1.weight))

      # Recency bonus: newer topics score higher
      recency_score = recency_bonus(topic.newest_item_at)

      # Premium source bonus: topics with ANY premium source get extra priority
      has_premium = Enum.any?(topic.source_items, &(&1.tier == :premium))
      premium_bonus = if has_premium, do: 3.0, else: 0.0

      total_score = source_score + recency_score + premium_bonus

      Map.put(topic, :rank_score, total_score)
    end)
    |> Enum.sort_by(& &1.rank_score, :desc)
  end
end
```

### 3.2 Topic Analysis via Claude

Use Claude (Haiku for fast/cheap topic clustering, Sonnet for content generation):

```elixir
# Topic clustering prompt (sent to Claude Haiku - fast & cheap)
"""
Analyze these #{length(items)} crypto news articles and group them into distinct topics.
For each topic:
1. Topic title (concise)
2. Category: one of #{inspect(@categories)}
3. Source article URLs
4. Key facts and data points
5. 3 potential original angles that a pro-decentralization, anti-government-overreach
   commentary site could take on this story

Articles:
#{format_items(items)}

Return as JSON array.
"""
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

### 4.2 Claude Content Generation Pipeline

```elixir
defmodule BlocksterV2.ContentAutomation.ContentGenerator do
  @anthropic_url "https://api.anthropic.com/v1/messages"
  @model "claude-sonnet-4-5-20250929"  # Good balance of quality/cost

  def generate_article(topic, author_persona) do
    prompt = build_generation_prompt(topic, author_persona)

    case call_claude(prompt) do
      {:ok, response} ->
        # Parse Claude's response into structured article
        article = parse_article_response(response)

        # Convert to TipTap JSON format
        tiptap_content = to_tiptap_json(article)

        {:ok, %{
          title: article.title,
          content: tiptap_content,
          excerpt: article.excerpt,
          category: topic.category,
          tags: article.tags,
          featured_image_query: article.image_suggestion
        }}

      {:error, reason} -> {:error, reason}
    end
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

    OUTPUT FORMAT (return as JSON):
    {
      "title": "Catchy, opinionated headline (max 80 chars)",
      "excerpt": "One-sentence summary for cards/social (max 160 chars)",
      "sections": [
        {"type": "paragraph", "text": "..."},
        {"type": "heading", "level": 2, "text": "..."},
        {"type": "blockquote", "text": "..."},
        {"type": "tweet_suggestion", "search_query": "relevant twitter search for embedding"}
      ],
      "tags": ["bitcoin", "regulation", "fed"],
      "image_suggestion": "search query for unsplash/stock photo"
    }
    """
  end
end
```

### 4.3 TipTap JSON Conversion

Convert Claude's structured output to Blockster's exact TipTap format:

```elixir
defmodule BlocksterV2.ContentAutomation.TipTapBuilder do
  @doc """
  Converts article sections into TipTap JSON that the renderer expects.
  """
  def build(sections) do
    content = Enum.flat_map(sections, &section_to_nodes/1)
    %{"type" => "doc", "content" => content}
  end

  defp section_to_nodes(%{"type" => "paragraph", "text" => text}) do
    [%{"type" => "paragraph", "content" => parse_inline_marks(text)}]
  end

  defp section_to_nodes(%{"type" => "heading", "level" => level, "text" => text}) do
    [%{"type" => "heading", "attrs" => %{"level" => level},
       "content" => [%{"type" => "text", "text" => text}]}]
  end

  defp section_to_nodes(%{"type" => "blockquote", "text" => text}) do
    [%{"type" => "blockquote", "content" => [
      %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => text}]}
    ]}]
  end

  defp section_to_nodes(%{"type" => "tweet", "url" => url, "id" => id}) do
    [%{"type" => "tweet", "attrs" => %{"url" => url, "id" => id}}]
  end

  defp section_to_nodes(%{"type" => "spacer"}) do
    [%{"type" => "spacer"}]
  end

  # Parse bold, italic, links from markdown-style text
  defp parse_inline_marks(text) do
    # Convert **bold** to marks, *italic* to marks, [text](url) to links
    # Returns list of TipTap inline nodes with marks
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

```elixir
# Migration or seed script
for persona <- AuthorRotator.personas() do
  BlocksterV2.Accounts.create_user(%{
    email: persona.email,
    username: persona.username,
    auth_method: "internal",  # Not accessible via login
    avatar_url: persona.avatar_url  # Pre-generated or stock photo
  })
end
```

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
    EngagementTracker.set_post_bux_pool(post.id, bux_pool)

    # 5. Notify SortedPostsCache to include new post
    BlocksterV2.SortedPostsCache.refresh()

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
  @publishing_hours 6..22      # Publish between 6am-10pm UTC
  @min_gap_minutes 60          # At least 1 hour between posts

  # Queue holds generated articles waiting to be published
  # Publishes at calculated intervals throughout the day

  def schedule_next_publish do
    hours_remaining = 22 - DateTime.utc_now().hour
    posts_remaining = @posts_per_day - posts_published_today()

    if posts_remaining > 0 and hours_remaining > 0 do
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

## 9. Database & Mnesia Changes

### 9.1 New Mnesia Tables

```elixir
# Feed items storage
:mnesia.create_table(:content_feed_items, [
  attributes: [:url, :title, :summary, :source, :published_at, :fetched_at,
               :processed, :topic_cluster_id],
  index: [:source, :processed, :published_at],
  disc_copies: [node()]
])

# Generated content tracking (prevent duplicates)
:mnesia.create_table(:content_generated_topics, [
  attributes: [:topic_id, :topic_title, :category, :source_urls, :article_id,
               :generated_at, :published_at, :author_id],
  index: [:category, :generated_at],
  disc_copies: [node()]
])

# Publishing schedule
:mnesia.create_table(:content_publish_queue, [
  attributes: [:id, :article_data, :author_id, :scheduled_at, :status, :created_at],
  index: [:status, :scheduled_at],
  disc_copies: [node()]
])
```

### 9.2 No PostgreSQL Schema Changes Required

Posts use the existing `posts` table with all needed fields. Author personas are regular User records.

---

## 10. Configuration

### 10.1 Application Config

```elixir
# config/runtime.exs
config :blockster_v2, :content_automation,
  enabled: System.get_env("CONTENT_AUTOMATION_ENABLED", "false") == "true",
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  x_bearer_token: System.get_env("X_BEARER_TOKEN"),
  unsplash_access_key: System.get_env("UNSPLASH_ACCESS_KEY"),
  posts_per_day: String.to_integer(System.get_env("CONTENT_POSTS_PER_DAY", "10")),
  claude_model: System.get_env("CONTENT_CLAUDE_MODEL", "claude-sonnet-4-5-20250929"),
  default_bux_reward: 5,
  default_bux_pool: 100,
  feed_poll_interval: :timer.minutes(5),
  topic_analysis_interval: :timer.minutes(15)
```

### 10.2 Required Environment Variables / Fly Secrets

```bash
flyctl secrets set \
  CONTENT_AUTOMATION_ENABLED=true \
  ANTHROPIC_API_KEY=sk-ant-... \
  X_BEARER_TOKEN=AAAA... \
  UNSPLASH_ACCESS_KEY=... \
  CONTENT_POSTS_PER_DAY=10 \
  --app blockster-v2
```

---

## 11. Cost Estimates

| Service | Usage | Monthly Cost |
|---------|-------|-------------|
| Claude Sonnet (content) | 10 articles/day × 30 = 300 calls, ~500 tokens in / ~2000 out each | ~$10-15 |
| Claude Haiku (topic analysis) | 96 calls/day (every 15 min) × 30 = 2,880 calls | ~$3-5 |
| X API (tweets) | Basic tier, ~300 searches/month | $100 |
| Unsplash | Free tier (50 req/hour) | $0 |
| **Total** | | **~$115-120/month** |

**Alternative without X API**: Use curated tweet list approach → **$15-20/month total**

---

## 12. Supervision Tree Integration

```elixir
# In application.ex, add to children list:
{BlocksterV2.ContentAutomation.FeedPoller, []},
{BlocksterV2.ContentAutomation.TopicEngine, []},
{BlocksterV2.ContentAutomation.ContentQueue, []},
```

All GenServers use `GlobalSingleton` for cluster-wide single instance (same pattern as PriceTracker, BetSettler).

---

## 13. Implementation Phases

### Phase 1: RSS Infrastructure (2-3 days)
- [ ] Add `elixir_feed_parser` to mix.exs
- [ ] Create FeedPoller GenServer
- [ ] Create FeedStore (Mnesia table)
- [ ] Configure 20 RSS feed URLs
- [ ] Test feed polling and storage
- [ ] Add to supervision tree (behind feature flag)

### Phase 2: Topic Engine (2-3 days)
- [ ] Create TopicEngine GenServer
- [ ] Implement Claude Haiku topic clustering
- [ ] Add category classification
- [ ] Implement deduplication (don't cover same topic twice)
- [ ] Test topic ranking and selection

### Phase 3: Content Generation (3-4 days)
- [ ] Create ContentGenerator with Claude Sonnet integration
- [ ] Build PromptTemplates module with editorial voice
- [ ] Create TipTapBuilder (JSON conversion)
- [ ] Implement article quality checks (word count, structure, originality)
- [ ] Test full generation pipeline

### Phase 4: Author Personas (1 day)
- [ ] Create AuthorRotator module with 5 personas
- [ ] Create User accounts in database for each persona
- [ ] Generate/upload avatar images
- [ ] Test author selection and rotation

### Phase 5: Publishing Pipeline (2-3 days)
- [ ] Create ContentPublisher module
- [ ] Implement BUX pool assignment
- [ ] Create ContentQueue with scheduling
- [ ] Test end-to-end: RSS → topic → generate → publish
- [ ] Verify posts appear correctly on frontend

### Phase 6: Tweet Integration (2 days)
- [ ] Create TweetFinder module
- [ ] Integrate X API (or curated list alternative)
- [ ] Embed tweets in TipTap content
- [ ] Test tweet rendering in published posts

### Phase 7: Featured Images (1 day)
- [ ] Create ImageFinder module (Unsplash integration)
- [ ] Map categories to fallback images
- [ ] Test image attachment to posts

### Phase 8: Monitoring & Polish (2 days)
- [ ] Add logging and error tracking
- [ ] Create admin dashboard page for content pipeline status
- [ ] Add manual override controls (pause, force publish, reject topic)
- [ ] Load testing (simulate 20+ posts/day)
- [ ] Documentation

**Total estimated time: 15-19 days**

---

## 14. Quality Control Checks

Before publishing, each article must pass:

1. **Word count**: 350-600 words (2 min read)
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

## 15. Admin Controls

Add a simple admin page at `/admin/content-automation`:

- **Status**: Running/Paused, feeds active, articles generated today
- **Queue**: Upcoming articles waiting to publish (with preview)
- **History**: Recently published automated articles
- **Controls**: Pause/resume, force generate, reject from queue
- **Metrics**: Articles per day, categories distribution, top performing automated posts

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
