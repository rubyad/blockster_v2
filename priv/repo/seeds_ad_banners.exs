# Seed template-based ad banners matching article_page_mock.html
#
# Run with: mix run priv/repo/seeds_ad_banners.exs

alias BlocksterV2.Repo
alias BlocksterV2.Ads.Banner
import Ecto.Query

# Deactivate all existing banners
Repo.update_all(from(b in Banner, where: b.is_active == true), set: [is_active: false])
IO.puts("Deactivated all existing banners")

# 1. Dark gradient — inline position 1 (1/3 mark)
Repo.insert!(%Banner{
  name: "Moonpay SOL On-Ramp",
  template: "dark_gradient",
  placement: "article_inline_1",
  link_url: "https://www.moonpay.com/buy/sol",
  is_active: true,
  params: %{
    "brand_name" => "Moonpay",
    "brand_color" => "#7D00FF",
    "heading" => "Buy SOL with a card in 30 seconds. No KYC for orders under $150.",
    "description" => "Trusted by 30 million users. Powering the on-ramp for the largest Solana wallets and dApps in the ecosystem.",
    "cta_text" => "Get Started"
  }
})
IO.puts("Created: Moonpay SOL On-Ramp (dark_gradient, article_inline_1)")

# 2. Portrait — inline position 2 (2/3 mark)
Repo.insert!(%Banner{
  name: "Heliosphere Capital",
  template: "portrait",
  placement: "article_inline_2",
  link_url: "#",
  is_active: true,
  params: %{
    "image_url" => "https://images.unsplash.com/photo-1560250097-0b93528c311a?w=800&q=85&auto=format&fit=crop",
    "heading" => "Putting capital to work on chain",
    "subtitle" => "Crypto-Native Investors",
    "cta_text" => "Find out more",
    "brand_name" => "Heliosphere Capital",
    "bg_color" => "#0a1838",
    "bg_color_end" => "#142a6b",
    "accent_color" => "#FF6B35"
  }
})
IO.puts("Created: Heliosphere Capital (portrait, article_inline_2)")

# 3. Split card — inline position 3 (end of article body, 3/3 mark)
Repo.insert!(%Banner{
  name: "Moonpay Bottom CTA",
  template: "split_card",
  placement: "article_inline_3",
  link_url: "https://www.moonpay.com",
  is_active: true,
  params: %{
    "brand_name" => "Moonpay",
    "brand_color" => "#7D00FF",
    "badge" => "Hub Sponsor",
    "heading" => "Skip the exchange. Fund your wallet directly.",
    "description" => "From card to wallet in under a minute. Available in 160 countries with the lowest fees in the industry.",
    "cta_text" => "Open Moonpay",
    "panel_color" => "#7D00FF",
    "panel_color_end" => "#4A00B8",
    "stat_label_top" => "From",
    "stat_value" => "$0.99",
    "stat_label_bottom" => "Network fee"
  }
})
IO.puts("Created: Moonpay Bottom CTA (split_card, article_bottom)")

IO.puts("\nDone! 4 template-based banners created.")
