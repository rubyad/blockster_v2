alias BlocksterV2.Repo
alias BlocksterV2.Blog.Post
alias BlocksterV2.Blog.Tag
alias BlocksterV2.Blog.Category
import Ecto.Query

# Get all existing posts with their metadata
existing_posts = Repo.all(
  from p in Post,
    preload: [:tags, :category],
    select: p
)

IO.puts("Found #{length(existing_posts)} posts to recreate")
IO.puts("")

# Store post metadata
posts_metadata = Enum.map(existing_posts, fn post ->
  %{
    title: post.title,
    slug: post.slug,
    excerpt: post.excerpt,
    category_id: post.category_id,
    category_name: post.category.name,
    featured_image: post.featured_image,
    author_name: post.author_name,
    published_at: post.published_at,
    custom_published_at: post.custom_published_at,
    tags: Enum.map(post.tags, & &1.name)
  }
end)

# Delete all posts
{deleted_count, _} = Repo.delete_all(Post)
IO.puts("Deleted #{deleted_count} posts")
IO.puts("")

# TipTap format sample content
sample_tiptap_content = %{
  "type" => "doc",
  "content" => [
    %{
      "type" => "paragraph",
      "content" => [
        %{
          "type" => "text",
          "marks" => [%{"type" => "italic"}],
          "text" => "Breaking news in the crypto space. Major innovation announced today."
        }
      ]
    },
    %{"type" => "paragraph"},
    %{
      "type" => "paragraph",
      "content" => [
        %{
          "type" => "text",
          "text" => "This groundbreaking development is set to revolutionize the industry."
        }
      ]
    },
    %{"type" => "paragraph"},
    %{
      "type" => "blockquote",
      "content" => [
        %{
          "type" => "paragraph",
          "content" => [
            %{
              "type" => "text",
              "text" => "We're incredibly excited about this innovation."
            }
          ]
        },
        %{
          "type" => "paragraph",
          "content" => [
            %{
              "type" => "text",
              "text" => "— Company CEO"
            }
          ]
        }
      ]
    },
    %{"type" => "paragraph"},
    %{
      "type" => "heading",
      "attrs" => %{"level" => 2},
      "content" => [
        %{
          "type" => "text",
          "text" => "Why It Matters"
        }
      ]
    },
    %{
      "type" => "paragraph",
      "content" => [
        %{
          "type" => "text",
          "text" => "Key benefits include:"
        }
      ]
    },
    %{
      "type" => "bulletList",
      "content" => [
        %{
          "type" => "listItem",
          "content" => [
            %{
              "type" => "paragraph",
              "content" => [
                %{"type" => "text", "text" => "Instant transactions"}
              ]
            }
          ]
        },
        %{
          "type" => "listItem",
          "content" => [
            %{
              "type" => "paragraph",
              "content" => [
                %{"type" => "text", "text" => "Lower fees"}
              ]
            }
          ]
        },
        %{
          "type" => "listItem",
          "content" => [
            %{
              "type" => "paragraph",
              "content" => [
                %{"type" => "text", "text" => "Enhanced security"}
              ]
            }
          ]
        },
        %{
          "type" => "listItem",
          "content" => [
            %{
              "type" => "paragraph",
              "content" => [
                %{"type" => "text", "text" => "Improved user experience"}
              ]
            }
          ]
        },
        %{
          "type" => "listItem",
          "content" => [
            %{
              "type" => "paragraph",
              "content" => [
                %{"type" => "text", "text" => "24/7 support"}
              ]
            }
          ]
        }
      ]
    },
    %{"type" => "paragraph"},
    %{
      "type" => "tweetEmbed",
      "attrs" => %{
        "url" => "https://x.com/twitter/status/20",
        "id" => "20"
      }
    },
    %{"type" => "paragraph"},
    %{
      "type" => "heading",
      "attrs" => %{"level" => 2},
      "content" => [
        %{
          "type" => "text",
          "text" => "Technical Details"
        }
      ]
    },
    %{
      "type" => "paragraph",
      "content" => [
        %{
          "type" => "text",
          "text" => "The platform leverages cutting-edge technology to deliver unprecedented performance."
        }
      ]
    }
  ]
}

# Recreate posts with TipTap format
IO.puts("Recreating posts with TipTap format...")
IO.puts("")

Enum.each(posts_metadata, fn metadata ->
  # Create post
  {:ok, post} = %Post{}
  |> Post.changeset(%{
    title: metadata.title,
    slug: metadata.slug,
    excerpt: metadata.excerpt,
    content: sample_tiptap_content,
    category_id: metadata.category_id,
    featured_image: metadata.featured_image,
    author_name: metadata.author_name,
    published_at: metadata.published_at,
    custom_published_at: metadata.custom_published_at
  })
  |> Repo.insert()

  # Add tags
  tag_records = Enum.map(metadata.tags, fn tag_name ->
    Repo.get_by(Tag, name: tag_name)
  end)
  |> Enum.filter(& &1)  # Remove nils

  # Directly insert into post_tags join table
  Enum.each(tag_records, fn tag ->
    Repo.insert_all(
      "post_tags",
      [%{post_id: post.id, tag_id: tag.id, inserted_at: NaiveDateTime.utc_now(), updated_at: NaiveDateTime.utc_now()}],
      on_conflict: :nothing
    )
  end)

  IO.puts("✓ Created: #{metadata.title} (#{metadata.category_name})")
end)

IO.puts("")
IO.puts("Done! All posts recreated with TipTap format.")

# Verify
final_count = Repo.aggregate(Post, :count)
IO.puts("Total posts in database: #{final_count}")
