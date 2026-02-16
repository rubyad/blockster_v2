defmodule BlocksterV2.ContentAutomation.TopicEngineLogicTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.ContentAutomation.{TopicEngine, Settings}
  import BlocksterV2.ContentAutomation.Factory

  setup do
    ensure_mnesia_tables()
    Settings.init_cache()

    on_exit(fn ->
      try do
        :mnesia.dirty_delete(:content_automation_settings, :category_config)
        :ets.delete_all_objects(:content_settings_cache)
      rescue
        _ -> :ok
      end
    end)

    :ok
  end

  defp create_author(_) do
    {:ok, user} =
      %BlocksterV2.Accounts.User{}
      |> Ecto.Changeset.change(%{
        email: "topic_test#{System.unique_integer([:positive])}@test.com",
        wallet_address: "0x#{:crypto.strong_rand_bytes(20) |> Base.encode16(case: :lower)}"
      })
      |> Repo.insert()

    %{author: user}
  end

  describe "enforce_content_mix/1" do
    setup [:create_author]

    test "when news_ratio < 50%, news topics are moved to front", %{author: author} do
      # Set up queue: more opinion than news
      insert_queue_entry(%{status: "pending", content_type: "opinion", author_id: author.id})
      insert_queue_entry(%{status: "pending", content_type: "opinion", author_id: author.id})
      insert_queue_entry(%{status: "pending", content_type: "opinion", author_id: author.id})
      insert_queue_entry(%{status: "pending", content_type: "news", author_id: author.id})

      topics = [
        %{title: "Opinion Topic", content_type: "opinion"},
        %{title: "News Topic A", content_type: "news"},
        %{title: "News Topic B", content_type: "news"}
      ]

      result = TopicEngine.enforce_content_mix(topics)

      # News topics should be moved to front
      assert hd(result).content_type == "news"
      first_two = Enum.take(result, 2)
      assert Enum.all?(first_two, &(&1.content_type == "news"))
    end

    test "when news_ratio >= 50%, topics remain in original order", %{author: author} do
      # Set up queue: balanced
      insert_queue_entry(%{status: "pending", content_type: "news", author_id: author.id})
      insert_queue_entry(%{status: "pending", content_type: "opinion", author_id: author.id})

      topics = [
        %{title: "Opinion Topic", content_type: "opinion"},
        %{title: "News Topic", content_type: "news"}
      ]

      result = TopicEngine.enforce_content_mix(topics)

      # Should remain in original order since ratio is 50%
      assert hd(result).title == "Opinion Topic"
    end

    test "when queue is empty, topics remain in original order" do
      topics = [
        %{title: "Opinion Topic", content_type: "opinion"},
        %{title: "News Topic", content_type: "news"}
      ]

      result = TopicEngine.enforce_content_mix(topics)
      assert hd(result).title == "Opinion Topic"
    end

    test "handles list with only news topics", %{author: author} do
      insert_queue_entry(%{status: "pending", content_type: "opinion", author_id: author.id})

      topics = [
        %{title: "News A", content_type: "news"},
        %{title: "News B", content_type: "news"}
      ]

      result = TopicEngine.enforce_content_mix(topics)
      assert length(result) == 2
    end

    test "handles list with only opinion topics", %{author: author} do
      insert_queue_entry(%{status: "pending", content_type: "opinion", author_id: author.id})
      insert_queue_entry(%{status: "pending", content_type: "opinion", author_id: author.id})

      topics = [
        %{title: "Opinion A", content_type: "opinion"},
        %{title: "Opinion B", content_type: "opinion"}
      ]

      result = TopicEngine.enforce_content_mix(topics)
      assert length(result) == 2
    end

    test "handles empty topic list" do
      result = TopicEngine.enforce_content_mix([])
      assert result == []
    end
  end

  describe "apply_category_diversity/1" do
    setup [:create_author]

    test "limits topics per category to max_per_day (default 2)", %{author: author} do
      # Create real posts so we can set article_id on ContentGeneratedTopic (FK to posts)
      for _ <- 1..2 do
        post = Repo.insert!(%BlocksterV2.Blog.Post{
          title: "BTC Post #{System.unique_integer([:positive])}",
          slug: "btc-post-#{System.unique_integer([:positive])}",
          author_id: author.id
        })
        Repo.insert!(%BlocksterV2.ContentAutomation.ContentGeneratedTopic{
          title: "BTC Topic #{System.unique_integer([:positive])}",
          category: "bitcoin",
          article_id: post.id
        })
      end

      topics = [
        %{title: "BTC Topic 1", category: "bitcoin"},
        %{title: "BTC Topic 2", category: "bitcoin"},
        %{title: "BTC Topic 3", category: "bitcoin"},
        %{title: "DeFi Topic 1", category: "defi"}
      ]

      result = TopicEngine.apply_category_diversity(topics)

      # Should keep max 2 bitcoin topics and the defi topic
      bitcoin_count = Enum.count(result, &(&1.category == "bitcoin"))
      assert bitcoin_count <= 2
      assert Enum.any?(result, &(&1.category == "defi"))
    end

    test "keeps topics from different categories" do
      topics = [
        %{title: "BTC Topic", category: "bitcoin"},
        %{title: "DeFi Topic", category: "defi"},
        %{title: "ETH Topic", category: "ethereum"},
        %{title: "NFT Topic", category: "nft"}
      ]

      result = TopicEngine.apply_category_diversity(topics)
      assert length(result) == 4
    end

    test "handles empty topic list" do
      result = TopicEngine.apply_category_diversity([])
      assert result == []
    end
  end
end
