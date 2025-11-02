defmodule BlocksterV2.Repo.Migrations.CreateTags do
  use Ecto.Migration

  def change do
    create table(:tags) do
      add :name, :string, null: false
      add :slug, :string, null: false

      timestamps()
    end

    create unique_index(:tags, [:name])
    create unique_index(:tags, [:slug])

    # Seed the predefined tags
    execute """
    INSERT INTO tags (name, slug, inserted_at, updated_at) VALUES
      ('Blockchain', 'blockchain', NOW(), NOW()),
      ('NFTs', 'nfts', NOW(), NOW()),
      ('Decentralization', 'decentralization', NOW(), NOW()),
      ('Real-World Assets (RWA)', 'real-world-assets-rwa', NOW(), NOW()),
      ('DeFi (Decentralized Finance)', 'defi-decentralized-finance', NOW(), NOW()),
      ('Staking', 'staking', NOW(), NOW()),
      ('Yield Farming', 'yield-farming', NOW(), NOW()),
      ('Airdrops', 'airdrops', NOW(), NOW()),
      ('Memecoins', 'memecoins', NOW(), NOW()),
      ('Layer-1 Blockchains', 'layer-1-blockchains', NOW(), NOW()),
      ('Layer-2 Blockchains', 'layer-2-blockchains', NOW(), NOW()),
      ('Layer-3 Blockchains', 'layer-3-blockchains', NOW(), NOW()),
      ('Smart Contracts', 'smart-contracts', NOW(), NOW()),
      ('GameFi / Play-to-Earn', 'gamefi-play-to-earn', NOW(), NOW()),
      ('Crypto Trading', 'crypto-trading', NOW(), NOW()),
      ('Market Analysis', 'market-analysis', NOW(), NOW()),
      ('On-Chain Data / Analytics', 'on-chain-data-analytics', NOW(), NOW()),
      ('Digital Identity / DID', 'digital-identity-did', NOW(), NOW()),
      ('Crypto Investing', 'crypto-investing', NOW(), NOW()),
      ('Stablecoins', 'stablecoins', NOW(), NOW()),
      ('Liquidity & Market-Making', 'liquidity-market-making', NOW(), NOW()),
      ('AI / Agent Economy', 'ai-agent-economy', NOW(), NOW()),
      ('Token Launchpads / Presales', 'token-launchpads-presales', NOW(), NOW()),
      ('Cross-Chain / Interoperability', 'cross-chain-interoperability', NOW(), NOW()),
      ('ZK-Rollups', 'zk-rollups', NOW(), NOW()),
      ('SocialFi', 'socialfi', NOW(), NOW()),
      ('Crypto Regulation', 'crypto-regulation', NOW(), NOW()),
      ('Gambling / Betting', 'gambling-betting', NOW(), NOW()),
      ('Mining / Cloud Mining', 'mining-cloud-mining', NOW(), NOW()),
      ('Fashion', 'fashion', NOW(), NOW()),
      ('Art', 'art', NOW(), NOW()),
      ('Music', 'music', NOW(), NOW()),
      ('Celebrity', 'celebrity', NOW(), NOW())
    """, ""
  end
end
