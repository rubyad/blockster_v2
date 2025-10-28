alias BlocksterV2.Repo
alias BlocksterV2.Blog.Post

posts = [
  %{
    title: "The Faces of Web3: Meet the Visionaries Shaping the Future at Major Summits",
    slug: "web3-visionaries-major-summits-sam-new",
    content: %{"ops" => [%{"insert" => "Exploring the faces of Web3 innovation at industry summits."}]},
    author_name: "Sam Bankman",
    category: "Blockchain",
    featured_image: "/images/sam.png",
    published_at: ~U[2025-01-15 14:00:00Z],
    view_count: 1264
  },
  %{
    title: "The Future of Ethereum: A Conversation with Vitalik Buterin",
    slug: "ethereum-future-vitalik-buterin-new",
    content: %{"ops" => [%{"insert" => "Vitalik Buterin shares his vision for Ethereum's evolution and the future of decentralized systems."}]},
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

IO.puts("Created 2 missing posts with sam.png and vitaly.png!")
