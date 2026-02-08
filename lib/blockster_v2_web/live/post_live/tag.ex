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
        # Initialize with first batch of components
        {components, displayed_post_ids, bux_balances} = build_initial_components(tag.slug)

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
         |> assign(:show_categories, true)
         |> assign(:displayed_post_ids, displayed_post_ids)
         |> assign(:bux_balances, bux_balances)
         |> assign(:user_post_rewards, user_post_rewards)
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
    bux_balances = socket.assigns.bux_balances

    # Build next batch of 4 components (Three, Four, Five, Six)
    {new_components, new_displayed_post_ids, new_bux_balances} =
      build_components_batch(tag_slug, displayed_post_ids, last_module)

    if new_components == [] do
      IO.puts("📜 No more posts to load")
      {:reply, %{end_reached: true}, socket}
    else
      IO.puts("📜 Loaded #{length(new_components)} components with #{length(new_displayed_post_ids) - length(displayed_post_ids)} new posts")

      # Insert new components into stream
      socket =
        Enum.reduce(new_components, socket, fn component, acc_socket ->
          stream_insert(acc_socket, :components, component, at: -1)
        end)

      # Track the last component module for next load
      last_module = if new_components != [], do: List.last(new_components).module, else: last_module

      {:reply, %{},
       socket
       |> assign(:displayed_post_ids, new_displayed_post_ids)
       |> assign(:bux_balances, Map.merge(bux_balances, new_bux_balances))
       |> assign(:last_component_module, last_module)}
    end
  end

  # Handle BUX balance updates from PubSub
  @impl true
  def handle_info({:bux_update, post_id, new_balance}, socket) do
    # Update balance in our local map if this post is displayed
    if post_id in socket.assigns.displayed_post_ids do
      bux_balances = Map.put(socket.assigns.bux_balances, post_id, new_balance)
      {:noreply, assign(socket, :bux_balances, bux_balances)}
    else
      {:noreply, socket}
    end
  end

  # Handle posts reordering - ignore for now since we'd need to rebuild components
  # In future could trigger a full page refresh or partial rebuild
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
  defp build_initial_components(tag_slug) do
    build_components_batch(tag_slug, [], BlocksterV2Web.PostLive.PostsSixComponent)
  end

  # Build a batch of 4 components cycling through the component modules
  # Uses pool-sorted query (sorted by BUX pool balance DESC, then published_at DESC)
  defp build_components_batch(tag_slug, displayed_post_ids, last_module) do
    # Start from the component after last_module
    start_index = Enum.find_index(@component_modules, &(&1 == last_module))
    start_index = if start_index, do: rem(start_index + 1, 4), else: 0

    # Build 4 components in order
    {components, final_displayed_ids, bux_balances} =
      Enum.reduce(0..3, {[], displayed_post_ids, %{}}, fn idx, {acc_components, acc_ids, acc_balances} ->
        module_index = rem(start_index + idx, 4)
        module = Enum.at(@component_modules, module_index)
        posts_needed = Map.get(@posts_per_component, module)

        # Fetch posts for this component using pool-sorted query
        # Posts come pre-sorted by BUX pool balance DESC, then published_at DESC
        # bux_balance is already attached to each post
        posts = Blog.list_published_posts_by_tag_pool(
          tag_slug,
          limit: posts_needed,
          exclude_ids: acc_ids
        )

        if posts == [] do
          # No more posts available
          {acc_components, acc_ids, acc_balances}
        else
          post_ids = Enum.map(posts, & &1.id)
          # Collect bux_balances from posts
          new_balances = posts
            |> Enum.map(fn p -> {p.id, Map.get(p, :bux_balance, 0)} end)
            |> Map.new()

          # Use unique integer to avoid ID conflicts across batches
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
end
