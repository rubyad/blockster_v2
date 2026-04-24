# Updates hub descriptions to match blockster.com/hubs production copy.
# Run with:  mix run priv/repo/update_hub_descriptions.exs
#
# One-off. Safe to re-run — only updates when the matching hub exists.
# Matches by case-insensitive name or slug.

alias BlocksterV2.Blog
alias BlocksterV2.Repo

import Ecto.Query

descriptions = [
  {"Aave", "Aave is a decentralized, non-custodial liquidity protocol where users can supply assets to earn interest or borrow assets by providing over-collateralized collateral."},
  {"Apex Fusion", "Apex Fusion is a next-generation multi-chain blockchain ecosystem that unifies UTxO-based and EVM-based networks into a single, interoperable infrastructure for Web3 users and developers."},
  {"Arbitrum", "Arbitrum is a Layer-2 scaling solution built atop the Ethereum blockchain that significantly improves transaction speed and reduces costs while inheriting Ethereum's security and decentralization."},
  {"Binance", "Binance is a global cryptocurrency exchange and blockchain ecosystem that allows users to trade, manage, and earn on digital assets, while supporting the BNB Chain for DeFi, NFTs, and decentralized applications."},
  {"Bitget", "Bitget is a global cryptocurrency exchange and Web3 platform that enables users to trade and invest in digital assets, serving millions of users across 100+ countries."},
  {"Bitmex", "BitMEX is a crypto derivatives exchange founded in 2014, known for pioneering perpetual futures and offering advanced trading products with deep liquidity for professional traders."},
  {"BitRobot", "BitRobot is a decentralized network designed to accelerate embodied AI by coordinating people, robots, and compute into onchain subnets that generate real-world data, models, and testing environments for next-generation robotics."},
  {"BTCC", "BTCC is one of the oldest cryptocurrency exchanges, founded in 2011, offering global spot and leveraged trading for digital assets."},
  {"Bybit", "Bybit is a global cryptocurrency exchange founded in 2018, offering spot and derivatives trading with a focus on speed, liquidity, and user experience."},
  {"Crypto.com", "Crypto.com is a global cryptocurrency platform offering trading, wallets, payments, and crypto-backed cards, designed to make crypto accessible for everyday use."},
  {"Fateswap", "FateSwap is a decentralized exchange (DEX) that enables users to trade digital assets directly on-chain, offering fast, low-cost transactions while maintaining full user custody."},
  {"Flare", "Flare is a Layer-1 blockchain designed for decentralized data access, enabling smart contracts to securely use off-chain and cross-chain data through its native oracle and interoperability protocols."},
  {"GoldZip", "GoldZip (XGZ) is a blockchain-based digital gold token backed 1:1 by physical gold stored in licensed vaults, combining the stability of gold with 24/7 tradable on-chain convenience."},
  {"Io.Net", "Io.net is a decentralized GPU network on Solana that pools unused compute power to provide scalable, low-cost AI and machine learning infrastructure."},
  {"KuCoin", "KuCoin is a global cryptocurrency exchange founded in 2017, offering spot, futures, margin, P2P trading, staking, lending, and a Web3 wallet for trading and managing digital assets."},
  {"Maple", "Maple Finance is an institutional-grade decentralized lending platform that connects borrowers and lenders through transparent, on-chain credit markets."},
  {"Midnight", "Midnight is a privacy-first blockchain that enables confidential smart contracts and secure data sharing, allowing developers and businesses to build compliant decentralized applications without exposing sensitive information."},
  {"MoonPay", "MoonPay is a global Web3 payments platform powering fiat-to-crypto onramps, offramps, and checkout for 6,000+ partners worldwide, bridging traditional finance with digital assets at scale."},
  {"Morpho", "Morpho is a DeFi lending protocol on Ethereum and other EVM chains, offering permissionless, non-custodial markets, optimized capital efficiency, and governance via the MORPHO token."},
  {"Myriad Markets", "Myriad Markets is a decentralized on-chain prediction market platform that lets users trade outcomes of real-world events directly from websites, social media, and news content."},
  {"Neo", "NEO is a Layer-1 smart contract blockchain focused on digital assets and onchain identity, enabling scalable Web3 applications with built-in tooling and multi-language developer support."},
  {"Nephos", "Nephos Group is a crypto-focused accounting firm offering tax planning, accounting, institutional support, and DeFi consulting to help clients stay compliant and scale in a fast-evolving digital asset market."},
  {"New Friendship Tech", "New Friendship Tech builds global event experiences and social infrastructure for internet-native communities, bringing creators, brands, and Web3 culture together through curated gatherings worldwide."},
  {"Nolcha Shows", "Nolcha Shows is a global Web3 culture network hosting immersive art and technology events across major cities, connecting thousands of artists, brands, and blockchain communities worldwide."},
  {"OKX", "OKX is a global cryptocurrency exchange that allows users to buy, sell, trade, and store digital assets, while also offering Web3 services like wallets, DeFi access, and NFTs."},
  {"RealFi", "RealFi is a financial infrastructure platform that transforms stablecoins from idle digital cash into income-generating assets by deploying capital into real-world credit and fixed income markets, with USDr targeting up to 9% APY."},
  {"Red Beard Ventures", "Red Beard Ventures is a Web3-focused venture capital firm investing in early-stage blockchain, crypto, and metaverse startups while supporting the growth of decentralized technologies."},
  {"Rogue Trader", "Rogue Trader is the fairest game of chance in the world, with zero house edge and instant on-chain payouts. Powered by the ROGUE token on our own lightning-fast blockchain, Rogue Chain."},
  {"Silver Times", "SilverTimes is an RWA token backed by real silver on Ethereum, blending spot silver, futures, cash, and T-bills to provide synthetic exposure."},
  {"Solana", "Solana is a high-performance Layer-1 blockchain capable of processing thousands of transactions per second, powering low-cost DeFi, payments, NFTs, and consumer Web3 applications."},
  {"Space & Time", "Space and Time is a decentralized data layer that uses cryptographic proofs to power trustless queries for smart contracts, supporting verifiable data across DeFi, AI, and enterprise systems."},
  {"Spark Protocol", "Spark Protocol is a decentralized finance (DeFi) liquidity and lending platform built within the Sky (formerly MakerDAO) ecosystem."},
  {"Sui", "Sui is a fast, scalable Layer 1 blockchain built for low-cost transactions and real-time Web3 apps like gaming and DeFi."},
  {"Tessera", "Tessera is a decentralized platform designed to make exposure to leading private companies accessible to everyone. Tessera provides 1:1 economic exposure to private equities with instant settlement, 24/7 liquidity, and no KYC requirements."},
  {"Tether", "Tether (USDT) is the largest and most widely used stablecoin in the cryptocurrency ecosystem, designed to maintain a 1:1 peg to the U.S. dollar (or other fiat currencies for variant tokens)."},
  {"Tezos", "Tezos is an open-source blockchain platform for smart contracts and dApps, focused on security, formal verification, and on-chain governance."},
  {"The Graph", "The Graph is a decentralized indexing protocol that enables developers to efficiently query blockchain data using open APIs called subgraphs — powering many of today's leading Web3 applications."},
  {"The Hashgraph Group", "The Hashgraph Group is a Swiss-based Web3 venture capital and technology firm focused on building and scaling enterprise-grade solutions within the Hedera ecosystem."},
  {"Transak", "Transak is a Web3 payments infrastructure provider enabling compliant crypto onramps, offramps, and embedded payments across 150+ countries for leading blockchain platforms and apps."},
  {"TRON", "TRON is a high-throughput Layer-1 blockchain built for fast, low-cost payments and stablecoins, processing millions of daily transactions and supporting one of the largest USDT ecosystems globally."},
  {"Trust Wallet", "Trust Wallet is a non-custodial mobile crypto wallet that lets users securely store, send, receive, and manage digital assets while accessing DeFi and dApps."},
  {"Voyager", "Voyager is an AI-powered Web3 trading platform that enables seamless access to cryptocurrencies, tokenized commodities, and derivatives in one unified ecosystem."}
]

# Match a hub by case-insensitive name OR slug.
find_hub = fn name ->
  name_lower = String.downcase(name)
  slug = String.downcase(name) |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")
  alt_slug = slug |> String.replace("-", "")

  Repo.one(
    from(h in BlocksterV2.Blog.Hub,
      where:
        fragment("lower(?)", h.name) == ^name_lower or
        fragment("lower(?)", h.slug) == ^slug or
        fragment("lower(?)", h.slug) == ^alt_slug,
      limit: 1
    )
  )
end

{updated, missing} =
  Enum.reduce(descriptions, {0, []}, fn {name, desc}, {updated, missing} ->
    case find_hub.(name) do
      nil ->
        {updated, [name | missing]}

      hub ->
        case Blog.update_hub(hub, %{description: desc}) do
          {:ok, _} ->
            IO.puts("  ✓ #{hub.name}")
            {updated + 1, missing}

          {:error, cs} ->
            IO.puts("  ✗ #{hub.name}: #{inspect(cs.errors)}")
            {updated, [name | missing]}
        end
    end
  end)

IO.puts("")
IO.puts("Updated #{updated} hubs.")
if missing != [], do: IO.puts("Missing (not in DB): #{Enum.join(Enum.reverse(missing), ", ")}")
