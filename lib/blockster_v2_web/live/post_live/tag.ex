defmodule BlocksterV2Web.PostLive.Tag do
  use BlocksterV2Web, :live_view

  import BlocksterV2Web.SharedComponents, only: [lightning_icon: 1]

  alias BlocksterV2.Blog
  alias BlocksterV2.EngagementTracker

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
    # Subscribe to BUX pool updates for real-time balance changes
    if connected?(socket) do
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "post_bux:all")
    end

    case Blog.get_tag_by_slug(tag_slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Tag not found")
         |> redirect(to: "/")}

      tag ->
        # Initialize with first batch of components - default to "latest" sort
        {components, displayed_post_ids, bux_balances} = build_initial_components(tag.slug, "latest")

        # Build post_to_component map for targeted updates
        post_to_component = build_post_to_component_map(components)

        # Get user's earned rewards by post for displaying "earned" badges
        user_post_rewards = if socket.assigns[:current_user] do
          EngagementTracker.get_user_post_rewards_map(socket.assigns.current_user.id)
        else
          %{}
        end

        {:ok,
         socket
         |> assign(:tag_name, tag.name)
         |> assign(:tag_slug, tag.slug)
         |> assign(:page_title, "#{tag.name} - Blockster")
         |> assign(:sort_mode, "latest")
         |> assign(:show_categories, true)
         |> assign(:displayed_post_ids, displayed_post_ids)
         |> assign(:bux_balances, bux_balances)
         |> assign(:user_post_rewards, user_post_rewards)
         |> assign(:post_to_component_map, post_to_component)
         |> assign(:last_component_module, BlocksterV2Web.PostLive.PostsSixComponent)
         |> stream(:components, components)}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) when tab in ["latest", "popular"] do
    tag_slug = socket.assigns.tag_slug

    {components, displayed_post_ids, bux_balances} = build_initial_components(tag_slug, tab)
    post_to_component = build_post_to_component_map(components)

    {:noreply,
     socket
     |> assign(:sort_mode, tab)
     |> assign(:displayed_post_ids, displayed_post_ids)
     |> assign(:bux_balances, bux_balances)
     |> assign(:post_to_component_map, post_to_component)
     |> assign(:last_component_module, BlocksterV2Web.PostLive.PostsSixComponent)
     |> stream(:components, components, reset: true)}
  end

  @impl true
  def handle_event("load-more", _, socket) do
    tag_slug = socket.assigns.tag_slug
    displayed_post_ids = socket.assigns.displayed_post_ids
    last_module = socket.assigns.last_component_module
    bux_balances = socket.assigns.bux_balances
    sort_mode = socket.assigns.sort_mode

    # Build next batch of 4 components (Three, Four, Five, Six)
    {new_components, new_displayed_post_ids, new_bux_balances} =
      build_components_batch(tag_slug, displayed_post_ids, last_module, sort_mode)

    if new_components == [] do
      {:reply, %{end_reached: true}, socket}
    else
      # Insert new components into stream
      socket =
        Enum.reduce(new_components, socket, fn component, acc_socket ->
          stream_insert(acc_socket, :components, component, at: -1)
        end)

      # Track the last component module for next load
      last_module = if new_components != [], do: List.last(new_components).module, else: last_module

      # Update post_to_component map
      new_post_to_component = build_post_to_component_map(new_components)
      updated_post_to_component = Map.merge(socket.assigns.post_to_component_map, new_post_to_component)

      {:reply, %{},
       socket
       |> assign(:displayed_post_ids, new_displayed_post_ids)
       |> assign(:bux_balances, Map.merge(bux_balances, new_bux_balances))
       |> assign(:post_to_component_map, updated_post_to_component)
       |> assign(:last_component_module, last_module)}
    end
  end

  # Handle BUX updates from PubSub - use total_distributed for display
  @impl true
  def handle_info({:bux_update, post_id, _pool_balance, total_distributed}, socket) do
    if post_id in socket.assigns.displayed_post_ids do
      bux_balances = Map.put(socket.assigns.bux_balances, post_id, total_distributed)

      case Map.get(socket.assigns.post_to_component_map, post_id) do
        {component_id, module} ->
          send_update(self(), module, id: component_id, bux_balances: bux_balances)
        nil -> :ok
      end

      {:noreply, assign(socket, :bux_balances, bux_balances)}
    else
      {:noreply, socket}
    end
  end

  # Legacy 3-element broadcast (backward compat during rolling deploy)
  def handle_info({:bux_update, _post_id, _new_balance}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:posts_reordered, _post_id, _new_balance}, socket) do
    {:noreply, socket}
  end

  # Ignore other PubSub messages
  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # Build initial batch of 4 components (Three, Four, Five, Six)
  defp build_initial_components(tag_slug, sort_mode) do
    build_components_batch(tag_slug, [], BlocksterV2Web.PostLive.PostsSixComponent, sort_mode)
  end

  # Build a batch of 4 components cycling through the component modules
  defp build_components_batch(tag_slug, displayed_post_ids, last_module, sort_mode) do
    # Start from the component after last_module
    start_index = Enum.find_index(@component_modules, &(&1 == last_module))
    start_index = if start_index, do: rem(start_index + 1, 4), else: 0

    # Build 4 components in order
    {components, final_displayed_ids, bux_balances} =
      Enum.reduce(0..3, {[], displayed_post_ids, %{}}, fn idx, {acc_components, acc_ids, acc_balances} ->
        module_index = rem(start_index + idx, 4)
        module = Enum.at(@component_modules, module_index)
        posts_needed = Map.get(@posts_per_component, module)

        # Fetch posts based on sort mode
        posts = case sort_mode do
          "popular" ->
            Blog.list_published_posts_by_popular_tag(
              tag_slug,
              limit: posts_needed,
              exclude_ids: acc_ids
            )
          _ ->
            Blog.list_published_posts_by_date_tag(
              tag_slug,
              limit: posts_needed,
              exclude_ids: acc_ids
            )
        end

        if posts == [] do
          {acc_components, acc_ids, acc_balances}
        else
          post_ids = Enum.map(posts, & &1.id)
          new_balances = posts
            |> Enum.map(fn p -> {p.id, Map.get(p, :bux_balance, 0)} end)
            |> Map.new()

          unique_id = System.unique_integer([:positive])
          component = %{
            id: "tag-#{tag_slug}-#{module}-#{unique_id}",
            module: module,
            posts: posts,
            content: tag_slug,
            type: "tag-posts"
          }

          {acc_components ++ [component], acc_ids ++ post_ids, Map.merge(acc_balances, new_balances)}
        end
      end)

    {components, final_displayed_ids, bux_balances}
  end

  # Build post_id => {component_id, module} map for targeted send_update
  defp build_post_to_component_map(components) do
    Enum.reduce(components, %{}, fn comp, acc ->
      Enum.reduce(Map.get(comp, :posts, []), acc, fn post, inner_acc ->
        Map.put(inner_acc, post.id, {comp.id, comp.module})
      end)
    end)
  end
end
