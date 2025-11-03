alias BlocksterV2.Repo
alias BlocksterV2.Blog
alias BlocksterV2.Blog.{Post, Category, Tag}
alias BlocksterV2.Accounts.User

# Get author
author = Repo.get_by(User, email: "lidia@blockster.com") || Repo.get(User, 1)
IO.puts("Using author: #{author.email} (ID: #{author.id})")

# Get all categories and tags
categories = Repo.all(Category)
all_tags = Repo.all(Tag)

IO.puts("Found #{length(categories)} categories")
IO.puts("Found #{length(all_tags)} tags")

# Available images
images = [
  "/images/bitcoin-guru.png",
  "/images/crypto-bull.png",
  "/images/delivering-speech.png",
  "/images/doge-coin.png",
  "/images/ecstatic.png",
  "/images/ethereum.png",
  "/images/group-shot.png",
  "/images/lifestyle-2.png",
  "/images/lifestyle-4.png",
  "/images/lifedtyle.png",
  "/images/w3-1.png",
  "/images/w3-2.png",
  "/images/w3-3.png",
  "/images/moonpay.png",
  "/images/nendorring.png",
  "/images/ad-banner.png"
]

# Create 10 posts per category
Enum.each(categories, fn category ->
  IO.puts("Creating posts for #{category.name}...")

  Enum.each(1..10, fn i ->
    # Random date in last 30 days
    days_ago = :rand.uniform(30)
    pub_date = DateTime.utc_now()
      |> DateTime.add(-days_ago * 86400, :second)
      |> DateTime.truncate(:second)

    title = "#{category.name} Innovation #{i}: Revolutionary Breakthrough"

    # Simple TipTap content
    content = %{
      "type" => "doc",
      "content" => [
        %{
          "type" => "paragraph",
          "content" => [
            %{"type" => "text", "text" => "Industry leaders announce breakthrough technology in the #{category.name} sector."}
          ]
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
            %{
              "type" => "listItem",
              "content" => [
                %{
                  "type" => "paragraph",
                  "content" => [%{"type" => "text", "text" => "Revolutionary new features"}]
                }
              ]
            },
            %{
              "type" => "listItem",
              "content" => [
                %{
                  "type" => "paragraph",
                  "content" => [%{"type" => "text", "text" => "Enhanced security protocols"}]
                }
              ]
            },
            %{
              "type" => "listItem",
              "content" => [
                %{
                  "type" => "paragraph",
                  "content" => [%{"type" => "text", "text" => "Improved user experience"}]
                }
              ]
            }
          ]
        },
        %{"type" => "paragraph"},
        %{
          "type" => "blockquote",
          "content" => [
            %{
              "type" => "paragraph",
              "content" => [%{"type" => "text", "text" => "This marks a significant milestone in our industry's evolution."}]
            }
          ]
        },
        %{
          "type" => "paragraph",
          "content" => [%{"type" => "text", "text" => "Stay tuned for more updates."}]
        }
      ]
    }

    # Pick random tags
    random_tags = Enum.take_random(all_tags, 6)

    # Create post using Blog context
    attrs = %{
      title: title,
      excerpt: "Major developments in #{category.name} sector driving industry innovation.",
      content: content,
      featured_image: Enum.random(images),
      published_at: pub_date,
      author_id: author.id,
      category_id: category.id,
      tag_ids: Enum.map(random_tags, & &1.id)
    }

    case Blog.create_post(attrs) do
      {:ok, post} ->
        IO.write(".")
      {:error, changeset} ->
        IO.puts("\nError creating post: #{inspect(changeset.errors)}")
    end
  end)

  IO.puts(" Done!")
end)

IO.puts("\nFinished creating posts!")
count = Repo.aggregate(Post, :count)
IO.puts("Total posts in database: #{count}")
