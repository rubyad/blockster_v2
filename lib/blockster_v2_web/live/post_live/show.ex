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
  def handle_event("delete", _params, socket) do
    defp render_quill_content(%{"ops" => ops}) when is_list(ops) do
      ops
      |> Enum.map(fn
        %{"insert" => text} when is_binary(text) ->
          text
          |> String.replace("\n", "<br>", global: true)
          |> Phoenix.HTML.raw()

        %{"insert" => %{"image" => url}} ->
          ~s(<img src="#{url}" class="max-w-full h-auto rounded-lg my-4" />)
          |> Phoenix.HTML.raw()

        _ ->
          ""
      end)
      |> Enum.intersperse("")
    end

    defp render_quill_content(_), do: ""
    {:ok, _} = Blog.delete_post(socket.assigns.post)

    {:noreply, push_navigate(socket, to: ~p"/")}
  end
end
