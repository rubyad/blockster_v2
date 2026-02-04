defmodule BlocksterV2Web.PostLive.Index do
  @moduledoc """
  Homepage LiveView - displays posts in chronological order.

  Posts are displayed in a cycling pattern: Three → Four → Five → Six → repeat.
  """

  use BlocksterV2Web, :live_view

  alias BlocksterV2.Blog
  alias BlocksterV2.Blog.Post
  alias BlocksterV2.EngagementTracker

  # Component modules for cycling through layouts (same as category page)
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

  # Total posts per component cycle (19 = 5+3+6+5)
  @posts_per_cycle 19

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to all BUX updates for real-time post card updates
    if connected?(socket) do
      EngagementTracker.subscribe_to_all_bux_updates()
    end

    # Build initial 4 components (19 posts total)
    {components, displayed_post_ids} = build_initial_components()

    # Build bux_balances map from posts
    all_posts = Enum.flat_map(components, fn c -> c.posts end)
    bux_balances = build_bux_balances_map(all_posts)

    # Track component ID -> module mapping for real-time BUX updates via send_update
    initial_component_map = components
      |> Enum.filter(fn comp -> String.starts_with?(comp.id, "posts-") or String.starts_with?(comp.id, "home-") end)
      |> Enum.reduce(%{}, fn comp, acc -> Map.put(acc, comp.id, comp.module) end)

    {:ok,
     socket
     |> assign(:page_title, "Latest Posts")
     |> assign(:show_categories, true)
     |> assign(:displayed_post_ids, displayed_post_ids)
     |> assign(:bux_balances, bux_balances)
     |> assign(:component_module_map, initial_component_map)
     |> assign(:last_component_module, BlocksterV2Web.PostLive.PostsSixComponent)
     |> assign(:current_offset, @posts_per_cycle)
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:show_search_results, false)
     |> assign(:show_mobile_search, false)
     |> assign(:show_bux_deposit_modal, false)
     |> assign(:deposit_modal_post, nil)
     |> stream(:components, components)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Latest Posts")
    |> assign(:post, nil)
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Post")
    |> assign(:post, %Post{})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    post = Blog.get_post!(id)

    socket
    |> assign(:page_title, "Edit Post")
    |> assign(:post, post)
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    post = Blog.get_post!(id)
    {:ok, _} = Blog.delete_post(post)
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_event("load-more", _, socket) do
    offset = socket.assigns.current_offset
    displayed_post_ids = socket.assigns.displayed_post_ids

    {new_components, new_displayed_post_ids} =
      build_components_batch(offset, displayed_post_ids)

    if new_components == [] do
      {:reply, %{end_reached: true}, socket}
    else
      # Insert new components into stream
      socket =
        Enum.reduce(new_components, socket, fn component, acc_socket ->
          stream_insert(acc_socket, :components, component, at: -1)
        end)

      # Track new post component ID -> module mapping for real-time BUX updates
      new_component_map = new_components
        |> Enum.filter(fn comp -> String.starts_with?(comp.id, "posts-") or String.starts_with?(comp.id, "home-") end)
        |> Enum.reduce(%{}, fn comp, acc -> Map.put(acc, comp.id, comp.module) end)
      updated_component_map = Map.merge(socket.assigns.component_module_map, new_component_map)

      # Update bux_balances with new posts
      new_posts = Enum.flat_map(new_components, fn c -> c.posts end)
      updated_bux_balances = Map.merge(socket.assigns.bux_balances, build_bux_balances_map(new_posts))

      {:noreply,
       socket
       |> assign(:displayed_post_ids, new_displayed_post_ids)
       |> assign(:current_offset, offset + @posts_per_cycle)
       |> assign(:component_module_map, updated_component_map)
       |> assign(:bux_balances, updated_bux_balances)
       |> assign(:last_component_module, BlocksterV2Web.PostLive.PostsSixComponent)}
    end
  end

  # Search handlers
  @impl true
  def handle_event("search_posts", %{"value" => query}, socket) do
    results = if String.length(query) >= 2 do
      Blog.search_posts_fulltext(query, limit: 20)
    else
      []
    end

    {:noreply,
     socket
     |> assign(:search_query, query)
     |> assign(:search_results, results)
     |> assign(:show_search_results, String.length(query) >= 2)}
  end

  @impl true
  def handle_event("close_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:show_search_results, false)
     |> assign(:show_mobile_search, false)}
  end

  @impl true
  def handle_event("open_mobile_search", _params, socket) do
    {:noreply, assign(socket, :show_mobile_search, true)}
  end

  @impl true
  def handle_event("close_mobile_search", _params, socket) do
    {:noreply,
     socket
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:show_search_results, false)
     |> assign(:show_mobile_search, false)}
  end

  # BUX Deposit Modal handlers
  @impl true
  def handle_event("open_bux_deposit_modal", %{"post-id" => post_id_str}, socket) do
    post_id = String.to_integer(post_id_str)
    post = Blog.get_post!(post_id)
    {pool_balance, total_deposited, total_distributed} = EngagementTracker.get_post_pool_stats(post_id)

    {:noreply,
     socket
     |> assign(:show_bux_deposit_modal, true)
     |> assign(:deposit_modal_post, %{
       id: post.id,
       title: post.title,
       pool_balance: pool_balance || 0,
       total_deposited: total_deposited || 0,
       total_distributed: total_distributed || 0
     })}
  end

  @impl true
  def handle_event("close_bux_deposit_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_bux_deposit_modal, false)
     |> assign(:deposit_modal_post, nil)}
  end

  @impl true
  def handle_event("deposit_bux", %{"amount" => amount_str}, socket) do
    if socket.assigns.current_user && socket.assigns.current_user.is_admin do
      case Integer.parse(amount_str) do
        {amount, _} when amount > 0 ->
          post_id = socket.assigns.deposit_modal_post.id

          case EngagementTracker.deposit_post_bux(post_id, amount) do
            {:ok, new_balance} ->
              # Update bux_balances map for the post card display
              bux_balances = Map.put(socket.assigns.bux_balances, post_id, new_balance)

              # Close modal and show success message
              {:noreply,
               socket
               |> assign(:bux_balances, bux_balances)
               |> assign(:show_bux_deposit_modal, false)
               |> assign(:deposit_modal_post, nil)
               |> put_flash(:info, "Deposited #{amount} BUX successfully!")}

            {:error, reason} ->
              {:noreply, put_flash(socket, :error, "Deposit failed: #{inspect(reason)}")}
          end

        _ ->
          {:noreply, put_flash(socket, :error, "Please enter a valid amount greater than 0")}
      end
    else
      {:noreply, put_flash(socket, :error, "Admin access required")}
    end
  end

  # ============================================================================
  # Handle Info (PubSub)
  # ============================================================================

  @impl true
  def handle_info({BlocksterV2Web.PostLive.FormComponent, {:saved, _post}}, socket) do
    # Post was saved, reload the page
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_info({:bux_update, post_id, new_balance}, socket) do
    # Check if this post is displayed on the page
    if post_id in socket.assigns.displayed_post_ids do
      # Update the bux_balances map for real-time display
      bux_balances = Map.put(socket.assigns.bux_balances, post_id, new_balance)

      # Send update to all displayed post components so they re-render with new bux_balances
      for {component_id, module} <- socket.assigns.component_module_map do
        send_update(self(), module, id: component_id, bux_balances: bux_balances)
      end

      {:noreply, assign(socket, :bux_balances, bux_balances)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:posts_reordered, _post_id, _new_balance}, socket) do
    # Posts have been reordered by BUX balance - rebuild all components with new order
    {components, displayed_post_ids} = build_initial_components()

    # Build new bux_balances map from posts
    all_posts = Enum.flat_map(components, fn c -> c.posts end)
    bux_balances = build_bux_balances_map(all_posts)

    # Track component ID -> module mapping for real-time BUX updates via send_update
    component_map = components
      |> Enum.filter(fn comp -> String.starts_with?(comp.id, "posts-") or String.starts_with?(comp.id, "home-") end)
      |> Enum.reduce(%{}, fn comp, acc -> Map.put(acc, comp.id, comp.module) end)

    {:noreply,
     socket
     |> assign(:displayed_post_ids, displayed_post_ids)
     |> assign(:bux_balances, bux_balances)
     |> assign(:component_module_map, component_map)
     |> assign(:current_offset, @posts_per_cycle)
     |> stream(:components, components, reset: true)}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  # Build initial batch of 4 components (19 posts total)
  defp build_initial_components do
    build_components_batch(0, [])
  end

  # Build a batch of 4 components cycling through the component modules
  defp build_components_batch(offset, displayed_post_ids) do
    # Calculate posts needed for one full cycle (19 posts)
    total_posts_needed = @posts_per_cycle

    # Fetch posts sorted by pool balance (highest first), then by date
    # list_published_posts_by_pool already attaches bux_balance to each post
    posts = Blog.list_published_posts_by_pool(
      limit: total_posts_needed,
      offset: offset
    )
    |> Enum.filter(fn p -> p.id not in displayed_post_ids end)

    if posts == [] do
      {[], displayed_post_ids}
    else
      # Distribute posts across components
      {three_posts, rest} = Enum.split(posts, 5)
      {four_posts, rest} = Enum.split(rest, 3)
      {five_posts, rest} = Enum.split(rest, 6)
      {six_posts, _} = Enum.split(rest, 5)

      # Use unique integer to avoid ID conflicts across batches
      unique_id = System.unique_integer([:positive])

      components = [
        %{
          id: "home-posts-three-#{unique_id}",
          module: BlocksterV2Web.PostLive.PostsThreeComponent,
          posts: three_posts,
          type: "home-posts",
          content: "home"
        },
        %{
          id: "home-posts-four-#{unique_id}",
          module: BlocksterV2Web.PostLive.PostsFourComponent,
          posts: four_posts,
          type: "home-posts",
          content: "home"
        },
        %{
          id: "home-posts-five-#{unique_id}",
          module: BlocksterV2Web.PostLive.PostsFiveComponent,
          posts: five_posts,
          type: "home-posts",
          content: "home"
        },
        %{
          id: "home-posts-six-#{unique_id}",
          module: BlocksterV2Web.PostLive.PostsSixComponent,
          posts: six_posts,
          type: "home-posts",
          content: "home"
        }
      ]

      # Filter out empty components
      components = Enum.filter(components, fn c -> c.posts != [] end)

      new_post_ids = Enum.map(posts, & &1.id)
      {components, displayed_post_ids ++ new_post_ids}
    end
  end

  defp build_bux_balances_map(posts) do
    posts
    |> Enum.uniq_by(& &1.id)
    |> Enum.reduce(%{}, fn post, acc ->
      Map.put(acc, post.id, Map.get(post, :bux_balance, 0))
    end)
  end
end
