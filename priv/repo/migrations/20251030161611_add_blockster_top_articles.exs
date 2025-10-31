defmodule BlocksterV2.Repo.Migrations.AddBlocksterTopArticles do
  use Ecto.Migration

  def up do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Parse dates properly
    date1 = ~U[2025-10-30 15:45:00Z]
    date2 = ~U[2025-10-30 14:30:00Z]
    date3 = ~U[2025-10-30 13:15:00Z]
    date4 = ~U[2025-10-30 12:00:00Z]
    date5 = ~U[2025-10-30 10:45:00Z]

    execute """
    INSERT INTO posts (title, slug, content, excerpt, author_name, published_at, category, featured_image, layout, view_count, inserted_at, updated_at)
    VALUES
    (
      'Edge & Node Launches ampersend, a Control Layer for the Coming AI-Agent Economy',
      'edge-node-launches-ampersend-control-layer-ai-agent-economy',
      '{"blocks": [
        {"type": "paragraph", "data": {"text": "Edge & Node, the founding team behind The Graph, introduced ampersend for autonomous agent management and oversight."}},
        {"type": "tweet", "data": {"html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">Everyone talks about agents, but are we actually using them in our daily lives?<br><br>Excited to dig in tomorrow with folks from <a href=\\"https://twitter.com/edgeandnode?ref_src=twsrc%5Etfw\\">@edgeandnode</a>, <a href=\\"https://twitter.com/ethereum?ref_src=twsrc%5Etfw\\">@ethereum</a>, <a href=\\"https://twitter.com/Google?ref_src=twsrc%5Etfw\\">@google</a>, and <a href=\\"https://twitter.com/coinbase?ref_src=twsrc%5Etfw\\">@coinbase</a>.<a href=\\"https://twitter.com/hashtag/ERC?src=hash&amp;ref_src=twsrc%5Etfw\\">#ERC</a>-8004 <a href=\\"https://t.co/BZIKIUumu9\\">https://t.co/BZIKIUumu9</a></p>&mdash; Marco De Rossi (@marco_derossi) <a href=\\"https://twitter.com/marco_derossi/status/1983684665547616641?ref_src=twsrc%5Etfw\\">October 29, 2025</a></blockquote>", "tweetId": "1983684665547616641"}},
        {"type": "tweet", "data": {"html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">New Speaker Announcement: Jordan Ellis from <a href=\\"https://twitter.com/googlecloud?ref_src=twsrc%5Etfw\\">@googlecloud</a> <br><br>Tomorrow, during our livestream on agentic economies, Jordan will dive into <a href=\\"https://twitter.com/Google?ref_src=twsrc%5Etfw\\">@Google</a> A2A protocol and what it brings for the agentic future.<br><br>RSVP ⬇️ <a href=\\"https://t.co/nzn5Bsv2mN\\">https://t.co/nzn5Bsv2mN</a> <a href=\\"https://t.co/1UwG2IWGm5\\">pic.twitter.com/1UwG2IWGm5</a></p>&mdash; Edge &amp; Node (@edgeandnode) <a href=\\"https://twitter.com/edgeandnode/status/1983655129393016964?ref_src=twsrc%5Etfw\\">October 29, 2025</a></blockquote>", "tweetId": "1983655129393016964"}}
      ]}',
      'Edge & Node, the founding team behind The Graph, introduced ampersend for autonomous agent management and oversight.',
      'Lidia Yadlos',
      '#{DateTime.to_iso8601(date1)}',
      'People',
      'https://ik.imagekit.io/blockster/63fad1d7-8813-410a-aeba-fbe243c036eb.png',
      'v2',
      32,
      '#{DateTime.to_iso8601(now)}',
      '#{DateTime.to_iso8601(now)}'
    ),
    (
      'Mono Protocol Presale Stage 15 Gains Momentum With Multi-Chain Innovation, Rewards Hub & Bonus',
      'mono-protocol-presale-stage-15-multi-chain-innovation',
      '{"blocks": [
        {"type": "paragraph", "data": {"text": "Presale gains traction merging multi-chain innovation with community rewards and transparent blockchain progress in DeFi."}},
        {"type": "tweet", "data": {"html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">Mono Protocol unifies per-token balances across chains and delivers instant, MEV-resilient execution – making Web3 feel like one seamless network.<br><br>By abstracting liquidity and infrastructure, Mono reduces costs, boosts user retention, and unlocks monetizable network effects for… <a href=\\"https://t.co/ufKZD1Quux\\">pic.twitter.com/ufKZD1Quux</a></p>&mdash; Mono Protocol (@mono_protocol) <a href=\\"https://twitter.com/mono_protocol/status/1983559494303994251?ref_src=twsrc%5Etfw\\">October 29, 2025</a></blockquote>", "tweetId": "1983559494303994251"}},
        {"type": "tweet", "data": {"html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">Stage 15 is live! ⚡️<br><br>👉 Join now: <a href=\\"https://t.co/obFjr3Pfe2\\">https://t.co/obFjr3Pfe2</a> <a href=\\"https://t.co/4uBHQhA3F2\\">pic.twitter.com/4uBHQhA3F2</a></p>&mdash; Mono Protocol (@mono_protocol) <a href=\\"https://twitter.com/mono_protocol/status/1983151929216938276?ref_src=twsrc%5Etfw\\">October 28, 2025</a></blockquote>", "tweetId": "1983151929216938276"}},
        {"type": "tweet", "data": {"html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">Most apps only support a handful of tokens and chains – creating friction and slowing adoption.<br>Mono Protocol abstracts away the complexity: one account, one balance, one click.<br><br>Users can pay in any token, on any supported chain, instantly and reliably.<br>Build apps that work… <a href=\\"https://t.co/bTYx7xF2oI\\">pic.twitter.com/bTYx7xF2oI</a></p>&mdash; Mono Protocol (@mono_protocol) <a href=\\"https://twitter.com/mono_protocol/status/1976295651907449095?ref_src=twsrc%5Etfw\\">October 9, 2025</a></blockquote>", "tweetId": "1976295651907449095"}}
      ]}',
      'Presale gains traction merging multi-chain innovation with community rewards and transparent blockchain progress in DeFi.',
      'Lidia Yadlos',
      '#{DateTime.to_iso8601(date2)}',
      'Tech',
      'https://ik.imagekit.io/blockster/4a900ac2-00cb-4bc1-9524-daf61277c88e.png',
      'v2',
      1516,
      '#{DateTime.to_iso8601(now)}',
      '#{DateTime.to_iso8601(now)}'
    ),
    (
      'Mass & MoonPay Make Bank-to-DeFi Transfers Instant With Virtual Accounts',
      'mass-moonpay-bank-to-defi-instant-virtual-accounts',
      '{"blocks": [
        {"type": "paragraph", "data": {"text": "Mass self-custodial crypto super-app partnered with MoonPay enabling instant bank-to-wallet transfers via Virtual Accounts powered by Iron."}},
        {"type": "tweet", "data": {"html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">go from TradFi to DeFi in a single transfer with Virtual Accounts<br><br>⚡️ instantly fund your non-custodial wallet via ACH, Wire, or SEPA<br><br>⛓️ supports SOL, ETH, BASE, and ARB<br><br>💸 onramp, trade, send, and offramp 24/7/365<br><br>now live in <a href=\\"https://twitter.com/massdotmoney?ref_src=twsrc%5Etfw\\">@massdotmoney</a>, powered by <a href=\\"https://twitter.com/iron?ref_src=twsrc%5Etfw\\">@iron</a> <a href=\\"https://t.co/eBwEo8mwbF\\">pic.twitter.com/eBwEo8mwbF</a></p>&mdash; MoonPay 🟣 (@moonpay) <a href=\\"https://twitter.com/moonpay/status/1983911738891173992?ref_src=twsrc%5Etfw\\">October 30, 2025</a></blockquote>", "tweetId": "1983911738891173992"}}
      ]}',
      'Mass self-custodial crypto super-app partnered with MoonPay enabling instant bank-to-wallet transfers via Virtual Accounts powered by Iron.',
      'Lidia Yadlos',
      '#{DateTime.to_iso8601(date3)}',
      'Business',
      'https://ik.imagekit.io/blockster/2883f9c9-ab16-4d56-aa2b-4667f7eeb421.png',
      'v2',
      303,
      '#{DateTime.to_iso8601(now)}',
      '#{DateTime.to_iso8601(now)}'
    ),
    (
      'Nansen Brings Full On-Chain Intelligence Stack to Plasma as Stablecoin Layer-1 Surges',
      'nansen-full-on-chain-intelligence-plasma-stablecoin',
      '{"blocks": [
        {"type": "paragraph", "data": {"text": "Nansen has officially integrated with Plasma — the Layer 1 designed for global USD₮ payments — unlocking real-time growth dashboards, smart-money tracking, token intelligence, wallet activity analytics."}},
        {"type": "tweet", "data": {"html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">We are excited to announce that our integration with <a href=\\"https://twitter.com/Plasma?ref_src=twsrc%5Etfw\\">@Plasma</a> is now live!<br><br>Plasma is building a global-scale network for USD₮ payments.<br><br>Now you can see that growth onchain with Nansen. 👇 <a href=\\"https://t.co/DAFqxXWMK5\\">pic.twitter.com/DAFqxXWMK5</a></p>&mdash; Nansen 🧭 (@nansen_ai) <a href=\\"https://twitter.com/nansen_ai/status/1983836612380520676?ref_src=twsrc%5Etfw\\">October 30, 2025</a></blockquote>", "tweetId": "1983836612380520676"}}
      ]}',
      'Nansen has officially integrated with Plasma — the Layer 1 designed for global USD₮ payments — unlocking real-time growth dashboards, smart-money tracking, token intelligence, wallet activity analytics.',
      'Lidia Yadlos',
      '#{DateTime.to_iso8601(date4)}',
      'Tech',
      'https://ik.imagekit.io/blockster/18a232ce-16ad-4edb-877d-9a668450731d.png',
      'v2',
      1503,
      '#{DateTime.to_iso8601(now)}',
      '#{DateTime.to_iso8601(now)}'
    ),
    (
      'KapKap Secures $10M to Build the AI-Native Attention Economy — Backed by Animoca, Shima & Mechanism',
      'kapkap-secures-10m-ai-native-attention-economy',
      '{"blocks": [
        {"type": "paragraph", "data": {"text": "AI-native Web3 platform raised $10 million to scale intelligent value systems and expand major IP partnerships across gaming and Web3 culture."}},
        {"type": "tweet", "data": {"html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">⛏️ Dig. Earn. Repeat. — GenkiMiner x KapKap<br><br>Focus on mining and collect 💎 diamonds, 🔑 keys, 🎁 treasure chests &amp; 🪙 points — all convertible into USDT and withdraw anytime.<br><br>Explore the Artifacts section too:<br>50 different pickaxes with random rewards<br>Generate daily income or… <a href=\\"https://t.co/3fqaGOWx88\\">pic.twitter.com/3fqaGOWx88</a></p>&mdash; Kapkap Hub (@Kapkap_Hub) <a href=\\"https://twitter.com/Kapkap_Hub/status/1983007351184732449?ref_src=twsrc%5Etfw\\">October 28, 2025</a></blockquote>", "tweetId": "1983007351184732449"}},
        {"type": "tweet", "data": {"html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">🎮 Every Effort Counts on KapKap with KAPS<br><br>Too many times... No credit for your time as a player, no recognition for your creative contributions, no way to reach the right audience for your game.<br><br>KapKap changes that with KAPS — Gameplay + Achievements + Influence 👇<br>Qualified… <a href=\\"https://t.co/IV0ikS4GCh\\">pic.twitter.com/IV0ikS4GCh</a></p>&mdash; Kapkap Hub (@Kapkap_Hub) <a href=\\"https://twitter.com/Kapkap_Hub/status/1981222442556412177?ref_src=twsrc%5Etfw\\">October 23, 2025</a></blockquote>", "tweetId": "1981222442556412177"}}
      ]}',
      'AI-native Web3 platform raised $10 million to scale intelligent value systems and expand major IP partnerships across gaming and Web3 culture.',
      'Lidia Yadlos',
      '#{DateTime.to_iso8601(date5)}',
      'Gaming',
      'https://ik.imagekit.io/blockster/df386fd7-2d8c-49c2-8cfe-359fb519a5df.png',
      'v2',
      357,
      '#{DateTime.to_iso8601(now)}',
      '#{DateTime.to_iso8601(now)}'
    )
    """
  end

  def down do
    execute """
    DELETE FROM posts WHERE slug IN (
      'edge-node-launches-ampersend-control-layer-ai-agent-economy',
      'mono-protocol-presale-stage-15-multi-chain-innovation',
      'mass-moonpay-bank-to-defi-instant-virtual-accounts',
      'nansen-full-on-chain-intelligence-plasma-stablecoin',
      'kapkap-secures-10m-ai-native-attention-economy'
    )
    """
  end
end