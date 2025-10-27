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
    # Quill stores headers as: text insert followed by newline with header attribute
    # We need to look ahead to see if the next op is a header newline
    html_parts =
      ops
      |> Enum.with_index()
      |> Enum.map(fn {op, index} ->
        next_op = Enum.at(ops, index + 1)

        case op do
          # Skip newlines with header attributes - they will be handled by the preceding text
          %{"insert" => "\n", "attributes" => %{"header" => _}} ->
            ""

          # Handle text that might be followed by a header newline
          %{"insert" => text} when is_binary(text) ->
            case next_op do
              # Next op is a header newline - wrap this text in header tag
              %{"insert" => "\n", "attributes" => %{"header" => level}} ->
                clean_text = String.replace(text, "\n", "", global: true)

                ~s(<h#{level} class="text-[#{if level == 1, do: "3xl", else: "2xl"}] font-bold my-6 text-[#141414]">#{clean_text}</h#{level}>)

              _ ->
                # No header - just regular text with line breaks
                text |> String.replace("\n", "<br>", global: true)
            end

          # Handle text with attributes (bold, italic, etc.) - but NOT header
          %{"insert" => text, "attributes" => attrs} when is_binary(text) and is_map(attrs) ->
            # Build content with formatting
            content = text |> String.replace("\n", "<br>", global: true)

            # Apply bold
            content =
              if attrs["bold"] do
                ~s(<strong>#{content}</strong>)
              else
                content
              end

            # Apply italic
            content =
              if attrs["italic"] do
                ~s(<em>#{content}</em>)
              else
                content
              end

            # Apply underline
            content =
              if attrs["underline"] do
                ~s(<u>#{content}</u>)
              else
                content
              end

            # Apply strike
            content =
              if attrs["strike"] do
                ~s(<s>#{content}</s>)
              else
                content
              end

            content

          # Handle images
          %{"insert" => %{"image" => url}} ->
            ~s(<img src="#{url}" class="max-w-full h-auto rounded-lg my-4" />)

          _ ->
            ""
        end
      end)
      |> Enum.join("")

    Phoenix.HTML.raw(html_parts)
  end

  defp render_quill_content(_), do: ""
end
