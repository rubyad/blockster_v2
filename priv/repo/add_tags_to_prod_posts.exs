alias BlocksterV2.Repo
alias BlocksterV2.Blog
alias BlocksterV2.Blog.{Post, Tag}
import Ecto.Query

IO.puts("Adding tags to all posts...")

# Get all posts and tags
posts = Repo.all(Post)
all_tags = Repo.all(Tag)
interview_tag = Repo.get_by(Tag, name: "Interview")

IO.puts("Found #{length(posts)} posts")
IO.puts("Found #{length(all_tags)} tags")

if interview_tag do
  IO.puts("Found Interview tag with ID: #{interview_tag.id}")
else
  IO.puts("Warning: Interview tag not found!")
end

# Add tags to each post
Enum.each(posts, fn post ->
  # Pick 6 random tags
  random_tags = Enum.take_random(all_tags, 6)

  # Add tags using the Blog context
  case Blog.update_post_tags(post, Enum.map(random_tags, & &1.name)) do
    {:ok, _updated_post} ->
      IO.write(".")
    {:error, changeset} ->
      IO.puts("\nError updating post #{post.id}: #{inspect(changeset.errors)}")
  end
end)

IO.puts("\n\nAdding Interview tag to 10 random posts...")

# Pick 10 random posts and add Interview tag
if interview_tag do
  posts
  |> Enum.take_random(10)
  |> Enum.each(fn post ->
    case Blog.update_post_tags(post, ["Interview"]) do
      {:ok, _updated_post} ->
        IO.puts("Added Interview tag to: #{post.title}")
      {:error, changeset} ->
        IO.puts("Error: #{inspect(changeset.errors)}")
    end
  end)
end

IO.puts("\nDone!")

# Count posts with tags
posts_with_tags = Repo.all(from p in Post,
  join: pt in "post_tags", on: pt.post_id == p.id,
  select: count(p.id, :distinct)
)

IO.puts("Posts with tags: #{List.first(posts_with_tags)}")
