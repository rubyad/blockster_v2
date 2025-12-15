alias BlocksterV2.Repo
alias BlocksterV2.Blog.Post
alias BlocksterV2.Blog.CuratedPost

import Ecto.Query

# Get all published posts
published_posts = Repo.all(from p in Post, where: not is_nil(p.published_at))

if length(published_posts) < 6 do
  IO.puts("Warning: Not enough published posts. Need at least 6 posts for posts_five section")
  IO.puts("Found: #{length(published_posts)} published posts")
else
  # Shuffle posts to get random selection
  shuffled_posts = Enum.shuffle(published_posts)

  # Clear existing posts_five curated posts
  Repo.delete_all(from cp in CuratedPost, where: cp.section == "posts_five")

  IO.puts("Populating posts_five curated posts with 6 random posts...")

  # Posts Five Section - 6 positions
  # Row 1: Position 1 (large left), Positions 2-3 (small right)
  # Row 2: Position 4 (large right), Positions 5-6 (small left)
  posts_five_posts = Enum.take(shuffled_posts, 6)

  Enum.with_index(posts_five_posts, 1)
  |> Enum.each(fn {post, position} ->
    %CuratedPost{}
    |> CuratedPost.changeset(%{
      section: "posts_five",
      position: position,
      post_id: post.id
    })
    |> Repo.insert!()

    position_name = case position do
      1 -> "Row 1 Large Card (left)"
      2 -> "Row 1 Small Card 1 (right)"
      3 -> "Row 1 Small Card 2 (right)"
      4 -> "Row 2 Large Card (right)"
      5 -> "Row 2 Small Card 1 (left)"
      6 -> "Row 2 Small Card 2 (left)"
    end

    IO.puts("  Posts Five Position #{position} (#{position_name}): #{post.title}")
  end)

  IO.puts("\nSuccessfully populated 6 posts_five curated post positions!")
end
