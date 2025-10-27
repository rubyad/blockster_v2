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
      |> Enum.map(fn
        # Handle text with attributes (bold, italic, header, etc.)
        %{"insert" => text, "attributes" => attrs} when is_binary(text) and is_map(attrs) ->
          # Build HTML tags based on attributes
          content = text |> String.replace("\n", "<br>", global: true)

          # Wrap in header tag if header attribute exists
          content =
            if attrs["header"] do
              level = attrs["header"]
              ~s(<h#{level} class="font-bold my-4">#{content}</h#{level}>)
            else
              content
            end

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

        # Handle plain text without attributes
        %{"insert" => text} when is_binary(text) ->
          text
          |> String.replace("\n", "<br>", global: true)

        # Handle images
        %{"insert" => %{"image" => url}} ->
          ~s(<img src="#{url}" class="max-w-full h-auto rounded-lg my-4" />)

        _ ->
          ""
      end)
      |> Enum.join("")

    Phoenix.HTML.raw(html_parts)
  end

  defp render_quill_content(_), do: ""
end
