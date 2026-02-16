defmodule BlocksterV2.ContentAutomation.ContentQueueOffersTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.ContentAutomation.FeedStore
  import BlocksterV2.ContentAutomation.Factory

  defp create_author(_) do
    {:ok, user} =
      %BlocksterV2.Accounts.User{}
      |> Ecto.Changeset.change(%{
        email: "offers_author#{System.unique_integer([:positive])}@test.com",
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        is_admin: true
      })
      |> Repo.insert()

    %{author: user}
  end

  describe "expired offer detection" do
    setup [:create_author]

    test "finds expired offers (expires_at in the past)", %{author: author} do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

      {:ok, post} =
        BlocksterV2.Blog.create_post(%{
          title: "Expired Offer Post",
          content: %{},
          author_id: author.id
        })

      insert_queue_entry(%{
        status: "published",
        content_type: "offer",
        expires_at: past,
        post_id: post.id,
        author_id: author.id
      })

      results = FeedStore.get_published_expired_offers(DateTime.utc_now())
      assert length(results) >= 1
    end

    test "does not find offers that haven't expired yet", %{author: author} do
      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)

      {:ok, post} =
        BlocksterV2.Blog.create_post(%{
          title: "Future Offer Post",
          content: %{},
          author_id: author.id
        })

      insert_queue_entry(%{
        status: "published",
        content_type: "offer",
        expires_at: future,
        post_id: post.id,
        author_id: author.id
      })

      results = FeedStore.get_published_expired_offers(DateTime.utc_now())
      assert results == []
    end

    test "does not find non-offer entries even if they have expires_at", %{author: author} do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)

      {:ok, post} =
        BlocksterV2.Blog.create_post(%{
          title: "News With Expiry",
          content: %{},
          author_id: author.id
        })

      insert_queue_entry(%{
        status: "published",
        content_type: "news",
        expires_at: past,
        post_id: post.id,
        author_id: author.id
      })

      results = FeedStore.get_published_expired_offers(DateTime.utc_now())
      assert results == []
    end
  end
end
