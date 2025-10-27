# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     BlocksterV2.Repo.insert!(%BlocksterV2.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias BlocksterV2.Repo
alias BlocksterV2.Blog
alias BlocksterV2.Blog.Post

# Clear existing posts
Repo.delete_all(Post)

# Sample Quill.js content structure
sample_content_1 = %{
  "ops" => [
    %{
      "insert" =>
        "Discover the innovative minds driving blockchain technology forward as we highlight key speakers and their groundbreaking ideas from recent global conferences.\n\n"
    },
    %{
      "insert" =>
        "The Web3 Summit brought together visionaries from across the globe to discuss the future of decentralized technology. From Ethereum co-founder Vitalik Buterin's insights on scalability to Coinbase CEO Brian Armstrong's vision for mainstream adoption, the event was packed with groundbreaking discussions.\n\n"
    },
    %{"insert" => "Key Takeaways:\n", "attributes" => %{"bold" => true}},
    %{"insert" => "• Blockchain scalability solutions are evolving rapidly\n"},
    %{"insert" => "• DeFi protocols are becoming more user-friendly\n"},
    %{"insert" => "• NFT utility is expanding beyond digital art\n"},
    %{"insert" => "• Web3 gaming is attracting major investment\n\n"},
    %{
      "insert" =>
        "The future of blockchain is being shaped by these incredible minds, and we're excited to see where this technology takes us next."
    }
  ]
}

sample_content_2 = %{
  "ops" => [
    %{
      "insert" =>
        "Ethereum 2.0 represents a fundamental shift in how the network operates. With the transition to Proof of Stake, developers now have new tools and capabilities at their disposal.\n\n"
    },
    %{
      "insert" =>
        "This comprehensive guide explores what the upgrade means for developers building on Ethereum."
    }
  ]
}

sample_content_3 = %{
  "ops" => [
    %{
      "insert" =>
        "We sat down with industry leaders at major blockchain events to get their perspectives on the future of crypto, regulation, and mass adoption.\n\n"
    },
    %{"insert" => "These exclusive interviews provide insights you won't find anywhere else."}
  ]
}

# Create sample posts
{:ok, _post1} =
  Blog.create_post(%{
    title: "The Faces of Web3: Meet the Visionaries Shaping the Future at Major Summits",
    content: sample_content_1,
    excerpt:
      "Discover the innovative minds driving blockchain technology forward as we highlight key speakers and their groundbreaking ideas from recent global conferences.",
    author_name: "Sarah Chen",
    category: "Blockchain",
    published_at: DateTime.utc_now() |> DateTime.add(-4, :hour)
  })

{:ok, _post2} =
  Blog.create_post(%{
    title: "Ethereum 2.0 Upgrade: How It Changes the Game for Developers",
    content: sample_content_2,
    excerpt:
      "A deep dive into Ethereum's transition to Proof of Stake and what it means for the developer ecosystem.",
    author_name: "Alex Rodriguez",
    category: "Blockchain",
    published_at: DateTime.utc_now() |> DateTime.add(-6, :hour)
  })

{:ok, _post3} =
  Blog.create_post(%{
    title: "Exclusive Interviews with Crypto Leaders: Insights from Global Events",
    content: sample_content_3,
    excerpt:
      "Direct conversations with the people shaping the future of cryptocurrency and blockchain technology.",
    author_name: "Maya Patel",
    category: "Events",
    published_at: DateTime.utc_now() |> DateTime.add(-8, :hour)
  })

{:ok, _post4} =
  Blog.create_post(%{
    title: "DeFi Revolution: Top Protocols Transforming Finance in 2024",
    content: sample_content_2,
    author_name: "James Wilson",
    category: "Trading",
    published_at: DateTime.utc_now() |> DateTime.add(-10, :hour)
  })

{:ok, _post5} =
  Blog.create_post(%{
    title: "Play-to-Earn Gaming: The Next Frontier in Blockchain Entertainment",
    content: sample_content_3,
    author_name: "Lisa Kim",
    category: "Gaming",
    published_at: DateTime.utc_now() |> DateTime.add(-12, :hour)
  })

IO.puts("Seeded #{Repo.aggregate(Post, :count, :id)} posts successfully!")
