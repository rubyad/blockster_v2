alias BlocksterV2.Repo
alias BlocksterV2.Blog.{Post, Tag}
import Ecto.Query

# Get or create the Interview tag
interview_tag = case Repo.get_by(Tag, slug: "interview") do
  nil ->
    IO.puts("Creating Interview tag...")
    {:ok, tag} = Repo.insert(%Tag{name: "Interview", slug: "interview"})
    tag
  tag ->
    IO.puts("Interview tag already exists")
    tag
end

# Get 10 random posts
IO.puts("\nSelecting 10 random posts...")
random_posts = Repo.all(
  from p in Post,
    order_by: fragment("RANDOM()"),
    limit: 10,
    preload: [:tags]
)

IO.puts("Found #{length(random_posts)} posts\n")

# Add Interview tag to each post
Enum.each(random_posts, fn post ->
  # Check if post already has Interview tag
  has_interview = Enum.any?(post.tags, fn tag -> tag.id == interview_tag.id end)

  unless has_interview do
    # Add Interview tag to existing tags
    updated_tags = [interview_tag | post.tags]

    {:ok, _post} = post
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_assoc(:tags, updated_tags)
      |> Repo.update()

    IO.puts("✓ Added Interview tag to: #{post.title}")
  else
    IO.puts("- Post already has Interview tag: #{post.title}")
  end
end)

IO.puts("\n✅ Successfully added Interview tag to 10 posts!")
