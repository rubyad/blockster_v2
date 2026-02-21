defmodule Mix.Tasks.SendTestEmails do
  @moduledoc "Send one example of every email template to a given address."
  use Mix.Task

  @shortdoc "Send all 8 notification email templates to an address"

  @impl true
  def run(args) do
    to_email = List.first(args) || "adam@blockster.com"
    to_name = "Adam"
    token = "test-unsub-token-12345"

    Mix.Task.run("app.start")

    alias BlocksterV2.Notifications.EmailBuilder
    alias BlocksterV2.Mailer

    emails = [
      {"Welcome", EmailBuilder.welcome(to_email, to_name, token, %{
        username: "Adam"
      })},

      {"Single Article", EmailBuilder.single_article(to_email, to_name, token, %{
        title: "BlackRock Tokenizes $10B Treasury Fund on Ethereum",
        body: "In a landmark move for institutional DeFi adoption, BlackRock has announced the full tokenization of its Treasury money market fund on the Ethereum mainnet. The BUIDL fund, which already held $5B in tokenized assets, will now expand to cover the firm's entire $10 billion short-term government bond portfolio. Industry analysts say this could trigger a wave of competing tokenization efforts from Fidelity, Vanguard, and State Street.",
        image_url: "https://ik.imagekit.io/blockster/tr:w-600/article-blackrock-tokenization.jpg",
        slug: "blackrock-tokenizes-10b-treasury-fund",
        hub_name: "DeFi Daily"
      })},

      {"Daily Digest", EmailBuilder.daily_digest(to_email, to_name, token, %{
        articles: [
          %{title: "Solana Hits 100K TPS in Firedancer Upgrade", slug: "solana-firedancer-100k-tps", image_url: "https://ik.imagekit.io/blockster/tr:w-100/solana-firedancer.jpg", hub_name: "Blockchain News"},
          %{title: "Trump Signs Executive Order Creating National Bitcoin Reserve", slug: "trump-bitcoin-reserve-executive-order", image_url: "https://ik.imagekit.io/blockster/tr:w-100/bitcoin-reserve.jpg", hub_name: "Policy Watch"},
          %{title: "Uniswap v5 Introduces Intent-Based Trading", slug: "uniswap-v5-intents", image_url: "https://ik.imagekit.io/blockster/tr:w-100/uniswap-v5.jpg", hub_name: "DeFi Daily"},
          %{title: "Vitalik Proposes EIP-9999: Verkle Tree Migration Plan", slug: "vitalik-eip-9999-verkle", hub_name: "Ethereum Hub"},
          %{title: "Nvidia Partners with Chainlink for GPU-Verified Oracles", slug: "nvidia-chainlink-gpu-oracles", hub_name: "AI x Crypto"}
        ],
        date: Date.utc_today()
      })},

      {"Promotional", EmailBuilder.promotional(to_email, to_name, token, %{
        title: "Flash Sale: 50% Off All Blockster Merch",
        body: "For the next 48 hours, everything in the Blockster Shop is half price. Limited edition hoodies, hats, and stickers — all available with BUX or card. Don't miss out, stock is limited.",
        image_url: "https://ik.imagekit.io/blockster/tr:w-600/shop-flash-sale-banner.jpg",
        action_url: "https://blockster-v2.fly.dev/shop",
        action_label: "Shop the Sale",
        discount_code: "FLASH50"
      })},

      {"Referral Prompt", EmailBuilder.referral_prompt(to_email, to_name, token, %{
        referral_link: "https://blockster-v2.fly.dev/ref/adam-xyz123",
        bux_reward: 750
      })},

      {"Weekly Reward Summary", EmailBuilder.weekly_reward_summary(to_email, to_name, token, %{
        total_bux_earned: 3_450,
        articles_read: 17,
        days_active: 5,
        top_hub: "DeFi Daily"
      })},

      {"Re-Engagement", EmailBuilder.re_engagement(to_email, to_name, token, %{
        days_inactive: 14,
        articles: [
          %{title: "Arbitrum Launches Orbit L3 SDK", slug: "arbitrum-orbit-l3-sdk"},
          %{title: "MakerDAO Rebrands to Sky Protocol", slug: "makerdao-sky-rebrand"},
          %{title: "Circle Launches Native USDC on Base", slug: "circle-usdc-base-native"},
          %{title: "Coinbase Q4 Earnings Beat Estimates", slug: "coinbase-q4-earnings-2026"},
          %{title: "Pudgy Penguins Floor Hits 30 ETH", slug: "pudgy-penguins-30-eth"}
        ],
        special_offer: "2x BUX on your next 3 articles — this week only!"
      })},

      {"Order Update (Shipped)", EmailBuilder.order_update(to_email, to_name, token, %{
        order_number: "BLK-20260220-0042",
        status: "shipped",
        tracking_url: "https://track.aftership.com/blockster/BLK-20260220-0042",
        items: [
          %{title: "Blockster Logo Hoodie — Black / L", quantity: 1},
          %{title: "ROGUE Enamel Pin Set", quantity: 2},
          %{title: "Blockster Sticker Pack (x10)", quantity: 1}
        ]
      })}
    ]

    IO.puts("\nSending #{length(emails)} test emails to #{to_email}...\n")

    Enum.each(emails, fn {name, email} ->
      case Mailer.deliver(email) do
        {:ok, _} ->
          IO.puts("  ✓ #{name}")
        {:error, reason} ->
          IO.puts("  ✗ #{name} — #{inspect(reason)}")
      end

      # Small delay between sends to avoid rate limits
      Process.sleep(1_000)
    end)

    IO.puts("\nDone! Check #{to_email} inbox.\n")
  end
end
