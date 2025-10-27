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
        next_op = Enum.at(ops, index + 1)

        case op do
          # Skip standalone newlines with header attributes - will be handled by preceding text
          %{"insert" => "\n", "attributes" => %{"header" => _}} ->
            acc

          # Handle regular text that precedes a header newline
          %{"insert" => text} when is_binary(text) ->
            case next_op do
              %{"insert" => "\n", "attributes" => %{"header" => level}} ->
                # This text should be wrapped in a header tag
                clean_text = String.trim(text)

                header_html =
                  ~s(<h#{level} class="text-[#{if level == 1, do: "3xl", else: "2xl"}] font-bold my-6 text-[#141414]">#{clean_text}</h#{level}>)

                [header_html | acc]

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
              # Build formatted content - keep as string
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
            img_html =
              ~s(<img src="#{url}" class="max-w-full h-auto rounded-lg my-4" />)

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
