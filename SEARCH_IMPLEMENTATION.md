# Search Implementation Guide

This document explains how the full-text search system works in the Blockster V2 application.

## Overview

The search system provides real-time, prefix-matching search across blog posts with intelligent ranking that prioritizes title matches. It uses PostgreSQL full-text search with a LiveView-based UI that displays results in a dropdown as users type.

## Architecture

### Components

1. **Database Layer** - PostgreSQL full-text search with tsvector
2. **Query Layer** - Ecto queries in `Blog` context
3. **LiveView Layer** - Event handlers and socket assigns
4. **UI Layer** - Phoenix components with dropdown results

## Database Setup

### Migration: `add_searchable_to_posts.exs`

The search system uses a `searchable` column with type `tsvector` that stores searchable text with weighted values:

```sql
ALTER TABLE posts
ADD COLUMN searchable tsvector
GENERATED ALWAYS AS (
  setweight(to_tsvector('english', COALESCE(title, '')), 'A') ||
  setweight(to_tsvector('english', COALESCE(excerpt, '')), 'B') ||
  setweight(to_tsvector('english', COALESCE(content, '')), 'C')
) STORED;
```

**Weight Priorities:**
- **A** - Title (highest priority)
- **B** - Excerpt (medium priority)
- **C** - Content (lowest priority)

### GIN Index

A GIN (Generalized Inverted Index) is created for fast full-text search:

```sql
CREATE INDEX posts_searchable_idx ON posts USING GIN(searchable);
```

This index makes full-text search queries extremely fast, even with thousands of posts.

### How It Works

- The `searchable` column is a **generated column** that automatically updates when title, excerpt, or content change
- PostgreSQL's `to_tsvector()` function converts text into searchable tokens
- The `setweight()` function assigns importance levels (A, B, C)
- The `||` operator combines weighted vectors

## Query Implementation

### Location: `lib/blockster_v2/blog.ex`

```elixir
def search_posts_fulltext(query_string, opts \\ []) do
  limit = Keyword.get(opts, :limit, 20)

  # Convert query to support prefix matching
  # Split on spaces, add :* to each word for prefix matching, join with &
  tsquery = query_string
    |> String.split(~r/\s+/, trim: true)
    |> Enum.map(&"#{&1}:*")
    |> Enum.join(" & ")

  published_posts_query()
  |> exclude(:order_by)  # Remove inherited ORDER BY published_at DESC
  |> where([p], fragment(
      "searchable @@ to_tsquery('english', ?)",
      ^tsquery
    ))
  |> order_by([p], [
      desc: fragment(
        """
        CASE
          WHEN to_tsvector('english', COALESCE(?, '')) @@ to_tsquery('english', ?) THEN 100
          ELSE 0
        END + ts_rank_cd(searchable, to_tsquery('english', ?), 1)
        """,
        p.title,
        ^tsquery,
        ^tsquery
      ),
      desc: p.published_at
    ])
  |> limit(^limit)
  |> Repo.all()
  |> populate_author_names()
end
```

### Prefix Matching

**User Input:** "moon"

**Transformation:**
```elixir
"moon"
|> String.split(~r/\s+/, trim: true)  # ["moon"]
|> Enum.map(&"#{&1}:*")                # ["moon:*"]
|> Enum.join(" & ")                    # "moon:*"
```

The `:*` wildcard tells PostgreSQL to match any word starting with "moon", so it will find:
- "moon"
- "moonpay"
- "moonlight"
- etc.

**Multi-word queries:**
- Input: "bitcoin moon"
- Result: `"bitcoin:* & moon:*"`
- Matches: Posts containing words starting with "bitcoin" AND words starting with "moon"

### Ranking Algorithm

The search uses a two-part ranking system:

#### 1. Title Boost (+100 points)

```sql
CASE
  WHEN to_tsvector('english', COALESCE(title, '')) @@ to_tsquery('english', ?) THEN 100
  ELSE 0
END
```

If the search query matches the post's title, add 100 points to the rank. This ensures posts with the search term in the title appear first.

#### 2. Full-Text Rank

```sql
ts_rank_cd(searchable, to_tsquery('english', ?), 1)
```

- `ts_rank_cd()` - PostgreSQL's cover density ranking function
- Considers the weighted values (A, B, C) set in the migration
- The `1` parameter uses normalization method 1 (divides rank by 1 + log of document length)
- Returns a decimal score (e.g., 0.6, 1.2, 3.5)

**Final Score** = Title Boost (0 or 100) + Full-Text Rank (0.0 to ~10.0)

**Example Results:**
1. Post with "moon" in title: Score = 100 + 2.5 = 102.5
2. Post with "moon" only in content: Score = 0 + 1.8 = 1.8

#### 3. Secondary Sort

```elixir
desc: p.published_at
```

Posts with the same search rank are sorted by publish date (newest first).

### Query Ordering Gotcha

**Problem:** The `published_posts_query()` inherits `order_by: [desc: p.published_at]` from `posts_base_query()`, which would interfere with search ranking.

**Solution:** Use `exclude(:order_by)` to remove inherited ordering before applying search-specific ordering:

```elixir
published_posts_query()
|> exclude(:order_by)  # Critical: removes inherited published_at ordering
|> where([p], fragment(...))
|> order_by([p], [desc: fragment(...), desc: p.published_at])
```

## LiveView Integration

### Socket Assigns

Three assigns track search state:

```elixir
socket
|> assign(:search_query, "")           # Current search input
|> assign(:search_results, [])         # Array of matching posts
|> assign(:show_search_results, false) # Whether to display dropdown
```

### Event Flow

#### 1. User Types in Search Input

**UI Component:** `lib/blockster_v2_web/components/layouts.ex`

```heex
<input
  type="text"
  phx-keyup="search_posts"
  phx-debounce="300"
  phx-value-value={@search_query}
  placeholder="Search posts..."
/>
```

- `phx-keyup="search_posts"` - Sends "search_posts" event to LiveView on each keystroke
- `phx-debounce="300"` - Waits 300ms after user stops typing before sending event
- `phx-value-value={@search_query}` - Sends current input value with event

#### 2. LiveView Handles Event

**Location:** `lib/blockster_v2_web/live/post_live/index.ex`

```elixir
@impl true
def handle_event("search_posts", %{"value" => query}, socket) do
  results = if String.length(query) >= 2 do
    Blog.search_posts_fulltext(query, limit: 20)
  else
    []
  end

  {:noreply,
   socket
   |> assign(:search_query, query)
   |> assign(:search_results, results)
   |> assign(:show_search_results, String.length(query) >= 2)}
end
```

**Logic:**
- Minimum 2 characters required to search (prevents single-letter searches)
- Updates socket assigns with query, results, and visibility flag
- Returns `{:noreply, socket}` to update the UI

#### 3. UI Updates Automatically

The LiveView automatically re-renders with new assigns:

```heex
<%= if @show_search_results && length(@search_results) > 0 do %>
  <div class="search-dropdown">
    <%= for post <- @search_results do %>
      <.link navigate={~p"/posts/#{post.slug}"}>
        <%= post.title %>
      </.link>
    <% end %>
  </div>
<% end %>
```

#### 4. User Closes Dropdown

Clicking outside or pressing Escape sends "close_search" event:

```elixir
@impl true
def handle_event("close_search", _params, socket) do
  {:noreply,
   socket
   |> assign(:search_query, "")
   |> assign(:search_results, [])
   |> assign(:show_search_results, false)}
end
```

## Data Flow Diagram

```
User Types "moon"
      ↓
[Input Field] phx-keyup="search_posts" (300ms debounce)
      ↓
[LiveView] handle_event("search_posts", %{"value" => "moon"}, socket)
      ↓
[Blog Context] search_posts_fulltext("moon", limit: 20)
      ↓
Transform to tsquery: "moon:*"
      ↓
[PostgreSQL]
  WHERE searchable @@ to_tsquery('english', 'moon:*')
  ORDER BY (title_boost + ts_rank_cd) DESC
      ↓
Returns: [%Post{}, %Post{}, ...]
      ↓
[LiveView] assign(:search_results, results)
      ↓
[UI Component] Re-renders with dropdown showing results
      ↓
User sees dropdown with posts matching "moon"
```

## Component Communication

### Layout to Header Component

**File:** `lib/blockster_v2_web/components/layouts/app.html.heex`

```heex
<.site_header
  current_user={assigns[:current_user]}
  search_query={assigns[:search_query] || ""}
  search_results={assigns[:search_results] || []}
  show_search_results={assigns[:show_search_results] || false}
/>
```

The layout passes search assigns from the LiveView socket to the `site_header` component.

### Header Component Attributes

**File:** `lib/blockster_v2_web/components/layouts.ex`

```elixir
attr :current_user, :any, default: nil
attr :search_query, :string, default: ""
attr :search_results, :list, default: []
attr :show_search_results, :boolean, default: false

def site_header(assigns) do
  # Component implementation
end
```

The `attr` declarations define the expected attributes with types and defaults.

## Adding Search to New Pages

To add search functionality to a new LiveView page:

### 1. Initialize Assigns in `mount/3`

```elixir
def mount(_params, _session, socket) do
  {:ok,
   socket
   |> assign(:search_query, "")
   |> assign(:search_results, [])
   |> assign(:show_search_results, false)
   |> assign(:other_data, ...)}
end
```

### 2. Add Event Handlers

```elixir
@impl true
def handle_event("search_posts", %{"value" => query}, socket) do
  results = if String.length(query) >= 2 do
    Blog.search_posts_fulltext(query, limit: 20)
  else
    []
  end

  {:noreply,
   socket
   |> assign(:search_query, query)
   |> assign(:search_results, results)
   |> assign(:show_search_results, String.length(query) >= 2)}
end

@impl true
def handle_event("close_search", _params, socket) do
  {:noreply,
   socket
   |> assign(:search_query, "")
   |> assign(:search_results, [])
   |> assign(:show_search_results, false)}
end
```

### 3. Ensure Layout Passes Assigns

The `app.html.heex` layout already passes search assigns to `site_header`, so no changes needed if using the standard layout.

## Performance Considerations

### Database Performance

- **GIN Index:** Makes full-text search queries run in milliseconds even with 10,000+ posts
- **Limit Clause:** Default limit of 20 results prevents slow queries
- **Prefix Matching:** The `:*` wildcard is efficient with GIN indexes

### LiveView Performance

- **Debouncing:** 300ms debounce prevents excessive server requests while typing
- **Minimum Query Length:** 2-character minimum prevents searching single letters
- **Empty Results:** Returns `[]` instead of querying database for short queries

### Network Performance

- **WebSocket:** Uses persistent WebSocket connection (no HTTP overhead per keystroke)
- **Differential Updates:** Phoenix LiveView only sends DOM changes, not full HTML
- **Preloaded Associations:** `preload: [:author, :category]` prevents N+1 queries

## PostgreSQL Full-Text Search Concepts

### tsvector

A `tsvector` is a sorted list of distinct lexemes (normalized words):

```sql
to_tsvector('english', 'The quick brown fox')
-- Result: 'brown':3 'fox':4 'quick':2
```

Notice:
- "The" is removed (stop word)
- Numbers indicate position in original text
- Words are normalized to root form

### tsquery

A `tsquery` represents a search query with operators:

```sql
to_tsquery('english', 'moon:*')  -- Prefix match
to_tsquery('english', 'moon & pay')  -- AND operator
to_tsquery('english', 'moon | sun')  -- OR operator
```

### Match Operator (`@@`)

The `@@` operator checks if a tsvector matches a tsquery:

```sql
to_tsvector('english', 'moonpay is a payment processor') @@ to_tsquery('english', 'moon:*')
-- Result: true (moonpay starts with moon)
```

### Ranking Functions

**ts_rank_cd()** - Cover density ranking:
- Considers how close together matching terms appear
- Weights matter: 'A' weighted terms score higher than 'C'
- Normalization prevents long documents from always ranking higher

## Debugging

### Server Logs

The search implementation includes debug output:

```elixir
IO.puts("🔍 SEARCH DEBUG")
IO.inspect(query, label: "Query")
IO.inspect(length(results), label: "Results count")
IO.inspect(String.length(query) >= 2, label: "Show dropdown")
```

**Example Output:**
```
🔍 SEARCH DEBUG
Query: "moon"
Results count: 5
Show dropdown: true
```

### Database Query Inspection

To see the actual SQL query:

```elixir
Blog.search_posts_fulltext("moon", limit: 20)
|> IO.inspect(label: "SQL Query")
```

### Testing Search in IEx

```elixir
iex -S mix
iex> BlocksterV2.Blog.search_posts_fulltext("moon", limit: 5)
```

## Common Issues and Solutions

### Issue: Dropdown doesn't appear

**Check:**
1. Are search assigns initialized in `mount/3`?
2. Is `show_search_results` set to `true`?
3. Are search assigns passed from layout to `site_header`?

### Issue: Prefix matching not working

**Check:**
- Using `to_tsquery()` with `:*` wildcard, not `websearch_to_tsquery()`

### Issue: Wrong ranking order

**Check:**
- Is `exclude(:order_by)` called before search ordering?
- Is title boost (`CASE WHEN...`) included in ranking fragment?

### Issue: Search too slow

**Check:**
- Is GIN index created on `searchable` column?
- Are results limited (default: 20)?
- Are associations preloaded to prevent N+1 queries?

## Future Enhancements

Potential improvements to the search system:

1. **Typo Tolerance:** Use `pg_trgm` extension for fuzzy matching
2. **Search Highlighting:** Show matched terms in bold in results
3. **Search Analytics:** Track popular search queries
4. **Multi-language Support:** Support languages beyond English
5. **Search Filters:** Filter by category, author, date range
6. **Search History:** Show user's recent searches
7. **Autocomplete:** Suggest complete queries as user types
8. **Search Synonyms:** Map related terms (e.g., "crypto" → "cryptocurrency")

## References

- [PostgreSQL Full-Text Search Documentation](https://www.postgresql.org/docs/current/textsearch.html)
- [Phoenix LiveView Documentation](https://hexdocs.pm/phoenix_live_view/)
- [Ecto Query Documentation](https://hexdocs.pm/ecto/Ecto.Query.html)
