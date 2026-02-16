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

1. **Pure function tests first**: Test modules with no external dependencies (TipTapBuilder, QualityChecker, TimeHelper, AltcoinAnalyzer formatting, calculate_bux, EventRoundup formatting)
2. **ETS pre-population for cache-dependent modules**: AltcoinAnalyzer functions read from an ETS cache — bypass HTTP calls by inserting test data directly into ETS before each test
3. **Ecto sandbox for database tests**: Use `DataCase` for anything touching PostgreSQL
4. **No Mnesia in tests**: Settings and EventRoundup use Mnesia — tests for these need either a test Mnesia setup or should mock/skip the Mnesia layer and test only the logic that runs after the Mnesia read
5. **Mox for external dependencies**: Mock Claude API calls and X API calls where needed

### Test Files & Coverage

Each section below maps to one or more implemented features from this document. Every feature marked **DONE** in Section 18 must have corresponding test coverage.

---

#### 12.1 Pure Function Tests (no mocks needed, `async: true`)

##### `test/blockster_v2/content_automation/tiptap_builder_test.exs`
**Covers**: Core article rendering used by all content types (Sections 5, 6, 10, 14, 15, 16, 17)

```
describe "build/1" do
  - converts heading sections to TipTap heading nodes (level 2, level 3)
  - converts paragraph sections to TipTap paragraph nodes
  - converts bullet_list sections to TipTap bulletList nodes
  - converts ordered_list sections to TipTap orderedList nodes
  - converts blockquote sections to TipTap blockquote nodes
  - converts code_block sections to TipTap codeBlock nodes
  - handles image sections with src and alt attributes
  - handles empty section list → empty doc
  - handles non-list input → empty doc
  - handles mixed section types in order
end

describe "parse_inline_marks/1" do
  - parses **bold** text to bold marks
  - parses *italic* text to italic marks
  - parses ~~strikethrough~~ text
  - parses `code` inline to code marks
  - parses [text](url) to link marks
  - handles multiple marks in one line
  - handles nested marks (bold inside italic)
  - handles \n as hardBreak
  - returns empty list for nil input
  - returns empty list for non-string input
end

describe "count_words/1" do
  - counts words in simple paragraph doc
  - counts words across multiple nodes (paragraphs + headings)
  - returns 0 for empty doc
  - returns 0 for non-doc input
  - handles whitespace-only text nodes
  - counts words inside list items
  - excludes non-text nodes (images) from count
end
```

##### `test/blockster_v2/content_automation/time_helper_test.exs`
**Covers**: Section 11 (Scheduler EST Timezone Fix)

```
describe "est_to_utc/1" do
  - converts EST (winter) to UTC: 2:00 PM EST → 7:00 PM UTC (+5h)
  - converts EDT (summer) to UTC: 2:00 PM EDT → 6:00 PM UTC (+4h)
  - handles midnight EST → 5:00 AM UTC
  - handles midnight EDT → 4:00 AM UTC
end

describe "utc_to_est/1" do
  - converts UTC to EST (winter): 7:00 PM UTC → 2:00 PM EST
  - converts UTC to EDT (summer): 6:00 PM UTC → 2:00 PM EDT
  - round-trips correctly with est_to_utc: est_to_utc(naive) |> utc_to_est == same time in EST
end

describe "format_for_input/1" do
  - produces YYYY-MM-DDTHH:MM format for datetime-local input
  - converts from UTC to EST before formatting
  - returns nil for nil input
end

describe "format_display/1" do
  - produces human-readable format "Feb 15, 2026 at 02:30 PM EST"
  - shows EDT suffix during daylight saving time (April-October)
  - shows EST suffix outside daylight saving time (November-March)
  - returns nil for nil input
end

describe "DST boundary tests" do
  - 2026 spring forward: March 8, 2026 02:00 EST → 03:00 EDT (skips 2am)
  - 2026 fall back: November 1, 2026 02:00 EDT → 01:00 EST (repeats 1am)
  - times just before and after DST transitions convert correctly
end
```

##### `test/blockster_v2/content_automation/content_publisher_bux_test.exs`
**Covers**: Section 1 (Preview/Draft), Section 5 (On-Demand Generation — BUX calculation used during publish)

```
describe "calculate_bux/1" do
  - formula: word_count / 250 = read_minutes, reward = trunc(read_minutes * 2)
  - minimum reward is 1 BUX (@min_bux_reward)
  - maximum reward is 10 BUX (@max_bux_reward)
  - pool = max(1000, reward * 500)
  - short article (100 words): 1 min → 2 BUX reward, 1000 BUX pool
  - medium article (500 words): 2 min → 4 BUX reward, 2000 BUX pool
  - long article (1000 words): 4 min → 8 BUX reward, 4000 BUX pool
  - very long article (2500 words): 10 min → capped at 10 BUX, 5000 BUX pool
  - empty content (0 words): 1 min minimum → 2 BUX reward, 1000 BUX pool
  - returns {base_reward, pool_size} tuple
end
```

##### `test/blockster_v2/content_automation/altcoin_analyzer_test.exs`
**Covers**: Section 17 (Altcoin Trending Analysis)

ETS cache population strategy: Create the `:altcoin_analyzer_cache` ETS table in setup and insert sample coin data with a far-future expiry. This bypasses the CoinGecko HTTP call entirely.

```
# Sample data factory:
# - BTC (+8.3% 7d), ETH (+5.1%), SOL (+12.5%), AVAX (+9.8%), ADA (+6.3%)
# - DOGE (+15%), SHIB (+18%), PEPE (+22%) → meme sector triggers narrative (3 tokens, avg ~18.3%)
# - NEAR (-8.5%), RENDER (-12%) → ai/depin sectors have losers but <3 tokens
# All with full market cap, volume, and multi-period data

describe "sector_tags/0" do
  - returns map with 8 sectors
  - all values are lists of strings
  - known sectors present: ai, defi, l1, l2, gaming, rwa, meme, depin
  - gaming and rwa sectors have empty lists (no tracked tokens)
end

describe "sector_names/0" do
  - returns sorted list of 8 sector name strings
  - first is "ai", last is "rwa"
end

describe "get_movers/2" do
  setup: populate ETS cache with 10 coins

  - returns %{gainers: [...], losers: [...], period: period} map
  - gainers sorted by change descending (highest first)
  - losers sorted by change ascending (most negative first)
  - default period is :"7d"
  - respects limit parameter (limit: 3 → 3 gainers, 3 losers)
  - filters out coins without period data (nil change for requested period)
  - works with :"24h" period (uses price_change_24h field)
  - works with :"30d" period (uses price_change_30d field)
  - returns empty lists when ETS cache has no data
end

describe "detect_narratives/1" do
  setup: populate ETS cache with sector-aware data

  - detects meme sector narrative (DOGE, SHIB, PEPE all >5% → 3 tokens, avg ~18.3%)
  - does not detect ai sector (only 2 tokens: RENDER, NEAR — needs 3+)
  - does not detect defi sector (only 2 tokens: UNI, AAVE — needs 3+)
  - does not detect sectors where avg change < 5% absolute
  - returns sorted by abs(avg_change) descending
  - returns empty list when no sector has 3+ tokens moving >5%
  - handles empty ETS cache gracefully
end

describe "format_for_prompt/2" do
  - includes "MARKET DATA" header with current date
  - includes "TOP GAINERS" section header with period label
  - includes "TOP LOSERS" section header with period label
  - includes "NARRATIVE ROTATIONS" section
  - formats each token line with: rank, symbol, name, change%, price, mcap, volume
  - shows "+" sign for positive changes, no sign for negative
  - formats prices: >=1 → 2 decimals, >=0.01 → 4 decimals, <0.01 → 8 decimals
  - formats large numbers: B for billions, M for millions, K for thousands
  - handles empty gainers list → shows "(none)"
  - handles empty losers list → shows "(none)"
  - handles empty narratives → shows "No clear narrative rotations detected."
  - handles nil market_cap gracefully (omits MCap field)
  - handles nil total_volume gracefully (omits Vol field)
end

describe "get_sector_data/2" do
  setup: populate ETS cache

  - returns %{sector, tokens, avg_change, direction, count, period} map
  - returns direction "up" for positive avg_change
  - returns direction "down" for negative avg_change
  - returns correct count of matched tokens
  - tokens sorted by change descending within sector
  - returns empty data for sector with no matching tokens (gaming has empty symbol list)
  - filters out tokens without period data for requested period
end

describe "get_recent_news_for_tokens/1" do
  Note: requires DB (FeedStore.get_recent_feed_items). Test with DataCase or skip.

  - matches feed items whose titles contain mover symbol (case-insensitive)
  - matches feed items whose titles contain mover name (case-insensitive)
  - deduplicates movers from gainers + losers
  - returns max 15 matching items
  - returns fallback string when no items match
  - formats matched items as "- [source] title (url)"
end
```

##### `test/blockster_v2/content_automation/event_roundup_format_test.exs`
**Covers**: Section 16 (Upcoming Events Stories)

```
describe "format_events_for_prompt/1" do
  - groups events by type (conference, upgrade, unlock, regulatory, ecosystem)
  - includes event name, dates, location, URL, description
  - shows date range for multi-day events (start_date — end_date)
  - shows single date for one-day events
  - handles missing location gracefully (shows "Virtual / TBA")
  - handles missing URL gracefully
  - sorts events chronologically within each group
  - returns empty sections for types with no events
  - handles empty event list
end
```

---

#### 12.2 Database Tests (`DataCase`, Ecto sandbox, `async: false`)

##### `test/blockster_v2/content_automation/feed_store_test.exs`
**Covers**: Core pipeline (all features depend on FeedStore), Section 10 (content_type), Section 14 (offers)

```
describe "store_new_items/1" do
  - inserts multiple feed items and returns count
  - skips duplicates by URL (on_conflict: :nothing)
  - handles empty list
end

describe "get_recent_unprocessed/1" do
  - returns items within time window (default 12 hours)
  - excludes items outside time window
  - excludes already-processed items (topic_id != nil)
  - limits to 50 items
  - orders by fetched_at descending
end

describe "get_queue_entries/1" do
  - filters by status: "pending", "draft", "approved", "published", "rejected"
  - returns entries ordered by inserted_at descending
  - supports pagination (page, per_page)
  - filters by category
end

describe "count_queued/0" do
  - counts entries with status pending, draft, or approved
  - excludes published and rejected entries
end

describe "count_queued_by_content_type/0" do [Section 10]
  - returns {news_count, opinion_count} tuple
  - counts only pending/draft/approved entries
  - handles entries with nil content_type (counted as opinion)
  - returns {0, 0} when queue is empty
end

describe "get_published_expired_offers/1" do [Section 14]
  - returns published entries where expires_at < now and content_type == "offer"
  - excludes non-offer entries even if they have expires_at
  - excludes offers that haven't expired yet
  - excludes unpublished offers
  - returns empty list when no expired offers exist
end

describe "mark_queue_entry_published/2" do
  - sets status to "published"
  - stores post_id
  - sets reviewed_at timestamp
end

describe "reject_queue_entry/2" do
  - sets status to "rejected"
  - stores rejection reason
end

describe "enqueue_article/1" do
  - creates queue entry with correct fields
  - stores article_data JSON (title, content, excerpt, tags, category)
  - sets content_type from params [Section 10]
  - sets offer fields when content_type is "offer" [Section 14]
  - returns {:ok, entry} on success
end
```

##### `test/blockster_v2/content_automation/feed_store_scheduling_test.exs`
**Covers**: Section 11 (Scheduler EST Timezone Fix — scheduling storage)

```
describe "update_queue_entry_scheduled_at/2" do
  - persists scheduled_at datetime
  - overwrites previous scheduled_at
end

describe "get_approved_ready_to_publish" do
  Note: tested via content_queue's get_next_approved_entry

  - returns entries where status == "approved" and scheduled_at <= now
  - returns entries where status == "approved" and scheduled_at is nil
  - excludes future-scheduled entries (scheduled_at > now)
  - excludes non-approved entries
end
```

##### `test/blockster_v2/content_automation/quality_checker_test.exs`
**Covers**: Article validation used by all content types (Sections 5, 10, 14, 15, 16, 17)

```
describe "validate/1" do
  setup: build valid article map with title, excerpt, content (TipTap doc), tags

  # Word count checks (350-1200 range)
  - passes article with 500 words
  - fails article with fewer than 350 words → {:reject, [{:word_count, {:fail, ...}}]}
  - fails article with more than 1200 words
  - passes article at exact boundary (350 words)

  # Structure checks
  - fails article with missing title (nil or empty)
  - fails article with missing excerpt
  - fails article with fewer than 3 paragraphs
  - passes article with 3+ paragraphs and valid title/excerpt

  # Tag checks
  - passes article with 2-5 tags
  - fails article with fewer than 2 tags
  - fails article with more than 5 tags
  - fails article with empty tags list

  # TipTap format validation
  - passes valid TipTap doc with "type" => "doc" and "content" list
  - fails invalid TipTap (missing "type" key)
  - fails invalid TipTap (content is not a list)

  # Duplicate detection (requires DB — uses FeedStore.get_generated_topic_titles)
  - passes article with unique title
  - fails article with title too similar to recent article (>60% word overlap)

  # Multiple failures
  - returns all failures when multiple checks fail simultaneously
end
```

---

#### 12.3 Settings Tests (Mnesia-dependent)

##### `test/blockster_v2/content_automation/settings_test.exs`
**Covers**: Settings CRUD used by Sections 4, 10, 11, 14, 16, 17

Note: Settings uses Mnesia `content_automation_settings` table + ETS cache. Tests need the Mnesia table to be available (it should be if MnesiaInitializer runs in test). If Mnesia is not started in test, these tests should be skipped or use a setup that initializes the table.

```
describe "get/2 and set/2" do
  - get returns default when no value has been set
  - set then get round-trips correctly for string values
  - set then get round-trips correctly for boolean values
  - set then get round-trips correctly for integer values
  - set overwrites previous value
  - get with explicit default returns that default when no value set
end

describe "paused?/0" do
  - returns false by default
  - returns true after set(:paused, true)
  - returns false after set(:paused, false)
end

describe "defaults" do
  - target_queue_size defaults to 20
end
```

---

#### 12.4 Preview/Draft Tests
**Covers**: Section 1 (Preview Button / Draft Mode for Posts)

##### `test/blockster_v2/content_automation/content_publisher_draft_test.exs` (DataCase)

```
describe "create_draft_post/1" do
  setup: create author user (id 300), insert queue entry with article_data

  - creates a post in the database with correct title, content, excerpt, slug
  - does NOT set published_at (leaves nil — post is a draft)
  - assigns tags from article_data["tags"]
  - stores post_id on the queue entry
  - does NOT deposit BUX (no pool created)
  - does NOT update SortedPostsCache
  - returns {:ok, post} on success
end

describe "cleanup_draft_post/1" do
  - deletes unpublished post (published_at nil) and returns :ok
  - does NOT delete published post (published_at set) — returns :ok without deletion
  - handles nil post_id gracefully (returns :ok)
  - handles non-existent post_id gracefully (returns :ok)
end
```

##### `test/blockster_v2_web/live/post_live/show_draft_test.exs` (LiveCase)

```
describe "unpublished post access control" do
  setup: create admin user, create non-admin user, create unpublished post (published_at nil)

  - admin can view unpublished post at /:slug
  - non-admin redirected or shown 404 for unpublished post
  - unauthenticated user redirected or shown 404 for unpublished post
  - shows "DRAFT PREVIEW" banner when admin views unpublished post
  - does NOT show draft banner for published posts
  - published post accessible to all users (no access control)
end
```

---

#### 12.5 Content Type System Tests
**Covers**: Section 10 (Factual News Content Type)

##### `test/blockster_v2/content_automation/content_generator_prompts_test.exs` (async: true)

Note: Prompt builders are private functions called within the generation pipeline. Since they produce string prompts, the best approach is to test through the pipeline with mocked ClaudeClient, or to verify template routing by checking which prompt function gets called. Alternatively, if prompt builders become `@doc false` public, they can be tested directly.

Strategy: Test prompt content indirectly by generating articles with mocked Claude and inspecting the prompt that was passed.

```
describe "prompt routing by content_type" do
  - topic with content_type "news" routes to build_news_prompt (neutral, factual tone)
  - topic with content_type "opinion" routes to build_opinion_prompt (editorial tone)
  - topic with content_type "offer" routes to build_offer_prompt (opportunity tone) [Section 14]
  - topic with nil content_type defaults to opinion prompt
end

describe "prompt routing by template (on-demand)" do
  - template "blockster_of_week" routes to build_blockster_of_week_prompt [Section 15]
  - template "weekly_roundup" routes to build_weekly_roundup_prompt [Section 16]
  - template "event_preview" routes to build_event_preview_prompt [Section 16]
  - template "market_movers" routes to build_market_movers_prompt [Section 17]
  - template "narrative_analysis" routes to build_narrative_analysis_prompt [Section 17]
  - template nil or "custom" routes based on content_type (news/opinion/offer)
end
```

##### `test/blockster_v2/content_automation/topic_engine_logic_test.exs` (async: true for pure logic)
**Covers**: Sections 9 (Content Diversity), 10 (Content Mix), 14 (Offer classification)

Note: TopicEngine is a GenServer. These tests target the pure logic functions extracted from the pipeline. If these are private, they need to be called indirectly or made `@doc false` public for testing.

```
describe "enforce_content_mix/1" do
  Given: mock FeedStore.count_queued_by_content_type returns {news, opinion} counts

  - when news_ratio < 55%, news topics are moved to front of list
  - when news_ratio >= 55%, topics remain in original order
  - when queue is empty (0, 0), topics remain in original order
  - handles list with only news topics
  - handles list with only opinion topics
  - handles empty topic list
end

describe "apply_category_diversity/1" do
  - limits topics per category to max_per_day (default 2)
  - keeps topics from different categories
  - respects custom max_per_day from Settings category_config
end

describe "build_clustering_prompt/1" do
  - includes content_type classification instructions (news/opinion/offer)
  - includes all categories in the prompt
  - includes category "blockster_of_week" [Section 15]
  - includes category "events" [Section 16]
end
```

---

#### 12.6 Offers Content Type Tests
**Covers**: Section 14 (Offers — DeFi, Exchange Promotions, Airdrops)

##### `test/blockster_v2/content_automation/content_queue_offers_test.exs` (DataCase)

```
describe "check_expired_offers (tested via maybe_publish cycle)" do
  setup: insert published offer entries with various expires_at values

  - logs expired offers (expires_at in the past)
  - does not log offers that haven't expired yet
  - does not log non-offer entries even if they have expires_at
end
```

---

#### 12.7 Blockster of the Week Tests
**Covers**: Section 15 (Weekly Thought Leader Profile)

##### `test/blockster_v2/content_automation/x_profile_fetcher_test.exs`

Note: `fetch_profile_data/1` makes X API calls. Tests need either Mox for XApiClient or integration-level testing.

```
describe "fetch_profile_data/1" do
  With mocked X API client:

  - returns {:ok, %{prompt_text: ..., embed_tweets: ..., user: ...}} on success
  - prompt_text includes X bio, follower count, and formatted top 20 tweets
  - embed_tweets contains top 3 tweet URLs by engagement
  - tweets sorted by engagement (likes + retweets + quotes) descending
  - excludes retweets and replies (only original posts)
  - returns {:error, :no_brand_token} when brand X connection not configured
  - returns {:error, reason} when X API fails
end
```

##### `test/blockster_v2_web/live/content_automation_live/request_article_blockster_test.exs` (LiveCase)

```
describe "Blockster of the Week template" do
  setup: create admin user, log in

  - shows "Blockster of the Week" option in template dropdown
  - selecting "Blockster of the Week" shows X/Twitter Handle field
  - selecting "Blockster of the Week" shows Role/Title field
  - auto-sets category to blockster_of_week
  - auto-sets content_type to opinion
  - changes topic label to "Person's Name"
  - changes instructions label to "Research Brief"
  - hides content type/category selectors (auto-set)
  - shows "Generate Profile" submit button text
end
```

---

#### 12.8 Events System Tests
**Covers**: Section 16 (Upcoming Events Stories)

##### `test/blockster_v2/content_automation/event_roundup_test.exs`

Note: EventRoundup uses Mnesia (`upcoming_events`) and DB (ContentGeneratedTopic). Split into logic tests and integration tests.

```
describe "format_events_for_prompt/1" do (async: true, pure)
  - tested in event_roundup_format_test.exs above (Section 12.1)
end

describe "get_events_for_week/1" do (DataCase + Mnesia)
  - merges admin-curated events (Mnesia) with RSS-sourced events (DB)
  - deduplicates events with Jaro distance > 0.85
  - returns events within next 10 days
  - handles zero admin events gracefully (RSS only)
  - handles zero RSS events gracefully (admin only)
end

describe "add_event/1" do (Mnesia-dependent)
  - inserts event into upcoming_events Mnesia table
  - returns {:ok, event_id}
  - stores all fields: name, type, start_date, end_date, location, url, tier, description
end

describe "list_events/1" do
  - lists all upcoming events sorted by start_date
  - supports filtering by type
  - supports filtering by date range
end

describe "delete_event/1" do
  - deletes event from Mnesia
  - returns :ok
end
```

##### `test/blockster_v2_web/live/content_automation_live/request_article_events_test.exs` (LiveCase)

```
describe "Event Preview template" do
  setup: create admin user, log in

  - shows "Event Preview" option in template dropdown
  - selecting "Event Preview" shows Event Date(s) field
  - selecting "Event Preview" shows Location field
  - selecting "Event Preview" shows Event URL field
  - auto-sets category to events
  - auto-sets content_type to news
  - changes topic label to "Event Name"
  - shows "Generate Event Preview" submit button text
end

describe "Weekly Roundup template" do
  setup: create admin user, log in

  - shows "Weekly Roundup" option in template dropdown
  - selecting "Weekly Roundup" triggers async event data fetch
  - auto-sets category to events
  - auto-sets content_type to news
  - hides topic field (auto-generated)
  - shows "Generate Weekly Roundup" submit button text
end
```

##### `test/blockster_v2_web/live/content_automation_live/events_page_test.exs` (LiveCase)

```
describe "Events admin page /admin/content/events" do
  setup: create admin user, log in

  - renders events list page
  - shows "Add Event" button
  - displays existing events in table sorted by date
  - add event form creates event in Mnesia
  - delete button removes event
end
```

---

#### 12.9 Altcoin Trending Analysis Tests
**Covers**: Section 17 (Altcoin Trending Analysis)

##### `test/blockster_v2/content_automation/altcoin_analyzer_test.exs`
Already detailed in Section 12.1 above.

##### `test/blockster_v2/content_automation/market_content_scheduler_test.exs` (DataCase)

Note: MarketContentScheduler calls AltcoinAnalyzer (ETS cache), Settings (Mnesia), and ContentGenerator (Claude API + DB). Pre-populate ETS cache. For ContentGenerator, either mock Claude or accept this is an integration test.

```
describe "maybe_generate_weekly_movers/0" do
  setup: populate AltcoinAnalyzer ETS cache with test data

  - returns {:error, :already_generated} when Settings has today's date
  - sets Settings key :last_market_movers_date when generating
  - builds params with template: "market_movers", category: "altcoins", content_type: "news"
  - topic includes formatted date range (e.g., "February 08 — February 15, 2026")
  - instructions contain market data from format_for_prompt + news context
end

describe "maybe_generate_narrative_report/0" do
  setup: populate ETS cache with sector data

  - returns {:error, :no_strong_narratives} when no sector has >10% avg change
  - generates reports for sectors with >10% avg change
  - skips sectors already covered within 7 days (Settings check)
  - generates for sectors not covered recently (>7 days since last)
  - sets Settings key :last_narrative_{sector} for each generated sector
  - builds params with template: "narrative_analysis", category: "altcoins", content_type: "opinion"
end
```

##### `test/blockster_v2_web/live/content_automation_live/request_article_market_test.exs` (LiveCase)

```
describe "Market Analysis template" do
  setup: create admin user, log in

  - shows "Market Analysis" option in template dropdown
  - selecting "Market Analysis" triggers async market data fetch (fetching_market_data: true)
  - auto-sets category to altcoins
  - auto-sets content_type to news
  - hides topic field (auto-generated via hidden input)
  - uses 12-row textarea for market data instructions
  - shows "Generate Market Analysis" submit button text
  - hides angle field
  - hides content type/category selectors (auto-set)
end

describe "Narrative Report template" do
  setup: create admin user, log in

  - shows "Narrative Report" option in template dropdown
  - selecting "Narrative Report" shows sector dropdown
  - sector dropdown has 8 options (ai, defi, l1, l2, gaming, rwa, meme, depin)
  - auto-sets category to altcoins
  - auto-sets content_type to opinion
  - shows topic field (not hidden)
  - shows "Generate Narrative Report" submit button text
end
```

##### `test/blockster_v2_web/live/content_automation_live/dashboard_market_test.exs` (LiveCase)

```
describe "Market Analysis button" do
  setup: create admin user, log in

  - renders "Market Analysis" button on dashboard
  - button has phx-click="generate_market_analysis"
end
```

---

#### 12.10 Content Queue Scheduling Tests
**Covers**: Sections 16 (Sunday event roundup), 17 (Friday market movers, every-cycle narrative)

##### `test/blockster_v2/content_automation/content_queue_weekly_test.exs`

Note: `maybe_generate_weekly_content/0` is a private function in the ContentQueue GenServer. Test indirectly through the GenServer's 10-minute check cycle, or extract the logic into a testable public module function.

```
describe "maybe_generate_weekly_content/0" do
  - on Friday (day 5): calls MarketContentScheduler.maybe_generate_weekly_movers
  - on Friday: checks Settings :last_market_movers_date to avoid duplicate generation
  - on Sunday (day 7): calls EventRoundup.generate_weekly_roundup
  - on Sunday: checks Settings :last_weekly_roundup_date to avoid duplicate generation
  - on other days: does not call either generator
  - every cycle: calls MarketContentScheduler.maybe_generate_narrative_report (self-gated)
  - all generation calls run in Task.start (non-blocking)
end
```

---

#### 12.11 Writing Style Tests
**Covers**: Section 8 (Writing Style Issues — Negative/Positive Pattern)

```
describe "opinion prompt includes structural variety" do
  Note: verify by inspecting prompt content

  - prompt includes "STRUCTURAL VARIETY" instructions
  - prompt lists multiple article approaches (data-first, narrative, analysis, opinion, trend report)
  - prompt includes banned phrases list ("X is a feature, not a bug", "And that's the point.")
  - prompt says "DO NOT default to the here's the problem... but actually it's good structure"
end
```

---

#### 12.12 Link Quality Tests
**Covers**: Section 6 (Link Quality in AI-Generated Articles)

```
describe "source URLs in generation prompt" do
  Note: verify by inspecting prompt content passed to Claude

  - generation prompt includes "AVAILABLE SOURCE URLs" section with feed item URLs
  - prompt includes anti-fabrication instruction ("NEVER fabricate or guess URLs")
  - source URL list includes source name, URL, and topic title for each item
end

describe "source URLs in revision prompt" do
  - revision prompt includes source URLs for link corrections
end
```

---

#### 12.13 On-Demand Generation Tests
**Covers**: Section 5 (On-Demand Article Generation Page)

##### `test/blockster_v2/content_automation/content_generator_on_demand_test.exs` (DataCase)

```
describe "generate_on_demand/1" do
  With mocked ClaudeClient:

  - creates queue entry with status "pending" on success
  - bypasses queue size limits (always generates regardless of count_queued)
  - stores content_type from params on queue entry
  - stores correct category from params
  - returns {:ok, entry} with article_data containing title, content, excerpt, tags
  - returns {:error, reason} when Claude API fails
  - broadcasts PubSub event on success
end
```

##### `test/blockster_v2_web/live/content_automation_live/request_article_test.exs` (LiveCase)

```
describe "Custom Article template" do
  setup: create admin user, log in

  - renders request article page at /admin/content/request
  - shows template selector with all 6 options (Custom, Blockster, Event Preview, Weekly Roundup, Market Analysis, Narrative Report)
  - shows topic field for custom template
  - shows instructions textarea (required)
  - shows angle/perspective textarea (optional)
  - shows content type dropdown (opinion/news/offer)
  - shows category dropdown with all categories
  - shows author persona dropdown with auto-select option
  - submit with empty topic shows error
  - submit with empty instructions shows error
end
```

---

#### 12.14 Publishing Pipeline Tests
**Covers**: Section 1 (Preview/Draft), Section 14 (Offer CTA/expiry)

##### `test/blockster_v2/content_automation/content_publisher_test.exs` (DataCase)

```
describe "publish_queue_entry/1" do
  setup: create author user, insert queue entry with full article_data

  - creates post with correct title, content, slug
  - sets published_at timestamp (not nil)
  - assigns tags from article_data
  - deposits BUX to post pool
  - updates SortedPostsCache
  - sets queue entry status to "published" with post_id
  - returns {:ok, post}
end

describe "resolve_category/1" do
  - maps known category strings to blog category IDs
  - maps "blockster_of_week" to correct category [Section 15]
  - maps "events" to correct category [Section 16]
  - maps "altcoins" to correct category [Section 17]
  - creates unknown categories on the fly
  - handles race conditions (concurrent category creation)
end

describe "post_promotional_tweet/2" do
  With mocked X API client:

  - posts tweet when tweet_approved is true
  - creates share campaign for the tweet
  - skips tweet when tweet_approved is false
  - handles missing brand X token gracefully
end
```

---

#### 12.15 Mock Setup

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

#### 12.16 Test Data Factories

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
        "content" => build_valid_tiptap_content(),
        "excerpt" => "Test excerpt for the article",
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

  def build_feed_item(attrs \\ %{}) do
    defaults = %{
      title: "Test Feed Item",
      url: "https://example.com/article-#{System.unique_integer([:positive])}",
      source: "TestSource",
      summary: "Summary of the test feed item with enough context for clustering.",
      fetched_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    }
    Map.merge(defaults, attrs)
  end

  def build_valid_tiptap_content(word_count \\ 500) do
    words = 1..word_count |> Enum.map(fn _ -> "word" end) |> Enum.join(" ")
    %{
      "type" => "doc",
      "content" => [
        %{"type" => "heading", "attrs" => %{"level" => 2}, "content" => [%{"type" => "text", "text" => "Test Heading"}]},
        %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => words}]},
        %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Second paragraph."}]},
        %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Third paragraph."}]}
      ]
    }
  end

  def sample_coins do
    [
      %{id: "bitcoin", symbol: "BTC", name: "Bitcoin", current_price: 95000.0, market_cap: 1_800_000_000_000, total_volume: 45_000_000_000, price_change_24h: 2.5, price_change_7d: 8.3, price_change_30d: 15.2, last_updated: "2026-02-15T10:00:00Z"},
      %{id: "ethereum", symbol: "ETH", name: "Ethereum", current_price: 3200.0, market_cap: 380_000_000_000, total_volume: 18_000_000_000, price_change_24h: 1.8, price_change_7d: 5.1, price_change_30d: 12.0, last_updated: "2026-02-15T10:00:00Z"},
      %{id: "solana", symbol: "SOL", name: "Solana", current_price: 180.0, market_cap: 85_000_000_000, total_volume: 4_500_000_000, price_change_24h: 4.2, price_change_7d: 12.5, price_change_30d: 25.0, last_updated: "2026-02-15T10:00:00Z"},
      %{id: "avalanche-2", symbol: "AVAX", name: "Avalanche", current_price: 42.0, market_cap: 16_000_000_000, total_volume: 800_000_000, price_change_24h: 3.1, price_change_7d: 9.8, price_change_30d: 18.0, last_updated: "2026-02-15T10:00:00Z"},
      %{id: "cardano", symbol: "ADA", name: "Cardano", current_price: 0.85, market_cap: 30_000_000_000, total_volume: 1_200_000_000, price_change_24h: -1.2, price_change_7d: 6.3, price_change_30d: 10.0, last_updated: "2026-02-15T10:00:00Z"},
      %{id: "dogecoin", symbol: "DOGE", name: "Dogecoin", current_price: 0.15, market_cap: 22_000_000_000, total_volume: 2_000_000_000, price_change_24h: 5.5, price_change_7d: 15.0, price_change_30d: 30.0, last_updated: "2026-02-15T10:00:00Z"},
      %{id: "shiba-inu", symbol: "SHIB", name: "Shiba Inu", current_price: 0.000025, market_cap: 15_000_000_000, total_volume: 1_500_000_000, price_change_24h: 6.2, price_change_7d: 18.0, price_change_30d: 35.0, last_updated: "2026-02-15T10:00:00Z"},
      %{id: "pepe", symbol: "PEPE", name: "Pepe", current_price: 0.0000012, market_cap: 5_000_000_000, total_volume: 800_000_000, price_change_24h: 8.0, price_change_7d: 22.0, price_change_30d: 40.0, last_updated: "2026-02-15T10:00:00Z"},
      %{id: "near", symbol: "NEAR", name: "NEAR Protocol", current_price: 6.50, market_cap: 7_500_000_000, total_volume: 500_000_000, price_change_24h: -2.0, price_change_7d: -8.5, price_change_30d: -15.0, last_updated: "2026-02-15T10:00:00Z"},
      %{id: "render-token", symbol: "RENDER", name: "Render", current_price: 9.20, market_cap: 4_800_000_000, total_volume: 350_000_000, price_change_24h: -3.5, price_change_7d: -12.0, price_change_30d: -20.0, last_updated: "2026-02-15T10:00:00Z"}
    ]
  end

  def populate_altcoin_cache(coins \\ sample_coins()) do
    table = :altcoin_analyzer_cache
    if :ets.whereis(table) == :undefined do
      :ets.new(table, [:set, :public, :named_table, read_concurrency: true])
    end
    far_future = System.monotonic_time(:millisecond) + :timer.hours(24)
    :ets.insert(table, {:market_data, coins, far_future})
    coins
  end
end
```

### Coverage Matrix — Features vs Test Files

| Feature (Section) | Test File(s) | Type |
|---|---|---|
| #1 Preview/Draft | `content_publisher_draft_test.exs`, `show_draft_test.exs` | DataCase, LiveCase |
| #2 Reject Modal | Manual/Playwright only (UI click behavior) | N/A |
| #5 On-Demand Generation | `content_generator_on_demand_test.exs`, `request_article_test.exs` | DataCase, LiveCase |
| #6 Link Quality | `content_generator_prompts_test.exs` (source URL checks) | async: true |
| #8 Writing Style | `content_generator_prompts_test.exs` (style checks) | async: true |
| #9 Content Diversity | `topic_engine_logic_test.exs` | async: true |
| #10 Factual News | `content_generator_prompts_test.exs`, `feed_store_test.exs` | mixed |
| #11 Timezone Fix | `time_helper_test.exs`, `feed_store_scheduling_test.exs` | async: true, DataCase |
| #14 Offers | `feed_store_test.exs`, `content_queue_offers_test.exs` | DataCase |
| #15 Blockster of Week | `x_profile_fetcher_test.exs`, `request_article_blockster_test.exs` | mixed |
| #16 Events | `event_roundup_test.exs`, `event_roundup_format_test.exs`, `request_article_events_test.exs`, `events_page_test.exs` | mixed |
| #17 Altcoin Analysis | `altcoin_analyzer_test.exs`, `market_content_scheduler_test.exs`, `request_article_market_test.exs`, `dashboard_market_test.exs` | mixed |
| Core: TipTap | `tiptap_builder_test.exs` | async: true |
| Core: Quality | `quality_checker_test.exs` | DataCase |
| Core: BUX Calc | `content_publisher_bux_test.exs` | async: true |
| Core: Settings | `settings_test.exs` | Mnesia |
| Core: FeedStore | `feed_store_test.exs` | DataCase |
| Core: Publisher | `content_publisher_test.exs` | DataCase |

### Running Tests

```bash
# Run all content automation tests
mix test test/blockster_v2/content_automation/

# Run all LiveView tests for content automation
mix test test/blockster_v2_web/live/content_automation_live/
mix test test/blockster_v2_web/live/post_live/show_draft_test.exs

# Run pure function tests only (fastest)
mix test test/blockster_v2/content_automation/tiptap_builder_test.exs \
         test/blockster_v2/content_automation/time_helper_test.exs \
         test/blockster_v2/content_automation/content_publisher_bux_test.exs \
         test/blockster_v2/content_automation/altcoin_analyzer_test.exs \
         test/blockster_v2/content_automation/event_roundup_format_test.exs

# Run with verbose output
mix test test/blockster_v2/content_automation/ --trace
```

### Priority Order for Implementation

1. **Pure function tests** (no dependencies, fast, high confidence):
   - `tiptap_builder_test.exs`
   - `time_helper_test.exs`
   - `content_publisher_bux_test.exs`
   - `altcoin_analyzer_test.exs`
   - `event_roundup_format_test.exs`

2. **Database tests** (need Ecto sandbox, moderate complexity):
   - `feed_store_test.exs`
   - `feed_store_scheduling_test.exs`
   - `quality_checker_test.exs`
   - `content_publisher_draft_test.exs`
   - `content_publisher_test.exs`

3. **Logic + mock tests** (need Mox or ETS setup):
   - `market_content_scheduler_test.exs`
   - `content_generator_prompts_test.exs`
   - `content_generator_on_demand_test.exs`
   - `topic_engine_logic_test.exs`

4. **LiveView tests** (need full app context, admin user setup):
   - `request_article_test.exs`
   - `request_article_blockster_test.exs`
   - `request_article_events_test.exs`
   - `request_article_market_test.exs`
   - `dashboard_market_test.exs`
   - `events_page_test.exs`
   - `show_draft_test.exs`

### Key Files to Create
| File | Purpose | Covers |
|------|---------|--------|
| `test/blockster_v2/content_automation/tiptap_builder_test.exs` | TipTap conversion + word count | Core |
| `test/blockster_v2/content_automation/time_helper_test.exs` | EST/UTC timezone conversion | #11 |
| `test/blockster_v2/content_automation/content_publisher_bux_test.exs` | BUX reward calculation | Core |
| `test/blockster_v2/content_automation/altcoin_analyzer_test.exs` | Market data analysis + formatting | #17 |
| `test/blockster_v2/content_automation/event_roundup_format_test.exs` | Event prompt formatting | #16 |
| `test/blockster_v2/content_automation/feed_store_test.exs` | DB queries + content type + offers | Core, #10, #14 |
| `test/blockster_v2/content_automation/feed_store_scheduling_test.exs` | Scheduling queries | #11 |
| `test/blockster_v2/content_automation/quality_checker_test.exs` | Article quality validation | Core |
| `test/blockster_v2/content_automation/settings_test.exs` | Settings CRUD (Mnesia) | Core |
| `test/blockster_v2/content_automation/content_publisher_draft_test.exs` | Draft creation + cleanup | #1 |
| `test/blockster_v2/content_automation/content_publisher_test.exs` | Full publish pipeline | Core, #15 |
| `test/blockster_v2/content_automation/market_content_scheduler_test.exs` | Market scheduling gates | #17 |
| `test/blockster_v2/content_automation/content_generator_prompts_test.exs` | Prompt routing + content | #6, #8, #10, #14-17 |
| `test/blockster_v2/content_automation/content_generator_on_demand_test.exs` | On-demand generation | #5 |
| `test/blockster_v2/content_automation/topic_engine_logic_test.exs` | Topic ranking/diversity/mix | #9, #10 |
| `test/blockster_v2/content_automation/content_queue_weekly_test.exs` | Weekly content triggers | #16, #17 |
| `test/blockster_v2/content_automation/content_queue_offers_test.exs` | Expired offer checks | #14 |
| `test/blockster_v2/content_automation/x_profile_fetcher_test.exs` | X profile data fetching | #15 |
| `test/blockster_v2/content_automation/event_roundup_test.exs` | Event roundup integration | #16 |
| `test/blockster_v2_web/live/post_live/show_draft_test.exs` | Draft access control | #1 |
| `test/blockster_v2_web/live/content_automation_live/request_article_test.exs` | Base request form | #5 |
| `test/blockster_v2_web/live/content_automation_live/request_article_blockster_test.exs` | Blockster template | #15 |
| `test/blockster_v2_web/live/content_automation_live/request_article_events_test.exs` | Event templates | #16 |
| `test/blockster_v2_web/live/content_automation_live/request_article_market_test.exs` | Market templates | #17 |
| `test/blockster_v2_web/live/content_automation_live/dashboard_market_test.exs` | Market Analysis button | #17 |
| `test/blockster_v2_web/live/content_automation_live/events_page_test.exs` | Events admin page | #16 |
| `test/support/content_automation_factory.ex` | Test data factory | All |
| `lib/blockster_v2/content_automation/claude_client_behaviour.ex` | Behaviour for mocking | All |
| `lib/blockster_v2/social/x_api_client_behaviour.ex` | Behaviour for mocking | #15 |

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

## 15. Blockster of the Week — Weekly Thought Leader Profile

### Concept

A recurring weekly feature that profiles a notable figure in the crypto/web3 space. "Blockster" is anyone deeply embedded in blockchain culture — founders, developers, researchers, artists, community builders, activists. Each profile is a ~800-1200 word editorial that covers who they are, what they've built or contributed, their public positions, and why they matter right now. Published every Monday morning as a flagship content piece.

### Why This Is Different from Regular Articles

Regular articles are **reactive** — they respond to RSS feed items about events that already happened. Blockster of the Week is **proactive** — the system (or admin) selects a person and researches them, regardless of whether they're in the news that day. This means:

1. **No feed items needed** — the article is sourced from the person's X posts, public profile, blog posts, and conference appearances, not from RSS
2. **Different prompt structure** — biographical/profile rather than news or opinion
3. **Weekly cadence** — not part of the 15-minute TopicEngine cycle
4. **Admin nomination** — admins suggest who to profile
5. **Evergreen** — doesn't expire or become stale as quickly as news

### How It Works

#### 15.1 Person Selection

Admin goes to `/admin/content/request` (existing on-demand page) and uses a "Blockster of the Week" content type template:
- Enters the person's name
- Enters their X/Twitter handle (required — used to pull recent posts)
- Optionally provides specific talking points or context
- System fetches their recent X posts, then generates the profile using `generate_on_demand/1`
- Article enters the review queue like any other on-demand article

#### 15.2 Source Material — X Posts as Primary Source

The candidate's recent X/Twitter posts are the **primary source material** for the profile. The system already has full X API integration (`Social.get_x_connection_for_user/1`, brand access token via `ContentPublisher.get_brand_access_token/0`). This feature uses the brand's read access to pull the candidate's public timeline.

**X Post Retrieval Flow**:

```elixir
defmodule BlocksterV2.ContentAutomation.XProfileFetcher do
  @moduledoc "Fetch a person's recent X posts for Blockster of the Week profiles."

  @doc "Fetch recent posts from a public X/Twitter account."
  def fetch_recent_posts(x_handle) do
    # 1. Get brand access token (already available via ContentPublisher)
    {:ok, access_token} = ContentPublisher.get_brand_access_token()

    # 2. Look up user by handle
    {:ok, user} = XApiClient.get_user_by_username(access_token, x_handle)

    # 3. Fetch recent tweets (last 30 days, max 100)
    {:ok, tweets} = XApiClient.get_user_tweets(access_token, user.id, %{
      max_results: 100,
      exclude: "retweets,replies",  # Only original posts
      tweet_fields: "created_at,public_metrics,entities",
      start_time: thirty_days_ago()
    })

    # 4. Sort by engagement (likes + retweets + quotes)
    sorted = tweets
      |> Enum.map(fn tweet ->
        engagement = tweet.public_metrics.like_count +
                     tweet.public_metrics.retweet_count +
                     tweet.public_metrics.quote_count
        Map.put(tweet, :engagement_score, engagement)
      end)
      |> Enum.sort_by(& &1.engagement_score, :desc)

    # 5. Take top 20 most-engaged posts
    top_posts = Enum.take(sorted, 20)

    # 6. Format for prompt
    format_posts_for_prompt(top_posts, user)
  end

  defp format_posts_for_prompt(posts, user) do
    header = """
    X/TWITTER PROFILE: @#{user.username} (#{user.name})
    Followers: #{user.public_metrics.followers_count}
    Bio: #{user.description}
    """

    post_text = posts
      |> Enum.with_index(1)
      |> Enum.map(fn {tweet, i} ->
        "#{i}. [#{tweet.created_at}] (#{tweet.public_metrics.like_count} likes, " <>
        "#{tweet.public_metrics.retweet_count} RTs)\n" <>
        "   #{tweet.text}\n"
      end)
      |> Enum.join("\n")

    header <> "\nRECENT HIGH-ENGAGEMENT POSTS:\n" <> post_text
  end
end
```

**X API Endpoints Needed** (may need to add to `XApiClient`):
- `GET /2/users/by/username/:username` — look up user by handle
- `GET /2/users/:id/tweets` — get user's recent tweets
- These are read-only public endpoints, available with any valid bearer token

**What Gets Included in the Prompt**:
- The person's X bio and follower count
- Their top 20 most-engaged original posts from the last 30 days
- Each post includes: text, date, like count, retweet count
- Retweets and replies are excluded (we want their original voice)

This gives Claude real, verbatim quotes and positions to reference in the profile, eliminating the need to fabricate quotes or rely solely on training data.

#### 15.3 Generation Prompt

Add `build_blockster_of_week_prompt/3` to `content_generator.ex`:

```
ROLE: You are a senior editorial writer for Blockster, profiling a notable figure in crypto and web3.

SUBJECT: {person_name} — {role_description}

VOICE & STYLE:
- Respectful but not fawning. Profile the person honestly — strengths AND controversies.
- Conversational and engaging, like a well-written magazine profile.
- Let the person's work speak for itself. Use specific examples, not vague praise.
- Use their actual tweets as direct quotes (attribute with "as they posted on X" or similar).
- Their X posts reveal their personality, priorities, and positions — reference them heavily.

STRUCTURE:
1. **Opening Hook** — Start with a specific moment, decision, or quote (ideally from their
   X posts) that captures who this person is. NOT a generic "In the world of crypto..." opening.
2. **Background** — Where they came from, how they got into crypto/web3, key career milestones.
   Keep this to 2-3 paragraphs. The reader cares more about what they're doing NOW.
3. **What They've Built / Contributed** — Their most significant work. Be specific: protocol
   names, TVL numbers, user counts, governance proposals, code contributions, research papers.
4. **In Their Own Words** — Use 2-3 of their most revealing or insightful X posts as direct
   quotes. Frame each with context: what prompted it, what it reveals about their thinking.
5. **Their Position** — What do they believe about where crypto is headed? What are they
   vocal about? Draw from their X posts and public statements.
6. **Why They're a Blockster** — What makes them stand out? What can the community learn
   from their approach? This is the editorial judgment section.
7. **What's Next** — What are they working on now? What should readers watch for?

WORD TARGET: 800-1200 words.

TONE: Think profile pieces in Wired, The Verge, or a16z's "Founders" series — substantive,
specific, and human. NOT a LinkedIn endorsement or a Wikipedia summary.

MANDATORY:
- Use the person's real name and real project names. Do NOT anonymize or fictionalize.
- Quote their actual X posts verbatim when possible. Attribute clearly.
- If you don't know a specific fact, omit it rather than guessing.
- Include at least one specific achievement with a number (TVL, users, funding raised, etc.).
- End with a forward-looking statement about what they're building next.

X PROFILE & RECENT POSTS:
{x_posts_data}

ADMIN RESEARCH BRIEF:
{admin_instructions}
```

#### 15.4 Integration with On-Demand Generation

The Blockster of the Week feature piggybacks on the existing `generate_on_demand/1` flow:

**RequestArticle LiveView changes** (`request_article.ex`):
- Add a "Content Template" dropdown above the form with options: "Custom Article", "Blockster of the Week"
- When "Blockster of the Week" is selected:
  - Change the "Topic" label to "Person's Name"
  - Add a "X/Twitter Handle" field (required, prefixed with @)
  - Add a "Role/Title" field
  - Change "Instructions" label to "Research Brief (optional — X posts are the primary source)"
  - Auto-set category to a new `blockster_of_week` category
  - Auto-set content_type to `"opinion"` (profiles are editorial)
- On submit:
  1. Call `XProfileFetcher.fetch_recent_posts(x_handle)` to get X data
  2. Merge X data into the instructions field
  3. Call `generate_on_demand/1` with the `blockster_of_week` template

**ContentGenerator changes** (`content_generator.ex`):
- In `generate_on_demand/1`, check if `params.template == "blockster_of_week"`
- If so, use `build_blockster_of_week_prompt/3` instead of the standard prompt
- Add the person's name to the article tags automatically

**Category & Tags**:
- Add `"blockster_of_week"` to `@categories` in `topic_engine.ex`
- Add `"blockster_of_week" => {"Blockster of the Week", "blockster-of-the-week"}` to `@category_map` in `content_publisher.ex`
- Auto-tag with `["blockster-of-the-week", person_name_slug]`

#### 15.5 Publishing & Display

**Scheduled for Mondays**: Admin approves the profile and schedules it for Monday morning EST using the existing scheduler. No special scheduling logic needed.

**Post page treatment** (`show.ex`):
- When category is "blockster-of-the-week", show a special header banner:
  ```heex
  <div class="bg-[#CAFC00] text-black px-6 py-3 rounded-lg mb-6 flex items-center gap-3">
    <svg class="w-6 h-6"><!-- star/trophy icon --></svg>
    <span class="font-haas_medium_65 text-lg">Blockster of the Week</span>
  </div>
  ```
- Featured image should ideally be a photo of the person (admin provides via image URL)

#### 15.6 Deduplication

Add the person's name to a dedup check so the same person isn't profiled twice within 90 days:
- Store `person_name` in the queue entry's `article_data` map
- In the on-demand form, check `FeedStore.recent_blockster_profiles(days: 90)` and warn the admin if the person was recently featured
- This is a soft warning, not a hard block — admin can override

### Key Files

| File | Change |
|------|--------|
| `lib/blockster_v2/content_automation/x_profile_fetcher.ex` | **Create** — Fetch X posts for a person, format for prompt |
| `lib/blockster_v2/content_automation/content_generator.ex` | Add `build_blockster_of_week_prompt/3`, handle template routing in `generate_on_demand/1` |
| `lib/blockster_v2_web/live/content_automation_live/request_article.ex` | Add "Content Template" dropdown, Blockster of the Week form fields, X post fetch on submit |
| `lib/blockster_v2/content_automation/topic_engine.ex` | Add `blockster_of_week` to `@categories` |
| `lib/blockster_v2/content_automation/content_publisher.ex` | Add `blockster_of_week` to `@category_map` |
| `lib/blockster_v2_web/live/post_live/show.ex` | Blockster of the Week header banner for matching category |
| `lib/blockster_v2/content_automation/feed_store.ex` | Add `recent_blockster_profiles/1` for dedup check |
| `lib/blockster_v2/social/x_api_client.ex` | Add `get_user_by_username/2` and `get_user_tweets/3` if not present |

### 15.7 Implementation Notes (Feb 2026)

**Architecture decisions:**
- `XProfileFetcher` gets brand access token directly (duplicates the `Config.brand_x_user_id()` → `Social.get_x_connection_for_user()` pattern from `ContentPublisher`) rather than making `get_brand_access_token/0` public. This avoids coupling the two modules.
- `XProfileFetcher.fetch_profile_data/1` returns both `prompt_text` (formatted text for Claude) and `embed_tweets` (top 3 tweet URLs/IDs). The prompt includes top 20 tweets by engagement; the embedded tweets are the top 3. This dual purpose means one API call serves both the generation prompt and the post-generation tweet embedding.
- Template routing is done via `params[:template]` check in `build_on_demand_prompt/3`, making it trivially extensible for future templates (events, market analysis). No changes needed to the `generate_on_demand/1` public API — templates are just another key in the params map.
- Tweet embedding uses existing `TweetFinder.insert_tweets_into_content/2` which distributes tweets evenly through the article via `TweetPlacer`. No new embedding logic needed.
- The `request_article.ex` form uses a two-phase async flow: first `start_async(:fetch_x_profile)` to pull X data (can take 5-10s), then on success chains into `start_async(:generate)`. This gives the user clear feedback about what's happening.

**Files created:**
- `lib/blockster_v2/content_automation/x_profile_fetcher.ex` — 100 lines

**Files modified:**
- `lib/blockster_v2/content_automation/content_generator.ex` — Added `build_blockster_of_week_prompt/2` (~65 lines), template routing in `build_on_demand_prompt/3`, `maybe_embed_profile_tweets/2`, auto-tagging in `process_on_demand_output`
- `lib/blockster_v2_web/live/content_automation_live/request_article.ex` — Rewritten with template selector, conditional blockster fields, two-phase async submit, `handle_async(:fetch_x_profile)` handlers
- `lib/blockster_v2_web/live/post_live/show.html.heex` — Added 7-line banner block before article body
- `lib/blockster_v2/content_automation/topic_engine.ex` — Added `blockster_of_week` to `@categories`
- `lib/blockster_v2/content_automation/content_publisher.ex` — Added `blockster_of_week` mapping to `@category_map`
- `lib/blockster_v2/social/x_api_client.ex` — Added `get_user_by_username/2`

**Not implemented (deferred):**
- `recent_blockster_profiles/1` dedup check — nice-to-have, admin can manually avoid duplicates for now
- Scheduled Monday publishing — admin uses existing scheduler manually

---

## 16. Upcoming Events Stories — Weekly Crypto Event Roundups

### Concept

A recurring weekly content type that previews upcoming crypto conferences, protocol upgrades, regulatory deadlines, token unlocks, and other time-bound events for the coming week. Published as a "What's Coming This Week" roundup article, plus individual event previews for major conferences. Gives readers a reason to check Blockster every week — it becomes a calendar they rely on.

### Content Formats

Three distinct article formats under the "events" umbrella:

#### 16.1 Weekly Roundup ("What's Coming This Week in Crypto")

A comprehensive article listing upcoming events for the next 7-10 days organized by category:
- **Conferences & Summits**: ETH Denver, Consensus, Token2049, etc.
- **Protocol Upgrades**: Ethereum Pectra, Solana Firedancer, etc.
- **Token Unlocks & TGEs**: Major vesting cliff dates, token generation events
- **Regulatory Deadlines**: SEC ruling dates, legislative hearings, comment periods
- **Ecosystem Milestones**: Testnet launches, mainnet activations, airdrop snapshots

Published every Sunday evening or Monday morning EST, covering the week ahead.

#### 16.2 Event Preview ("ETH Denver 2026: What to Expect")

A standalone article for major events (Tier 1 conferences, significant protocol upgrades). Covers:
- What the event is and why it matters
- Key speakers and panels to watch
- Expected announcements or reveals
- How to attend (or follow remotely)
- Historical context (what happened at last year's event)

Published 5-7 days before the event.

#### 16.3 Protocol Upgrade Explainer ("Ethereum Pectra Upgrade: What Changes")

Technical but accessible article about upcoming protocol changes:
- What's changing and why
- Impact on users, developers, and validators
- Timeline and rollout plan
- Risks and what could go wrong
- How to prepare

Published 3-5 days before the upgrade.

### How It Works

#### 16.4 Source Material — Where Event Data Comes From

Events can't be reliably sourced from RSS feeds alone. The system uses a hybrid approach:

**Source 1: RSS Feeds (Automated)**
Several existing and new feeds publish event-related content:
- Protocol blogs announce upgrade dates
- Conference organizers post speaker lineups
- News outlets cover upcoming regulatory hearings
- The TopicEngine already clusters these — they just need to be categorized as `events`

Feed items that mention future dates, "upcoming", "scheduled for", "launching on", or conference names get classified as `events` category during clustering.

**Source 2: Admin-Curated Event List (Manual)**
A new Mnesia table `upcoming_events` where admins can manually add events:

```elixir
# Mnesia table: upcoming_events
{:upcoming_events, event_id, %{
  name: "ETH Denver 2026",
  type: "conference",           # conference | upgrade | unlock | regulatory | ecosystem
  start_date: ~D[2026-02-27],
  end_date: ~D[2026-03-01],     # nil for single-day events
  location: "Denver, Colorado",  # nil for virtual/on-chain events
  url: "https://ethdenver.com",
  description: "Annual Ethereum hackathon and conference",
  tier: "major",                 # major | notable | minor
  added_by: user_id,
  article_generated: false       # tracks if a preview article was generated
}}
```

Admins add events via a simple form on the content automation dashboard: name, type, dates, URL, tier.

**Source 3: On-Demand Generation (Admin-Triggered)**
Admin uses `/admin/content/request` with the "Event Preview" template to generate a standalone article for a specific event. The admin provides the event details and the system generates the preview article.

#### 16.5 Weekly Roundup Generation

A scheduled task triggers every Sunday (configurable):

```elixir
defmodule BlocksterV2.ContentAutomation.EventRoundup do
  @doc "Generate weekly event roundup article"
  def generate_weekly_roundup do
    today = Date.utc_today()
    week_end = Date.add(today, 10)  # Cover next 10 days for overlap

    # 1. Query upcoming_events Mnesia table for the coming week
    events = get_events_in_range(today, week_end)

    # 2. Query recent feed items tagged with "events" category
    feed_events = FeedStore.get_topics_by_category("events", days: 14)

    # 3. Combine and deduplicate
    all_events = merge_event_sources(events, feed_events)

    # 4. Build prompt with event list
    params = %{
      topic: "What's Coming This Week in Crypto — #{format_week_range(today)}",
      category: "events",
      content_type: "news",
      instructions: format_events_for_prompt(all_events),
      template: "weekly_roundup"
    }

    # 5. Generate via on-demand pipeline
    ContentGenerator.generate_on_demand(params)
  end
end
```

**Scheduling**: Piggybacks on ContentQueue's existing 10-minute check cycle. Add a weekly check:

```elixir
defp maybe_generate_weekly_roundup(state) do
  today = Date.utc_today()
  day_of_week = Date.day_of_week(today)
  # Generate on Sundays (day 7)
  if day_of_week == 7 and not already_generated_this_week?(state) do
    EventRoundup.generate_weekly_roundup()
  end
end
```

#### 16.6 Weekly Roundup Prompt

Add `build_weekly_roundup_prompt/2` to `content_generator.ex`:

```
ROLE: You are an events editor for Blockster, creating a comprehensive preview of upcoming
crypto and web3 events for the coming week.

VOICE & STYLE:
- Informative and practical. Help readers plan their week.
- For each event, explain WHY it matters, not just WHAT it is.
- Prioritize events by significance — lead with the biggest ones.
- Include actionable details: dates, locations, registration links, livestream info.
- Keep descriptions concise (2-3 sentences per event). This is a roundup, not deep dives.

STRUCTURE:
1. **Opening** — 2-3 sentence overview of what makes this week notable in crypto.
   Mention the 2-3 biggest events upfront.

2. **Conferences & Summits** — In-person and virtual events.
   For each: Name, dates, location, why it matters, registration link.

3. **Protocol Upgrades & Launches** — Network upgrades, mainnet launches, major deploys.
   For each: Protocol, what's changing, date, impact on users.

4. **Token Events** — Unlocks, TGEs, airdrop snapshots, staking changes.
   For each: Token, event type, date, approximate value/impact.

5. **Regulatory & Governance** — Hearings, ruling deadlines, governance votes.
   For each: What's being decided, who's involved, date, potential impact.

6. **Ones to Watch** — 2-3 smaller events that could be sleeper hits.

7. **Closing** — Brief editorial note on the overall theme of the week.

WORD TARGET: 800-1200 words.

MANDATORY:
- Include specific dates for every event.
- Include URLs where readers can register, watch, or learn more.
- If an event date is uncertain, say "expected" or "tentatively scheduled."
- Sort events chronologically within each section.

EVENTS LIST:
{formatted_events}
```

#### 16.7 Event Preview Prompt (for individual major events)

Add `build_event_preview_prompt/2` to `content_generator.ex`:

```
ROLE: You are covering an upcoming major crypto event for Blockster.

VOICE & STYLE:
- Anticipatory and informative. Build excitement while being substantive.
- Explain why this event matters to the broader crypto ecosystem.
- Include practical details for attendees and remote followers.

STRUCTURE:
1. **What Is [Event Name]?** — Overview, history, significance.
2. **Key Speakers & Panels** — Who's presenting, what topics are expected.
3. **What to Expect** — Anticipated announcements, themes, trends.
4. **How to Participate** — In-person: tickets, travel, venue info.
   Remote: livestreams, Twitter Spaces, Discord channels.
5. **Historical Context** — What happened at the last edition. Notable outcomes.
6. **Bottom Line** — Is this worth your time/money? Who should attend?

WORD TARGET: 600-900 words.

EVENT DETAILS:
{event_info}

ADMIN NOTES:
{admin_instructions}
```

#### 16.8 Integration with On-Demand Generation

**RequestArticle LiveView changes** (`request_article.ex`):
- Add "Event Preview" and "Weekly Roundup" to the "Content Template" dropdown
- When "Event Preview" is selected:
  - Add "Event Name" field
  - Add "Event Date(s)" field
  - Add "Event URL" field
  - Add "Location" field (optional)
  - Auto-set category to `events`
  - Auto-set content_type to `news`
- When "Weekly Roundup" is selected:
  - Auto-populate instructions from `upcoming_events` Mnesia table for the next 7-10 days
  - Auto-set category to `events`

#### 16.9 Admin Event Management UI

Add an "Events" tab to the content automation dashboard (`/admin/content/events`):

**Event List View**:
- Table of upcoming events sorted by date
- Columns: Name, Type, Date, Tier, Article Status
- "Add Event" button opens a form modal
- "Generate Preview" button on major events triggers on-demand generation

**Add Event Form**:
- Name (required)
- Type dropdown: Conference, Protocol Upgrade, Token Unlock, Regulatory, Ecosystem
- Start date (required), End date (optional)
- Location (optional)
- URL (required)
- Tier: Major / Notable / Minor
- Description (optional, short)

**Implementation**: New LiveView at `lib/blockster_v2_web/live/content_automation_live/events.ex`. The Mnesia table is lightweight — no PostgreSQL migration needed. Events are ephemeral (past events auto-archive after 30 days).

### Key Files

| File | Change |
|------|--------|
| `lib/blockster_v2/content_automation/event_roundup.ex` | **Create** — Weekly roundup generation logic, event queries |
| `lib/blockster_v2/content_automation/content_generator.ex` | Add `build_weekly_roundup_prompt/2`, `build_event_preview_prompt/2`, handle event templates in `generate_on_demand/1` |
| `lib/blockster_v2/content_automation/content_queue.ex` | Add `maybe_generate_weekly_roundup/1` to publish cycle |
| `lib/blockster_v2_web/live/content_automation_live/request_article.ex` | Add "Event Preview" and "Weekly Roundup" template options |
| `lib/blockster_v2_web/live/content_automation_live/events.ex` | **Create** — Admin event management page |
| `lib/blockster_v2_web/router.ex` | Add route `live "/admin/content/events", ContentAutomationLive.Events` |
| `lib/blockster_v2/content_automation/mnesia_tables.ex` | Add `upcoming_events` table definition |
| `lib/blockster_v2/content_automation/topic_engine.ex` | Enhance clustering prompt to identify event-related topics |

### Implementation Notes (Feb 2026)

**Status: DONE**

All items implemented. Key design decisions:

1. **Mnesia table added to MnesiaInitializer** (not a separate `mnesia_tables.ex`) — follows the established pattern where all Mnesia table definitions live in `@tables` in `mnesia_initializer.ex`. Both dev nodes need restart after deploy.

2. **Dual event sources**: `EventRoundup.get_events_for_week/1` merges admin-curated events (Mnesia `upcoming_events` table) with RSS-sourced events (PostgreSQL `ContentGeneratedTopic` where `category == "events"`). Deduplication uses Jaro string distance (>0.85 threshold). Works with zero admin events — RSS events alone are sufficient for roundups.

3. **Template routing pattern**: Added `"weekly_roundup"` and `"event_preview"` cases in `build_on_demand_prompt/3` alongside existing `"blockster_of_week"`. No changes to public API — templates are just another key in the params map.

4. **Weekly auto-generation**: `ContentQueue.maybe_generate_weekly_content/0` runs on every 10-minute check cycle. Gates on `Date.day_of_week == 7` (Sunday) and `Settings.get(:last_weekly_roundup_date)` to prevent duplicate generation. Runs the actual generation in `Task.start` so it doesn't block the publish queue.

5. **RequestArticle two-phase async for weekly_roundup**: When admin selects "Weekly Roundup" template, `start_async(:fetch_events)` fires to auto-populate the instructions textarea with formatted event data from `EventRoundup.get_events_for_week/1`. Admin can edit before generating. Event Preview template shows dedicated fields (Event Dates, Location, URL) and doesn't need async pre-population.

**Files created:**
- `lib/blockster_v2/content_automation/event_roundup.ex` — ~230 lines
- `lib/blockster_v2_web/live/content_automation_live/events.ex` — ~310 lines

**Files modified:**
- `lib/blockster_v2/mnesia_initializer.ex` — Added `upcoming_events` table (15 lines)
- `lib/blockster_v2/content_automation/content_generator.ex` — Added `build_weekly_roundup_prompt/2` (~55 lines), `build_event_preview_prompt/2` (~45 lines), two template cases in routing
- `lib/blockster_v2_web/live/content_automation_live/request_article.ex` — Extended with event templates, conditional fields, async event data fetch (~120 lines added)
- `lib/blockster_v2/content_automation/content_queue.ex` — Added `maybe_generate_weekly_content/0` (~25 lines), `EventRoundup` alias
- `lib/blockster_v2_web/router.ex` — Added events route (1 line)

**Not implemented (deferred):**
- TopicEngine clustering prompt enhancement for event detection — RSS feeds already provide some event content naturally
- Event editing (only add/delete implemented — editing an event requires delete + re-add)
- Past event auto-archival (30-day cleanup) — events persist until manually deleted

---

## 17. Altcoin Trending Analysis — Data-Driven Market Stories

**Status: DONE**

All items implemented. Key design decisions:

1. **PriceTracker NOT modified** — AltcoinAnalyzer makes its own CoinGecko API call to `/coins/markets` (richer data with 7d/30d changes) and caches in a separate ETS table (`:altcoin_analyzer_cache`, 10-minute TTL). Falls back to PriceTracker's 24h data if CoinGecko call fails. The `token_prices` Mnesia table and its 6-element tuple are completely untouched.

2. **Sector tags scoped to tracked tokens only** — `@sector_tags` in `AltcoinAnalyzer` maps 8 sectors (ai, defi, l1, l2, gaming, rwa, meme, depin) but only includes symbols that PriceTracker actually tracks. Some sectors (gaming, rwa) have empty lists because none of their characteristic tokens are in PriceTracker's 41-token set. This is intentional — the CoinGecko `/coins/markets` call returns top 100 coins anyway, so narrative detection works across the full set.

3. **Two-module architecture**: `AltcoinAnalyzer` handles data (fetch, cache, analyze, format) while `MarketContentScheduler` handles scheduling logic and content generation calls. This separation keeps concerns clean and matches the EventRoundup/ContentQueue pattern.

4. **Template routing pattern extended** — Added `"market_movers"` and `"narrative_analysis"` cases to `build_on_demand_prompt/3` alongside existing `"blockster_of_week"`, `"weekly_roundup"`, and `"event_preview"`. No changes to the public API.

5. **Weekly trigger pattern extended** — `ContentQueue.maybe_generate_weekly_content/0` now checks both Sunday (day 7, event roundup) and Friday (day 5, market movers). Narrative report runs on every 10-minute cycle but self-gates via `Settings.get(:last_narrative_#{sector})` with 7-day cooldown per sector.

6. **Two-phase async for RequestArticle** — When admin selects "Market Analysis" template, `start_async(:fetch_market_data)` fires to fetch live CoinGecko data + recent news and auto-populate the instructions textarea. "Narrative Report" template shows a sector dropdown and `start_async(:fetch_sector_data)` populates sector-specific data. Admin can edit all data before generating.

7. **Atom quoting** — Period atoms (`:7d`, `:24h`, `:30d`) must be quoted in Elixir as `:"7d"`, `:"24h"`, `:"30d"` because atoms starting with digits are invalid without quotes.

8. **Monthly leaderboard deferred** — Section 17.3 (Monthly Altcoin Leaderboard) is not implemented yet. The infrastructure supports it (30d data is fetched and cached), but no monthly trigger or prompt exists.

**Files created:**
- `lib/blockster_v2/content_automation/altcoin_analyzer.ex` — ~357 lines
- `lib/blockster_v2/content_automation/market_content_scheduler.ex` — ~142 lines

**Files modified:**
- `lib/blockster_v2/content_automation/content_generator.ex` — Added `build_market_movers_prompt/2` (~55 lines), `build_narrative_analysis_prompt/2` (~40 lines), two template cases in routing
- `lib/blockster_v2_web/live/content_automation_live/request_article.ex` — Extended with market templates, sector dropdown, async market data fetch, generate handlers (~180 lines added)
- `lib/blockster_v2/content_automation/content_queue.ex` — Extended `maybe_generate_weekly_content/0` with Friday market movers and every-cycle narrative report (~40 lines added)
- `lib/blockster_v2_web/live/content_automation_live/dashboard.ex` — Added "Market Analysis" button with async handler (~20 lines added)

**Not implemented (deferred):**
- Monthly Altcoin Leaderboard (Section 17.3) — infrastructure supports it (30d data cached), no trigger/prompt yet
- Sector tag admin editor — sectors are hardcoded in `@sector_tags`, admin can't modify via UI
- Auto-generation toggle in Settings — always enabled, can be gated by adding a Settings key check

---

### Concept

Automated articles that analyze which altcoins are trending up or down and explain WHY, using real on-chain and market data. Not just "SOL is up 15%" — but "SOL is up 15% because Firedancer testnet hit 1M TPS and institutional inflows jumped after the Grayscale filing." These are the articles traders and enthusiasts actually want: data-backed market analysis with context.

### Why This Requires Special Treatment

Regular articles are written from RSS feed summaries. Altcoin analysis requires **live market data** that doesn't come from feeds:
- Token prices, 24h/7d/30d changes, market caps, volume
- Top gainers and losers
- Which narratives are driving rotations (AI, RWA, memes, L2s)

The system already has `token_prices` Mnesia data from CoinGecko (via `PriceTracker`). This feature connects that data to the content generation pipeline.

### Content Formats

#### 17.1 Weekly Market Movers ("This Week's Biggest Altcoin Moves")

A data-first article covering the top 5 gainers and top 5 losers of the week:
- What moved, by how much, and why
- Narrative themes (AI tokens pumping, meme coins dumping, etc.)
- On-chain signals (TVL changes, whale movements, exchange flows)
- What to watch next week

Published weekly (Friday afternoon EST) as a news-type article.

#### 17.2 Narrative Rotation Report ("The AI Token Rally: Who's Winning")

A thematic analysis when a clear narrative is driving the market:
- When 3+ tokens in the same sector move together, that's a narrative
- Identify the narrative, explain why it's happening, which tokens are in it
- Compare the tokens: fundamentals, valuation, risk
- Historical context: is this narrative sustainable or a repeat of past cycles?

Published ad-hoc when the data shows a clear narrative rotation. Can be triggered automatically or by admin.

#### 17.3 Monthly Altcoin Leaderboard ("February 2026 Altcoin Scoreboard")

A comprehensive monthly review:
- Top 10 performers and bottom 10 performers by % change
- Market cap tier analysis (large cap vs mid vs small vs micro)
- Sector performance (DeFi vs Gaming vs AI vs L1s vs L2s)
- New entrants to top 100
- Exits from top 100

Published on the 1st of each month.

### How It Works

#### 17.4 Data Collection — CoinGecko via PriceTracker

The `PriceTracker` GenServer already polls CoinGecko and stores prices in the `token_prices` Mnesia table. The current data structure:

```elixir
# Mnesia table: token_prices
{:token_prices, token_id, %{
  symbol: "SOL",
  name: "Solana",
  current_price: 145.23,
  price_change_24h: 5.2,
  price_change_7d: 12.8,
  market_cap: 65_000_000_000,
  total_volume: 3_200_000_000,
  last_updated: ~U[2026-02-15 10:00:00Z]
}}
```

**What's available now**: Current price, 24h change, market cap, volume for tracked tokens.

**What needs to be added**: 7-day and 30-day price changes, sector/narrative tags, historical snapshots.

#### 17.5 Enhanced Price Data

Add a new `AltcoinAnalyzer` module that enriches the raw price data:

```elixir
defmodule BlocksterV2.ContentAutomation.AltcoinAnalyzer do
  @moduledoc """
  Analyzes CoinGecko market data to identify trending altcoins,
  narrative rotations, and market movements for content generation.
  """

  @sector_tags %{
    "ai" => ~w(FET RNDR TAO NEAR OCEAN AKT),
    "defi" => ~w(UNI AAVE MKR CRV SNX COMP SUSHI),
    "l1" => ~w(SOL AVAX ADA DOT ATOM NEAR SUI APT),
    "l2" => ~w(ARB OP MATIC MANTA STRK),
    "gaming" => ~w(IMX GALA AXS SAND MANA ILV),
    "rwa" => ~w(ONDO MKR CPOOL MAPLE),
    "meme" => ~w(DOGE SHIB PEPE BONK WIF FLOKI),
    "depin" => ~w(FIL AR RNDR HNT IOTX)
  }

  @doc "Get top N gainers and losers over a time period."
  def get_movers(period \\ :7d, limit \\ 10) do
    all_prices = PriceTracker.get_all_prices()

    sorted = all_prices
      |> Enum.filter(&has_period_data(&1, period))
      |> Enum.sort_by(&get_change(&1, period), :desc)

    gainers = Enum.take(sorted, limit)
    losers = sorted |> Enum.reverse() |> Enum.take(limit)

    %{gainers: gainers, losers: losers, period: period}
  end

  @doc "Detect narrative rotations — sectors where 3+ tokens move together."
  def detect_narratives(period \\ :7d) do
    all_prices = PriceTracker.get_all_prices()

    @sector_tags
    |> Enum.map(fn {sector, symbols} ->
      tokens = Enum.filter(all_prices, &(&1.symbol in symbols))
      avg_change = average_change(tokens, period)
      {sector, %{tokens: tokens, avg_change: avg_change, count: length(tokens)}}
    end)
    |> Enum.filter(fn {_sector, data} ->
      # Narrative = 3+ tokens moving in same direction by >5%
      data.count >= 3 and abs(data.avg_change) > 5.0
    end)
    |> Enum.sort_by(fn {_sector, data} -> abs(data.avg_change) end, :desc)
  end

  @doc "Format market data as structured text for Claude prompt."
  def format_for_prompt(movers, narratives) do
    """
    MARKET DATA (from CoinGecko, #{DateTime.utc_now() |> Calendar.strftime("%B %d, %Y")}):

    TOP GAINERS (7-day):
    #{format_token_list(movers.gainers)}

    TOP LOSERS (7-day):
    #{format_token_list(movers.losers)}

    NARRATIVE ROTATIONS:
    #{format_narratives(narratives)}
    """
  end

  defp format_token_list(tokens) do
    tokens
    |> Enum.with_index(1)
    |> Enum.map(fn {t, i} ->
      "#{i}. #{t.symbol} (#{t.name}): #{sign(t.change_7d)}#{t.change_7d}% | " <>
      "Price: $#{t.current_price} | MCap: $#{format_mcap(t.market_cap)} | " <>
      "Vol: $#{format_mcap(t.total_volume)}"
    end)
    |> Enum.join("\n")
  end

  defp format_narratives(narratives) do
    narratives
    |> Enum.map(fn {sector, data} ->
      tokens = data.tokens |> Enum.map(& &1.symbol) |> Enum.join(", ")
      "#{String.upcase(sector)}: avg #{sign(data.avg_change)}#{data.avg_change}% " <>
      "(#{tokens})"
    end)
    |> Enum.join("\n")
  end
end
```

#### 17.6 Generation Prompts

**Weekly Market Movers Prompt** (`build_market_movers_prompt/2`):

```
ROLE: You are a crypto market analyst for Blockster. Your job is to explain this week's
biggest altcoin price movements with context and analysis.

VOICE & STYLE:
- Data-first. Lead with numbers, then explain the story behind them.
- Analytical but accessible. A crypto-literate reader should understand everything.
- Balanced — don't cheerleader for gainers or doom-and-gloom losers.
- Be specific: name protocols, cite TVL numbers, reference on-chain data.
- DO NOT use "to the moon", "rekt", or other meme language unless quoting someone.

STRUCTURE:
1. **Market Overview** — 2-3 sentences on the overall altcoin market this week.
   Total altcoin market cap direction, BTC dominance trend, ETH/BTC ratio.

2. **Top Gainers** — For each of the top 5 gainers:
   - What moved: token name, symbol, % change, current price
   - Why it moved: catalyst (news, upgrade, partnership, narrative)
   - Sustainability: is this a one-off or the start of a trend?

3. **Top Losers** — For each of the top 5 losers:
   - What moved: token name, symbol, % change, current price
   - Why it dropped: catalyst or lack thereof
   - Outlook: oversold bounce candidate or continued decline?

4. **Narrative Watch** — Which sectors/narratives are rotating in or out?
   Use the narrative rotation data to identify themes.

5. **What to Watch Next Week** — 2-3 catalysts coming up that could move altcoins.
   Tie to the events calendar where possible.

WORD TARGET: 800-1200 words.

MANDATORY:
- Use the EXACT price data provided below. Do NOT make up prices or percentages.
- If you don't know WHY a token moved, say "the catalyst is unclear" rather than guessing.
- Include at least one on-chain observation (TVL change, whale movement, exchange flow).
- Mention Bitcoin's price as context (altcoins move relative to BTC).

{market_data}

RELEVANT NEWS CONTEXT (from recent feed items):
{recent_news_context}
```

**Narrative Rotation Prompt** (`build_narrative_analysis_prompt/2`):

```
ROLE: You are analyzing a sector rotation in the crypto market for Blockster.

The {sector_name} sector is moving: {direction} with an average {period} change of {avg_change}%.

STRUCTURE:
1. **The Rotation** — What's happening across the sector. Which tokens, how much, since when.
2. **The Catalyst** — What triggered this rotation? Be specific.
3. **Token Comparison** — Compare the top 3-4 tokens in this sector:
   - Fundamentals (revenue, TVL, users, technology)
   - Valuation (FDV, circulating supply, P/S ratio if applicable)
   - Risk profile (token unlock schedule, team concentration, smart contract risk)
4. **Historical Context** — Has this sector rallied before? What happened after?
5. **The Trade** — NOT financial advice, but analytical framework for thinking about it.

WORD TARGET: 600-900 words.

{market_data}
{recent_news_context}
```

#### 17.7 Automated Trigger Logic

Add to `ContentQueue` or a new `MarketContentScheduler`:

```elixir
defmodule BlocksterV2.ContentAutomation.MarketContentScheduler do
  @doc "Check if a weekly market movers article should be generated."
  def maybe_generate_weekly_movers do
    today = Date.utc_today()
    day_of_week = Date.day_of_week(today)

    # Generate on Fridays (day 5)
    if day_of_week == 5 and not already_generated_this_week?("market_movers") do
      movers = AltcoinAnalyzer.get_movers(:7d, 10)
      narratives = AltcoinAnalyzer.detect_narratives(:7d)
      market_data = AltcoinAnalyzer.format_for_prompt(movers, narratives)

      # Get recent news context from feed items for each top mover
      news_context = get_recent_news_for_tokens(movers)

      params = %{
        topic: "This Week's Biggest Altcoin Moves — #{format_date_range()}",
        category: "altcoins",
        content_type: "news",
        instructions: market_data <> "\n\n" <> news_context,
        template: "market_movers"
      }

      ContentGenerator.generate_on_demand(params)
    end
  end

  @doc "Check if a narrative rotation article should be generated."
  def maybe_generate_narrative_report do
    narratives = AltcoinAnalyzer.detect_narratives(:7d)

    # Only generate if there's a strong narrative (>10% average sector move)
    strong_narratives = Enum.filter(narratives, fn {_, data} ->
      abs(data.avg_change) > 10.0
    end)

    for {sector, data} <- strong_narratives,
        not already_covered_narrative?(sector, days: 7) do
      market_data = AltcoinAnalyzer.format_for_prompt(
        %{gainers: data.tokens, losers: [], period: :7d},
        [{sector, data}]
      )

      params = %{
        topic: "The #{String.capitalize(sector)} Rally: What's Driving It",
        category: "altcoins",
        content_type: "opinion",
        instructions: market_data,
        template: "narrative_analysis"
      }

      ContentGenerator.generate_on_demand(params)
    end
  end
end
```

#### 17.8 Integration with Existing Pipeline

The altcoin analysis feature connects to the existing system at several points:

**PriceTracker** (already exists): Provides raw CoinGecko data. May need enhancement:
- Add 7d and 30d change fields to the `token_prices` table
- Increase the number of tracked tokens (currently may be limited to tokens used in BuxBoosterGame)
- Add a `get_all_prices/0` function if not already present

**TopicEngine** (existing): When clustering feed items, the engine already categorizes topics as `altcoins`. The market analysis articles supplement this with data-driven content that may not appear in feeds.

**On-Demand Generation** (existing): All three formats use `generate_on_demand/1` with custom templates and instructions. No changes needed to the core generation pipeline.

**ContentQueue** (existing): Add `MarketContentScheduler.maybe_generate_weekly_movers/0` and `maybe_generate_narrative_report/0` to the 10-minute check cycle, guarded by day-of-week and dedup checks.

#### 17.9 Admin Controls

**Dashboard additions**:
- "Generate Market Analysis" button that manually triggers the weekly movers article
- Toggle for auto-generation (on/off via Settings)
- Sector tag editor — admin can update which tokens belong to which sectors

**RequestArticle additions**:
- Add "Market Analysis" and "Narrative Report" to the "Content Template" dropdown
- When selected, auto-populate with current market data from `AltcoinAnalyzer`
- Admin can edit/supplement the data before generating

### Key Files

| File | Change | Status |
|------|--------|--------|
| `lib/blockster_v2/content_automation/altcoin_analyzer.ex` | **Created** — Market data analysis, mover detection, narrative detection, prompt formatting, ETS cache | **DONE** |
| `lib/blockster_v2/content_automation/market_content_scheduler.ex` | **Created** — Weekly/ad-hoc scheduling for market analysis articles | **DONE** |
| `lib/blockster_v2/content_automation/content_generator.ex` | Added `build_market_movers_prompt/2`, `build_narrative_analysis_prompt/2`, `"market_movers"` and `"narrative_analysis"` template routing | **DONE** |
| `lib/blockster_v2/content_automation/content_queue.ex` | Extended `maybe_generate_weekly_content/0` with Friday market movers + every-cycle narrative report | **DONE** |
| `lib/blockster_v2_web/live/content_automation_live/request_article.ex` | Added "Market Analysis" and "Narrative Report" templates with async auto-population and sector dropdown | **DONE** |
| `lib/blockster_v2_web/live/content_automation_live/dashboard.ex` | Added "Market Analysis" button with `start_async(:generate_market)` | **DONE** |
| `lib/blockster_v2/price_tracker.ex` | **NOT modified** — AltcoinAnalyzer uses its own CoinGecko call instead | N/A |

---

## 18. Summary of All Issues

| # | Issue | Type | Severity | Effort | Status |
|---|-------|------|----------|--------|--------|
| 1 | Preview button (draft mode) | Feature | Medium | Medium | **DONE** |
| 2 | Reject modal textarea disappears | Bug | High | Trivial | **DONE** |
| 3 | Lidia X account connection | Config | High | Trivial | Manual steps needed |
| 4 | Scheduler queue overflow (was reported as "not working") | Operational | Medium | Trivial | Resolved (queue size → 20) |
| 5 | On-demand article generation page | Feature | High | Large | **DONE** |
| 6 | Link quality in generated articles | Bug | High | Medium | **DONE** |
| 7 | Editorial memory box error (intermittent, table exists) | Bug | Medium | Small | Needs repro |
| 8 | Writing style repetition | Enhancement | Medium | Small | **DONE** |
| 9 | Content diversity / topic expansion | Feature | High | Large | **DONE** |
| 10 | Factual news content type (>50% news mix) | Feature | **Critical** | Large | **DONE** |
| 11 | Scheduler EST timezone fix | Bug | High | Medium | **DONE** |
| 12 | Comprehensive unit tests | Testing | High | Large | Not started |
| 13 | Playwright UI test setup | Testing | Medium | Medium | Not started |
| 14 | Offers content type (DeFi, exchange, airdrops) | Feature | **Critical** | Large | **DONE** |
| 15 | Blockster of the Week (thought leader profiles) | Feature | High | Large | **DONE** |
| 16 | Upcoming Events stories (weekly roundups) | Feature | High | Large | **DONE** |
| 17 | Altcoin Trending Analysis (data-driven market stories) | Feature | High | Large | **DONE** |

---

## Implementation Checklist

### Phase 1: Critical Fixes (Do First)

- [x] **Fix reject modal bug** (`queue.ex:356`) — **DONE**
  - [x] Remove `phx-click="close_reject"` from the outer overlay div
  - [x] Keep only `phx-click-away="close_reject"` on the inner modal div
  - [x] Test: click Reject, click into textarea, type reason, confirm reject works

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

- [x] **Fix link quality in generated articles** (`content_generator.ex`) — **DONE**
  - [x] Modify `format_source_summaries/1` to include full source URLs (add `\nURL: #{item.url}` to each item)
  - [x] Add a separate "AVAILABLE VERIFIED URLS" section in the prompt listing all source URLs
  - [x] Add explicit instruction: "ONLY use URLs from SOURCE MATERIAL. NEVER fabricate URLs."
  - [x] Add instruction: "If you cannot verify a URL, state the fact without linking."
  - [x] Remove or deprioritize the "link to primary sources" instruction that encourages URL guessing
  - [x] Store `source_urls` in `article_data` map in `enqueue_article/4` so the edit page can display them

- [x] **Fix links in revision prompt** (`editorial_feedback.ex`) — **DONE**
  - [x] Load the queue entry's topic and its feed_items before building revision prompt
  - [x] Pass source URLs into `build_revision_prompt/3`
  - [x] Add source URL list to the revision prompt so Claude can reference them

- [ ] **Optional: Add post-processing link validator** (`tiptap_builder.ex`)
  - [ ] After building TipTap content, extract all link URLs
  - [ ] Flag links that are just homepages (path is `/` or empty)
  - [ ] Log warnings for suspicious URLs
  - [ ] Consider removing links that don't pass validation

- [x] **Fix writing style repetition** (`content_generator.ex:186-264`) — **DONE**
  - [x] Add "STRUCTURAL VARIETY" section to the prompt with 5-6 article structure options
  - [x] Add explicit instruction: "DO NOT default to negative-then-positive pattern"
  - [x] Remove or soften the "always offer solutions or silver linings" instruction
  - [x] Add instruction to vary openings — not every article needs a counter-narrative
  - [ ] Test with 5-10 generated articles to verify variety

### Phase 3: Preview Feature & Draft Security

- [x] **Fix unpublished post access control** (`show.ex`) — **DONE** — SECURITY FIX
  - [x] In `handle_params/3`, after loading post, check `Post.published?/1`
  - [x] If not published and user is not admin: raise `NotFoundError`
  - [x] This prevents anyone from accessing draft posts via guessed slugs

- [x] **Create draft post from queue entry** (`content_publisher.ex`) — **DONE**
  - [x] Add `create_draft_post/1` function that creates post WITHOUT calling `publish_post/1`
  - [x] Store `post_id` on the queue entry when draft is created
  - [x] Add cleanup function to delete draft post if article is rejected

- [x] **Add admin-only access for unpublished posts** (`show.ex`) — **DONE**
  - [x] In `handle_params/3`, after loading post by slug, check `Post.published?/1`
  - [x] If not published: check if `current_user` is admin
  - [x] If not admin or not logged in: raise `NotFoundError`
  - [x] If admin: show the post with a "DRAFT PREVIEW" banner at the top

- [x] **Add Preview button to queue page** (`queue.ex`) — **DONE**
  - [x] Add "Preview" button next to "Edit" and "Publish Now"
  - [x] On click: create draft post (if not already created), open in new tab
  - [x] Store post_id on queue entry to enable re-preview

- [x] **Add Preview button to edit page** (`edit_article.ex`) — **DONE**
  - [x] Add "Preview on Site" button in the actions bar
  - [x] Creates draft post with current edits, opens in new tab

### Phase 4: On-Demand Article Generation

- [x] **Create RequestArticle LiveView** (`request_article.ex`) — **DONE**
  - [x] Form fields: topic, category, instructions, angle, author persona (optional)
  - [x] On submit: call `ContentGenerator.generate_on_demand/1`
  - [x] Use `start_async` for non-blocking generation
  - [x] Show loading state with "Generating article..." spinner
  - [x] On success: redirect to edit page for the new queue entry
  - [x] On error: show error message, allow retry

- [x] **Add `generate_on_demand/1` to ContentGenerator** (`content_generator.ex`) — **DONE**
  - [x] Accept admin-provided topic details instead of feed items
  - [x] Build a custom prompt that uses admin's instructions as source material
  - [x] Skip queue size check (admin requests bypass limits)
  - [x] Enqueue result with status "pending" and source "on_demand"
  - [x] Return `{:ok, queue_entry}` for redirect

- [x] **Add route** (`router.ex`) — **DONE**
  - [x] `live "/admin/content/request", ContentAutomationLive.RequestArticle, :new`

- [x] **Add "Request Article" button to dashboard** (`dashboard.ex`) — **DONE**
  - [x] Prominent button in header area
  - [x] Links to `/admin/content/request`

### Phase 5: Content Diversity

- [x] **Increase default queue size to 20** (`settings.ex`) — **DONE**
  - [x] Change `target_queue_size: 10` to `target_queue_size: 20` in `@defaults`
  - [x] Note: Production Mnesia settings table has 0 entries — everything uses code defaults.

- [x] **Add new categories** (`topic_engine.ex`) — **DONE**
  - [x] Add `fundraising`, `events` to `@categories`
  - [x] Update `build_clustering_prompt/1` to describe these categories to Claude

- [x] **Add category mappings** (`content_publisher.ex`) — **DONE**
  - [x] Add `"fundraising" => {"Fundraising", "fundraising"}` to `@category_map`
  - [x] Add `"events" => {"Events", "events"}` to `@category_map`

- [ ] **Configure category boosts** (admin dashboard or seeds)
  - [ ] Boost: `rwa: 3`, `defi: 2`, `token_launches: 2`, `altcoins: 2`, `fundraising: 3`, `events: 2`
  - [ ] Cap: `bitcoin: max 2/day`, `ethereum: max 2/day`
  - [ ] Set via `Settings.set(:category_config, ...)`

- [x] **Add diverse RSS feeds** (`feed_config.ex`) — **DONE** (added ~45 new feeds)
  - [x] Add RWA-focused feeds
  - [x] Add DeFi-focused feeds
  - [x] Add fundraising/VC feeds
  - [x] Add event calendar feeds

- [x] **Update clustering prompt for diversity** (`topic_engine.ex`) — **DONE**
  - [x] Add explicit guidance to identify fundraising rounds, VC activity, events
  - [x] Instruct Claude to categorize trending altcoin stories with analysis of WHY
  - [ ] Add instruction to identify thought leader profiles for "Blockster of the Week" — deferred (separate feature)

- [x] **Create "Blockster of the Week" generation pipeline** (Section 15) — **DONE** (Feb 2026)
  - [x] Create `XProfileFetcher` module (`lib/blockster_v2/content_automation/x_profile_fetcher.ex`) — fetches X profile + top 20 tweets by engagement via brand access token, returns `prompt_text` for Claude and `embed_tweets` (top 3) for TipTap embedding
  - [x] Add `get_user_by_username/2` to `XApiClient` — uses `GET /2/users/by/username/:username` with `user.fields=public_metrics,created_at,profile_image_url,name,username,description`
  - [x] Add `build_blockster_of_week_prompt/2` to `ContentGenerator` — magazine-profile style prompt with 7-section structure (Opening Hook → Background → What They've Built → In Their Own Words → Their Position → Why They're a Blockster → What's Next), 800-1200 words, uses X posts as primary source
  - [x] Add template routing to `build_on_demand_prompt/3` — checks `params[:template]` before content_type routing, extensible for future templates
  - [x] Add "Blockster of the Week" template option to `RequestArticle` LiveView — template dropdown at top, conditional fields (Person's Name, X Handle with @ prefix, Role/Title), auto-sets category/content_type, relabels Instructions to "Research Brief (optional)"
  - [x] Two-phase async submit: `start_async(:fetch_x_profile)` → then `start_async(:generate)` — shows "Fetching X profile & tweets..." then "Generating article..." loading states
  - [x] Auto-embed person's top 3 tweets as TipTap tweet nodes via existing `TweetFinder.insert_tweets_into_content/2` after generation
  - [x] Auto-tag articles with `["blockster-of-the-week", person-name-slug]`
  - [x] Add `blockster_of_week` to `@categories` in `topic_engine.ex` and `@category_map` in `content_publisher.ex`
  - [x] Add `blockster_of_week` to `@categories` in `request_article.ex`
  - [x] Add Blockster of the Week banner in `show.html.heex` — lime green `#CAFC00` with star icon, renders when `@post_category_slug == "blockster-of-the-week"`
  - [ ] Add `recent_blockster_profiles/1` dedup check (90-day window, soft warning) — deferred, nice-to-have

- [x] **Add altcoin trending analysis** (Section 17) — **DONE** (Feb 2026)
  - [x] Create `AltcoinAnalyzer` module (`lib/blockster_v2/content_automation/altcoin_analyzer.ex`) — `fetch_market_data/0` (CoinGecko `/coins/markets` with 7d/30d, ETS cache), `get_movers/2`, `detect_narratives/1` (3+ tokens >5% same direction), `format_for_prompt/2`, `get_recent_news_for_tokens/1` (FeedStore filter), `get_sector_data/2`. 8 sectors: ai, defi, l1, l2, gaming, rwa, meme, depin
  - [x] Create `MarketContentScheduler` module (`lib/blockster_v2/content_automation/market_content_scheduler.ex`) — `maybe_generate_weekly_movers/0` (gates via `Settings.get(:last_market_movers_date)`), `maybe_generate_narrative_report/0` (>10% threshold, 7-day per-sector cooldown via `Settings.get(:last_narrative_#{sector})`)
  - [x] Add `build_market_movers_prompt/2` to `ContentGenerator` — data-first, top 5 gainers/losers with WHY, 800-1200 words, market overview, narrative watch, what to watch next week
  - [x] Add `build_narrative_analysis_prompt/2` to `ContentGenerator` — sector rotation deep dive, token comparison, historical context, 600-900 words
  - [x] Add "Market Analysis" and "Narrative Report" templates to `RequestArticle` — auto-populate via `start_async(:fetch_market_data)` / `start_async(:fetch_sector_data)`, sector dropdown for narrative, auto-set category=altcoins/content_type
  - [x] Add `MarketContentScheduler` calls to `ContentQueue` — Friday (day 5) for weekly movers, every cycle for narrative report (self-gated)
  - [x] PriceTracker NOT modified — AltcoinAnalyzer uses its own `/coins/markets` call with separate ETS cache, falls back to PriceTracker 24h data
  - [x] Add "Market Analysis" button to admin dashboard with async handler
  - [ ] Monthly Altcoin Leaderboard (Section 17.3) — deferred, infrastructure supports it

- [x] **Add upcoming events content type** (Section 16) — **DONE** (Feb 2026)
  - [x] Create `upcoming_events` Mnesia table for admin-curated events — added to `MnesiaInitializer.@tables` with 12 attributes (id, name, event_type, start_date, end_date, location, url, description, tier, added_by, article_generated, created_at), type `:set`, index on `:start_date`. **NOTE: Both dev nodes need restart to create the new table.**
  - [x] Create `EventRoundup` module (`lib/blockster_v2/content_automation/event_roundup.ex`) — `add_event/1`, `list_events/1`, `delete_event/1`, `mark_article_generated/1`, `get_events_for_week/1` (merges admin Mnesia events + PostgreSQL `ContentGeneratedTopic` with category "events", deduplicates via Jaro distance >0.85), `generate_weekly_roundup/0`, `format_events_for_prompt/1` (groups by event type: conference/upgrade/unlock/regulatory/ecosystem)
  - [x] Add `build_weekly_roundup_prompt/2` to `ContentGenerator` — full prompt from Section 16.6 with 7-section structure (Opening → Conferences → Protocol Upgrades → Token Events → Regulatory → Ones to Watch → Closing), 800-1200 words
  - [x] Add `build_event_preview_prompt/2` to `ContentGenerator` — standalone event preview from Section 16.7 with 6-section structure, 600-900 words, accepts `event_dates`, `event_url`, `event_location` params
  - [x] Add template routing for `"weekly_roundup"` and `"event_preview"` in `build_on_demand_prompt/3` alongside existing `"blockster_of_week"` case
  - [x] Add "Event Preview" and "Weekly Roundup" templates to `RequestArticle` — template dropdown extended, conditional fields: Event Preview shows Event Dates/Location/URL fields (auto-sets category to events, content_type to news); Weekly Roundup auto-populates instructions via `start_async(:fetch_events)` → `EventRoundup.get_events_for_week()` on template change, hides Topic field, shows editable Event Data textarea
  - [x] Create `Events` LiveView (`lib/blockster_v2_web/live/content_automation_live/events.ex`) at `/admin/content/events` — table listing events sorted by start_date, inline "Add Event" form with all fields, Delete per row, "Generate Preview" button for major/notable events (creates article and marks `article_generated`), "Generate Weekly Roundup" button, follows admin page styling patterns
  - [x] Add `maybe_generate_weekly_content/0` to `ContentQueue` — checks `Date.day_of_week == 7` (Sunday), uses `Settings.get(:last_weekly_roundup_date)` to prevent duplicates, runs `EventRoundup.generate_weekly_roundup/0` in `Task.start` to not block queue
  - [x] Add route `live "/admin/content/events", ContentAutomationLive.Events, :index` in `router.ex` admin content group
  - [ ] Enhance TopicEngine clustering prompt to better identify event-related feed items — deferred, RSS feeds already provide some event content via category classification

### Phase 6: Factual News Content Type (Section 10)

- [x] **Database migrations** — **DONE** (migration `20250214_add_content_type_and_offer_fields.exs`)
  - [x] Add `content_type` column to `content_generated_topics` (default: "news")
  - [x] Add `content_type` column to `content_publish_queue` (default: "news")
  - [x] Update Ecto schemas with new field

- [x] **TopicEngine content type classification** (`topic_engine.ex`) — **DONE**
  - [x] Add content_type to clustering prompt instructions
  - [x] Add `content_type` to tool schema (enum: "news", "opinion", "offer")
  - [x] Default unclassified topics to "news"
  - [x] Store content_type on `ContentGeneratedTopic` records

- [x] **Separate generation prompts** (`content_generator.ex`) — **DONE**
  - [x] Create `build_news_prompt/4` — neutral, factual, Reuters-style
  - [x] Rename `build_generation_prompt/4` → `build_opinion_prompt/4`
  - [x] Add routing function that picks prompt based on `topic.content_type`
  - [x] Propagate content_type from topic to queue entry in `enqueue_article/4`

- [x] **Content mix enforcement** (`topic_engine.ex`) — **DONE**
  - [x] Add `FeedStore.count_queued_by_content_type/0` query
  - [x] Add `enforce_content_mix/1` to `analyze_and_select/0` pipeline
  - [x] Target: 55% news minimum across entire queue
  - [x] When below target, prioritize news topics in selection

- [x] **Increase default queue size to 20** (`settings.ex`) — **DONE** (see Phase 5)
  - [x] Change `target_queue_size: 10` → `20` in `@defaults`

- [x] **UI content type indicators** — **DONE**
  - [x] Show "News" / "Opinion" / "Offer" badge on queue entries (`queue.ex`)
  - [x] Show content type in edit page header (`edit_article.ex`)
  - [x] Show news/opinion/offer breakdown in dashboard stats (`dashboard.ex`)

### Phase 7: Offers Content Type (Section 14)

- [x] **Add offer feed sources** (`feed_config.ex`) — **DONE** (added DeFi, CEX, yield, L2 feeds)
  - [x] Verify all DeFi protocol feed URLs (Aave, Uniswap, Compound, Lido, Curve, Yearn, etc.)
  - [x] Verify all CEX feed URLs (Binance, Coinbase, Kraken, OKX, Bybit, KuCoin, etc.)
  - [x] Verify yield tracker feeds (DeFi Llama, DefiPrime, etc.)
  - [x] Verify L2/chain feeds (Arbitrum, Optimism, Base, Solana, etc.)
  - [x] Add all verified feeds — target ~55 new feeds
  - [ ] Remove/flag any feeds that return errors or paywalled content — verify after deploy

- [x] **Schema migrations** (combined with Phase 6 migration) — **DONE**
  - [x] Add `offer_type` to `content_generated_topics` and `content_publish_queue`
  - [x] Add `expires_at` to both tables
  - [x] Add `cta_url` and `cta_text` to `content_publish_queue`
  - [x] Update Ecto schemas

- [x] **TopicEngine offer classification** (`topic_engine.ex`) — **DONE**
  - [x] Add "offer" to content_type enum in clustering prompt
  - [x] Add `offer_type` enum to tool schema
  - [x] Extract offer metadata (expires_at, offer sub-type) during clustering

- [x] **Offer generation prompt** (`content_generator.ex`) — **DONE**
  - [x] Create `build_offer_prompt/4` — neutral explainer with risk warnings and CTA structure
  - [x] Route offer topics to the offer prompt
  - [x] Propagate offer fields (offer_type, expires_at, cta_url, cta_text) to queue entry

- [x] **Offer UI — queue & edit pages** — **DONE**
  - [x] Green "Offer" badge on queue entries (`queue.ex`)
  - [x] Offer sub-type label and expiration display on queue entries
  - [x] "Offer Details" section on edit page (CTA URL, CTA text, expiration, offer type, risk disclaimer toggle)

- [x] **Offer UI — published post** (`show.ex`) — **DONE**
  - [x] "Opportunity" banner at top of offer articles
  - [x] CTA button below content
  - [x] Expiration notice (auto-detects expired offers)
  - [x] Risk disclaimer footer

- [x] **Offer expiration handling** (`content_queue.ex`) — **DONE**
  - [x] Add `check_expired_offers/0` to 10-minute publish cycle
  - [ ] Add `FeedStore.get_published_expired_offers/1` query — basic logging only for now
  - [ ] Add `Blog.mark_offer_expired/1` — adds "EXPIRED" banner, keeps post live — deferred (using client-side expiration detection instead)

### Phase 8: Scheduler EST Timezone Fix (Section 11)

- [x] **Add `tz` dependency** (`mix.exs`) — **DONE**
  - [x] Add `{:tz, "~> 0.28"}` to deps
  - [x] Run `mix deps.get`

- [x] **Create TimeHelper module** (`time_helper.ex`) — **DONE**
  - [x] `est_to_utc/1` — convert naive datetime (EST input) to UTC
  - [x] `utc_to_est/1` — convert UTC datetime to EST for display
  - [x] `format_for_input/1` — format UTC as EST string for datetime-local input
  - [x] `format_display/1` — human-readable EST string with EST/EDT suffix
  - [x] Handle DST via America/New_York timezone

- [x] **Update edit page** (`edit_article.ex`) — **DONE**
  - [x] Remove `phx-hook="ScheduleDatetime"` from datetime input
  - [x] Use `TimeHelper.format_for_input/1` for input value
  - [x] Update `handle_event("update_scheduled_at")` to parse EST → UTC
  - [x] Display scheduled time with `TimeHelper.format_display/1`
  - [x] Add "All times are Eastern (EST/EDT)" label

- [x] **Update queue page** (`queue.ex`) — **DONE**
  - [x] Display scheduled times in EST using `TimeHelper.format_display/1`

- [x] **Remove JS hook** (`assets/js/app.js`) — **DONE**
  - [x] Delete `ScheduleDatetime` hook (lines 587-601)

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
