alias BlocksterV2.Repo
alias BlocksterV2.Blog.Post
alias BlocksterV2.Blog.Tag
import Ecto.Query

# Available interview-style images
interview_images = [
  "/images/smile.png",
  "/images/idris.png",
  "/images/ecstatic.png",
  "/images/sam.png",
  "/images/vitaly.png",
  "/images/avatar.png",
  "/images/avatar-2.png",
  "/images/avatar-3.png",
  "/images/avatar-chen.png"
]

# Get all interview posts with missing images
posts_without_images = Repo.all(
  from p in Post,
    join: t in assoc(p, :tags),
    where: t.slug == "interview" and (is_nil(p.featured_image) or p.featured_image == ""),
    select: p
)

IO.puts("Found #{length(posts_without_images)} interview posts without images")
IO.puts("")

# Assign random images to posts without featured images
Enum.each(posts_without_images, fn post ->
  random_image = Enum.random(interview_images)

  {:ok, updated_post} = post
  |> Ecto.Changeset.change(%{featured_image: random_image})
  |> Repo.update()

  IO.puts("Updated post #{updated_post.id}: #{updated_post.title}")
  IO.puts("  Image: #{random_image}")
  IO.puts("")
end)

IO.puts("Done! All interview posts now have featured images.")
