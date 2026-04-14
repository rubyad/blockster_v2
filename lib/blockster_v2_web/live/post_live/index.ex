defmodule BlocksterV2Web.PostLive.Index do
  @moduledoc """
  Homepage LiveView — redesigned per `docs/solana/homepage_redesign_plan.md`.

  Posts are rendered in date-desc order through a cycling sequence of layouts.

      Hero (one-shot, 1 post)
      ThreeColumn (3 posts)
      Mosaic       (14 posts)
      VideoLayout  (7 video posts — skipped when fewer videos remain)
      Editorial    (4 posts)
      [repeat ThreeColumn → Mosaic → VideoLayout → Editorial …]

  Plus several one-shot non-feed sections rendered exactly once on initial
  mount and never appended to the infinite-scroll cycle:

      Hub showcase            (top 8 hubs by post count)
      Token sales · STUB      (3 Coming Soon placeholder cards)
      Hubs you follow         (logged-in only)
      Recommended for you · STUB (logged-in only)
      Welcome hero            (anonymous only)
      What you unlock         (anonymous only)

  Real-time BUX updates flow through the existing `:bux_update` PubSub topic
  and `send_update` to whichever cycling layout component contains the post.
  """

  use BlocksterV2Web, :live_view

  alias BlocksterV2.Blog
  alias BlocksterV2.Blog.Post
  alias BlocksterV2.EngagementTracker

  # Old cycling component modules: Three (5) → Four (3) → Five (6) → Six (5) = 19 per cycle
  # Total posts per component cycle
  @posts_per_cycle 19

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      EngagementTracker.subscribe_to_all_bux_updates()
    end

    # Fetch the hero post (most recent) — displayed above the feed.
    hero_post = fetch_hero_post()
    hero_id = if hero_post, do: [hero_post.id], else: []

    # Build initial 4 old-style components (19 posts), offset by hero post
    {cycle_components, displayed_post_ids} = build_components_batch(0, hero_id, 0)

    user = socket.assigns[:current_user]

    # Logged-in only one-shots
    followed_hub_posts = if user, do: Blog.list_posts_from_followed_hubs(user, limit: 8), else: []

    post_to_component = build_post_to_component_map(cycle_components)
    component_module_map = build_component_module_map(cycle_components)

    all_posts = collect_posts(cycle_components, hero_post, followed_hub_posts)
    bux_balances = build_bux_balances_map(all_posts)

    user_post_rewards =
      if user do
        EngagementTracker.get_user_post_rewards_map(user.id)
      else
        %{}
      end

    hub_showcase = list_hub_showcase()

    homepage_top_desktop_banners = load_homepage_banners(socket, "homepage_top_desktop")
    homepage_top_mobile_banners = load_homepage_banners(socket, "homepage_top_mobile")

    # Load template-based inline ads. First try homepage-specific placements,
    # then fall back to article_inline banners (same template ads shown on articles).
    inline_desktop_banners = load_homepage_inline_banners(socket)
    inline_mobile_banners = load_homepage_banners(socket, "homepage_inline_mobile")

    {:ok,
     socket
     |> assign(:page_title, "Latest Posts")
     |> assign(:show_categories, false)
     |> assign(:show_why_earn_bux, true)
     |> assign(:hero_post, hero_post)
     |> assign(:hub_showcase, hub_showcase)
     |> assign(:followed_hub_posts, followed_hub_posts)
     |> assign(:displayed_post_ids, displayed_post_ids)
     |> assign(:bux_balances, bux_balances)
     |> assign(:user_post_rewards, user_post_rewards)
     |> assign(:component_module_map, component_module_map)
     |> assign(:post_to_component_map, post_to_component)
     |> assign(:current_offset, @posts_per_cycle)
     |> assign(:inline_banner_offset, length(cycle_components))
     |> assign(:search_query, "")
     |> assign(:search_results, [])
     |> assign(:show_search_results, false)
     |> assign(:show_mobile_search, false)
     |> assign(:show_bux_deposit_modal, false)
     |> assign(:deposit_modal_post, nil)
     |> assign(:homepage_top_desktop_banners, homepage_top_desktop_banners)
     |> assign(:homepage_top_mobile_banners, homepage_top_mobile_banners)
     |> assign(:inline_desktop_banners, inline_desktop_banners)
     |> assign(:inline_mobile_banners, inline_mobile_banners)
     |> stream(:components, cycle_components)}
  end

  defp load_homepage_banners(socket, placement) do
    if connected?(socket),
      do: BlocksterV2.Ads.list_active_banners_by_placement(placement),
      else: []
  end

  # Collects template-based inline ad banners for the homepage feed.
  # Priority: homepage_inline > homepage_inline_desktop > article_inline_*.
  # Sorted by sort_order (ascending) so admins control display order.
  defp load_homepage_inline_banners(socket) do
    if connected?(socket) do
      homepage = BlocksterV2.Ads.list_active_banners_by_placement("homepage_inline")

      if homepage != [] do
        homepage
      else
        desktop = BlocksterV2.Ads.list_active_banners_by_placement("homepage_inline_desktop")

        if desktop != [] do
          desktop
        else
          ["article_inline_1", "article_inline_2", "article_inline_3"]
          |> Enum.flat_map(&BlocksterV2.Ads.list_active_banners_by_placement/1)
        end
      end
    else
      []
    end
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
    inline_banner_offset = socket.assigns.inline_banner_offset

    {new_components, new_displayed_post_ids} =
      build_components_batch(offset, displayed_post_ids, inline_banner_offset)

    if new_components == [] do
      {:reply, %{end_reached: true}, socket}
    else
      socket =
        Enum.reduce(new_components, socket, fn comp, acc ->
          stream_insert(acc, :components, comp, at: -1)
        end)

      new_module_map = build_component_module_map(new_components)
      new_post_map = build_post_to_component_map(new_components)

      new_posts = Enum.flat_map(new_components, fn c -> c.posts end)
      updated_balances = Map.merge(socket.assigns.bux_balances, build_bux_balances_map(new_posts))

      {:noreply,
       socket
       |> assign(:displayed_post_ids, new_displayed_post_ids)
       |> assign(:current_offset, offset + @posts_per_cycle)
       |> assign(:inline_banner_offset, inline_banner_offset + length(new_components))
       |> assign(:component_module_map, Map.merge(socket.assigns.component_module_map, new_module_map))
       |> assign(:post_to_component_map, Map.merge(socket.assigns.post_to_component_map, new_post_map))
       |> assign(:bux_balances, updated_balances)}
    end
  end

  # Search handlers — preserved from the previous implementation, used by the
  # new design system header search button.
  @impl true
  def handle_event("search_posts", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2 do
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

  # BUX Deposit Modal handlers (admin only)
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
            {:ok, _new_pool_balance} ->
              {:noreply,
               socket
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
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_info({:bux_update, post_id, _pool_balance, total_distributed}, socket) do
    if post_id in socket.assigns.displayed_post_ids do
      bux_balances = Map.put(socket.assigns.bux_balances, post_id, total_distributed)

      case Map.get(socket.assigns.post_to_component_map, post_id) do
        {component_id, module} ->
          send_update(self(), module, id: component_id, bux_balances: bux_balances)

        nil ->
          :ok
      end

      {:noreply, assign(socket, :bux_balances, bux_balances)}
    else
      {:noreply, socket}
    end
  end

  # Backward-compat handler for legacy 3-element broadcasts
  def handle_info({:bux_update, _post_id, _new_balance}, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_info({:posts_reordered, _post_id, _new_balance}, socket) do
    {:noreply, socket}
  end

  # ============================================================================
  # Cycle building (old-style Three → Four → Five → Six, 19 posts per cycle)
  # ============================================================================

  defp fetch_hero_post do
    case Blog.list_published_posts_by_date(limit: 1) do
      [post | _] -> post
      _ -> nil
    end
  end

  # Builds a batch of 4 components cycling Three(5) → Four(3) → Five(6) → Six(5).
  # Uses offset-based pagination. `inline_banner_offset` tags each component with
  # a global index for rotating inline ad banners.
  defp build_components_batch(offset, displayed_post_ids, inline_banner_offset) do
    posts =
      Blog.list_published_posts_by_date(limit: @posts_per_cycle, offset: offset)
      |> Enum.filter(fn p -> p.id not in displayed_post_ids end)

    if posts == [] do
      {[], displayed_post_ids}
    else
      {three_posts, rest} = Enum.split(posts, 5)
      {four_posts, rest} = Enum.split(rest, 3)
      {five_posts, rest} = Enum.split(rest, 6)
      {six_posts, _} = Enum.split(rest, 5)

      uid = System.unique_integer([:positive])

      components =
        [
          %{
            id: "home-posts-three-#{uid}",
            module: BlocksterV2Web.PostLive.PostsThreeComponent,
            posts: three_posts,
            type: "home-posts",
            content: "home"
          },
          %{
            id: "home-posts-four-#{uid}",
            module: BlocksterV2Web.PostLive.PostsFourComponent,
            posts: four_posts,
            type: "home-posts",
            content: "home"
          },
          %{
            id: "home-posts-five-#{uid}",
            module: BlocksterV2Web.PostLive.PostsFiveComponent,
            posts: five_posts,
            type: "home-posts",
            content: "home"
          },
          %{
            id: "home-posts-six-#{uid}",
            module: BlocksterV2Web.PostLive.PostsSixComponent,
            posts: six_posts,
            type: "home-posts",
            content: "home"
          }
        ]
        |> Enum.filter(fn c -> c.posts != [] end)
        |> Enum.with_index(inline_banner_offset)
        |> Enum.map(fn {comp, idx} -> Map.put(comp, :inline_banner_index, idx) end)

      new_post_ids = Enum.map(posts, & &1.id)
      {components, displayed_post_ids ++ new_post_ids}
    end
  end

  defp build_post_to_component_map(components) do
    Enum.reduce(components, %{}, fn comp, acc ->
      Enum.reduce(comp.posts, acc, fn post, inner ->
        Map.put(inner, post.id, {comp.id, comp.module})
      end)
    end)
  end

  defp build_component_module_map(components) do
    Enum.reduce(components, %{}, fn comp, acc -> Map.put(acc, comp.id, comp.module) end)
  end

  defp build_bux_balances_map(posts) do
    posts
    |> Enum.uniq_by(& &1.id)
    |> Enum.reduce(%{}, fn post, acc ->
      Map.put(acc, post.id, Map.get(post, :bux_balance, 0))
    end)
  end

  defp collect_posts(components, hero_post, followed_hub_posts) do
    base = if hero_post, do: [hero_post], else: []
    cycle = Enum.flat_map(components, & &1.posts)
    base ++ cycle ++ followed_hub_posts
  end

  # ============================================================================
  # Hub showcase
  # ============================================================================

  # Returns the top 8 hubs ordered by published post count (desc) for the
  # one-shot hub showcase section. Each entry is a map with the hub's struct
  # plus a `:post_count` integer.
  defp list_hub_showcase do
    hubs = Blog.list_hubs()

    counts =
      hubs
      |> Enum.map(fn hub ->
        count = Blog.count_published_posts_by_hub(hub)
        Map.put(hub, :post_count, count)
      end)
      |> Enum.sort_by(& &1.post_count, :desc)
      |> Enum.take(8)

    counts
  end
end
