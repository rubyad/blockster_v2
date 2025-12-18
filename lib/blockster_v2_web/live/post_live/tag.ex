defmodule BlocksterV2Web.PostLive.Tag do
  use BlocksterV2Web, :live_view

  import BlocksterV2Web.SharedComponents, only: [lightning_icon: 1]

  alias BlocksterV2.Blog

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

  @impl true
  def mount(%{"tag" => tag_slug}, _session, socket) do
    case Blog.get_tag_by_slug(tag_slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Tag not found")
         |> redirect(to: "/")}

      tag ->
        # Initialize with first batch of components
        {components, displayed_post_ids} = build_initial_components(tag.slug)

        {:ok,
         socket
         |> assign(:tag_name, tag.name)
         |> assign(:tag_slug, tag.slug)
         |> assign(:page_title, "#{tag.name} - Blockster")
         |> assign(:displayed_post_ids, displayed_post_ids)
         |> assign(:last_component_module, BlocksterV2Web.PostLive.PostsSixComponent)
         |> stream(:components, components)}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("load-more", _, socket) do
    IO.puts("📜 Loading more tag components...")

    tag_slug = socket.assigns.tag_slug
    displayed_post_ids = socket.assigns.displayed_post_ids
    last_module = socket.assigns.last_component_module

    # Build next batch of 4 components (Three, Four, Five, Six)
    {new_components, new_displayed_post_ids} =
      build_components_batch(tag_slug, displayed_post_ids, last_module)

    if new_components == [] do
      IO.puts("📜 No more posts to load")
      {:noreply, socket}
    else
      IO.puts("📜 Loaded #{length(new_components)} components with #{length(new_displayed_post_ids) - length(displayed_post_ids)} new posts")

      # Insert new components into stream
      socket =
        Enum.reduce(new_components, socket, fn component, acc_socket ->
          stream_insert(acc_socket, :components, component, at: -1)
        end)

      # Track the last component module for next load
      last_module = if new_components != [], do: List.last(new_components).module, else: last_module

      {:noreply,
       socket
       |> assign(:displayed_post_ids, new_displayed_post_ids)
       |> assign(:last_component_module, last_module)}
    end
  end

  # Build initial batch of 4 components (Three, Four, Five, Six)
  defp build_initial_components(tag_slug) do
    build_components_batch(tag_slug, [], BlocksterV2Web.PostLive.PostsSixComponent)
  end

  # Build a batch of 4 components cycling through the component modules
  defp build_components_batch(tag_slug, displayed_post_ids, last_module) do
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
        posts = Blog.list_published_posts_by_tag(
          tag_slug,
          limit: posts_needed,
          exclude_ids: acc_ids
        ) |> Blog.with_bux_balances()

        if posts == [] do
          # No more posts available
          {acc_components, acc_ids}
        else
          post_ids = Enum.map(posts, & &1.id)
          # Use unique integer to avoid ID conflicts across batches
          unique_id = System.unique_integer([:positive])
          component = %{
            id: "tag-#{tag_slug}-#{module}-#{unique_id}",
            module: module,
            posts: posts,
            content: tag_slug,
            type: "tag-posts"
          }

          {acc_components ++ [component], acc_ids ++ post_ids}
        end
      end)

    {components, final_displayed_ids}
  end
end
