defmodule BlocksterV2Web.PostLive.TipTapRenderer do
  @moduledoc """
  Renders TipTap JSON content to HTML for display
  """

  def render_content(%{"type" => "doc", "content" => content}) when is_list(content) do
    html =
      content
      |> Enum.map(&render_node/1)
      |> Enum.join("\n")

    Phoenix.HTML.raw(html)
  end

  def render_content(_), do: Phoenix.HTML.raw("")

  # Paragraph
  defp render_node(%{"type" => "paragraph", "content" => content}) when is_list(content) do
    inner = Enum.map(content, &render_inline/1) |> Enum.join()
    "<p class=\"mb-4\">#{inner}</p>"
  end

  defp render_node(%{"type" => "paragraph"}), do: "<p class=\"mb-4\"><br></p>"

  # Headings
  defp render_node(%{"type" => "heading", "attrs" => %{"level" => level}, "content" => content})
       when is_list(content) do
    inner = Enum.map(content, &render_inline/1) |> Enum.join()
    class = get_heading_class(level)
    "<h#{level} class=\"#{class}\">#{inner}</h#{level}>"
  end

  defp render_node(%{"type" => "heading", "attrs" => %{"level" => level}}) do
    class = get_heading_class(level)
    "<h#{level} class=\"#{class}\"><br></h#{level}>"
  end

  # Blockquote
  defp render_node(%{"type" => "blockquote", "content" => content}) when is_list(content) do
    inner = Enum.map(content, &render_node/1) |> Enum.join()

    """
    <blockquote class="border-l-4 border-gray-300 pl-4 italic my-6 text-gray-700 bg-gray-50 py-2 rounded-r">
      #{inner}
    </blockquote>
    """
  end

  # Bullet List
  defp render_node(%{"type" => "bulletList", "content" => items}) when is_list(items) do
    inner = Enum.map(items, &render_node/1) |> Enum.join()
    "<ul class=\"list-disc pl-6 mb-4 space-y-2\">#{inner}</ul>"
  end

  # Ordered List
  defp render_node(%{"type" => "orderedList", "content" => items}) when is_list(items) do
    inner = Enum.map(items, &render_node/1) |> Enum.join()
    "<ol class=\"list-decimal pl-6 mb-4 space-y-2\">#{inner}</ol>"
  end

  # List Item
  defp render_node(%{"type" => "listItem", "content" => content}) when is_list(content) do
    inner = Enum.map(content, &render_node/1) |> Enum.join()
    "<li>#{inner}</li>"
  end

  # Image
  defp render_node(%{"type" => "image", "attrs" => %{"src" => src}}) do
    "<img src=\"#{escape_html(src)}\" class=\"max-w-full h-auto rounded-lg my-4\" alt=\"\" />"
  end

  # Tweet Embed
  defp render_node(%{"type" => "tweet", "attrs" => %{"url" => url, "id" => tweet_id}}) do
    """
    <div class="tweet-embed my-6">
      <blockquote class="twitter-tweet" data-theme="light" data-dnt="true">
        <a href="#{escape_html(url)}"></a>
      </blockquote>
    </div>
    """
  end

  # Spacer
  defp render_node(%{"type" => "spacer"}) do
    "<div class=\"text-left text-[#343434] my-4 text-2xl\">--</div>"
  end

  # Code Block
  defp render_node(%{"type" => "codeBlock", "content" => content}) when is_list(content) do
    inner = Enum.map(content, &render_inline/1) |> Enum.join()

    """
    <pre class="bg-gray-900 text-gray-100 p-4 rounded my-4 overflow-x-auto"><code>#{escape_html(inner)}</code></pre>
    """
  end

  # Horizontal Rule
  defp render_node(%{"type" => "horizontalRule"}) do
    "<hr class=\"my-6 border-gray-300\" />"
  end

  # Fallback for unknown nodes
  defp render_node(_), do: ""

  # Render inline content (text with marks)
  defp render_inline(%{"type" => "text", "text" => text, "marks" => marks})
       when is_list(marks) do
    Enum.reduce(marks, escape_html(text), fn mark, acc ->
      apply_mark(mark, acc)
    end)
  end

  # Plain text without marks
  defp render_inline(%{"type" => "text", "text" => text}) do
    escape_html(text)
  end

  # Hard break
  defp render_inline(%{"type" => "hardBreak"}) do
    "<br />"
  end

  # Fallback
  defp render_inline(_), do: ""

  # Apply text marks (formatting)
  defp apply_mark(%{"type" => "bold"}, text), do: "<strong>#{text}</strong>"
  defp apply_mark(%{"type" => "italic"}, text), do: "<em>#{text}</em>"
  defp apply_mark(%{"type" => "underline"}, text), do: "<u>#{text}</u>"
  defp apply_mark(%{"type" => "strike"}, text), do: "<s>#{text}</s>"
  defp apply_mark(%{"type" => "code"}, text), do: "<code class=\"bg-gray-100 px-1 py-0.5 rounded text-sm\">#{text}</code>"

  defp apply_mark(%{"type" => "link", "attrs" => %{"href" => href}}, text) do
    "<a href=\"#{escape_html(href)}\" target=\"_blank\" rel=\"noopener noreferrer\" class=\"text-blue-600 hover:underline\">#{text}</a>"
  end

  defp apply_mark(_, text), do: text

  # Heading class helpers
  defp get_heading_class(1), do: "text-4xl font-bold mb-4 mt-6"
  defp get_heading_class(2), do: "text-3xl font-bold mb-4 mt-6"
  defp get_heading_class(3), do: "text-2xl font-bold mb-3 mt-5"
  defp get_heading_class(_), do: "font-bold mb-2 mt-4"

  # Fetch tweet HTML from Twitter oEmbed API
  defp fetch_tweet_html(url) do
    case Req.get("https://publish.twitter.com/oembed",
           params: %{url: url, theme: "light", dnt: "true"}
         ) do
      {:ok, %{body: %{"html" => html}}} -> {:ok, html}
      _ -> {:error, :fetch_failed}
    end
  end

  # Basic HTML escaping
  defp escape_html(text) when is_binary(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace("\"", "&quot;")
    |> String.replace("'", "&#39;")
  end

  defp escape_html(text), do: text
end
