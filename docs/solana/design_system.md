# Blockster Redesign · Design System Reference

> **Read this doc before producing any new mock or extracting any component.**
> It captures every design decision that's currently only encoded in the existing mock files. If a fresh session reads this + one or two example mocks, it should be able to produce a new mock that's stylistically indistinguishable from the others.

---

## How this doc came to exist

The Blockster redesign started as a sister-project widget integration and grew into a full design-language overhaul. By the time we'd mocked 8 pages, the language was stable but lived only inside the HTML files and inside the conversation. To prevent drift across context resets and to give Phase 2 (component extraction) a clean spec, we wrote this reference.

This doc is the **single source of truth** for design tokens, fonts, components, and conventions. The mock files are the visual reference; this doc is the spec.

For project history and sequencing, see `redesign_overview.md`.

---

## File inventory · what each existing mock contains

When you need an example of a particular pattern, look here first:

| Mock file | Best examples of |
|---|---|
| `realtime_widgets_mock.html` | Article page · drop caps · article body styles · sidebar widgets · all 4 ad banner styles · Why Earn BUX banner · floating BUX panel · suggested reading cards |
| `homepage_mock.html` | Magazine cover hero · AI × Crypto category row · trending mosaic · hub showcase grid · videos section · upcoming token sales promo strip · logged-in additions divider · anonymous welcome hero |
| `hubs_index_mock.html` | Browse hubs page · featured hub strip · sticky search + category chips · 4-col hub grid |
| `hub_show_mock.html` | Brand-color full-bleed banner · sticky tab nav · pinned post · hub-scoped mosaic · authors strip · about + stats two-column · hub-sponsored ad pattern · all 7 stacked tab states (News / Videos / Long reads / Shop / Events / Authors / About) |
| `profile_mock.html` | Identity hero · 3 stat cards · email verification banner · multiplier breakdown card · all 5 stacked tab states (Activity / Following / Refer / Rewards / Settings) |
| `member_public_mock.html` | Public `/member/:slug` view · identity hero with bio + social + Follow CTA · public stats row · sticky tab nav · "Published in" hub cards in sidebar |
| `play_mock.html` | Coin Flip game · 3 stacked states (Place bet / In progress / Result win+loss) · stylized H/T coin design · difficulty pill grid · provably-fair commitment box · live activity sidebar · recent games table |
| `pool_index_mock.html` | Two big vault feature cards (SOL + BUX) · how it works 3-step · cross-pool activity table |
| `pool_detail_mock.html` | Pool brand banner · sticky order form (deposit/withdraw tabs) · LP price chart with timeframe controls · 8-stat grid · pool activity table |
| `wallet_modal_mock.html` | Wallet connect modal · Phantom / Solflare / Backpack rows with brand badges · empty + connecting states stacked · shimmer progress strip |
| `shop_index_mock.html` | Shop main page · full-bleed hero banner · sidebar filter (Products / Communities / Brands) · equal-aspect 3-col product grid · USD prices with strikethrough + BUX-discounted price |
| `product_detail_mock.html` | Product page · gallery + thumbnails · BUX-redemption card (1 BUX = $0.01 off) · size pills + color swatches · spec table · related products |
| `cart_mock.html` | Cart page · per-item BUX redemption input · USD subtotal/discount/total summary · empty state stacked |
| `checkout_mock.html` | 4-step checkout · Shipping → Review → Payment → Confirmation · payment step has dual BUX-burn (Solana tx) + Helio USD widget |
| `airdrop_mock.html` | Single ongoing round · 1 BUX = 1 entry · 33 winners · prize structure grid · open + drawn celebration states stacked · provably-fair commitment + revealed seed verification |
| `token_sales_index_mock.html` | Token sales index · stat tiles · filter chips · featured sale magazine cover · 6-card grid covering live / upcoming / closed states with brand-color stripes |
| `token_sale_detail_mock.html` | Single sale page · **dark trading-terminal hero** with Bloomberg-style ticker strip + mono stats + frosted live-commitments widget · sticky light tab nav · **dark allocation card** styled as a trading panel (the right column is the second major dark surface in the system after the footer) |
| `category_mock.html` | Category browse (DeFi example) · editorial title hero · featured post · filter chips · mosaic grid · related categories · big featured author card |
| `tag_mock.html` | Tag browse (#solana example) · compact hero · 3-col post grid · related tags chip cloud (slimmer than category by design) |
| `events_index_mock.html` | Events index · stat tiles · filter chips for Free / Music / Online / IRL · featured event magazine cover · 9-card grid mixing free meetups + paid music events with **date-tile** component + free/paid badges · hosting communities strip |
| `event_detail_mock.html` | Event page · **poster layout** (no brand banner) · full-container 21:9 image hero with massive overhanging date tile · big editorial title block below · 3 stat cards (When/Where/Capacity) · vertical-timeline agenda · polaroid-style speakers/lineup · clean white sticky enrollment card · two stacked states: free meetup (RSVP) + paid music event (tier picker + BUX discount) |
| `event_checkout_mock.html` | Enrollment flow · two stacked flows · Flow A: free RSVP in 2 steps (attendee details → confirmation) · Flow B: paid ticket purchase in 4 steps (attendees → review → payment with BUX burn + Helio → confirmation) |

---

## Color tokens

```
PAGE
  --bg-page              #fafaf9     Eggshell off-white. The default body background.
  --bg-card              #ffffff     White card surface (used inside cards on the eggshell page).

TEXT
  --text-primary         #141414     Main headings and high-contrast text.
  --text-body            #343434     Article body text (slightly softer than primary).
  --text-muted           #6B7280     Captions, labels, secondary content.
  --text-faint           #9CA3AF     Eyebrows, muted hints, very-low-priority text.
  --text-extra-faint     #d4d4d2     Skeleton placeholders, placeholder input text.

BRAND
  --blockster-lime       #CAFC00     The brand color. Used for accents, BUX-related things, "earning" indicators.
                                     NOT used for: button backgrounds on light pages, text colors against light bg.

TRADING / SEMANTIC
  #22C55E   /  #4ade80    Win, positive, "live" indicator (deeper for outlines/text, brighter for inline).
  #15803d                 Dark green for win text on light tints.
  #EF4444   /  #f87171    Loss, negative, error.
  #7f1d1d                 Dark red for loss text on light tints.
  #facc15   /  #a16207    Amber/gold for warnings, multipliers, pending states.
  #fef9c3                 Soft yellow background for warning banners.

HUB BRAND COLORS (real seeded values from priv/repo/seeds_hubs.exs)
  Moonpay      #7D00FF → #4A00B8  (purple)
  Solana       #00FFA3 → #00DC82 → #064e3b  (Solana green → dark)
  Ethereum     #627EEA → #454A75
  Bitcoin      #F7931A → #B86811
  Polygon      #8247E5 → #5A2DAA
  Arbitrum     #28A0F0 → #0F4F7B
  Base         #0052FF → #002a82
  Binance      #F3BA2F → #B88712
  Phantom      #AB9FF2 → #534BB1
  Uniswap      #FF007A → #870042
  Aave         #B6509E → #2EBAC6
  Magic Eden   #E42575 → #7B0B33
  Helius       #06B6D4 → #0E7490
  Jito         #14F195 → #0B7548
  Pyth         #2A2D3A → #6B0DAD
  OpenSea      #2081E2 → #0E5BA6
  Coinbase     #0052FF → #001E5C
  Jupiter      #C7F284 → #4F7D2B

DARK SURFACES
  #0a0a0a                 Footer background, dark CTAs, "trading terminal" widgets.
  #1a1a22                 Hover state for #0a0a0a.
  #14141A                 Trading widget row background (slightly lighter than #0a0a0a).
  #E8E4DD                 Primary text inside dark surfaces.
```

### Color usage rules

- **Lime `#CAFC00`** is used for: BUX-related accents, the "Why Earn BUX?" header banner, primary CTAs *inside dark surfaces* (e.g. "Subscribe" in the footer, "Connect Wallet" in the welcome hero), small accent dots, and the active state on tabs/sparklines. **Never** use lime as a button background on a light page (looks washed). **Never** use lime as text color.
- **Trading semantic colors** (green/red/amber) are reserved for win/loss/warning states. Don't use them as decorative accents.
- **Hub brand colors** are used in full-bleed gradients on hub-specific surfaces (cards, banners) and as small color dots when identifying which hub a piece of content belongs to. Two-stop linear gradient `135deg`, primary → secondary.
- **Black `#0a0a0a`** is the dark CTA color. The footer is the only large dark surface on most pages. The trading widgets and the welcome hero are intentional exceptions.

---

## Typography

```
LOADED FROM GOOGLE FONTS:
  Inter           weights 400, 500, 600, 700, 800
  JetBrains Mono  weights 400, 500, 600, 700

CSS CLASSES:
  .font-haas       Inter 500   — body sans, default body font
  .font-haas-bold  Inter 700   — bold sans, headings, button labels
  .font-mono       JetBrains Mono with font-variant-numeric: tabular-nums
  .font-segoe      'Segoe UI', system-ui, -apple-system, 'Helvetica Neue'  — article body content (matches font-segoe_regular in production)

DEFAULT BODY:
  font-family: 'Inter', 'Helvetica Neue', Arial, sans-serif

DISPLAY HEADINGS:
  .article-title   font-weight: 700, letter-spacing: -0.022em, line-height: 1.04
  .section-title   font-weight: 700, letter-spacing: -0.018em
  .eyebrow         font-weight: 700, font-size: 10px, letter-spacing: 0.16em, uppercase, color: text-faint
```

### Typography rules

- **Display**: Use `.article-title` for the biggest headlines (h1, hero text). For h2 section headers use `.section-title`. Both use Inter 700 with negative letter-spacing.
- **Body**: Use `.font-haas` for paragraphs, descriptions, captions on non-article pages. Use `.font-segoe` only inside an `<article class="article-body">` block (article pages only).
- **Numerics**: ALL prices, balances, percentages, dates, IDs, addresses, BUX amounts, multipliers, and timestamps use `.font-mono`. The `tabular-nums` variant ensures vertical alignment.
- **Eyebrows**: Use `.eyebrow` above section headings and inside cards. They give the page rhythm and editorial weight.
- **Sentence case** for headlines (not Title Case). One exception: tab labels and short button labels can be Title Case.
- **No emojis** in production text. The play page used to use 🚀/💩 for coin faces — these were replaced with stylized `H` / `T` letters in gradient circles. Don't reintroduce emojis.

---

## CSS template · paste this into every new mock

This is the canonical `<style>` block. Every mock uses some subset of it. When you start a new mock, copy this entire block and trim anything you don't need:

```html
<style>
  :root {
    --bg-page: #fafaf9;
    --text-primary: #141414;
    --text-body: #343434;
    --text-muted: #6B7280;
    --text-faint: #9CA3AF;
    --blockster-lime: #CAFC00;
  }

  html, body {
    background: var(--bg-page);
    color: var(--text-primary);
    -webkit-font-smoothing: antialiased;
    text-rendering: optimizeLegibility;
  }

  .font-haas       { font-family: 'Inter', 'Helvetica Neue', Arial, sans-serif; font-weight: 500; }
  .font-haas-bold  { font-family: 'Inter', 'Helvetica Neue', Arial, sans-serif; font-weight: 700; }
  .font-segoe      { font-family: 'Segoe UI', system-ui, -apple-system, 'Helvetica Neue', sans-serif; }
  .font-mono       { font-family: 'JetBrains Mono', ui-monospace, 'SF Mono', Menlo, monospace; font-variant-numeric: tabular-nums; }
  body             { font-family: 'Inter', 'Helvetica Neue', Arial, sans-serif; }

  .article-title {
    font-family: 'Inter', 'Helvetica Neue', Arial, sans-serif;
    font-weight: 700;
    color: var(--text-primary);
    letter-spacing: -0.022em;
    line-height: 1.04;
  }

  .header-bg {
    background: rgba(255, 255, 255, 0.92);
    backdrop-filter: saturate(180%) blur(12px);
    -webkit-backdrop-filter: saturate(180%) blur(12px);
  }

  /* User initials avatars (small + large) */
  .author-avatar {
    background: linear-gradient(135deg, #1a1a22 0%, #2a2a35 100%);
    color: #E8E4DD;
    font-family: 'Inter', 'Helvetica Neue', Arial, sans-serif;
    font-weight: 700;
    letter-spacing: 0.02em;
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.08), 0 2px 8px rgba(0, 0, 0, 0.12);
  }
  .profile-avatar {
    background: linear-gradient(135deg, #1a1a22 0%, #2a2a35 50%, #0a0a0a 100%);
    color: #E8E4DD;
    font-family: 'Inter', sans-serif;
    font-weight: 800;
  }

  /* Generic post card with hover lift */
  .post-card {
    transition: transform 0.25s ease, box-shadow 0.25s ease, border-color 0.25s ease;
  }
  .post-card:hover {
    transform: translateY(-2px);
    box-shadow: 0 18px 30px -12px rgba(0, 0, 0, 0.12), 0 6px 12px -4px rgba(0, 0, 0, 0.06);
    border-color: rgba(0, 0, 0, 0.12);
  }

  /* Hub / vault card with brand-color gradient */
  .hub-card {
    transition: transform 0.25s ease, box-shadow 0.25s ease;
    position: relative;
    overflow: hidden;
  }
  .hub-card::after {
    content: '';
    position: absolute;
    inset: 0;
    background: radial-gradient(circle at 80% 20%, rgba(255, 255, 255, 0.18), transparent 60%);
    pointer-events: none;
  }
  .hub-card:hover {
    transform: translateY(-3px);
    box-shadow: 0 18px 40px -12px rgba(0, 0, 0, 0.35);
  }

  /* Pulsing live indicator */
  @keyframes pulse-dot {
    0%, 100% { opacity: 1; transform: scale(1); }
    50%      { opacity: 0.55; transform: scale(1.15); }
  }
  .pulse-dot { animation: pulse-dot 1.6s cubic-bezier(0.4, 0, 0.6, 1) infinite; }

  /* Section heading helpers */
  .section-title {
    font-family: 'Inter', 'Helvetica Neue', Arial, sans-serif;
    font-weight: 700;
    letter-spacing: -0.018em;
    color: var(--text-primary);
  }
  .eyebrow {
    font-family: 'Inter', 'Helvetica Neue', Arial, sans-serif;
    font-weight: 700;
    font-size: 10px;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    color: var(--text-faint);
  }

  /* Filter / category chip */
  .chip {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    padding: 6px 12px;
    border-radius: 999px;
    font-size: 12px;
    font-weight: 500;
    transition: background-color 0.15s ease, color 0.15s ease;
    cursor: pointer;
    white-space: nowrap;
  }
  .chip-default {
    background: white;
    border: 1px solid #e5e5e2;
    color: #6B7280;
  }
  .chip-default:hover {
    border-color: #141414;
    color: #141414;
  }
  .chip-active {
    background: #141414;
    color: white;
    border: 1px solid #141414;
  }

  /* Activity table row hover */
  .activity-row {
    transition: background-color 0.15s ease;
  }
  .activity-row:hover { background-color: rgba(0, 0, 0, 0.02); }

  /* State-stacked mock divider (for showing multiple states in one file) */
  .state-divider, .variant-divider {
    position: relative;
    margin: 100px 0 60px;
    text-align: center;
  }
  .state-divider::before, .variant-divider::before {
    content: '';
    position: absolute;
    inset: 50% 0 0 0;
    height: 1px;
    background: linear-gradient(90deg, transparent, #d4d4d2, transparent);
  }
  .state-divider span, .variant-divider span {
    position: relative;
    background: var(--bg-page);
    padding: 0 16px;
    font-family: 'JetBrains Mono', monospace;
    font-size: 11px;
    letter-spacing: 0.16em;
    text-transform: uppercase;
    color: #9CA3AF;
  }

  .line-clamp-2 { display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; }
  .line-clamp-3 { display: -webkit-box; -webkit-line-clamp: 3; -webkit-box-orient: vertical; overflow: hidden; }
</style>
```

---

## Mock document scaffold

Every mock starts the same way. Use this skeleton:

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Blockster · [Page Name] — Design Mock</title>
  <script src="https://cdn.tailwindcss.com"></script>
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&family=JetBrains+Mono:wght@400;500;600;700&display=swap" rel="stylesheet">
  [STYLE BLOCK FROM ABOVE]
</head>
<body class="relative">
  [HEADER]
  <main class="max-w-[1280px] mx-auto px-6">
    [PAGE HERO]
    [SECTIONS]
  </main>
  [FOOTER]
</body>
</html>
```

---

## Section pattern · Header (logged-in)

Sticky header at `top-0 z-20`, with a thin lime "Why Earn BUX?" banner stuck underneath. The avatar in the top-right is the user's initials block in a lime ring (matches `.profile-avatar`). The BUX balance pill shows the wallet's BUX balance.

```html
<header class="header-bg border-b border-neutral-200/70 sticky top-0 z-20">
  <div class="max-w-[1280px] mx-auto px-6 h-14 flex items-center justify-between">
    <div class="flex items-center gap-3">
      <a href="#" class="flex items-center">
        <img src="https://ik.imagekit.io/blockster/blockster-logo.png" alt="Blockster" class="h-[22px] w-auto" />
      </a>
      <div class="hidden md:flex items-center ml-2 gap-1.5 text-[11px] text-neutral-500 font-mono">
        <span class="w-1.5 h-1.5 rounded-full bg-[#22C55E]"></span>
        <span>Solana mainnet</span>
      </div>
    </div>
    <nav class="hidden md:flex items-center gap-7 text-[13px] text-neutral-700 font-haas">
      <a href="#" class="hover:text-neutral-900 transition-colors">Home</a>
      <a href="#" class="hover:text-neutral-900 transition-colors">Hubs</a>
      <a href="#" class="hover:text-neutral-900 transition-colors">Shop</a>
      <a href="#" class="hover:text-neutral-900 transition-colors">Play</a>
      <a href="#" class="hover:text-neutral-900 transition-colors">Pool</a>
      <a href="#" class="hover:text-neutral-900 transition-colors">Airdrop</a>
    </nav>
    <div class="flex items-center gap-3">
      <div class="hidden sm:flex items-center gap-1.5 px-2.5 py-1 bg-neutral-100 border border-neutral-200/60 rounded-full">
        <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="BUX" class="w-4 h-4 rounded-full object-cover" />
        <span class="text-[12px] font-haas-bold text-neutral-800">12,450</span>
        <span class="text-[10px] font-haas text-neutral-500">BUX</span>
      </div>
      <div class="w-8 h-8 rounded-full overflow-hidden ring-2 ring-[#CAFC00]">
        <div class="profile-avatar w-full h-full grid place-items-center text-[11px]">MV</div>
      </div>
    </div>
  </div>
  <div class="bg-[#CAFC00] border-t border-black/10">
    <div class="max-w-[1280px] mx-auto px-6">
      <div class="flex items-center justify-center gap-3 py-1.5 text-[13px] text-black font-haas">
        <span><strong class="font-haas-bold">Why Earn BUX?</strong> Redeem BUX to enter sponsored airdrops.</span>
      </div>
    </div>
  </div>
</header>
```

**Notes:**
- The active nav item gets a lime underline: `class="text-neutral-900 font-haas-bold border-b-2 border-[#CAFC00] -mb-[15px] pb-[15px]"`
- The "Solana mainnet" indicator is a tiny ambient signal — don't make it bigger
- The lime banner is **not** sticky on its own; it sticks because it's a child of the header
- The "Coming Soon" pill that used to be in the lime banner has been **removed** — don't add it back

---

## Section pattern · Header (anonymous / Connect Wallet variant)

Same header structure but the BUX pill + avatar are replaced with a black "Connect Wallet" button:

```html
<div class="flex items-center gap-2">
  <a href="#" class="hidden sm:inline-flex items-center gap-2 bg-[#0a0a0a] text-white px-3.5 py-2 rounded-full text-[12px] font-haas-bold hover:bg-[#1a1a1a] transition-colors">
    <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
      <rect x="2" y="6" width="20" height="14" rx="2"/>
      <path d="M22 10h-4a2 2 0 100 4h4"/>
    </svg>
    Connect Wallet
  </a>
</div>
```

The homepage anonymous lead uses this header. When the user is signed in, the BUX pill + avatar replaces it.

---

## Section pattern · Footer

The dark footer is shared across every page. It carries the mission line, social icons, link columns, and newsletter form. Copy this verbatim:

```html
<footer class="mt-20 bg-[#0a0a0a] text-white relative overflow-hidden">
  <div class="absolute top-0 right-0 w-[40%] h-full bg-gradient-to-l from-[#CAFC00]/[0.04] to-transparent pointer-events-none"></div>
  <div class="absolute top-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-white/10 to-transparent"></div>
  <div class="max-w-[1280px] mx-auto px-6 py-16 relative">
    <div class="grid grid-cols-12 gap-8">
      <div class="col-span-12 md:col-span-5">
        <div class="flex items-center gap-2.5 mb-5">
          <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="" class="w-9 h-9 rounded-md" />
          <img src="https://ik.imagekit.io/blockster/blockster-logo.png" alt="Blockster" class="h-6 w-auto invert" />
        </div>
        <h3 class="font-haas-bold text-[28px] leading-[1.1] text-white max-w-[360px] tracking-tight mb-4">Where the chain meets the model.</h3>
        <p class="text-white/55 text-[13px] leading-relaxed max-w-[360px] font-haas">Blockster is a decentralized publishing platform where readers earn BUX for engaging with the best writing in crypto and AI — and where every dollar of attention is settled on chain.</p>
      </div>
      <div class="col-span-6 md:col-span-2">
        <div class="text-[10px] uppercase tracking-[0.14em] text-white/40 font-haas-bold mb-4">Read</div>
        <ul class="space-y-2.5 text-[13px] font-haas">
          <li><a href="#" class="text-white/70 hover:text-white transition-colors">Hubs</a></li>
          <li><a href="#" class="text-white/70 hover:text-white transition-colors">Categories</a></li>
          <li><a href="#" class="text-white/70 hover:text-white transition-colors">Authors</a></li>
          <li><a href="#" class="text-white/70 hover:text-white transition-colors">Latest</a></li>
          <li><a href="#" class="text-white/70 hover:text-white transition-colors">Trending</a></li>
        </ul>
      </div>
      <div class="col-span-6 md:col-span-2">
        <div class="text-[10px] uppercase tracking-[0.14em] text-white/40 font-haas-bold mb-4">Earn</div>
        <ul class="space-y-2.5 text-[13px] font-haas">
          <li><a href="#" class="text-white/70 hover:text-white transition-colors">BUX Token</a></li>
          <li><a href="#" class="text-white/70 hover:text-white transition-colors">Pool</a></li>
          <li><a href="#" class="text-white/70 hover:text-white transition-colors">Play</a></li>
          <li><a href="#" class="text-white/70 hover:text-white transition-colors">Airdrops</a></li>
          <li><a href="#" class="text-white/70 hover:text-white transition-colors">Shop</a></li>
        </ul>
      </div>
      <div class="col-span-12 md:col-span-3">
        <div class="text-[10px] uppercase tracking-[0.14em] text-white/40 font-haas-bold mb-4">Stay in the loop</div>
        <p class="text-[13px] text-white/60 leading-relaxed mb-3 font-haas">The best of crypto × AI, every Friday. No spam, no shilling.</p>
        <form class="flex items-center gap-2">
          <input type="email" placeholder="you@somewhere.com" class="flex-1 min-w-0 bg-white/[0.06] border border-white/10 rounded-md px-3 py-2 text-[12px] text-white placeholder-white/30 focus:outline-none focus:border-[#CAFC00]/50 font-haas" />
          <button type="button" class="shrink-0 bg-[#CAFC00] text-black px-3.5 py-2 rounded-md text-[12px] font-haas-bold hover:bg-white transition-colors">Subscribe</button>
        </form>
        <div class="mt-4 flex items-center gap-1.5 text-[10px] text-white/40 font-mono">
          <span class="w-1.5 h-1.5 rounded-full bg-[#22C55E] pulse-dot"></span>
          <span>SOLANA · MAINNET LIVE</span>
        </div>
      </div>
    </div>
    <div class="mt-14 pt-6 border-t border-white/[0.08] flex items-center justify-between flex-wrap gap-4">
      <div class="text-[11px] text-white/40 font-haas">© 2026 Blockster Inc. · All rights reserved.</div>
      <div class="flex items-center gap-5 text-[11px] text-white/40 font-haas">
        <a href="#" class="hover:text-white transition-colors">Privacy</a>
        <a href="#" class="hover:text-white transition-colors">Terms</a>
        <a href="#" class="hover:text-white transition-colors">Cookie Policy</a>
        <a href="#" class="hover:text-white transition-colors">Press Kit</a>
        <a href="#" class="hover:text-white transition-colors">Status</a>
      </div>
    </div>
  </div>
</footer>
```

The mission line is **"Where the chain meets the model."** — do not change this.

---

## Section pattern · Page hero

A page hero is the top of the page below the header. There are three variants:

### Variant A · Editorial title hero (used on hubs index, profile, pool index, play, etc.)

Big article-title heading on the left + 3-stat band on the right.

```html
<section class="pt-12 pb-10">
  <div class="grid grid-cols-12 gap-8 items-end">
    <div class="col-span-12 md:col-span-7">
      <div class="eyebrow mb-3">[Tagline · short]</div>
      <h1 class="article-title text-[60px] md:text-[80px] mb-3 leading-[0.96]">Page Title</h1>
      <p class="text-[16px] leading-[1.5] text-neutral-600 max-w-[560px] font-haas">
        One-line description of what this page does and why someone would care.
      </p>
    </div>
    <div class="col-span-12 md:col-span-5">
      <div class="grid grid-cols-3 gap-3">
        <!-- 3 stat tiles -->
      </div>
    </div>
  </div>
</section>
```

Title sizes: `text-[60px] md:text-[80px]` for the very biggest pages, `text-[44px] md:text-[52px]` for smaller pages. Use 80px for index pages and 52px for detail pages.

### Variant B · Magazine-cover featured hero (used on homepage)

7-col image left, 5-col text right. Hub badge + huge title + kicker + author byline + lime BUX reward pill + dark "Read article" CTA.

See `homepage_mock.html` lines 230-289 for the canonical example.

### Variant C · Brand-color full-bleed banner (used on hub show + pool detail)

Full-bleed gradient using the hub or pool brand color. Identity block (logo + name) + description + stats row + CTAs + a frosted-glass card on the right (live activity widget for hub show, your-position card for pool detail).

See `hub_show_mock.html` lines 145-260 and `pool_detail_mock.html` lines 165-250 for the canonical examples.

### Variant D · Poster hero (used on event detail)

A full-width 21:9 image with a massive **date tile** overhanging the bottom-left corner, a small `live-pill` top-left, a `price-badge` and share button top-right, and a hub-credit pill bottom-right. The title block lives **below** the image — eyebrow + huge `article-title` + tagline + a CTA cluster on the right. Then a row of 3 stat cards (When / Where / Capacity).

```html
<section class="pb-24">
  <div class="aspect-[21/9] rounded-3xl overflow-hidden relative ring-1 ring-black/5 shadow-[0_30px_60px_-20px_rgba(0,0,0,0.25)]">
    <img src="..." alt="" class="w-full h-full object-cover" />
    <div class="absolute inset-0 bg-gradient-to-tr from-black/55 via-black/15 to-transparent"></div>
    <div class="absolute inset-0 bg-gradient-to-b from-transparent to-black/35"></div>

    <!-- Top-left: live indicator -->
    <div class="absolute top-6 left-6 md:top-8 md:left-8">
      <div class="live-pill">
        <span class="w-1.5 h-1.5 rounded-full bg-[#CAFC00] pulse-dot"></span>
        142 going · 58 spots left
      </div>
    </div>

    <!-- Top-right: price badge + share -->
    <div class="absolute top-6 right-6 md:top-8 md:right-8 flex items-center gap-2">
      <span class="price-badge free">Free meetup</span>
      <button class="w-9 h-9 rounded-full bg-black/60 backdrop-blur ring-1 ring-white/20 grid place-items-center"></button>
    </div>

    <!-- Bottom-right: hub credit pill -->
    <div class="absolute bottom-6 right-6">…hub badge…</div>

    <!-- The signature move: massive date tile overhanging the bottom-left -->
    <div class="absolute -bottom-12 left-8 md:left-16">
      <div class="date-tile-massive">
        <div class="month">APR</div>
        <div class="day">22</div>
        <div class="weekday">TUESDAY</div>
      </div>
    </div>
  </div>
</section>
```

**Rules:**
- Image aspect MUST be `21/9` — wider than the editorial article hero (16/11) so the date tile has room to breathe
- Date tile must overhang the bottom edge of the image (`-bottom-12`) — that's the signature move; without it the page looks like the hub show
- The title goes BELOW the image — never overlay it on top. The image is for atmosphere, the title is for reading
- Two soft gradient overlays (`from-black/55 via-black/15 to-transparent` + `from-transparent to-black/35`) so any image works
- The 3 stat cards row that follows the title block uses `WHEN / WHERE / CAPACITY` icons in `bg-neutral-100 rounded-xl` icon squares — different from the hub show's stats which sit inline on the dark banner

This pattern is **only** for event detail pages. Don't use it on hubs, pools, sales, or anything else.

See `event_detail_mock.html` for the canonical example.

### Variant E · Dark trading terminal (used on token sale detail)

The second major dark surface on a light page (after the footer). A `#0a0a0a` hero with a Bloomberg-style ticker strip running across the top, big project identity (mono ticker symbol + name), mono stat row, and a frosted live-commitments terminal on the right. Below the hero: light tab nav, light body content, and a **dark allocation card** in the right sticky column that doubles down on the trading-panel vibe.

Key elements:

```html
<!-- The dark hero shell -->
<section class="terminal-hero">
  <!-- Bloomberg ticker strip — top edge -->
  <div class="ticker-strip">
    <div class="max-w-[1280px] mx-auto px-6 py-2 flex items-center gap-4 font-mono text-[10px] uppercase tracking-[0.14em]">
      <span class="text-[#CAFC00] flex items-center gap-2">
        <span class="w-1.5 h-1.5 rounded-full bg-[#22C55E] pulse-dot"></span> Live now
      </span>
      <span class="ticker-divider"></span>
      <span class="text-white/55">$PHX</span>
      <span class="ticker-divider"></span>
      <span class="text-white/55">Closes <span class="text-white">04D 12H 38M</span></span>
      …
    </div>
  </div>
  …
</section>
```

```css
.terminal-hero {
  background: #0a0a0a;
  color: #E8E4DD;
  position: relative;
  overflow: hidden;
}
.terminal-hero::before {                    /* pixel grid texture */
  content: '';
  position: absolute;
  inset: 0;
  background-image: radial-gradient(circle at 30% 30%, rgba(255, 255, 255, 0.04) 1.5px, transparent 1.5px);
  background-size: 32px 32px;
}
.terminal-hero::after {                     /* brand-color glow */
  content: '';
  position: absolute;
  top: 0; right: 0;
  width: 60%; height: 100%;
  background: radial-gradient(ellipse at top right, rgba(255, 107, 53, 0.18), transparent 60%);
}

.ticker-strip {
  border-top: 1px solid rgba(255, 255, 255, 0.08);
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
  font-family: 'JetBrains Mono', monospace;
}
.ticker-divider { width: 1px; height: 12px; background: rgba(255, 255, 255, 0.15); }

.terminal-stat .label  { font-family: monospace; font-size: 9px; letter-spacing: 0.14em; text-transform: uppercase; color: rgba(255,255,255,0.45); }
.terminal-stat .value  { font-family: monospace; font-size: 26px; font-weight: 700; color: #fff; line-height: 1; }
.terminal-stat .sub    { font-family: monospace; font-size: 10px; color: rgba(255,255,255,0.45); }
```

**Rules:**
- Dark surface is `#0a0a0a` (same as the footer). Brand color is a **glow accent only** in the top-right of the hero — never a flat background fill, never a CTA fill on the dark surface
- All numbers in the hero are `JetBrains Mono` — this is the *one* page hero where mono dominates
- The ticker strip sits at the top edge with `border-y border-white/8` and uses the same `ticker-divider` between fields. It's the signature element that says "this is finance"
- The frosted commitments widget on the right uses `bg-white/[0.04] border border-white/10` — softer than the footer's `white/[0.06]` because it's against a textured ground
- After the hero ends, the body content goes back to light. Tabs are light. Body sections are light. The next dark surface is the right-column allocation card

**Allocation card** (the dark sticky widget on the right of the body):

```css
.alloc-terminal {
  background: #0a0a0a;
  color: #E8E4DD;
  border-radius: 18px;
  box-shadow: 0 30px 60px -20px rgba(0, 0, 0, 0.45), 0 10px 24px -8px rgba(0, 0, 0, 0.25);
}
.alloc-header {                  /* mono terminal title bar */
  padding: 14px 20px;
  border-bottom: 1px solid rgba(255, 255, 255, 0.08);
  font-family: 'JetBrains Mono', monospace;
  font-size: 10px;
  letter-spacing: 0.14em;
  text-transform: uppercase;
}
.alloc-input {
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.12);
  font-family: 'JetBrains Mono', monospace;
  font-size: 22px;
  font-weight: 700;
  color: #fff;
}
.alloc-quick {                   /* dark mono quick-step pills */
  background: rgba(255, 255, 255, 0.04);
  border: 1px solid rgba(255, 255, 255, 0.10);
  font-family: 'JetBrains Mono', monospace;
  color: rgba(255, 255, 255, 0.65);
}
.alloc-quick.active {
  background: var(--sale-primary);  /* brand color */
  color: white;
}
```

The submit button at the bottom of the allocation card is **lime on dark** (`bg-[#CAFC00] text-black`) — that's the one place lime works as a primary CTA fill, *because* it sits inside a dark surface and not on the page eggshell.

**This pattern is only for token sale detail pages.** Don't use it for hubs, events, pools, or anything else.

See `token_sale_detail_mock.html` for the canonical example.

### Picking the right hero variant

| Page type | Variant | Why |
|---|---|---|
| Index pages (shop, hubs, pool, play, events, sales, airdrop, profile, member, category, tag) | A · Editorial title hero | Pages that ARE a list need a calm, type-led hero so the content below dominates |
| Homepage main story | B · Magazine cover | Pulls a single article forward with a 7/5 image-text grid |
| Hub show, pool detail | C · Brand-color full-bleed banner | These pages ARE a brand — the brand color earns its full bleed |
| Event detail | D · Poster hero | An event is closer to a poster than a brand — image leads, type follows |
| Token sale detail | E · Dark trading terminal | A token sale is a financial product. Mono numbers, dark surfaces, ticker strip — earns the gravity of a trading venue |

**The rule:** if a new page type comes along, pick the variant that *means the right thing*. Don't reach for the brand banner just because it's the most dramatic. The brand banner means "this is a brand." The poster means "this is an event." The terminal means "this is a market."

---

## Section pattern · Sticky tab nav

Used on hub show, pool detail, and profile pages. Sits just below the brand banner and stays sticky as the user scrolls.

```html
<div class="hub-tabs border-y border-neutral-200/70" style="position: sticky; top: 84px; z-index: 15; background: rgba(250, 250, 249, 0.95); backdrop-filter: saturate(180%) blur(12px);">
  <div class="max-w-[1280px] mx-auto px-6 flex items-center gap-8 overflow-x-auto">
    <button class="tab-button active">All <span class="tab-count">142</span></button>
    <button class="tab-button">News <span class="tab-count">98</span></button>
    <button class="tab-button">Videos <span class="tab-count">26</span></button>
  </div>
</div>
```

`.tab-button` styles:

```css
.tab-button {
  position: relative;
  padding: 16px 4px;
  font-family: 'Inter', sans-serif;
  font-weight: 500;
  font-size: 14px;
  color: #6B7280;
  transition: color 0.15s ease;
  cursor: pointer;
  white-space: nowrap;
}
.tab-button:hover { color: #141414; }
.tab-button.active { color: #141414; font-weight: 700; }
.tab-button.active::after {
  content: '';
  position: absolute;
  bottom: 0;
  left: 0;
  right: 0;
  height: 2px;
  background: var(--blockster-lime);  /* or the page's brand color */
}
.tab-count {
  margin-left: 6px;
  font-family: 'JetBrains Mono', monospace;
  font-size: 11px;
  opacity: 0.5;
}
```

The active tab indicator is **lime** by default. On hub show pages, use the hub's brand color instead (`#7D00FF` for Moonpay, etc.).

---

## Component pattern · Stat card

The white stat card is the most-reused component. It's a small white card with eyebrow + colored icon square + big mono number + footer hint:

```html
<div class="bg-white rounded-2xl border border-neutral-200/70 p-6 shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
  <div class="flex items-start justify-between mb-4">
    <div class="eyebrow">BUX Balance</div>
    <div class="w-9 h-9 rounded-xl bg-[#CAFC00] grid place-items-center">
      <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="" class="w-5 h-5 rounded-full" />
    </div>
  </div>
  <div class="flex items-baseline gap-2 mb-1">
    <span class="font-mono font-bold text-[44px] text-[#141414] leading-none tracking-tight">12,450</span>
    <span class="text-[12px] font-haas text-neutral-500">BUX</span>
  </div>
  <div class="text-[11px] text-neutral-500 font-haas">≈ $124.50 redeemable</div>
  <div class="mt-4 pt-4 border-t border-neutral-100 flex items-center justify-between text-[10px] font-haas">
    <span class="text-neutral-500">Today</span>
    <span class="font-mono font-bold text-[#22C55E]">+ 245 BUX</span>
  </div>
</div>
```

**Pattern**: every stat card has:
1. Eyebrow + icon square row
2. Big mono number with small unit suffix
3. Sub-text caption (USD equivalent or context)
4. Optional bordered footer with a contextual hint pulling the user toward an action

---

## Component pattern · Post card (suggested reading / article card)

White card with image on top, content below, hover lift:

```html
<a href="#" class="post-card block bg-white rounded-2xl border border-neutral-200/70 overflow-hidden">
  <div class="aspect-[16/9] bg-neutral-100 overflow-hidden">
    <img src="https://picsum.photos/seed/blockster-1/640/360" alt="" class="w-full h-full object-cover" />
  </div>
  <div class="p-4">
    <div class="flex items-center gap-1.5 mb-2">
      <div class="w-4 h-4 rounded bg-[#7D00FF] grid place-items-center">
        <svg class="w-2.5 h-2.5 text-white" viewBox="0 0 24 24" fill="currentColor"><circle cx="12" cy="12" r="10" stroke="white" stroke-width="2" fill="none"/><circle cx="12" cy="12" r="5" fill="white"/></svg>
      </div>
      <span class="text-[9px] uppercase tracking-[0.12em] text-neutral-500 font-haas">Moonpay</span>
    </div>
    <h3 class="font-haas-bold text-[15px] text-[#141414] leading-[1.25] mb-3 line-clamp-3 tracking-tight">Article title in 2-3 lines max</h3>
    <div class="flex items-center justify-between text-[10px]">
      <div class="flex items-center gap-1.5 text-neutral-500 font-haas">
        <span>Author Name</span>
        <span class="text-neutral-300">·</span>
        <span>5 min</span>
      </div>
      <div class="flex items-center gap-1 bg-[#CAFC00] text-black px-1.5 py-0.5 rounded-full font-haas-bold">
        <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="" class="w-2.5 h-2.5 rounded-full" />
        +35
      </div>
    </div>
  </div>
</a>
```

**Variations:**
- Small card (used in 4-col grids): `text-[14px]` title, smaller padding
- Large card (editorial pick): `p-6`, `text-[24px]` article-title heading, larger image, longer description
- Horizontal compact card: `grid-cols-[120px_1fr]`, image on left, content on right (used in Recommended for you)

---

## Component pattern · Hub card (full-bleed brand color)

Used on the homepage hub showcase, the hubs index, and the profile Following tab.

```html
<a href="#" class="hub-card rounded-2xl p-5 text-white relative" style="background: linear-gradient(135deg, #7D00FF 0%, #4A00B8 100%); min-height: 240px;">
  <div class="relative z-10 h-full flex flex-col">
    <div class="flex items-center justify-between mb-8">
      <div class="w-9 h-9 rounded-md bg-white/15 backdrop-blur grid place-items-center ring-1 ring-white/20">
        <!-- hub icon SVG -->
      </div>
      <div class="text-[10px] uppercase tracking-[0.14em] bg-white/15 backdrop-blur px-2 py-0.5 rounded-full font-haas-bold">Sponsor</div>
    </div>
    <h3 class="font-haas-bold text-[20px] tracking-tight mb-1">Hub Name</h3>
    <p class="text-white/70 text-[11px] font-haas line-clamp-2 mb-4">One-line description.</p>
    <div class="flex items-center justify-between mt-auto">
      <div class="flex items-center gap-3">
        <div><span class="text-[14px] font-haas-bold">142</span> <span class="text-[10px] text-white/60">posts</span></div>
        <div><span class="text-[14px] font-haas-bold">8.2k</span> <span class="text-[10px] text-white/60">readers</span></div>
      </div>
      <button class="bg-white text-[#7D00FF] text-[10px] font-haas-bold px-2.5 py-1 rounded-full hover:bg-[#CAFC00] hover:text-black transition-colors">+ Follow</button>
    </div>
  </div>
</a>
```

**Rules:**
- Always use a `linear-gradient(135deg, primary, secondary)` from the hub's seeded brand colors
- The `::after` pseudo-element on `.hub-card` adds the radial highlight in the top-right
- Logo block: 36×36 frosted glass square (`bg-white/15 backdrop-blur ring-1 ring-white/20`) with the hub's icon or 3-letter ticker
- Follow button: white background with brand color text (or `bg-black/25 backdrop-blur ring-1 ring-white/20 text-white` for a more subtle treatment on bright hubs like Solana)
- Min height: 240px so all cards in a grid align
- For featured/sponsor hubs use min-height 320-420px with bigger padding (`p-8`) and larger inner type

---

## Component pattern · Activity table row

Used for: profile activity, recent games, pool activity, referral earnings, transaction history.

```html
<div class="bg-white rounded-2xl border border-neutral-200/70 shadow-[0_1px_3px_rgba(0,0,0,0.04)] overflow-hidden">
  <!-- Header strip -->
  <div class="grid grid-cols-[120px_1fr_140px] px-5 py-3 bg-neutral-50/70 border-b border-neutral-100 text-[10px] uppercase tracking-[0.14em] text-neutral-500 font-haas-bold">
    <div>Date</div>
    <div>Activity</div>
    <div class="text-right">Reward</div>
  </div>
  <!-- Rows -->
  <div class="divide-y divide-neutral-100">
    <div class="px-5 py-4 activity-row">
      <div class="grid grid-cols-[120px_1fr_140px] items-center gap-3">
        <div class="font-mono text-[11px] text-neutral-500">2 min ago</div>
        <div class="flex items-center gap-3">
          <div class="w-8 h-8 rounded-lg bg-[#CAFC00]/15 border border-[#CAFC00]/30 grid place-items-center shrink-0">
            <!-- icon -->
          </div>
          <div class="min-w-0">
            <div class="text-[13px] font-haas-bold text-[#141414] leading-tight truncate">Activity name</div>
            <div class="text-[10px] text-neutral-500 font-haas">Sub-detail</div>
          </div>
        </div>
        <div class="text-right">
          <div class="font-mono font-bold text-[14px] text-[#22C55E]">+ 45 BUX</div>
          <a href="#" class="text-[9px] font-mono text-neutral-400 hover:text-[#141414]">tx · 5gWp…</a>
        </div>
      </div>
    </div>
  </div>
</div>
```

**Conventions:**
- Header strip is `bg-neutral-50/70` with uppercase mono labels
- Each row has a colored icon square (32×32 `rounded-lg` with 12% bg + 30% border of the relevant color)
- Date column always uses mono font
- Reward column always right-aligned with mono numbers
- Solscan tx link is always small mono in `text-neutral-400 hover:text-[#141414]`
- Hover bg via `.activity-row` class

---

## Component pattern · Order form (deposit/withdraw)

Used on pool detail. Sticky on the left, white card with tab switcher.

```html
<div class="bg-white rounded-2xl border border-neutral-200/70 shadow-[0_1px_3px_rgba(0,0,0,0.04)] overflow-hidden">
  <!-- Tabs -->
  <div class="p-2">
    <div class="flex bg-neutral-100 rounded-full p-1 gap-1">
      <button class="form-tab active">Deposit</button>
      <button class="form-tab">Withdraw</button>
    </div>
  </div>
  <!-- Your wallet balances row -->
  <!-- Amount input with quick adjusts -->
  <!-- Output preview card (colored tint) -->
  <!-- Submit button -->
</div>
```

`.form-tab` styles:

```css
.form-tab {
  flex: 1;
  padding: 12px 0;
  font-family: 'Inter', sans-serif;
  font-weight: 600;
  font-size: 13px;
  color: #6B7280;
  transition: all 0.15s ease;
  cursor: pointer;
  text-align: center;
  border-radius: 999px;
}
.form-tab.active {
  background: white;
  color: #141414;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.06), 0 0 0 1px rgba(0, 0, 0, 0.04);
}
```

**Quick adjust pills** (½, 2×, MAX):

```css
.quick-bet {
  padding: 4px 10px;
  border-radius: 999px;
  background: #f3f4f6;
  border: 1px solid #e5e5e2;
  font-family: 'JetBrains Mono', monospace;
  font-size: 10px;
  font-weight: 600;
  color: #6B7280;
}
.quick-bet.max {
  background: #0a0a0a;
  color: #CAFC00;  /* or brand color, e.g. #064e3b text-white for SOL pool */
  border-color: #0a0a0a;
}
```

See `pool_detail_mock.html` for the canonical example.

---

## Component pattern · Mosaic grid (varied card sizes)

Used on the homepage trending section, hub show latest posts, anywhere we want a magazine-style mixed-size layout.

```css
.mosaic {
  display: grid;
  grid-template-columns: repeat(12, minmax(0, 1fr));
  grid-auto-rows: 180px;
  gap: 16px;
}
```

Cards declare their own `col-span-N` and `row-span-N`. Pattern:
- 1 big feature: `col-span-12 md:col-span-7 row-span-2`
- 2 medium horizontals: `col-span-12 md:col-span-5 row-span-1` each
- 4 small cards: `col-span-6 md:col-span-3 row-span-1` each

Big features use a full-bleed dark gradient image with overlay text. See `homepage_mock.html` Trending section.

---

## Component pattern · Sponsored label

Always above an ad banner. Tiny eyebrow:

```html
<div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-haas">Sponsored</div>
```

Used above all 4 ad banner styles (inline_dark, follow_strip, portrait_stonepeak, split_bottom) and above any "Sponsored by [hub]" content.

---

## Component pattern · Verification banner

Used on the profile page when the user has missing verification. Soft amber gradient with icon, label, big headline, and CTA. Motivational, not scolding.

```html
<div class="bg-gradient-to-r from-[#fef3c7] to-[#fef9c3] border border-[#facc15]/40 rounded-2xl p-5 flex items-center gap-4 flex-wrap">
  <div class="w-12 h-12 rounded-xl bg-white border border-[#facc15]/40 grid place-items-center shrink-0">
    <!-- icon -->
  </div>
  <div class="flex-1 min-w-0">
    <div class="flex items-center gap-2 mb-1">
      <span class="text-[10px] font-haas-bold uppercase tracking-[0.14em] text-[#a16207]">One thing left</span>
    </div>
    <h3 class="font-haas-bold text-[18px] text-[#141414] leading-tight">Headline · <span class="text-[#a16207]">benefit in amber</span></h3>
    <p class="text-[12px] text-neutral-600 font-haas mt-1">Sub-description.</p>
  </div>
  <button class="bg-[#0a0a0a] text-white px-5 py-2.5 rounded-full text-[12px] font-haas-bold hover:bg-[#1a1a22] transition-colors shrink-0">CTA →</button>
</div>
```

---

## Component pattern · Difficulty pill grid

Used on the play page. 9-column grid of stacked difficulty buttons.

```css
.difficulty-pill {
  padding: 10px 8px;
  border-radius: 12px;
  border: 1px solid #e5e5e2;
  background: white;
  font-family: 'JetBrains Mono', monospace;
  font-size: 11px;
  font-weight: 600;
  color: #6B7280;
}
.difficulty-pill.active {
  background: #0a0a0a;
  color: white;
  border-color: #0a0a0a;
}
```

Each button has 3 stacked text rows: small uppercase mode label, big multiplier, tiny flip count. See `play_mock.html`.

---

## Component pattern · Date tile (events)

The signature component for the events section. A floating white tile with a colored month label, big mono day number, and small uppercase weekday. Used in two sizes — small for cards, large for the event detail banner.

```css
/* Large variant — used on event detail brand banner */
.date-tile {
  background: white;
  border: 1px solid rgba(0, 0, 0, 0.08);
  border-radius: 18px;
  padding: 10px 18px 14px;
  box-shadow: 0 14px 30px -10px rgba(0, 0, 0, 0.25), 0 4px 8px -2px rgba(0, 0, 0, 0.1);
  text-align: center;
  min-width: 88px;
  font-family: 'Inter', sans-serif;
}
.date-tile .month {
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.16em;
  text-transform: uppercase;
  color: #C73E1D;        /* terracotta — the signature month color */
  line-height: 1;
  margin-bottom: 4px;
}
.date-tile .day {
  font-family: 'JetBrains Mono', monospace;
  font-size: 38px;
  font-weight: 700;
  color: #141414;
  line-height: 1.05;
}
.date-tile .weekday {
  font-size: 10px;
  font-weight: 500;
  color: #9CA3AF;
  letter-spacing: 0.1em;
  text-transform: uppercase;
  margin-top: 4px;
}
```

```html
<div class="date-tile">
  <div class="month">APR</div>
  <div class="day">22</div>
  <div class="weekday">TUE</div>
</div>
```

**Small variant** (`.date-tile-sm`, used in event cards and order summaries): 56px min-width, 22px day number, 12px border-radius, lighter shadow. Both variants use the same terracotta `#C73E1D` for the month label — that's the only place this color appears in the system.

**Placement**: top-left of an event card image (overlaying the photo with a soft drop shadow), or floating to the left of the event title in a brand-banner identity block. Never use on a non-event surface.

---

## Component pattern · Free / Paid event badge

A small mono pill that classifies an event at a glance. Three variants:

```css
.price-badge {
  display: inline-flex;
  align-items: center;
  gap: 4px;
  font-family: 'JetBrains Mono', monospace;
  font-size: 10px;
  font-weight: 700;
  letter-spacing: 0.06em;
  padding: 4px 9px;
  border-radius: 999px;
  text-transform: uppercase;
}
.price-badge.free   { background: #CAFC00; color: #141414; }
.price-badge.paid   { background: #141414; color: white; }
.price-badge.online { background: rgba(34, 197, 94, 0.12); color: #15803d; border: 1px solid rgba(34, 197, 94, 0.25); }
```

**Rules:**
- Lime + black for free (community / free meetup)
- Black for paid (music / culture / ticketed)
- Soft green for online (modifier — usually stacked under a free or paid badge)
- Always small. Place top-right of the event card image. Never bigger than the date tile.

The lime free badge is one of the **only** places lime works as a button-shaped background on a light page — and only because it's a small pill, not a large surface.

---

## Component pattern · Event card

Combines the date tile + price badge over a 16:10 image, then standard card body below. See `events_index_mock.html` for canonical examples.

```html
<a href="#" class="event-card block bg-white rounded-2xl border border-neutral-200/70 overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
  <div class="aspect-[16/10] bg-neutral-100 overflow-hidden relative">
    <img src="..." alt="" class="w-full h-full object-cover" />
    <div class="absolute top-3 left-3"><div class="date-tile">…</div></div>
    <div class="absolute top-3 right-3"><span class="price-badge free">Free</span></div>
  </div>
  <div class="p-5">
    <!-- hub badge row -->
    <!-- title (line-clamp-2) -->
    <!-- 2-line meta: time + location -->
    <!-- (optional) BUX discount strip if paid -->
    <!-- footer: avatar stack + going count -->
  </div>
</a>
```

**Conventions:**
- Image aspect: `16/10` (taller than the article post card's `16/9` — gives more room for the date tile)
- Date tile sits in `top-3 left-3` of the image; price badge in `top-3 right-3`. Online modifier stacks under the price badge if present.
- Hub badge row mirrors the post card (small color dot + hub name)
- Title `line-clamp-2`, body meta uses `font-haas` 11px in `text-neutral-500`
- Avatar stack at the bottom-left footer with `+N` overflow chip; going count in mono on the right
- Paid events get an extra `bg-[#CAFC00]/12 border border-[#CAFC00]/40 rounded-lg` strip above the footer mentioning the BUX discount cap

**Hover**: same lift as `.post-card` plus slightly heavier shadow. Brand color stripe at the top is optional — use it to differentiate sponsored events on a busy index.

---

## State-stacked mock pattern

When a page has multiple visual states (e.g. profile tabs, play game states, logged-out vs logged-in), stack them all in one mock file separated by `state-divider` / `variant-divider` blocks. This lets the user scroll through every state in one view.

```html
<!-- State 1 sections -->

<div class="state-divider"><span>State name · State 2 ↓</span></div>

<!-- State 2 sections -->

<div class="variant-divider"><span>When you're signed in ↓ · You also see these personalized sections</span></div>

<!-- Variant additions -->
```

The divider CSS is in the canonical style block. Always uses mono font and a subtle horizontal gradient line.

---

## Conventions · what to do

- **Icons**: use inline SVG (Heroicons-style — `viewBox="0 0 24 24"`, `stroke-width="2"`). Not Font Awesome, not Material.
- **Currency / numbers**: format with thousand separators. Use 4 decimal places for SOL prices, 2 for USD, integer for BUX.
- **Wallet addresses**: always truncate as `7xQk8…3mPa` (3-4 chars at start, ellipsis, 4-5 chars at end), in `font-mono`.
- **Solscan links**: small mono `text-neutral-400 hover:text-[#141414]` with a `↗` glyph.
- **Image placeholders**: use `picsum.photos/seed/blockster-something/640/360` with descriptive seeds. Sizes match the card aspect ratio.
- **Hero images**: Unsplash URLs work (e.g. `images.unsplash.com/photo-1620321023374-d1a68fbc720d?w=1400&q=85&auto=format&fit=crop`).
- **Hub icons**: use 3-letter tickers (SOL, ARB, BNB, POL, BASE) inside frosted-glass squares. For Moonpay use the inline SVG pattern: outer ring + inner filled circle.
- **Live indicators**: small `pulse-dot` next to a `LIVE` label in mono uppercase. Always green.
- **Section spacing**: `py-10` for medium sections, `py-12` for large sections, `pt-12 pb-10` for the page hero.
- **Card padding**: `p-5` for compact cards, `p-6` for medium cards, `p-7` for large cards, `p-8` for hero cards.
- **Card borders**: `border border-neutral-200/70`, `rounded-2xl`, `shadow-[0_1px_3px_rgba(0,0,0,0.04)]`.
- **Body width**: `max-w-[1280px] mx-auto px-6` for the main container.

---

## Conventions · what NOT to do

These were tried and rejected. Don't reintroduce them.

1. **Dark earning panels on light pages**. The first version of the floating BUX panel and the top-of-article earned pill were dark gradient cards. The user explicitly rejected them — switched to clean white cards with subtle borders. Same for the referral link card on the profile page (was dark, now white) and the lifetime BUX card on the rewards tab (was dark, now white). **The trading widgets and the welcome hero are the only large dark surfaces on light pages**.

2. **Pastel green `#8AE388` → `#6BCB69`**. Originally used for the BUX earning gradient. User called it "ugly". Replaced with the brand lime `#CAFC00` as the BUX accent.

3. **Emoji-based coin faces (🚀 / 💩)**. The production play page uses these. The mock replaces them with stylized `H` and `T` letters in gradient circles (gold for heads, silver for tails). Don't reintroduce emojis as core game UI.

4. **"Coming Soon" pill in the lime banner**. Removed at the user's request. The banner is just `Why Earn BUX? Redeem BUX to enter sponsored airdrops.` with no pill on the right.

5. **Lime as button background on light pages**. The Connect Wallet button in the welcome hero is lime *because* it sits on a dark gradient panel. Lime buttons on white look washed out. Use `bg-[#0a0a0a] text-white` for primary CTAs on light pages.

6. **Dark cards inside grids on light pages**. We tested this and it creates jarring visual noise. Cards inside light-page grids should be white/cream with subtle borders.

7. **Drop caps anywhere except inside the article body**. They belong only on `.article-body p::first-letter` inside the post show page. Don't add them to landing pages, hub pages, or other surfaces.

8. **Random green `text-green-600` / `emerald-500`**. Greens for "earning" or "money" should always be the brand lime `#CAFC00` (when on dark surfaces) or solid black with a lime accent dot (when on light surfaces). Use `#22C55E` only for trading-semantic win states.

9. **Bright lime as the active tab indicator on dark backgrounds**. The lime works *under* the active tab as a 2px underline. Don't fill the whole tab background with lime — that pushes lime into territory it doesn't work in (button background).

10. **Skipping the eyebrow above section titles**. Every section needs a small uppercase eyebrow. It's a core part of the editorial weight.

---

## Mock format checklist

When you start a new mock:

- [ ] Use the file name `[page]_mock.html` in `docs/solana/`
- [ ] Copy the canonical `<style>` block
- [ ] Set the `<title>` to `Blockster · [Page Name] — Design Mock`
- [ ] Header (logged-in or anonymous variant)
- [ ] Lime "Why Earn BUX?" banner under the header
- [ ] Page hero (Variant A / B / C as appropriate)
- [ ] Main content sections
- [ ] State dividers if showing multiple states
- [ ] Footer (verbatim from this doc)
- [ ] Open in a browser to verify

---

## Hub seed data · use real values

When you need example hubs in a mock, use real names from `priv/repo/seeds_hubs.exs`:

| Hub | Primary | Secondary | Description |
|---|---|---|---|
| Moonpay | `#7D00FF` | `#4A00B8` | The simplest way to buy and sell crypto |
| Solana | `#00FFA3` | `#00DC82` | High-performance blockchain |
| Ethereum | `#627EEA` | `#454A75` | Leading smart contract platform |
| Bitcoin | `#F7931A` | `#B86811` | The original cryptocurrency |
| Polygon | `#8247E5` | `#5A2DAA` | Ethereum scaling solution |
| Arbitrum | `#28A0F0` | `#0F4F7B` | Ethereum layer 2 scaling |
| Base | `#0052FF` | `#002a82` | Coinbase layer 2 network |
| Binance | `#F3BA2F` | `#B88712` | Leading cryptocurrency exchange |
| Phantom | `#AB9FF2` | `#534BB1` | The friendly crypto wallet |
| Uniswap | `#FF007A` | `#870042` | Decentralized exchange |
| Aave | `#B6509E` | `#2EBAC6` | Open-source liquidity protocol |
| Magic Eden | `#E42575` | `#7B0B33` | Cross-chain NFT marketplace |
| Helius | `#06B6D4` | `#0E7490` | Solana RPC infrastructure |
| Jito | `#14F195` | `#0B7548` | Liquid staking on Solana |
| Pyth | `#2A2D3A` | `#6B0DAD` | High-fidelity oracle network |
| OpenSea | `#2081E2` | `#0E5BA6` | Largest NFT marketplace |
| Coinbase | `#0052FF` | `#001E5C` | The on-ramp the world plugged into |
| Jupiter | `#C7F284` | `#4F7D2B` | Solana's swap aggregator |

Use 4-8 of these per page where hub examples are needed.

---

## Author / wallet examples

When you need fake user data in a mock, use these established names so the design feels continuous across pages:

- **Marcus Verren** (`@marcus`, MV initials) — the default "you". Editor at Large.
- **Sara K.** (SK) — Compliance Lead at Moonpay
- **Lena Park** (LP) — Product Reporter
- **Daniyar K.** (DK) — Markets writer
- **Jamie Chen** (JC) — Solana coverage
- **Iris Chen** (IC) — Ethereum coverage
- **Rachel Harlow** (RH) — Long-form / investigations

Wallet examples (truncated): `7xQk8…3mPa`, `9aBc…2vNm`, `3FpQ…8RtY`, `hQ4n…6mLk`, `5gWp…1nVx`, `2xMq…7vPk`, `8mLp…4vQa`.

---

## Recurring phrases / brand voice

These phrases appear across mocks and should be used verbatim where applicable:

- Mission line: **"Where the chain meets the model."**
- Footer description: *"Blockster is a decentralized publishing platform where readers earn BUX for engaging with the best writing in crypto and AI — and where every dollar of attention is settled on chain."*
- Welcome eyebrow: **"Welcome to Blockster"** in lime on dark
- Why Earn BUX: **"Why Earn BUX? Redeem BUX to enter sponsored airdrops."**
- Newsletter subhead: *"The best of crypto × AI, every Friday. No spam, no shilling."*
- Solana mainnet indicator: small green pulse + `Solana mainnet` in mono

---

*This doc is the spec. The mock files are the visual reference. Any change to the design language must be reflected here before being applied across pages.*
