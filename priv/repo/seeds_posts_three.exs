# Seed script for posts_three curated section (5 positions)
# Run with: mix run priv/repo/seeds_posts_three.exs

alias BlocksterV2.Repo
alias BlocksterV2.Blog.Post
alias BlocksterV2.Blog.CuratedPost

import Ecto.Query

# Get all published posts
published_posts = Repo.all(from p in Post, where: not is_nil(p.published_at))

# Get existing curated post IDs (to avoid duplicates)
existing_curated_ids =
  Repo.all(from cp in CuratedPost, select: cp.post_id)
  |> MapSet.new()

# Filter out posts already in curated sections
available_posts =
  published_posts
  |> Enum.reject(fn post -> MapSet.member?(existing_curated_ids, post.id) end)

if length(available_posts) < 5 do
  IO.puts("Warning: Not enough available posts. Need at least 5 posts not already curated.")
  IO.puts("Found: #{length(available_posts)} available posts")
  IO.puts("Using any 5 published posts instead...")

  # Fallback to any 5 published posts
  posts_to_use = Enum.take(Enum.shuffle(published_posts), 5)

  IO.puts("\nSeeding posts_three section with 5 posts...")

  # Check if posts_three already has entries and skip if so
  existing_posts_three = Repo.all(from cp in CuratedPost, where: cp.section == "posts_three")

  if length(existing_posts_three) > 0 do
    IO.puts("posts_three section already has #{length(existing_posts_three)} entries. Skipping.")
  else
    Enum.with_index(posts_to_use, 1)
    |> Enum.each(fn {post, position} ->
      %CuratedPost{}
      |> CuratedPost.changeset(%{
        section: "posts_three",
        position: position,
        post_id: post.id
      })
      |> Repo.insert!()

      position_name = case position do
        1 -> "Left Top Card"
        2 -> "Left Bottom Card"
        3 -> "Center Card (Large)"
        4 -> "Right Top Card"
        5 -> "Right Bottom Card"
      end

      IO.puts("  Position #{position} (#{position_name}): #{post.title}")
    end)

    IO.puts("\nSuccessfully populated 5 posts_three positions!")
  end
else
  # Shuffle available posts and take 5
  posts_to_use = Enum.take(Enum.shuffle(available_posts), 5)

  IO.puts("Seeding posts_three section with 5 random posts...")

  # Check if posts_three already has entries and skip if so
  existing_posts_three = Repo.all(from cp in CuratedPost, where: cp.section == "posts_three")

  if length(existing_posts_three) > 0 do
    IO.puts("posts_three section already has #{length(existing_posts_three)} entries. Skipping.")
  else
    Enum.with_index(posts_to_use, 1)
    |> Enum.each(fn {post, position} ->
      %CuratedPost{}
      |> CuratedPost.changeset(%{
        section: "posts_three",
        position: position,
        post_id: post.id
      })
      |> Repo.insert!()

      position_name = case position do
        1 -> "Left Top Card"
        2 -> "Left Bottom Card"
        3 -> "Center Card (Large)"
        4 -> "Right Top Card"
        5 -> "Right Bottom Card"
      end

      IO.puts("  Position #{position} (#{position_name}): #{post.title}")
    end)

    IO.puts("\nSuccessfully populated 5 posts_three positions!")
  end
end
