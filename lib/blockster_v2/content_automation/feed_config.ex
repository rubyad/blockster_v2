defmodule BlocksterV2.ContentAutomation.FeedConfig do
  @moduledoc """
  Static RSS feed configuration for the content automation pipeline.

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
    %{source: "Milk Road", url: "https://www.milkroad.com/feed", tier: :standard, status: :active},

    # ── DeFi Protocol Feeds — Lending & Borrowing ──
    %{source: "Aave Governance", url: "https://governance.aave.com/latest.rss", tier: :premium, status: :active},
    %{source: "Aave Blog", url: "https://aave.mirror.xyz/feed/atom", tier: :premium, status: :active},
    %{source: "Compound Blog", url: "https://medium.com/feed/compound-finance", tier: :premium, status: :active},
    %{source: "MakerDAO Forum", url: "https://forum.makerdao.com/latest.rss", tier: :premium, status: :active},
    %{source: "Morpho Blog", url: "https://morpho.mirror.xyz/feed/atom", tier: :premium, status: :blocked},
    %{source: "Radiant Capital", url: "https://medium.com/feed/@radiantcapitalHQ", tier: :standard, status: :blocked},

    # ── DeFi Protocol Feeds — DEXs & AMMs ──
    %{source: "Uniswap Blog", url: "https://blog.uniswap.org/rss.xml", tier: :premium, status: :blocked},
    %{source: "Curve Finance News", url: "https://news.curve.fi/rss/", tier: :premium, status: :active},
    %{source: "Balancer Blog", url: "https://medium.com/feed/balancer-protocol", tier: :standard, status: :active},
    %{source: "SushiSwap Blog", url: "https://medium.com/feed/sushiswap-org", tier: :standard, status: :active},
    %{source: "PancakeSwap Blog", url: "https://blog.pancakeswap.finance/rss", tier: :standard, status: :blocked},
    %{source: "1inch Blog", url: "https://blog.1inch.io/feed", tier: :standard, status: :active},
    %{source: "Aerodrome (Base)", url: "https://medium.com/feed/@aeraborat", tier: :standard, status: :blocked},
    %{source: "Velodrome (Optimism)", url: "https://medium.com/feed/@VelodromeFi", tier: :standard, status: :active},
    %{source: "Jupiter (Solana)", url: "https://www.jup.ag/blog/rss.xml", tier: :standard, status: :blocked},
    %{source: "Raydium Blog", url: "https://medium.com/feed/@raaborat", tier: :standard, status: :blocked},

    # ── DeFi Protocol Feeds — Liquid Staking & Restaking ──
    %{source: "Lido Blog", url: "https://blog.lido.fi/rss/", tier: :premium, status: :active},
    %{source: "Rocket Pool Blog", url: "https://medium.com/feed/rocket-pool", tier: :standard, status: :active},
    %{source: "EigenLayer Blog", url: "https://www.blog.eigenlayer.xyz/rss/", tier: :premium, status: :active},
    %{source: "Jito (Solana)", url: "https://www.jito.network/blog/rss.xml", tier: :standard, status: :active},
    %{source: "Marinade Finance", url: "https://medium.com/feed/marinade-finance", tier: :standard, status: :active},
    %{source: "Ether.fi Blog", url: "https://etherfi.mirror.xyz/feed/atom", tier: :standard, status: :blocked},

    # ── DeFi Protocol Feeds — Yield Aggregators & Vaults ──
    %{source: "Yearn Finance Blog", url: "https://medium.com/feed/iearn", tier: :premium, status: :active},
    %{source: "Convex Finance Blog", url: "https://medium.com/feed/convex-finance", tier: :standard, status: :blocked},
    %{source: "Pendle Finance Blog", url: "https://medium.com/feed/@pendle_fi", tier: :standard, status: :blocked},
    %{source: "Stargate Finance", url: "https://medium.com/feed/stargate-official", tier: :standard, status: :active},

    # ── DeFi Protocol Feeds — Perpetuals & Derivatives ──
    %{source: "dYdX Blog", url: "https://dydx.exchange/blog/feed", tier: :premium, status: :blocked},
    %{source: "GMX Blog", url: "https://medium.com/feed/@gmx.io", tier: :standard, status: :active},
    %{source: "Synthetix Blog", url: "https://blog.synthetix.io/rss/", tier: :standard, status: :active},
    %{source: "Hyperliquid Blog", url: "https://hyperliquid.mirror.xyz/feed/atom", tier: :standard, status: :blocked},

    # ── RWA & Stablecoins ──
    %{source: "Ethena Blog", url: "https://mirror.xyz/0xF99d0E4E3435cc9C9868D1C6274DfaB3e2721341/feed/atom", tier: :premium, status: :blocked},
    %{source: "Frax Finance Blog", url: "https://medium.com/feed/frax-finance", tier: :standard, status: :blocked},
    %{source: "Ondo Finance Blog", url: "https://blog.ondo.finance/rss", tier: :standard, status: :active},
    %{source: "Centrifuge Blog", url: "https://medium.com/feed/centrifuge", tier: :standard, status: :active},
    %{source: "Maple Finance Blog", url: "https://medium.com/feed/maple-finance", tier: :standard, status: :blocked},

    # ── Centralized Exchange Feeds ──
    %{source: "Binance Blog", url: "https://www.binance.com/en/blog/rss", tier: :standard, status: :blocked},
    %{source: "Coinbase Blog", url: "https://www.coinbase.com/blog/rss", tier: :standard, status: :blocked},
    %{source: "Kraken Blog", url: "https://blog.kraken.com/feed", tier: :standard, status: :active},
    %{source: "OKX Blog", url: "https://www.okx.com/academy/en/rss", tier: :standard, status: :active},
    %{source: "Bybit Blog", url: "https://blog.bybit.com/feed", tier: :standard, status: :blocked},
    %{source: "KuCoin Blog", url: "https://www.kucoin.com/blog/rss", tier: :standard, status: :active},
    %{source: "Bitget Blog", url: "https://www.bitget.com/blog/feed", tier: :standard, status: :blocked},
    %{source: "Gate.io Blog", url: "https://www.gate.io/blog/feed", tier: :standard, status: :blocked},
    %{source: "MEXC Blog", url: "https://www.mexc.com/blog/feed", tier: :standard, status: :blocked},
    %{source: "HTX (Huobi) Blog", url: "https://www.htx.com/support/articles/rss", tier: :standard, status: :blocked},
    %{source: "Crypto.com Blog", url: "https://blog.crypto.com/feed", tier: :standard, status: :active},
    %{source: "Gemini Blog", url: "https://www.gemini.com/blog/feed", tier: :standard, status: :active},
    %{source: "Bitstamp Blog", url: "https://www.bitstamp.net/blog/feed/", tier: :standard, status: :active},
    %{source: "Bitfinex Blog", url: "https://blog.bitfinex.com/feed/", tier: :standard, status: :active},
    %{source: "Upbit Blog", url: "https://upbit.com/service_center/notice/rss", tier: :standard, status: :active},

    # ── DeFi Aggregators & Yield Trackers ──
    %{source: "DefiPrime", url: "https://defiprime.com/feed.xml", tier: :standard, status: :active},
    %{source: "DeFi Pulse Blog", url: "https://medium.com/feed/defi-pulse", tier: :standard, status: :blocked},

    # ── L2 & Chain-Specific Feeds ──
    %{source: "Arbitrum Blog", url: "https://medium.com/feed/offchainlabs", tier: :standard, status: :active},
    %{source: "Optimism Blog", url: "https://optimism.mirror.xyz/feed/atom", tier: :standard, status: :active},
    %{source: "Base Blog", url: "https://base.mirror.xyz/feed/atom", tier: :standard, status: :active},
    %{source: "Polygon Blog", url: "https://blog.polygon.technology/feed", tier: :standard, status: :active},
    %{source: "zkSync Blog", url: "https://zksync.mirror.xyz/feed/atom", tier: :standard, status: :active},
    %{source: "Scroll Blog", url: "https://scroll.io/blog/feed", tier: :standard, status: :active},
    %{source: "Solana Foundation", url: "https://solana.com/news/feed.xml", tier: :standard, status: :blocked},
    %{source: "Avalanche Blog", url: "https://medium.com/feed/avalancheavax", tier: :standard, status: :active},
    %{source: "Cosmos Blog", url: "https://blog.cosmos.network/feed", tier: :standard, status: :blocked},
    %{source: "Sui Blog", url: "https://blog.sui.io/feed", tier: :standard, status: :active},
    %{source: "Aptos Blog", url: "https://medium.com/feed/aptoslabs", tier: :standard, status: :active}
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
