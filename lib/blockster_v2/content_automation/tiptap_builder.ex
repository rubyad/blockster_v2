defmodule BlocksterV2.ContentAutomation.TipTapBuilder do
  @moduledoc """
  Converts article sections from Claude's structured output into TipTap JSON
  compatible with the existing TipTapRenderer.

  Supported node types: paragraph, heading, blockquote, bulletList, orderedList,
  listItem, image, tweet, spacer, codeBlock, horizontalRule.

  Inline marks: **bold**, *italic*, ~~strike~~, `code`, [text](url), \\n → hardBreak.
  """

  @doc """
  Build a TipTap document from a list of section maps.
  Returns `%{"type" => "doc", "content" => nodes}`.
  """
  def build(sections) when is_list(sections) do
    content = Enum.flat_map(sections, &section_to_nodes/1)
    %{"type" => "doc", "content" => content}
  end

  def build(_), do: %{"type" => "doc", "content" => []}

  # ── Node Type Handlers ──

  defp section_to_nodes(%{"type" => "paragraph", "text" => text}) do
    [%{"type" => "paragraph", "content" => parse_inline_marks(text)}]
  end

  defp section_to_nodes(%{"type" => "heading", "text" => text} = section) do
    level = section["level"] || 2

    [%{
      "type" => "heading",
      "attrs" => %{"level" => level},
      "content" => [%{"type" => "text", "text" => text}]
    }]
  end

  defp section_to_nodes(%{"type" => "blockquote", "text" => text}) do
    [%{
      "type" => "blockquote",
      "content" => [
        %{"type" => "paragraph", "content" => parse_inline_marks(text)}
      ]
    }]
  end

  defp section_to_nodes(%{"type" => "bullet_list", "items" => items}) when is_list(items) do
    list_items = Enum.map(items, &build_list_item/1)
    [%{"type" => "bulletList", "content" => list_items}]
  end

  defp section_to_nodes(%{"type" => "ordered_list", "items" => items}) when is_list(items) do
    list_items = Enum.map(items, &build_list_item/1)
    [%{"type" => "orderedList", "content" => list_items}]
  end

  defp section_to_nodes(%{"type" => "image", "src" => src}) do
    [%{"type" => "image", "attrs" => %{"src" => src}}]
  end

  defp section_to_nodes(%{"type" => "tweet", "url" => url, "id" => id}) do
    [%{"type" => "tweet", "attrs" => %{"url" => url, "id" => id}}]
  end

  defp section_to_nodes(%{"type" => "spacer"}) do
    [%{"type" => "spacer"}]
  end

  defp section_to_nodes(%{"type" => "code_block", "text" => text}) do
    [%{"type" => "codeBlock", "content" => [%{"type" => "text", "text" => text}]}]
  end

  defp section_to_nodes(%{"type" => "horizontalRule"}) do
    [%{"type" => "horizontalRule"}]
  end

  # Fallback — skip unknown types
  defp section_to_nodes(_), do: []

  # ── List Item Builder ──

  defp build_list_item(item_text) when is_binary(item_text) do
    %{
      "type" => "listItem",
      "content" => [
        %{"type" => "paragraph", "content" => parse_inline_marks(item_text)}
      ]
    }
  end

  defp build_list_item(_), do: %{"type" => "listItem", "content" => []}

  # ── Inline Mark Parser ──

  @doc """
  Parse markdown-style inline formatting into TipTap text nodes with marks.
  Handles: **bold**, *italic*, ~~strikethrough~~, `code`, [text](url), \\n hardBreak.
  """
  def parse_inline_marks(text) when is_binary(text) do
    text
    |> tokenize_inline()
    |> Enum.flat_map(&to_tiptap_text_nodes/1)
  end

  def parse_inline_marks(_), do: []

  # Pattern priority: links > code > bold > strikethrough > italic > plain text
  defp tokenize_inline(text) do
    regex = ~r/\[([^\]]+)\]\(([^)]+)\)|`([^`]+)`|\*\*(.+?)\*\*|~~(.+?)~~|\*(.+?)\*|([^*\[`~]+)/s

    Regex.scan(regex, text)
    |> Enum.map(fn captures ->
      cond do
        match_at(captures, 1) != "" and match_at(captures, 2) != "" ->
          {match_at(captures, 1), [%{"type" => "link", "attrs" => %{"href" => match_at(captures, 2)}}]}

        match_at(captures, 3) != "" ->
          {match_at(captures, 3), [%{"type" => "code"}]}

        match_at(captures, 4) != "" ->
          {match_at(captures, 4), [%{"type" => "bold"}]}

        match_at(captures, 5) != "" ->
          {match_at(captures, 5), [%{"type" => "strike"}]}

        match_at(captures, 6) != "" ->
          {match_at(captures, 6), [%{"type" => "italic"}]}

        true ->
          {List.first(captures), []}
      end
    end)
  end

  defp match_at(list, index), do: Enum.at(list, index, "")

  # Convert token to TipTap nodes, splitting on \n for hard breaks
  defp to_tiptap_text_nodes({text, marks}) do
    text
    |> String.split("\n")
    |> Enum.intersperse(:hard_break)
    |> Enum.flat_map(fn
      :hard_break -> [%{"type" => "hardBreak"}]
      "" -> []
      segment when marks == [] -> [%{"type" => "text", "text" => segment}]
      segment -> [%{"type" => "text", "text" => segment, "marks" => marks}]
    end)
  end

  # ── Word Counting ──

  @doc """
  Count words in a TipTap document by extracting all text content.
  """
  def count_words(%{"type" => "doc", "content" => nodes}) when is_list(nodes) do
    nodes
    |> extract_text()
    |> String.split(~r/\s+/, trim: true)
    |> length()
  end

  def count_words(_), do: 0

  defp extract_text(nodes) when is_list(nodes) do
    Enum.map_join(nodes, " ", &extract_text_from_node/1)
  end

  defp extract_text_from_node(%{"type" => "text", "text" => text}), do: text

  defp extract_text_from_node(%{"content" => children}) when is_list(children) do
    extract_text(children)
  end

  defp extract_text_from_node(_), do: ""
end
