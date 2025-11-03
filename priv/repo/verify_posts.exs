alias BlocksterV2.Repo
alias BlocksterV2.Blog.{Post, Category, Tag}
import Ecto.Query

post_count = Repo.aggregate(Post, :count, :id)
IO.puts("Total posts: #{post_count}")

posts_with_tags = Repo.all(from p in Post, preload: [:tags, :category], order_by: [desc: p.published_at], limit: 5)

IO.puts("\nSample of 5 most recent posts:")
Enum.each(posts_with_tags, fn post ->
  tag_names = Enum.map(post.tags, & &1.name) |> Enum.join(", ")
  IO.puts("\n- #{post.title}")
  IO.puts("  Category: #{if post.category, do: post.category.name, else: 'None'}")
  IO.puts("  Tags (#{length(post.tags)}): #{tag_names}")
  IO.puts("  Published: #{post.published_at}")
end)

# Count posts by category
posts_by_category = Repo.all(
  from p in Post,
    join: c in assoc(p, :category),
    group_by: c.name,
    select: {c.name, count(p.id)}
)

IO.puts("\n\nPosts per category:")
Enum.each(posts_by_category, fn {category_name, count} ->
  IO.puts("  #{category_name}: #{count} posts")
end)

# Tag stats
tag_usage = Repo.all(
  from t in Tag,
    left_join: pt in "post_tags", on: pt.tag_id == t.id,
    group_by: t.name,
    select: {t.name, count(pt.post_id)},
    order_by: [desc: count(pt.post_id)]
)

IO.puts("\n\nTop 10 most used tags:")
tag_usage
|> Enum.take(10)
|> Enum.each(fn {tag_name, count} ->
  IO.puts("  #{tag_name}: #{count} posts")
end)
