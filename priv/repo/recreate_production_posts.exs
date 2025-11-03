defmodule RecreateProductionPosts do
  alias BlocksterV2.Repo
  alias BlocksterV2.Blog.{Post, Category, Tag}
  alias BlocksterV2.Accounts.User
  import Ecto.Query

  def run do
    IO.puts("Starting post recreation...")

    # Delete all existing posts
    delete_all_posts()

    # Get all categories
    categories = Repo.all(Category)

    # Get all tags
    all_tags = Repo.all(Tag)

    # Get authors
    authors = Repo.all(from u in User, where: u.is_author == true)

    if Enum.empty?(authors) do
      IO.puts("No authors found!")
      :error
    else
      # Create 10 posts for each category
      Enum.each(categories, fn category ->
        IO.puts("Creating posts for category: #{category.name}")
        create_posts_for_category(category, all_tags, authors, 10)
      end)

      IO.puts("Done! Created posts for all categories.")
    end
  end

  defp delete_all_posts do
    IO.puts("Deleting all existing posts...")
    {count, _} = Repo.delete_all(Post)
    IO.puts("Deleted #{count} posts")
  end

  defp create_posts_for_category(category, all_tags, authors, count) do
    Enum.each(1..count, fn index ->
      # Random date in last month
      days_ago = :rand.uniform(30)
      published_at = DateTime.utc_now() |> DateTime.add(-days_ago * 24 * 60 * 60, :second)

      # Pick 6 random tags
      tags = Enum.take_random(all_tags, 6)

      # Add Interview tag to some posts (roughly 1 in 9)
      tags = if rem(index, 9) == 0 do
        interview_tag = Enum.find(all_tags, fn t -> t.name == "Interview" end)
        if interview_tag, do: [interview_tag | tags] |> Enum.uniq(), else: tags
      else
        tags
      end

      # Random author
      author = Enum.random(authors)

      # Generate post data
      post_data = generate_post_data(category, index)

      # Create post
      {:ok, post} = %Post{}
      |> Post.changeset(%{
        title: post_data.title,
        slug: post_data.slug,
        content: post_data.content,
        excerpt: post_data.excerpt,
        featured_image: post_data.featured_image,
        published_at: published_at,
        author_id: author.id,
        category_id: category.id
      })
      |> Repo.insert()

      # Associate tags
      Enum.each(tags, fn tag ->
        Ecto.build_assoc(post, :post_tags, %{tag_id: tag.id})
        |> Repo.insert()
      end)

      IO.puts("  Created: #{post.title}")
    end)
  end

  defp generate_post_data(category, index) do
    # Generate fictional content based on category
    case category.slug do
      "blockchain" -> generate_blockchain_post(index)
      "market-analysis" -> generate_market_post(index)
      "investment" -> generate_investment_post(index)
      "events" -> generate_events_post(index)
      "crypto-trading" -> generate_trading_post(index)
      "people" -> generate_people_post(index)
      "defi" -> generate_defi_post(index)
      "announcements" -> generate_announcement_post(index)
      "gaming" -> generate_gaming_post(index)
      _ -> generate_default_post(category, index)
    end
  end

  defp generate_blockchain_post(index) do
    titles = [
      "Ethereum 3.0 Roadmap Unveiled by Vitalik Chen",
      "Polygon Launches ZK-Rollup Solution for Enterprise",
      "Solana Network Achieves Record 65,000 TPS",
      "Cardano Introduces Smart Contract Upgrade",
      "Avalanche Partners with Fortune 500 Companies",
      "Polkadot Unveils Parachain Auction Results",
      "Cosmos Launches Interchain Security Module",
      "Near Protocol Expands to European Markets",
      "Algorand Develops Quantum-Resistant Blockchain",
      "Tezos Implements Privacy-Focused Features"
    ]

    authors_names = ["Sarah Mitchell", "Dr. James Wong", "Alexandra Rivera", "Michael Chen"]

    title = Enum.at(titles, rem(index - 1, length(titles)))
    slug = title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.trim("-")
    author_name = Enum.random(authors_names)

    %{
      title: title,
      slug: slug,
      excerpt: "Major breakthrough in blockchain technology promises to revolutionize the industry with unprecedented scalability and security features.",
      featured_image: "https://blockster-images.s3.us-east-1.amazonaws.com/uploads/#{:rand.uniform(999999999)}-#{:rand.uniform(999999999999999999) |> Integer.to_string(16) |> String.downcase()}.webp",
      content: %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "paragraph",
            "content" => [
              %{
                "type" => "text",
                "text" => "In a groundbreaking development for the blockchain industry, ",
                "marks" => []
              },
              %{
                "type" => "text",
                "text" => "#{String.split(title, " ") |> Enum.take(3) |> Enum.join(" ")}",
                "marks" => [%{"type" => "bold"}]
              },
              %{
                "type" => "text",
                "text" => " has set a new benchmark for technological innovation.",
                "marks" => []
              }
            ]
          },
          %{"type" => "paragraph"},
          %{
            "type" => "heading",
            "attrs" => %{"level" => 2},
            "content" => [%{"type" => "text", "text" => "Revolutionary Technology"}]
          },
          %{
            "type" => "paragraph",
            "content" => [
              %{
                "type" => "text",
                "text" => "The new implementation introduces advanced cryptographic techniques that enhance both security and scalability. According to lead developer #{author_name}, this represents a quantum leap forward for distributed ledger technology."
              }
            ]
          },
          %{"type" => "paragraph"},
          %{
            "type" => "blockquote",
            "content" => [
              %{
                "type" => "paragraph",
                "content" => [%{"type" => "text", "text" => "This technology will fundamentally change how we think about blockchain scalability and security."}]
              },
              %{
                "type" => "paragraph",
                "content" => [%{"type" => "text", "text" => "— #{author_name}, Chief Technology Officer"}]
              }
            ]
          },
          %{"type" => "paragraph"},
          %{
            "type" => "heading",
            "attrs" => %{"level" => 2},
            "content" => [%{"type" => "text", "text" => "Key Features"}]
          },
          %{
            "type" => "bulletList",
            "content" => [
              %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Enhanced transaction throughput up to 100,000 TPS"}]}]},
              %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Reduced gas fees by 95%"}]}]},
              %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Improved smart contract efficiency"}]}]},
              %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Cross-chain interoperability"}]}]},
              %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Enterprise-grade security protocols"}]}]}
            ]
          },
          %{"type" => "paragraph"},
          %{
            "type" => "heading",
            "attrs" => %{"level" => 2},
            "content" => [%{"type" => "text", "text" => "Market Impact"}]
          },
          %{
            "type" => "paragraph",
            "content" => [
              %{
                "type" => "text",
                "text" => "Industry analysts predict this development will attract significant institutional investment and drive mainstream adoption. The technology addresses long-standing concerns about blockchain scalability while maintaining decentralization."
              }
            ]
          },
          %{"type" => "paragraph"},
          %{
            "type" => "paragraph",
            "content" => [
              %{
                "type" => "text",
                "text" => "Major corporations including tech giants and financial institutions have already expressed interest in implementing this solution for their blockchain infrastructure needs."
              }
            ]
          }
        ]
      }
    }
  end

  defp generate_market_post(index) do
    titles = [
      "Bitcoin Reaches New All-Time High Amid Institutional Demand",
      "Crypto Market Cap Surpasses $3 Trillion Milestone",
      "Ethereum Shows Strong Momentum Following Upgrade",
      "DeFi Tokens Rally 40% in Weekly Trading Session",
      "Altcoin Season Indicators Flash Bullish Signals",
      "Stablecoin Market Dominance Reaches Record Levels",
      "NFT Trading Volume Spikes to $2.5 Billion",
      "Layer 2 Solutions Capture 30% of Market Share",
      "Institutional Bitcoin Holdings Hit New Record",
      "Crypto ETF Inflows Exceed $1 Billion Mark"
    ]

    title = Enum.at(titles, rem(index - 1, length(titles)))
    slug = title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.trim("-")

    %{
      title: title,
      slug: slug,
      excerpt: "Market analysis reveals significant trends as digital assets continue to gain traction among institutional and retail investors worldwide.",
      featured_image: "https://blockster-images.s3.us-east-1.amazonaws.com/uploads/#{:rand.uniform(999999999)}-#{:rand.uniform(999999999999999999) |> Integer.to_string(16) |> String.downcase()}.webp",
      content: generate_market_content(title)
    }
  end

  defp generate_investment_post(index) do
    titles = [
      "Top 5 Crypto Investment Strategies for 2024",
      "Venture Capital Pours $500M into Web3 Startups",
      "How to Build a Diversified Crypto Portfolio",
      "Institutional Investors Increase Crypto Allocations",
      "Risk Management in Cryptocurrency Investments",
      "Emerging Markets Show Strong Crypto Adoption",
      "Long-term vs Short-term Crypto Investment Approaches",
      "Regulatory Changes Impact Investment Landscape",
      "Portfolio Rebalancing Strategies for Crypto Assets",
      "Tax-Efficient Crypto Investment Techniques"
    ]

    title = Enum.at(titles, rem(index - 1, length(titles)))
    slug = title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.trim("-")

    %{
      title: title,
      slug: slug,
      excerpt: "Expert insights on cryptocurrency investment strategies and emerging opportunities in the digital asset market.",
      featured_image: "https://blockster-images.s3.us-east-1.amazonaws.com/uploads/#{:rand.uniform(999999999)}-#{:rand.uniform(999999999999999999) |> Integer.to_string(16) |> String.downcase()}.webp",
      content: generate_investment_content(title)
    }
  end

  defp generate_events_post(index) do
    titles = [
      "Global Blockchain Summit Announces 2024 Lineup",
      "Crypto Conference Draws 10,000 Attendees",
      "DeFi Summit Showcases Latest Innovations",
      "NFT Convention Highlights Digital Art Trends",
      "Web3 Hackathon Attracts Top Developers",
      "Blockchain Expo Features Fortune 500 Companies",
      "Virtual Crypto Meetup Series Launches",
      "Industry Leaders Speak at Token2049",
      "ETHGlobal Hackathon Awards $1M in Prizes",
      "Consensus Conference Returns to Austin"
    ]

    title = Enum.at(titles, rem(index - 1, length(titles)))
    slug = title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.trim("-")

    %{
      title: title,
      slug: slug,
      excerpt: "Join the crypto community at upcoming events featuring industry leaders, innovative projects, and networking opportunities.",
      featured_image: "https://blockster-images.s3.us-east-1.amazonaws.com/uploads/#{:rand.uniform(999999999)}-#{:rand.uniform(999999999999999999) |> Integer.to_string(16) |> String.downcase()}.webp",
      content: generate_events_content(title)
    }
  end

  defp generate_trading_post(index) do
    titles = [
      "Advanced Trading Strategies for Volatile Markets",
      "Technical Analysis: Key Indicators to Watch",
      "Automated Trading Bots Show 60% Success Rate",
      "Spot vs Futures Trading: A Comprehensive Guide",
      "Risk Management Techniques for Day Traders",
      "Order Book Analysis for Better Trade Execution",
      "Arbitrage Opportunities in Crypto Markets",
      "Leverage Trading: Risks and Rewards Explained",
      "Market Making Strategies for Liquidity Providers",
      "Swing Trading Tactics for Crypto Assets"
    ]

    title = Enum.at(titles, rem(index - 1, length(titles)))
    slug = title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.trim("-")

    %{
      title: title,
      slug: slug,
      excerpt: "Professional trading insights and strategies to help navigate the dynamic cryptocurrency market landscape.",
      featured_image: "https://blockster-images.s3.us-east-1.amazonaws.com/uploads/#{:rand.uniform(999999999)}-#{:rand.uniform(999999999999999999) |> Integer.to_string(16) |> String.downcase()}.webp",
      content: generate_trading_content(title)
    }
  end

  defp generate_people_post(index) do
    titles = [
      "Interview: Lisa Thompson on the Future of DeFi",
      "Meet the Developer Behind Revolutionary Smart Contract",
      "Crypto Pioneer Marcus Rodriguez Shares Vision",
      "Rising Star: Young Entrepreneur Builds $100M Protocol",
      "Industry Veteran Jennifer Lee Launches New Venture",
      "Profile: The Team Building Next-Gen Blockchain",
      "Founder Story: From Startup to Unicorn in 2 Years",
      "Women in Crypto: Breaking Barriers and Leading Change",
      "The Visionary Behind Cutting-Edge Layer 2 Solution",
      "From Traditional Finance to Crypto: A Journey"
    ]

    title = Enum.at(titles, rem(index - 1, length(titles)))
    slug = title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.trim("-")

    %{
      title: title,
      slug: slug,
      excerpt: "Get to know the innovators, entrepreneurs, and thought leaders shaping the future of blockchain and cryptocurrency.",
      featured_image: "https://blockster-images.s3.us-east-1.amazonaws.com/uploads/#{:rand.uniform(999999999)}-#{:rand.uniform(999999999999999999) |> Integer.to_string(16) |> String.downcase()}.webp",
      content: generate_people_content(title)
    }
  end

  defp generate_defi_post(index) do
    titles = [
      "Yield Farming Strategies Generating 200% APY",
      "New DEX Protocol Reaches $1B TVL Milestone",
      "Lending Platforms Introduce Variable Rate Models",
      "Liquidity Mining Programs Attract Major Capital",
      "Cross-Chain DeFi Bridges Enable Seamless Swaps",
      "Staking Rewards Reach All-Time High Levels",
      "DeFi Insurance Protocols Gain Traction",
      "Synthetic Assets Platform Launches New Features",
      "Flash Loan Technology Advances Risk Management",
      "Governance Token Holders Vote on Major Upgrade"
    ]

    title = Enum.at(titles, rem(index - 1, length(titles)))
    slug = title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.trim("-")

    %{
      title: title,
      slug: slug,
      excerpt: "Explore the latest developments in decentralized finance, from yield optimization to innovative protocol designs.",
      featured_image: "https://blockster-images.s3.us-east-1.amazonaws.com/uploads/#{:rand.uniform(999999999)}-#{:rand.uniform(999999999999999999) |> Integer.to_string(16) |> String.downcase()}.webp",
      content: generate_defi_content(title)
    }
  end

  defp generate_announcement_post(index) do
    titles = [
      "Major Exchange Lists 50 New Trading Pairs",
      "Platform Upgrade Scheduled for Next Week",
      "New Partnership Announcement with Tech Giant",
      "Token Burn Event Removes 100M from Circulation",
      "Mobile App Update Brings Enhanced Features",
      "Strategic Investment Round Closes at $50M",
      "Mainnet Launch Date Confirmed for Q2",
      "Airdrop Campaign Rewards Loyal Community Members",
      "New Staking Program Offers Competitive Rewards",
      "Platform Achieves SOC 2 Compliance Certification"
    ]

    title = Enum.at(titles, rem(index - 1, length(titles)))
    slug = title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.trim("-")

    %{
      title: title,
      slug: slug,
      excerpt: "Stay informed with the latest announcements and updates from leading cryptocurrency projects and platforms.",
      featured_image: "https://blockster-images.s3.us-east-1.amazonaws.com/uploads/#{:rand.uniform(999999999)}-#{:rand.uniform(999999999999999999) |> Integer.to_string(16) |> String.downcase()}.webp",
      content: generate_announcement_content(title)
    }
  end

  defp generate_gaming_post(index) do
    titles = [
      "Play-to-Earn Game Surpasses 1 Million Players",
      "NFT Gaming Platform Raises $30M Series A",
      "Metaverse Land Sales Reach $100M This Quarter",
      "Blockchain Gaming Tournament Offers $500K Prize",
      "New RPG Integrates DeFi Mechanics Seamlessly",
      "Virtual World Economy Generates Real Revenue",
      "Gaming Guild Acquires $10M in Digital Assets",
      "Cross-Platform Gaming Protocol Launches Beta",
      "In-Game NFT Marketplace Hits $50M Volume",
      "eSports Team Adopts Cryptocurrency Payments"
    ]

    title = Enum.at(titles, rem(index - 1, length(titles)))
    slug = title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9\s-]/, "")
      |> String.replace(~r/\s+/, "-")
      |> String.trim("-")

    %{
      title: title,
      slug: slug,
      excerpt: "Discover how blockchain technology is revolutionizing the gaming industry with play-to-earn models and digital ownership.",
      featured_image: "https://blockster-images.s3.us-east-1.amazonaws.com/uploads/#{:rand.uniform(999999999)}-#{:rand.uniform(999999999999999999) |> Integer.to_string(16) |> String.downcase()}.webp",
      content: generate_gaming_content(title)
    }
  end

  defp generate_default_post(category, index) do
    %{
      title: "#{category.name} Update #{index}",
      slug: "#{category.slug}-update-#{index}",
      excerpt: "Latest developments in #{category.name}.",
      featured_image: "https://blockster-images.s3.us-east-1.amazonaws.com/uploads/#{:rand.uniform(999999999)}-#{:rand.uniform(999999999999999999) |> Integer.to_string(16) |> String.downcase()}.webp",
      content: generate_generic_content(category.name)
    }
  end

  defp generate_market_content(title) do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "paragraph",
          "content" => [
            %{"type" => "text", "text" => "Market analysis shows ", "marks" => []},
            %{"type" => "text", "text" => "significant momentum", "marks" => [%{"type" => "bold"}]},
            %{"type" => "text", "text" => " as #{title |> String.downcase()} continues to shape the cryptocurrency landscape.", "marks" => []}
          ]
        },
        %{"type" => "paragraph"},
        %{
          "type" => "heading",
          "attrs" => %{"level" => 2},
          "content" => [%{"type" => "text", "text" => "Market Overview"}]
        },
        %{
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "Trading volumes have surged across major exchanges as institutional and retail investors respond to positive market dynamics. Technical indicators suggest sustained bullish momentum in the near term."}]
        },
        %{"type" => "paragraph"},
        %{
          "type" => "heading",
          "attrs" => %{"level" => 2},
          "content" => [%{"type" => "text", "text" => "Key Metrics"}]
        },
        %{
          "type" => "bulletList",
          "content" => [
            %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "24-hour trading volume up 45%"}]}]},
            %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Market cap growth of 12%"}]}]},
            %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Active addresses increased by 30%"}]}]},
            %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "On-chain metrics remain bullish"}]}]}
          ]
        },
        %{"type" => "paragraph"},
        %{
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "Analysts expect continued growth as market conditions remain favorable and regulatory clarity improves across major jurisdictions."}]
        }
      ]
    }
  end

  defp generate_investment_content(title) do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "Investment strategies continue to evolve as the cryptocurrency market matures and offers new opportunities for both institutional and retail participants."}]
        },
        %{"type" => "paragraph"},
        %{
          "type" => "heading",
          "attrs" => %{"level" => 2},
          "content" => [%{"type" => "text", "text" => "Strategic Approach"}]
        },
        %{
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "Diversification remains key to managing risk while capturing upside potential across different asset classes and protocols within the digital asset ecosystem."}]
        },
        %{"type" => "paragraph"},
        %{
          "type" => "blockquote",
          "content" => [
            %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "The key to successful crypto investing is understanding the underlying technology and market dynamics."}]},
            %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "— Investment Strategist"}]}
          ]
        },
        %{"type" => "paragraph"},
        %{
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "As the market continues to develop, new investment vehicles and strategies emerge, providing sophisticated tools for portfolio management and risk mitigation."}]
        }
      ]
    }
  end

  defp generate_events_content(title) do
    generate_generic_content("Events")
  end

  defp generate_trading_content(title) do
    generate_generic_content("Crypto Trading")
  end

  defp generate_people_content(title) do
    generate_generic_content("People")
  end

  defp generate_defi_content(title) do
    generate_generic_content("DeFi")
  end

  defp generate_announcement_content(title) do
    generate_generic_content("Announcements")
  end

  defp generate_gaming_content(title) do
    generate_generic_content("Gaming")
  end

  defp generate_generic_content(topic) do
    %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "Important developments in #{topic} are reshaping the industry landscape and creating new opportunities for innovation."}]
        },
        %{"type" => "paragraph"},
        %{
          "type" => "heading",
          "attrs" => %{"level" => 2},
          "content" => [%{"type" => "text", "text" => "Key Highlights"}]
        },
        %{
          "type" => "bulletList",
          "content" => [
            %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Significant technological advancement"}]}]},
            %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Enhanced user experience"}]}]},
            %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Improved security features"}]}]},
            %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Growing community adoption"}]}]}
          ]
        },
        %{"type" => "paragraph"},
        %{
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "The #{topic} sector continues to attract attention from investors and developers alike as it demonstrates sustained growth and innovation potential."}]
        }
      ]
    }
  end
end

RecreateProductionPosts.run()
