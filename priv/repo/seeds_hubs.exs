# Script for populating the database with hub data
alias BlocksterV2.Repo
alias BlocksterV2.Blog.Hub
alias BlocksterV2.Blog

# List of hubs (businesses/blockchains) to seed
hubs_data = [
  %{name: "Flare", tag_name: "Flare", description: "Smart contract platform for decentralized applications", logo_url: nil, color_primary: "#E84142", color_secondary: "#C42A2B"},
  %{name: "Mythical Games", tag_name: "Mythical Games", description: "Gaming technology company and game publisher", logo_url: nil, color_primary: "#8B5CF6", color_secondary: "#7C3AED"},
  %{name: "Moca Network", tag_name: "Moca Network", description: "Network solutions for blockchain", logo_url: nil, color_primary: "#10B981", color_secondary: "#059669"},
  %{name: "0G", tag_name: "0G", description: "Decentralized storage network", logo_url: nil, color_primary: "#3B82F6", color_secondary: "#2563EB"},
  %{name: "Space & Time", tag_name: "Space & Time", description: "Decentralized data warehouse", logo_url: nil, color_primary: "#6366F1", color_secondary: "#4F46E5"},
  %{name: "Story Protocol", tag_name: "Story Protocol", description: "IP infrastructure for the web3", logo_url: nil, color_primary: "#EC4899", color_secondary: "#DB2777"},
  %{name: "BNB Chain", tag_name: "BNB Chain", description: "Binance Smart Chain ecosystem", logo_url: nil, color_primary: "#F3BA2F", color_secondary: "#D4A027"},
  %{name: "Bitlayer", tag_name: "Bitlayer", description: "Bitcoin layer 2 solution", logo_url: nil, color_primary: "#F7931A", color_secondary: "#E67F0A"},
  %{name: "BTCC", tag_name: "BTCC", description: "Cryptocurrency exchange", logo_url: nil, color_primary: "#1E40AF", color_secondary: "#1E3A8A"},
  %{name: "Neo", tag_name: "Neo", description: "Smart economy platform", logo_url: nil, color_primary: "#58BF00", color_secondary: "#4CAF00"},
  %{name: "Optimism", tag_name: "Optimism", description: "Ethereum layer 2 scaling solution", logo_url: nil, color_primary: "#FF0420", color_secondary: "#E00319"},
  %{name: "Etherlink", tag_name: "Etherlink", description: "Bridge protocol for cross-chain", logo_url: nil, color_primary: "#3B82F6", color_secondary: "#2563EB"},
  %{name: "COTI", tag_name: "COTI", description: "Payment solution for enterprises", logo_url: nil, color_primary: "#00C9FF", color_secondary: "#00B4E6"},
  %{name: "Apex Fusion", tag_name: "Apex Fusion", description: "DeFi protocol", logo_url: nil, color_primary: "#8B5CF6", color_secondary: "#7C3AED"},
  %{name: "Open Ledger", tag_name: "Open Ledger", description: "Distributed ledger technology", logo_url: nil, color_primary: "#10B981", color_secondary: "#059669"},
  %{name: "Trust Wallet", tag_name: "Trust Wallet", description: "Multi-chain crypto wallet", logo_url: nil, color_primary: "#3375BB", color_secondary: "#2A5F9E"},
  %{name: "KuCoin", tag_name: "KuCoin", description: "Cryptocurrency exchange", logo_url: nil, color_primary: "#24AE8F", color_secondary: "#1F9476"},
  %{name: "Bybit", tag_name: "Bybit", description: "Cryptocurrency derivatives exchange", logo_url: nil, color_primary: "#F7A600", color_secondary: "#DD9500"},
  %{name: "Binance", tag_name: "Binance", description: "Leading cryptocurrency exchange", logo_url: nil, color_primary: "#F3BA2F", color_secondary: "#D4A027"},
  %{name: "ExtateX", tag_name: "ExtateX", description: "Digital asset platform", logo_url: nil, color_primary: "#6366F1", color_secondary: "#4F46E5"},
  %{name: "MoonPay", tag_name: "MoonPay", description: "Buy and sell crypto with ease", logo_url: "/images/moonpay.png", color_primary: "#7B3FE4", color_secondary: "#5B2FC1"},
  %{name: "Myriad", tag_name: "Myriad", description: "Decentralized social network", logo_url: nil, color_primary: "#EC4899", color_secondary: "#DB2777"},
  %{name: "Maple", tag_name: "Maple", description: "Institutional capital marketplace", logo_url: nil, color_primary: "#FF6B6B", color_secondary: "#EE5A52"},
  %{name: "ETH Women", tag_name: "ETH Women", description: "Community empowering women in Ethereum", logo_url: nil, color_primary: "#B794F4", color_secondary: "#9F7AEA"},
  %{name: "Nolcha", tag_name: "Nolcha", description: "Fashion NFT platform", logo_url: nil, color_primary: "#F59E0B", color_secondary: "#D97706"},
  %{name: "TRON", tag_name: "TRON", description: "Decentralized blockchain platform", logo_url: nil, color_primary: "#EB0029", color_secondary: "#C70022"},
  %{name: "Crypto.com", tag_name: "Crypto.com", description: "Cryptocurrency platform", logo_url: nil, color_primary: "#103F68", color_secondary: "#0D3252"},
  %{name: "Ethereum", tag_name: "Ethereum", description: "Leading smart contract platform", logo_url: nil, color_primary: "#627EEA", color_secondary: "#454A75"},
  %{name: "WalletConnect", tag_name: "WalletConnect", description: "Open protocol for wallet communication", logo_url: nil, color_primary: "#3B99FC", color_secondary: "#2A7BC9"},
  %{name: "MetaMask", tag_name: "MetaMask", description: "Leading Ethereum wallet", logo_url: nil, color_primary: "#F6851B", color_secondary: "#E2761B"},
  %{name: "Solana", tag_name: "Solana", description: "High-performance blockchain", logo_url: nil, color_primary: "#00FFA3", color_secondary: "#00DC82"},
  %{name: "Avalanche", tag_name: "Avalanche", description: "Lightning fast blockchain platform", logo_url: nil, color_primary: "#E84142", color_secondary: "#C42A2B"},
  %{name: "Polygon", tag_name: "Polygon", description: "Ethereum scaling solution", logo_url: nil, color_primary: "#8247E5", color_secondary: "#7130D3"},
  %{name: "Arbitrum", tag_name: "Arbitrum", description: "Ethereum layer 2 scaling", logo_url: nil, color_primary: "#28A0F0", color_secondary: "#1E87D4"},
  %{name: "Base", tag_name: "Base", description: "Coinbase layer 2 network", logo_url: nil, color_primary: "#0052FF", color_secondary: "#0041CC"},
  %{name: "Cosmos", tag_name: "Cosmos", description: "Internet of blockchains", logo_url: nil, color_primary: "#2E3148", color_secondary: "#1C1E2E"},
  %{name: "Cardano", tag_name: "Cardano", description: "Proof-of-stake blockchain platform", logo_url: nil, color_primary: "#0033AD", color_secondary: "#002A8D"},
  %{name: "Polkadot", tag_name: "Polkadot", description: "Multi-chain protocol", logo_url: nil, color_primary: "#E6007A", color_secondary: "#CC006C"},
  %{name: "Sui", tag_name: "Sui", description: "Layer 1 blockchain", logo_url: nil, color_primary: "#6FBCF0", color_secondary: "#5AA5D9"},
  %{name: "Aptos", tag_name: "Aptos", description: "Layer 1 blockchain for everyone", logo_url: nil, color_primary: "#00D9D5", color_secondary: "#00BFB7"},
  %{name: "TON", tag_name: "TON", description: "The Open Network", logo_url: nil, color_primary: "#0088CC", color_secondary: "#0073AD"},
  %{name: "Fantom", tag_name: "Fantom", description: "High-performance DAG blockchain", logo_url: nil, color_primary: "#1969FF", color_secondary: "#0F4FCC"},
  %{name: "Linea", tag_name: "Linea", description: "zkEVM layer 2", logo_url: nil, color_primary: "#121212", color_secondary: "#000000"},
  %{name: "zkSync", tag_name: "zkSync", description: "Zero-knowledge rollup", logo_url: nil, color_primary: "#8C8DFC", color_secondary: "#7172E3"},
  %{name: "Mantle", tag_name: "Mantle", description: "Ethereum layer 2 network", logo_url: nil, color_primary: "#000000", color_secondary: "#1A1A1A"},
  %{name: "Uniswap", tag_name: "Uniswap", description: "Leading decentralized exchange", logo_url: nil, color_primary: "#FF007A", color_secondary: "#E6006C"},
  %{name: "Aave", tag_name: "Aave", description: "DeFi lending protocol", logo_url: nil, color_primary: "#B6509E", color_secondary: "#9D4386"},
  %{name: "Curve", tag_name: "Curve", description: "Stablecoin exchange protocol", logo_url: nil, color_primary: "#40B4EA", color_secondary: "#349AC4"},
  %{name: "MakerDAO", tag_name: "MakerDAO", description: "Decentralized credit platform", logo_url: nil, color_primary: "#1AAB9B", color_secondary: "#148E80"},
  %{name: "Lido", tag_name: "Lido", description: "Liquid staking solution", logo_url: nil, color_primary: "#00A3FF", color_secondary: "#008CDB"},
  %{name: "Bitcoin", tag_name: "Bitcoin", description: "The original cryptocurrency", logo_url: nil, color_primary: "#F7931A", color_secondary: "#E67F0A"},
  %{name: "Nansen", tag_name: "Nansen", description: "Blockchain analytics platform", logo_url: nil, color_primary: "#9945FF", color_secondary: "#8534E6"},
  %{name: "Messari", tag_name: "Messari", description: "Crypto market intelligence", logo_url: nil, color_primary: "#1E1E1E", color_secondary: "#0A0A0A"},
  %{name: "Glassnode", tag_name: "Glassnode", description: "On-chain market intelligence", logo_url: nil, color_primary: "#4A90E2", color_secondary: "#3A77C2"},
  %{name: "Chainalysis", tag_name: "Chainalysis", description: "Blockchain data platform", logo_url: nil, color_primary: "#0045FF", color_secondary: "#0037CC"},
  %{name: "Dune Analytics", tag_name: "Dune Analytics", description: "Blockchain analytics platform", logo_url: nil, color_primary: "#FF6B40", color_secondary: "#E65630"},
  %{name: "Santiment", tag_name: "Santiment", description: "Behavior analytics platform", logo_url: nil, color_primary: "#5275FF", color_secondary: "#3F5FE6"},
  %{name: "Token Terminal", tag_name: "Token Terminal", description: "Crypto financial data", logo_url: nil, color_primary: "#627EEA", color_secondary: "#4F67BA"},
  %{name: "IntoTheBlock", tag_name: "IntoTheBlock", description: "Market intelligence platform", logo_url: nil, color_primary: "#4E54C8", color_secondary: "#3F44A3"},
  %{name: "DefiLlama", tag_name: "DefiLlama", description: "DeFi TVL aggregator", logo_url: nil, color_primary: "#2F80ED", color_secondary: "#2569CA"},
  %{name: "Plasma", tag_name: "Plasma", description: "Scalability framework", logo_url: nil, color_primary: "#8B5CF6", color_secondary: "#7C3AED"},
  %{name: "Robinhood chain", tag_name: "Robinhood chain", description: "Robinhood blockchain network", logo_url: nil, color_primary: "#00C805", color_secondary: "#00A804"},
  %{name: "Tempo", tag_name: "Tempo", description: "Stripe blockchain initiative", logo_url: nil, color_primary: "#635BFF", color_secondary: "#4E49E6"},
  %{name: "Rogue Trader", tag_name: "Rogue Trader", description: "Trading platform", logo_url: nil, color_primary: "#FF4500", color_secondary: "#E63D00"}
]

# Seed the hubs and create corresponding tags
Enum.each(hubs_data, fn hub_attrs ->
  # Create the hub
  case Blog.create_hub(hub_attrs) do
    {:ok, hub} ->
      IO.puts("Created hub: #{hub.name}")

      # Create corresponding tag
      case Blog.get_or_create_tag(hub.tag_name) do
        {:ok, tag} ->
          IO.puts("  Created/found tag: #{tag.name}")
        {:error, error} ->
          IO.puts("  Failed to create tag for: #{hub.tag_name}")
          IO.inspect(error)
      end

    {:error, changeset} ->
      IO.puts("Failed to create hub: #{hub_attrs.name}")
      IO.inspect(changeset.errors)
  end
end)

IO.puts("\nSeeded #{length(hubs_data)} hubs and tags successfully!")
