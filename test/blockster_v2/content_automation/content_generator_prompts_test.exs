defmodule BlocksterV2.ContentAutomation.ContentGeneratorPromptsTest do
  use BlocksterV2.DataCase, async: false

  import Mox

  alias BlocksterV2.ContentAutomation.ContentGenerator
  import BlocksterV2.ContentAutomation.Factory

  setup :verify_on_exit!

  defp create_author_persona(_) do
    [first | _] = create_author_personas()
    %{author: first}
  end

  defp mock_claude_returning_article(assert_fn \\ nil) do
    BlocksterV2.ContentAutomation.ClaudeClientMock
    |> expect(:call_with_tools, fn prompt, _tools, _opts ->
      if assert_fn, do: assert_fn.(prompt)

      {:ok, %{
        "title" => "Generated Test Article",
        "excerpt" => "A test article excerpt for validation.",
        "sections" => [
          %{"type" => "heading", "level" => 2, "text" => "Main Section"},
          %{"type" => "paragraph", "text" => String.duplicate("word ", 500)},
          %{"type" => "paragraph", "text" => "Another paragraph of content here."},
          %{"type" => "paragraph", "text" => "Third paragraph for quality checker."}
        ],
        "tags" => ["crypto", "bitcoin", "test"],
        "image_search_queries" => ["crypto bitcoin"],
        "tweet_suggestions" => [],
        "promotional_tweet" => nil
      }}
    end)
  end

  describe "prompt routing by content_type (on-demand)" do
    setup [:create_author_persona]

    test "content_type 'news' routes to news prompt (neutral, factual tone)", %{author: author} do
      mock_claude_returning_article(fn prompt ->
        assert prompt =~ "Neutral, factual, and professional"
        assert prompt =~ "Report the news"
      end)

      params = %{
        topic: "Bitcoin Hits All-Time High",
        category: "bitcoin",
        content_type: "news",
        instructions: "Bitcoin reached $100K today."
      }

      assert {:ok, _entry} = ContentGenerator.generate_on_demand(params)
    end

    test "content_type 'opinion' routes to opinion prompt (editorial tone)", %{author: author} do
      mock_claude_returning_article(fn prompt ->
        assert prompt =~ "Opinionated and direct"
        assert prompt =~ "pro-decentralization"
      end)

      params = %{
        topic: "Why DeFi Matters",
        category: "defi",
        content_type: "opinion",
        instructions: "Explore DeFi's impact."
      }

      assert {:ok, _entry} = ContentGenerator.generate_on_demand(params)
    end

    test "content_type 'offer' routes to offer prompt (opportunity tone)", %{author: author} do
      mock_claude_returning_article(fn prompt ->
        assert prompt =~ "opportunity"
        assert prompt =~ "not financial advice"
      end)

      params = %{
        topic: "New Yield Farm on Aave",
        category: "defi",
        content_type: "offer",
        instructions: "Aave launching new yield vault at 8% APY."
      }

      assert {:ok, _entry} = ContentGenerator.generate_on_demand(params)
    end

    test "nil content_type defaults to opinion prompt", %{author: author} do
      mock_claude_returning_article(fn prompt ->
        assert prompt =~ "Opinionated and direct"
      end)

      params = %{
        topic: "Default Content Type Test",
        category: "bitcoin",
        instructions: "Testing default content type."
      }

      assert {:ok, _entry} = ContentGenerator.generate_on_demand(params)
    end
  end

  describe "prompt routing by template (on-demand)" do
    setup [:create_author_persona]

    test "template 'blockster_of_week' routes to blockster prompt", %{author: author} do
      mock_claude_returning_article(fn prompt ->
        assert prompt =~ "profiling a notable figure"
        assert prompt =~ "Blockster of the Week" or prompt =~ "SUBJECT:"
      end)

      params = %{
        topic: "Vitalik Buterin",
        category: "blockster_of_week",
        content_type: "opinion",
        instructions: "Profile of Vitalik.",
        template: "blockster_of_week"
      }

      assert {:ok, _entry} = ContentGenerator.generate_on_demand(params)
    end

    test "template 'weekly_roundup' routes to roundup prompt", %{author: author} do
      mock_claude_returning_article(fn prompt ->
        assert prompt =~ "events editor"
        assert prompt =~ "upcoming"
      end)

      params = %{
        topic: "This Week in Crypto",
        category: "events",
        content_type: "news",
        instructions: "Events list here.",
        template: "weekly_roundup"
      }

      assert {:ok, _entry} = ContentGenerator.generate_on_demand(params)
    end

    test "template 'event_preview' routes to event preview prompt", %{author: author} do
      mock_claude_returning_article(fn prompt ->
        assert prompt =~ "upcoming major crypto event"
      end)

      params = %{
        topic: "ETH Denver 2026",
        category: "events",
        content_type: "news",
        instructions: "Preview of ETH Denver.",
        template: "event_preview"
      }

      assert {:ok, _entry} = ContentGenerator.generate_on_demand(params)
    end

    test "template 'market_movers' routes to market movers prompt", %{author: author} do
      mock_claude_returning_article(fn prompt ->
        assert prompt =~ "crypto market analyst"
        assert prompt =~ "altcoin price movements"
      end)

      params = %{
        topic: "Weekly Market Movers",
        category: "altcoins",
        content_type: "news",
        instructions: "Market data here.",
        template: "market_movers"
      }

      assert {:ok, _entry} = ContentGenerator.generate_on_demand(params)
    end

    test "template 'narrative_analysis' routes to narrative prompt", %{author: author} do
      mock_claude_returning_article(fn prompt ->
        assert prompt =~ "sector rotation"
      end)

      params = %{
        topic: "AI Sector Rally",
        category: "altcoins",
        content_type: "opinion",
        instructions: "AI sector analysis.",
        template: "narrative_analysis",
        sector: "ai",
        sector_data: %{direction: "rallying", avg_change: 15.0}
      }

      assert {:ok, _entry} = ContentGenerator.generate_on_demand(params)
    end

    test "nil template routes based on content_type", %{author: author} do
      mock_claude_returning_article(fn prompt ->
        assert prompt =~ "Neutral, factual"
      end)

      params = %{
        topic: "No Template Test",
        category: "bitcoin",
        content_type: "news",
        instructions: "Testing no template."
      }

      assert {:ok, _entry} = ContentGenerator.generate_on_demand(params)
    end
  end
end
