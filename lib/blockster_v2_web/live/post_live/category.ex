defmodule BlocksterV2Web.PostLive.Category do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Blog
  alias BlocksterV2.Blog.Post
  alias BlocksterV2.EngagementTracker
  alias BlocksterV2.Repo

  import Ecto.Query, only: [from: 2]

  @posts_per_page 12

  @impl true
  def mount(%{"category" => category_slug}, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(BlocksterV2.PubSub, "post_bux:all")
    end

    case Blog.get_category_by_slug(category_slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Category not found")
         |> redirect(to: "/")}

      category ->
        # Featured post (latest in category)
        featured_posts =
          Blog.list_published_posts_by_date_category(category_slug, limit: 1)

        featured_post = List.first(featured_posts)
        featured_ids = if featured_post, do: [featured_post.id], else: []

        # First page of posts (excluding featured)
        posts =
          Blog.list_published_posts_by_date_category(category_slug,
            limit: @posts_per_page,
            exclude_ids: featured_ids
          )

        displayed_post_ids = featured_ids ++ Enum.map(posts, & &1.id)

        # BUX balances
        bux_balances =
          (featured_posts ++ posts)
          |> Enum.map(fn p -> {p.id, Map.get(p, :bux_balance, 0)} end)
          |> Map.new()

        # Stats
        post_count = Blog.count_published_posts_by_category(category_slug)
        {total_readers, total_bux_paid} = get_category_stats(category)

        # Related categories
        related_categories = get_related_categories(category_slug)

        # Featured author (from featured post)
        featured_author = get_featured_author(featured_post, category)

        # User's earned rewards
        user_post_rewards =
          if socket.assigns[:current_user] do
            EngagementTracker.get_user_post_rewards_map(socket.assigns.current_user.id)
          else
            %{}
          end

        # Ad banners
        inline_desktop_banners = load_listing_banners(socket, "homepage_inline_desktop")
        inline_mobile_banners = load_listing_banners(socket, "homepage_inline_mobile")

        # Stream pages of posts
        page = %{id: "page-0", posts: posts}

        {:ok,
         socket
         |> assign(:category, category.name)
         |> assign(:category_slug, category.slug)
         |> assign(:category_description, category.description)
         |> assign(:page_title, "#{category.name} - Blockster")
         |> assign(:announcement_banner, if(connected?(socket), do: BlocksterV2Web.AnnouncementBanner.pick(socket.assigns[:current_user])))
         |> assign(:featured_post, featured_post)
         |> assign(:featured_author, featured_author)
         |> assign(:post_count, post_count)
         |> assign(:total_readers, total_readers)
         |> assign(:total_bux_paid, total_bux_paid)
         |> assign(:related_categories, related_categories)
         |> assign(:filter, "trending")
         |> assign(:displayed_post_ids, displayed_post_ids)
         |> assign(:bux_balances, bux_balances)
         |> assign(:user_post_rewards, user_post_rewards)
         |> assign(:page_num, 0)
         |> assign(:inline_desktop_banners, inline_desktop_banners)
         |> assign(:inline_mobile_banners, inline_mobile_banners)
         |> stream(:post_pages, [page])}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("load-more", _, socket) do
    category_slug = socket.assigns.category_slug
    displayed_post_ids = socket.assigns.displayed_post_ids

    posts =
      Blog.list_published_posts_by_date_category(category_slug,
        limit: @posts_per_page,
        exclude_ids: displayed_post_ids
      )

    if posts == [] do
      {:reply, %{end_reached: true}, socket}
    else
      page_num = socket.assigns.page_num + 1
      page = %{id: "page-#{page_num}", posts: posts}
      new_ids = Enum.map(posts, & &1.id)

      new_balances =
        posts
        |> Enum.map(fn p -> {p.id, Map.get(p, :bux_balance, 0)} end)
        |> Map.new()

      {:reply, %{},
       socket
       |> assign(:displayed_post_ids, displayed_post_ids ++ new_ids)
       |> assign(:bux_balances, Map.merge(socket.assigns.bux_balances, new_balances))
       |> assign(:page_num, page_num)
       |> stream_insert(:post_pages, page, at: -1)}
    end
  end

  # Handle BUX updates from PubSub
  @impl true
  def handle_info({:bux_update, post_id, _pool_balance, total_distributed}, socket) do
    if post_id in socket.assigns.displayed_post_ids do
      bux_balances = Map.put(socket.assigns.bux_balances, post_id, total_distributed)
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

  # ── Private helpers ────────────────────────────────────────────────────────

  defp load_listing_banners(socket, placement) do
    if connected?(socket),
      do: BlocksterV2.Ads.list_active_banners_by_placement(placement),
      else: []
  end

  defp get_category_stats(category) do
    result =
      Repo.one(
        from(p in Post,
          where: not is_nil(p.published_at),
          where: p.category_id == ^category.id,
          select: {
            coalesce(sum(p.view_count), 0),
            coalesce(sum(p.bux_earned), 0)
          }
        )
      )

    result || {0, 0}
  end

  defp get_related_categories(current_slug) do
    Blog.list_categories()
    |> Enum.reject(&(&1.slug == current_slug))
    |> Enum.map(fn cat ->
      count = Blog.count_published_posts_by_category(cat.slug)
      %{name: cat.name, slug: cat.slug, post_count: count}
    end)
    |> Enum.sort_by(& &1.post_count, :desc)
    |> Enum.take(6)
  end

  defp get_featured_author(nil, _category), do: nil

  defp get_featured_author(featured_post, category) do
    author = featured_post.author

    if author do
      # Get author stats within this category
      stats =
        Repo.one(
          from(p in Post,
            where: not is_nil(p.published_at),
            where: p.category_id == ^category.id,
            where: p.author_id == ^author.id,
            select: %{
              post_count: count(p.id),
              total_reads: coalesce(sum(p.view_count), 0),
              total_bux: coalesce(sum(p.bux_earned), 0)
            }
          )
        )

      %{
        user: author,
        name: featured_post.author_name || author.username || "Anonymous",
        bio: author.bio,
        initials: user_initials(author),
        post_count: (stats && stats.post_count) || 0,
        total_reads: (stats && stats.total_reads) || 0,
        total_bux: (stats && stats.total_bux) || 0,
        slug: author.username || to_string(author.id)
      }
    end
  end

  defp user_initials(user) do
    name = user.username || "?"

    name
    |> String.split(~r/[\s_-]+/)
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  # ── Template helpers ───────────────────────────────────────────────────────

  def format_compact(n) when is_integer(n) and n >= 1_000_000,
    do: "#{Float.round(n / 1_000_000, 1)}M"

  def format_compact(n) when is_integer(n) and n >= 1_000,
    do: "#{Float.round(n / 1_000, 1)}k"

  def format_compact(n) when is_integer(n), do: Integer.to_string(n)
  def format_compact(n), do: to_string(n)

  defp post_href(post), do: ~p"/#{post.slug}"

  defp post_image(post) do
    post.featured_image || "https://picsum.photos/seed/post-#{post.id}/640/360"
  end

  defp post_hub_name(post) do
    if post.hub, do: post.hub.name, else: nil
  end

  defp post_hub_color(post) do
    if post.hub, do: post.hub.color_primary || "#6B7280", else: "#6B7280"
  end

  defp post_category_name(post) do
    if post.category, do: post.category.name, else: nil
  end

  defp post_author_name(post) do
    post.author_name || (post.author && post.author.username) || "Anonymous"
  end

  defp post_author_initials(post) do
    name = post.author_name || (post.author && post.author.username) || "?"

    name
    |> String.split(~r/[\s_-]+/)
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  defp post_read_minutes(post) do
    # Estimate reading time from content
    word_count =
      case post.content do
        %{"content" => blocks} when is_list(blocks) ->
          blocks
          |> Enum.map(&extract_text/1)
          |> Enum.join(" ")
          |> String.split(~r/\s+/)
          |> length()

        _ ->
          0
      end

    max(1, div(word_count, 250))
  end

  defp extract_text(%{"text" => text}), do: text

  defp extract_text(%{"content" => children}) when is_list(children),
    do: Enum.map_join(children, " ", &extract_text/1)

  defp extract_text(_), do: ""

  defp post_bux_reward(post, bux_balances) do
    balance = Map.get(bux_balances, post.id, 0)
    raw = if balance > 0, do: balance, else: post.base_bux_reward
    trunc(raw)
  end

  defp post_time_ago(post) do
    case post.published_at do
      nil ->
        ""

      dt ->
        diff = DateTime.diff(DateTime.utc_now(), dt, :second)

        cond do
          diff < 3600 -> "#{div(diff, 60)}m ago"
          diff < 86400 -> "#{div(diff, 3600)}h ago"
          diff < 604_800 -> "#{div(diff, 86400)}d ago"
          true -> Calendar.strftime(dt, "%b %-d")
        end
    end
  end

  defp post_view_count(post) do
    post.view_count || 0
  end
end
