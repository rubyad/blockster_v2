defmodule BlocksterV2Web.HubLive.Show do
  use BlocksterV2Web, :live_view

  import BlocksterV2Web.SharedComponents, only: [lightning_icon: 1]

  alias BlocksterV2.Blog

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    # Get hub from database by slug
    case Blog.get_hub_by_slug(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Hub not found")
         |> redirect(to: "/")}

      hub ->
        # Get posts for this hub's tag
        posts = Blog.list_published_posts_by_tag(hub.tag_name)

        {:ok,
         socket
         |> assign(:posts, posts)
         |> assign(:hub, hub)
         |> assign(:page_title, "#{hub.name} Hub")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end
end
