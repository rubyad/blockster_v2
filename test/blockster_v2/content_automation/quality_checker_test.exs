defmodule BlocksterV2.ContentAutomation.QualityCheckerTest do
  use BlocksterV2.DataCase, async: false

  alias BlocksterV2.ContentAutomation.QualityChecker
  import BlocksterV2.ContentAutomation.Factory

  defp valid_article(overrides \\ %{}) do
    content = build_valid_tiptap_content(500)

    Map.merge(
      %{
        title: "A Comprehensive Guide to Bitcoin Mining in 2026",
        excerpt: "Everything you need to know about Bitcoin mining today.",
        content: content,
        tags: ["bitcoin", "mining", "crypto"]
      },
      overrides
    )
  end

  describe "validate/1" do
    # Word count checks (350-1200 range)

    test "passes article with 500 words" do
      article = valid_article()
      assert :ok = QualityChecker.validate(article)
    end

    test "fails article with fewer than 350 words" do
      article = valid_article(%{content: build_valid_tiptap_content(200)})
      assert {:reject, failures} = QualityChecker.validate(article)
      assert Enum.any?(failures, fn {check, _} -> check == :word_count end)
    end

    test "fails article with more than 1200 words" do
      article = valid_article(%{content: build_valid_tiptap_content(1500)})
      assert {:reject, failures} = QualityChecker.validate(article)
      assert Enum.any?(failures, fn {check, _} -> check == :word_count end)
    end

    test "passes article at exact boundary (350 words)" do
      # 350 words in paragraph + heading + "Second paragraph..." + "Third paragraph..."
      # The tiptap content builder adds heading words + extra paragraphs
      # Let's build one that targets ~350 total words
      article = valid_article(%{content: build_valid_tiptap_content(340)})
      result = QualityChecker.validate(article)

      # With "Test Heading" (2 words) + 340 + "Second paragraph with some content." (5 words) + "Third paragraph for structure check." (5 words) = ~352
      assert result == :ok
    end

    # Structure checks

    test "fails article with missing title (nil)" do
      article = valid_article(%{title: nil})
      assert {:reject, failures} = QualityChecker.validate(article)
      assert Enum.any?(failures, fn {check, _} -> check == :structure end)
    end

    test "fails article with empty title" do
      article = valid_article(%{title: ""})
      assert {:reject, failures} = QualityChecker.validate(article)
      assert Enum.any?(failures, fn {check, _} -> check == :structure end)
    end

    test "fails article with missing excerpt" do
      article = valid_article(%{excerpt: nil})
      assert {:reject, failures} = QualityChecker.validate(article)
      assert Enum.any?(failures, fn {check, _} -> check == :structure end)
    end

    test "fails article with fewer than 3 paragraphs" do
      content = %{
        "type" => "doc",
        "content" => [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => String.duplicate("word ", 400)}]},
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Short."}]}
        ]
      }

      article = valid_article(%{content: content})
      assert {:reject, failures} = QualityChecker.validate(article)
      assert Enum.any?(failures, fn {check, _} -> check == :structure end)
    end

    test "passes article with 3+ paragraphs and valid title/excerpt" do
      article = valid_article()
      assert :ok = QualityChecker.validate(article)
    end

    # Tag checks

    test "passes article with 2-5 tags" do
      article = valid_article(%{tags: ["bitcoin", "mining"]})
      assert :ok = QualityChecker.validate(article)
    end

    test "fails article with fewer than 2 tags" do
      article = valid_article(%{tags: ["bitcoin"]})
      assert {:reject, failures} = QualityChecker.validate(article)
      assert Enum.any?(failures, fn {check, _} -> check == :tags end)
    end

    test "fails article with more than 5 tags" do
      article = valid_article(%{tags: ["a", "b", "c", "d", "e", "f"]})
      assert {:reject, failures} = QualityChecker.validate(article)
      assert Enum.any?(failures, fn {check, _} -> check == :tags end)
    end

    test "fails article with empty tags list" do
      article = valid_article(%{tags: []})
      assert {:reject, failures} = QualityChecker.validate(article)
      assert Enum.any?(failures, fn {check, _} -> check == :tags end)
    end

    # TipTap format validation

    test "passes valid TipTap doc" do
      article = valid_article()
      assert :ok = QualityChecker.validate(article)
    end

    test "fails invalid TipTap (missing type key)" do
      article = valid_article(%{content: %{"content" => []}})
      assert {:reject, failures} = QualityChecker.validate(article)
      assert Enum.any?(failures, fn {check, _} -> check == :tiptap_valid end)
    end

    test "fails invalid TipTap (content is not a list)" do
      # Use a content that won't crash word_count but is invalid TipTap
      article = valid_article(%{content: %{"type" => "invalid"}})
      assert {:reject, failures} = QualityChecker.validate(article)
      assert Enum.any?(failures, fn {check, _} -> check == :tiptap_valid end)
    end

    # Duplicate detection

    test "passes article with unique title" do
      article = valid_article(%{title: "Totally Unique Article About Quantum Computing #{System.unique_integer([:positive])}"})
      assert :ok = QualityChecker.validate(article)
    end

    test "fails article with title too similar to recent article" do
      # Insert a topic with a similar title
      Repo.insert!(%BlocksterV2.ContentAutomation.ContentGeneratedTopic{
        title: "Bitcoin Mining Revolution Changes Everything"
      })

      article = valid_article(%{title: "Bitcoin Mining Revolution Changes Everything Now"})
      result = QualityChecker.validate(article)
      assert {:reject, failures} = result
      assert Enum.any?(failures, fn {check, _} -> check == :duplicate end)
    end

    # Multiple failures

    test "returns all failures when multiple checks fail simultaneously" do
      article = %{
        title: nil,
        excerpt: nil,
        content: %{"wrong" => "format"},
        tags: []
      }

      assert {:reject, failures} = QualityChecker.validate(article)
      # Should have failures for structure (nil title), tags, tiptap_valid, word_count
      assert length(failures) >= 3
    end
  end
end
