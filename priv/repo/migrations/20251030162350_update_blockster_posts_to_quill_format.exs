defmodule BlocksterV2.Repo.Migrations.UpdateBlocksterPostsToQuillFormat do
  use Ecto.Migration

  def up do
    # Update Edge & Node article
    execute """
    UPDATE posts
    SET content = '{"ops": [
      {"insert": "Edge & Node, the founding team behind The Graph, introduced ampersend for autonomous agent management and oversight.\\n\\n"},
      {"insert": {"tweet": {"id": "1983684665547616641", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">Everyone talks about agents, but are we actually using them in our daily lives?<br><br>Excited to dig in tomorrow with folks from <a href=\\"https://twitter.com/edgeandnode?ref_src=twsrc%5Etfw\\">@edgeandnode</a>, <a href=\\"https://twitter.com/ethereum?ref_src=twsrc%5Etfw\\">@ethereum</a>, <a href=\\"https://twitter.com/Google?ref_src=twsrc%5Etfw\\">@google</a>, and <a href=\\"https://twitter.com/coinbase?ref_src=twsrc%5Etfw\\">@coinbase</a>.<a href=\\"https://twitter.com/hashtag/ERC?src=hash&amp;ref_src=twsrc%5Etfw\\">#ERC</a>-8004 <a href=\\"https://t.co/BZIKIUumu9\\">https://t.co/BZIKIUumu9</a></p>&mdash; Marco De Rossi (@marco_derossi) <a href=\\"https://twitter.com/marco_derossi/status/1983684665547616641?ref_src=twsrc%5Etfw\\">October 29, 2025</a></blockquote>"}}},
      {"insert": "\\n"},
      {"insert": {"tweet": {"id": "1983655129393016964", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">New Speaker Announcement: Jordan Ellis from <a href=\\"https://twitter.com/googlecloud?ref_src=twsrc%5Etfw\\">@googlecloud</a> <br><br>Tomorrow, during our livestream on agentic economies, Jordan will dive into <a href=\\"https://twitter.com/Google?ref_src=twsrc%5Etfw\\">@Google</a> A2A protocol and what it brings for the agentic future.<br><br>RSVP ⬇️ <a href=\\"https://t.co/nzn5Bsv2mN\\">https://t.co/nzn5Bsv2mN</a> <a href=\\"https://t.co/1UwG2IWGm5\\">pic.twitter.com/1UwG2IWGm5</a></p>&mdash; Edge &amp; Node (@edgeandnode) <a href=\\"https://twitter.com/edgeandnode/status/1983655129393016964?ref_src=twsrc%5Etfw\\">October 29, 2025</a></blockquote>"}}},
      {"insert": "\\n"}
    ]}'
    WHERE slug = 'edge-node-launches-ampersend-control-layer-ai-agent-economy';
    """

    # Update Mono Protocol article
    execute """
    UPDATE posts
    SET content = '{"ops": [
      {"insert": "Presale gains traction merging multi-chain innovation with community rewards and transparent blockchain progress in DeFi.\\n\\n"},
      {"insert": {"tweet": {"id": "1983559494303994251", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">Mono Protocol unifies per-token balances across chains and delivers instant, MEV-resilient execution – making Web3 feel like one seamless network.<br><br>By abstracting liquidity and infrastructure, Mono reduces costs, boosts user retention, and unlocks monetizable network effects for… <a href=\\"https://t.co/ufKZD1Quux\\">pic.twitter.com/ufKZD1Quux</a></p>&mdash; Mono Protocol (@mono_protocol) <a href=\\"https://twitter.com/mono_protocol/status/1983559494303994251?ref_src=twsrc%5Etfw\\">October 29, 2025</a></blockquote>"}}},
      {"insert": "\\n"},
      {"insert": {"tweet": {"id": "1983151929216938276", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">Stage 15 is live! ⚡️<br><br>👉 Join now: <a href=\\"https://t.co/obFjr3Pfe2\\">https://t.co/obFjr3Pfe2</a> <a href=\\"https://t.co/4uBHQhA3F2\\">pic.twitter.com/4uBHQhA3F2</a></p>&mdash; Mono Protocol (@mono_protocol) <a href=\\"https://twitter.com/mono_protocol/status/1983151929216938276?ref_src=twsrc%5Etfw\\">October 28, 2025</a></blockquote>"}}},
      {"insert": "\\n"},
      {"insert": {"tweet": {"id": "1976295651907449095", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">Most apps only support a handful of tokens and chains – creating friction and slowing adoption.<br>Mono Protocol abstracts away the complexity: one account, one balance, one click.<br><br>Users can pay in any token, on any supported chain, instantly and reliably.<br>Build apps that work… <a href=\\"https://t.co/bTYx7xF2oI\\">pic.twitter.com/bTYx7xF2oI</a></p>&mdash; Mono Protocol (@mono_protocol) <a href=\\"https://twitter.com/mono_protocol/status/1976295651907449095?ref_src=twsrc%5Etfw\\">October 9, 2025</a></blockquote>"}}},
      {"insert": "\\n"}
    ]}'
    WHERE slug = 'mono-protocol-presale-stage-15-multi-chain-innovation';
    """

    # Update Mass & MoonPay article
    execute """
    UPDATE posts
    SET content = '{"ops": [
      {"insert": "Mass self-custodial crypto super-app partnered with MoonPay enabling instant bank-to-wallet transfers via Virtual Accounts powered by Iron.\\n\\n"},
      {"insert": {"tweet": {"id": "1983911738891173992", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">go from TradFi to DeFi in a single transfer with Virtual Accounts<br><br>⚡️ instantly fund your non-custodial wallet via ACH, Wire, or SEPA<br><br>⛓️ supports SOL, ETH, BASE, and ARB<br><br>💸 onramp, trade, send, and offramp 24/7/365<br><br>now live in <a href=\\"https://twitter.com/massdotmoney?ref_src=twsrc%5Etfw\\">@massdotmoney</a>, powered by <a href=\\"https://twitter.com/iron?ref_src=twsrc%5Etfw\\">@iron</a> <a href=\\"https://t.co/eBwEo8mwbF\\">pic.twitter.com/eBwEo8mwbF</a></p>&mdash; MoonPay 🟣 (@moonpay) <a href=\\"https://twitter.com/moonpay/status/1983911738891173992?ref_src=twsrc%5Etfw\\">October 30, 2025</a></blockquote>"}}},
      {"insert": "\\n"}
    ]}'
    WHERE slug = 'mass-moonpay-bank-to-defi-instant-virtual-accounts';
    """

    # Update Nansen article
    execute """
    UPDATE posts
    SET content = '{"ops": [
      {"insert": "Nansen has officially integrated with Plasma — the Layer 1 designed for global USD₮ payments — unlocking real-time growth dashboards, smart-money tracking, token intelligence, wallet activity analytics.\\n\\n"},
      {"insert": {"tweet": {"id": "1983836612380520676", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">We are excited to announce that our integration with <a href=\\"https://twitter.com/Plasma?ref_src=twsrc%5Etfw\\">@Plasma</a> is now live!<br><br>Plasma is building a global-scale network for USD₮ payments.<br><br>Now you can see that growth onchain with Nansen. 👇 <a href=\\"https://t.co/DAFqxXWMK5\\">pic.twitter.com/DAFqxXWMK5</a></p>&mdash; Nansen 🧭 (@nansen_ai) <a href=\\"https://twitter.com/nansen_ai/status/1983836612380520676?ref_src=twsrc%5Etfw\\">October 30, 2025</a></blockquote>"}}},
      {"insert": "\\n"}
    ]}'
    WHERE slug = 'nansen-full-on-chain-intelligence-plasma-stablecoin';
    """

    # Update KapKap article
    execute """
    UPDATE posts
    SET content = '{"ops": [
      {"insert": "AI-native Web3 platform raised $10 million to scale intelligent value systems and expand major IP partnerships across gaming and Web3 culture.\\n\\n"},
      {"insert": {"tweet": {"id": "1983007351184732449", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">⛏️ Dig. Earn. Repeat. — GenkiMiner x KapKap<br><br>Focus on mining and collect 💎 diamonds, 🔑 keys, 🎁 treasure chests &amp; 🪙 points — all convertible into USDT and withdraw anytime.<br><br>Explore the Artifacts section too:<br>50 different pickaxes with random rewards<br>Generate daily income or… <a href=\\"https://t.co/3fqaGOWx88\\">pic.twitter.com/3fqaGOWx88</a></p>&mdash; Kapkap Hub (@Kapkap_Hub) <a href=\\"https://twitter.com/Kapkap_Hub/status/1983007351184732449?ref_src=twsrc%5Etfw\\">October 28, 2025</a></blockquote>"}}},
      {"insert": "\\n"},
      {"insert": {"tweet": {"id": "1981222442556412177", "html": "<blockquote class=\\"twitter-tweet\\"><p lang=\\"en\\" dir=\\"ltr\\">🎮 Every Effort Counts on KapKap with KAPS<br><br>Too many times... No credit for your time as a player, no recognition for your creative contributions, no way to reach the right audience for your game.<br><br>KapKap changes that with KAPS — Gameplay + Achievements + Influence 👇<br>Qualified… <a href=\\"https://t.co/IV0ikS4GCh\\">pic.twitter.com/IV0ikS4GCh</a></p>&mdash; Kapkap Hub (@Kapkap_Hub) <a href=\\"https://twitter.com/Kapkap_Hub/status/1981222442556412177?ref_src=twsrc%5Etfw\\">October 23, 2025</a></blockquote>"}}},
      {"insert": "\\n"}
    ]}'
    WHERE slug = 'kapkap-secures-10m-ai-native-attention-economy';
    """
  end

  def down do
    # Revert back to blocks format if needed
    execute """
    UPDATE posts
    SET content = content
    WHERE slug IN (
      'edge-node-launches-ampersend-control-layer-ai-agent-economy',
      'mono-protocol-presale-stage-15-multi-chain-innovation',
      'mass-moonpay-bank-to-defi-instant-virtual-accounts',
      'nansen-full-on-chain-intelligence-plasma-stablecoin',
      'kapkap-secures-10m-ai-native-attention-economy'
    );
    """
  end
end