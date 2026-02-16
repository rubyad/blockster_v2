defmodule BlocksterV2.ContentAutomation.TipTapBuilderTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.ContentAutomation.TipTapBuilder

  describe "build/1" do
    test "converts heading sections to TipTap heading nodes (default level 2)" do
      sections = [%{"type" => "heading", "text" => "My Heading"}]
      result = TipTapBuilder.build(sections)

      assert %{"type" => "doc", "content" => [node]} = result
      assert node["type"] == "heading"
      assert node["attrs"]["level"] == 2
      assert [%{"type" => "text", "text" => "My Heading"}] = node["content"]
    end

    test "converts heading sections with custom level" do
      sections = [%{"type" => "heading", "text" => "Sub Heading", "level" => 3}]
      result = TipTapBuilder.build(sections)

      assert %{"type" => "doc", "content" => [node]} = result
      assert node["attrs"]["level"] == 3
    end

    test "converts paragraph sections to TipTap paragraph nodes" do
      sections = [%{"type" => "paragraph", "text" => "Hello world"}]
      result = TipTapBuilder.build(sections)

      assert %{"type" => "doc", "content" => [node]} = result
      assert node["type"] == "paragraph"
      assert [%{"type" => "text", "text" => "Hello world"}] = node["content"]
    end

    test "converts bullet_list sections to TipTap bulletList nodes" do
      sections = [%{"type" => "bullet_list", "items" => ["Item 1", "Item 2"]}]
      result = TipTapBuilder.build(sections)

      assert %{"type" => "doc", "content" => [node]} = result
      assert node["type"] == "bulletList"
      assert length(node["content"]) == 2

      [item1, item2] = node["content"]
      assert item1["type"] == "listItem"
      assert item2["type"] == "listItem"
    end

    test "converts ordered_list sections to TipTap orderedList nodes" do
      sections = [%{"type" => "ordered_list", "items" => ["First", "Second", "Third"]}]
      result = TipTapBuilder.build(sections)

      assert %{"type" => "doc", "content" => [node]} = result
      assert node["type"] == "orderedList"
      assert length(node["content"]) == 3
    end

    test "converts blockquote sections to TipTap blockquote nodes" do
      sections = [%{"type" => "blockquote", "text" => "A wise quote"}]
      result = TipTapBuilder.build(sections)

      assert %{"type" => "doc", "content" => [node]} = result
      assert node["type"] == "blockquote"
      assert [%{"type" => "paragraph", "content" => _}] = node["content"]
    end

    test "converts code_block sections to TipTap codeBlock nodes" do
      sections = [%{"type" => "code_block", "text" => "def foo, do: :bar"}]
      result = TipTapBuilder.build(sections)

      assert %{"type" => "doc", "content" => [node]} = result
      assert node["type"] == "codeBlock"
      assert [%{"type" => "text", "text" => "def foo, do: :bar"}] = node["content"]
    end

    test "handles image sections with src attribute" do
      sections = [%{"type" => "image", "src" => "https://example.com/img.jpg"}]
      result = TipTapBuilder.build(sections)

      assert %{"type" => "doc", "content" => [node]} = result
      assert node["type"] == "image"
      assert node["attrs"]["src"] == "https://example.com/img.jpg"
    end

    test "handles empty section list" do
      assert %{"type" => "doc", "content" => []} = TipTapBuilder.build([])
    end

    test "handles non-list input" do
      assert %{"type" => "doc", "content" => []} = TipTapBuilder.build("not a list")
      assert %{"type" => "doc", "content" => []} = TipTapBuilder.build(nil)
      assert %{"type" => "doc", "content" => []} = TipTapBuilder.build(42)
    end

    test "handles mixed section types in order" do
      sections = [
        %{"type" => "heading", "text" => "Title"},
        %{"type" => "paragraph", "text" => "Body text"},
        %{"type" => "bullet_list", "items" => ["a", "b"]}
      ]

      result = TipTapBuilder.build(sections)
      assert %{"type" => "doc", "content" => nodes} = result
      assert length(nodes) == 3
      assert Enum.map(nodes, & &1["type"]) == ["heading", "paragraph", "bulletList"]
    end
  end

  describe "parse_inline_marks/1" do
    test "parses **bold** text to bold marks" do
      result = TipTapBuilder.parse_inline_marks("This is **bold** text")

      bold_node = Enum.find(result, fn n -> n["marks"] != nil and hd(n["marks"])["type"] == "bold" end)
      assert bold_node
      assert bold_node["text"] == "bold"
    end

    test "parses *italic* text to italic marks" do
      result = TipTapBuilder.parse_inline_marks("This is *italic* text")

      italic_node = Enum.find(result, fn n -> n["marks"] != nil and hd(n["marks"])["type"] == "italic" end)
      assert italic_node
      assert italic_node["text"] == "italic"
    end

    test "parses ~~strikethrough~~ text" do
      result = TipTapBuilder.parse_inline_marks("This is ~~struck~~ text")

      strike_node = Enum.find(result, fn n -> n["marks"] != nil and hd(n["marks"])["type"] == "strike" end)
      assert strike_node
      assert strike_node["text"] == "struck"
    end

    test "parses `code` inline to code marks" do
      result = TipTapBuilder.parse_inline_marks("Use `mix test` here")

      code_node = Enum.find(result, fn n -> n["marks"] != nil and hd(n["marks"])["type"] == "code" end)
      assert code_node
      assert code_node["text"] == "mix test"
    end

    test "parses [text](url) to link marks" do
      result = TipTapBuilder.parse_inline_marks("Visit [Blockster](https://blockster.com) now")

      link_node = Enum.find(result, fn n ->
        n["marks"] != nil and hd(n["marks"])["type"] == "link"
      end)

      assert link_node
      assert link_node["text"] == "Blockster"
      assert hd(link_node["marks"])["attrs"]["href"] == "https://blockster.com"
    end

    test "handles multiple marks in one line" do
      result = TipTapBuilder.parse_inline_marks("**bold** and *italic*")

      bold_node = Enum.find(result, fn n -> n["marks"] != nil and hd(n["marks"])["type"] == "bold" end)
      italic_node = Enum.find(result, fn n -> n["marks"] != nil and hd(n["marks"])["type"] == "italic" end)

      assert bold_node
      assert italic_node
    end

    test "handles \\n as hardBreak" do
      result = TipTapBuilder.parse_inline_marks("Line one\nLine two")

      assert Enum.any?(result, fn n -> n["type"] == "hardBreak" end)
    end

    test "returns empty list for nil input" do
      assert [] = TipTapBuilder.parse_inline_marks(nil)
    end

    test "returns empty list for non-string input" do
      assert [] = TipTapBuilder.parse_inline_marks(123)
      assert [] = TipTapBuilder.parse_inline_marks(%{})
    end
  end

  describe "count_words/1" do
    test "counts words in simple paragraph doc" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Hello world foo bar"}]}
        ]
      }

      assert TipTapBuilder.count_words(doc) == 4
    end

    test "counts words across multiple nodes (paragraphs + headings)" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{"type" => "heading", "attrs" => %{"level" => 2}, "content" => [%{"type" => "text", "text" => "My Title"}]},
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "One two three"}]}
        ]
      }

      assert TipTapBuilder.count_words(doc) == 5
    end

    test "returns 0 for empty doc" do
      doc = %{"type" => "doc", "content" => []}
      assert TipTapBuilder.count_words(doc) == 0
    end

    test "returns 0 for non-doc input" do
      assert TipTapBuilder.count_words(nil) == 0
      assert TipTapBuilder.count_words("string") == 0
      assert TipTapBuilder.count_words(%{}) == 0
    end

    test "handles whitespace-only text nodes" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "   "}]}
        ]
      }

      assert TipTapBuilder.count_words(doc) == 0
    end

    test "counts words inside list items" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{
            "type" => "bulletList",
            "content" => [
              %{"type" => "listItem", "content" => [
                %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Item one"}]}
              ]},
              %{"type" => "listItem", "content" => [
                %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Item two"}]}
              ]}
            ]
          }
        ]
      }

      assert TipTapBuilder.count_words(doc) == 4
    end

    test "excludes non-text nodes (images) from count" do
      doc = %{
        "type" => "doc",
        "content" => [
          %{"type" => "paragraph", "content" => [%{"type" => "text", "text" => "Hello"}]},
          %{"type" => "image", "attrs" => %{"src" => "https://example.com/img.jpg"}}
        ]
      }

      assert TipTapBuilder.count_words(doc) == 1
    end
  end
end
