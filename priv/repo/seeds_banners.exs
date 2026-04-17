# Single source of truth for ad + widget banners on Blockster V2.
#
# Replaces the legacy `seeds_ad_banners.exs`, `seeds_widget_banners.exs`,
# `seeds_luxury_ads.exs`, and `seeds_article_inline_force.exs` scripts.
#
# This script mirrors the full banner state to the DB:
#
#   1. Deactivates EVERY existing banner row first (blank slate).
#   2. Upserts every banner defined below by `name` — create if missing,
#      update every attribute, and set is_active according to the entry
#      (defaults to true; entries may set `is_active: false` to ship a
#      dormant creative that admins can toggle on via /admin/banners
#      without re-authoring).
#
# After running, any banner not listed here is left in the DB but INACTIVE.
# Admins can still edit or re-enable old rows through /admin/banners.
#
# Current inventory (as of 2026-04-17):
#   - 57 active banners across article_top, article_inline_{1,2,3},
#     homepage_inline, homepage_top_desktop, sidebar_{left,right}
#   - 5 dormant banners (Follow Moonpay in Hubs + 4 patriotic_portrait rows —
#     toggle on via /admin/banners when ready)
#
# Run locally:
#
#     mix run priv/repo/seeds_banners.exs
#
# Run on Fly.io after a deploy (referenced in docs/solana_mainnet_deployment.md):
#
#     flyctl ssh console --app blockster-v2 -C "/app/bin/blockster_v2 eval \
#       'Code.eval_file(Path.wildcard(\"/app/lib/blockster_v2-*/priv/repo/seeds_banners.exs\") |> hd())'"

alias BlocksterV2.{Ads, Ads.Banner, Repo}
import Ecto.Query

# ── Reusable param blocks (dedupe the big brand configs) ──────────────────

ferrari_params = %{
  "accent_color" => "#DC0000",
  "badge" => "Pre-owned · 948 mi",
  "bg_color" => "#0a0a0a",
  "bg_color_end" => "#1a1a1a",
  "brand_color" => "#DC0000",
  "brand_name" => "Ferrari of Miami",
  "cta_text" => "View this Ferrari",
  "image_url" =>
    "https://ik.imagekit.io/blockster/ads/ferrarimiami/1776225530-4b09dbcff153-ferrari-roma-spider-clean.jpg",
  "model_name" => "Ferrari Roma Spider",
  "price_usd" => 316_900,
  "trim" => "Convertible · Bianco Cervino over Cuoio",
  "year" => 2024
}

ferrari_link =
  "https://ferrariofmiami.com/inventory/ferrari-roma-spider-zff09rpa3r0310246/"

ferrari_image =
  "https://ik.imagekit.io/blockster/ads/ferrarimiami/1776225530-4b09dbcff153-ferrari-roma-spider-clean.jpg"

jet_params = %{
  "accent_color" => "#D4AF37",
  "aircraft_category" => "Embraer Phenom 300E · Light Jet",
  "badge" => "25-hour jet card",
  "bg_color" => "#0a1838",
  "bg_color_end" => "#1a2c5e",
  "brand_name" => "Flight Finder Exclusive",
  "cta_text" => "Buy Jet Card",
  "headline" => "Pre-paid light-jet hours, ready to fly.",
  "hours" => 25,
  "image_bg_color" => "#0a1838",
  "image_url" =>
    "https://ik.imagekit.io/blockster/ads/flightfinder/1776227229-18ee34b9735f-phenom-300e-tight.jpg",
  "price_subtitle" => "25-hour jet card · Light Jet tier",
  "price_usd" => 100_000,
  "text_color" => "#E8E4DD"
}

jet_link = "https://flightfinder-exclusive.com/jet-card/"

jet_image =
  "https://ik.imagekit.io/blockster/ads/flightfinder/1776227229-18ee34b9735f-phenom-300e-tight.jpg"

watch_base = %{
  "accent_color" => "#C9A961",
  "bg_color" => "#0e0e0e",
  "bg_color_end" => "#1a1a1a",
  "brand_name" => "Gray & Sons",
  "cta_text" => "Inspect the piece",
  "image_bg_color" => "#FFFFFF",
  "text_color" => "#E8E4DD"
}

submariner_params =
  Map.merge(watch_base, %{
    "image_url" =>
      "https://ik.imagekit.io/blockster/ads/grayandsons/1776222731-879ba0a4c7b8-submariner-snug.jpg",
    "model_name" => "Rolex Submariner",
    "price_usd" => 36_500,
    "reference" => "Reference 116618LN · 40mm 18k Gold"
  })

submariner_link =
  "https://www.grayandsons.com/w529963-rolex-submariner-40mm-116618ln/"

submariner_image =
  "https://ik.imagekit.io/blockster/ads/grayandsons/1776222731-879ba0a4c7b8-submariner-snug.jpg"

gmt_params =
  Map.merge(watch_base, %{
    "image_url" =>
      "https://ik.imagekit.io/blockster/ads/grayandsons/1776222731-552693c61f97-gmt-snug.jpg",
    "model_name" => "Rolex GMT-Master II",
    "price_usd" => 41_500,
    "reference" => "Reference 116718 · 40mm 18k Gold"
  })

gmt_link = "https://www.grayandsons.com/w529620-rolex-gmt-master-ii-40mm-116718/"

gmt_image =
  "https://ik.imagekit.io/blockster/ads/grayandsons/1776222731-552693c61f97-gmt-snug.jpg"

day_date_40_params =
  Map.merge(watch_base, %{
    "image_url" =>
      "https://ik.imagekit.io/blockster/ads/grayandsons/1776222731-1fba6cfc444c-daydate40-228238-snug.jpg",
    "model_name" => "Rolex Day-Date 40",
    "price_usd" => 45_500,
    "reference" => "Reference 228238 · 40mm 18k Gold"
  })

day_date_40_link =
  "https://www.grayandsons.com/w529840-rolex-day-date-40-40mm-228238/"

day_date_40_image =
  "https://ik.imagekit.io/blockster/ads/grayandsons/1776222731-1fba6cfc444c-daydate40-228238-snug.jpg"

# ── Banner list (mirrors current prod-ready state) ────────────────────────

banners = [
  # ── article_inline_1 ────────────────────────────────────────────────────
  %{
    name: "Ferrari of Miami · 2024 Roma Spider · luxury_car",
    placement: "article_inline_1",
    template: "luxury_car",
    link_url: ferrari_link,
    image_url: ferrari_image,
    params: ferrari_params,
    sort_order: 0
  },
  %{
    name: "Flight Finder Exclusive · 25hr Light Jet · jet_card",
    placement: "article_inline_1",
    template: "jet_card_compact",
    link_url: jet_link,
    image_url: jet_image,
    params: jet_params,
    sort_order: 0
  },
  %{
    name: "Coin Flip Landscape Demo — Inline 1",
    placement: "article_inline_1",
    widget_type: "cf_inline_landscape_demo",
    widget_config: %{},
    sort_order: 0
  },
  %{
    name: "AUTO · Coin Flip Portrait · article_inline_1",
    placement: "article_inline_1",
    widget_type: "cf_portrait_demo",
    widget_config: %{},
    sort_order: 0
  },
  %{
    name: "AUTO · Rolex Submariner · article_inline_1",
    placement: "article_inline_1",
    template: "luxury_watch_split",
    link_url: submariner_link,
    image_url: submariner_image,
    params: submariner_params,
    sort_order: 0
  },
  %{
    name: "AUTO · Rolex GMT-Master II · article_inline_1",
    placement: "article_inline_1",
    template: "luxury_watch_split",
    link_url: gmt_link,
    image_url: gmt_image,
    params: gmt_params,
    sort_order: 0
  },
  %{
    name: "AUTO · Rolex Day-Date 40 · article_inline_1",
    placement: "article_inline_1",
    template: "luxury_watch_split",
    link_url: day_date_40_link,
    image_url: day_date_40_image,
    params: day_date_40_params,
    sort_order: 0
  },
  %{
    name: "RogueTrader · Chart landscape · biggest gainer",
    placement: "article_inline_1",
    widget_type: "rt_chart_landscape",
    widget_config: %{"selection" => "biggest_gainer"},
    link_url: "https://roguetrader.io",
    sort_order: 10
  },
  %{
    name: "AUTO · RT Chart Portrait · article_inline_1",
    placement: "article_inline_1",
    widget_type: "rt_chart_portrait",
    widget_config: %{"selection" => "biggest_mover"},
    link_url: "https://roguetrader.io",
    sort_order: 10
  },

  # ── article_inline_2 ────────────────────────────────────────────────────
  %{
    name: "Coin Flip Portrait Demo — Inline 2",
    placement: "article_inline_2",
    widget_type: "cf_portrait_demo",
    widget_config: %{},
    sort_order: 0
  },
  %{
    name: "AUTO · Coin Flip Landscape · article_inline_2",
    placement: "article_inline_2",
    widget_type: "cf_inline_landscape_demo",
    widget_config: %{},
    sort_order: 0
  },
  %{
    name: "AUTO · Ferrari Roma Spider · article_inline_2",
    placement: "article_inline_2",
    template: "luxury_car",
    link_url: ferrari_link,
    image_url: ferrari_image,
    params: ferrari_params,
    sort_order: 0
  },
  %{
    name: "AUTO · Rolex Submariner · article_inline_2",
    placement: "article_inline_2",
    template: "luxury_watch_split",
    link_url: submariner_link,
    image_url: submariner_image,
    params: submariner_params,
    sort_order: 0
  },
  %{
    name: "AUTO · Jet Card · article_inline_2",
    placement: "article_inline_2",
    template: "jet_card_compact",
    link_url: jet_link,
    image_url: jet_image,
    params: jet_params,
    sort_order: 0
  },
  %{
    name: "AUTO · Rolex GMT-Master II · article_inline_2",
    placement: "article_inline_2",
    template: "luxury_watch_split",
    link_url: gmt_link,
    image_url: gmt_image,
    params: gmt_params,
    sort_order: 0
  },
  %{
    name: "AUTO · Rolex Day-Date 40 · article_inline_2",
    placement: "article_inline_2",
    template: "luxury_watch_split",
    link_url: day_date_40_link,
    image_url: day_date_40_image,
    params: day_date_40_params,
    sort_order: 0
  },
  %{
    name: "RogueTrader · Chart portrait · biggest mover",
    placement: "article_inline_2",
    widget_type: "rt_chart_portrait",
    widget_config: %{"selection" => "biggest_mover"},
    link_url: "https://roguetrader.io",
    sort_order: 10
  },
  %{
    name: "AUTO · RT Chart Landscape · article_inline_2",
    placement: "article_inline_2",
    widget_type: "rt_chart_landscape",
    widget_config: %{"selection" => "biggest_gainer"},
    link_url: "https://roguetrader.io",
    sort_order: 10
  },

  # ── article_inline_3 ────────────────────────────────────────────────────
  %{
    name: "Gray & Sons · Rolex Submariner · split",
    placement: "article_inline_3",
    template: "luxury_watch_split",
    link_url: submariner_link,
    image_url: submariner_image,
    params: submariner_params,
    sort_order: 0
  },
  %{
    name: "AUTO · Coin Flip Landscape · article_inline_3",
    placement: "article_inline_3",
    widget_type: "cf_inline_landscape_demo",
    widget_config: %{},
    sort_order: 0
  },
  %{
    name: "AUTO · Coin Flip Portrait · article_inline_3",
    placement: "article_inline_3",
    widget_type: "cf_portrait_demo",
    widget_config: %{},
    sort_order: 0
  },
  %{
    name: "AUTO · Ferrari Roma Spider · article_inline_3",
    placement: "article_inline_3",
    template: "luxury_car",
    link_url: ferrari_link,
    image_url: ferrari_image,
    params: ferrari_params,
    sort_order: 0
  },
  %{
    name: "AUTO · Jet Card · article_inline_3",
    placement: "article_inline_3",
    template: "jet_card_compact",
    link_url: jet_link,
    image_url: jet_image,
    params: jet_params,
    sort_order: 0
  },
  %{
    name: "AUTO · Rolex GMT-Master II · article_inline_3",
    placement: "article_inline_3",
    template: "luxury_watch_split",
    link_url: gmt_link,
    image_url: gmt_image,
    params: gmt_params,
    sort_order: 0
  },
  %{
    name: "AUTO · Rolex Day-Date 40 · article_inline_3",
    placement: "article_inline_3",
    template: "luxury_watch_split",
    link_url: day_date_40_link,
    image_url: day_date_40_image,
    params: day_date_40_params,
    sort_order: 0
  },
  %{
    name: "AUTO · RT Chart Landscape · article_inline_3",
    placement: "article_inline_3",
    widget_type: "rt_chart_landscape",
    widget_config: %{"selection" => "biggest_gainer"},
    link_url: "https://roguetrader.io",
    sort_order: 10
  },
  %{
    name: "AUTO · RT Chart Portrait · article_inline_3",
    placement: "article_inline_3",
    widget_type: "rt_chart_portrait",
    widget_config: %{"selection" => "biggest_mover"},
    link_url: "https://roguetrader.io",
    sort_order: 10
  },

  # ── homepage_inline ─────────────────────────────────────────────────────
  #
  # Homepage rotator picks ONE banner per class (car/jet/cf/rt/watch) at
  # mount via `BlocksterV2.Ads.pick_one_per_class/1`, then cycles the 5-banner
  # result via modulo so no class repeats within any 4-slot window.
  #
  # Add as many creatives per class as you want — only one from each class
  # is used per page view, but users see different Rolexes / Ferraris on
  # different visits.
  %{
    name: "Homepage · Ferrari Roma Spider",
    placement: "homepage_inline",
    template: "luxury_car",
    link_url: ferrari_link,
    image_url: ferrari_image,
    params: ferrari_params,
    sort_order: 10
  },
  %{
    name: "Homepage · Jet Card",
    placement: "homepage_inline",
    template: "jet_card_compact",
    link_url: jet_link,
    image_url: jet_image,
    params: jet_params,
    sort_order: 20
  },
  %{
    name: "Homepage · Rolex Submariner",
    placement: "homepage_inline",
    template: "luxury_watch_split",
    link_url: submariner_link,
    image_url: submariner_image,
    params: submariner_params,
    sort_order: 50
  },
  %{
    name: "Homepage · Rolex GMT-Master II",
    placement: "homepage_inline",
    template: "luxury_watch_split",
    link_url: gmt_link,
    image_url: gmt_image,
    params: gmt_params,
    sort_order: 50
  },
  %{
    name: "Homepage · Rolex Day-Date 40",
    placement: "homepage_inline",
    template: "luxury_watch_split",
    link_url: day_date_40_link,
    image_url: day_date_40_image,
    params: day_date_40_params,
    sort_order: 50
  },

  # ── homepage top (ticker strip) ─────────────────────────────────────────
  %{
    name: "RogueTrader · Ticker · homepage top desktop",
    placement: "homepage_top_desktop",
    widget_type: "rt_ticker",
    widget_config: %{},
    link_url: "https://roguetrader.io",
    sort_order: 50
  },

  # ── article top (ticker strip) ──────────────────────────────────────────
  %{
    name: "RogueTrader · Ticker · article top",
    placement: "article_top",
    widget_type: "rt_ticker",
    widget_config: %{},
    link_url: "https://roguetrader.io",
    sort_order: 50
  },

  # ── sidebars ────────────────────────────────────────────────────────────
  %{
    name: "Coin Flip Sidebar Demo — Left Sidebar",
    placement: "sidebar_left",
    widget_type: "cf_sidebar_demo",
    widget_config: %{},
    sort_order: 0
  },
  %{
    name: "RogueTrader · Sidebar tile · biggest gainer",
    placement: "sidebar_left",
    widget_type: "rt_sidebar_tile",
    widget_config: %{"selection" => "biggest_gainer"},
    link_url: "https://roguetrader.io",
    sort_order: 100
  },
  %{
    name: "RogueTrader · Top RogueBots (right sidebar)",
    placement: "sidebar_right",
    widget_type: "rt_skyscraper",
    widget_config: %{},
    link_url: "https://roguetrader.io",
    sort_order: 0
  },

  # ── FOX One streaming trial ─────────────────────────────────────────────
  #
  # 7-day free trial then $19.99/month (FOX News, FOX Sports, FIFA 2026,
  # MLB, local FOX station). Uses `streaming_trial` template. Active at all
  # 4 inline placements so it joins the class rotation.
  %{
    name: "FOX One · 7-Day Free Trial",
    placement: "article_inline_1",
    template: "streaming_trial",
    link_url: "https://www.fox.com/",
    image_url: "https://static.foxnews.com/foxnews.com/content/uploads/2023/05/The-Five.png",
    params: %{
      "brand_name" => "FOX ONE",
      "brand_tagline" => "Streaming",
      "brand_color" => "#003DA5",
      "brand_text_color" => "#ffffff",
      "bg_color" => "#0a0a0a",
      "bg_color_end" => "#1a1a1a",
      "text_color" => "#ffffff",
      "heading" => "America's most-watched news network. Now streaming.",
      "subheading" => "FOX News, FOX Sports, FIFA 2026, MLB, and originals. Watch anywhere.",
      "image_url" => "https://static.foxnews.com/foxnews.com/content/uploads/2023/05/The-Five.png",
      "trial_label" => "7 Days Free",
      "price_after" => "$19.99/mo",
      "cta_text" => "Start Free Trial",
      "watch_on" => "Phone · Tablet · Smart TV · Roku · Apple TV"
    },
    sort_order: 0
  },
  %{
    name: "FOX One · 7-Day Free Trial · article_inline_2",
    placement: "article_inline_2",
    template: "streaming_trial",
    link_url: "https://www.fox.com/",
    image_url: "https://static.foxnews.com/foxnews.com/content/uploads/2023/05/The-Five.png",
    params: %{
      "brand_name" => "FOX ONE",
      "brand_tagline" => "Streaming",
      "brand_color" => "#003DA5",
      "brand_text_color" => "#ffffff",
      "bg_color" => "#0a0a0a",
      "bg_color_end" => "#1a1a1a",
      "text_color" => "#ffffff",
      "heading" => "America's most-watched news network. Now streaming.",
      "subheading" => "FOX News, FOX Sports, FIFA 2026, MLB, and originals. Watch anywhere.",
      "image_url" => "https://static.foxnews.com/foxnews.com/content/uploads/2023/05/The-Five.png",
      "trial_label" => "7 Days Free",
      "price_after" => "$19.99/mo",
      "cta_text" => "Start Free Trial",
      "watch_on" => "Phone · Tablet · Smart TV · Roku · Apple TV"
    },
    sort_order: 0
  },
  %{
    name: "FOX One · 7-Day Free Trial · article_inline_3",
    placement: "article_inline_3",
    template: "streaming_trial",
    link_url: "https://www.fox.com/",
    image_url: "https://static.foxnews.com/foxnews.com/content/uploads/2023/05/The-Five.png",
    params: %{
      "brand_name" => "FOX ONE",
      "brand_tagline" => "Streaming",
      "brand_color" => "#003DA5",
      "brand_text_color" => "#ffffff",
      "bg_color" => "#0a0a0a",
      "bg_color_end" => "#1a1a1a",
      "text_color" => "#ffffff",
      "heading" => "America's most-watched news network. Now streaming.",
      "subheading" => "FOX News, FOX Sports, FIFA 2026, MLB, and originals. Watch anywhere.",
      "image_url" => "https://static.foxnews.com/foxnews.com/content/uploads/2023/05/The-Five.png",
      "trial_label" => "7 Days Free",
      "price_after" => "$19.99/mo",
      "cta_text" => "Start Free Trial",
      "watch_on" => "Phone · Tablet · Smart TV · Roku · Apple TV"
    },
    sort_order: 0
  },
  %{
    name: "FOX One · 7-Day Free Trial · homepage_inline",
    placement: "homepage_inline",
    template: "streaming_trial",
    link_url: "https://www.fox.com/",
    image_url: "https://static.foxnews.com/foxnews.com/content/uploads/2023/05/The-Five.png",
    params: %{
      "brand_name" => "FOX ONE",
      "brand_tagline" => "Streaming",
      "brand_color" => "#003DA5",
      "brand_text_color" => "#ffffff",
      "bg_color" => "#0a0a0a",
      "bg_color_end" => "#1a1a1a",
      "text_color" => "#ffffff",
      "heading" => "America's most-watched news network. Now streaming.",
      "subheading" => "FOX News, FOX Sports, FIFA 2026, MLB, and originals. Watch anywhere.",
      "image_url" => "https://static.foxnews.com/foxnews.com/content/uploads/2023/05/The-Five.png",
      "trial_label" => "7 Days Free",
      "price_after" => "$19.99/mo",
      "cta_text" => "Start Free Trial",
      "watch_on" => "Phone · Tablet · Smart TV · Roku · Apple TV"
    },
    sort_order: 80
  },

  # ── America 250 · Trump tribute (patriotic_portrait) ────────────────────
  #
  # Centered editorial portrait with red/white/blue flag stripe across the
  # top of the image. Active at all 4 inline placements. Links to Trump's
  # official site.
  %{
    name: "America 250 · Trump tribute · article_inline_1",
    placement: "article_inline_1",
    template: "patriotic_portrait",
    link_url: "https://www.donaldjtrump.com/",
    image_url: "https://upload.wikimedia.org/wikipedia/commons/thumb/1/16/Official_Presidential_Portrait_of_President_Donald_J._Trump_%282025%29.jpg/960px-Official_Presidential_Portrait_of_President_Donald_J._Trump_%282025%29.jpg",
    params: %{
      "brand_name" => "America 250",
      "image_url" => "https://upload.wikimedia.org/wikipedia/commons/thumb/1/16/Official_Presidential_Portrait_of_President_Donald_J._Trump_%282025%29.jpg/960px-Official_Presidential_Portrait_of_President_Donald_J._Trump_%282025%29.jpg",
      "image_bg_color" => "#FFFFFF",
      "model_name" => "Donald J. Trump",
      "reference" => "45th & 47th President of the United States",
      "heading" => "The greatest president in American history.",
      "subheading" => "Celebrating 250 years of American excellence",
      "cta_text" => "Honor the legacy",
      "bg_color" => "#0a0a0a",
      "bg_color_end" => "#1a1a1a",
      "accent_color" => "#C9A961",
      "text_color" => "#E8E4DD"
    },
    sort_order: 5,
    is_active: false
  },
  %{
    name: "America 250 · Trump tribute · article_inline_2",
    placement: "article_inline_2",
    template: "patriotic_portrait",
    link_url: "https://www.donaldjtrump.com/",
    image_url: "https://upload.wikimedia.org/wikipedia/commons/thumb/1/16/Official_Presidential_Portrait_of_President_Donald_J._Trump_%282025%29.jpg/960px-Official_Presidential_Portrait_of_President_Donald_J._Trump_%282025%29.jpg",
    params: %{
      "brand_name" => "America 250",
      "image_url" => "https://upload.wikimedia.org/wikipedia/commons/thumb/1/16/Official_Presidential_Portrait_of_President_Donald_J._Trump_%282025%29.jpg/960px-Official_Presidential_Portrait_of_President_Donald_J._Trump_%282025%29.jpg",
      "image_bg_color" => "#FFFFFF",
      "model_name" => "Donald J. Trump",
      "reference" => "45th & 47th President of the United States",
      "heading" => "The greatest president in American history.",
      "subheading" => "Celebrating 250 years of American excellence",
      "cta_text" => "Honor the legacy",
      "bg_color" => "#0a0a0a",
      "bg_color_end" => "#1a1a1a",
      "accent_color" => "#C9A961",
      "text_color" => "#E8E4DD"
    },
    sort_order: 5,
    is_active: false
  },
  %{
    name: "America 250 · Trump tribute · article_inline_3",
    placement: "article_inline_3",
    template: "patriotic_portrait",
    link_url: "https://www.donaldjtrump.com/",
    image_url: "https://upload.wikimedia.org/wikipedia/commons/thumb/1/16/Official_Presidential_Portrait_of_President_Donald_J._Trump_%282025%29.jpg/960px-Official_Presidential_Portrait_of_President_Donald_J._Trump_%282025%29.jpg",
    params: %{
      "brand_name" => "America 250",
      "image_url" => "https://upload.wikimedia.org/wikipedia/commons/thumb/1/16/Official_Presidential_Portrait_of_President_Donald_J._Trump_%282025%29.jpg/960px-Official_Presidential_Portrait_of_President_Donald_J._Trump_%282025%29.jpg",
      "image_bg_color" => "#FFFFFF",
      "model_name" => "Donald J. Trump",
      "reference" => "45th & 47th President of the United States",
      "heading" => "The greatest president in American history.",
      "subheading" => "Celebrating 250 years of American excellence",
      "cta_text" => "Honor the legacy",
      "bg_color" => "#0a0a0a",
      "bg_color_end" => "#1a1a1a",
      "accent_color" => "#C9A961",
      "text_color" => "#E8E4DD"
    },
    sort_order: 5,
    is_active: false
  },
  %{
    name: "America 250 · Trump tribute · homepage_inline",
    placement: "homepage_inline",
    template: "patriotic_portrait",
    link_url: "https://www.donaldjtrump.com/",
    image_url: "https://upload.wikimedia.org/wikipedia/commons/thumb/1/16/Official_Presidential_Portrait_of_President_Donald_J._Trump_%282025%29.jpg/960px-Official_Presidential_Portrait_of_President_Donald_J._Trump_%282025%29.jpg",
    params: %{
      "brand_name" => "America 250",
      "image_url" => "https://upload.wikimedia.org/wikipedia/commons/thumb/1/16/Official_Presidential_Portrait_of_President_Donald_J._Trump_%282025%29.jpg/960px-Official_Presidential_Portrait_of_President_Donald_J._Trump_%282025%29.jpg",
      "image_bg_color" => "#FFFFFF",
      "model_name" => "Donald J. Trump",
      "reference" => "45th & 47th President of the United States",
      "heading" => "The greatest president in American history.",
      "subheading" => "Celebrating 250 years of American excellence",
      "cta_text" => "Honor the legacy",
      "bg_color" => "#0a0a0a",
      "bg_color_end" => "#1a1a1a",
      "accent_color" => "#C9A961",
      "text_color" => "#E8E4DD"
    },
    sort_order: 90,
    is_active: false
  },

  # ── Thank You 47 · animated loop ─────────────────────────────────────────
  #
  # Square 1:1 · 11s CSS loop:
  #   writes headline → fades to hero image → fades to "THANK YOU / 47"
  # Active at all 4 inline placements. Links to Trump's official site.
  %{
    name: "Thank You 47 · patriotic_loop · article_inline_1",
    placement: "article_inline_1",
    template: "patriotic_loop",
    link_url: "https://www.donaldjtrump.com/",
    image_url: "https://upload.wikimedia.org/wikipedia/en/8/88/Shooting_of_Donald_Trump.webp",
    params: %{
      "brand_name" => "America 250",
      "image_url" => "https://upload.wikimedia.org/wikipedia/en/8/88/Shooting_of_Donald_Trump.webp",
      "headline" => "The greatest president in American history.",
      "thank_top" => "THANK YOU",
      "number_text" => "47",
      "number_color" => "#BF0A30",
      "cta_text" => "Honor the legacy",
      "cta_meta" => "1776 — 2026",
      "accent_color" => "#BF0A30"
    },
    sort_order: 6
  },
  %{
    name: "Thank You 47 · patriotic_loop · article_inline_2",
    placement: "article_inline_2",
    template: "patriotic_loop",
    link_url: "https://www.donaldjtrump.com/",
    image_url: "https://upload.wikimedia.org/wikipedia/en/8/88/Shooting_of_Donald_Trump.webp",
    params: %{
      "brand_name" => "America 250",
      "image_url" => "https://upload.wikimedia.org/wikipedia/en/8/88/Shooting_of_Donald_Trump.webp",
      "headline" => "The greatest president in American history.",
      "thank_top" => "THANK YOU",
      "number_text" => "47",
      "number_color" => "#BF0A30",
      "cta_text" => "Honor the legacy",
      "cta_meta" => "1776 — 2026",
      "accent_color" => "#BF0A30"
    },
    sort_order: 6
  },
  %{
    name: "Thank You 47 · patriotic_loop · article_inline_3",
    placement: "article_inline_3",
    template: "patriotic_loop",
    link_url: "https://www.donaldjtrump.com/",
    image_url: "https://upload.wikimedia.org/wikipedia/en/8/88/Shooting_of_Donald_Trump.webp",
    params: %{
      "brand_name" => "America 250",
      "image_url" => "https://upload.wikimedia.org/wikipedia/en/8/88/Shooting_of_Donald_Trump.webp",
      "headline" => "The greatest president in American history.",
      "thank_top" => "THANK YOU",
      "number_text" => "47",
      "number_color" => "#BF0A30",
      "cta_text" => "Honor the legacy",
      "cta_meta" => "1776 — 2026",
      "accent_color" => "#BF0A30"
    },
    sort_order: 6
  },
  %{
    name: "Thank You 47 · patriotic_loop · homepage_inline",
    placement: "homepage_inline",
    template: "patriotic_loop",
    link_url: "https://www.donaldjtrump.com/",
    image_url: "https://upload.wikimedia.org/wikipedia/en/8/88/Shooting_of_Donald_Trump.webp",
    params: %{
      "brand_name" => "America 250",
      "image_url" => "https://upload.wikimedia.org/wikipedia/en/8/88/Shooting_of_Donald_Trump.webp",
      "headline" => "The greatest president in American history.",
      "thank_top" => "THANK YOU",
      "number_text" => "47",
      "number_color" => "#BF0A30",
      "cta_text" => "Honor the legacy",
      "cta_meta" => "1776 — 2026",
      "accent_color" => "#BF0A30"
    },
    sort_order: 95
  },

  # ── Trump 2028 · animated loop ──────────────────────────────────────────
  #
  # Square 1:1 · 10s CSS loop:
  #   "America needs him, again." → hero image → "TRUMP / 2028 / Finish what
  #   you started" on black. Active at all 4 inline placements.
  %{
    name: "Trump 2028 · trump_2028_loop · article_inline_1",
    placement: "article_inline_1",
    template: "trump_2028_loop",
    link_url: "https://www.donaldjtrump.com/",
    image_url: "https://upload.wikimedia.org/wikipedia/en/8/88/Shooting_of_Donald_Trump.webp",
    params: %{
      "brand_name" => "Trump · Vance 2028",
      "image_url" => "https://upload.wikimedia.org/wikipedia/en/8/88/Shooting_of_Donald_Trump.webp",
      "headline" => "America needs him, again.",
      "top_text" => "TRUMP",
      "number_text" => "2028",
      "number_color" => "#BF0A30",
      "subtitle" => "Finish what you started",
      "cta_text" => "Join",
      "accent_color" => "#BF0A30"
    },
    sort_order: 7
  },
  %{
    name: "Trump 2028 · trump_2028_loop · article_inline_2",
    placement: "article_inline_2",
    template: "trump_2028_loop",
    link_url: "https://www.donaldjtrump.com/",
    image_url: "https://upload.wikimedia.org/wikipedia/en/8/88/Shooting_of_Donald_Trump.webp",
    params: %{
      "brand_name" => "Trump · Vance 2028",
      "image_url" => "https://upload.wikimedia.org/wikipedia/en/8/88/Shooting_of_Donald_Trump.webp",
      "headline" => "America needs him, again.",
      "top_text" => "TRUMP",
      "number_text" => "2028",
      "number_color" => "#BF0A30",
      "subtitle" => "Finish what you started",
      "cta_text" => "Join",
      "accent_color" => "#BF0A30"
    },
    sort_order: 7
  },
  %{
    name: "Trump 2028 · trump_2028_loop · article_inline_3",
    placement: "article_inline_3",
    template: "trump_2028_loop",
    link_url: "https://www.donaldjtrump.com/",
    image_url: "https://upload.wikimedia.org/wikipedia/en/8/88/Shooting_of_Donald_Trump.webp",
    params: %{
      "brand_name" => "Trump · Vance 2028",
      "image_url" => "https://upload.wikimedia.org/wikipedia/en/8/88/Shooting_of_Donald_Trump.webp",
      "headline" => "America needs him, again.",
      "top_text" => "TRUMP",
      "number_text" => "2028",
      "number_color" => "#BF0A30",
      "subtitle" => "Finish what you started",
      "cta_text" => "Join",
      "accent_color" => "#BF0A30"
    },
    sort_order: 7
  },
  %{
    name: "Trump 2028 · trump_2028_loop · homepage_inline",
    placement: "homepage_inline",
    template: "trump_2028_loop",
    link_url: "https://www.donaldjtrump.com/",
    image_url: "https://upload.wikimedia.org/wikipedia/en/8/88/Shooting_of_Donald_Trump.webp",
    params: %{
      "brand_name" => "Trump · Vance 2028",
      "image_url" => "https://upload.wikimedia.org/wikipedia/en/8/88/Shooting_of_Donald_Trump.webp",
      "headline" => "America needs him, again.",
      "top_text" => "TRUMP",
      "number_text" => "2028",
      "number_color" => "#BF0A30",
      "subtitle" => "Finish what you started",
      "cta_text" => "Join",
      "accent_color" => "#BF0A30"
    },
    sort_order: 100
  },

  # ── Dormant creatives (created but inactive) ────────────────────────────
  #
  # Shipped so admins can toggle them on via /admin/banners without
  # re-authoring the params, but they never render by default.
  %{
    name: "Follow Moonpay in Hubs",
    placement: "article_inline_1",
    template: "follow_bar",
    link_url: "/hub/moonpay",
    image_url: "https://ik.imagekit.io/blockster/uploads/1776110628-489a1c36bb39432a.jpg",
    params: %{
      "brand_color" => "#7D00FF",
      "brand_name" => "Moonpay",
      "heading" => "Follow Moonpay in Hubs"
    },
    sort_order: 0,
    is_active: false
  },
  %{
    name: "Moonpay SOL On-Ramp",
    placement: "article_inline_1",
    template: "dark_gradient",
    link_url: "https://www.moonpay.com/buy/sol",
    image_url: "https://ik.imagekit.io/blockster/uploads/1776110628-489a1c36bb39432a.jpg",
    params: %{
      "brand_color" => "#7D00FF",
      "brand_name" => "Moonpay",
      "cta_text" => "Get Started",
      "description" => "Trusted by 30 million users. Powering the on-ramp for the largest Solana wallets and dApps in the ecosystem.",
      "heading" => "Buy SOL with a card in 30 seconds. No KYC for orders under $150.",
      "icon_url" => "https://ik.imagekit.io/blockster/uploads/1776110628-489a1c36bb39432a.jpg"
    },
    sort_order: 0
  },
  %{
    name: "Moonpay SOL On-Ramp · article_inline_2",
    placement: "article_inline_2",
    template: "dark_gradient",
    link_url: "https://www.moonpay.com/buy/sol",
    image_url: "https://ik.imagekit.io/blockster/uploads/1776110628-489a1c36bb39432a.jpg",
    params: %{
      "brand_color" => "#7D00FF",
      "brand_name" => "Moonpay",
      "cta_text" => "Get Started",
      "description" => "Trusted by 30 million users. Powering the on-ramp for the largest Solana wallets and dApps in the ecosystem.",
      "heading" => "Buy SOL with a card in 30 seconds. No KYC for orders under $150.",
      "icon_url" => "https://ik.imagekit.io/blockster/uploads/1776110628-489a1c36bb39432a.jpg"
    },
    sort_order: 0
  },
  %{
    name: "Moonpay SOL On-Ramp · article_inline_3",
    placement: "article_inline_3",
    template: "dark_gradient",
    link_url: "https://www.moonpay.com/buy/sol",
    image_url: "https://ik.imagekit.io/blockster/uploads/1776110628-489a1c36bb39432a.jpg",
    params: %{
      "brand_color" => "#7D00FF",
      "brand_name" => "Moonpay",
      "cta_text" => "Get Started",
      "description" => "Trusted by 30 million users. Powering the on-ramp for the largest Solana wallets and dApps in the ecosystem.",
      "heading" => "Buy SOL with a card in 30 seconds. No KYC for orders under $150.",
      "icon_url" => "https://ik.imagekit.io/blockster/uploads/1776110628-489a1c36bb39432a.jpg"
    },
    sort_order: 0
  },
  %{
    name: "Moonpay SOL On-Ramp · homepage_inline",
    placement: "homepage_inline",
    template: "dark_gradient",
    link_url: "https://www.moonpay.com/buy/sol",
    image_url: "https://ik.imagekit.io/blockster/uploads/1776110628-489a1c36bb39432a.jpg",
    params: %{
      "brand_color" => "#7D00FF",
      "brand_name" => "Moonpay",
      "cta_text" => "Get Started",
      "description" => "Trusted by 30 million users. Powering the on-ramp for the largest Solana wallets and dApps in the ecosystem.",
      "heading" => "Buy SOL with a card in 30 seconds. No KYC for orders under $150.",
      "icon_url" => "https://ik.imagekit.io/blockster/uploads/1776110628-489a1c36bb39432a.jpg"
    },
    sort_order: 60
  },
  %{
    name: "Moonpay Bottom CTA",
    placement: "article_inline_3",
    template: "split_card",
    link_url: "https://www.moonpay.com",
    image_url: "https://ik.imagekit.io/blockster/uploads/1776110628-489a1c36bb39432a.jpg",
    params: %{
      "brand_color" => "#7D00FF",
      "brand_name" => "Moonpay",
      "cta_text" => "Open Moonpay",
      "description" => "From card to wallet in under a minute. Available in 160 countries with the lowest fees in the industry.",
      "heading" => "Skip the exchange. Fund your wallet directly.",
      "panel_color" => "#7D00FF",
      "panel_color_end" => "#4A00B8",
      "stat_label_bottom" => "Card min",
      "stat_label_top" => "From",
      "stat_value" => "$3.99"
    },
    sort_order: 0
  },
  %{
    name: "Moonpay Bottom CTA · article_inline_1",
    placement: "article_inline_1",
    template: "split_card",
    link_url: "https://www.moonpay.com",
    image_url: "https://ik.imagekit.io/blockster/uploads/1776110628-489a1c36bb39432a.jpg",
    params: %{
      "brand_color" => "#7D00FF",
      "brand_name" => "Moonpay",
      "cta_text" => "Open Moonpay",
      "description" => "From card to wallet in under a minute. Available in 160 countries with the lowest fees in the industry.",
      "heading" => "Skip the exchange. Fund your wallet directly.",
      "panel_color" => "#7D00FF",
      "panel_color_end" => "#4A00B8",
      "stat_label_bottom" => "Card min",
      "stat_label_top" => "From",
      "stat_value" => "$3.99"
    },
    sort_order: 0
  },
  %{
    name: "Moonpay Bottom CTA · article_inline_2",
    placement: "article_inline_2",
    template: "split_card",
    link_url: "https://www.moonpay.com",
    image_url: "https://ik.imagekit.io/blockster/uploads/1776110628-489a1c36bb39432a.jpg",
    params: %{
      "brand_color" => "#7D00FF",
      "brand_name" => "Moonpay",
      "cta_text" => "Open Moonpay",
      "description" => "From card to wallet in under a minute. Available in 160 countries with the lowest fees in the industry.",
      "heading" => "Skip the exchange. Fund your wallet directly.",
      "panel_color" => "#7D00FF",
      "panel_color_end" => "#4A00B8",
      "stat_label_bottom" => "Card min",
      "stat_label_top" => "From",
      "stat_value" => "$3.99"
    },
    sort_order: 0
  },
  %{
    name: "Moonpay Bottom CTA · homepage_inline",
    placement: "homepage_inline",
    template: "split_card",
    link_url: "https://www.moonpay.com",
    image_url: "https://ik.imagekit.io/blockster/uploads/1776110628-489a1c36bb39432a.jpg",
    params: %{
      "brand_color" => "#7D00FF",
      "brand_name" => "Moonpay",
      "cta_text" => "Open Moonpay",
      "description" => "From card to wallet in under a minute. Available in 160 countries with the lowest fees in the industry.",
      "heading" => "Skip the exchange. Fund your wallet directly.",
      "panel_color" => "#7D00FF",
      "panel_color_end" => "#4A00B8",
      "stat_label_bottom" => "Card min",
      "stat_label_top" => "From",
      "stat_value" => "$3.99"
    },
    sort_order: 70
  }
]

# ── Execute ────────────────────────────────────────────────────────────────

# Blank slate — any pre-existing banner row not in this list stays OFF.
{off, _} = Repo.update_all(Banner, set: [is_active: false])
IO.puts("Deactivated #{off} existing banner(s)")

created = :counters.new(1, [])
updated = :counters.new(1, [])

for attrs <- banners do
  # Banners default to active. Entries can opt out by setting
  # `is_active: false` inline — used for Moonpay creatives that should ship
  # to prod (so admins can toggle them on via /admin/banners without
  # re-authoring the row from scratch), but stay dormant by default.
  attrs = Map.put_new(attrs, :is_active, true)

  case Repo.one(from b in Banner, where: b.name == ^attrs.name) do
    nil ->
      {:ok, b} = Ads.create_banner(attrs)
      :counters.add(created, 1, 1)
      IO.puts("Created ##{b.id} [#{attrs.placement}] #{attrs.name}")

    existing ->
      {:ok, b} = Ads.update_banner(existing, Map.drop(attrs, [:name]))
      :counters.add(updated, 1, 1)
      IO.puts("Updated ##{b.id} [#{attrs.placement}] #{attrs.name}")
  end
end

active = Enum.count(banners, &Map.get(&1, :is_active, true))
dormant = length(banners) - active

IO.puts("\nCreated: #{:counters.get(created, 1)}")
IO.puts("Updated: #{:counters.get(updated, 1)}")
IO.puts("Total active:  #{active}")
IO.puts("Total dormant: #{dormant}  (created but is_active: false — toggle via /admin/banners)")
IO.puts("\nDone.")
