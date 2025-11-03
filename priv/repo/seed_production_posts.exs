alias BlocksterV2.Repo
alias BlocksterV2.Blog.{Post, Category, Tag}
alias BlocksterV2.Accounts.User
import Ecto.Query

IO.puts("Deleting all posts...")
Repo.delete_all(Post)

categories = Repo.all(Category)
all_tags = Repo.all(Tag)
authors = Repo.all(from u in User, where: u.is_author == true)
interview_tag = Enum.find(all_tags, fn t -> t.name == "Interview" end)

IO.puts("Creating posts...")

Enum.each(categories, fn cat ->
  IO.puts("Category: #{cat.name}")
  Enum.each(1..10, fn i ->
    days_ago = :rand.uniform(30)
    pub_date = DateTime.utc_now() |> DateTime.add(-days_ago * 86400, :second)

    tags = Enum.take_random(all_tags, 6)
    tags = if rem(i, 9) == 0 and interview_tag, do: [interview_tag | tags] |> Enum.uniq(), else: tags

    title = "#{cat.name} Innovation #{i}: Revolutionary Breakthrough"
    slug = title |> String.downcase() |> String.replace(~r/[^a-z0-9\s-]/, "") |> String.replace(~r/\s+/, "-") |> String.trim("-")

    {:ok, post} = %Post{} |> Post.changeset(%{
      title: title,
      slug: slug,
      excerpt: "Major developments in #{cat.name} sector driving industry innovation.",
      featured_image: "https://blockster-images.s3.us-east-1.amazonaws.com/uploads/#{:rand.uniform(999999999)}-abc123.webp",
      content: %{
        "type" => "doc",
        "content" => [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Industry leaders announce breakthrough in #{cat.name} technology."}]},
          %{"type" => "paragraph"},
          %{"type" => "heading", "attrs" => %{"level" => 2}, "content" => [%{"type" => "text", "text" => "Key Highlights"}]},
          %{"type" => "bulletList", "content" => [
            %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Enhanced performance metrics"}]}]},
            %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Improved user experience"}]}]},
            %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Advanced security features"}]}]}
          ]},
          %{"type" => "paragraph"},
          %{"type" => "blockquote", "content" => [
            %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "This represents a major step forward for the industry."}]},
            %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "— Industry Expert"}]}
          ]},
          %{"type" => "paragraph"},
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "The #{cat.name} sector continues to demonstrate strong growth and innovation potential."}]}
        ]
      },
      published_at: pub_date,
      author_id: Enum.random(authors).id,
      category_id: cat.id
    }) |> Repo.insert()

    Enum.each(tags, fn tag ->
      Ecto.build_assoc(post, :post_tags, %{tag_id: tag.id}) |> Repo.insert()
    end)
  end)
end)

IO.puts("Done! Created #{Repo.aggregate(Post, :count)} posts")
