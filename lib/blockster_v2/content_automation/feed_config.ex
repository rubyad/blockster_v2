defmodule BlocksterV2.ContentAutomation.FeedConfig do
  @moduledoc """
  Static RSS feed configuration for the content automation pipeline.
  28 feeds total: 12 premium (2x weight), 16 standard (1x weight).

  Premium tier includes major mainstream financial outlets (whose framing we
  challenge with counter-narrative content) and top crypto-native publications.

  Feeds with status :blocked have paywalled or unreliable RSS — they're kept
  in the list so they can be activated when workarounds become available.
  """

  alias BlocksterV2.ContentAutomation.Settings

  @feeds [
    # ── Premium Tier (2x weight in topic ranking) ──
    # Mainstream financial press — excellent factual reporting, establishment framing we challenge
    %{source: "Bloomberg Crypto", url: "https://feeds.bloomberg.com/crypto/news.rss", tier: :premium, status: :active},
    %{source: "TechCrunch Crypto", url: "https://techcrunch.com/category/cryptocurrency/feed/", tier: :premium, status: :active},
    %{source: "Reuters Business", url: "https://www.reutersagency.com/feed/?best-topics=business-finance", tier: :premium, status: :blocked},
    %{source: "Financial Times", url: "https://www.ft.com/cryptofinance?format=rss", tier: :premium, status: :blocked},
    %{source: "The Economist", url: "https://www.economist.com/finance-and-economics/rss.xml", tier: :premium, status: :blocked},
    %{source: "Forbes Crypto", url: "https://www.forbes.com/crypto-blockchain/feed/", tier: :premium, status: :blocked},
    %{source: "Barron's", url: "https://www.barrons.com/feed?id=blog_rss", tier: :premium, status: :blocked},
    %{source: "The Verge", url: "https://www.theverge.com/rss/index.xml", tier: :premium, status: :blocked},
    # Crypto-native premium — promoted for quality and depth
    %{source: "CoinDesk", url: "https://www.coindesk.com/arc/outboundfeeds/rss/", tier: :premium, status: :active},
    %{source: "The Block", url: "https://www.theblock.co/rss.xml", tier: :premium, status: :active},
    %{source: "Blockworks", url: "https://blockworks.co/feed", tier: :premium, status: :active},
    %{source: "DL News", url: "https://www.dlnews.com/arc/outboundfeeds/rss/", tier: :premium, status: :active},

    # ── Standard Tier (1x weight) ──
    %{source: "CoinTelegraph", url: "https://cointelegraph.com/rss", tier: :standard, status: :active},
    %{source: "Decrypt", url: "https://decrypt.co/feed", tier: :standard, status: :active},
    %{source: "Bitcoin Magazine", url: "https://bitcoinmagazine.com/feed", tier: :standard, status: :active},
    %{source: "The Defiant", url: "https://thedefiant.io/feed", tier: :standard, status: :active},
    %{source: "CryptoSlate", url: "https://cryptoslate.com/feed/", tier: :standard, status: :active},
    %{source: "NewsBTC", url: "https://www.newsbtc.com/feed/", tier: :standard, status: :active},
    %{source: "Bitcoinist", url: "https://bitcoinist.com/feed/", tier: :standard, status: :active},
    %{source: "U.Today", url: "https://u.today/rss", tier: :standard, status: :active},
    %{source: "Crypto Briefing", url: "https://cryptobriefing.com/feed/", tier: :standard, status: :active},
    %{source: "BeInCrypto", url: "https://beincrypto.com/feed/", tier: :standard, status: :active},
    %{source: "Unchained", url: "https://unchainedcrypto.com/feed/", tier: :standard, status: :active},
    %{source: "CoinGape", url: "https://coingape.com/feed/", tier: :standard, status: :active},
    %{source: "Crypto Potato", url: "https://cryptopotato.com/feed/", tier: :standard, status: :active},
    %{source: "AMBCrypto", url: "https://ambcrypto.com/feed/", tier: :standard, status: :active},
    %{source: "Protos", url: "https://protos.com/feed/", tier: :standard, status: :active},
    %{source: "Milk Road", url: "https://www.milkroad.com/feed", tier: :standard, status: :active}
  ]

  @doc """
  Returns active feeds not disabled by admin settings.
  Filters out :blocked feeds (paywalled) and admin-disabled feeds.
  """
  def get_active_feeds do
    disabled = Settings.get(:disabled_feeds, [])

    @feeds
    |> Enum.filter(&(&1.status == :active))
    |> Enum.reject(fn feed -> feed.source in disabled end)
  end

  @doc "Returns all feeds including blocked ones (for admin dashboard)."
  def all_feeds, do: @feeds

  @doc "Returns the weight multiplier for a tier."
  def tier_weight(:premium), do: 2.0
  def tier_weight(:standard), do: 1.0
  def tier_weight(_), do: 1.0
end
