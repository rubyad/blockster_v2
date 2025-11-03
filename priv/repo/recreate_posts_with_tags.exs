# Script to delete all posts and recreate them with 10 posts per category,
# each with 6 random tags and random published dates within the past month

alias BlocksterV2.Repo
alias BlocksterV2.Blog.{Post, Category, Tag}
alias BlocksterV2.Accounts.User
import Ecto.Query

# First, let's fetch all existing posts with their data
IO.puts("Fetching existing posts...")
existing_posts = Repo.all(from p in Post, preload: [:category, :author])

# Group posts by category
posts_by_category = Enum.group_by(existing_posts, fn post ->
  if post.category, do: post.category.name, else: "Uncategorized"
end)

IO.puts("Found #{length(existing_posts)} existing posts")
IO.puts("Categories: #{Enum.join(Map.keys(posts_by_category), ", ")}")

# Get or create default author
author = Repo.get_by(User, email: "admin@blockster.com") ||
         Repo.get_by(User, email: "lidia@blockster.com") ||
         Repo.one(from u in User, limit: 1)

unless author do
  IO.puts("Error: No users found in database. Please create a user first.")
  System.halt(1)
end

IO.puts("Using author: #{author.email}")

# Tag pool to randomly select from
tag_names = [
  "Blockchain", "Cryptocurrency", "Bitcoin", "Ethereum", "DeFi", "NFT",
  "Web3", "Smart Contracts", "Mining", "Trading", "Altcoins", "Stablecoins",
  "DEX", "CEX", "Wallet", "Security", "Regulation", "Investment", "Technology",
  "Innovation", "Market Analysis", "Tutorial", "News", "Gaming", "Metaverse"
]

# Create or get all tags
IO.puts("\nCreating/fetching tags...")
tags = Enum.map(tag_names, fn name ->
  slug = Tag.generate_slug(name)
  case Repo.get_by(Tag, slug: slug) do
    nil ->
      {:ok, tag} = Repo.insert(%Tag{name: name, slug: slug})
      tag
    tag ->
      tag
  end
end)

IO.puts("Created/found #{length(tags)} tags")

# Helper function to get random tags
defmodule Helper do
  def random_tags(tags, count) do
    Enum.take_random(tags, count)
  end

  def random_date_in_past_month do
    # Get a random number of seconds in the past month (30 days)
    seconds_ago = :rand.uniform(30 * 24 * 60 * 60)
    DateTime.utc_now()
    |> DateTime.add(-seconds_ago, :second)
    |> DateTime.truncate(:second)
  end
end

# Delete all existing posts
IO.puts("\nDeleting all existing posts...")
{deleted_count, _} = Repo.delete_all(Post)
IO.puts("Deleted #{deleted_count} posts")

# Recreate posts - 10 per category
IO.puts("\nRecreating posts...")

total_created = Enum.reduce(posts_by_category, 0, fn {category_name, posts}, acc ->
  category = Repo.get_by(Category, name: category_name)

  unless category do
    IO.puts("Warning: Category '#{category_name}' not found, skipping...")
    acc
  else
    IO.puts("\nCreating 10 posts for category: #{category_name}")

    # Take first post as template, or use first available
    template_post = List.first(posts)

    # Create 10 posts for this category
    new_posts = for i <- 1..10 do
      # Generate unique title by appending number
      title = if i == 1 do
        template_post.title
      else
        "#{template_post.title} (Part #{i})"
      end

      # Create post
      {:ok, post} = Repo.insert(%Post{
        title: title,
        slug: Post.changeset(%Post{}, %{title: title}) |> Ecto.Changeset.get_change(:slug),
        content: template_post.content,
        excerpt: template_post.excerpt,
        author_id: author.id,
        category_id: category.id,
        published_at: Helper.random_date_in_past_month(),
        featured_image: template_post.featured_image
      })

      # Add 6 random tags
      random_tags = Helper.random_tags(tags, 6)
      post = post |> Repo.preload(:tags)
      {:ok, post} = post
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:tags, random_tags)
        |> Repo.update()

      IO.write(".")
      post
    end

    IO.puts(" Created #{length(new_posts)} posts")
    acc + length(new_posts)
  end
end)

IO.puts("\n\n✅ Successfully recreated #{total_created} posts!")
IO.puts("Each post has 6 random tags and a random published date within the past 30 days.")
