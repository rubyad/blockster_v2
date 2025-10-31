defmodule BlocksterV2.Repo.Migrations.AddNftNewsPosts do
  use Ecto.Migration

  def up do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    execute """
    INSERT INTO posts (title, slug, content, excerpt, author_name, published_at, category, featured_image, layout, inserted_at, updated_at)
    VALUES
    (
      'Binance and Cristiano Ronaldo Launch 7he Selection',
      'binance-and-cristiano-ronaldo-launch-7he-selection',
      '{"blocks": [{"type": "paragraph", "data": {"text": "Binance, the world''s leading cryptocurrency exchange, has partnered with football legend Cristiano Ronaldo to launch ''7he Selection,'' a groundbreaking NFT collection celebrating his incredible milestone of 950 career goals. This collaboration marks another significant step in bridging the worlds of sports, entertainment, and blockchain technology."}}]}',
      'Binance and Cristiano Ronaldo collaborate to launch 7he Selection, an exclusive NFT collection celebrating the football icon''s historic achievement of 950 career goals.',
      'Blockster Team',
      '#{DateTime.to_iso8601(now)}',
      'People',
      'https://ik.imagekit.io/blockster/984a3be4-7edf-422a-9dc4-f127223d6560.png',
      'default',
      '#{DateTime.to_iso8601(now)}',
      '#{DateTime.to_iso8601(now)}'
    ),
    (
      'Museum of the Moving Image and Tezos Foundation Launch Blockchain Art Initiative',
      'museum-of-the-moving-image-tezos-foundation-launch-blockchain-art-initiative',
      '{"blocks": [{"type": "paragraph", "data": {"text": "The Museum of the Moving Image in New York has announced an innovative partnership with the Tezos Foundation to explore the intersection of film, digital art, and blockchain technology. This groundbreaking initiative aims to showcase how blockchain can preserve and authenticate digital art in the moving image space."}}]}',
      'Museum of the Moving Image partners with Tezos Foundation to launch a pioneering blockchain art initiative exploring digital preservation and authentication.',
      'Blockster Team',
      '#{DateTime.to_iso8601(now)}',
      'Art',
      'https://ik.imagekit.io/blockster/2b3f49f4-1b1c-47d0-9ca0-bc521989b234.png',
      'default',
      '#{DateTime.to_iso8601(now)}',
      '#{DateTime.to_iso8601(now)}'
    ),
    (
      'KuCard and Plaza Premium Lounge Partner for Crypto Travel Benefits',
      'kucard-plaza-premium-lounge-partner-for-crypto-travel-benefits',
      '{"blocks": [{"type": "paragraph", "data": {"text": "KuCard, the innovative crypto payment card, has announced a strategic partnership with Plaza Premium Lounge to bring exclusive benefits to crypto users traveling globally. This collaboration enables cryptocurrency holders to access premium airport lounge services worldwide, marking a significant advancement in crypto adoption for travel and lifestyle services."}}]}',
      'KuCard teams up with Plaza Premium Lounge to offer crypto users exclusive airport lounge access and travel benefits worldwide.',
      'Blockster Team',
      '#{DateTime.to_iso8601(now)}',
      'Lifestyle',
      'https://ik.imagekit.io/blockster/dd5ef38c-671e-4a70-8a6d-13c12cae7d87.png',
      'default',
      '#{DateTime.to_iso8601(now)}',
      '#{DateTime.to_iso8601(now)}'
    ),
    (
      'Final Bosu Meets My Neighbor Alice',
      'final-bosu-meets-my-neighbor-alice',
      '{"blocks": [{"type": "paragraph", "data": {"text": "In an exciting collaboration between two beloved gaming universes, Final Bosu and My Neighbor Alice have announced a strategic partnership that will bring unique cross-platform experiences to players. This integration promises to combine the best elements of both games, creating new opportunities for players to explore and interact across virtual worlds."}}]}',
      'Final Bosu and My Neighbor Alice announce an innovative partnership bringing cross-platform gaming experiences to both communities.',
      'Blockster Team',
      '#{DateTime.to_iso8601(now)}',
      'Gaming',
      'https://ik.imagekit.io/blockster/719c4f1d-c7ba-4a52-b290-67cf5bc4d377.png',
      'default',
      '#{DateTime.to_iso8601(now)}',
      '#{DateTime.to_iso8601(now)}'
    ),
    (
      'Prediction Protocol Myriad Launches on BNB Chain to Expand Across Asia',
      'prediction-protocol-myriad-launches-on-bnb-chain-to-expand-across-asia',
      '{"blocks": [{"type": "paragraph", "data": {"text": "Myriad, an innovative prediction protocol, has officially launched on BNB Chain with a strategic focus on expanding its presence across Asian markets. This deployment on one of the world''s fastest-growing blockchain networks positions Myriad to serve millions of users with efficient, low-cost prediction markets tailored to regional preferences and needs."}}]}',
      'Myriad prediction protocol deploys on BNB Chain, targeting rapid expansion across Asian markets with localized prediction services.',
      'Blockster Team',
      '#{DateTime.to_iso8601(now)}',
      'Business',
      'https://ik.imagekit.io/blockster/8f05a87f-6841-46fa-a6f8-49a0c08830de.png',
      'default',
      '#{DateTime.to_iso8601(now)}',
      '#{DateTime.to_iso8601(now)}'
    ),
    (
      'Hilton Anaheim Turns Into a Digital Playground with Disney Pinnacle x Dapper Labs Scavenger Hunt',
      'hilton-anaheim-disney-pinnacle-dapper-labs-scavenger-hunt',
      '{"blocks": [{"type": "paragraph", "data": {"text": "The Hilton Anaheim has transformed into an immersive digital experience through a unique collaboration between Disney Pinnacle and Dapper Labs. This innovative scavenger hunt combines physical exploration with digital collectibles, offering guests an engaging way to interact with Disney''s beloved characters through blockchain technology while exploring the hotel''s premises."}}]}',
      'Hilton Anaheim hosts an interactive scavenger hunt featuring Disney Pinnacle and Dapper Labs, blending physical adventure with digital collectibles.',
      'Blockster Team',
      '#{DateTime.to_iso8601(now)}',
      'Lifestyle',
      'https://ik.imagekit.io/blockster/170946e2-fba4-4a57-85ee-b805dadbf1f4.png',
      'default',
      '#{DateTime.to_iso8601(now)}',
      '#{DateTime.to_iso8601(now)}'
    )
    """
  end

  def down do
    execute """
    DELETE FROM posts WHERE slug IN (
      'binance-and-cristiano-ronaldo-launch-7he-selection',
      'museum-of-the-moving-image-tezos-foundation-launch-blockchain-art-initiative',
      'kucard-plaza-premium-lounge-partner-for-crypto-travel-benefits',
      'final-bosu-meets-my-neighbor-alice',
      'prediction-protocol-myriad-launches-on-bnb-chain-to-expand-across-asia',
      'hilton-anaheim-disney-pinnacle-dapper-labs-scavenger-hunt'
    )
    """
  end
end
