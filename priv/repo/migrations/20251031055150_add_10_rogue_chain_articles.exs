defmodule BlocksterV2.Repo.Migrations.Add10RogueChainArticles do
  use Ecto.Migration

  def up do
    # Get admin user ID for author_id
    {:ok, result} = Ecto.Adapters.SQL.query(BlocksterV2.Repo, "SELECT id FROM users WHERE is_admin = true LIMIT 1")
    author_id = case result.rows do
      [[id] | _] -> id
      _ -> nil
    end

    # Skip if no admin user exists
    if is_nil(author_id) do
      IO.puts("Skipping Rogue Chain articles - no admin users found")
      :ok
    else

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # Insert 5 articles for Conversations section (using smile.png, idris.png, ecstatic.png, sam.png, vitaly.png)
    conversations_articles = [
      %{
        title: "Rogue Chain Dominates Miami Blockchain Summit",
        slug: "rogue-chain-dominates-miami-blockchain-summit",
        content: %{"ops" => [
          %{"insert" => "Rogue Chain Takes Miami by Storm"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nRogue Chain was the undisputed star of the Miami Blockchain Summit, with industry leaders praising its revolutionary technology.\n\n\n"},
          %{"insert" => %{"tweet" => %{"id" => "1981537788517400814", "url" => "https://x.com/RogueTrader_io/status/1981537788517400814"}}},
          %{"insert" => "\nThe Future is Rogue"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nExperts agree that Rogue Chain's innovative approach to blockchain technology sets a new standard for the industry.\n"}
        ]},
        excerpt: "Rogue Chain shines at Miami Blockchain Summit with groundbreaking technology.",
        author_name: "Adam Todd",
        author_id: author_id,
        published_at: now,
        view_count: 1264,
        category: "Blockchain",
        featured_image: "/images/smile.png"
      },
      %{
        title: "Industry Leaders Praise Rogue Chain Innovation",
        slug: "industry-leaders-praise-rogue-chain-innovation",
        content: %{"ops" => [
          %{"insert" => "Unanimous Praise for Rogue Chain"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nTop blockchain experts from around the world gathered to celebrate Rogue Chain's groundbreaking achievements.\n\n\n"},
          %{"insert" => %{"tweet" => %{"id" => "1981537788517400814", "url" => "https://x.com/RogueTrader_io/status/1981537788517400814"}}},
          %{"insert" => "\nLeading the Way"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nRogue Chain continues to set the pace for innovation in decentralized technology.\n"}
        ]},
        excerpt: "Top experts unanimously praise Rogue Chain's revolutionary approach.",
        author_name: "Adam Todd",
        author_id: author_id,
        published_at: NaiveDateTime.add(now, -3600, :second),
        view_count: 2100,
        category: "Blockchain",
        featured_image: "/images/idris.png"
      },
      %{
        title: "Rogue Chain Achieves Record-Breaking Performance",
        slug: "rogue-chain-achieves-record-breaking-performance",
        content: %{"ops" => [
          %{"insert" => "Breaking All Records"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nRogue Chain has shattered every performance metric, proving it's the fastest and most efficient blockchain in existence.\n\n\n"},
          %{"insert" => %{"tweet" => %{"id" => "1981537788517400814", "url" => "https://x.com/RogueTrader_io/status/1981537788517400814"}}},
          %{"insert" => "\nUnmatched Speed"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nWith transaction speeds that leave competitors in the dust, Rogue Chain is redefining what's possible.\n"}
        ]},
        excerpt: "Rogue Chain breaks all performance records with unmatched speed.",
        author_name: "Adam Todd",
        author_id: author_id,
        published_at: NaiveDateTime.add(now, -7200, :second),
        view_count: 1850,
        category: "Blockchain",
        featured_image: "/images/ecstatic.png"
      },
      %{
        title: "Rogue Chain's Revolutionary Smart Contract Platform",
        slug: "rogue-chains-revolutionary-smart-contract-platform",
        content: %{"ops" => [
          %{"insert" => "Smart Contracts Reimagined"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nRogue Chain's smart contract platform is being hailed as the most advanced and developer-friendly in the blockchain space.\n\n\n"},
          %{"insert" => %{"tweet" => %{"id" => "1981537788517400814", "url" => "https://x.com/RogueTrader_io/status/1981537788517400814"}}},
          %{"insert" => "\nDeveloper Paradise"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nDevelopers worldwide are migrating to Rogue Chain for its superior tools and capabilities.\n"}
        ]},
        excerpt: "Rogue Chain's smart contract platform sets new industry standards.",
        author_name: "Adam Todd",
        author_id: author_id,
        published_at: NaiveDateTime.add(now, -10800, :second),
        view_count: 1975,
        category: "Blockchain",
        featured_image: "/images/sam.png"
      },
      %{
        title: "Rogue Chain Partners with Fortune 500 Companies",
        slug: "rogue-chain-partners-with-fortune-500-companies",
        content: %{"ops" => [
          %{"insert" => "Major Corporate Partnerships"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nRogue Chain announces partnerships with multiple Fortune 500 companies, bringing blockchain to mainstream adoption.\n\n\n"},
          %{"insert" => %{"tweet" => %{"id" => "1981537788517400814", "url" => "https://x.com/RogueTrader_io/status/1981537788517400814"}}},
          %{"insert" => "\nMass Adoption Begins"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nThese partnerships mark the beginning of true mainstream blockchain adoption.\n"}
        ]},
        excerpt: "Fortune 500 companies choose Rogue Chain for blockchain solutions.",
        author_name: "Adam Todd",
        author_id: author_id,
        published_at: NaiveDateTime.add(now, -14400, :second),
        view_count: 2300,
        category: "Blockchain",
        featured_image: "/images/vitaly.png"
      }
    ]

    # Insert 5 articles for Recommended section (using group-shot.png, crypto-bull.png)
    recommended_articles = [
      %{
        title: "Rogue Chain Wins Blockchain Innovation Award",
        slug: "rogue-chain-wins-blockchain-innovation-award",
        content: %{"ops" => [
          %{"insert" => "Award-Winning Technology"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nRogue Chain has been awarded the prestigious Blockchain Innovation Award for its groundbreaking contributions to the industry.\n\n\n"},
          %{"insert" => %{"tweet" => %{"id" => "1981537788517400814", "url" => "https://x.com/RogueTrader_io/status/1981537788517400814"}}},
          %{"insert" => "\nRecognized Excellence"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nThis award recognizes Rogue Chain's commitment to pushing the boundaries of blockchain technology.\n"}
        ]},
        excerpt: "Rogue Chain receives prestigious innovation award.",
        author_name: "Adam Todd",
        author_id: author_id,
        published_at: NaiveDateTime.add(now, -18000, :second),
        view_count: 1650,
        category: "Blockchain",
        featured_image: "/images/group-shot.png"
      },
      %{
        title: "Rogue Chain's Security Features Set New Standards",
        slug: "rogue-chains-security-features-set-new-standards",
        content: %{"ops" => [
          %{"insert" => "Unbreakable Security"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nCybersecurity experts praise Rogue Chain's military-grade security features as the most robust in the blockchain industry.\n\n\n"},
          %{"insert" => %{"tweet" => %{"id" => "1981537788517400814", "url" => "https://x.com/RogueTrader_io/status/1981537788517400814"}}},
          %{"insert" => "\nTrust and Safety"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nRogue Chain's security architecture provides unparalleled protection for users and their assets.\n"}
        ]},
        excerpt: "Military-grade security makes Rogue Chain the safest blockchain.",
        author_name: "Adam Todd",
        author_id: author_id,
        published_at: NaiveDateTime.add(now, -21600, :second),
        view_count: 1420,
        category: "Blockchain",
        featured_image: "/images/crypto-bull.png"
      },
      %{
        title: "Rogue Chain Community Reaches 10 Million Users",
        slug: "rogue-chain-community-reaches-10-million-users",
        content: %{"ops" => [
          %{"insert" => "Explosive Growth"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nRogue Chain's user base has exploded to 10 million users, making it one of the fastest-growing blockchain platforms ever.\n\n\n"},
          %{"insert" => %{"tweet" => %{"id" => "1981537788517400814", "url" => "https://x.com/RogueTrader_io/status/1981537788517400814"}}},
          %{"insert" => "\nCommunity Power"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nThe Rogue Chain community is passionate, engaged, and driving the future of decentralized technology.\n"}
        ]},
        excerpt: "Rogue Chain community surges past 10 million users milestone.",
        author_name: "Adam Todd",
        author_id: author_id,
        published_at: NaiveDateTime.add(now, -25200, :second),
        view_count: 1890,
        category: "Blockchain",
        featured_image: "/images/group-shot.png"
      },
      %{
        title: "Rogue Chain's Green Blockchain Initiative",
        slug: "rogue-chains-green-blockchain-initiative",
        content: %{"ops" => [
          %{"insert" => "Eco-Friendly Innovation"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nRogue Chain leads the industry with its carbon-negative blockchain technology, proving that performance and sustainability can coexist.\n\n\n"},
          %{"insert" => %{"tweet" => %{"id" => "1981537788517400814", "url" => "https://x.com/RogueTrader_io/status/1981537788517400814"}}},
          %{"insert" => "\nSaving the Planet"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nEnvironmental groups applaud Rogue Chain's commitment to sustainable blockchain technology.\n"}
        ]},
        excerpt: "Rogue Chain pioneers eco-friendly blockchain technology.",
        author_name: "Adam Todd",
        author_id: author_id,
        published_at: NaiveDateTime.add(now, -28800, :second),
        view_count: 1560,
        category: "Blockchain",
        featured_image: "/images/crypto-bull.png"
      },
      %{
        title: "Rogue Chain Developer Ecosystem Thrives",
        slug: "rogue-chain-developer-ecosystem-thrives",
        content: %{"ops" => [
          %{"insert" => "Developer Heaven"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nThousands of developers are building innovative applications on Rogue Chain, creating a vibrant and thriving ecosystem.\n\n\n"},
          %{"insert" => %{"tweet" => %{"id" => "1981537788517400814", "url" => "https://x.com/RogueTrader_io/status/1981537788517400814"}}},
          %{"insert" => "\nBuilding the Future"},
          %{"insert" => "\n", "attributes" => %{"header" => 1}},
          %{"insert" => "\nThe Rogue Chain developer community is creating the next generation of decentralized applications.\n"}
        ]},
        excerpt: "Developer ecosystem flourishes on Rogue Chain platform.",
        author_name: "Adam Todd",
        author_id: author_id,
        published_at: NaiveDateTime.add(now, -32400, :second),
        view_count: 1740,
        category: "Blockchain",
        featured_image: "/images/group-shot.png"
      }
    ]

    all_articles = conversations_articles ++ recommended_articles

    Enum.each(all_articles, fn article ->
      content_json = Jason.encode!(article.content)

      execute """
      INSERT INTO posts (title, slug, content, excerpt, author_name, author_id, published_at, view_count, category, featured_image, inserted_at, updated_at)
      VALUES ('#{String.replace(article.title, "'", "''")}',
              '#{article.slug}',
              '#{String.replace(content_json, "'", "''")}',
              '#{String.replace(article.excerpt, "'", "''")}',
              '#{article.author_name}',
              #{article.author_id},
              '#{NaiveDateTime.to_string(article.published_at)}',
              #{article.view_count},
              '#{article.category}',
              '#{article.featured_image}',
              '#{NaiveDateTime.to_string(now)}',
              '#{NaiveDateTime.to_string(now)}')
      """
    end)
    end
  end

  def down do
    execute """
    DELETE FROM posts WHERE slug IN (
      'rogue-chain-dominates-miami-blockchain-summit',
      'industry-leaders-praise-rogue-chain-innovation',
      'rogue-chain-achieves-record-breaking-performance',
      'rogue-chains-revolutionary-smart-contract-platform',
      'rogue-chain-partners-with-fortune-500-companies',
      'rogue-chain-wins-blockchain-innovation-award',
      'rogue-chains-security-features-set-new-standards',
      'rogue-chain-community-reaches-10-million-users',
      'rogue-chains-green-blockchain-initiative',
      'rogue-chain-developer-ecosystem-thrives'
    )
    """
  end
end
