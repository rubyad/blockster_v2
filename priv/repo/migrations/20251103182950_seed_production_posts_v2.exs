defmodule BlocksterV2.Repo.Migrations.SeedProductionPostsV2 do
  use Ecto.Migration
  import Ecto.Query

  def up do
    # Delete all existing posts first
    execute "DELETE FROM post_tags"
    execute "DELETE FROM posts"

    # Get category and author IDs
    categories = repo().all(from c in "categories", select: {c.id, c.name})
    category_map = Map.new(categories, fn {id, name} -> {name, id} end)

    authors = repo().all(from u in "users", where: u.is_author == true, select: u.id)
    author_id = List.first(authors) || 1

    # Get all tag IDs
    tags = repo().all(from t in "tags", select: {t.id, t.name})
    tag_map = Map.new(tags, fn {id, name} -> {name, id} end)
    interview_tag_id = Map.get(tag_map, "Interview")

    # Featured images
    images = [
      "/images/bitcoin-guru.png",
      "/images/crypto-bull.png",
      "/images/delivering-speech.png",
      "/images/doge-coin.png",
      "/images/ecstatic.png",
      "/images/ethereum.png",
      "/images/group-shot.png",
      "/images/lifestyle-2.png",
      "/images/lifestyle-4.png",
      "/images/lifedtyle.png",
      "/images/w3-1.png",
      "/images/w3-2.png",
      "/images/w3-3.png",
      "/images/moonpay.png",
      "/images/nendorring.png",
      "/images/ad-banner.png"
    ]

    # Content template
    content = %{
      "type" => "doc",
      "content" => [
        %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Industry leaders announce breakthrough technology."}]},
        %{"type" => "paragraph"},
        %{"type" => "heading", "attrs" => %{"level" => 2}, "content" => [%{"type" => "text", "text" => "Key Highlights"}]},
        %{"type" => "bulletList", "content" => [
          %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Enhanced performance metrics"}]}]},
          %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Improved user experience"}]}]},
          %{"type" => "listItem", "content" => [%{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Advanced security features"}]}]}
        ]},
        %{"type" => "paragraph"},
        %{"type" => "blockquote", "content" => [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "This represents a major step forward for the industry."}]},
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "— Industry Expert"}]}
        ]},
        %{"type" => "paragraph"},
        %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "The sector continues to demonstrate strong growth and innovation potential."}]}
      ]
    }

    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    # Create 10 posts for each category
    Enum.each(category_map, fn {cat_name, cat_id} ->
      Enum.each(1..10, fn i ->
        days_ago = :rand.uniform(30)
        pub_date = DateTime.utc_now()
          |> DateTime.add(-days_ago * 86400, :second)
          |> DateTime.truncate(:second)

        timestamp = :os.system_time(:millisecond)
        title = "#{cat_name} Innovation #{i}: Revolutionary Breakthrough"
        slug = "#{title}-#{timestamp}"
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9\s-]/, "")
          |> String.replace(~r/\s+/, "-")
          |> String.trim("-")

        image = Enum.random(images)

        {:ok, result} = repo().query(
          "INSERT INTO posts (title, slug, excerpt, featured_image, content, published_at, author_id, category_id, view_count, inserted_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11) RETURNING id",
          [
            title,
            slug,
            "Major developments in #{cat_name} sector driving industry innovation.",
            image,
            content,
            pub_date,
            author_id,
            cat_id,
            0,
            now,
            now
          ]
        )

        post_id = result.rows |> List.first() |> List.first()

        # Add 6 random tags
        random_tags = tags |> Enum.take_random(6)

        # Add Interview tag on every 9th post
        final_tags = if rem(i, 9) == 0 and interview_tag_id do
          [{interview_tag_id, "Interview"} | random_tags] |> Enum.uniq()
        else
          random_tags
        end

        Enum.each(final_tags, fn {tag_id, _} ->
          repo().query(
            "INSERT INTO post_tags (post_id, tag_id) VALUES ($1, $2)",
            [post_id, tag_id]
          )
        end)
      end)
    end)
  end

  def down do
    execute "DELETE FROM post_tags"
    execute "DELETE FROM posts"
  end
end
