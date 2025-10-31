defmodule BlocksterV2.Repo.Migrations.AddDemoBlogPosts do
  use Ecto.Migration

  def up do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    execute """
    INSERT INTO posts (title, slug, content, excerpt, author_name, published_at, category, featured_image, layout, view_count, inserted_at, updated_at)
    VALUES
    (
      'Bitcoin ETF Approval Triggers Institutional Gold Rush: $10B Inflows in First Quarter',
      'bitcoin-etf-institutional-gold-rush',
      '{"ops": [
        {"insert": "The long-awaited Bitcoin ETF approvals have unleashed unprecedented institutional demand, with over $10 billion flowing into spot Bitcoin ETFs in the first quarter alone. This watershed moment marks Bitcoin''s transition from fringe asset to portfolio staple.\\n\\n"},
        {"insert": "Breaking Down the Numbers", "attributes": {"header": 2}},
        {"insert": "\\n"},
        {"insert": "BlackRock''s iShares Bitcoin Trust leads the pack with $5.2 billion in assets under management, followed closely by Fidelity and Grayscale conversions. Daily trading volumes regularly exceed $2 billion, rivaling established commodity ETFs.\\n\\n"},
        {"insert": {"tweet": {"id": "1721901627053818209", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">BREAKING: BlackRock''s Bitcoin ETF sees record $520 million in daily inflows as institutional adoption accelerates. <br><br>This is bigger than most predicted - we''re witnessing history in real-time. The institutional FOMO is real.<br><br>Bitcoin is no longer an \\"if\\" - it''s a \\"how much\\" 🚀</p>&mdash; Anthony Pompliano 🌪 (@APompliano) <a href=\\"https://twitter.com/APompliano/status/1721901627053818209?ref_src=twsrc%5Etfw\\">November 7, 2024</a></blockquote>"}}},
        {"insert": "\\n\\n"},
        {"insert": "Pension funds and endowments are allocating 1-3% of portfolios to Bitcoin, viewing it as digital gold and inflation hedge. Insurance companies are following suit, with several major firms announcing Bitcoin allocations for their general accounts.\\n\\n"},
        {"insert": "Market Impact and Price Discovery", "attributes": {"header": 2}},
        {"insert": "\\n"},
        {"insert": "The ETF effect on Bitcoin''s price has been dramatic but orderly. Spot prices have increased 45% since approval, with volatility actually decreasing as institutional buyers provide market depth. The correlation with traditional markets has weakened, suggesting Bitcoin is maturing as an independent asset class.\\n\\n"},
        {"insert": {"tweet": {"id": "1720815432928751837", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">Just had dinner with the CIO of a $50B pension fund.<br><br>They''re allocating 2% to Bitcoin through the ETF. That''s $1 billion.<br><br>And they''re not alone - I''m hearing similar numbers from funds across the country.<br><br>The institutional wave is just beginning.</p>&mdash; Cathie Wood (@CathieDWood) <a href=\\"https://twitter.com/CathieDWood/status/1720815432928751837?ref_src=twsrc%5Etfw\\">November 4, 2024</a></blockquote>"}}},
        {"insert": "\\n\\n"},
        {"insert": "Options markets have exploded, with sophisticated strategies emerging. Covered call strategies are yielding 15-20% annually, attracting yield-focused institutions. The derivatives market is providing price discovery and hedging tools that make Bitcoin more palatable to risk-averse investors.\\n\\n"},
        {"insert": "Looking ahead, analysts predict ETF assets could reach $100 billion within two years. As more countries approve similar products and Bitcoin becomes a standard portfolio allocation, we may be witnessing the early stages of a multi-decade adoption cycle.\\n"}
      ]}',
      'Bitcoin ETF approvals trigger massive institutional adoption with $10B in Q1 inflows, marking crypto''s entrance into mainstream portfolios.',
      'Michael Torres',
      '#{DateTime.to_iso8601(DateTime.add(now, -1, :day))}',
      'Business',
      'https://images.unsplash.com/photo-1518546305927-5a555bb7020d?w=1200&h=600&fit=crop',
      'default',
      5234,
      '#{DateTime.to_iso8601(now)}',
      '#{DateTime.to_iso8601(now)}'
    ),
    (
      'Ethereum Staking Yields Hit 7% as Network Activity Surges Post-Merge',
      'ethereum-staking-yields-network-surge',
      '{"ops": [
        {"insert": "Ethereum staking has become the crypto equivalent of high-yield bonds, with validators earning consistent 7% returns as network activity reaches all-time highs. The Merge''s success has transformed ETH into a yield-bearing asset that institutions can''t ignore.\\n\\n"},
        {"insert": "The Staking Economics Revolution", "attributes": {"header": 2}},
        {"insert": "\\n"},
        {"insert": "With over 28 million ETH staked (worth $56 billion), Ethereum has created one of the largest yield-generating ecosystems in crypto. Liquid staking derivatives like Lido and Rocket Pool have made staking accessible to everyone, not just those with 32 ETH.\\n\\n"},
        {"insert": {"tweet": {"id": "1722234567890123456", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">Ethereum staking APR just hit 7.2% 📈<br><br>Combined with ETH burns from high network activity, we''re seeing real yield + deflationary supply.<br><br>This is what sustainable crypto economics looks like. No ponzinomics, just network revenue sharing.</p>&mdash; Vitalik Buterin (@VitalikButerin) <a href=\\"https://twitter.com/VitalikButerin/status/1722234567890123456?ref_src=twsrc%5Etfw\\">November 8, 2024</a></blockquote>"}}},
        {"insert": "\\n\\n"},
        {"insert": "MEV (Maximum Extractable Value) boost is adding 2-3% to base staking yields. Validators are earning from priority fees, tips, and MEV rewards, creating a sophisticated revenue model that rewards network participation. Professional staking services are optimizing these revenue streams, offering institutional-grade yields.\\n\\n"},
        {"insert": "Institutional Staking Surge", "attributes": {"header": 2}},
        {"insert": "\\n"},
        {"insert": "Banks and asset managers are launching staking services, recognizing the demand for yield in a low-rate environment. Coinbase, Kraken, and Binance control significant staking market share, but traditional finance is catching up with custodial staking solutions.\\n\\n"},
        {"insert": "The regulatory clarity around staking rewards has improved dramatically. The IRS has provided guidance on taxation, and the SEC has approved several staking-focused investment products. This regulatory certainty is crucial for institutional participation.\\n\\n"},
        {"insert": {"tweet": {"id": "1721456789012345678", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">JP Morgan just announced they''re offering Ethereum staking to institutional clients.<br><br>7% yield on a $2 trillion asset class.<br><br>This is the biggest fixed income opportunity since corporate bonds. Traditional finance can''t ignore these returns.</p>&mdash; Raoul Pal (@RaoulGMI) <a href=\\"https://twitter.com/RaoulGMI/status/1721456789012345678?ref_src=twsrc%5Etfw\\">November 6, 2024</a></blockquote>"}}},
        {"insert": "\\n\\n"},
        {"insert": "Looking forward, Ethereum''s staking ratio could reach 50-60%, similar to other proof-of-stake networks. As more ETH gets staked and network activity grows, we might see a supply squeeze that drives both price appreciation and sustained high yields.\\n"}
      ]}',
      'Ethereum staking yields reach 7% as institutional adoption accelerates, transforming ETH into a premier yield-bearing digital asset.',
      'Emily Zhang',
      '#{DateTime.to_iso8601(DateTime.add(now, -2, :day))}',
      'Tech',
      'https://images.unsplash.com/photo-1622630998477-20aa696ecb05?w=1200&h=600&fit=crop',
      'default',
      4567,
      '#{DateTime.to_iso8601(now)}',
      '#{DateTime.to_iso8601(now)}'
    ),
    (
      'Solana DEX Volume Flips Ethereum: The Speed and Cost Advantage',
      'solana-dex-volume-flips-ethereum',
      '{"ops": [
        {"insert": "In a stunning development, Solana''s decentralized exchange volume has surpassed Ethereum for the first time, processing over $3 billion daily. This flip represents a seismic shift in DeFi user preferences driven by speed and cost advantages.\\n\\n"},
        {"insert": "The Numbers Don''t Lie", "attributes": {"header": 2}},
        {"insert": "\\n"},
        {"insert": "Solana DEXs like Jupiter, Raydium, and Orca are processing more transactions than Uniswap, Curve, and Balancer combined. Average transaction costs on Solana are $0.00025, compared to $5-50 on Ethereum. This 20,000x cost difference is driving retail users and high-frequency traders to Solana.\\n\\n"},
        {"insert": {"tweet": {"id": "1723456789012345678", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">Solana DEX volume just flipped Ethereum 🔄<br><br>$3.2B daily volume<br>$0.0002 avg transaction cost<br>400ms confirmation time<br><br>This isn''t about ETH vs SOL - it''s about giving users what they want: fast, cheap, reliable DeFi.<br><br>Competition drives innovation 🚀</p>&mdash; Anatoly Yakovenko (@aeyakovenko) <a href=\\"https://twitter.com/aeyakovenko/status/1723456789012345678?ref_src=twsrc%5Etfw\\">November 11, 2024</a></blockquote>"}}},
        {"insert": "\\n\\n"},
        {"insert": "Transaction speed is equally important. Solana''s 400-millisecond block times enable near-instant trades, crucial for arbitrageurs and market makers. The user experience rivals centralized exchanges, eliminating the waiting and uncertainty that plagued early DeFi.\\n\\n"},
        {"insert": "Ecosystem Explosion", "attributes": {"header": 2}},
        {"insert": "\\n"},
        {"insert": "Solana''s DeFi ecosystem has matured rapidly. Advanced features like cross-margined perpetuals, options protocols, and sophisticated yield vaults are attracting serious capital. TVL has grown to $5 billion, with new protocols launching weekly.\\n\\n"},
        {"insert": "Institutional traders are taking notice. Jump Trading, Alameda''s successor firms, and new market makers are providing deep liquidity. The order book model on Serum and Phoenix offers familiar trading mechanics for traditional finance professionals.\\n\\n"},
        {"insert": {"tweet": {"id": "1722987654321098765", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">Just moved our entire trading operation to Solana.<br><br>- 99.9% cost reduction<br>- 1000x faster execution<br>- Better liquidity on major pairs<br><br>Ethereum will always be the OG, but Solana is where traders trade. Numbers don''t lie.</p>&mdash; Pentoshi (@Pentosh1) <a href=\\"https://twitter.com/Pentosh1/status/1722987654321098765?ref_src=twsrc%5Etfw\\">November 10, 2024</a></blockquote>"}}},
        {"insert": "\\n\\n"},
        {"insert": "The competition is healthy for the entire ecosystem. Ethereum is responding with Layer 2 improvements, while Solana continues pushing performance boundaries. Users are the ultimate winners, with more choices and better experiences across all chains.\\n"}
      ]}',
      'Solana''s DEX volume surpasses Ethereum as traders flock to faster, cheaper transactions, marking a new era in DeFi competition.',
      'David Park',
      '#{DateTime.to_iso8601(DateTime.add(now, -3, :day))}',
      'Tech',
      'https://images.unsplash.com/photo-1640340434855-6084b1f4901c?w=1200&h=600&fit=crop',
      'default',
      3892,
      '#{DateTime.to_iso8601(now)}',
      '#{DateTime.to_iso8601(now)}'
    ),
    (
      'AI and Crypto Convergence: The $100B Market Nobody Saw Coming',
      'ai-crypto-convergence-100b-market',
      '{"ops": [
        {"insert": "The intersection of artificial intelligence and cryptocurrency has created a $100 billion market seemingly overnight. From decentralized compute networks to AI-powered trading bots, this convergence is reshaping both industries.\\n\\n"},
        {"insert": "Decentralized AI Infrastructure", "attributes": {"header": 2}},
        {"insert": "\\n"},
        {"insert": "Projects like Render Network and Akash are creating decentralized GPU marketplaces, making AI compute accessible and affordable. Prices are 70% lower than AWS, attracting AI startups and researchers who need massive compute without massive budgets.\\n\\n"},
        {"insert": {"tweet": {"id": "1724567890123456789", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">We just trained a 7B parameter model on decentralized GPUs for $10,000.<br><br>Same model on AWS: $35,000<br><br>Crypto isn''t just disrupting finance - it''s disrupting the entire AI compute stack. This changes everything for AI startups.</p>&mdash; Emad Mostaque (@EMostaque) <a href=\\"https://twitter.com/EMostaque/status/1724567890123456789?ref_src=twsrc%5Etfw\\">November 14, 2024</a></blockquote>"}}},
        {"insert": "\\n\\n"},
        {"insert": "AI agents are becoming crypto native. Bots that trade, provide liquidity, and optimize DeFi strategies are processing billions in volume. These aren''t simple algorithms - they''re sophisticated neural networks that learn and adapt to market conditions.\\n\\n"},
        {"insert": "Token-Powered AI Models", "attributes": {"header": 2}},
        {"insert": "\\n"},
        {"insert": "New tokenomics models are emerging where AI services are paid for with tokens, creating sustainable economics for open-source AI development. Projects like Bittensor are creating decentralized intelligence markets where the best models earn the most rewards.\\n\\n"},
        {"insert": "Data ownership is being revolutionized. Users can monetize their data for AI training through crypto micropayments, creating a fairer value exchange than the current Big Tech model. Ocean Protocol and similar projects are leading this charge.\\n\\n"},
        {"insert": {"tweet": {"id": "1723890123456789012", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">OpenAI valued at $157B<br>Anthropic at $40B<br><br>Meanwhile, decentralized AI protocols at $15B combined.<br><br>The opportunity is massive. Open source + crypto incentives will eat closed AI''s lunch. We''re betting big on this convergence.</p>&mdash; Chris Dixon (@cdixon) <a href=\\"https://twitter.com/cdixon/status/1723890123456789012?ref_src=twsrc%5Etfw\\">November 13, 2024</a></blockquote>"}}},
        {"insert": "\\n\\n"},
        {"insert": "The regulatory landscape is surprisingly supportive. Governments see decentralized AI as a counterbalance to Big Tech dominance. The EU and several Asian countries are crafting frameworks that encourage this innovation while ensuring safety and accountability.\\n\\n"},
        {"insert": "We''re witnessing the birth of a new computing paradigm where AI and crypto create a decentralized, permissionless intelligence layer for the internet. The implications are profound and we''re just scratching the surface.\\n"}
      ]}',
      'AI and cryptocurrency convergence creates a $100B market with decentralized compute, AI agents, and new economic models reshaping both industries.',
      'Rachel Liu',
      '#{DateTime.to_iso8601(DateTime.add(now, -4, :day))}',
      'Tech',
      'https://images.unsplash.com/photo-1677442136019-21780ecad995?w=1200&h=600&fit=crop',
      'default',
      4678,
      '#{DateTime.to_iso8601(now)}',
      '#{DateTime.to_iso8601(now)}'
    ),
    (
      'Real World Assets Hit $10 Trillion: The Tokenization Revolution Is Here',
      'real-world-assets-tokenization-revolution',
      '{"ops": [
        {"insert": "The tokenization of real-world assets (RWAs) has quietly reached $10 trillion in value, transforming everything from real estate to carbon credits into liquid, programmable digital assets. This isn''t the future - it''s happening now.\\n\\n"},
        {"insert": "Treasury Bonds Lead the Charge", "attributes": {"header": 2}},
        {"insert": "\\n"},
        {"insert": "U.S. Treasury bonds on-chain have exploded to $2 billion in TVL. Protocols like Ondo Finance and Maple are offering tokenized T-bills yielding 5.5%, attracting DeFi users seeking stable, regulated yields. This is the safest yield in crypto, backed by the full faith and credit of the U.S. government.\\n\\n"},
        {"insert": {"tweet": {"id": "1725678901234567890", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">BREAKING: Singapore''s largest bank DBS tokenizes $1 billion in trade finance assets on blockchain.<br><br>- 90% reduction in settlement time<br>- 60% cost savings<br>- Instant liquidity for previously illiquid assets<br><br>Every bank will do this. The efficiency gains are too massive to ignore.</p>&mdash; Larry Fink (@laurencefink) <a href=\\"https://twitter.com/laurencefink/status/1725678901234567890?ref_src=twsrc%5Etfw\\">November 17, 2024</a></blockquote>"}}},
        {"insert": "\\n\\n"},
        {"insert": "Real estate tokenization is transforming property investment. Fractional ownership of commercial buildings, simplified cross-border transactions, and instant liquidity are making real estate accessible to millions of new investors. Major REITs are exploring tokenization to reduce costs and increase accessibility.\\n\\n"},
        {"insert": "The Commodity Revolution", "attributes": {"header": 2}},
        {"insert": "\\n"},
        {"insert": "Gold, silver, and oil are being tokenized at scale. Paxos Gold and similar products offer physical commodity exposure without storage hassles. Agricultural commodities are next, with coffee, wheat, and corn tokens enabling farmers to access global markets directly.\\n\\n"},
        {"insert": "Carbon credits are perhaps the most interesting development. Tokenization brings transparency and liquidity to a traditionally opaque market. Companies can buy, sell, and retire carbon credits instantly, accelerating the path to net zero.\\n\\n"},
        {"insert": {"tweet": {"id": "1724901234567890123", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">Just tokenized $500M in carbon credits.<br><br>Before: 6 months to trade, 5% fees, zero transparency<br>After: Instant trading, 0.1% fees, complete on-chain transparency<br><br>This is how we solve climate change - by making green investments profitable and liquid.</p>&mdash; Mark Cuban (@mcuban) <a href=\\"https://twitter.com/mcuban/status/1724901234567890123?ref_src=twsrc%5Etfw\\">November 15, 2024</a></blockquote>"}}},
        {"insert": "\\n\\n"},
        {"insert": "Traditional exchanges are embracing tokenization. The NYSE, NASDAQ, and international exchanges are building tokenization infrastructure. Within five years, most securities will have tokenized versions trading 24/7 on blockchain rails.\\n\\n"},
        {"insert": "The $10 trillion milestone is just the beginning. McKinsey predicts $120 trillion in tokenized assets by 2030. We''re witnessing the greatest transformation of capital markets since electronic trading. The entire global economy is being rebuilt on blockchain rails.\\n"}
      ]}',
      'Real-world asset tokenization reaches $10 trillion as treasuries, real estate, and commodities move on-chain, revolutionizing global markets.',
      'James Mitchell',
      '#{DateTime.to_iso8601(DateTime.add(now, -5, :day))}',
      'Business',
      'https://images.unsplash.com/photo-1611974789855-9c2a0a7236a3?w=1200&h=600&fit=crop',
      'default',
      5891,
      '#{DateTime.to_iso8601(now)}',
      '#{DateTime.to_iso8601(now)}'
    )
    """
  end

  def down do
    execute """
    DELETE FROM posts WHERE slug IN (
      'bitcoin-etf-institutional-gold-rush',
      'ethereum-staking-yields-network-surge',
      'solana-dex-volume-flips-ethereum',
      'ai-crypto-convergence-100b-market',
      'real-world-assets-tokenization-revolution'
    )
    """
  end
end