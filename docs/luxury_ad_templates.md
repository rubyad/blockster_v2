# Luxury Ad Templates Reference

How the watch / car / jet card ad templates work — for admins picking templates in `/admin/banners`, and for engineers extending the system.

> **Quick links**
> - Full ad system source of truth: [`ad_banners_system.md`](ad_banners_system.md)
> - Code: `lib/blockster_v2_web/components/design_system.ex` (each `def ad_banner(%{banner: %{template: "..."}})` clause)
> - Admin UI: `lib/blockster_v2_web/live/banners_admin_live.ex` (`@templates`, `@template_params`, `@enum_params`)
> - Schema whitelist: `lib/blockster_v2/ads/banner.ex` (`@valid_templates`)
> - Production seed: `priv/repo/seeds_banners.exs` (unified — replaces the old `seeds_luxury_ads.exs`)
> - Build history: [`solana_build_history.md`](solana_build_history.md) — "Real-Time Widgets Phase 6 + Luxury Ad Vertical (2026-04-15)"

---

## Table of Contents

1. [How template ads work](#how-template-ads-work) — system overview
2. [Live SOL pricing](#live-sol-pricing) — how `price_usd` becomes `N SOL`
3. [Image hosting workflow](#image-hosting-workflow) — sips → ExAws → ImageKit
4. [Template catalog](#template-catalog) — every luxury template's purpose + params
5. [Picking the right template](#picking-the-right-template) — placement guide
6. [Adding a new luxury template](#adding-a-new-luxury-template) — the playbook
7. [Common params (shared across most templates)](#common-params-shared-across-most-templates)

---

## How template ads work

The template ad system is **separate from the real-time widgets system** but shares the `ad_banners` table. A banner row has either:
- `widget_type` set (e.g. `rt_skyscraper`) → renders via a `BlocksterV2Web.Widgets.*` component (real-time data from Mnesia caches)
- `widget_type: nil` + `template` set (e.g. `luxury_watch`) → renders via a `BlocksterV2Web.DesignSystem.ad_banner/1` clause

The dispatcher (`BlocksterV2Web.WidgetComponents.widget_or_ad/1`) handles the branch.

**Template renderers live in `design_system.ex`.** Each is a multi-clause `ad_banner` function matching on `template:`. The clause reads `params` (a JSONB map on the banner row), runs it through `sanitize_ad_params/1` (strips empty strings to nil so `@p["key"] || "default"` falls through), and renders HEEx.

**`@params` is JSONB.** Add as many fields as you want — only the ones the template reads matter. Admin form (`/admin/banners`) shows the fields registered in `@template_params[template]`.

---

## Live SOL pricing

All luxury templates store **USD** in `params["price_usd"]` (just the dollar amount as a number) and convert to SOL **at render time**. The conversion reads the live SOL/USD rate from `BlocksterV2.PriceTracker.get_price("SOL")`, which reads the `token_prices` Mnesia table refreshed every minute by the global `PriceTracker` GenServer.

The two helpers (defp in `design_system.ex`):

```elixir
defp luxury_watch_price_sol(price_usd)
# Returns "1,234" / "280.2" / "12.34" / "—"
# Formatting tiers:
#   sol >= 1000 → integer with thousand-separators
#   sol >= 100  → 1 decimal
#   sol < 100   → 2 decimals
#   PriceTracker miss → "—"

defp luxury_watch_format_usd(price_usd)
# Returns "23,500" / "316,900" / "—"
```

Templates render the SOL line as: `<SOL logo image> 280.2 SOL ≈ $23,500` — large monospace SOL amount, smaller grey USD subtitle.

If `PriceTracker` hasn't fetched yet (e.g. fresh deploy before the first 60s tick), SOL shows `—` and USD still renders. Graceful degradation.

**Don't store SOL on the banner.** Always derive at render time. Storing SOL would go stale within minutes.

---

## Image hosting workflow

All luxury ad images are hosted on ImageKit. ImageKit serves directly from the project's S3 bucket as origin — uploading to S3 → image is immediately available at `https://ik.imagekit.io/blockster/<key>`.

### Step 1: Source the image

`curl` from the dealer site. Dealers usually have a CDN that requires a specific URL pattern (Gray & Sons uses `cdn.grayandsons.com/s/<slug>-w360.jpg.auto`; sizes other than `w360` may 403). Pre-check with `curl -I` for `200 OK` + `image/jpeg` content-type.

### Step 2: Pad or crop with `sips` (macOS built-in)

Watches benefit from a small white border so the watch sits in a frame:

```bash
sips -p 380 270 --padColor FFFFFF watch.jpg --out watch-snug.jpg
# -p H W → pad to height H, width W
# --padColor FFFFFF → fill bars with white
```

Cars and jets need **bottom-only crops** to remove dealer-overlay strips (logo + contact info baked into stock photos). Default `sips -c` is center-crop — use `--cropOffset 0 0` to anchor at top-left:

```bash
sips -c 600 1024 --cropOffset 0 0 lambo.jpg --out lambo-clean.jpg
# -c H W → crop to height H, width W
# --cropOffset 0 0 → start at row 0, col 0 (top-left), keep top H rows + left W cols
```

### Step 3: Upload to S3

```elixir
mix run -e '
binary = File.read!("/tmp/watch-snug.jpg")
bucket = Application.get_env(:blockster_v2, :s3_bucket)
ts = DateTime.utc_now() |> DateTime.to_unix()
hex = :crypto.strong_rand_bytes(6) |> Base.encode16(case: :lower)
key = "ads/<dealer-slug>/#{ts}-#{hex}-watch-snug.jpg"
{:ok, _} = ExAws.S3.put_object(bucket, key, binary,
                                content_type: "image/jpeg",
                                acl: :public_read) |> ExAws.request()
IO.puts("https://ik.imagekit.io/blockster/#{key}")
'
```

ACL `:public_read` is required for ImageKit to serve it.

### Step 4: Set on banner

Update both `image_url` (top-level column, used for legacy fallback) and `params["image_url"]` (which is what every luxury template actually reads):

```elixir
b = BlocksterV2.Ads.get_banner!(<id>)
url = "https://ik.imagekit.io/blockster/<key>"
new_params = Map.put(b.params, "image_url", url)
{:ok, _} = BlocksterV2.Ads.update_banner(b, %{image_url: url, params: new_params})
```

### When NOT to use this workflow

If you're an admin uploading from the browser (not scripting bulk operations), use `/admin/banners` → "Banner Image" upload. The `BannerAdminUpload` JS hook handles S3 presign + ImageKit URL rewrite automatically.

---

## Template catalog

11 luxury templates organized by family. All accept the [common params](#common-params-shared-across-most-templates) plus a few template-specific ones noted below.

### Watch family (Gray & Sons)

#### `luxury_watch`
**560px max-width** card, image-driven height (no crop). Editorial layout: brand strip with gold rules → full-width watch photo → thin gold divider → model name (uppercase serif) + reference (italic) → live SOL price + USD subtitle. Whole card is the click target. Default accent color: champagne gold `#C9A961`.

**Template-specific params:** `model_name`, `reference`, `price_usd`, optional `cta_text`.

**Use when:** you want a single watch as the editorial centerpiece of an article column. Best for 720px-wide content slots like `article_inline_*`.

#### `luxury_watch_compact_full`
**560px max**, but tighter padding throughout. Image-driven height (no crop). Same content shape as `luxury_watch`. Renders ~30% shorter.

**Use when:** you want the luxury look without dominating the article. Trade-off: less breathing room around the price/CTA.

#### `luxury_watch_skyscraper`
**200px wide × ~280px tall** sidebar tile. Image-driven height. Compact brand strip + image + tiny model line + small SOL price line.

**Use when:** vertical sidebar slots like `sidebar_left`, `sidebar_right`. Stack multiple watches one per slot.

#### `luxury_watch_banner`
**Full-width × ~140px** horizontal leaderboard. 180px square image left, info right (brand · model · SOL price). Stacks vertically on mobile (image on top).

**Use when:** `homepage_top_*` placements. Lower height than the inline templates so it doesn't dominate a homepage hero strip.

#### `luxury_watch_split`
**Full-width × ~380px** split layout. Dark editorial info column on the LEFT (brand · model · reference · SOL price · CTA pill), light watch panel on the RIGHT. The right panel uses `image_bg_color` (white by default) which is designed to match the white padding sips adds to watch images — the watch reads as floating in pure white.

**Template-specific params:** `cta_text` (CTA pill is part of this template's signature look).

**Use when:** wider article inline slots (`article_inline_3`, etc.) where you want a more "product-detail" feel than the centered editorial of `luxury_watch`.

### Car family (Ferrari of Miami, Lamborghini Miami)

#### `luxury_car`
**720px max-width** card. Brand strip + optional accent-color badge top → edge-to-edge landscape car photo → bold "YEAR MODEL" headline (year in accent color) → italic trim line → live SOL price + USD + outlined CTA pill. Default accent: Ferrari red `#FF2800` (Lambo uses lime green `#A4DD00`).

**Template-specific params:** `year`, `model_name`, `trim`, optional `badge` (e.g. "Pre-owned · 948 mi"), optional `cta_text` (default "View this car").

The original spec row (4-column Mileage/Exterior/Interior/Stock) was removed mid-design — info is now condensed into the trim line + badge. Schema still accepts `spec_*_label` and `spec_*_value` fields but the renderer ignores them.

**Use when:** showcasing a single dealer inventory listing inline in an article.

#### `luxury_car_skyscraper`
**200px wide** sidebar variant. Brand strip + photo + year/model + trim + SOL price.

**Use when:** sidebar slots. Tighter than `luxury_watch_skyscraper` because car photos are landscape — the tile is shorter.

#### `luxury_car_banner`
**Full-width × ~180px** horizontal. 300px image left, info right. Stacks on mobile.

**Use when:** `homepage_top_desktop` or `homepage_top_mobile`.

### Jet card family (Flight Finder Exclusive)

#### `jet_card_compact`
**560px wide** card. Brand strip + optional badge → edge-to-edge jet photo → big "**N HOURS**" headline (N in accent color, "hours" in muted small caps) → tagline → italic aircraft category → divider → live SOL price + price_subtitle (e.g. "25-hour jet card · Light Jet tier") → outlined accent CTA pill. Default accent: champagne gold `#D4AF37`. Default bg: midnight navy gradient `#0a1838 → #1a2c5e`.

**Template-specific params:** `hours` (number — the prepaid block size), `headline` (one-liner under the hours), `aircraft_category`, optional `badge` (e.g. "25-hour jet card"), optional `price_subtitle`, optional `cta_text` (default "Buy Jet Card").

**Use when:** any inline slot. The original 720px-wide `jet_card` template was removed in favor of this compact version per design feedback.

#### `jet_card_skyscraper`
**200px wide** sidebar variant. Same content shape, condensed.

**Use when:** sidebar slots.

---

## Picking the right template

| Placement | Width | Best templates |
|---|---|---|
| `article_inline_1/2/3` | ~720px content column | `luxury_watch`, `luxury_watch_compact_full`, `luxury_watch_split`, `luxury_car`, `jet_card_compact` |
| `sidebar_left`, `sidebar_right` | 200px | Any `*_skyscraper` template |
| `homepage_top_desktop` | full × ~140px target | Any `*_banner` template |
| `homepage_top_mobile` | full × mobile | Any `*_banner` template (responsive) |
| `homepage_inline` | full × varies | Any inline template |

Multiple banners can target the same placement. The article and homepage templates pre-pick ONE at random per LiveView session via `random_or_nil/1` (frozen at mount, doesn't re-roll on PubSub re-renders). Sidebar slots render the FULL list of active banners stacked.

---

## Adding a new luxury template

Five-step playbook:

1. **Add to `@valid_templates`** in `lib/blockster_v2/ads/banner.ex`. The changeset's `validate_inclusion(:template, @valid_templates)` blocks unknown templates from being saved.

2. **Add a renderer clause** in `lib/blockster_v2_web/components/design_system.ex` matching on `template: "your_new_template"`. Pattern:
   ```elixir
   def ad_banner(%{banner: %{template: "your_new_template"}} = assigns) do
     assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))
     ~H"""
     ...
     """
   end
   ```
   For SOL pricing call `luxury_watch_price_sol(@p["price_usd"])` and `luxury_watch_format_usd(@p["price_usd"])` — they're shared helpers.

3. **Register in admin `@templates` list** in `lib/blockster_v2_web/live/banners_admin_live.ex` so it appears in the Template Style dropdown:
   ```elixir
   {"Your New Template (one-line description for admins)", "your_new_template"}
   ```

4. **Register `@template_params`** so the admin form shows the right fields:
   ```elixir
   "your_new_template" => ~w(brand_name image_url model_name price_usd cta_text bg_color accent_color)
   ```

5. **Optional: add `param_placeholder/1` clauses** for nicer admin form placeholders (`Buy SOL instantly` is the default — empty for unknown fields).

For enum-typed params (select dropdowns), add to `@enum_params`:
```elixir
@enum_params %{
  "your_enum_field" => %{
    default: "first_option",
    hint: "what this controls",
    options: [
      {"Display Label A", "value_a"},
      {"Display Label B", "value_b"}
    ]
  }
}
```

The admin form auto-renders these as `<select>` instead of text inputs.

---

## Common params (shared across most templates)

These params show up on most luxury templates. Defaults are baked into the renderer — set on the banner only if you want to override.

| Param | Type | Default | Used by |
|---|---|---|---|
| `brand_name` | string | nil → no brand strip | All — top brand line |
| `image_url` | URL | required | All — hero image |
| `image_bg_color` | hex | varies per template | All — fills the image container area; for watch templates set to white to match padded backgrounds |
| `bg_color` | hex | varies per family | All — gradient start (top/left of card) |
| `bg_color_end` | hex | varies per family | All — gradient end |
| `accent_color` | hex | varies per family | All — gold/red/lime — lines, headlines, CTA borders |
| `text_color` | hex | `#E8E4DD` | All — main copy color (off-white) |
| `price_usd` | number | nil → no price line | Watch / car / jet — converts to live SOL at render time |
| `cta_text` | string | varies per template | Templates with a CTA pill |
| `model_name` | string | — | Watch / car — the bold model headline |

**Family conventions** (defaults if you don't override):

| Family | bg_color | bg_color_end | accent_color |
|---|---|---|---|
| Watch (Gray & Sons) | `#0e0e0e` | `#1a1a1a` | `#C9A961` (champagne gold) |
| Car — Ferrari | `#0e0e0e` | `#1a1a1a` | `#FF2800` (Ferrari red) |
| Car — Lambo | `#0a0a0a` | `#1a1a1a` | `#A4DD00` (Verde Scandal lime) |
| Jet card | `#0a1838` | `#1a2c5e` | `#D4AF37` (champagne gold) |

When seeding new dealers/brands in the same family, copy the family palette and just swap the accent color to match the dealer's brand identity.
