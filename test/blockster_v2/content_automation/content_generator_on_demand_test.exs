defmodule BlocksterV2.ContentAutomation.ContentGeneratorOnDemandTest do
  use BlocksterV2.DataCase, async: false

  import Mox

  alias BlocksterV2.ContentAutomation.{ContentGenerator, FeedStore}
  import BlocksterV2.ContentAutomation.Factory

  setup :verify_on_exit!

  defp create_author(_) do
    [first | _] = create_author_personas()
    %{author: first}
  end

  defp mock_claude_success do
    BlocksterV2.ContentAutomation.ClaudeClientMock
    |> expect(:call_with_tools, fn _prompt, _tools, _opts ->
      {:ok, %{
        "title" => "On-Demand Test Article",
        "excerpt" => "An on-demand generated test article.",
        "sections" => [
          %{"type" => "heading", "level" => 2, "text" => "Generated Topic"},
          %{"type" => "paragraph", "text" => String.duplicate("word ", 500)},
          %{"type" => "paragraph", "text" => "Second paragraph of generated content."},
          %{"type" => "paragraph", "text" => "Third paragraph for quality."}
        ],
        "tags" => ["bitcoin", "test", "generated"],
        "image_search_queries" => ["bitcoin test"],
        "tweet_suggestions" => ["Check out this article!"],
        "promotional_tweet" => "New article on Bitcoin"
      }}
    end)
  end

  describe "generate_on_demand/1" do
    setup [:create_author]

    test "creates queue entry with status 'pending' on success", %{author: _author} do
      mock_claude_success()

      params = %{
        topic: "Bitcoin Testing Article",
        category: "bitcoin",
        content_type: "news",
        instructions: "Write about Bitcoin testing."
      }

      assert {:ok, entry} = ContentGenerator.generate_on_demand(params)
      assert entry.status == "pending"
    end

    test "stores content_type from params on queue entry", %{author: _author} do
      mock_claude_success()

      params = %{
        topic: "Opinion Article",
        category: "defi",
        content_type: "opinion",
        instructions: "Write an opinion."
      }

      assert {:ok, entry} = ContentGenerator.generate_on_demand(params)
      assert entry.content_type == "opinion"
    end

    test "returns {:ok, entry} with article_data containing title, content, excerpt, tags", %{author: _author} do
      mock_claude_success()

      params = %{
        topic: "Full Article",
        category: "bitcoin",
        content_type: "news",
        instructions: "Full article test."
      }

      assert {:ok, entry} = ContentGenerator.generate_on_demand(params)
      # Reload from DB so JSONB keys are consistently strings
      entry = Repo.get!(BlocksterV2.ContentAutomation.ContentPublishQueue, entry.id)
      assert entry.article_data["title"] == "On-Demand Test Article"
      assert entry.article_data["excerpt"] == "An on-demand generated test article."
      assert is_map(entry.article_data["content"])
      assert is_list(entry.article_data["tags"])
    end

    test "returns {:error, reason} when Claude API fails", %{author: _author} do
      BlocksterV2.ContentAutomation.ClaudeClientMock
      |> expect(:call_with_tools, fn _prompt, _tools, _opts ->
        {:error, :api_timeout}
      end)

      params = %{
        topic: "Failing Article",
        category: "bitcoin",
        content_type: "news",
        instructions: "This should fail."
      }

      assert {:error, :api_timeout} = ContentGenerator.generate_on_demand(params)
    end

    test "broadcasts PubSub event on success", %{author: _author} do
      mock_claude_success()
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "content_automation")

      params = %{
        topic: "PubSub Test Article",
        category: "bitcoin",
        content_type: "news",
        instructions: "Testing PubSub broadcast."
      }

      assert {:ok, _entry} = ContentGenerator.generate_on_demand(params)

      assert_receive {:content_automation, :article_enqueued, _entry}, 1000
    end

    test "bypasses queue size limits (always generates)", %{author: _author} do
      mock_claude_success()

      # On-demand generation should work regardless of queue size
      params = %{
        topic: "Queue Bypass Article",
        category: "bitcoin",
        content_type: "news",
        instructions: "Should bypass limits."
      }

      assert {:ok, _entry} = ContentGenerator.generate_on_demand(params)
    end

    test "stores category from params", %{author: _author} do
      mock_claude_success()

      params = %{
        topic: "Category Test",
        category: "altcoins",
        content_type: "news",
        instructions: "Test category storage."
      }

      assert {:ok, entry} = ContentGenerator.generate_on_demand(params)
      # Reload from DB so JSONB keys are consistently strings
      entry = Repo.get!(BlocksterV2.ContentAutomation.ContentPublishQueue, entry.id)
      assert entry.article_data["category"] == "altcoins"
    end
  end
end
