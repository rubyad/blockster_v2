# Seed a test article with rich content for typography verification
#
# Run with: mix run priv/repo/seeds_test_article.exs

alias BlocksterV2.Repo
alias BlocksterV2.Blog.{Post, Hub, Category, Tag}
import Ecto.Query

# Find or create a hub
hub = Repo.one(from h in Hub, where: h.is_active == true, limit: 1)

hub =
  hub ||
    Repo.insert!(%Hub{
      name: "Moonpay",
      tag_name: "moonpay",
      slug: "moonpay",
      color_primary: "#7D00FF",
      color_secondary: "#4A00B8",
      description: "Global payments infrastructure",
      is_active: true
    })

# Find or create a category
category = Repo.one(from c in Category, where: c.slug == "defi", limit: 1)

category =
  category ||
    Repo.insert!(%Category{
      name: "DeFi",
      slug: "defi"
    })

# Find or create tags
find_or_create_tag = fn name, slug ->
  Repo.one(from t in Tag, where: t.slug == ^slug) ||
    Repo.insert!(%Tag{name: name, slug: slug})
end

tag_solana = find_or_create_tag.("Solana", "solana")
tag_defi = find_or_create_tag.("DeFi", "defi")
tag_lp = find_or_create_tag.("Liquidity", "liquidity")

# Delete existing test article if present
Repo.delete_all(from p in Post, where: p.slug == "the-quiet-revolution-of-onchain-liquidity-pools")

# TipTap JSON content with all formatting elements
content = %{
  "type" => "doc",
  "content" => [
    # Paragraph 1 — will get drop cap on first letter
    %{"type" => "paragraph", "content" => [
      %{"type" => "text", "text" => "For most of the last decade, gambling sites operated like banks — opaque, custodial, built on the unspoken assumption that the house would always have the deeper pocket. The model worked because the friction of moving money in and out was high enough that nobody bothered to ask where it actually lived. That assumption is now breaking down, and faster than the operators are willing to "},
      %{"type" => "text", "text" => "admit publicly", "marks" => [%{"type" => "link", "attrs" => %{"href" => "https://blockster.com"}}]},
      %{"type" => "text", "text" => "."}
    ]},

    # Paragraph 2
    %{"type" => "paragraph", "content" => [
      %{"type" => "text", "text" => "The pieces are mundane on their own. A vault that holds SOL. A second vault that holds a stablecoin. An LP token representing a share of each. A program that takes a bet, rolls a number, and pays out from the vault that matches the wager's denomination. None of this is novel — "},
      %{"type" => "text", "text" => "Uniswap", "marks" => [%{"type" => "link", "attrs" => %{"href" => "https://uniswap.org"}}]},
      %{"type" => "text", "text" => " and Compound shipped variants of every idea here years ago. What is novel is the assembly. When all of those pieces sit together inside a single Solana program, the bankroll stops being a service operated by a company and starts being an object operated by code."}
    ]},

    # Paragraph 3
    %{"type" => "paragraph", "content" => [
      %{"type" => "text", "text" => "The strangest part of all this isn't the technology — it's that the technology has been sitting on the shelf for years. Constant function market makers were a 2018 idea. Commit-reveal randomness was a 2019 idea. Liquid staking derivatives have been around since 2020. What was missing was a runtime fast enough and cheap enough to bind them together inside a single transaction without making the user wait. Solana solved that problem in production sometime around the middle of last year, and the people who noticed first are now shipping the second wave."}
    ]},

    # H2 heading
    %{"type" => "heading", "attrs" => %{"level" => 2}, "content" => [
      %{"type" => "text", "text" => "From house edge to house yield"}
    ]},

    # Paragraph 4
    %{"type" => "paragraph", "content" => [
      %{"type" => "text", "text" => "Anyone can deposit. Anyone can withdraw. The house edge becomes a public number, queryable by anyone with a wallet. And every player who funds the pool earns a share of every loss that flows through it. The inversion is subtle but consequential — losing players are no longer transferring wealth to a faceless casino; they are transferring it to the depositors who chose to take the other side of the trade."}
    ]},

    # Paragraph 5 — introduces the list
    %{"type" => "paragraph", "content" => [
      %{"type" => "text", "text" => "The shift looks small on paper. In practice, it pulls four things into the open that the old model deliberately hid:"}
    ]},

    # Bullet list
    %{"type" => "bulletList", "content" => [
      %{"type" => "listItem", "content" => [
        %{"type" => "paragraph", "content" => [
          %{"type" => "text", "text" => "The bankroll", "marks" => [%{"type" => "bold"}]},
          %{"type" => "text", "text" => " — its size, its composition, and its solvency, all queryable on chain in real time."}
        ]}
      ]},
      %{"type" => "listItem", "content" => [
        %{"type" => "paragraph", "content" => [
          %{"type" => "text", "text" => "The edge", "marks" => [%{"type" => "bold"}]},
          %{"type" => "text", "text" => " — encoded as a multiplier table inside the program, not buried in a regulator filing."}
        ]}
      ]},
      %{"type" => "listItem", "content" => [
        %{"type" => "paragraph", "content" => [
          %{"type" => "text", "text" => "The yield", "marks" => [%{"type" => "bold"}]},
          %{"type" => "text", "text" => " — distributed pro-rata to LPs every time a player loses, with no off-chain settlement."}
        ]}
      ]},
      %{"type" => "listItem", "content" => [
        %{"type" => "paragraph", "content" => [
          %{"type" => "text", "text" => "The risk", "marks" => [%{"type" => "bold"}]},
          %{"type" => "text", "text" => " — capped per bet, per game, per day, by parameters anyone can read before depositing."}
        ]}
      ]}
    ]},

    # Paragraph 6
    %{"type" => "paragraph", "content" => [
      %{"type" => "text", "text" => "There is a reason this matters now and not three years ago. "},
      %{"type" => "text", "text" => "Provably-fair systems", "marks" => [%{"type" => "link", "attrs" => %{"href" => "https://blockster.com"}}]},
      %{"type" => "text", "text" => " — the cryptographic commit-reveal dances that let a player verify the dice were honest — used to be a thing you read about in white papers and rarely saw in production. The friction was too high, the user experience too brittle, and the cost of every verification step prohibitive. With the latest generation of Anchor programs running on Solana's local fee market, that verification step costs less than a fraction of a cent and resolves in under a second. The barrier collapsed without anyone noticing."}
    ]},

    # H2 heading
    %{"type" => "heading", "attrs" => %{"level" => 2}, "content" => [
      %{"type" => "text", "text" => "The market makers are the players"}
    ]},

    # Paragraph 7
    %{"type" => "paragraph", "content" => [
      %{"type" => "text", "text" => "The result is a game that feels nothing like the old model. Players are no longer up against a hidden bankroll; they are up against other people's deposits, and when they win, they win them. When they lose, the pool grows, the yield compounds, and somewhere a college student with three SOL becomes a market maker for a game he might be playing tomorrow."}
    ]},

    # Paragraph 8
    %{"type" => "paragraph", "content" => [
      %{"type" => "text", "text" => "It is hard to overstate how much of a departure this is from the way the previous decade thought about gambling on chain. The early experiments were either too slow to be playable, or too custodial to be trustless, or both. The new generation of programs solves both problems by colocating the bet, the randomness, the payout, and the bankroll inside a single atomic transaction. Nothing leaves the chain. Nothing waits on a backend service to confirm a result. Nothing requires the player to trust the operator."}
    ]},

    # Paragraph with stats
    %{"type" => "paragraph", "content" => [
      %{"type" => "text", "text" => "The most striking demonstration came in February. A pool that started the month with eighteen SOL in liquidity ended it with two hundred and twelve, after roughly four thousand bets across the same dozen wallets. No marketing, no Telegram pump, no influencer promotion. Just a working contract and a handful of regulars. The depositors made forty-three percent on their capital. The players, in aggregate, lost twelve percent — about what you would expect from a game with a sub-one-percent house edge running at high enough volume."}
    ]},

    # Blockquote
    %{"type" => "blockquote", "content" => [
      %{"type" => "paragraph", "content" => [
        %{"type" => "text", "text" => "When the bankroll is the bank, the player becomes the house.", "marks" => [%{"type" => "italic"}]}
      ]},
      %{"type" => "paragraph", "content" => [
        %{"type" => "text", "text" => "— Anonymous LP, Pool #4421"}
      ]}
    ]},

    # Paragraph 9
    %{"type" => "paragraph", "content" => [
      %{"type" => "text", "text" => "None of this guarantees the model wins. There are obvious failure modes: a bad oracle, a sloppy multiplier table, an unbounded max-bet that lets a single whale drain a vault before the LPs can react. The teams shipping these programs know the failure modes and have spent the last eighteen months building "},
      %{"type" => "text", "text" => "guardrails", "marks" => [%{"type" => "link", "attrs" => %{"href" => "https://blockster.com"}}]},
      %{"type" => "text", "text" => " — per-difficulty bet caps, daily withdrawal limits, settler services that batch-confirm transactions before letting them touch the pool. The infrastructure is rough but it is real, and it is shipping."}
    ]},

    # H2 heading
    %{"type" => "heading", "attrs" => %{"level" => 2}, "content" => [
      %{"type" => "text", "text" => "What comes next"}
    ]},

    # Paragraph 10
    %{"type" => "paragraph", "content" => [
      %{"type" => "text", "text" => "The honest answer is that nobody knows. The pieces are all in production, the volume is real, and the depositors are getting paid. But the same was true of decentralized exchanges in 2020, and it took two more years and several public collapses before anything that looked like institutional capital showed up. The bankroll model is in roughly the same place that AMMs were before Curve and Balancer turned the architecture into something a stablecoin desk could underwrite."}
    ]},

    # Paragraph 11 — closing
    %{"type" => "paragraph", "content" => [
      %{"type" => "text", "text" => "What is happening, quietly, in production, on a chain that most regulators still don't know how to spell, is the early version of an industry rebuild. The legacy operators will not see it until the depositors who used to be their customers have already migrated. By then it will be too late to compete on edge. The only thing left to compete on will be trust — and trust, on chain, is a public number."}
    ]}
  ]
}

post =
  Repo.insert!(%Post{
    title: "The Quiet Revolution of On-Chain Liquidity Pools",
    slug: "the-quiet-revolution-of-onchain-liquidity-pools",
    excerpt: "How dual-vault bankrolls are rewriting the rules of provably-fair gaming on Solana — and why the next generation of LPs are funding their own trades.",
    content: content,
    featured_image: "https://images.unsplash.com/photo-1639762681485-074b7f938ba0?w=1600&q=80&auto=format&fit=crop",
    published_at: DateTime.utc_now() |> DateTime.truncate(:second),
    hub_id: hub.id,
    category_id: category.id,
    base_bux_reward: 50
  })

# Attach tags
Repo.insert_all("post_tags", [
  %{post_id: post.id, tag_id: tag_solana.id},
  %{post_id: post.id, tag_id: tag_defi.id},
  %{post_id: post.id, tag_id: tag_lp.id}
])

IO.puts("""
Test article created!

  Title: #{post.title}
  Slug:  #{post.slug}
  URL:   http://localhost:4000/#{post.slug}
  Hub:   #{hub.name}
  Cat:   #{category.name}
  Tags:  Solana, DeFi, Liquidity

Typography elements to verify:
  - Drop cap on first paragraph
  - 3 inline links (blue, underline on hover)
  - 3 H2 headings (Inter 700, 28px)
  - 1 bullet list (4 items, bold labels, left border)
  - 1 blockquote (lime left border, italic 22px)
  - 4 inline ad banners (follow_bar, dark_gradient, portrait, split_card)
  - 3 tags at bottom
""")
