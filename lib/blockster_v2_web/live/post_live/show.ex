defmodule BlocksterV2Web.PostLive.Show do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Blog

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"slug" => slug} = params, _url, socket) do
    post = Blog.get_post_by_slug!(slug)

    # Increment view count
    {:ok, updated_post} = Blog.increment_view_count(post)

    {:noreply,
     socket
     |> assign(:page_title, post.title)
     |> assign(:post, updated_post)}
  end

  @impl true
  def handle_event("publish", _params, socket) do
    {:ok, post} = Blog.publish_post(socket.assigns.post)

    {:noreply,
     socket
     |> put_flash(:info, "Post published successfully")
     |> assign(:post, post)}
  end

  @impl true
  def handle_event("unpublish", _params, socket) do
    {:ok, post} = Blog.unpublish_post(socket.assigns.post)

    {:noreply,
     socket
     |> put_flash(:info, "Post unpublished successfully")
     |> assign(:post, post)}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    {:ok, _} = Blog.delete_post(socket.assigns.post)

    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  defp render_quill_content(%{"ops" => ops}) when is_list(ops) do
    IO.puts("=== ALL QUILL OPS ===")
    IO.inspect(ops, label: "OPS", limit: :infinity)

    html_parts =
      ops
      |> Enum.with_index()
      |> Enum.map(fn {op, index} ->
        next_op = Enum.at(ops, index + 1)
        result = render_single_op(op, next_op)
        IO.inspect({op, result}, label: "OP -> RESULT")
        result
      end)
      |> List.flatten()
      |> tap(fn parts -> IO.inspect(parts, label: "BEFORE REJECT", limit: :infinity) end)
      |> Enum.reject(fn x -> x == "" || x == nil end)
      |> tap(fn parts -> IO.inspect(parts, label: "AFTER REJECT", limit: :infinity) end)
      |> wrap_inline_paragraphs()
      |> Enum.join("\n")
      |> wrap_list_items() # Groups list items with formatted content

    Phoenix.HTML.raw(html_parts)
  end

  # Wrap consecutive inline text/formatted elements in paragraph tags
  defp wrap_inline_paragraphs(parts) do
    {result, current_para} = Enum.reduce(parts, {[], []}, fn part, {acc, para} ->
      cond do
        # If it's a block-level element (starts with known block tags), flush current paragraph
        String.starts_with?(part, ["<h1", "<h2", "<h3", "<h4", "<h5", "<h6", "<blockquote", "<ul", "<ol", "<div", "<img", "<p "]) ->
          if length(para) > 0 do
            # Wrap accumulated inline content in a paragraph
            wrapped = ~s(<p class="mt-4 mb-8 text-[#343434] leading-[1.6]">#{Enum.join(para, "")}</p>)
            {acc ++ [wrapped, part], []}
          else
            {acc ++ [part], []}
          end

        # Otherwise, accumulate inline content
        true ->
          {acc, para ++ [part]}
      end
    end)

    # Handle remaining accumulated inline content
    if length(current_para) > 0 do
      wrapped = ~s(<p class="mt-4 mb-8 text-[#343434] leading-[1.6]">#{Enum.join(current_para, "")}</p>)
      result ++ [wrapped]
    else
      result
    end
  end

  # Wrap consecutive list items in ul/ol tags and blockquote paragraphs in blockquote tags
  defp wrap_list_items(html) do
    html
    |> String.replace(
      ~r/<li class="[^"]*list-item-ordered">.*?<\/li>/s,
      fn match ->
        # Check if already wrapped
        if String.contains?(match, "<ol") do
          match
        else
          match
        end
      end
    )
    # Wrap bullet list items
    |> String.replace(
      ~r/(<li class="[^"]*list-item-bullet">.*?<\/li>)+/s,
      fn matches ->
        ~s(<ul class="list-disc pl-6 mb-4">#{matches}</ul>)
      end
    )
    # Wrap ordered list items
    |> String.replace(
      ~r/(<li class="[^"]*list-item-ordered">.*?<\/li>)+/s,
      fn matches ->
        ~s(<ol class="list-decimal pl-6 mb-4">#{matches}</ol>)
      end
    )
    # Wrap consecutive blockquote paragraphs in a single blockquote
    |> wrap_blockquotes()
  end

  # Wrap consecutive blockquote-line paragraphs
  defp wrap_blockquotes(html) do
    IO.puts("=== WRAP_BLOCKQUOTES CALLED ===")
    IO.inspect(String.contains?(html, "blockquote-line"), label: "Contains blockquote-line?")

    # Split HTML into lines and process sequentially
    lines = String.split(html, "\n")
    IO.inspect(length(lines), label: "Number of lines")

    {result, current_group} = Enum.reduce(lines, {[], []}, fn line, {acc, group} ->
      cond do
        # If line contains blockquote-line opening tag
        String.contains?(line, ~s(<p class="blockquote-line">)) ->
          {acc, [line | group]}

        # If we have accumulated blockquote lines and this isn't one, wrap them
        length(group) > 0 and not String.contains?(line, "blockquote-line") ->
          # Process the group - mark last paragraph as attribution
          reversed_group = Enum.reverse(group)
          cleaned_lines = reversed_group
          |> Enum.with_index()
          |> Enum.map(fn {l, idx} ->
            # Last item gets attribution class
            if idx == length(reversed_group) - 1 do
              String.replace(l, ~s(<p class="blockquote-line">), ~s(<p class="blockquote-attribution">))
            else
              String.replace(l, ~s(<p class="blockquote-line">), "<p>")
            end
          end)
          wrapped = ~s(<blockquote class="mt-4 mb-8">#{Enum.join(cleaned_lines, "\n")}</blockquote>)
          {acc ++ [wrapped, line], []}

        # Otherwise just accumulate
        true ->
          {acc ++ [line], group}
      end
    end)

    # Handle remaining group at end
    final_result = if length(current_group) > 0 do
      # Process the group - mark last paragraph as attribution
      reversed_group = Enum.reverse(current_group)
      cleaned_lines = reversed_group
      |> Enum.with_index()
      |> Enum.map(fn {l, idx} ->
        # Last item gets attribution class
        if idx == length(reversed_group) - 1 do
          String.replace(l, ~s(<p class="blockquote-line">), ~s(<p class="blockquote-attribution">))
        else
          String.replace(l, ~s(<p class="blockquote-line">), "<p>")
        end
      end)
      wrapped = ~s(<blockquote class="mt-4 mb-8">#{Enum.join(cleaned_lines, "\n")}</blockquote>)
      result ++ [wrapped]
    else
      result
    end

    Enum.join(final_result, "\n")
  end

  defp render_quill_content(_), do: ""

  # Handle text that will be followed by a header newline
  defp render_single_op(
         %{"insert" => text},
         %{"insert" => "\n", "attributes" => %{"header" => level}}
       )
       when is_binary(text) do
    # Split the text by newlines
    lines = String.split(text, "\n")

    # All lines except the last are regular paragraphs
    paragraph_lines = Enum.drop(lines, -1)

    # The last line is the header text
    header_text = List.last(lines) |> String.trim()

    # Render paragraphs first (only non-empty ones)
    paragraphs =
      paragraph_lines
      |> Enum.map(fn para ->
        trimmed = String.trim(para)

        if trimmed != "" do
          ~s(<p class="mb-4 text-[#343434] leading-[1.6]">#{trimmed}</p>)
        else
          # Skip empty lines, margins provide spacing
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Render header with proper HTML tag and size
    size_class =
      case level do
        1 -> "text-4xl font-bold"
        2 -> "text-3xl font-bold"
        _ -> "text-2xl font-bold"
      end

    # Add mt-4 mb-8 spacing for h1 and h2 tags
    spacing_class =
      case level do
        1 -> "mt-4 mb-8"
        2 -> "mt-4 mb-8"
        _ -> "mb-4"
      end

    header_tag = "h#{level}"

    header_html =
      ~s(<#{header_tag} class="#{spacing_class} text-[#343434] leading-[1.2] #{size_class}">#{header_text}</#{header_tag}>)

    # Return paragraphs followed by header
    paragraphs ++ [header_html]
  end

  # Handle header newlines - just skip them, margins handle spacing
  defp render_single_op(%{"insert" => text, "attributes" => %{"header" => _}}, _next_op) when is_binary(text) do
    # Check if the text is ONLY newlines (no actual text content)
    if String.trim(text) == "" do
      # Skip newline-only header operations, margins provide spacing
      nil
    else
      # Has actual text content, should be handled by the header+text handler above
      nil
    end
  end

  # Handle blockquote text - mark it as blockquote paragraph, wrapping happens later
  defp render_single_op(
         %{"insert" => text},
         %{"insert" => "\n", "attributes" => %{"blockquote" => true}}
       )
       when is_binary(text) do
    IO.inspect(text, label: "BLOCKQUOTE TEXT")

    # Check if text contains a double newline (paragraph separator)
    # If so, only render paragraphs AFTER the first double newline as blockquote
    # This handles Quill's behavior of including preceding text in blockquote
    result = if String.contains?(text, "\n\n") do
      # Split by double newline to separate paragraphs
      paragraphs = String.split(text, "\n\n")
      IO.inspect(paragraphs, label: "SPLIT PARAGRAPHS")

      # First paragraph(s) before the last one should be rendered as normal text
      # Only the last paragraph(s) should be blockquoted
      {non_blockquote_parts, blockquote_parts} = Enum.split(paragraphs, -1)

      # Render non-blockquote parts as regular paragraphs (skip empty ones)
      regular_html = non_blockquote_parts
      |> Enum.map(fn para ->
        trimmed = String.trim(para)
        if trimmed != "" do
          ~s(<p>#{trimmed}</p>)
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

      # Render blockquote parts with blockquote-line class (skip empty lines)
      blockquote_html = blockquote_parts
      |> Enum.flat_map(fn para -> String.split(para, "\n") end)
      |> Enum.map(fn line ->
        trimmed = String.trim(line)
        if trimmed != "" do
          ~s(<p class="blockquote-line">#{trimmed}</p>)
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

      # Combine regular and blockquote HTML
      [regular_html, blockquote_html]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
    else
      # No double newline - render all as blockquote (skip empty lines)
      lines = String.split(text, "\n")

      lines
      |> Enum.map(fn line ->
        trimmed = String.trim(line)
        if trimmed != "" do
          ~s(<p class="blockquote-line">#{trimmed}</p>)
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")
    end

    IO.inspect(result, label: "BLOCKQUOTE RESULT")
    result
  end

  # Detect if a line is an attribution (e.g., "John Doe, CEO at Company")
  defp is_attribution?(text) do
    # Pattern: Name, Title at Company or Name, Title
    # Look for patterns like ", CEO at", ", CTO at", etc.
    String.match?(text, ~r/^[^,]+,\s+[A-Z][^,]+ at .+$/) or
    # Also match simpler pattern: just "Name, Position"
    String.match?(text, ~r/^[^,]+,\s+[A-Z][^,]+$/)
  end

  # Skip blockquote newlines (they're processed above)
  defp render_single_op(%{"insert" => "\n", "attributes" => %{"blockquote" => true}}, _next_op) do
    nil
  end

  # Handle list item text (ordered or bullet)
  defp render_single_op(
         %{"insert" => text},
         %{"insert" => "\n", "attributes" => %{"list" => list_type}}
       )
       when is_binary(text) do
    trimmed = String.trim(text)

    if trimmed != "" do
      ~s(<li class="mb-2 text-[#343434] leading-[1.6] list-item-#{list_type}">#{trimmed}</li>)
    else
      ""
    end
  end

  # Skip list newlines (they're processed above)
  defp render_single_op(%{"insert" => "\n", "attributes" => %{"list" => _}}, _next_op) do
    nil
  end

  # Handle text with inline formatting attributes (bold, italic, underline, strike, link)
  # This MUST come before the plain text handler to match more specific patterns first
  defp render_single_op(%{"insert" => text, "attributes" => attrs}, _next_op)
       when is_binary(text) and is_map(attrs) do
    # Don't process if this is a block-level attribute (header, blockquote, list)
    # Those are handled by their specific handlers above
    if Map.has_key?(attrs, "header") or Map.has_key?(attrs, "blockquote") or
         Map.has_key?(attrs, "list") do
      nil
    else
      # Just apply inline formatting without wrapping in <p> tags
      # The wrapping happens later when we join ops together
      content = text

      content =
        if attrs["bold"] do
          ~s(<strong>#{content}</strong>)
        else
          content
        end

      content =
        if attrs["italic"] do
          ~s(<em>#{content}</em>)
        else
          content
        end

      content =
        if attrs["underline"] do
          ~s(<u>#{content}</u>)
        else
          content
        end

      content =
        if attrs["strike"] do
          ~s(<s>#{content}</s>)
        else
          content
        end

      content =
        if attrs["link"] do
          url = attrs["link"]
          ~s(<a href="#{url}" target="_blank" rel="noopener noreferrer" class="text-blue-600 hover:underline">#{content}</a>)
        else
          content
        end

      content
    end
  end

  # Handle regular text without any formatting
  defp render_single_op(%{"insert" => text}, _next_op) when is_binary(text) do
    # Split by double newlines (paragraph breaks) to preserve paragraph structure
    # Single newlines within paragraphs are ignored
    text
    |> String.split("\n\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(fn para ->
      # Reject empty strings and separator-only strings like "--"
      para == "" || String.match?(para, ~r/^[-\s]+$/)
    end)
    |> Enum.map(fn para ->
      ~s(<p class="mt-4 mb-8 text-[#343434] leading-[1.6]">#{para}</p>)
    end)
  end

  # Handle images
  defp render_single_op(%{"insert" => %{"image" => url}}, _next_op) do
    ~s(<img src="#{url}" class="max-w-full h-auto rounded-lg my-4" />)
  end

  # Handle spacer embeds
  defp render_single_op(%{"insert" => %{"spacer" => _}}, _next_op) do
    ~s(<div class="text-left text-[#343434] my-4 text-2xl">--</div>)
  end

  # Handle tweet embeds with embedded HTML
  defp render_single_op(%{"insert" => %{"tweet" => %{"html" => html}}}, _next_op) do
    ~s{<div class="my-6">#{html}<script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script></div>}
  end

  # Handle tweet embeds using Twitter's oEmbed API (legacy format with URL)
  defp render_single_op(%{"insert" => %{"tweet" => %{"url" => url}}}, _next_op) do
    # Fetch tweet HTML from Twitter's oEmbed API
    case fetch_tweet_embed(url) do
      {:ok, html} ->
        # Wrap in container for styling
        ~s(<div class="my-6">#{html}</div>)

      {:error, _reason} ->
        # Fallback to simple link if oEmbed fails
        ~s(<p class="my-4"><a href="#{url}" target="_blank" rel="noopener noreferrer" class="text-blue-600 hover:underline">View Tweet on Twitter</a></p>)
    end
  end

  # Handle tweet embeds with just a URL string (backward compatibility)
  defp render_single_op(%{"insert" => %{"tweet" => url}}, _next_op) when is_binary(url) do
    # Fetch tweet HTML from Twitter's oEmbed API
    case fetch_tweet_embed(url) do
      {:ok, html} ->
        # Wrap in container for styling
        ~s(<div class="my-6">#{html}</div>)

      {:error, _reason} ->
        # Fallback to simple link if oEmbed fails
        ~s(<p class="my-4"><a href="#{url}" target="_blank" rel="noopener noreferrer" class="text-blue-600 hover:underline">View Tweet on Twitter</a></p>)
    end
  end

  # Handle plain newlines (blank lines) - just skip them, margins handle spacing
  defp render_single_op(%{"insert" => "\n"}, _next_op) do
    nil
  end

  # Catch-all for unknown ops
  defp render_single_op(_op, _next_op), do: nil

  # Fetch tweet embed HTML from Twitter's oEmbed API
  defp fetch_tweet_embed(url) do
    # Twitter's oEmbed endpoint
    oembed_url =
      "https://publish.twitter.com/oembed?url=#{URI.encode_www_form(url)}&theme=light&dnt=true"

    case Req.get(oembed_url) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        # Extract HTML from oEmbed response
        case Map.get(body, "html") do
          html when is_binary(html) ->
            {:ok, html}

          _ ->
            {:error, :invalid_response}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      {:error, error}
  end
end
