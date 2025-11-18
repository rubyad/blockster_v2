# Tweet Embed Implementation Guide

## Overview

This document explains how tweet embeds work in the Blockster V2 application. The implementation uses Twitter's official widgets.js library for client-side rendering of embedded tweets.

## Architecture

### 1. Data Storage (TipTap JSON Format)

Tweets are stored in the database as part of the post content in TipTap JSON format:

```json
{
  "type": "tweet",
  "attrs": {
    "url": "https://x.com/username/status/1234567890",
    "id": "1234567890"
  }
}
```

**Key Fields:**
- `type`: Always "tweet" to identify this node as a tweet embed
- `attrs.url`: The full URL to the tweet (can be x.com or twitter.com)
- `attrs.id`: The tweet status ID (numeric string)

### 2. Server-Side Rendering

**File:** `lib/blockster_v2_web/live/post_live/tiptap_renderer.ex`

The `render_node/1` function processes tweet nodes and converts them to HTML blockquotes:

```elixir
defp render_node(%{"type" => "tweet", "attrs" => %{"url" => url, "id" => tweet_id}}) do
  # Normalize URL to use twitter.com instead of x.com for better compatibility
  normalized_url = String.replace(url, "x.com", "twitter.com")

  """
  <blockquote class="twitter-tweet" data-tweet-id="#{escape_html(tweet_id)}" data-theme="light" data-dnt="true">
    <p lang="en" dir="ltr">Loading tweet...</p>
    <a href="#{escape_html(normalized_url)}">View Tweet</a>
  </blockquote>
  """
end
```

**Important Details:**
- URLs are normalized from `x.com` to `twitter.com` for better compatibility with Twitter's widgets library
- The blockquote has the class `twitter-tweet` which is required by Twitter's script
- `data-tweet-id` attribute contains the tweet ID
- `data-theme="light"` sets the theme to light mode
- `data-dnt="true"` enables "Do Not Track" privacy mode
- The `<p>` tag with "Loading tweet..." provides placeholder content
- The `<a>` tag links to the actual tweet as a fallback

### 3. Twitter Widgets Script Loading

**File:** `lib/blockster_v2_web/components/layouts/root.html.heex`

The Twitter widgets library is loaded in the HTML head:

```html
<script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script>
```

**Key Characteristics:**
- Loaded with `async` attribute for non-blocking page load
- This script defines the global `window.twttr` object
- The script automatically looks for `<blockquote class="twitter-tweet">` elements

### 4. Client-Side Rendering (Phoenix LiveView Hook)

**File:** `assets/js/twitter_widgets.js`

A Phoenix LiveView hook manages the client-side tweet rendering:

```javascript
export const TwitterWidgets = {
  mounted() {
    console.log("TwitterWidgets hook mounted");
    this.loadWidgets();
  },

  updated() {
    console.log("TwitterWidgets hook updated");
    this.loadWidgets();
  },

  loadWidgets() {
    if (typeof window.twttr !== "undefined" && window.twttr.widgets) {
      console.log("Loading Twitter widgets in content...", this.el);

      window.twttr.widgets.load(this.el).then(() => {
        console.log("Twitter widgets loaded successfully");
      }).catch((error) => {
        console.error("Error loading Twitter widgets:", error);
      });
    } else {
      console.log("Twitter widgets not ready, retrying in 100ms...");
      setTimeout(() => this.loadWidgets(), 100);
    }
  }
};
```

**Hook Lifecycle:**
1. `mounted()`: Called when the LiveView mounts, triggers widget loading
2. `updated()`: Called when the LiveView updates (e.g., navigation), re-triggers loading
3. `loadWidgets()`:
   - Checks if `window.twttr` is available
   - If not ready, retries every 100ms
   - Calls `twttr.widgets.load(this.el)` to process all tweet blockquotes in the element
   - Returns a Promise that resolves when all tweets are rendered

**File:** `assets/js/app.js`

The hook is registered with Phoenix LiveSocket:

```javascript
import { TwitterWidgets } from "./twitter_widgets.js";

const liveSocket = new LiveSocket("/live", Socket, {
  hooks: { TwitterWidgets, /* other hooks */ }
});
```

### 5. Hook Attachment in Template

**File:** `lib/blockster_v2_web/live/post_live/show.html.heex`

The hook is attached to the post content container:

```html
<div
  id="post-content"
  class="text-[#343434] leading-[1.4] space-y-6 font-segoe_regular"
  phx-hook="TwitterWidgets"
  phx-no-format
>
  <%= raw(render_quill_content(@post.content)) %>
</div>
```

**Key Attributes:**
- `phx-hook="TwitterWidgets"`: Attaches the TwitterWidgets hook to this element
- `phx-no-format`: Prevents Phoenix from formatting the HTML (preserves tweet structure)
- The hook will process all tweet blockquotes within this container

## How It All Works Together

### Initial Page Load

1. User navigates to a post with tweet embeds
2. **Server-side**: Phoenix LiveView renders the page
3. **Server-side**: TipTap renderer converts tweet JSON to blockquote HTML
4. **Client-side**: Browser receives HTML with blockquotes
5. **Client-side**: Twitter's `widgets.js` script loads asynchronously
6. **Client-side**: Phoenix LiveView mounts and triggers the `TwitterWidgets` hook
7. **Client-side**: Hook waits for `window.twttr` to be available
8. **Client-side**: Hook calls `twttr.widgets.load()` on the content container
9. **Client-side**: Twitter's script finds all blockquotes with class `twitter-tweet`
10. **Client-side**: Twitter's script replaces each blockquote with a fully rendered embedded tweet (iframe)

### LiveView Navigation

When navigating between posts using LiveView:

1. LiveView updates the page content
2. `TwitterWidgets.updated()` is called automatically
3. The hook re-runs `loadWidgets()` to process any new tweets
4. New tweet blockquotes are transformed into embedded tweets

## Troubleshooting

### Tweets Don't Display

**Symptoms:** You see only the blockquote with "Loading tweet..." text

**Common Causes:**

1. **Twitter widgets script not loaded**
   - Check browser console for "Twitter widgets not ready, retrying..."
   - Verify `<script>` tag in `root.html.heex`
   - Check for network errors loading `platform.twitter.com/widgets.js`

2. **Hook not attached**
   - Check browser console for "TwitterWidgets hook mounted"
   - Verify `phx-hook="TwitterWidgets"` attribute exists on content div
   - Verify hook is registered in `app.js`

3. **Missing tweet content in blockquote**
   - Ensure blockquote has `<p>` and `<a>` tags with content
   - Empty blockquotes may not be processed by Twitter's script

4. **Invalid tweet URL or ID**
   - Verify the tweet URL is valid and the tweet exists
   - Check that the tweet ID matches the URL

5. **Twitter API/Service Issues**
   - Twitter/X's embedding service may be down or restricted
   - Check if tweets load on twitter.com/x.com directly

### Console Debugging

Enable detailed logging by checking the browser console for these messages:

```
TwitterWidgets hook mounted
Twitter widgets not ready, retrying in 100ms...  // If script hasn't loaded yet
Loading Twitter widgets in content...            // When starting to process
Twitter widgets loaded successfully              // When complete
Error loading Twitter widgets: [error]           // If there's an error
```

### Testing Tweet Embeds

To test if tweet embeds are working:

1. Open browser developer console (F12)
2. Navigate to a post with tweet embeds
3. Look for console messages from the TwitterWidgets hook
4. Check Network tab for successful load of `widgets.js`
5. Inspect the DOM - tweets should be in `<iframe>` elements, not blockquotes

## Historical Context

### Why This Approach?

**Previous Attempt: Server-Side oEmbed**

The original implementation tried to use Twitter's oEmbed API (`https://publish.twitter.com/oembed`) to fetch tweet HTML on the server-side. This approach failed because:

- Twitter/X's oEmbed API stopped working reliably
- The API returns HTML error pages instead of JSON
- Server-side rendering created performance and caching issues

**Current Approach: Client-Side Widgets**

The current implementation uses Twitter's official `widgets.js` for client-side rendering:

- ✅ Works with Twitter/X's current embedding system
- ✅ Handles tweet updates and availability automatically
- ✅ Better performance (no server-side API calls)
- ✅ Follows Twitter's recommended embedding method
- ✅ Respects user privacy preferences (DNT)

### URL Normalization (x.com → twitter.com)

Twitter rebranded to X and changed URLs from `twitter.com` to `x.com`. However, the widgets library works better with `twitter.com` URLs, so we normalize all URLs in the renderer:

```elixir
normalized_url = String.replace(url, "x.com", "twitter.com")
```

This ensures compatibility regardless of which domain is stored in the database.

## Adding New Tweet Embeds

### Via TipTap Editor

1. In the post editor, use the tweet embed button (if available in toolbar)
2. Paste the tweet URL
3. The editor will create the appropriate TipTap JSON structure
4. Save the post

### Via Database

If you need to manually add a tweet to the database:

```elixir
# Extract tweet ID from URL
# Example: https://x.com/username/status/1234567890
tweet_url = "https://x.com/username/status/1234567890"
tweet_id = "1234567890"

# Add to TipTap content structure
tweet_node = %{
  "type" => "tweet",
  "attrs" => %{
    "url" => tweet_url,
    "id" => tweet_id
  }
}

# Insert into the content's "content" array at the desired position
```

## Configuration Options

### Theme

To change the tweet theme from light to dark, modify the `data-theme` attribute in `tiptap_renderer.ex`:

```elixir
data-theme="dark"  # Dark theme
data-theme="light" # Light theme (current)
```

### Privacy (Do Not Track)

To disable Do Not Track, modify the `data-dnt` attribute:

```elixir
data-dnt="true"  # Enable DNT (current)
data-dnt="false" # Disable DNT
```

### Card Display

To hide media/cards in tweets, add:

```elixir
data-cards="hidden"
```

### Conversation Display

To hide the conversation thread, add:

```elixir
data-conversation="none"
```

## Dependencies

- **Phoenix LiveView**: For reactive UI updates
- **Twitter widgets.js**: Official Twitter embedding library
- **TipTap**: For content editing and storage

## Related Files

- `lib/blockster_v2_web/live/post_live/tiptap_renderer.ex` - Server-side rendering
- `assets/js/twitter_widgets.js` - Client-side hook
- `assets/js/app.js` - Hook registration
- `lib/blockster_v2_web/live/post_live/show.html.heex` - Template with hook attachment
- `lib/blockster_v2_web/components/layouts/root.html.heex` - Twitter script loading

## Support

For issues with tweet embeds:
1. Check this documentation
2. Review browser console for errors
3. Verify Twitter/X service status
4. Test with a known working tweet URL
