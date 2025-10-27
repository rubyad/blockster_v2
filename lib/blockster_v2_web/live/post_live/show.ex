defmodule BlocksterV2Web.PostLive.Show do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Blog

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    post = Blog.get_post!(id)

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
      |> Enum.reduce([], fn {op, index}, acc ->
        prev_op = if index > 0, do: Enum.at(ops, index - 1), else: nil

        case op do
          # Handle newline with header attribute - look BACK at previous text
          %{"insert" => "\n", "attributes" => %{"header" => level}} ->
            case prev_op do
              %{"insert" => text} when is_binary(text) ->
                # Split by newlines and take only the last line (the actual header text)
                lines = String.split(text, "\n")
                header_text = List.last(lines) |> String.trim()

                # Create header with proper sizing
                {size_class, font_size} =
                  case level do
                    1 -> {"text-4xl", "48px"}
                    2 -> {"text-3xl", "36px"}
                    _ -> {"text-2xl", "24px"}
                  end

                header_html =
                  ~s(<h#{level} class="#{size_class} font-bold my-6 text-[#141414]" style="font-size: #{font_size};">#{header_text}</h#{level}>)

                [header_html | acc]

              _ ->
                acc
            end

          # Handle regular text ONLY if next op is NOT a header newline
          %{"insert" => text} when is_binary(text) ->
            next_op = Enum.at(ops, index + 1)

            case next_op do
              # Skip if next is header newline - we'll handle it above
              %{"insert" => "\n", "attributes" => %{"header" => _}} ->
                acc

              _ ->
                # Regular text - convert newlines to paragraphs
                paragraphs =
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
                  |> Enum.reject(&(&1 == ""))

                paragraphs ++ acc
            end

          # Handle text with formatting attributes (bold, italic, etc.)
          %{"insert" => text, "attributes" => attrs} when is_binary(text) and is_map(attrs) ->
            # Don't process if this is a header (those are handled above)
            if Map.has_key?(attrs, "header") do
              acc
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

              # Wrap in span to preserve inline formatting
              formatted = ~s(<span>#{content}</span>)
              [formatted | acc]
            end

          # Handle images
          %{"insert" => %{"image" => url}} ->
            img_html = ~s(<img src="#{url}" class="max-w-full h-auto rounded-lg my-4" />)
            [img_html | acc]

          _ ->
            acc
        end
      end)
      |> Enum.reverse()
      |> Enum.join("")

    Phoenix.HTML.raw(html_parts)
  end

  defp render_quill_content(_), do: ""
end
