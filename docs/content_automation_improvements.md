# Content Automation System - Improvements & Bug Fixes

## Overview

This document covers all pending improvements, bug fixes, and new features for the Blockster content automation system. The system auto-generates crypto articles from RSS feeds using Claude, manages them through an admin review queue, and publishes them with optional auto-tweeting via the @BlocksterCom X account.

---

## 1. Preview Button (Draft Mode for Posts)

### Problem
There is no way for an admin to preview how an article will look on the live site before publishing. Currently articles go from "queue" directly to "published" with no intermediate preview.

### Current State
- Posts are created via `ContentPublisher.publish_queue_entry/1` which calls `Blog.create_post/1` followed by `Blog.publish_post/1`
- `Blog.publish_post/1` sets `published_at` timestamp (see `lib/blockster_v2/blog/post.ex:194`)
- The Post show page (`lib/blockster_v2_web/live/post_live/show.ex:40`) loads posts via `Blog.get_post_by_slug(slug)` with **no visibility check** — any slug is accessible
- There is no `status` field on the Post schema — publication is determined by whether `published_at` is nil or not
- The `SortedPostsCache` and listing pages only show published posts (those with `published_at` set)

### Solution Design
Create a "preview as draft" flow that:
1. Creates the post in the database **without** calling `Blog.publish_post/1` (leaves `published_at` as nil)
2. Generates a preview URL like `/preview/:slug?token=<admin_token>` or simply `/:slug` with admin access check
3. The post won't appear in any listing, cache, or search because `published_at` is nil
4. Admin can view it at its real slug URL, verify it looks good, then publish from the queue page
5. If rejected, the draft post is deleted from the `posts` table

### Key Files
| File | Purpose |
|------|---------|
| `lib/blockster_v2/blog/post.ex` | Post schema, `publish/1` function |
| `lib/blockster_v2/blog.ex` | `create_post/1`, `publish_post/1`, `get_post_by_slug/1` |
| `lib/blockster_v2_web/live/post_live/show.ex` | Post show page — needs admin access check for unpublished |
| `lib/blockster_v2_web/live/content_automation_live/queue.ex` | Queue page — needs "Preview" button |
| `lib/blockster_v2_web/live/content_automation_live/edit_article.ex` | Edit page — needs "Preview" button |
| `lib/blockster_v2/content_automation/content_publisher.ex` | Publishing pipeline — needs draft creation path |

### Security Note
**Currently, unpublished posts are fully accessible to anyone who knows the slug URL.** `PostLive.Show` (`show.ex:40`) calls `Blog.get_post_by_slug(slug)` which fetches ANY post regardless of `published_at` status. There is NO access control check. As of Feb 14 2026, **6 unpublished posts exist in production** and are accessible to anyone who guesses the slug. This needs to be fixed regardless of the preview feature.

### Implementation Notes
- The simplest approach: create the post without publishing (leave `published_at = nil`), store the `post_id` on the queue entry, and add a "Preview" link that goes to `/:slug`
- In `show.ex`, check if `post.published_at` is nil. If so, only allow access if `current_user` is admin
- Non-admin visitors to an unpublished slug should get a 404
- The post won't appear in `SortedPostsCache`, category pages, or tag pages because those all filter by `published_at`
- Add a "DRAFT PREVIEW" banner at the top of the page when admin is viewing an unpublished post

---

## 2. Reject Modal Bug (Textarea Disappears on Click)

### Problem
When admin clicks "Reject" on the queue page, the rejection reason modal appears, but clicking into the textarea to type a reason causes the entire modal to disappear.

### Current State
The reject modal in `lib/blockster_v2_web/live/content_automation_live/queue.ex:355-376`:

```heex
<div class="fixed inset-0 z-50 flex items-center justify-center bg-black/40" phx-click="close_reject">
  <div class="bg-white rounded-xl shadow-xl p-6 w-full max-w-md" phx-click-away="close_reject">
```

### Root Cause
**Two competing close handlers**: The outer overlay has `phx-click="close_reject"` AND the inner modal has `phx-click-away="close_reject"`. When the user clicks the textarea inside the modal, the click event bubbles up to the overlay div, triggering `close_reject`. The `phx-click-away` is redundant and also fires.

### Fix
Remove `phx-click="close_reject"` from the outer overlay div. Keep only `phx-click-away="close_reject"` on the inner modal div. Alternatively, add `phx-click-stop` on the inner modal to prevent event bubbling.

### Key File
- `lib/blockster_v2_web/live/content_automation_live/queue.ex` — lines 355-376

---

## 3. X/Twitter Account Connection for lidia@blockster.com

### Problem
The auto-tweeting system needs to know which user's X connection to use for posting tweets as @BlocksterCom. Currently the `BRAND_X_USER_ID` Fly secret determines this. Lidia's account needs to be the one that connects the @BlocksterCom X account.

### Current State
- `Config.brand_x_user_id/0` reads from `BRAND_X_USER_ID` env var (see `lib/blockster_v2/content_automation/config.ex:24`)
- `config/runtime.exs:66-70` parses it as an integer
- `ContentPublisher.get_brand_access_token/0` (line 201) uses this ID to look up the X connection in Mnesia via `Social.get_x_connection_for_user(brand_user_id)`
- The X OAuth flow is handled by the existing X connection system (`x_connections` Mnesia table)

### Lidia's User ID
**lidia@blockster.com = user_id `7`** (confirmed from production database query).

### Current State (queried from production)
- **@BlocksterCom** (X user ID `1350269503033245704`) is currently connected to **user 18** (`lidia+1@blockster.com`)
- User 18 has `locked_x_user_id = "1350269503033245704"` in PostgreSQL
- **User 7** (`lidia@blockster.com`) has `locked_x_user_id = nil` — no X lock yet
- The `BRAND_X_USER_ID` secret has not been set yet

### Action Required (in order)

**Step 1: Clear the existing @BlocksterCom connection from user 18**
```bash
# Clear the locked_x_user_id on user 18 (PostgreSQL)
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc '
alias BlocksterV2.{Repo, Accounts.User}
user = Repo.get!(User, 18)
user |> Ecto.Changeset.change(%{locked_x_user_id: nil}) |> Repo.update!()
IO.puts(\"Cleared locked_x_user_id for user 18\")
'"

# Delete the x_connections Mnesia record for user 18
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc '
:mnesia.dirty_delete(:x_connections, 18)
IO.puts(\"Deleted x_connections Mnesia record for user 18\")
'"
```

**Step 2: Set the Fly secret**
```bash
flyctl secrets set BRAND_X_USER_ID=7 --app blockster-v2
```

**Step 3: Lidia connects @BlocksterCom via OAuth**
- Lidia logs into blockster.com as `lidia@blockster.com`
- Goes to `/auth/x` to connect her X account
- Authorizes the @BlocksterCom X account
- This creates an `x_connections` Mnesia record for user 7 and sets `locked_x_user_id` on her account

**Step 4: Verify**
```bash
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc '
BlocksterV2.Social.get_x_connection_for_user(7) |> IO.inspect(label: \"lidia_x_connection\")
'"
```

### Notes
- **X account locking**: Once Lidia connects @BlocksterCom, her account becomes permanently locked to that X user ID. No other Blockster user can connect the same X account.
- **Token management**: Access tokens expire after 2 hours. The system auto-refreshes within a 5-minute buffer before API calls (`ContentPublisher.ensure_fresh_token/1`).

### Key Files
| File | Purpose |
|------|---------|
| `lib/blockster_v2/content_automation/config.ex:24` | `brand_x_user_id/0` reader |
| `config/runtime.exs:66-70` | Env var parsing |
| `lib/blockster_v2/content_automation/content_publisher.ex:201-212` | Brand token lookup |
| `lib/blockster_v2/social.ex` | `get_x_connection_for_user/1` |

---

## 4. Production Scheduler — Status & Known Risk

### Production Status (verified Feb 14 2026)
**The scheduler IS currently running.** All three GenServers are registered globally:
- `FeedPoller` — actively polling (latest feed item: Feb 14 19:20 UTC, 668 total items)
- `TopicEngine` — actively generating (latest topic: "Ethereum Foundation Leadership Transition" at 19:04 UTC, 35 total topics)
- `ContentQueue` — actively publishing (latest publish: 15:33 UTC today)

**Pipeline stats**: 15 pending, 1 draft, 7 published, 11 rejected in queue.
34 unprocessed feed items available in the last 12 hours.

**Config confirmed**: `CONTENT_AUTOMATION_ENABLED=true`, `ANTHROPIC_API_KEY` set, all 8 author personas exist (IDs 300-307), pipeline NOT paused.

**The queue is over capacity**: 15 pending + 1 draft = 16 queued articles vs default `target_queue_size` of 10. This means TopicEngine is currently **skipping generation cycles** because the queue is full. Articles need to be approved/rejected/published to free up slots.

### Original Complaint
The admin reported "scheduler in production didn't work." Since the scheduler IS currently working, the original issue was likely one of:
1. **Queue was full** — once 10+ articles accumulated in pending/draft/approved, generation stopped until slots freed up. This is the most likely explanation given current state (16 queued vs 10 target).
2. **Transient issue after a deploy** — the GlobalSingleton rolling deploy risk (see below) may have caused a temporary outage that resolved after a restart.
3. **Admin checked before the first cycle** — FeedPoller waits 30s, TopicEngine waits 60s after startup.

### Latent Risk: GlobalSingleton + Rolling Deploy

This is NOT the current problem, but it IS a real architectural risk that could cause future outages. During a rolling deploy:

1. Node A (old) has FeedPoller, TopicEngine, ContentQueue running
2. Node B (new) starts → `GlobalSingleton` finds them on Node A → returns `:ignore` → supervisor records child as started
3. Node A shuts down → processes die → global names unregistered
4. Node B's supervisor already completed startup → **processes are NOT restarted**

The supervisor uses `one_for_one` strategy, but since the children returned `:ignore` (not `{:ok, pid}`), there's no PID to monitor.

**Mitigation options**:
- Add a periodic health check GenServer that re-registers if global names are undefined
- Use `Horde` for distributed supervision instead of `GlobalSingleton`
- After deploy, manually restart the app: `flyctl apps restart blockster-v2`
- Scale to 1 machine before deploying, then scale back up

### Debugging Commands (for future issues)
```bash
# Check if GenServers are running
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc ':global.registered_names() |> IO.inspect()'"

# Check queue size vs target
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc 'alias BlocksterV2.ContentAutomation.FeedStore; IO.inspect(FeedStore.count_queued(), label: \"queued\")'"

# Check feed item count
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc 'alias BlocksterV2.ContentAutomation.FeedStore; FeedStore.get_recent_unprocessed(hours: 12) |> length() |> IO.inspect()'"

# Force a poll + analysis cycle
flyctl ssh console --app blockster-v2 -C "bin/blockster_v2 rpc 'BlocksterV2.ContentAutomation.FeedPoller.force_poll(); Process.sleep(5000); BlocksterV2.ContentAutomation.TopicEngine.force_analyze()'"
```

### Key Files
| File | Purpose |
|------|---------|
| `lib/blockster_v2/application.ex:56-63` | Conditional startup |
| `lib/blockster_v2/content_automation/feed_poller.ex` | RSS polling GenServer |
| `lib/blockster_v2/content_automation/topic_engine.ex` | Topic analysis + article generation |
| `lib/blockster_v2/content_automation/content_queue.ex` | Publish scheduler |
| `config/runtime.exs:55-73` | Runtime config |

---

## 5. On-Demand Article Generation Page

### Problem
Admin wants to request a specific article on any topic, bypassing the RSS feed pipeline entirely. The generated article should appear in the same edit UI with tweet ready, and these on-demand requests should be processed immediately regardless of pending queue size.

### Current State
- No on-demand generation UI exists
- `ContentGenerator.generate_article/1` takes a topic map with `feed_items`, `title`, `category`, etc.
- The full edit UI exists at `lib/blockster_v2_web/live/content_automation_live/edit_article.ex`

### Solution Design
Create a new LiveView page at `/admin/content/request`:

1. **Admin form fields**:
   - Topic/headline (required) — what the article should be about
   - Category (dropdown, required) — which category to assign
   - Key details/instructions (textarea, required) — specific details, links, data points
   - Angle/perspective (textarea, optional) — editorial angle to take
   - Author persona (dropdown, optional) — override auto-selection
   - Priority flag — "generate immediately"

2. **Generation flow**:
   - Admin submits form
   - System creates a synthetic "topic" (no feed items needed)
   - Uses `start_async` to call Claude with admin-provided details as the source material
   - On success, creates a queue entry with status "pending" and redirects to the edit page
   - Bypasses queue size limits entirely (these are admin-requested, not automated)

3. **Modified prompt**: Instead of source material from RSS feeds, the prompt uses the admin's detailed instructions as the source material. The system should do a web search or use the admin's provided links to gather facts.

### Key Files to Create/Modify
| File | Action |
|------|--------|
| `lib/blockster_v2_web/live/content_automation_live/request_article.ex` | **Create** — new LiveView |
| `lib/blockster_v2_web/router.ex` | Add route `live "/admin/content/request", ContentAutomationLive.RequestArticle, :new` |
| `lib/blockster_v2/content_automation/content_generator.ex` | Add `generate_on_demand/1` for admin-requested articles |
| `lib/blockster_v2_web/live/content_automation_live/dashboard.ex` | Add "Request Article" button |

---

## 6. Link Quality in AI-Generated Articles

### Problem
Auto-generated articles contain links that don't point to the correct deep pages. Links often point to the homepage of a website instead of the specific report, announcement, or story being referenced. Asking for link corrections via the AI revision box doesn't fix this either.

### Root Cause (Confirmed by codebase analysis)
**Source URLs are NOT passed to Claude in the generation prompt.** This is the definitive root cause.

`ContentGenerator.format_source_summaries/1` (line 277-285) formats source items as:
```elixir
"#{tier_label}#{item.source}: #{item.title}\n#{summary}"
```
Note: **NO URL included!** The `ContentFeedItem` records have a `url` field, but it's stripped out before sending to Claude.

Meanwhile, `TopicEngine.format_items_for_prompt/1` (line 254-263) DOES include URLs:
```elixir
"#{idx}. #{source_label}: \"#{item.title}\"\n   URL: #{item.url}\n   #{summary}\n"
```
But this is only for topic selection/clustering, NOT for article generation.

So when the prompt says "Link to PRIMARY SOURCES" (line 239-248), Claude has NO actual URLs to work with. It hallucinates links from its training data, which are often wrong or point to homepages.

The revision prompt (`EditorialFeedback.build_revision_prompt/3`) also doesn't include source URLs, so asking for link corrections via revision can't work either — Claude still has no verified URLs to use.

Additionally, source URLs are NOT stored in `article_data` when the queue entry is created (`enqueue_article/4` at line 115-134), so the edit page's "Source Articles" section may show empty.

### Solution

1. **Pass source URLs explicitly to Claude**: Include the full list of source article URLs in the prompt with instructions to use THESE specific URLs when linking:
   ```
   AVAILABLE SOURCE URLs (use these for linking, they are VERIFIED):
   - CoinDesk: https://coindesk.com/full-article-path (Topic: "Bitcoin ETF approval")
   - Bloomberg: https://bloomberg.com/full-article-path (Topic: "SEC ruling")
   ```

2. **In the revision prompt**: When admin asks to fix links, include the source URLs so Claude can reference them:
   ```
   SOURCE URLs FROM ORIGINAL RESEARCH (use these for any link corrections):
   [list of verified URLs from the topic's feed_items]
   ```

3. **Post-processing link validator**: After Claude generates the article, check each `[text](url)` link and:
   - Verify it's a valid URL format
   - Remove links that point to homepages (path is `/` or empty)
   - Flag suspicious links for admin review

4. **Explicit instruction not to fabricate URLs**: Add to the prompt:
   ```
   CRITICAL: ONLY use URLs from the SOURCE MATERIAL list above. NEVER fabricate or guess URLs.
   If you cannot find a specific URL for a claim, do not add a link — state the fact without linking.
   ```

### Key Files
| File | Lines | Change |
|------|-------|--------|
| `lib/blockster_v2/content_automation/content_generator.ex` | 177-264 | Add source URLs to prompt, add anti-fabrication instruction |
| `lib/blockster_v2/content_automation/editorial_feedback.ex` | 233-270 | Include source URLs in revision prompt |
| `lib/blockster_v2/content_automation/tiptap_builder.ex` | — | Optional: add link validation in `build/1` |

---

## 7. Editorial Memory Box Error

### Problem
When admin tries to add comments to the editorial memory box on the edit page, they get an error.

### Production Status (verified Feb 14 2026)
**The editorial memory table EXISTS and is functional.** Production query found **2 memories** already saved:
1. A "tone" memory about avoiding the negative-to-positive writing pattern (the exact issue from Section 8)
2. Another saved memory entry

So the table is not missing, and memories CAN be saved. The error is likely **intermittent or input-specific**.

### Current State
- Memory form at `edit_article.ex:784-805` submits `phx-submit="add_memory"` with `instruction` and `category` params
- Handler at `edit_article.ex:243-267` calls `EditorialFeedback.add_memory/2`
- `ContentEditorialMemory` schema (`content_editorial_memory.ex`) validates: `instruction` required, length 5-500, `category` must be in `["global", "tone", "terminology", "topics", "formatting"]`

### Likely Causes (given table exists and works)
1. **Instruction too short**: Validation requires minimum 5 characters (`validate_length(:instruction, min: 5, max: 500)`) — short inputs like "ok" or "fix" will produce a changeset error
2. **Category mismatch**: Ruled out — form dropdown values (`@memory_categories` at line 7) match schema enum exactly
3. **Error display**: Handler at line 262-264 DOES surface changeset errors via `put_flash(:error, ...)` — errors are shown
4. **Possible misattribution**: The error may have originated from a different part of the edit page (e.g., a revision or other form action) and was attributed to the memory box

### Code Analysis (verified)
The handler at `edit_article.ex:243-267` DOES show errors — it calls `Ecto.Changeset.traverse_errors` and displays via `put_flash(:error, ...)`. So errors are surfaced to the user.

### Investigation Steps
- Ask admin to reproduce the exact error message they saw
- Test with edge cases: whitespace-only input (trimmed to empty → caught), exactly 5 chars after trim, >500 chars
- Check if the error was actually from a different part of the edit page (e.g., a revision or form error attributed to the memory box)
- Check production logs around the time the error occurred for stack traces

### Key Files
| File | Purpose |
|------|---------|
| `lib/blockster_v2_web/live/content_automation_live/edit_article.ex:243-267` | Event handler |
| `lib/blockster_v2/content_automation/editorial_feedback.ex:78-89` | `add_memory/2` |
| `lib/blockster_v2/content_automation/content_editorial_memory.ex` | Schema + validation |

---

## 8. Writing Style Issues (Negative/Positive Pattern)

### Problem
The AI-generated articles have a repetitive writing pattern: a negative observation followed by a positive spin. This "but actually" structure is overused and makes articles feel formulaic.

### Current Prompt (from `content_generator.ex:189-201`)
```
VOICE & STYLE:
- Opinionated and direct. You believe in decentralization, sound money, and individual freedom.
- Skeptical of government regulation, central banks, and surveillance.
- POSITIVE AND OPTIMISTIC — you are enthusiastic about the future of crypto and decentralization.
  You point out problems but always offer solutions or silver linings.
```

### Root Cause
The prompt explicitly instructs Claude to be skeptical (negative) AND positive/optimistic, which naturally produces the "here's the bad thing... but here's why it's actually good" pattern. The `COUNTER-NARRATIVE FRAMING` section (lines 210-222) reinforces this by saying to take mainstream framing and flip it.

### Fix
Update the prompt to:
1. Vary article structures — not every article needs a counter-narrative
2. Explicitly list **multiple** article opening styles to prevent repetitive hooks
3. Add instruction: "AVOID the pattern of presenting a negative followed by a positive spin. Vary your rhetorical structure — sometimes lead with opportunity, sometimes with analysis, sometimes with data."
4. Add variety instructions:
   ```
   STRUCTURAL VARIETY (rotate between these approaches):
   - Data-first: Lead with numbers, stats, or on-chain data. Let the data tell the story.
   - Narrative: Tell the story of a specific project, person, or event chronologically.
   - Analysis: Deep-dive into what happened and why it matters, without the negative/positive seesaw.
   - Opinion: State your position upfront and defend it with evidence.
   - Trend report: Survey multiple related developments and identify the pattern.
   - Interview-style: Frame the article around key quotes from industry figures.

   DO NOT default to the "here's the problem... but actually it's good" structure.
   This pattern is overused. Mix it up.

   BANNED PHRASES (never use these):
   - "X is a feature, not a bug" — cliché, overused in crypto writing
   - "And that's the point." — overused as a sentence-ending mic drop
   ```

### Key File
- `lib/blockster_v2/content_automation/content_generator.ex:186-264` — `build_generation_prompt/4`

---

## 9. Content Diversity — Expanding Topic Coverage

### Problem
Auto-generated content is too heavily focused on Bitcoin and Ethereum price/regulation stories. The system needs much broader topic diversity.

### Current State
- Categories exist: `defi rwa regulation gaming trading token_launches gambling privacy macro_trends investment bitcoin ethereum altcoins nft ai_crypto stablecoins cbdc security_hacks adoption mining` (see `topic_engine.ex:28-32`)
- TopicEngine has category diversity limits (`max_per_day: 2` default per category in `apply_category_diversity/1`)
- Target queue size is `10` (default in `settings.ex:13`)
- Feed sources are primarily crypto-native news sites

### Required New Content Types

The following content categories need to be added or boosted:

#### 9.1 RWA (Real World Assets) Stories
- Tokenization of real estate, bonds, commodities
- RWA protocol launches and milestones
- Institutional RWA adoption

#### 9.2 DeFi Offers & Opportunities
- New DeFi protocols and yield opportunities
- Protocol updates and governance changes
- DeFi security and audit news

#### 9.3 Token Launches
- New token launches and TGEs
- Airdrop campaigns
- Token migration and upgrade events

#### 9.4 Exchange Offers
- CEX and DEX promotions
- New listing announcements
- Exchange feature launches

#### 9.5 Altcoin Trending Analysis
- What altcoins are performing well and WHY
- What altcoins are declining and WHY
- Market cap movements and rotation patterns

#### 9.6 Upcoming Events
- Major crypto conferences and events for the coming month
- Protocol upgrade dates and milestones
- Regulatory deadlines and hearings

#### 9.7 Fundraising & VC Activity
- Who raised money, how much, from whom, for what
- VC firm activity and portfolio movements
- Seed/Series A/B rounds in crypto

#### 9.8 Blockster of the Week
- Featured thought leader profile
- Their achievements, quotes, and contributions
- Why they embody the "Blockster" ethos (someone into web3/crypto)
- Biographical deep-dive with direct quotes

### Solution

1. **Increase default queue size to 20**: Change `@defaults` in `settings.ex:13` from `target_queue_size: 10` to `target_queue_size: 20`

2. **Add new category types**: Add to `@categories` in `topic_engine.ex`:
   - `fundraising` — VC rounds, fundraising news
   - `events` — upcoming conferences, protocol milestones
   - `blockster_of_the_week` — thought leader features

3. **Update clustering prompt**: In `build_clustering_prompt/1`, add instructions to identify these new content types from feed items

4. **Add category boost config**: Use `Settings.set(:category_config, ...)` to boost underrepresented categories:
   ```elixir
   %{
     "rwa" => %{boost: 3, max_per_day: 3},
     "defi" => %{boost: 2, max_per_day: 3},
     "token_launches" => %{boost: 2, max_per_day: 2},
     "altcoins" => %{boost: 2, max_per_day: 3},
     "fundraising" => %{boost: 3, max_per_day: 2},
     "events" => %{boost: 2, max_per_day: 2},
     "bitcoin" => %{boost: 0, max_per_day: 2},  # reduce dominance
     "ethereum" => %{boost: 0, max_per_day: 2}   # reduce dominance
   }
   ```

5. **Add RSS feeds for underrepresented topics**: Add feeds from RWA-focused, DeFi-focused, and VC/fundraising-focused sources to `feed_config.ex`

6. **"Blockster of the Week" special content type**: This requires a different generation pipeline since it's profile/editorial rather than news-reactive:
   - Create a periodic job (weekly) that selects a thought leader
   - Use a different prompt template focused on biographical content
   - Source from Twitter/X profiles, conference appearances, and project involvement

### Key Files
| File | Change |
|------|--------|
| `lib/blockster_v2/content_automation/settings.ex:13` | Change `target_queue_size: 10` to `20` |
| `lib/blockster_v2/content_automation/topic_engine.ex:28-32` | Add new categories |
| `lib/blockster_v2/content_automation/topic_engine.ex:228-251` | Update clustering prompt for diversity |
| `lib/blockster_v2/content_automation/content_publisher.ex:260-281` | Add category mappings |
| `lib/blockster_v2/content_automation/feed_config.ex` | Add diverse RSS feed sources |
| `lib/blockster_v2/content_automation/content_generator.ex` | Add "Blockster of the Week" prompt template |

---

## 10. Factual News Content Type System

### Problem
All AI-generated articles are opinion pieces with a pro-crypto editorial slant. This gets repetitive and limits the site's credibility. Over half the content should be straightforward factual news — reporting on events that actually happened, without the opinionated spin.

### Current State
- `TopicEngine` clusters feed items into topics and assigns categories, but has NO concept of content type (news vs opinion)
- `ContentGenerator.build_generation_prompt/4` builds a single prompt that always produces opinionated, editorial content
- The prompt explicitly says "Opinionated and direct. You believe in decentralization..." (line 189)
- `ContentGeneratedTopic` schema has no `content_type` field
- `ContentPublishQueue` schema has no `content_type` field
- No way to track or enforce a news/opinion mix ratio

### Solution Design

#### 10.1 Content Type Classification at Clustering Time

Add `content_type` to the TopicEngine clustering step. When Claude Haiku clusters feed items into topics, it also classifies each topic as either `"news"` or `"opinion"`:

**Clustering prompt addition** (`topic_engine.ex:228-251`):
```
For each topic, classify the content_type as one of:
- "news": Factual reporting on events, announcements, data, launches, regulatory actions,
  security incidents, market movements. Report WHAT happened and WHY it matters. No editorial slant.
- "opinion": Analysis, predictions, editorials, trend commentary, counter-narratives.
  Includes the author's perspective and editorial voice.
- "offer": Actionable opportunities — yield farming, DEX/CEX promotions, airdrops, token launches
  with specific terms the reader can act on right now. (See Section 14 for full details.)

DEFAULT TO "news" unless the topic clearly calls for opinion/editorial treatment or is
a specific actionable opportunity.
```

**Clustering tool schema addition** (`topic_engine.ex:266-303`):
Add to the topic object properties:
```json
"content_type": {
  "type": "string",
  "enum": ["news", "opinion"],
  "description": "news = factual reporting, opinion = editorial/analysis"
}
```

#### 10.2 Schema Changes

**Migration: Add `content_type` to `content_generated_topics`**
```elixir
alter table(:content_generated_topics) do
  add :content_type, :string, default: "news"
end
```

**Migration: Add `content_type` to `content_publish_queue`**
```elixir
alter table(:content_publish_queue) do
  add :content_type, :string, default: "news"
end
```

Update both Ecto schemas to include the new field.

#### 10.3 Separate Generation Prompts

**News prompt** (new function `build_news_prompt/4` in `content_generator.ex`):
```
ROLE: You are a professional crypto journalist for Blockster, a web3 news platform.

VOICE & STYLE:
- Neutral, factual, and professional. Report the news — don't editorialize it.
- Use clear, concise language. Lead with the most important facts.
- Attribute claims to their sources. Use direct quotes where available.
- DO NOT inject personal opinions, predictions, or crypto-optimist framing.
- DO NOT use phrases like "this is bullish", "this could be huge", "exciting development".

STRUCTURE:
- Lead with the key news (who, what, when, where, why) in the first paragraph
- Follow with supporting details, context, and background
- Include relevant data points, numbers, and quotes
- End with implications or what to watch next — NOT with an opinion

TONE: Think Reuters or Bloomberg crypto desk, not a crypto influencer blog.
```

**Opinion prompt** (rename current `build_generation_prompt/4` → `build_opinion_prompt/4`):
Keep the existing opinionated, editorial prompt as-is for opinion pieces.

**Router function** in `ContentGenerator`:
```elixir
defp build_prompt(topic, author, sources, content) do
  case topic.content_type do
    "news" -> build_news_prompt(topic, author, sources, content)
    _ -> build_opinion_prompt(topic, author, sources, content)
  end
end
```

#### 10.4 Content Mix Enforcement (>50% News)

In `TopicEngine.analyze_and_select/0`, after ranking and filtering topics, enforce a minimum 55% news ratio:

```elixir
defp enforce_content_mix(selected_topics) do
  # Count current queue composition
  {news_count, opinion_count} = FeedStore.count_queued_by_content_type()
  total_queued = news_count + opinion_count

  # Target: 55% news minimum across entire queue
  news_ratio = if total_queued > 0, do: news_count / total_queued, else: 0.0

  if news_ratio < 0.55 do
    # Prioritize news topics to restore balance
    {news_topics, opinion_topics} = Enum.split_with(selected_topics, &(&1.content_type == "news"))
    news_topics ++ opinion_topics
  else
    selected_topics
  end
end
```

**New query** in `FeedStore`:
```elixir
def count_queued_by_content_type do
  from(q in ContentPublishQueue,
    where: q.status in ["pending", "draft", "approved"],
    group_by: q.content_type,
    select: {q.content_type, count(q.id)}
  )
  |> Repo.all()
  |> Enum.reduce({0, 0}, fn
    {"news", count}, {_n, o} -> {count, o}
    {_, count}, {n, _o} -> {n, count}  # opinion or nil
  end)
end
```

#### 10.5 Queue Size Increase

Change default `target_queue_size` from 10 to 20 in `settings.ex:13`:
```elixir
@defaults %{
  target_queue_size: 20,
  # ...
}
```

#### 10.6 UI Indicators

- Show content type badge ("News" / "Opinion") on queue entries in `queue.ex` and `dashboard.ex`
- Show content type in edit page header in `edit_article.ex`
- Color coding: News = blue badge, Opinion = purple badge
- Dashboard stats: show news/opinion breakdown in pending count

### Key Files
| File | Change |
|------|--------|
| `lib/blockster_v2/content_automation/topic_engine.ex` | Add content_type to clustering prompt and tool schema |
| `lib/blockster_v2/content_automation/content_generator.ex` | Add `build_news_prompt/4`, rename existing to `build_opinion_prompt/4` |
| `lib/blockster_v2/content_automation/content_generated_topic.ex` | Add `content_type` field |
| `lib/blockster_v2/content_automation/content_publish_queue.ex` | Add `content_type` field |
| `lib/blockster_v2/content_automation/feed_store.ex` | Add `count_queued_by_content_type/0` |
| `lib/blockster_v2/content_automation/settings.ex` | Change `target_queue_size: 10` → `20` |
| `lib/blockster_v2_web/live/content_automation_live/queue.ex` | Show content type badge |
| `lib/blockster_v2_web/live/content_automation_live/edit_article.ex` | Show content type in header |
| `priv/repo/migrations/` | Two new migrations for content_type columns |

---

## 11. Scheduler EST Timezone Fix

### Problem
The scheduler UI converts admin-inputted times to UTC, which is confusing. Whatever EST time the admin selects should be the time displayed and the time the post publishes. The UI should only show EST times — no UTC anywhere.

### Current State
- The edit page (`edit_article.ex:710-733`) uses a `datetime-local` HTML input with a `phx-hook="ScheduleDatetime"` JS hook
- The JS hook (`assets/js/app.js:587-601`) converts the browser's local time to UTC via `new Date(val).toISOString()`
- The server stores `scheduled_at` as `:utc_datetime` in PostgreSQL
- On page reload, `local_datetime_value/1` formats the UTC datetime back to a string, but since the input is `datetime-local`, the browser interprets it in the user's local timezone, causing a **double conversion bug** (UTC → displayed as if it's local → converted to UTC again on save)
- The queue page (`queue.ex:307`) displays times as "at HH:MM UTC"

### Root Cause
The fundamental issue is mixing browser-local timezone handling (via JS) with server-side UTC storage. The admin is in EST but the system converts to UTC and displays UTC, creating confusion. On reload, the double conversion shifts the time again.

### Solution Design

#### 11.1 Add `tz` Dependency

Add the `tz` library for DST-aware timezone conversion (America/New_York handles EST/EDT automatically):

```elixir
# mix.exs
{:tz, "~> 0.28"}
```

#### 11.2 Create TimeHelper Module

```elixir
defmodule BlocksterV2.ContentAutomation.TimeHelper do
  @moduledoc "EST/UTC conversion for scheduler UI. Handles DST automatically."

  @timezone "America/New_York"

  @doc "Convert a naive datetime (from EST input) to UTC for storage."
  def est_to_utc(%NaiveDateTime{} = naive) do
    naive
    |> DateTime.from_naive!(@timezone)
    |> DateTime.shift_zone!("Etc/UTC")
  end

  @doc "Convert a UTC datetime to EST for display."
  def utc_to_est(%DateTime{} = utc) do
    DateTime.shift_zone!(utc, @timezone)
  end

  @doc "Format a UTC datetime as EST string for datetime-local input (YYYY-MM-DDTHH:MM)."
  def format_for_input(%DateTime{} = utc) do
    est = utc_to_est(utc)
    Calendar.strftime(est, "%Y-%m-%dT%H:%M")
  end

  @doc "Format a UTC datetime as human-readable EST string."
  def format_display(%DateTime{} = utc) do
    est = utc_to_est(utc)
    suffix = if est.zone_abbr == "EDT", do: "EDT", else: "EST"
    Calendar.strftime(est, "%b %d, %Y at %I:%M %p") <> " " <> suffix
  end
end
```

#### 11.3 Modify Edit Page (`edit_article.ex`)

**Remove JS hook**: Change the input from `phx-hook="ScheduleDatetime"` to a plain `phx-change` event:
```heex
<input type="datetime-local" name="scheduled_at"
  value={if @scheduled_at, do: TimeHelper.format_for_input(@scheduled_at)}
  phx-change="update_scheduled_at"
  class="..." />
<span class="text-xs text-gray-500">All times are Eastern (EST/EDT)</span>
```

**Update event handler** (`handle_event("update_scheduled_at", ...)`):
```elixir
def handle_event("update_scheduled_at", %{"scheduled_at" => value}, socket) do
  case NaiveDateTime.from_iso8601(value <> ":00") do
    {:ok, naive} ->
      utc_dt = TimeHelper.est_to_utc(naive)
      FeedStore.update_queue_entry_scheduled_at(socket.assigns.entry.id, utc_dt)
      {:noreply, assign(socket, scheduled_at: utc_dt)}

    _ ->
      {:noreply, socket}
  end
end
```

**Update display** (line 726): Replace UTC display with EST:
```heex
<p class="text-sm text-gray-600">
  Scheduled for: <%= TimeHelper.format_display(@scheduled_at) %>
</p>
```

#### 11.4 Modify Queue Page (`queue.ex`)

Update the scheduled time display (line 307) from UTC to EST:
```heex
<span class="text-xs text-gray-500">
  Scheduled: <%= TimeHelper.format_display(entry.scheduled_at) %>
</span>
```

#### 11.5 Remove JS Hook

Delete or comment out the `ScheduleDatetime` hook from `assets/js/app.js:587-601`. The server now handles all timezone conversion.

#### 11.6 ContentQueue Comparison

`ContentQueue.get_next_approved_entry/0` compares `scheduled_at` with `DateTime.utc_now()`. Since we store UTC in the database, this comparison remains correct — no changes needed to the publish scheduler logic.

### Key Files
| File | Change |
|------|--------|
| `mix.exs` | Add `{:tz, "~> 0.28"}` |
| `lib/blockster_v2/content_automation/time_helper.ex` | **Create** — EST/UTC conversion module |
| `lib/blockster_v2_web/live/content_automation_live/edit_article.ex` | Remove JS hook, use EST display/input |
| `lib/blockster_v2_web/live/content_automation_live/queue.ex` | Display EST times |
| `assets/js/app.js` | Remove `ScheduleDatetime` hook |

---

## 12. Comprehensive Unit Tests

### Problem
The content automation system has no automated tests. All features — existing and new — need comprehensive unit tests that can be run with `mix test`.

### Test Strategy

1. **Pure function tests first**: Test modules with no external dependencies (TipTapBuilder, QualityChecker, TimeHelper, calculate_bux)
2. **Mox for external dependencies**: Mock Claude API calls, X API calls, BUX minter
3. **Ecto sandbox for database tests**: Use `DataCase` for anything touching PostgreSQL
4. **No Mnesia in tests**: Mock or stub Mnesia calls since test config disables GenServers

### Test Files & Coverage

#### 12.1 Pure Function Tests (no mocks needed)

**`test/blockster_v2/content_automation/tiptap_builder_test.exs`**
- `build/1` converts markdown to TipTap JSON (headings, paragraphs, lists, links, images, code blocks, blockquotes)
- `count_words/1` accurately counts words in markdown and TipTap JSON
- Edge cases: empty content, nested lists, special characters, very long content

**`test/blockster_v2/content_automation/quality_checker_test.exs`**
- `check/1` passes valid articles (correct word count, has sections, proper links)
- `check/1` fails articles that are too short (<300 words) or too long (>3000 words)
- `check/1` fails articles missing required sections
- `check/1` detects excessive link density, broken markdown

**`test/blockster_v2/content_automation/time_helper_test.exs`** (new module)
- `est_to_utc/1` converts EST to UTC correctly (EST = UTC-5)
- `est_to_utc/1` handles EDT correctly (EDT = UTC-4, March–November)
- `utc_to_est/1` round-trips correctly with `est_to_utc/1`
- `format_for_input/1` produces correct `datetime-local` format
- `format_display/1` shows correct EST/EDT suffix based on date
- DST boundary tests: exact transition dates for 2026

**`test/blockster_v2/content_automation/content_publisher_test.exs`**
- `calculate_bux/1` returns correct reward and pool for various word counts
- `calculate_bux/1` respects min/max bounds (`@min_bux_reward`, `@max_bux_reward`)
- `calculate_bux/1` handles edge cases: empty content, very short, very long

#### 12.2 Database Tests (DataCase, Ecto sandbox)

**`test/blockster_v2/content_automation/feed_store_test.exs`**
- `create_feed_item/1` inserts and returns a feed item
- `get_recent_unprocessed/1` returns items within time window
- `get_queue_entries/1` filters by status correctly
- `count_queued/0` counts pending/draft/approved entries
- `count_queued_by_content_type/0` returns correct news/opinion counts (new)
- `mark_queue_entry_published/2` updates status and stores post_id
- `reject_queue_entry/1` sets status to "rejected"
- `count_published_today/0` and `count_rejected_today/0` scope to current day
- Pagination: entries ordered by inserted_at desc

**`test/blockster_v2/content_automation/feed_store_scheduling_test.exs`**
- `update_queue_entry_scheduled_at/2` persists scheduled_at
- `get_approved_ready_to_publish/0` returns entries where `scheduled_at <= now`
- `get_approved_ready_to_publish/0` excludes future-scheduled entries

**`test/blockster_v2/content_automation/settings_test.exs`**
- `get/2` returns default when no value set
- `set/2` and `get/2` round-trip correctly
- `paused?/0` returns false by default
- `target_queue_size` defaults to 20 (after the change)
- Settings persist across calls within a test

#### 12.3 Tests Requiring Mocks

**`test/blockster_v2/content_automation/topic_engine_test.exs`**
- `rank_topics/1` sorts by score descending (pure, testable)
- `filter_already_covered/1` removes topics matching published titles
- `apply_category_diversity/1` limits topics per category
- `apply_keyword_blocks/1` removes topics with blocked keywords
- `enforce_content_mix/1` prioritizes news when ratio < 55% (new)
- `build_clustering_prompt/1` includes content_type classification instructions (new)
- Integration: `analyze_and_select/0` with mocked Claude API

**`test/blockster_v2/content_automation/content_generator_test.exs`**
- `build_news_prompt/4` produces neutral, factual prompt (new)
- `build_opinion_prompt/4` produces editorial prompt
- Prompt routing: news topics get news prompt, opinion topics get opinion prompt (new)
- `generate_article/1` with mocked Claude API returns valid article data
- `enqueue_article/4` creates queue entry with correct fields
- Content type propagation: topic's content_type flows to queue entry (new)

**`test/blockster_v2/content_automation/content_publisher_test.exs`** (expanded)
- `publish_queue_entry/1` creates post, assigns tags, deposits BUX, updates cache
- `publish_queue_entry/1` handles missing category gracefully (creates it)
- `publish_queue_entry/1` with tweet_approved posts promotional tweet
- `publish_queue_entry/1` without tweet_approved skips tweet
- `resolve_category/1` maps known categories correctly
- `resolve_category/1` creates unknown categories on the fly

**`test/blockster_v2/content_automation/content_queue_test.exs`**
- `get_next_approved_entry/0` returns entry when `scheduled_at <= now`
- `get_next_approved_entry/0` returns nil when no approved entries exist
- `get_next_approved_entry/0` skips future-scheduled entries

#### 12.4 Mock Setup

Add to `test/test_helper.exs`:
```elixir
# Define Mox mocks for content automation
Mox.defmock(BlocksterV2.ContentAutomation.ClaudeClientMock, for: BlocksterV2.ContentAutomation.ClaudeClientBehaviour)
Mox.defmock(BlocksterV2.Social.XApiClientMock, for: BlocksterV2.Social.XApiClientBehaviour)
```

Create behaviour modules:
```elixir
# lib/blockster_v2/content_automation/claude_client_behaviour.ex
defmodule BlocksterV2.ContentAutomation.ClaudeClientBehaviour do
  @callback chat_completion(list(), keyword()) :: {:ok, map()} | {:error, term()}
end
```

Add to `config/test.exs`:
```elixir
config :blockster_v2, :claude_client, BlocksterV2.ContentAutomation.ClaudeClientMock
config :blockster_v2, :x_api_client, BlocksterV2.Social.XApiClientMock
```

#### 12.5 Test Data Factories

Create `test/support/content_automation_factory.ex`:
```elixir
defmodule BlocksterV2.ContentAutomation.Factory do
  alias BlocksterV2.Repo
  alias BlocksterV2.ContentAutomation.{ContentPublishQueue, ContentFeedItem, ContentGeneratedTopic}

  def build_queue_entry(attrs \\ %{}) do
    defaults = %{
      status: "pending",
      content_type: "news",
      article_data: %{
        "title" => "Test Article Title",
        "content" => "This is a test article with enough words to pass validation...",
        "excerpt" => "Test excerpt",
        "category" => "bitcoin",
        "tags" => ["bitcoin", "test"],
        "featured_image" => "https://example.com/image.jpg"
      },
      author_id: 300
    }
    struct(ContentPublishQueue, Map.merge(defaults, attrs))
  end

  def insert_queue_entry(attrs \\ %{}) do
    build_queue_entry(attrs) |> Repo.insert!()
  end
end
```

### Running Tests
```bash
# Run all content automation tests
mix test test/blockster_v2/content_automation/

# Run a specific test file
mix test test/blockster_v2/content_automation/tiptap_builder_test.exs

# Run with verbose output
mix test test/blockster_v2/content_automation/ --trace
```

### Key Files to Create
| File | Purpose |
|------|---------|
| `test/blockster_v2/content_automation/tiptap_builder_test.exs` | TipTap conversion tests |
| `test/blockster_v2/content_automation/quality_checker_test.exs` | Article quality validation tests |
| `test/blockster_v2/content_automation/time_helper_test.exs` | EST/UTC timezone tests |
| `test/blockster_v2/content_automation/content_publisher_test.exs` | Publishing pipeline + BUX calc tests |
| `test/blockster_v2/content_automation/feed_store_test.exs` | Database query tests |
| `test/blockster_v2/content_automation/feed_store_scheduling_test.exs` | Scheduling query tests |
| `test/blockster_v2/content_automation/settings_test.exs` | Settings CRUD tests |
| `test/blockster_v2/content_automation/topic_engine_test.exs` | Topic ranking/filtering tests |
| `test/blockster_v2/content_automation/content_generator_test.exs` | Generation prompt + routing tests |
| `test/blockster_v2/content_automation/content_queue_test.exs` | Scheduler logic tests |
| `test/support/content_automation_factory.ex` | Test data factory |
| `lib/blockster_v2/content_automation/claude_client_behaviour.ex` | Behaviour for mocking |
| `lib/blockster_v2/social/x_api_client_behaviour.ex` | Behaviour for mocking |

---

## 13. Playwright UI Test Setup

### Problem
Automated UI tests require authenticated access to admin pages. The site uses Thirdweb email authentication with a verification code, which can't be fully automated. This section documents how to set up Playwright-based UI testing with a semi-automated login flow.

### Approach: Chrome DevTools MCP + Manual Verification

Since Claude Code has access to Chrome DevTools MCP tools (and optionally Playwright MCP), we can use these to drive the browser directly. The login flow requires one manual step (entering the verification code), after which full automated testing can proceed.

### Setup Steps

#### 13.1 Prerequisites
```bash
# Playwright is already a devDependency
cd assets && npm install

# Install browsers (if not already)
npx playwright install chromium
```

#### 13.2 Authentication Flow

The login requires **human-in-the-loop** for the verification code:

1. **Navigate** to `http://localhost:4000` (or production URL)
2. **Click** "Sign Up / Login" button
3. **Enter email** (e.g., `lidia@blockster.com` or a test admin email)
4. **Wait for user** to provide the 6-digit verification code from their email
5. **Enter verification code** into the OTP input
6. **Wait for redirect** to the authenticated dashboard
7. **Session is now authenticated** — proceed with all UI tests

#### 13.3 Using Chrome DevTools MCP for Testing

With the Chrome DevTools MCP tools available in Claude Code, the testing flow is:

```
1. mcp__chrome-devtools__navigate_page → http://localhost:4000
2. mcp__chrome-devtools__take_snapshot → find login button
3. mcp__chrome-devtools__click → click login button
4. mcp__chrome-devtools__fill → enter email address
5. ASK USER for verification code
6. mcp__chrome-devtools__fill → enter verification code
7. mcp__chrome-devtools__wait_for → wait for authenticated page
8. Now run all test scenarios...
```

#### 13.4 Test Scenarios

Once authenticated, the following admin pages can be fully tested:

**Content Automation Dashboard** (`/admin/content`)
- [ ] Stats cards display correct counts (pending, published today, rejected today, feeds active)
- [ ] Queue size +/- controls update the target
- [ ] "Force Analyze" button triggers analysis
- [ ] "Pause Pipeline" / "Resume Pipeline" toggles correctly
- [ ] Recent queue shows articles with correct status badges
- [ ] Quick approve publishes article and updates stats
- [ ] Reject removes article and updates stats

**Content Queue** (`/admin/content/queue`)
- [ ] Articles listed with correct status (pending/draft/approved)
- [ ] Content type badges show "News" or "Opinion" (new)
- [ ] Scheduled times display in EST (new)
- [ ] Edit link navigates to edit page
- [ ] Publish Now publishes and redirects
- [ ] Reject modal opens, textarea accepts input (bug fix verification)
- [ ] Reject with reason works correctly

**Edit Article** (`/admin/content/queue/:id/edit`)
- [ ] Article content loads in TipTap editor
- [ ] Title, excerpt, category, tags are editable
- [ ] Featured image displays
- [ ] Schedule datetime picker shows EST times (new)
- [ ] Setting a scheduled time stores correct EST value (new)
- [ ] "Request AI Revision" sends revision request
- [ ] "Approve & Publish" publishes the article
- [ ] Tweet toggle and template editing works
- [ ] Editorial memory box accepts new memories
- [ ] Source articles section shows feed item links

**Feeds Management** (`/admin/content/feeds`)
- [ ] Feed list displays with status indicators
- [ ] Enable/disable toggle works
- [ ] Add new feed creates entry
- [ ] Force poll triggers immediate fetch

#### 13.5 Dev-Only Login Bypass (Optional Enhancement)

For fully automated test runs (CI/CD), add a dev-only login bypass route:

```elixir
# Only in dev/test — NEVER in production
if Mix.env() in [:dev, :test] do
  scope "/dev" do
    get "/auto-login/:user_id", DevAuthController, :auto_login
  end
end
```

This allows tests to authenticate without the email verification flow. The controller would:
1. Look up the user by ID
2. Create a session token
3. Set the session cookie
4. Redirect to the dashboard

**Security**: This route MUST be guarded by `Mix.env()` check and should NEVER exist in production builds.

#### 13.6 TipTap Editor Interaction

The TipTap editor uses a `phx-hook` with `phx-update="ignore"`, so standard form fills won't work. To interact with the editor content:

```javascript
// Via evaluate_script or browser_evaluate:
// Get editor content
() => {
  const editor = document.querySelector('[data-editor]').__tiptap_editor;
  return editor.getJSON();
}

// Set editor content
(content) => {
  const editor = document.querySelector('[data-editor]').__tiptap_editor;
  editor.commands.setContent(content);
}
```

### Key Files
| File | Purpose |
|------|---------|
| `test/e2e/README.md` | **Create** — Playwright test setup instructions |
| `test/e2e/content_automation.spec.ts` | **Create** — E2E test scenarios (optional) |
| `lib/blockster_v2_web/controllers/dev_auth_controller.ex` | **Create** — Dev-only login bypass (optional) |

---

## 14. Offers Content Type System (DeFi Offers, Exchange Promotions, Airdrops)

### Problem
DeFi yield opportunities, exchange promotions, and airdrop campaigns are a distinct content category that the current system cannot handle. These are **actionable, time-sensitive opportunities** — fundamentally different from both news reporting and opinion editorials. A reader should be able to come to Blockster and see "here's what you can do right now to earn yield / get a discount / claim an airdrop" alongside the regular news.

### Why This Needs Its Own Content Type

Regular articles say "Aave announced a governance vote" (news) or "Why Aave's governance model matters" (opinion). An **offer** says "Aave V3 just opened a WETH market at ~8% APY — here's how to use it, what the risks are, and when it ends." The difference:

| Aspect | News/Opinion | Offer |
|--------|-------------|-------|
| Purpose | Inform / persuade | Help reader take action |
| Tone | Editorial or factual reporting | Neutral explainer with risk warnings |
| Time sensitivity | General | Often expires (24h promo, limited airdrop) |
| Structure | Standard article | What → How → Risks → CTA |
| Required fields | Title, content, tags | + expiration, CTA URL, CTA text, risk disclaimer |
| Feed sources | Crypto news outlets | Protocol blogs, exchange blogs, yield trackers |

### Current Gaps

1. **No feed sources for offers**: All 28 current RSS feeds are crypto news outlets (CoinDesk, The Block, etc.). None cover protocol-specific yield opportunities, exchange listing bonuses, or airdrop campaigns.
2. **No offer classification**: TopicEngine clusters everything as news topics. It can't distinguish "Binance launches zero-fee BTC trading" (offer) from "Binance reports Q4 earnings" (news).
3. **No offer-specific prompt**: The generation prompt produces editorials. Offers need factual explainers with step-by-step instructions and risk disclaimers.
4. **No offer-specific fields**: No way to store expiration dates, CTA URLs, or risk disclaimers on articles.

### Solution Design

#### 14.1 Extend `content_type` to Include "offer"

Building on Section 10's news/opinion system, add `"offer"` as a third content type:

```
content_type: "news" | "opinion" | "offer"
```

Update the TopicEngine clustering prompt to classify offer topics:
```
Content Type Classification:
- "news": Factual reporting on events, announcements, data, launches, regulatory actions.
- "opinion": Analysis, predictions, editorials, trend commentary with editorial voice.
- "offer": Actionable opportunities — yield farming, DEX/CEX promotions, airdrops, token launches
  with specific terms. The reader can DO something with this information right now.
  DEFAULT TO "news" unless the topic is clearly editorial or a specific actionable opportunity.
```

#### 14.2 Offer Sub-Types

Add `offer_type` field to distinguish offer categories:

```elixir
# On ContentGeneratedTopic and ContentPublishQueue
field :offer_type, :string  # nil for non-offers
# Values: "yield_opportunity", "exchange_promotion", "token_launch", "airdrop", "listing"
```

Clustering tool schema addition:
```json
"offer_type": {
  "type": "string",
  "enum": ["yield_opportunity", "exchange_promotion", "token_launch", "airdrop", "listing"],
  "description": "Only set when content_type is 'offer'. Categorizes the type of opportunity."
}
```

#### 14.3 Offer-Specific Schema Fields

**Migration: Add offer fields to `content_publish_queue`**
```elixir
alter table(:content_publish_queue) do
  add :offer_type, :string       # yield_opportunity, exchange_promotion, etc.
  add :expires_at, :utc_datetime # when the offer ends (nil = ongoing)
  add :cta_url, :string          # direct link to take the action
  add :cta_text, :string         # button text: "Stake on Aave", "Trade on Binance"
end
```

**Migration: Add offer fields to `content_generated_topics`**
```elixir
alter table(:content_generated_topics) do
  add :offer_type, :string
  add :expires_at, :utc_datetime
end
```

These can be combined with the Section 10 content_type migrations into a single migration.

#### 14.4 Offer Generation Prompt

Create `build_offer_prompt/4` in `content_generator.ex`:

```
ROLE: You are a helpful DeFi/crypto researcher for Blockster. Your job is to explain
an opportunity clearly so readers can make an informed decision.

VOICE & STYLE:
- Neutral, factual, and helpful. You are NOT selling anything.
- Explain like you're talking to a friend who's crypto-literate but hasn't seen this yet.
- DO NOT use hype language ("This is huge!", "Don't miss out!", "To the moon!").
- DO NOT guarantee returns or imply risk-free profit.
- Be specific with numbers: APY, TVL, minimum deposits, fee structures.

STRUCTURE (follow this order):
1. **The Opportunity** — What is it? Who's offering it? What are the terms?
   Lead with the most important number (APY, discount %, reward amount).
2. **How It Works** — Step-by-step for someone who wants to participate.
   Be specific: which wallet, which chain, which pool/market.
3. **The Risks** — Smart contract risk, impermanent loss, regulatory risk,
   protocol track record, audit status. Be thorough and honest.
4. **Timeline** — When does it start? When does it end? Is it ongoing?
   If time-limited, make the deadline prominent.
5. **Bottom Line** — One-sentence summary of who this is good for and who should skip it.

MANDATORY:
- Include "This is not financial advice. Always do your own research." at the end.
- If the APY/reward seems unsustainably high, say so explicitly.
- Link to the actual protocol/exchange page where readers can take action.
- Mention the chain (Ethereum, Arbitrum, etc.) and any gas cost implications.

SOURCE MATERIAL:
{source_summaries}
```

#### 14.5 Offer-Specific Feed Sources

The current 28 feeds are all crypto news outlets. To surface offers, we need **protocol-specific** and **exchange-specific** feeds. Add all of the following to `feed_config.ex`:

> **Note**: RSS feed availability changes over time. Each URL must be verified before adding. Some protocols use Medium (reliable RSS), some have custom blogs (may not have RSS), and some only announce on X/Discord (not capturable via RSS). Feeds that fail verification should be flagged for manual review or API integration later.

**DeFi Protocol Feeds (Premium tier)** — these are the source of yield/staking/LP opportunities:
```elixir
# Lending & Borrowing
%{source: "Aave Governance", url: "https://governance.aave.com/latest.rss", tier: :premium},
%{source: "Aave Blog", url: "https://aave.mirror.xyz/feed/atom", tier: :premium},
%{source: "Compound Blog", url: "https://medium.com/feed/compound-finance", tier: :premium},
%{source: "MakerDAO Forum", url: "https://forum.makerdao.com/latest.rss", tier: :premium},
%{source: "Morpho Blog", url: "https://morpho.mirror.xyz/feed/atom", tier: :premium},
%{source: "Radiant Capital", url: "https://medium.com/feed/@radaborat", tier: :standard},

# DEXs & AMMs
%{source: "Uniswap Blog", url: "https://blog.uniswap.org/rss.xml", tier: :premium},
%{source: "Curve Finance News", url: "https://news.curve.fi/rss/", tier: :premium},
%{source: "Balancer Blog", url: "https://medium.com/feed/balancer-protocol", tier: :standard},
%{source: "SushiSwap Blog", url: "https://medium.com/feed/sushiswap-org", tier: :standard},
%{source: "PancakeSwap Blog", url: "https://blog.pancakeswap.finance/rss", tier: :standard},
%{source: "1inch Blog", url: "https://blog.1inch.io/feed", tier: :standard},
%{source: "Aerodrome (Base)", url: "https://medium.com/feed/@aaborat", tier: :standard},
%{source: "Velodrome (Optimism)", url: "https://medium.com/feed/@VelodromeFi", tier: :standard},
%{source: "Jupiter (Solana)", url: "https://www.jup.ag/blog/rss.xml", tier: :standard},
%{source: "Raydium Blog", url: "https://medium.com/feed/@raaborat", tier: :standard},

# Liquid Staking & Restaking
%{source: "Lido Blog", url: "https://blog.lido.fi/rss/", tier: :premium},
%{source: "Rocket Pool Blog", url: "https://medium.com/feed/rocket-pool", tier: :standard},
%{source: "EigenLayer Blog", url: "https://www.blog.eigenlayer.xyz/rss/", tier: :premium},
%{source: "Jito (Solana)", url: "https://www.jito.network/blog/rss.xml", tier: :standard},
%{source: "Marinade Finance", url: "https://medium.com/feed/marinade-finance", tier: :standard},
%{source: "Ether.fi Blog", url: "https://etherfi.mirror.xyz/feed/atom", tier: :standard},

# Yield Aggregators & Vaults
%{source: "Yearn Finance Blog", url: "https://medium.com/feed/iearn", tier: :premium},
%{source: "Convex Finance Blog", url: "https://medium.com/feed/convex-finance", tier: :standard},
%{source: "Pendle Finance Blog", url: "https://medium.com/feed/@penaborat", tier: :standard},
%{source: "Stargate Finance", url: "https://medium.com/feed/stargate-official", tier: :standard},

# Perpetuals & Derivatives
%{source: "dYdX Blog", url: "https://dydx.exchange/blog/feed", tier: :premium},
%{source: "GMX Blog", url: "https://medium.com/feed/@gmx.io", tier: :standard},
%{source: "Synthetix Blog", url: "https://blog.synthetix.io/rss/", tier: :standard},
%{source: "Hyperliquid Blog", url: "https://hyperliquid.mirror.xyz/feed/atom", tier: :standard},

# Stablecoins & RWA
%{source: "Ethena Blog", url: "https://mirror.xyz/0xF99d0E4E3435cc9C9868D1C6274DfaB3e2721341/feed/atom", tier: :premium},
%{source: "Frax Finance Blog", url: "https://medium.com/feed/frax-finance", tier: :standard},
%{source: "Ondo Finance Blog", url: "https://blog.ondo.finance/rss", tier: :standard},
%{source: "Centrifuge Blog", url: "https://medium.com/feed/centrifuge", tier: :standard},
%{source: "Maple Finance Blog", url: "https://medium.com/feed/maple-finance", tier: :standard},
```

**Centralized Exchange Feeds (Standard tier)** — source of listing announcements, promotions, fee changes:
```elixir
# Major CEXs
%{source: "Binance Blog", url: "https://www.binance.com/en/blog/rss", tier: :standard},
%{source: "Coinbase Blog", url: "https://www.coinbase.com/blog/rss", tier: :standard},
%{source: "Kraken Blog", url: "https://blog.kraken.com/feed", tier: :standard},
%{source: "OKX Blog", url: "https://www.okx.com/academy/en/rss", tier: :standard},
%{source: "Bybit Blog", url: "https://blog.bybit.com/feed", tier: :standard},
%{source: "KuCoin Blog", url: "https://www.kucoin.com/blog/rss", tier: :standard},
%{source: "Bitget Blog", url: "https://www.bitget.com/blog/feed", tier: :standard},
%{source: "Gate.io Blog", url: "https://www.gate.io/blog/feed", tier: :standard},
%{source: "MEXC Blog", url: "https://www.mexc.com/blog/feed", tier: :standard},
%{source: "HTX (Huobi) Blog", url: "https://www.htx.com/support/articles/rss", tier: :standard},
%{source: "Crypto.com Blog", url: "https://blog.crypto.com/feed", tier: :standard},
%{source: "Gemini Blog", url: "https://www.gemini.com/blog/feed", tier: :standard},
%{source: "Bitstamp Blog", url: "https://www.bitstamp.net/blog/feed/", tier: :standard},
%{source: "Bitfinex Blog", url: "https://blog.bitfinex.com/feed/", tier: :standard},
%{source: "Upbit Blog", url: "https://upbit.com/service_center/notice/rss", tier: :standard},
```

**DeFi Aggregators & Yield Trackers (Standard tier)** — surface trending opportunities:
```elixir
%{source: "DeFi Llama News", url: "https://defillama.com/rss", tier: :standard},
%{source: "DefiPrime", url: "https://defiprime.com/feed.xml", tier: :standard},
%{source: "DeFi Pulse Blog", url: "https://medium.com/feed/defi-pulse", tier: :standard},
%{source: "Zapper Blog", url: "https://blog.zapper.xyz/feed", tier: :standard},
%{source: "DeBank Blog", url: "https://medium.com/feed/@DeBank_Official", tier: :standard},
%{source: "Dune Analytics Blog", url: "https://dune.com/blog/feed", tier: :standard},
```

**L2 & Chain-Specific Feeds (Standard tier)** — ecosystem-specific opportunities:
```elixir
%{source: "Arbitrum Blog", url: "https://medium.com/feed/offchainlabs", tier: :standard},
%{source: "Optimism Blog", url: "https://optimism.mirror.xyz/feed/atom", tier: :standard},
%{source: "Base Blog", url: "https://base.mirror.xyz/feed/atom", tier: :standard},
%{source: "Polygon Blog", url: "https://blog.polygon.technology/feed", tier: :standard},
%{source: "zkSync Blog", url: "https://zksync.mirror.xyz/feed/atom", tier: :standard},
%{source: "Scroll Blog", url: "https://scroll.io/blog/feed", tier: :standard},
%{source: "Solana Foundation", url: "https://solana.com/news/feed.xml", tier: :standard},
%{source: "Avalanche Blog", url: "https://medium.com/feed/avalancheavax", tier: :standard},
%{source: "Cosmos Blog", url: "https://blog.cosmos.network/feed", tier: :standard},
%{source: "Sui Blog", url: "https://blog.sui.io/feed", tier: :standard},
%{source: "Aptos Blog", url: "https://medium.com/feed/aptoslabs", tier: :standard},
```

This brings the total from 28 feeds to **~85+ feeds**, with heavy coverage of protocols and exchanges that produce offer-type content.

#### 14.6 Categories & Badge System

**Offers use existing categories with a visual badge overlay** — no new category slugs needed. When a topic is classified as `content_type: "offer"`, the article gets assigned to the most relevant existing category (`defi`, `trading`, `token_launches`, `stablecoins`, etc.) and gets a visual "Offer" badge on top.

The `offer_type` field provides the sub-classification:
- `"yield_opportunity"` → category: `defi` + Offer badge
- `"exchange_promotion"` → category: `trading` + Offer badge
- `"token_launch"` → category: `token_launches` + Offer badge
- `"airdrop"` → category: `altcoins` or `defi` + Offer badge
- `"listing"` → category: `trading` + Offer badge

Badge rendering (Tailwind):
```heex
<%= if entry.content_type == "offer" do %>
  <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium bg-green-100 text-green-800">
    Offer
  </span>
<% end %>
```

On the published post page, offers get a green "Opportunity" banner at the top and a CTA button below the content.

#### 14.7 Content Mix with Offers

Update the mix enforcement from Section 10 to account for three types:

```
Target mix across the full queue:
  News:    >= 50%  (factual reporting)
  Opinion: <= 30%  (editorial/analysis)
  Offer:   ~15-20% (actionable opportunities)
```

In practice, offers will be naturally less frequent because not every feed item from a protocol blog is an actionable offer — many are governance updates or technical announcements that classify as "news." The mix enforcement only needs to cap opinion pieces and ensure news stays above 50%. Offers fill the remaining slots organically.

#### 14.8 UI Treatment for Offers

**Queue page** (`queue.ex`):
- Green "Offer" badge next to the regular category badge
- Show expiration: "Expires: Mar 15, 2026" or "Ongoing"
- Show offer sub-type label: "Yield", "Exchange Promo", "Airdrop", "Listing"

**Edit page** (`edit_article.ex`):
- When `content_type == "offer"`, show an additional "Offer Details" section:
  - CTA URL (text input) — link to the protocol/exchange
  - CTA Text (text input) — button label ("Stake on Aave", "Trade on Binance")
  - Expiration date (datetime picker in EST, like the scheduler)
  - Offer type (dropdown: yield, exchange promo, airdrop, listing, token launch)
- Risk disclaimer toggle — auto-appends "Not financial advice" footer

**Published post** (`show.ex`):
- "Opportunity" banner at top of article
- CTA button rendered prominently below the article content
- Expiration notice: "This offer expires on [date]" or "This offer has expired" (auto-detected)
- Risk disclaimer footer: "Not financial advice. Always do your own research."

**Dashboard** (`dashboard.ex`):
- Stats breakdown: News / Opinion / Offers counts in pending
- Expired offers flagged for admin attention

#### 14.9 Offer Expiration Handling

Add a periodic check (piggyback on ContentQueue's 10-minute cycle):

```elixir
defp check_expired_offers do
  now = DateTime.utc_now()
  expired = FeedStore.get_published_expired_offers(now)

  for entry <- expired do
    # Keep the post live but add "EXPIRED" banner (preserves SEO, no dead links)
    Blog.mark_offer_expired(entry.post_id)
    Logger.info("[ContentQueue] Marked offer expired: post #{entry.post_id}")
  end
end
```

Default behavior: keep expired offers live with an "EXPIRED" banner. This preserves SEO value and prevents dead links. Admin can manually unpublish if needed.

### Key Files
| File | Change |
|------|--------|
| `lib/blockster_v2/content_automation/topic_engine.ex` | Add "offer" to content_type enum, offer_type extraction in clustering |
| `lib/blockster_v2/content_automation/content_generator.ex` | Add `build_offer_prompt/4`, routing for offer type |
| `lib/blockster_v2/content_automation/content_generated_topic.ex` | Add `offer_type`, `expires_at` fields |
| `lib/blockster_v2/content_automation/content_publish_queue.ex` | Add `offer_type`, `expires_at`, `cta_url`, `cta_text` fields |
| `lib/blockster_v2/content_automation/feed_store.ex` | Add `get_published_expired_offers/1` query |
| `lib/blockster_v2/content_automation/content_publisher.ex` | Offer badge rendering logic |
| `lib/blockster_v2/content_automation/content_queue.ex` | Add expired offer check to publish cycle |
| `lib/blockster_v2/content_automation/feed_config.ex` | Add ~55 new feeds (DeFi protocols, exchanges, L2s, aggregators) |
| `lib/blockster_v2_web/live/content_automation_live/queue.ex` | Offer badges, expiration display, offer type labels |
| `lib/blockster_v2_web/live/content_automation_live/edit_article.ex` | Offer details section (CTA, expiry, type, risk disclaimer) |
| `lib/blockster_v2_web/live/post_live/show.ex` | CTA button, expiration notice, risk disclaimer footer |
| `lib/blockster_v2_web/live/content_automation_live/dashboard.ex` | Offer count in stats |
| `priv/repo/migrations/` | Add offer fields (combine with Section 10 migration) |

---

## 15. Summary of All Issues

| # | Issue | Type | Severity | Effort |
|---|-------|------|----------|--------|
| 1 | Preview button (draft mode) | Feature | Medium | Medium |
| 2 | Reject modal textarea disappears | Bug | High | Trivial |
| 3 | Lidia X account connection | Config | High | Trivial |
| 4 | Scheduler queue overflow (was reported as "not working") | Operational | Medium | Trivial |
| 5 | On-demand article generation page | Feature | High | Large |
| 6 | Link quality in generated articles | Bug | High | Medium |
| 7 | Editorial memory box error (intermittent, table exists) | Bug | Medium | Small |
| 8 | Writing style repetition | Enhancement | Medium | Small |
| 9 | Content diversity / topic expansion | Feature | High | Large |
| 10 | Factual news content type (>50% news mix) | Feature | **Critical** | Large |
| 11 | Scheduler EST timezone fix | Bug | High | Medium |
| 12 | Comprehensive unit tests | Testing | High | Large |
| 13 | Playwright UI test setup | Testing | Medium | Medium |
| 14 | Offers content type (DeFi, exchange, airdrops) | Feature | **Critical** | Large |

---

## Implementation Checklist

### Phase 1: Critical Fixes (Do First)

- [ ] **Fix reject modal bug** (`queue.ex:356`)
  - [ ] Remove `phx-click="close_reject"` from the outer overlay div
  - [ ] Keep only `phx-click-away="close_reject"` on the inner modal div
  - [ ] Test: click Reject, click into textarea, type reason, confirm reject works

- [ ] **Process queue backlog** (scheduler IS running, but queue is over capacity — 16 queued vs 10 target)
  - [ ] Review and approve/reject the 15 pending articles in the queue to free up slots
  - [ ] Increase `target_queue_size` to 20 (see Phase 5) so the pipeline has more room
  - [ ] Note: Mnesia settings table has 0 entries — everything uses code defaults. Changing the default in `settings.ex` is the simplest fix.
  - [ ] After clearing backlog, verify TopicEngine resumes generating new topics/articles
  - [ ] **Latent risk — GlobalSingleton rolling deploy**: During a rolling deploy, GenServers on the old node die and the new node's supervisor has already started (with `:ignore`). Mitigate by restarting after deploy (`flyctl apps restart`) or scaling to 1 machine before deploying. See Section 4 for full analysis.

- [ ] **Set up lidia@blockster.com as brand X account** (user_id = **7**)
  - [ ] Clear user 18's X lock: `Repo.get!(User, 18) |> Changeset.change(%{locked_x_user_id: nil}) |> Repo.update!()`
  - [ ] Delete user 18's Mnesia x_connection: `:mnesia.dirty_delete(:x_connections, 18)`
  - [ ] Set Fly secret: `flyctl secrets set BRAND_X_USER_ID=7 --app blockster-v2`
  - [ ] Lidia logs into blockster.com and connects @BlocksterCom via `/auth/x`
  - [ ] Verify: `Social.get_x_connection_for_user(7)` returns a valid connection

- [ ] **Fix editorial memory box error** (table exists, 2 memories saved — error is intermittent)
  - [ ] Check `edit_article.ex:243-267` handler — does it surface changeset errors to the UI?
  - [ ] Add `put_flash(:error, ...)` with human-readable validation messages on changeset failure
  - [ ] Test with edge cases: <5 chars, >500 chars, empty category
  - [ ] Verify the form doesn't reset before the error flash is visible

### Phase 2: Link Quality & Writing Style

- [ ] **Fix link quality in generated articles** (`content_generator.ex`)
  - [ ] Modify `format_source_summaries/1` to include full source URLs (add `\nURL: #{item.url}` to each item)
  - [ ] Add a separate "AVAILABLE VERIFIED URLS" section in the prompt listing all source URLs
  - [ ] Add explicit instruction: "ONLY use URLs from SOURCE MATERIAL. NEVER fabricate URLs."
  - [ ] Add instruction: "If you cannot verify a URL, state the fact without linking."
  - [ ] Remove or deprioritize the "link to primary sources" instruction that encourages URL guessing
  - [ ] Store `source_urls` in `article_data` map in `enqueue_article/4` so the edit page can display them

- [ ] **Fix links in revision prompt** (`editorial_feedback.ex`)
  - [ ] Load the queue entry's topic and its feed_items before building revision prompt
  - [ ] Pass source URLs into `build_revision_prompt/3`
  - [ ] Add source URL list to the revision prompt so Claude can reference them

- [ ] **Optional: Add post-processing link validator** (`tiptap_builder.ex`)
  - [ ] After building TipTap content, extract all link URLs
  - [ ] Flag links that are just homepages (path is `/` or empty)
  - [ ] Log warnings for suspicious URLs
  - [ ] Consider removing links that don't pass validation

- [ ] **Fix writing style repetition** (`content_generator.ex:186-264`)
  - [ ] Add "STRUCTURAL VARIETY" section to the prompt with 5-6 article structure options
  - [ ] Add explicit instruction: "DO NOT default to negative-then-positive pattern"
  - [ ] Remove or soften the "always offer solutions or silver linings" instruction
  - [ ] Add instruction to vary openings — not every article needs a counter-narrative
  - [ ] Test with 5-10 generated articles to verify variety

### Phase 3: Preview Feature & Draft Security

- [ ] **Fix unpublished post access control** (`show.ex`) — SECURITY FIX, do regardless of preview feature
  - [ ] In `handle_params/3`, after loading post, check `Post.published?/1`
  - [ ] If not published and user is not admin: raise `NotFoundError`
  - [ ] This prevents anyone from accessing draft posts via guessed slugs

- [ ] **Create draft post from queue entry** (`content_publisher.ex`)
  - [ ] Add `create_draft_post/1` function that creates post WITHOUT calling `publish_post/1`
  - [ ] Store `post_id` on the queue entry when draft is created
  - [ ] Add cleanup function to delete draft post if article is rejected

- [ ] **Add admin-only access for unpublished posts** (`show.ex`)
  - [ ] In `handle_params/3`, after loading post by slug, check `Post.published?/1`
  - [ ] If not published: check if `current_user` is admin
  - [ ] If not admin or not logged in: raise `NotFoundError`
  - [ ] If admin: show the post with a "DRAFT PREVIEW" banner at the top

- [ ] **Add Preview button to queue page** (`queue.ex`)
  - [ ] Add "Preview" button next to "Edit" and "Publish Now"
  - [ ] On click: create draft post (if not already created), open in new tab
  - [ ] Store post_id on queue entry to enable re-preview

- [ ] **Add Preview button to edit page** (`edit_article.ex`)
  - [ ] Add "Preview on Site" button in the actions bar
  - [ ] Creates draft post with current edits, opens in new tab

### Phase 4: On-Demand Article Generation

- [ ] **Create RequestArticle LiveView** (`request_article.ex`)
  - [ ] Form fields: topic, category, instructions, angle, author persona (optional)
  - [ ] On submit: call `ContentGenerator.generate_on_demand/1`
  - [ ] Use `start_async` for non-blocking generation
  - [ ] Show loading state with "Generating article..." spinner
  - [ ] On success: redirect to edit page for the new queue entry
  - [ ] On error: show error message, allow retry

- [ ] **Add `generate_on_demand/1` to ContentGenerator** (`content_generator.ex`)
  - [ ] Accept admin-provided topic details instead of feed items
  - [ ] Build a custom prompt that uses admin's instructions as source material
  - [ ] Skip queue size check (admin requests bypass limits)
  - [ ] Enqueue result with status "pending" and source "on_demand"
  - [ ] Return `{:ok, queue_entry}` for redirect

- [ ] **Add route** (`router.ex`)
  - [ ] `live "/admin/content/request", ContentAutomationLive.RequestArticle, :new`

- [ ] **Add "Request Article" button to dashboard** (`dashboard.ex`)
  - [ ] Prominent button in header area
  - [ ] Links to `/admin/content/request`

### Phase 5: Content Diversity

- [ ] **Increase default queue size to 20** (`settings.ex`)
  - [ ] Change `target_queue_size: 10` to `target_queue_size: 20` in `@defaults`
  - [ ] Note: Production Mnesia settings table has 0 entries — everything uses code defaults. Changing the default in `settings.ex` is the correct approach (no Mnesia migration needed).

- [ ] **Add new categories** (`topic_engine.ex`)
  - [ ] Add `fundraising`, `events`, `blockster_of_the_week` to `@categories`
  - [ ] Update `build_clustering_prompt/1` to describe these categories to Claude

- [ ] **Add category mappings** (`content_publisher.ex`)
  - [ ] Add `"fundraising" => {"Fundraising", "fundraising"}` to `@category_map`
  - [ ] Add `"events" => {"Events", "events"}` to `@category_map`
  - [ ] Add `"blockster_of_the_week" => {"Blockster of the Week", "blockster-of-the-week"}` to `@category_map`

- [ ] **Configure category boosts** (admin dashboard or seeds)
  - [ ] Boost: `rwa: 3`, `defi: 2`, `token_launches: 2`, `altcoins: 2`, `fundraising: 3`, `events: 2`
  - [ ] Cap: `bitcoin: max 2/day`, `ethereum: max 2/day`
  - [ ] Set via `Settings.set(:category_config, ...)`

- [ ] **Add diverse RSS feeds** (`feed_config.ex`)
  - [ ] Add RWA-focused feeds (e.g., rwa.xyz blog, Centrifuge blog)
  - [ ] Add DeFi-focused feeds (e.g., DeFi Llama blog, Aave governance)
  - [ ] Add fundraising/VC feeds (e.g., The Block research, Messari)
  - [ ] Add event calendar feeds (e.g., coinmarketcal.com, crypto events aggregators)

- [ ] **Update clustering prompt for diversity** (`topic_engine.ex`)
  - [ ] Add explicit guidance to identify fundraising rounds, VC activity, events
  - [ ] Instruct Claude to categorize trending altcoin stories with analysis of WHY
  - [ ] Add instruction to identify thought leader profiles for "Blockster of the Week"

- [ ] **Create "Blockster of the Week" generation pipeline**
  - [ ] New function in ContentGenerator for profile-style articles
  - [ ] Different prompt template: biographical, quote-heavy, achievement-focused
  - [ ] Weekly trigger (separate from the 15-min TopicEngine cycle)
  - [ ] Source: X/Twitter API for recent tweets, web search for background
  - [ ] Selection criteria: crypto thought leaders with recent notable activity

- [ ] **Add altcoin trending analysis template**
  - [ ] Custom prompt for market analysis articles
  - [ ] Include specific instructions to explain WHY tokens are up/down
  - [ ] Use CoinGecko data (already available via `token_prices` Mnesia table) for real metrics

- [ ] **Add "upcoming events" content type**
  - [ ] Monthly roundup of upcoming crypto events/conferences
  - [ ] Source from event calendar feeds
  - [ ] Custom prompt focused on event previews and what to expect

### Phase 6: Factual News Content Type (Section 10)

- [ ] **Database migrations**
  - [ ] Add `content_type` column to `content_generated_topics` (default: "news")
  - [ ] Add `content_type` column to `content_publish_queue` (default: "news")
  - [ ] Update Ecto schemas with new field

- [ ] **TopicEngine content type classification** (`topic_engine.ex`)
  - [ ] Add content_type to clustering prompt instructions
  - [ ] Add `content_type` to tool schema (enum: "news", "opinion")
  - [ ] Default unclassified topics to "news"
  - [ ] Store content_type on `ContentGeneratedTopic` records

- [ ] **Separate generation prompts** (`content_generator.ex`)
  - [ ] Create `build_news_prompt/4` — neutral, factual, Reuters-style
  - [ ] Rename `build_generation_prompt/4` → `build_opinion_prompt/4`
  - [ ] Add routing function that picks prompt based on `topic.content_type`
  - [ ] Propagate content_type from topic to queue entry in `enqueue_article/4`

- [ ] **Content mix enforcement** (`topic_engine.ex`)
  - [ ] Add `FeedStore.count_queued_by_content_type/0` query
  - [ ] Add `enforce_content_mix/1` to `analyze_and_select/0` pipeline
  - [ ] Target: 55% news minimum across entire queue
  - [ ] When below target, prioritize news topics in selection

- [ ] **Increase default queue size to 20** (`settings.ex`)
  - [ ] Change `target_queue_size: 10` → `20` in `@defaults`

- [ ] **UI content type indicators**
  - [ ] Show "News" / "Opinion" / "Offer" badge on queue entries (`queue.ex`)
  - [ ] Show content type in edit page header (`edit_article.ex`)
  - [ ] Show news/opinion/offer breakdown in dashboard stats (`dashboard.ex`)

### Phase 7: Offers Content Type (Section 14)

- [ ] **Add offer feed sources** (`feed_config.ex`)
  - [ ] Verify all DeFi protocol feed URLs (Aave, Uniswap, Compound, Lido, Curve, Yearn, etc.)
  - [ ] Verify all CEX feed URLs (Binance, Coinbase, Kraken, OKX, Bybit, KuCoin, etc.)
  - [ ] Verify yield tracker feeds (DeFi Llama, DefiPrime, etc.)
  - [ ] Verify L2/chain feeds (Arbitrum, Optimism, Base, Solana, etc.)
  - [ ] Add all verified feeds — target ~55 new feeds
  - [ ] Remove/flag any feeds that return errors or paywalled content

- [ ] **Schema migrations** (combine with Phase 6 migration)
  - [ ] Add `offer_type` to `content_generated_topics` and `content_publish_queue`
  - [ ] Add `expires_at` to both tables
  - [ ] Add `cta_url` and `cta_text` to `content_publish_queue`
  - [ ] Update Ecto schemas

- [ ] **TopicEngine offer classification** (`topic_engine.ex`)
  - [ ] Add "offer" to content_type enum in clustering prompt
  - [ ] Add `offer_type` enum to tool schema
  - [ ] Extract offer metadata (expires_at, offer sub-type) during clustering

- [ ] **Offer generation prompt** (`content_generator.ex`)
  - [ ] Create `build_offer_prompt/4` — neutral explainer with risk warnings and CTA structure
  - [ ] Route offer topics to the offer prompt
  - [ ] Propagate offer fields (offer_type, expires_at, cta_url, cta_text) to queue entry

- [ ] **Offer UI — queue & edit pages**
  - [ ] Green "Offer" badge on queue entries (`queue.ex`)
  - [ ] Offer sub-type label and expiration display on queue entries
  - [ ] "Offer Details" section on edit page (CTA URL, CTA text, expiration, offer type, risk disclaimer toggle)

- [ ] **Offer UI — published post** (`show.ex`)
  - [ ] "Opportunity" banner at top of offer articles
  - [ ] CTA button below content
  - [ ] Expiration notice (auto-detects expired offers)
  - [ ] Risk disclaimer footer

- [ ] **Offer expiration handling** (`content_queue.ex`)
  - [ ] Add `check_expired_offers/0` to 10-minute publish cycle
  - [ ] Add `FeedStore.get_published_expired_offers/1` query
  - [ ] Add `Blog.mark_offer_expired/1` — adds "EXPIRED" banner, keeps post live

### Phase 8: Scheduler EST Timezone Fix (Section 11)

- [ ] **Add `tz` dependency** (`mix.exs`)
  - [ ] Add `{:tz, "~> 0.28"}` to deps
  - [ ] Run `mix deps.get`

- [ ] **Create TimeHelper module** (`time_helper.ex`)
  - [ ] `est_to_utc/1` — convert naive datetime (EST input) to UTC
  - [ ] `utc_to_est/1` — convert UTC datetime to EST for display
  - [ ] `format_for_input/1` — format UTC as EST string for datetime-local input
  - [ ] `format_display/1` — human-readable EST string with EST/EDT suffix
  - [ ] Handle DST via America/New_York timezone

- [ ] **Update edit page** (`edit_article.ex`)
  - [ ] Remove `phx-hook="ScheduleDatetime"` from datetime input
  - [ ] Use `TimeHelper.format_for_input/1` for input value
  - [ ] Update `handle_event("update_scheduled_at")` to parse EST → UTC
  - [ ] Display scheduled time with `TimeHelper.format_display/1`
  - [ ] Add "All times are Eastern (EST/EDT)" label

- [ ] **Update queue page** (`queue.ex`)
  - [ ] Display scheduled times in EST using `TimeHelper.format_display/1`

- [ ] **Remove JS hook** (`assets/js/app.js`)
  - [ ] Delete `ScheduleDatetime` hook (lines 587-601)

### Phase 9: Comprehensive Unit Tests (Section 12)

- [ ] **Test infrastructure setup**
  - [ ] Create `test/support/content_automation_factory.ex` with test data builders
  - [ ] Create `ClaudeClientBehaviour` and `XApiClientBehaviour` modules
  - [ ] Add Mox mock definitions to `test/test_helper.exs`
  - [ ] Add mock configs to `config/test.exs`

- [ ] **Pure function tests** (no mocks needed)
  - [ ] `tiptap_builder_test.exs` — markdown→TipTap conversion, word counting
  - [ ] `quality_checker_test.exs` — article validation rules
  - [ ] `time_helper_test.exs` — EST/UTC conversion, DST boundaries
  - [ ] `content_publisher_test.exs` — `calculate_bux/1` min/max/edge cases

- [ ] **Database tests** (DataCase)
  - [ ] `feed_store_test.exs` — CRUD, queries, counting, filtering
  - [ ] `feed_store_scheduling_test.exs` — scheduled_at queries
  - [ ] `settings_test.exs` — get/set, defaults, persistence

- [ ] **Tests with mocks**
  - [ ] `topic_engine_test.exs` — ranking, filtering, diversity, content mix enforcement
  - [ ] `content_generator_test.exs` — prompt building, routing, enqueue
  - [ ] `content_queue_test.exs` — scheduler logic, next entry selection

### Phase 10: Playwright UI Test Setup (Section 13)

- [ ] **Document test setup** in `test/e2e/README.md`
  - [ ] Prerequisites (Playwright install, browser setup)
  - [ ] Auth flow with verification code
  - [ ] Chrome DevTools MCP tool usage patterns
  - [ ] TipTap editor interaction guide

- [ ] **Optional: Dev-only login bypass** (`dev_auth_controller.ex`)
  - [ ] Create controller with `Mix.env()` guard
  - [ ] Add route in dev/test scope only
  - [ ] Test that route doesn't exist in prod config

- [ ] **Test scenario checklists**
  - [ ] Dashboard tests (stats, controls, quick actions)
  - [ ] Queue page tests (listing, filtering, scheduling, reject modal)
  - [ ] Edit page tests (content editing, scheduling EST, tweet, memory)
  - [ ] Feeds management tests (CRUD, polling)

### Phase 11: Manual Testing & Verification

- [ ] Test reject modal works correctly after fix
- [ ] Test scheduler resumes generating articles after queue backlog is cleared
- [ ] Test Lidia can connect X account and tweets are posted
- [ ] Reproduce and fix the editorial memory error (try various input lengths/categories)
- [ ] Test link quality improvement with 5+ generated articles
- [ ] Test writing style variety with 10+ generated articles
- [ ] Test preview button shows draft to admin, 404 to public
- [ ] Test on-demand article generation end-to-end
- [ ] Test content diversity — verify broader topic mix
- [ ] Verify queue handles 20 articles without performance issues
- [ ] Test news vs opinion content generation — verify distinct tones
- [ ] Test content mix enforcement — verify >50% news ratio
- [ ] Test scheduler EST times — set EST time, verify display and publish time
- [ ] Run full unit test suite — `mix test test/blockster_v2/content_automation/`
- [ ] Test offer content type — verify neutral, risk-aware tone with CTA
- [ ] Test offer fields flow end-to-end (CTA URL, expiration, offer type)
- [ ] Test offer badge displays correctly on queue, edit, and published pages
- [ ] Test offer expiration handling — expired offers get "EXPIRED" banner
- [ ] Verify new feed sources are polling correctly (~55 new feeds)
- [ ] Run Playwright UI tests with Chrome DevTools MCP
