alias BlocksterV2.Repo
alias BlocksterV2.Blog.Post
alias BlocksterV2.Blog.CuratedPost

import Ecto.Query

# Get all published posts
published_posts = Repo.all(from p in Post, where: not is_nil(p.published_at))

if length(published_posts) < 5 do
  IO.puts("Warning: Not enough published posts. Need at least 5 posts for posts_six section")
  IO.puts("Found: #{length(published_posts)} published posts")
else
  # Shuffle posts to get random selection
  shuffled_posts = Enum.shuffle(published_posts)

  # Clear existing posts_six curated posts
  Repo.delete_all(from cp in CuratedPost, where: cp.section == "posts_six")

  IO.puts("Populating posts_six curated posts with 5 random posts...")

  # Posts Six Section - 5 positions
  # Left side: 4 small cards (2x2 grid) - Positions 1-4
  # Right side: 1 large sidebar card - Position 5
  posts_six_posts = Enum.take(shuffled_posts, 5)

  Enum.with_index(posts_six_posts, 1)
  |> Enum.each(fn {post, position} ->
    %CuratedPost{}
    |> CuratedPost.changeset(%{
      section: "posts_six",
      position: position,
      post_id: post.id
    })
    |> Repo.insert!()

    position_name = case position do
      1 -> "Small Card 1 (top-left)"
      2 -> "Small Card 2 (top-right)"
      3 -> "Small Card 3 (bottom-left)"
      4 -> "Small Card 4 (bottom-right)"
      5 -> "Large Sidebar Card (right)"
    end

    IO.puts("  Posts Six Position #{position} (#{position_name}): #{post.title}")
  end)

  IO.puts("\nSuccessfully populated 5 posts_six curated post positions!")
end
