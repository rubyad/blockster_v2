alias BlocksterV2.Repo
alias BlocksterV2.Blog.Post

posts = [
  %{
    title: "Bitcoin Is Just Getting Started – Michael Saylor on the Future of Digital Gold",
    slug: "bitcoin-just-getting-started-michael-saylor",
    content: %{"ops" => [%{"insert" => "Michael Saylor discusses Bitcoin and its role as digital gold in the future economy."}]},
    author_name: "Michael Saylor",
    category: "Blockchain",
    featured_image: "/images/bitcoin-guru.png",
    published_at: ~U[2025-01-15 10:00:00Z],
    view_count: 1264
  },
  %{
    title: "Changpeng Zhao Talks Binance, Regulation, and What's Next for Crypto",
    slug: "cz-binance-regulation-crypto-future",
    content: %{"ops" => [%{"insert" => "Changpeng Zhao shares insights on Binance growth and cryptocurrency regulation."}]},
    author_name: "Changpeng Zhao",
    category: "Blockchain",
    featured_image: "/images/smile.png",
    published_at: ~U[2025-01-15 11:00:00Z],
    view_count: 1264
  },
  %{
    title: "Casandra Armstrong: How Coinbase Plans to Onboard the Next 100 Million Users",
    slug: "coinbase-100-million-users-casandra-armstrong",
    content: %{"ops" => [%{"insert" => "Casandra Armstrong reveals Coinbase strategy for mass adoption."}]},
    author_name: "Casandra Armstrong",
    category: "Blockchain",
    featured_image: "/images/idris.png",
    published_at: ~U[2025-01-15 12:00:00Z],
    view_count: 1264
  },
  %{
    title: "We're Building the Internet of Value – Brad Garlinghouse on Ripple's Global Vision",
    slug: "ripple-internet-of-value-brad-garlinghouse",
    content: %{"ops" => [%{"insert" => "Brad Garlinghouse discusses Ripple's role in creating the internet of value."}]},
    author_name: "Brad Garlinghouse",
    category: "Blockchain",
    featured_image: "/images/ecstatic.png",
    published_at: ~U[2025-01-15 13:00:00Z],
    view_count: 1264
  },
  %{
    title: "The Faces of Web3: Meet the Visionaries Shaping the Future at Major Summits",
    slug: "web3-visionaries-major-summits-sam",
    content: %{"ops" => [%{"insert" => "Exploring the faces of Web3 innovation at industry summits."}]},
    author_name: "Sam Bankman",
    category: "Blockchain",
    featured_image: "/images/sam.png",
    published_at: ~U[2025-01-15 14:00:00Z],
    view_count: 1264
  },
  %{
    title: "The Faces of Web3: Meet the Visionaries Shaping the Future at Major Summits",
    slug: "web3-visionaries-major-summits-vitaly",
    content: %{"ops" => [%{"insert" => "Discovering Web3 leaders and their vision for the future."}]},
    author_name: "Vitalik Buterin",
    category: "Blockchain",
    featured_image: "/images/vitaly.png",
    published_at: ~U[2025-01-15 15:00:00Z],
    view_count: 1264
  }
]

Enum.each(posts, fn post_attrs ->
  %Post{}
  |> Post.changeset(post_attrs)
  |> Repo.insert!()
end)

IO.puts("Created 6 new posts!")
