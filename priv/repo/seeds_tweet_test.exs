# Script to create a test post with tweet embed

alias BlocksterV2.Repo
alias BlocksterV2.Blog

# Sample content with a tweet embed
content_with_tweet = %{
  "ops" => [
    %{
      "insert" => "The Future of Blockchain: Insights from Vitalik Buterin\n\n"
    },
    %{
      "insert" =>
        "Ethereum co-founder Vitalik Buterin recently shared his thoughts on the future of blockchain technology and decentralization. His insights provide a glimpse into what's coming next for the ecosystem.\n\n"
    },
    %{
      "insert" =>
        "In a recent tweet, he addressed the importance of scalability and user experience:\n\n"
    },
    %{
      "insert" => %{
        "tweet" => %{
          "url" => "https://twitter.com/VitalikButerin/status/1735056849162223744",
          "id" => "1735056849162223744"
        }
      }
    },
    %{
      "insert" => "\n\n"
    },
    %{
      "insert" =>
        "This perspective highlights the ongoing evolution of blockchain technology and the challenges that still need to be addressed for mass adoption.\n\n"
    },
    %{
      "insert" => "Key Takeaways:\n",
      "attributes" => %{"bold" => true}
    },
    %{
      "insert" =>
        "• Scalability remains a top priority for Ethereum\n• User experience needs to improve for mainstream adoption\n• Layer 2 solutions are crucial for the ecosystem's growth\n• Privacy features are becoming increasingly important\n\n"
    },
    %{
      "insert" =>
        "The blockchain community continues to innovate and push boundaries, with leaders like Vitalik providing valuable guidance on the path forward."
    }
  ]
}

# Create the test post
{:ok, post} =
  Blog.create_post(%{
    title: "Vitalik Buterin on Blockchain's Future: A Tweet Analysis",
    content: content_with_tweet,
    excerpt:
      "Ethereum co-founder Vitalik Buterin shares insights on scalability, user experience, and the future of blockchain technology.",
    author_name: "Crypto Insights Team",
    category: "Blockchain",
    featured_image:
      "https://blockster-images.s3.us-east-1.amazonaws.com/uploads/reference-article.jpg",
    published_at: DateTime.utc_now() |> DateTime.add(-2, :hour)
  })

IO.puts("\n✅ Created test post with tweet embed!")
IO.puts("   Title: #{post.title}")
IO.puts("   Slug: #{post.slug}")
IO.puts("   URL: http://localhost:4000/#{post.slug}")
IO.puts("\n   Visit the article to see the embedded tweet!")
