defmodule BlocksterV2Web.PostLive.Show do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Blog

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"slug" => slug}, _url, socket) do
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
    html_parts =
      ops
      |> Enum.with_index()
      |> Enum.map(fn {op, index} ->
        next_op = Enum.at(ops, index + 1)
        render_single_op(op, next_op)
      end)
      |> List.flatten()
      |> Enum.reject(fn x -> x == "" || x == nil end)
      |> Enum.join("")

    Phoenix.HTML.raw(html_parts)
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

    # Render paragraphs first
    paragraphs =
      paragraph_lines
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn para ->
        trimmed = String.trim(para)

        if trimmed != "" do
          ~s(<p class="mb-4 text-[#343434] leading-[1.6]">#{trimmed}</p>)
        else
          ""
        end
      end)

    # Render header
    {size_class, font_size} =
      case level do
        1 -> {"text-4xl", "48px"}
        2 -> {"text-3xl", "36px"}
        _ -> {"text-2xl", "24px"}
      end

    header_html =
      ~s(<p class="mb-4 text-[#343434] leading-[1.6]">#{header_text}</p>)

    # Return paragraphs followed by header
    paragraphs ++ [header_html]
  end

  # Skip header newlines (they're processed above)
  defp render_single_op(%{"insert" => "\n", "attributes" => %{"header" => _}}, _next_op) do
    nil
  end

  # Handle regular text without header following
  defp render_single_op(%{"insert" => text}, _next_op) when is_binary(text) do
    # Convert double newlines to separate paragraphs
    text
    |> String.split("\n\n")
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(fn para ->
      trimmed = String.trim(para)

      if trimmed != "" do
        # Replace single newlines with <br> within paragraphs
        content = String.replace(trimmed, "\n", "<br>")
        ~s(<p class="mb-4 text-[#343434] leading-[1.6]">#{content}</p>)
      else
        ""
      end
    end)
  end

  # Handle text with formatting attributes (bold, italic, etc.)
  defp render_single_op(%{"insert" => text, "attributes" => attrs}, _next_op)
       when is_binary(text) and is_map(attrs) do
    # Don't process if this is a header (those are handled above)
    if Map.has_key?(attrs, "header") do
      nil
    else
      # Build formatted content
      content = to_string(text)

      # Apply formatting in order: bold, italic, underline, strike
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

      # Return as inline span
      ~s(<span>#{content}</span>)
    end
  end

  # Handle images
  defp render_single_op(%{"insert" => %{"image" => url}}, _next_op) do
    ~s(<img src="#{url}" class="max-w-full h-auto rounded-lg my-4" />)
  end

  # Handle tweet embeds using Twitter's oEmbed API
  defp render_single_op(%{"insert" => %{"tweet" => tweet_data}}, _next_op) do
    url = tweet_data["url"]

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
