alias BlocksterV2.Repo
alias BlocksterV2.Blog.Post
alias BlocksterV2.Blog.CuratedPost

import Ecto.Query

# Get all published posts
published_posts = Repo.all(from p in Post, where: not is_nil(p.published_at))

if length(published_posts) < 3 do
  IO.puts("Warning: Not enough published posts. Need at least 3 posts for posts_four section")
  IO.puts("Found: #{length(published_posts)} published posts")
else
  # Shuffle posts to get random selection
  shuffled_posts = Enum.shuffle(published_posts)

  # Clear existing posts_four curated posts
  Repo.delete_all(from cp in CuratedPost, where: cp.section == "posts_four")

  IO.puts("Populating posts_four curated posts with 3 random posts...")

  # Posts Four Section - 3 positions (3 cards in a row)
  posts_four_posts = Enum.take(shuffled_posts, 3)

  Enum.with_index(posts_four_posts, 1)
  |> Enum.each(fn {post, position} ->
    %CuratedPost{}
    |> CuratedPost.changeset(%{
      section: "posts_four",
      position: position,
      post_id: post.id
    })
    |> Repo.insert!()

    IO.puts("  Posts Four Position #{position}: #{post.title}")
  end)

  IO.puts("\nSuccessfully populated 3 posts_four curated post positions!")
end
