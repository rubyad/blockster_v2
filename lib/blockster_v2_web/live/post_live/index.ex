defmodule BlocksterV2Web.PostLive.Index do
  use BlocksterV2Web, :live_view

  import BlocksterV2Web.SharedComponents, only: [lightning_icon: 1]

  alias BlocksterV2.Blog
  alias BlocksterV2.Blog.Post
  alias BlocksterV2.EngagementTracker

  @impl true
  def mount(_params, _session, socket) do
    # Subscribe to all BUX updates for real-time post card updates
    if connected?(socket) do
      EngagementTracker.subscribe_to_all_bux_updates()
    end

    # Load ALL curated posts in a single DB query and group by section
    all_curated = Blog.get_all_curated_posts()

    # Extract posts for each section from the grouped result (with empty list fallback)
    latest_news_posts = Map.get(all_curated, "latest_news", []) |> Blog.with_bux_balances()
    conversations_posts = Map.get(all_curated, "conversations", []) |> Blog.with_bux_balances()
    posts_three_posts = Map.get(all_curated, "posts_three", []) |> Blog.with_bux_balances()
    posts_four_posts = Map.get(all_curated, "posts_four", []) |> Blog.with_bux_balances()
    posts_five_posts = Map.get(all_curated, "posts_five", []) |> Blog.with_bux_balances()
    posts_six_posts = Map.get(all_curated, "posts_six", []) |> Blog.with_bux_balances()

    # Create a single list of all displayed post IDs for tracking
    displayed_post_ids =
      (Enum.map(latest_news_posts, & &1.id) ++ Enum.map(conversations_posts, & &1.id) ++ Enum.map(posts_three_posts, & &1.id) ++ Enum.map(posts_four_posts, & &1.id) ++ Enum.map(posts_five_posts, & &1.id) ++ Enum.map(posts_six_posts, & &1.id))
      |> Enum.uniq()
    IO.inspect(displayed_post_ids, label: "Displayed Post IDs")

    # Build initial bux_balances map from posts
    all_posts = latest_news_posts ++ conversations_posts ++ posts_three_posts ++ posts_four_posts ++ posts_five_posts ++ posts_six_posts
    bux_balances = all_posts
      |> Enum.uniq_by(& &1.id)
      |> Enum.reduce(%{}, fn post, acc ->
        Map.put(acc, post.id, Map.get(post, :bux_balance, 0))
      end)

    displayed_categories = []
    displayed_tags = []
    displayed_hubs = []
    displayed_banners = ["master-crypto"]

    current_user = socket.assigns[:current_user]

    # Load section titles from DB (with defaults)
    section_titles = Blog.get_all_section_titles()
    latest_news_title = Map.get(section_titles, "latest_news", "Top Stories")
    conversations_title = Map.get(section_titles, "conversations", "Conversations with industry leaders")
    posts_three_title = Map.get(section_titles, "posts_three", "Real World Assets (RWA)")
    posts_four_title = Map.get(section_titles, "posts_four", "DeFi")
    posts_five_title = Map.get(section_titles, "posts_five", "Investment")
    posts_six_title = Map.get(section_titles, "posts_six", "Business")

    components = [
      %{module: BlocksterV2Web.PostLive.PostsOneComponent, id: "posts-one", posts: latest_news_posts, current_user: current_user, type: "curated-posts", content: "curated", title: latest_news_title, bux_balances: bux_balances},
      %{module: BlocksterV2Web.PostLive.PostsTwoComponent, id: "posts-two", posts: conversations_posts, current_user: current_user, type: "curated-posts", content: "curated", title: conversations_title, bux_balances: bux_balances},
      %{module: BlocksterV2Web.PostLive.PostsThreeComponent, id: "posts-three", posts: posts_three_posts, current_user: current_user, type: "curated-posts", title: posts_three_title, bux_balances: bux_balances},
      %{module: BlocksterV2Web.PostLive.PostsFourComponent, id: "posts-four", posts: posts_four_posts, current_user: current_user, type: "curated-posts", title: posts_four_title, bux_balances: bux_balances},
      %{module: BlocksterV2Web.PostLive.PostsFiveComponent, id: "posts-five", posts: posts_five_posts, current_user: current_user, type: "curated-posts", title: posts_five_title, bux_balances: bux_balances},
      %{module: BlocksterV2Web.PostLive.PostsSixComponent, id: "posts-six", posts: posts_six_posts, current_user: current_user, type: "curated-posts", title: posts_six_title, bux_balances: bux_balances},
      # %{module: BlocksterV2Web.PostLive.ShopOneComponent, id: "shop-one", type: "shop", content: "general"},
      # %{module: BlocksterV2Web.PostLive.PostsThreeComponent, id: "posts-three", posts: business_posts, type: "category-posts", content: "business"},
      # %{module: BlocksterV2Web.PostLive.RewardsBannerComponent, id: "rewards-banner", type: "banner", content: "rewards"},
      # %{module: BlocksterV2Web.PostLive.ShopTwoComponent, id: "shop-two", type: "shop", content: "general"},
      # %{module: BlocksterV2Web.PostLive.PostsFourComponent, id: "posts-four", posts: people_posts, type: "category-posts", content: "people"},
      # %{module: BlocksterV2Web.PostLive.FullWidthBannerComponent, id: "crypto-streetwear-hero", type: "banner", content: "streetwear"},
      # %{module: BlocksterV2Web.PostLive.PostsFiveComponent, id: "posts-five", posts: tech_posts, type: "category-posts", content: "tech"},
      # %{module: BlocksterV2Web.PostLive.ShopThreeComponent, id: "shop-three", type: "shop", content: "general"},
      # %{module: BlocksterV2Web.PostLive.PostsSixComponent, id: "posts-six", posts: defi_posts, type: "category-posts", content: "defi"},
      # %{module: BlocksterV2Web.PostLive.ShopFourComponent, id: "shop-four", type: "shops", content: "general"}
    ]

    # Track component ID -> module mapping for real-time BUX updates via send_update
    initial_component_map = components
      |> Enum.filter(fn comp -> String.starts_with?(comp.id, "posts-") or String.starts_with?(comp.id, "videos-") end)
      |> Enum.reduce(%{}, fn comp, acc -> Map.put(acc, comp.id, comp.module) end)

    {:ok,
        socket
          # |> assign(:latest_news_posts, latest_news_posts)
          # |> assign(:conversations_posts, conversations_posts)
          # |> assign(:business_posts, business_posts)
          # |> assign(:people_posts, people_posts)
          # |> assign(:tech_posts, tech_posts)
          # |> assign(:defi_posts, defi_posts)
          # |> assign(:categories, categories)
          # |> assign(:selected_category, nil)
          # |> assign(:selected_interview_category, nil)
          |> assign(:page_title, "Latest Posts")
          |> assign(:search_query, "")
          |> assign(:search_results, [])
          |> assign(:show_search_results, false)
          |> assign(:show_post_selector, false)
          |> assign(:selector_section, nil)
          |> assign(:selector_position, nil)
          |> assign(:selector_query, "")
          |> assign(:selector_results, [])
          |> assign(:section_titles, section_titles)
          |> assign(:editing_title_section, nil)
          |> assign(:editing_title_value, "")
          |> assign(:displayed_post_ids, displayed_post_ids)
          |> assign(:displayed_categories, displayed_categories)
          |> assign(:displayed_tags, displayed_tags)
          |> assign(:displayed_hubs, displayed_hubs)
          |> assign(:displayed_banners, displayed_banners)
          |> assign(:bux_balances, bux_balances)
          |> assign(:component_module_map, initial_component_map)
          |> assign(:last_component_module, BlocksterV2Web.PostLive.PostsTwoComponent)
          |> stream(:components, components)
      }
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

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    post = Blog.get_post!(id)
    {:ok, _} = Blog.delete_post(post)

    # After deletion, navigate back to the index page to ensure the list is refreshed.
    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_event("filter_category", %{"category" => category}, socket) do
    filtered_posts = if category == "" do
      Blog.list_published_posts()
    else
      Blog.list_published_posts_by_category(category)
    end

    {:noreply,
     socket
     |> assign(:posts, filtered_posts)
     |> assign(:selected_category, if(category == "", do: nil, else: category))}
  end

  @impl true
  def handle_event("filter_interview_category", %{"category" => category}, socket) do
    all_interview_posts = Blog.list_published_posts_by_tag("interview", limit: 10)

    filtered_posts = if category == "" do
      Enum.shuffle(all_interview_posts)
    else
      all_interview_posts
      |> Enum.filter(fn post -> post.category.name == category end)
      |> Enum.shuffle()
    end

    {:noreply,
     socket
     |> assign(:interview_posts, filtered_posts)
     |> assign(:selected_interview_category, if(category == "", do: nil, else: category))}
  end

  @impl true
  def handle_event("search_posts", %{"value" => query}, socket) do
    results = if String.length(query) >= 2 do
      Blog.search_posts_fulltext(query, limit: 20)
    else
      []
    end

    IO.puts("🔍 SEARCH DEBUG")
    IO.inspect(query, label: "Query")
    IO.inspect(length(results), label: "Results count")
    IO.inspect(String.length(query) >= 2, label: "Show dropdown")

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
     |> assign(:show_search_results, false)}
  end

  @impl true
  def handle_info({BlocksterV2Web.PostLive.FormComponent, {:saved, _post}}, socket) do
    {:noreply,
     socket
     |> assign(:posts, Blog.list_published_posts())
     |> assign(:selected_category, nil)}
  end

  @impl true
  def handle_event("open_post_selector", %{"section" => section, "position" => position}, socket) do
    # Load 100 most recent posts by default
    recent_posts = Blog.list_published_posts(limit: 100)

    {:noreply,
     socket
     |> assign(:show_post_selector, true)
     |> assign(:selector_section, section)
     |> assign(:selector_position, String.to_integer(position))
     |> assign(:selector_query, "")
     |> assign(:selector_results, recent_posts)}
  end

  @impl true
  def handle_event("close_post_selector", _, socket) do
    {:noreply,
     socket
     |> assign(:show_post_selector, false)
     |> assign(:selector_section, nil)
     |> assign(:selector_position, nil)
     |> assign(:selector_query, "")
     |> assign(:selector_results, [])}
  end

  @impl true
  def handle_event("search_selector_posts", %{"value" => query}, socket) do
    results = if String.length(query) >= 2 do
      Blog.search_posts_fulltext(query, limit: 100)
    else
      # Show 100 most recent posts when query is empty or too short
      Blog.list_published_posts(limit: 100)
    end

    {:noreply,
     socket
     |> assign(:selector_query, query)
     |> assign(:selector_results, results)}
  end

  @impl true
  def handle_event("select_post", %{"post_id" => post_id}, socket) do
    section = socket.assigns.selector_section
    position = socket.assigns.selector_position
    post_id = String.to_integer(post_id)

    case Blog.update_curated_post_position(section, position, post_id) do
      {:ok, _} ->
        # Reload ALL curated posts in a single DB query
        all_curated = Blog.get_all_curated_posts()

        latest_news_posts = Map.get(all_curated, "latest_news", []) |> Blog.with_bux_balances()
        conversations_posts = Map.get(all_curated, "conversations", []) |> Blog.with_bux_balances()
        posts_three_posts = Map.get(all_curated, "posts_three", []) |> Blog.with_bux_balances()
        posts_four_posts = Map.get(all_curated, "posts_four", []) |> Blog.with_bux_balances()
        posts_five_posts = Map.get(all_curated, "posts_five", []) |> Blog.with_bux_balances()
        posts_six_posts = Map.get(all_curated, "posts_six", []) |> Blog.with_bux_balances()
        current_user = socket.assigns[:current_user]
        bux_balances = socket.assigns.bux_balances
        section_titles = socket.assigns.section_titles

        latest_news_title = Map.get(section_titles, "latest_news", get_default_title("latest_news"))
        conversations_title = Map.get(section_titles, "conversations", get_default_title("conversations"))
        posts_three_title = Map.get(section_titles, "posts_three", get_default_title("posts_three"))
        posts_four_title = Map.get(section_titles, "posts_four", get_default_title("posts_four"))
        posts_five_title = Map.get(section_titles, "posts_five", get_default_title("posts_five"))
        posts_six_title = Map.get(section_titles, "posts_six", get_default_title("posts_six"))

        # Update the stream with new component data
        # Use stream_insert with :at to replace existing items
        socket =
          socket
          |> stream_insert(:components, %{module: BlocksterV2Web.PostLive.PostsOneComponent, id: "posts-one", posts: latest_news_posts, current_user: current_user, type: "curated-posts", content: "curated", title: latest_news_title, bux_balances: bux_balances}, at: 0)
          |> stream_insert(:components, %{module: BlocksterV2Web.PostLive.PostsTwoComponent, id: "posts-two", posts: conversations_posts, current_user: current_user, type: "curated-posts", content: "curated", title: conversations_title, bux_balances: bux_balances}, at: 1)
          |> stream_insert(:components, %{module: BlocksterV2Web.PostLive.PostsThreeComponent, id: "posts-three", posts: posts_three_posts, current_user: current_user, type: "curated-posts", title: posts_three_title, bux_balances: bux_balances}, at: 2)
          |> stream_insert(:components, %{module: BlocksterV2Web.PostLive.PostsFourComponent, id: "posts-four", posts: posts_four_posts, current_user: current_user, type: "curated-posts", title: posts_four_title, bux_balances: bux_balances}, at: 3)
          |> stream_insert(:components, %{module: BlocksterV2Web.PostLive.PostsFiveComponent, id: "posts-five", posts: posts_five_posts, current_user: current_user, type: "curated-posts", title: posts_five_title, bux_balances: bux_balances}, at: 4)
          |> stream_insert(:components, %{module: BlocksterV2Web.PostLive.PostsSixComponent, id: "posts-six", posts: posts_six_posts, current_user: current_user, type: "curated-posts", title: posts_six_title, bux_balances: bux_balances}, at: 5)

        {:noreply,
         socket
         |> assign(:show_post_selector, false)
         |> assign(:selector_section, nil)
         |> assign(:selector_position, nil)
         |> assign(:selector_query, "")
         |> assign(:selector_results, [])
         |> put_flash(:info, "Post updated successfully")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update post")}
    end
  end

  # Title editing event handlers
  def handle_event("edit_section_title", %{"section" => section}, socket) do
    section_titles = socket.assigns.section_titles
    current_title = Map.get(section_titles, section, get_default_title(section))

    {:noreply,
     socket
     |> assign(:editing_title_section, section)
     |> assign(:editing_title_value, current_title)}
  end

  def handle_event("update_title_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, :editing_title_value, value)}
  end

  def handle_event("save_section_title", _params, socket) do
    section = socket.assigns.editing_title_section
    new_title = socket.assigns.editing_title_value

    case Blog.update_section_title(section, new_title) do
      {:ok, _} ->
        # Update section_titles map
        section_titles = Map.put(socket.assigns.section_titles, section, new_title)

        # Reload the components with new title
        {:noreply, reload_components_with_titles(socket, section_titles)}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update title")}
    end
  end

  def handle_event("cancel_title_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing_title_section, nil)
     |> assign(:editing_title_value, "")}
  end

  defp get_default_title(section) do
    case section do
      "latest_news" -> "Top Stories"
      "conversations" -> "Conversations with industry leaders"
      "posts_three" -> "Real World Assets (RWA)"
      "posts_four" -> "DeFi"
      "posts_five" -> "Investment"
      "posts_six" -> "Business"
      _ -> "Untitled"
    end
  end

  defp reload_components_with_titles(socket, section_titles) do
    # Reload ALL curated posts in a single DB query
    all_curated = Blog.get_all_curated_posts()

    latest_news_posts = Map.get(all_curated, "latest_news", []) |> Blog.with_bux_balances()
    conversations_posts = Map.get(all_curated, "conversations", []) |> Blog.with_bux_balances()
    posts_three_posts = Map.get(all_curated, "posts_three", []) |> Blog.with_bux_balances()
    posts_four_posts = Map.get(all_curated, "posts_four", []) |> Blog.with_bux_balances()
    posts_five_posts = Map.get(all_curated, "posts_five", []) |> Blog.with_bux_balances()
    posts_six_posts = Map.get(all_curated, "posts_six", []) |> Blog.with_bux_balances()
    current_user = socket.assigns[:current_user]
    bux_balances = socket.assigns.bux_balances

    latest_news_title = Map.get(section_titles, "latest_news", get_default_title("latest_news"))
    conversations_title = Map.get(section_titles, "conversations", get_default_title("conversations"))
    posts_three_title = Map.get(section_titles, "posts_three", get_default_title("posts_three"))
    posts_four_title = Map.get(section_titles, "posts_four", get_default_title("posts_four"))
    posts_five_title = Map.get(section_titles, "posts_five", get_default_title("posts_five"))
    posts_six_title = Map.get(section_titles, "posts_six", get_default_title("posts_six"))

    socket
    |> stream_insert(:components, %{module: BlocksterV2Web.PostLive.PostsOneComponent, id: "posts-one", posts: latest_news_posts, current_user: current_user, type: "curated-posts", content: "curated", title: latest_news_title, bux_balances: bux_balances}, at: 0)
    |> stream_insert(:components, %{module: BlocksterV2Web.PostLive.PostsTwoComponent, id: "posts-two", posts: conversations_posts, current_user: current_user, type: "curated-posts", content: "curated", title: conversations_title, bux_balances: bux_balances}, at: 1)
    |> stream_insert(:components, %{module: BlocksterV2Web.PostLive.PostsThreeComponent, id: "posts-three", posts: posts_three_posts, current_user: current_user, type: "curated-posts", title: posts_three_title, bux_balances: bux_balances}, at: 2)
    |> stream_insert(:components, %{module: BlocksterV2Web.PostLive.PostsFourComponent, id: "posts-four", posts: posts_four_posts, current_user: current_user, type: "curated-posts", title: posts_four_title, bux_balances: bux_balances}, at: 3)
    |> stream_insert(:components, %{module: BlocksterV2Web.PostLive.PostsFiveComponent, id: "posts-five", posts: posts_five_posts, current_user: current_user, type: "curated-posts", title: posts_five_title, bux_balances: bux_balances}, at: 4)
    |> stream_insert(:components, %{module: BlocksterV2Web.PostLive.PostsSixComponent, id: "posts-six", posts: posts_six_posts, current_user: current_user, type: "curated-posts", title: posts_six_title, bux_balances: bux_balances}, at: 5)
    |> assign(:section_titles, section_titles)
    |> assign(:editing_title_section, nil)
    |> assign(:editing_title_value, "")
    |> put_flash(:info, "Title updated successfully")
  end

  # edit this to load 3 more components when scrolling to bottom using algo that reads readers category, tag and hub preferences and history
  # if not logged in use general popular categories and tags and hubs
  # check last 3 components loaded to see if should load more posts or shop or banner
  # check displayed_post_ids to avoid loading duplicate posts
  # keep list of categories, tags and hubs already loaded to diversify content
  @impl true
  def handle_event("load-more", _, socket) do
    IO.puts("📜 Loading 3 more components...")

    displayed_post_ids = socket.assigns.displayed_post_ids
      displayed_categories = socket.assigns.displayed_categories
      displayed_tags = socket.assigns.displayed_tags
      displayed_hubs = socket.assigns.displayed_hubs
      displayed_banners = socket.assigns.displayed_banners
      # Get last component module from assigns (can't enumerate stream)
      last_module_name = socket.assigns.last_component_module
      # loaded 3 at a time, based on last component loaded
    {new_components, new_displayed_post_ids, new_displayed_categories, new_displayed_tags, new_displayed_hubs, new_displayed_banners} =
      cond do
        last_module_name == BlocksterV2Web.PostLive.PostsTwoComponent or last_module_name == BlocksterV2Web.PostLive.ShopFourComponent ->
          # select category randomly from all categories not yet displayed
          category =
            case Blog.list_categories() |> Enum.map(& &1.slug) |> Enum.filter(fn cat -> not Enum.member?(displayed_categories, cat) end) do
              [] -> nil
              available_categories -> Enum.random(available_categories)
            end
          # use category if not nil, otherwise filter is a random tag not yet displayed
          filter =
            if category == nil do
              # load posts by tag
              case Blog.list_tags() |> Enum.map(& &1.slug) |> Enum.filter(fn tag -> not Enum.member?(displayed_tags, tag) end) do
                [] -> nil
                available_tags -> Enum.random(available_tags)
              end
            else
              # load posts by category
              category
            end
          posts =
            if category != nil do
              Blog.list_published_posts_by_category(filter, limit: 5, exclude_ids: displayed_post_ids) |> Blog.with_bux_balances()
            else
              Blog.list_published_posts_by_tag(filter, limit: 5, exclude_ids: displayed_post_ids) |> Blog.with_bux_balances()
            end
          new_displayed_post_ids = displayed_post_ids ++ Enum.map(posts, & &1.id)
          new_displayed_categories =
            if category != nil do
              displayed_categories ++ [category]
            else
              displayed_categories
            end
          new_displayed_tags =
            if category == nil do
              displayed_tags ++ [filter]
            else
              displayed_tags
            end
          type = if category != nil, do: "category-posts", else: "tag-posts"

          {[
            %{module: BlocksterV2Web.PostLive.ShopOneComponent, id: "shop-one-#{System.unique_integer([:positive])}", type: "shop", content: "general"},
            %{module: BlocksterV2Web.PostLive.PostsThreeComponent, id: "posts-three-#{System.unique_integer([:positive])}", posts: posts, type: type, content: filter},
            %{module: BlocksterV2Web.PostLive.RewardsBannerComponent, id: "rewards-banner-#{System.unique_integer([:positive])}", type: "banner", content: "rewards"}
          ], new_displayed_post_ids, new_displayed_categories, new_displayed_tags, displayed_hubs, displayed_banners}

        last_module_name == BlocksterV2Web.PostLive.RewardsBannerComponent ->
          # load shop, People posts and full width banner and posts component
          # First posts section - select category or tag
          category1 =
            case Blog.list_categories() |> Enum.map(& &1.slug) |> Enum.filter(fn cat -> not Enum.member?(displayed_categories, cat) end) do
              [] -> nil
              available_categories -> Enum.random(available_categories)
            end
          filter1 =
            if category1 == nil do
              case Blog.list_tags() |> Enum.map(& &1.slug) |> Enum.filter(fn tag -> not Enum.member?(displayed_tags, tag) end) do
                [] -> nil
                available_tags -> Enum.random(available_tags)
              end
            else
              category1
            end
          posts1 =
            if category1 != nil do
              Blog.list_published_posts_by_category(filter1, limit: 3, exclude_ids: displayed_post_ids) |> Blog.with_bux_balances()
            else
              Blog.list_published_posts_by_tag(filter1, limit: 3, exclude_ids: displayed_post_ids) |> Blog.with_bux_balances()
            end

          # Second posts section - select category or tag
          category2 =
            case Blog.list_categories() |> Enum.map(& &1.slug) |> Enum.filter(fn cat -> not Enum.member?(displayed_categories ++ (if category1, do: [category1], else: []), cat) end) do
              [] -> nil
              available_categories -> Enum.random(available_categories)
            end
          filter2 =
            if category2 == nil do
              case Blog.list_tags() |> Enum.map(& &1.slug) |> Enum.filter(fn tag -> not Enum.member?(displayed_tags ++ (if category1 == nil, do: [filter1], else: []), tag) end) do
                [] -> nil
                available_tags -> Enum.random(available_tags)
              end
            else
              category2
            end
          posts2 =
            if category2 != nil do
              Blog.list_published_posts_by_category(filter2, limit: 6, exclude_ids: displayed_post_ids ++ Enum.map(posts1, & &1.id)) |> Blog.with_bux_balances()
            else
              Blog.list_published_posts_by_tag(filter2, limit: 6, exclude_ids: displayed_post_ids ++ Enum.map(posts1, & &1.id)) |> Blog.with_bux_balances()
            end

          new_displayed_post_ids = displayed_post_ids ++ Enum.map(posts1, & &1.id) ++ Enum.map(posts2, & &1.id)
          new_displayed_categories = displayed_categories ++ (if category1, do: [category1], else: []) ++ (if category2, do: [category2], else: [])
          new_displayed_tags = displayed_tags ++ (if category1 == nil, do: [filter1], else: []) ++ (if category2 == nil, do: [filter2], else: [])
          type1 = if category1 != nil, do: "category-posts", else: "tag-posts"
          type2 = if category2 != nil, do: "category-posts", else: "tag-posts"

          {[
            %{module: BlocksterV2Web.PostLive.ShopTwoComponent, id: "shop-two-#{System.unique_integer([:positive])}", type: "shop", content: "general"},
            %{module: BlocksterV2Web.PostLive.PostsFourComponent, id: "posts-four-#{System.unique_integer([:positive])}", posts: posts1, type: type1, content: filter1},
            %{module: BlocksterV2Web.PostLive.FullWidthBannerComponent, id: "crypto-streetwear-hero-#{System.unique_integer([:positive])}", type: "banner", content: "streetwear"},
            %{module: BlocksterV2Web.PostLive.PostsFiveComponent, id: "posts-five-#{System.unique_integer([:positive])}", posts: posts2, type: type2, content: filter2}
          ], new_displayed_post_ids, new_displayed_categories, new_displayed_tags, displayed_hubs, displayed_banners}

        last_module_name == BlocksterV2Web.PostLive.PostsFiveComponent ->
          # load shop, posts component and shop
          # select category or tag
          category =
            case Blog.list_categories() |> Enum.map(& &1.slug) |> Enum.filter(fn cat -> not Enum.member?(displayed_categories, cat) end) do
              [] -> nil
              available_categories -> Enum.random(available_categories)
            end
          filter =
            if category == nil do
              case Blog.list_tags() |> Enum.map(& &1.slug) |> Enum.filter(fn tag -> not Enum.member?(displayed_tags, tag) end) do
                [] -> nil
                available_tags -> Enum.random(available_tags)
              end
            else
              category
            end
          posts =
            if category != nil do
              Blog.list_published_posts_by_category(filter, limit: 5, exclude_ids: displayed_post_ids) |> Blog.with_bux_balances()
            else
              Blog.list_published_posts_by_tag(filter, limit: 5, exclude_ids: displayed_post_ids) |> Blog.with_bux_balances()
            end

          new_displayed_post_ids = displayed_post_ids ++ Enum.map(posts, & &1.id)
          new_displayed_categories =
            if category != nil do
              displayed_categories ++ [category]
            else
              displayed_categories
            end
          new_displayed_tags =
            if category == nil do
              displayed_tags ++ [filter]
            else
              displayed_tags
            end
          type = if category != nil, do: "category-posts", else: "tag-posts"

          {[
            %{module: BlocksterV2Web.PostLive.ShopThreeComponent, id: "shop-three-#{System.unique_integer([:positive])}", type: "shop", content: "general"},
            %{module: BlocksterV2Web.PostLive.PostsSixComponent, id: "posts-six-#{System.unique_integer([:positive])}", posts: posts, type: type, content: filter},
            %{module: BlocksterV2Web.PostLive.ShopFourComponent, id: "shop-four-#{System.unique_integer([:positive])}", type: "shop", content: "general"}
          ], new_displayed_post_ids, new_displayed_categories, new_displayed_tags, displayed_hubs, displayed_banners}


        true ->
          {[], displayed_post_ids, displayed_categories, displayed_tags, displayed_hubs, displayed_banners}
      end

    # Insert new components into stream
    socket =
      Enum.reduce(new_components, socket, fn component, acc_socket ->
        stream_insert(acc_socket, :components, component, at: -1)
      end)

    # Track the last component module for next load
    last_module = if new_components != [], do: List.last(new_components).module, else: last_module_name

    # Track new post component ID -> module mapping for real-time BUX updates
    new_component_map = new_components
      |> Enum.filter(fn comp -> String.starts_with?(comp.id, "posts-") or String.starts_with?(comp.id, "videos-") end)
      |> Enum.reduce(%{}, fn comp, acc -> Map.put(acc, comp.id, comp.module) end)
    updated_component_map = Map.merge(socket.assigns.component_module_map, new_component_map)

    {:noreply,
      socket
        |> assign(:displayed_post_ids, new_displayed_post_ids)
        |> assign(:displayed_categories, new_displayed_categories)
        |> assign(:displayed_tags, new_displayed_tags)
        |> assign(:displayed_hubs, new_displayed_hubs)
        |> assign(:displayed_banners, new_displayed_banners)
        |> assign(:component_module_map, updated_component_map)
        |> assign(:last_component_module, last_module)
    }
  end

  @impl true
  def handle_info({:bux_update, post_id, new_balance}, socket) do
    # Check if this post is displayed on the page
    if post_id in socket.assigns.displayed_post_ids do
      # Update the bux_balances map for real-time display
      bux_balances = Map.put(socket.assigns.bux_balances, post_id, new_balance)

      # Send update to all displayed post components so they re-render with new bux_balances
      # This is needed because components are in a stream and won't re-render from parent assigns
      for {component_id, module} <- socket.assigns.component_module_map do
        send_update(self(), module, id: component_id, bux_balances: bux_balances)
      end

      {:noreply, assign(socket, :bux_balances, bux_balances)}
    else
      {:noreply, socket}
    end
  end
end
