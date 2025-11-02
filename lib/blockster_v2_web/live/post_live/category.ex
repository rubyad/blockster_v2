defmodule BlocksterV2Web.PostLive.Category do
  use BlocksterV2Web, :live_view

  import BlocksterV2Web.SharedComponents, only: [lightning_icon: 1]

  alias BlocksterV2.Blog

  @impl true
  def mount(%{"category" => category_slug}, _session, socket) do
    # Look up category by slug from database
    case Blog.get_category_by_slug(category_slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Category not found")
         |> redirect(to: "/")}

      category ->
        posts = Blog.list_published_posts_by_category(category.slug)

        {:ok,
         socket
         |> assign(:posts, posts)
         |> assign(:category, category.name)
         |> assign(:page_title, "#{category.name} - Blockster")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end
end
