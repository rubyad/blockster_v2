# Simple seeds script for generating posts
import Ecto.Query
alias BlocksterV2.Repo
alias BlocksterV2.Blog.{Post, Category, Tag}
alias BlocksterV2.Accounts.User

# Get first available user
author = Repo.all(from u in User, where: u.is_admin == true or u.is_author == true, limit: 1) |> List.first()

if !author do
  author = Repo.all(from u in User, limit: 1) |> List.first()
end

if !author do
  IO.puts("ERROR: No users found in database!")
  System.halt(1)
end

IO.puts("Using author: #{author.email} (ID: #{author.id})")

categories = Repo.all(Category)
all_tags = Repo.all(Tag)

IO.puts("Categories: #{length(categories)}")
IO.puts("Tags: #{length(all_tags)}")

images = [
  "/images/bitcoin-guru.png",
  "/images/crypto-bull.png",
  "/images/ethereum.png",
  "/images/doge-coin.png",
  "/images/moonpay.png",
  "/images/w3-1.png",
  "/images/w3-2.png",
  "/images/w3-3.png",
  "/images/lifestyle-2.png",
  "/images/lifestyle-4.png"
]

# Simple content template matching MoonPay format
content = %{
  "ops" => [
    %{"attributes" => %{"italic" => true}, "insert" => "Breaking news in the crypto space. Major innovation announced today."},
    %{"insert" => "\n\n"},
    %{"insert" => %{"spacer" => true}},
    %{"insert" => "\n\nThis groundbreaking development is set to revolutionize the industry.\n\n\"We're incredibly excited about this innovation,\" said the CEO.\n"},
    %{"attributes" => %{"blockquote" => true}, "insert" => "\n"},
    %{"insert" => "Company CEO"},
    %{"attributes" => %{"blockquote" => true}, "insert" => "\n"},
    %{"insert" => "\nWhy It Matters"},
    %{"attributes" => %{"header" => 2}, "insert" => "\n"},
    %{"insert" => " \nKey benefits include:\n \nInstant transactions"},
    %{"attributes" => %{"list" => "bullet"}, "insert" => "\n"},
    %{"insert" => "Lower fees"},
    %{"attributes" => %{"list" => "bullet"}, "insert" => "\n"},
    %{"insert" => "Enhanced security"},
    %{"attributes" => %{"list" => "bullet"}, "insert" => "\n"},
    %{"insert" => "Improved user experience"},
    %{"attributes" => %{"list" => "bullet"}, "insert" => "\n"},
    %{"insert" => "24/7 support"},
    %{"attributes" => %{"list" => "bullet"}, "insert" => "\n"},
    %{"insert" => "\n"},
    %{"insert" => %{"tweet" => %{"id" => "20", "url" => "https://x.com/twitter/status/20"}}},
    %{"insert" => "\n"},
    %{"insert" => "Technical Details"},
    %{"attributes" => %{"header" => 2}, "insert" => "\n"},
    %{"insert" => " \nThe platform leverages cutting-edge technology to deliver unprecedented performance.\n"}
  ]
}

IO.puts("\nGenerating 10 posts per category...")

for category <- categories do
  IO.puts("\nCategory: #{category.name}")

  for i <- 1..10 do
    title = "#{category.name} Innovation #{i}: Breaking Crypto News Today"
    slug = String.downcase(title)
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.slice(0..99)

    unless Repo.get_by(Post, slug: slug) do
      tags = Enum.take_random(all_tags, 6)

      {:ok, post} = %Post{}
      |> Post.changeset(%{
        title: title,
        slug: slug,
        content: content,
        excerpt: String.slice(title, 0..150) <> "...",
        author_id: author.id,
        category_id: category.id,
        featured_image: Enum.random(images),
        published_at: DateTime.utc_now() |> DateTime.add(-Enum.random(1..30), :day),
        view_count: Enum.random(100..5000)
      })
      |> Repo.insert()

      Enum.each(tags, fn tag ->
        Repo.insert_all("post_tags", [[post_id: post.id, tag_id: tag.id]])
      end)

      IO.write(" ✓")
    else
      IO.write(" -")
    end
  end
end

IO.puts("\n\n✅ Done! Total posts: #{Repo.aggregate(Post, :count, :id)}")
