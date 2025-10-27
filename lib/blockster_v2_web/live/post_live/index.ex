defmodule BlocksterV2Web.PostLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Blog

  @impl true
  def mount(_params, _session, socket) do
    posts = Blog.list_published_posts()

    {:ok,
     socket
     |> assign(:posts, posts)
     |> assign(:page_title, "Latest Posts")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Latest Posts")
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Post")
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    post = Blog.get_post!(id)

    socket
    |> assign(:page_title, "Edit Post")
    |> assign(:post, post)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    post = Blog.get_post!(id)
    {:ok, _} = Blog.delete_post(post)

    {:noreply, assign(socket, :posts, Blog.list_published_posts())}
  end
end
