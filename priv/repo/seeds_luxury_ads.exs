# Seed luxury template ads built during the April 2026 ads-system pass:
# Gray & Sons (watches), Ferrari of Miami + Lamborghini Miami (cars), and
# Flight Finder Exclusive (jet card). All images are hosted on ImageKit
# (origin = the project S3 bucket) so this seed is production-safe.
#
#   mix run priv/repo/seeds_luxury_ads.exs
#
# Idempotent: if a banner with the same name already exists, it's
# reactivated rather than duplicated. Other attrs are NOT updated on
# re-run — edit existing banners through `/admin/banners` or via mix run.

alias BlocksterV2.Ads
alias BlocksterV2.Ads.Banner
alias BlocksterV2.Repo
import Ecto.Query

# ── Shared image URLs (hosted on ImageKit) ──────────────────────────────
img_day_date_v2 = "https://ik.imagekit.io/blockster/ads/grayandsons/1776227245-044b255f5339-day-date-v2.png"
img_submariner = "https://ik.imagekit.io/blockster/ads/grayandsons/1776222731-879ba0a4c7b8-submariner-snug.jpg"
img_gmt = "https://ik.imagekit.io/blockster/ads/grayandsons/1776222731-552693c61f97-gmt-snug.jpg"
img_dd36_a = "https://ik.imagekit.io/blockster/ads/grayandsons/1776222731-64a288757ce1-daydate36-18038-a-snug.jpg"
img_dd40 = "https://ik.imagekit.io/blockster/ads/grayandsons/1776222731-1fba6cfc444c-daydate40-228238-snug.jpg"
img_dd36_b = "https://ik.imagekit.io/blockster/ads/grayandsons/1776222731-981c0584120a-daydate36-18038-b-snug.jpg"
img_ferrari = "https://ik.imagekit.io/blockster/ads/ferrarimiami/1776225530-4b09dbcff153-ferrari-roma-spider-clean.jpg"
img_lambo = "https://ik.imagekit.io/blockster/ads/lamborghinimiami/1776225530-2b102ad61435-lambo-revuelto-clean.jpg"
img_phenom_full = "https://ik.imagekit.io/blockster/ads/flightfinder/1776226070-d35e17c339a6-phenom-300e.jpg"
img_phenom_tight = "https://ik.imagekit.io/blockster/ads/flightfinder/1776227229-18ee34b9735f-phenom-300e-tight.jpg"

# ── Shared param presets per brand ──────────────────────────────────────
gray_sons_base = %{
  "brand_name" => "Gray & Sons",
  "image_bg_color" => "#FFFFFF",
  "bg_color" => "#0e0e0e",
  "bg_color_end" => "#1a1a1a",
  "accent_color" => "#C9A961",
  "text_color" => "#E8E4DD"
}

ferrari_base = %{
  "brand_name" => "Ferrari of Miami",
  "image_bg_color" => "#0a0a0a",
  "bg_color" => "#0e0e0e",
  "bg_color_end" => "#1a1a1a",
  "accent_color" => "#FF2800",
  "text_color" => "#E8E4DD"
}

lambo_base = %{
  "brand_name" => "Lamborghini Miami",
  "image_bg_color" => "#0a0a0a",
  "bg_color" => "#0a0a0a",
  "bg_color_end" => "#1a1a1a",
  "accent_color" => "#A4DD00",
  "text_color" => "#E8E4DD"
}

flightfinder_base = %{
  "brand_name" => "Flight Finder Exclusive",
  "image_bg_color" => "#0a1838",
  "bg_color" => "#0a1838",
  "bg_color_end" => "#1a2c5e",
  "accent_color" => "#D4AF37",
  "text_color" => "#E8E4DD"
}

banners = [
  # ── Gray & Sons watches ──────────────────────────────────────────────
  %{
    name: "Grays & Sons · Rolex Day-Date · luxury_watch",
    placement: "article_inline_1",
    template: "luxury_watch",
    image_url: img_day_date_v2,
    link_url: "https://www.grayandsons.com/w529951-rolex-day-date-bark-finish-36mm-18078/",
    is_active: true,
    sort_order: 0,
    params: Map.merge(gray_sons_base, %{
      "image_url" => img_day_date_v2,
      "model_name" => "Rolex Day-Date 36",
      "reference" => "Reference 18078 · Bark Finish · c. 1988",
      "price_usd" => 23500,
      "cta_text" => "Inspect the piece"
    })
  },
  %{
    name: "Gray & Sons · Rolex Day-Date · skyscraper",
    placement: "sidebar_left",
    template: "luxury_watch_skyscraper",
    image_url: img_day_date_v2,
    link_url: "https://www.grayandsons.com/w529951-rolex-day-date-bark-finish-36mm-18078/",
    is_active: true,
    sort_order: 5,
    params: Map.merge(gray_sons_base, %{
      "image_url" => img_day_date_v2,
      "model_name" => "Rolex Day-Date 36",
      "reference" => "Reference 18078 · Bark Finish · c. 1988",
      "price_usd" => 23500
    })
  },
  %{
    name: "Gray & Sons · Rolex Submariner 116618LN · skyscraper",
    placement: "sidebar_left",
    template: "luxury_watch_skyscraper",
    image_url: img_submariner,
    link_url: "https://www.grayandsons.com/w529963-rolex-submariner-40mm-116618ln/",
    is_active: true,
    sort_order: 6,
    params: Map.merge(gray_sons_base, %{
      "image_url" => img_submariner,
      "model_name" => "Rolex Submariner",
      "reference" => "Reference 116618LN · 40mm 18k Gold",
      "price_usd" => 36500
    })
  },
  %{
    name: "Gray & Sons · Rolex GMT-Master II 116718 · skyscraper",
    placement: "sidebar_left",
    template: "luxury_watch_skyscraper",
    image_url: img_gmt,
    link_url: "https://www.grayandsons.com/w529620-rolex-gmt-master-ii-40mm-116718/",
    is_active: true,
    sort_order: 7,
    params: Map.merge(gray_sons_base, %{
      "image_url" => img_gmt,
      "model_name" => "Rolex GMT-Master II",
      "reference" => "Reference 116718 · 40mm 18k Gold",
      "price_usd" => 41500
    })
  },
  %{
    name: "Gray & Sons · Rolex Day-Date 36 18038 · skyscraper",
    placement: "sidebar_left",
    template: "luxury_watch_skyscraper",
    image_url: img_dd36_a,
    link_url: "https://www.grayandsons.com/w529886-rolex-day-date-36mm-18038/",
    is_active: true,
    sort_order: 8,
    params: Map.merge(gray_sons_base, %{
      "image_url" => img_dd36_a,
      "model_name" => "Rolex Day-Date 36",
      "reference" => "Reference 18038 · 36mm 18k Gold",
      "price_usd" => 21500
    })
  },
  %{
    name: "Gray & Sons · Rolex Day-Date 40 228238 · skyscraper",
    placement: "sidebar_left",
    template: "luxury_watch_skyscraper",
    image_url: img_dd40,
    link_url: "https://www.grayandsons.com/w529840-rolex-day-date-40-40mm-228238/",
    is_active: true,
    sort_order: 9,
    params: Map.merge(gray_sons_base, %{
      "image_url" => img_dd40,
      "model_name" => "Rolex Day-Date 40",
      "reference" => "Reference 228238 · 40mm 18k Gold",
      "price_usd" => 45500
    })
  },
  %{
    name: "Gray & Sons · Rolex Day-Date 36 18038 (alt) · skyscraper",
    placement: "sidebar_left",
    template: "luxury_watch_skyscraper",
    image_url: img_dd36_b,
    link_url: "https://www.grayandsons.com/w529714-rolex-day-date-36mm-18038/",
    is_active: true,
    sort_order: 10,
    params: Map.merge(gray_sons_base, %{
      "image_url" => img_dd36_b,
      "model_name" => "Rolex Day-Date 36",
      "reference" => "Reference 18038 · 36mm 18k Gold",
      "price_usd" => 21500
    })
  },
  %{
    name: "Gray & Sons · Rolex Day-Date · compact full (whole image)",
    placement: "article_inline_2",
    template: "luxury_watch_compact_full",
    image_url: img_day_date_v2,
    link_url: "https://www.grayandsons.com/w529951-rolex-day-date-bark-finish-36mm-18078/",
    is_active: true,
    sort_order: 0,
    params: Map.merge(gray_sons_base, %{
      "image_url" => img_day_date_v2,
      "model_name" => "Rolex Day-Date 36",
      "reference" => "Reference 18078 · Bark Finish · c. 1988",
      "price_usd" => 23500
    })
  },
  %{
    name: "Gray & Sons · Rolex Submariner · split",
    placement: "article_inline_3",
    template: "luxury_watch_split",
    image_url: img_submariner,
    link_url: "https://www.grayandsons.com/w529963-rolex-submariner-40mm-116618ln/",
    is_active: true,
    sort_order: 0,
    params: Map.merge(gray_sons_base, %{
      "image_url" => img_submariner,
      "model_name" => "Rolex Submariner",
      "reference" => "Reference 116618LN · 40mm 18k Gold",
      "price_usd" => 36500,
      "cta_text" => "Inspect the piece"
    })
  },

  # ── Ferrari of Miami ─────────────────────────────────────────────────
  %{
    name: "Ferrari of Miami · 2024 Roma Spider · luxury_car",
    placement: "article_inline_1",
    template: "luxury_car",
    image_url: img_ferrari,
    link_url: "https://ferrariofmiami.com/inventory/ferrari-roma-spider-zff09rpa3r0310246/",
    is_active: true,
    sort_order: 0,
    params: Map.merge(ferrari_base, %{
      "image_url" => img_ferrari,
      "year" => 2024,
      "model_name" => "Ferrari Roma Spider",
      "trim" => "Convertible · Bianco Cervino over Cuoio",
      "badge" => "Pre-owned · 948 mi",
      "price_usd" => 316900,
      "cta_text" => "View this Ferrari"
    })
  },

  # ── Lamborghini Miami ────────────────────────────────────────────────
  %{
    name: "Lamborghini Miami · 2024 Revuelto · luxury_car",
    placement: "article_inline_2",
    template: "luxury_car",
    image_url: img_lambo,
    link_url: "https://www.lamborghinimiami.com/vehicle-details/used-2024-lamborghini-revuelto--north-miami-beach-fl-id-64077173",
    is_active: true,
    sort_order: 0,
    params: Map.merge(lambo_base, %{
      "image_url" => img_lambo,
      "year" => 2024,
      "model_name" => "Lamborghini Revuelto",
      "trim" => "Verde Scandal Metallic over Nero Ade",
      "badge" => "Pre-owned · 5,506 mi",
      "price_usd" => 674950,
      "cta_text" => "View this Lamborghini"
    })
  },
  %{
    name: "Lamborghini Miami · 2024 Revuelto · skyscraper",
    placement: "sidebar_left",
    template: "luxury_car_skyscraper",
    image_url: img_lambo,
    link_url: "https://www.lamborghinimiami.com/vehicle-details/used-2024-lamborghini-revuelto--north-miami-beach-fl-id-64077173",
    is_active: true,
    sort_order: 11,
    params: Map.merge(lambo_base, %{
      "image_url" => img_lambo,
      "year" => 2024,
      "model_name" => "Lamborghini Revuelto",
      "trim" => "Verde Scandal Metallic over Nero Ade",
      "price_usd" => 674950
    })
  },
  %{
    name: "Lamborghini Miami · 2024 Revuelto · homepage banner",
    placement: "homepage_top_desktop",
    template: "luxury_car_banner",
    image_url: img_lambo,
    link_url: "https://www.lamborghinimiami.com/vehicle-details/used-2024-lamborghini-revuelto--north-miami-beach-fl-id-64077173",
    is_active: true,
    sort_order: 5,
    params: Map.merge(lambo_base, %{
      "image_url" => img_lambo,
      "year" => 2024,
      "model_name" => "Lamborghini Revuelto",
      "trim" => "Verde Scandal Metallic over Nero Ade",
      "price_usd" => 674950
    })
  },

  # ── Flight Finder Exclusive (jet card) ───────────────────────────────
  %{
    name: "Flight Finder Exclusive · 25hr Light Jet · jet_card",
    placement: "article_inline_1",
    template: "jet_card_compact",
    image_url: img_phenom_tight,
    link_url: "https://flightfinder-exclusive.com/services/light-jets/",
    is_active: true,
    sort_order: 0,
    params: Map.merge(flightfinder_base, %{
      "image_url" => img_phenom_tight,
      "hours" => 25,
      "headline" => "Pre-paid light-jet hours, ready to fly.",
      "aircraft_category" => "Embraer Phenom 300E · Light Jet",
      "badge" => "25-hour jet card",
      "price_usd" => 100000,
      "price_subtitle" => "25-hour jet card · Light Jet tier",
      "cta_text" => "Buy Jet Card"
    })
  },
  %{
    name: "Flight Finder Exclusive · 25hr Light Jet · skyscraper",
    placement: "sidebar_left",
    template: "jet_card_skyscraper",
    image_url: img_phenom_full,
    link_url: "https://flightfinder-exclusive.com/services/light-jets/",
    is_active: true,
    sort_order: 12,
    params: Map.merge(flightfinder_base, %{
      "image_url" => img_phenom_full,
      "hours" => 25,
      "headline" => "Pre-paid light-jet hours.",
      "aircraft_category" => "Embraer Phenom 300E · Light Jet",
      "price_usd" => 100000
    })
  }
]

for attrs <- banners do
  case Repo.one(from b in Banner, where: b.name == ^attrs.name) do
    nil ->
      {:ok, banner} = Ads.create_banner(attrs)
      IO.puts("Created luxury ad ##{banner.id}: #{banner.name}")

    existing ->
      {:ok, banner} = Ads.update_banner(existing, %{is_active: true})
      IO.puts("Kept luxury ad ##{banner.id}: #{banner.name} (reactivated)")
  end
end
