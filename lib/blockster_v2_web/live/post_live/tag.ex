defmodule BlocksterV2Web.PostLive.Tag do
  use BlocksterV2Web, :live_view

  import BlocksterV2Web.SharedComponents, only: [lightning_icon: 1]

  alias BlocksterV2.Blog

  @impl true
  def mount(%{"tag" => tag_slug}, _session, socket) do
    case Blog.get_tag_by_slug(tag_slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Tag not found")
         |> redirect(to: "/")}

      tag ->
        posts = Blog.list_published_posts_by_tag(tag.slug)

        {:ok,
         socket
         |> assign(:posts, posts)
         |> assign(:tag_name, tag.name)
         |> assign(:page_title, "#{tag.name} - Blockster")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end
end
