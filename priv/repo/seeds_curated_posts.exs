alias BlocksterV2.Repo
alias BlocksterV2.Blog.Post
alias BlocksterV2.Blog.CuratedPost

import Ecto.Query

# Get all published posts
published_posts = Repo.all(from p in Post, where: not is_nil(p.published_at))

if length(published_posts) < 16 do
  IO.puts("Warning: Not enough published posts. Need at least 16 posts (10 for latest_news, 6 for conversations)")
  IO.puts("Found: #{length(published_posts)} published posts")
else
  # Shuffle posts to get random selection
  shuffled_posts = Enum.shuffle(published_posts)

  # Clear existing curated posts
  Repo.delete_all(CuratedPost)

  IO.puts("Populating curated posts with random posts...")

  # Latest News Section - 10 positions
  # Positions 1-5: Main grid (2 left, 1 middle, 2 right)
  # Positions 6-10: Recommended sidebar
  latest_news_posts = Enum.take(shuffled_posts, 10)

  Enum.with_index(latest_news_posts, 1)
  |> Enum.each(fn {post, position} ->
    %CuratedPost{}
    |> CuratedPost.changeset(%{
      section: "latest_news",
      position: position,
      post_id: post.id
    })
    |> Repo.insert!()

    IO.puts("  Latest News Position #{position}: #{post.title}")
  end)

  # Conversations Section - 6 positions
  # Positions 1-3: Top row (3 square cards)
  # Positions 4-5: Bottom row (2 horizontal cards)
  # Position 6: Large sidebar card
  conversations_posts = Enum.slice(shuffled_posts, 10, 6)

  Enum.with_index(conversations_posts, 1)
  |> Enum.each(fn {post, position} ->
    %CuratedPost{}
    |> CuratedPost.changeset(%{
      section: "conversations",
      position: position,
      post_id: post.id
    })
    |> Repo.insert!()

    position_name = case position do
      p when p in [1, 2, 3] -> "Top Row Card #{p}"
      4 -> "Bottom Row Card 1"
      5 -> "Bottom Row Card 2"
      6 -> "Large Sidebar Card"
    end

    IO.puts("  Conversations #{position_name}: #{post.title}")
  end)

  IO.puts("\nSuccessfully populated #{10 + 6} curated post positions!")
end
