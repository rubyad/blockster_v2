defmodule BlocksterV2.ContentAutomation.ContentPublisherDraftTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.ContentAutomation.{ContentPublisher, FeedStore}
  alias BlocksterV2.Blog
  import BlocksterV2.ContentAutomation.Factory

  defp create_author(_) do
    {:ok, user} =
      %BlocksterV2.Accounts.User{}
      |> Ecto.Changeset.change(%{
        email: "draft_author#{System.unique_integer([:positive])}@test.com",
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        is_admin: true,
        is_author: true
      })
      |> Repo.insert()

    %{author: user}
  end

  describe "create_draft_post/1" do
    setup [:create_author]

    test "creates a post in the database with correct title, content, excerpt, slug", %{author: author} do
      entry = insert_queue_entry(%{author_id: author.id})

      {:ok, post} = ContentPublisher.create_draft_post(entry)

      assert post.title == entry.article_data["title"]
      assert post.content == entry.article_data["content"]
      assert post.excerpt == entry.article_data["excerpt"]
      assert post.slug != nil
    end

    test "does NOT set published_at (leaves nil - post is a draft)", %{author: author} do
      entry = insert_queue_entry(%{author_id: author.id})

      {:ok, post} = ContentPublisher.create_draft_post(entry)

      assert post.published_at == nil
    end

    test "stores post_id on the queue entry", %{author: author} do
      entry = insert_queue_entry(%{author_id: author.id})

      {:ok, post} = ContentPublisher.create_draft_post(entry)

      updated_entry = FeedStore.get_queue_entry(entry.id)
      assert updated_entry.post_id == post.id
    end

    test "returns {:ok, post} on success", %{author: author} do
      entry = insert_queue_entry(%{author_id: author.id})

      result = ContentPublisher.create_draft_post(entry)

      assert {:ok, %BlocksterV2.Blog.Post{}} = result
    end
  end

  describe "cleanup_draft_post/1" do
    setup [:create_author]

    test "deletes unpublished post (published_at nil) and returns :ok", %{author: author} do
      {:ok, post} =
        Blog.create_post(%{
          title: "Draft to delete",
          content: %{},
          author_id: author.id
        })

      assert post.published_at == nil
      assert :ok = ContentPublisher.cleanup_draft_post(post.id)
      assert Repo.get(Blog.Post, post.id) == nil
    end

    test "does NOT delete published post (published_at set)", %{author: author} do
      {:ok, post} =
        Blog.create_post(%{
          title: "Published post",
          content: %{},
          author_id: author.id
        })

      {:ok, published_post} = Blog.publish_post(post)
      assert published_post.published_at != nil

      assert :ok = ContentPublisher.cleanup_draft_post(published_post.id)
      assert Repo.get(Blog.Post, published_post.id) != nil
    end

    test "handles nil post_id gracefully" do
      assert :ok = ContentPublisher.cleanup_draft_post(nil)
    end

    test "handles non-existent post_id gracefully" do
      assert :ok = ContentPublisher.cleanup_draft_post(999_999)
    end
  end
end
