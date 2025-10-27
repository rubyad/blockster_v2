# Script to add the reference article from blockerstaging2.netlify.app/article

alias BlocksterV2.Repo
alias BlocksterV2.Blog

# Create the Quill.js Delta content matching the reference article
content = %{
  "ops" => [
    %{"insert" => "A Strong Foundation for Success", "attributes" => %{"header" => 2}},
    %{"insert" => "\n\n"},
    %{
      "insert" =>
        "Alongside this financial backing, Orbs' technical expertise and marketing efforts have greatly enhanced THENA's visibility, particularly within the BNB Chain ecosystem, helping the protocol expand its market share.\n\nSince Orbs began supporting THENA in early 2023, the protocol has leveraged a combination of capital, marketing, and advanced technical solutions. The results are clear: THENA's liquidity protocol has surged to new heights.\n\nAt the heart of this transformation are Orbs' cutting-edge Layer-3 trading solutions, including the integration of dTWAP, dLIMIT, Liquidity Hub, and Perpetual Hub. These technologies have allowed THENA to offer highly efficient trading execution, enhanced liquidity management, and pioneering perpetual trading features.\n\nAlongside this financial backing, Orbs' technical expertise and marketing efforts have greatly enhanced THENA's visibility, particularly within the BNB Chain ecosystem, helping the protocol expand its market share.\n\n"
    },
    %{"insert" => %{"image" => "/images/keynote.png"}},
    %{"insert" => "\n"},
    %{
      "insert" => "Keynote at Web3 Global Summit – July 25, 2025",
      "attributes" => %{"italic" => true}
    },
    %{"insert" => "\n\n"},
    %{
      "insert" =>
        "Since Orbs began supporting THENA in early 2023, the protocol has leveraged a combination of capital, marketing, and advanced technical solutions. The results are clear: THENA's liquidity protocol has surged to new heights.\n\nAt the heart of this transformation are Orbs' cutting-edge Layer-3 trading solutions, including the integration of dTWAP, dLIMIT, Liquidity Hub, and Perpetual Hub. These technologies have allowed THENA to offer highly efficient trading execution, enhanced liquidity management, and pioneering perpetual trading features.\n\nAlongside this financial backing, Orbs' technical expertise and marketing efforts have greatly enhanced THENA's visibility, particularly within the BNB Chain ecosystem, helping the protocol expand its market share.\n\n"
    },
    %{"insert" => "Binance Listing: A Game-Changer", "attributes" => %{"header" => 2}},
    %{"insert" => "\n\n"},
    %{
      "insert" =>
        "Since Orbs began supporting THENA in early 2023, the protocol has leveraged a combination of capital, marketing, and advanced technical solutions. The results are clear: THENA's liquidity protocol has surged to new heights.\n\nSince Orbs began supporting THENA in early 2023, the protocol has leveraged a combination of capital, marketing, and advanced technical solutions. The results are clear: THENA's liquidity protocol has surged to new heights.\n\n"
    },
    %{"insert" => %{"image" => "/images/tedx.png"}},
    %{"insert" => "\n"},
    %{
      "insert" => "Interview for TED CryptoTalks – July 25, 2025",
      "attributes" => %{"italic" => true}
    },
    %{"insert" => "\n\n"},
    %{
      "insert" => "Game-Changing Integrations and Market Expansion",
      "attributes" => %{"header" => 2}
    },
    %{"insert" => "\n\n"},
    %{
      "insert" =>
        "Since Orbs began supporting THENA in early 2023, the protocol has leveraged a combination of capital, marketing, and advanced technical solutions. The results are clear: THENA's liquidity protocol has surged to new heights.\n\nSince Orbs began supporting THENA in early 2023, the protocol has leveraged a combination of capital, marketing, and advanced technical solutions. The results are clear: THENA's liquidity protocol has surged to new heights."
    }
  ]
}

{:ok, post} =
  Blog.create_post(%{
    title: "Inside Web3 Innovation: Daniel Ortega Reshaping DeFi",
    content: content,
    excerpt:
      "Alongside this financial backing, Orbs' technical expertise and marketing efforts have greatly enhanced THENA's visibility, particularly within the BNB Chain ecosystem.",
    author_name: "BlockRise Capital",
    category: "Trading",
    featured_image:
      "https://blockster-images.s3.us-east-1.amazonaws.com/uploads/reference-article.jpg",
    published_at: ~U[2025-10-28 00:00:00Z]
  })

IO.puts("Created reference article post with ID: #{post.id}")
IO.puts("Title: #{post.title}")
IO.puts("Slug: #{post.slug}")
IO.puts("Category: #{post.category}")
IO.puts("Author: #{post.author_name}")
