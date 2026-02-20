defmodule BlocksterV2Web.HubLive.Show do
  use BlocksterV2Web, :live_view

  import BlocksterV2Web.SharedComponents, only: [lightning_icon: 1, token_badge: 1]

  alias BlocksterV2.ImageKit

  alias BlocksterV2.Blog
  alias BlocksterV2.Shop

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    # Get hub from database by slug with associations preloaded
    case Blog.get_hub_by_slug_with_associations(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Hub not found")
         |> redirect(to: "/")}

      hub ->
        # Get posts for this hub by hub_id
        # PostsThreeComponent needs 5 posts, PostsFourComponent needs 3 posts
        posts_three = Blog.list_published_posts_by_hub(hub.id, limit: 5) |> Blog.with_bux_earned()
        posts_four = Blog.list_published_posts_by_hub(hub.id, limit: 3, exclude_ids: Enum.map(posts_three, & &1.id)) |> Blog.with_bux_earned()

        # VideosComponent needs 3 video posts for the All tab (posts with video_id)
        videos_posts = Blog.list_video_posts_by_hub(hub.id, limit: 3) |> Blog.with_bux_earned()

        # Hub-specific products for Shop section
        hub_products = Shop.list_products_by_hub(hub.id)

        {:ok,
         socket
         |> assign(:posts_three, posts_three)
         |> assign(:posts_four, posts_four)
         |> assign(:hub, hub)
         |> assign(:page_title, "#{hub.name} Hub")
         |> assign(:show_all, true)
         |> assign(:show_news, false)
         |> assign(:show_videos, false)
         |> assign(:show_shop, false)
         |> assign(:show_events, false)
         |> assign(:show_mobile_menu, false)
         |> assign(:news_loaded, false)
         |> assign(:videos_loaded, true)
         |> assign(:shop_loaded, true)
         |> assign(:videos_posts, videos_posts)
         |> assign(:hub_products, hub_products)
         |> assign(:displayed_post_ids, [])
         |> assign(:last_component_module, BlocksterV2Web.PostLive.PostsSixComponent)
         |> stream(:news_components, [])}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_mobile_menu", _params, socket) do
    {:noreply, assign(socket, :show_mobile_menu, !socket.assigns.show_mobile_menu)}
  end

  @impl true
  def handle_event("close_mobile_menu", _params, socket) do
    {:noreply, assign(socket, :show_mobile_menu, false)}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    socket =
      socket
      |> assign(:show_all, tab == "all")
      |> assign(:show_news, tab == "news")
      |> assign(:show_videos, tab == "videos")
      |> assign(:show_shop, tab == "shop")
      |> assign(:show_events, tab == "events")
      |> assign(:show_mobile_menu, false)

    # Load/reload news components when switching to news tab
    # Always reset the stream to ensure consistent display
    socket =
      if tab == "news" do
        {news_components, displayed_post_ids} = build_initial_news_components(socket.assigns.hub.id)

        socket
        |> assign(:news_loaded, true)
        |> assign(:displayed_post_ids, displayed_post_ids)
        |> assign(:last_component_module, BlocksterV2Web.PostLive.PostsSixComponent)
        |> stream(:news_components, news_components, reset: true)
      else
        socket
      end

    # Load videos when switching to videos tab for the first time
    socket =
      if tab == "videos" && !socket.assigns.videos_loaded do
        # Use list_video_posts_by_hub to get only posts with video_id
        videos_posts = Blog.list_video_posts_by_hub(socket.assigns.hub.id, limit: 3) |> Blog.with_bux_earned()

        socket
        |> assign(:videos_loaded, true)
        |> assign(:videos_posts, videos_posts)
      else
        socket
      end

    # Shop is now loaded in mount, no lazy loading needed
    # (hub_products are loaded eagerly since they're shown in the All tab)

    {:noreply, socket}
  end

  @impl true
  def handle_event("update_hub_logo", %{"logo_url" => logo_url}, socket) do
    hub = socket.assigns.hub

    case Blog.update_hub(hub, %{logo_url: logo_url}) do
      {:ok, updated_hub} ->
        {:noreply,
         socket
         |> assign(:hub, updated_hub)
         |> put_flash(:info, "Logo updated successfully")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to update logo")}
    end
  end

  @impl true
  def handle_event("load-more-news", _, socket) do
    hub_id = socket.assigns.hub.id
    displayed_post_ids = socket.assigns.displayed_post_ids
    last_module = socket.assigns.last_component_module

    # Build next batch of 4 components (Three, Four, Five, Six)
    {new_components, new_displayed_post_ids} =
      build_news_components_batch(hub_id, displayed_post_ids, last_module)

    if new_components == [] do
      {:reply, %{end_reached: true}, socket}
    else
      # Insert new components into stream
      socket =
        Enum.reduce(new_components, socket, fn component, acc_socket ->
          stream_insert(acc_socket, :news_components, component, at: -1)
        end)

      # Track the last component module for next load
      last_module = if new_components != [], do: List.last(new_components).module, else: last_module

      {:reply, %{},
       socket
       |> assign(:displayed_post_ids, new_displayed_post_ids)
       |> assign(:last_component_module, last_module)}
    end
  end

  # Component modules for cycling through layouts
  @component_modules [
    BlocksterV2Web.PostLive.PostsThreeComponent,
    BlocksterV2Web.PostLive.PostsFourComponent,
    BlocksterV2Web.PostLive.PostsFiveComponent,
    BlocksterV2Web.PostLive.PostsSixComponent
  ]

  # Posts per component
  @posts_per_component %{
    BlocksterV2Web.PostLive.PostsThreeComponent => 5,
    BlocksterV2Web.PostLive.PostsFourComponent => 3,
    BlocksterV2Web.PostLive.PostsFiveComponent => 6,
    BlocksterV2Web.PostLive.PostsSixComponent => 5
  }

  # Build initial batch of 4 components (Three, Four, Five, Six)
  defp build_initial_news_components(hub_id) do
    build_news_components_batch(hub_id, [], BlocksterV2Web.PostLive.PostsSixComponent)
  end

  # Build a batch of 4 components cycling through the component modules
  defp build_news_components_batch(hub_id, displayed_post_ids, last_module) do
    # Start from the component after last_module
    start_index = Enum.find_index(@component_modules, &(&1 == last_module))
    start_index = if start_index, do: rem(start_index + 1, 4), else: 0

    # Build 4 components in order
    {components, final_displayed_ids} =
      Enum.reduce(0..3, {[], displayed_post_ids}, fn idx, {acc_components, acc_ids} ->
        module_index = rem(start_index + idx, 4)
        module = Enum.at(@component_modules, module_index)
        posts_needed = Map.get(@posts_per_component, module)

        # Fetch posts for this component (with bux_balances from Mnesia)
        posts = Blog.list_published_posts_by_hub(
          hub_id,
          limit: posts_needed,
          exclude_ids: acc_ids
        ) |> Blog.with_bux_earned()

        if posts == [] do
          # No more posts available
          {acc_components, acc_ids}
        else
          post_ids = Enum.map(posts, & &1.id)
          # Use unique integer to avoid ID conflicts across batches
          unique_id = System.unique_integer([:positive])
          component = %{
            id: "hub-news-#{hub_id}-#{module}-#{unique_id}",
            module: module,
            posts: posts,
            content: "News",
            type: "hub-news"
          }

          {acc_components ++ [component], acc_ids ++ post_ids}
        end
      end)

    {components, final_displayed_ids}
  end
end
