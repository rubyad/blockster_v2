defmodule BlocksterV2.ContentAutomation.FeedStoreTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.ContentAutomation.{FeedStore, ContentFeedItem, ContentPublishQueue}
  import BlocksterV2.ContentAutomation.Factory

  defp create_author(_) do
    {:ok, user} =
      %BlocksterV2.Accounts.User{}
      |> Ecto.Changeset.change(%{
        email: "author#{System.unique_integer([:positive])}@test.com",
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}",
        is_admin: true
      })
      |> Repo.insert()

    %{author: user}
  end

  describe "store_new_items/1" do
    test "inserts multiple feed items and returns count" do
      items = [
        build_feed_item(%{url: "https://example.com/1", title: "Article 1", source: "Source1", tier: "standard"}),
        build_feed_item(%{url: "https://example.com/2", title: "Article 2", source: "Source2", tier: "standard"})
      ]

      {count, _} = FeedStore.store_new_items(items)
      assert count == 2
    end

    test "skips duplicates by URL (on_conflict: :nothing)" do
      items = [
        build_feed_item(%{url: "https://example.com/dup", title: "First", source: "S1", tier: "standard"})
      ]

      FeedStore.store_new_items(items)
      {count, _} = FeedStore.store_new_items(items)
      assert count == 0
    end

    test "handles empty list" do
      {count, _} = FeedStore.store_new_items([])
      assert count == 0
    end
  end

  describe "get_recent_unprocessed/1" do
    test "returns items within time window" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert!(%ContentFeedItem{
        url: "https://example.com/recent-#{System.unique_integer([:positive])}",
        title: "Recent Item",
        source: "Test",
        tier: "standard",
        fetched_at: now,
        processed: false
      })

      results = FeedStore.get_recent_unprocessed(hours: 12)
      assert length(results) >= 1
      assert Enum.any?(results, &(&1.title == "Recent Item"))
    end

    test "excludes already-processed items" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      Repo.insert!(%ContentFeedItem{
        url: "https://example.com/processed-#{System.unique_integer([:positive])}",
        title: "Processed Item",
        source: "Test",
        tier: "standard",
        fetched_at: now,
        processed: true
      })

      results = FeedStore.get_recent_unprocessed(hours: 12)
      refute Enum.any?(results, &(&1.title == "Processed Item"))
    end
  end

  describe "get_queue_entries/1" do
    setup [:create_author]

    test "filters by status", %{author: author} do
      insert_queue_entry(%{status: "pending", author_id: author.id})
      insert_queue_entry(%{status: "published", author_id: author.id})

      pending = FeedStore.get_queue_entries(status: "pending")
      assert length(pending) >= 1
      assert Enum.all?(pending, &(&1.status == "pending"))
    end

    test "returns entries ordered by inserted_at descending", %{author: author} do
      insert_queue_entry(%{status: "pending", author_id: author.id})
      insert_queue_entry(%{status: "pending", author_id: author.id})

      entries = FeedStore.get_queue_entries(status: "pending")
      inserted_ats = Enum.map(entries, & &1.inserted_at)
      assert inserted_ats == Enum.sort(inserted_ats, {:desc, NaiveDateTime})
    end

    test "supports pagination", %{author: author} do
      for _ <- 1..5, do: insert_queue_entry(%{status: "pending", author_id: author.id})

      page1 = FeedStore.get_queue_entries(status: "pending", per_page: 2, page: 1)
      page2 = FeedStore.get_queue_entries(status: "pending", per_page: 2, page: 2)

      assert length(page1) == 2
      assert length(page2) == 2
    end
  end

  describe "count_queued/0" do
    setup [:create_author]

    test "counts entries with status pending, draft, or approved", %{author: author} do
      insert_queue_entry(%{status: "pending", author_id: author.id})
      insert_queue_entry(%{status: "draft", author_id: author.id})
      insert_queue_entry(%{status: "approved", author_id: author.id})

      count = FeedStore.count_queued()
      assert count >= 3
    end

    test "excludes published and rejected entries", %{author: author} do
      insert_queue_entry(%{status: "published", author_id: author.id})
      insert_queue_entry(%{status: "rejected", author_id: author.id})

      count = FeedStore.count_queued()
      # These should not be counted
      assert count == 0
    end
  end

  describe "count_queued_by_content_type/0" do
    setup [:create_author]

    test "returns map with news, opinion, offer counts", %{author: author} do
      insert_queue_entry(%{status: "pending", content_type: "news", author_id: author.id})
      insert_queue_entry(%{status: "pending", content_type: "opinion", author_id: author.id})

      result = FeedStore.count_queued_by_content_type()
      assert Map.has_key?(result, :news)
      assert Map.has_key?(result, :opinion)
      assert result.news >= 1
      assert result.opinion >= 1
    end

    test "returns zeros when queue is empty" do
      result = FeedStore.count_queued_by_content_type()
      assert result == %{news: 0, opinion: 0, offer: 0}
    end
  end

  describe "get_published_expired_offers/1" do
    setup [:create_author]

    test "returns published entries where expires_at < now and content_type == offer", %{author: author} do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      {:ok, post} = BlocksterV2.Blog.create_post(%{title: "Offer Post", content: %{}, author_id: author.id})

      insert_queue_entry(%{
        status: "published",
        content_type: "offer",
        expires_at: past,
        post_id: post.id,
        author_id: author.id
      })

      results = FeedStore.get_published_expired_offers(DateTime.utc_now())
      assert length(results) >= 1
      assert Enum.all?(results, &(&1.content_type == "offer"))
    end

    test "excludes non-offer entries even if they have expires_at", %{author: author} do
      past = DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:second)
      {:ok, post} = BlocksterV2.Blog.create_post(%{title: "News Post", content: %{}, author_id: author.id})

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

    test "excludes offers that haven't expired yet", %{author: author} do
      future = DateTime.utc_now() |> DateTime.add(3600, :second) |> DateTime.truncate(:second)
      {:ok, post} = BlocksterV2.Blog.create_post(%{title: "Future Offer", content: %{}, author_id: author.id})

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

    test "returns empty list when no expired offers exist" do
      results = FeedStore.get_published_expired_offers(DateTime.utc_now())
      assert results == []
    end
  end

  describe "mark_queue_entry_published/2" do
    setup [:create_author]

    test "sets status to published and stores post_id", %{author: author} do
      entry = insert_queue_entry(%{status: "pending", author_id: author.id})

      {:ok, post} =
        BlocksterV2.Blog.create_post(%{
          title: "Test Post for Mark Published",
          content: %{},
          author_id: author.id
        })

      {:ok, updated} = FeedStore.mark_queue_entry_published(entry.id, post.id)

      assert updated.status == "published"
      assert updated.post_id == post.id
      assert updated.reviewed_at != nil
    end
  end

  describe "reject_queue_entry/2" do
    setup [:create_author]

    test "sets status to rejected and stores rejection reason", %{author: author} do
      entry = insert_queue_entry(%{status: "pending", author_id: author.id})

      {:ok, updated} = FeedStore.reject_queue_entry(entry.id, "Low quality")

      assert updated.status == "rejected"
      assert updated.rejected_reason == "Low quality"
    end
  end

  describe "enqueue_article/1" do
    setup [:create_author]

    test "creates queue entry with correct fields", %{author: author} do
      {:ok, entry} =
        FeedStore.enqueue_article(%{
          article_data: %{"title" => "Test", "content" => %{}, "excerpt" => "Ex"},
          author_id: author.id,
          status: "pending",
          content_type: "news"
        })

      assert entry.status == "pending"
      assert entry.content_type == "news"
      assert entry.article_data["title"] == "Test"
    end

    test "sets content_type from params", %{author: author} do
      {:ok, entry} =
        FeedStore.enqueue_article(%{
          article_data: %{"title" => "Offer", "content" => %{}},
          author_id: author.id,
          status: "pending",
          content_type: "offer"
        })

      assert entry.content_type == "offer"
    end

    test "returns {:ok, entry} on success", %{author: author} do
      result =
        FeedStore.enqueue_article(%{
          article_data: %{"title" => "Test", "content" => %{}},
          author_id: author.id,
          status: "pending"
        })

      assert {:ok, %ContentPublishQueue{}} = result
    end
  end
end
