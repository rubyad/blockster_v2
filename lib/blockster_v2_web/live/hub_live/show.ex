defmodule BlocksterV2Web.HubLive.Show do
  use BlocksterV2Web, :live_view
  use BlocksterV2Web.DesignSystem

  import BlocksterV2Web.SharedComponents, only: [lightning_icon: 1, token_badge: 1, video_play_icon: 1]

  alias BlocksterV2.ImageKit
  alias BlocksterV2.Blog
  alias BlocksterV2.Shop
  alias BlocksterV2.UserEvents

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Blog.get_hub_by_slug_with_associations(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Hub not found")
         |> redirect(to: "/")}

      hub ->
        tag = hub.tag_name

        # All posts for this hub (used for All tab + stats)
        all_posts =
          Blog.list_published_posts_by_hub(hub.id, tag_name: tag)
          |> Blog.with_bux_earned()

        # Video posts (used for Videos tab)
        videos_posts =
          Blog.list_video_posts_by_hub(hub.id, limit: 10, tag_name: tag)
          |> Blog.with_bux_earned()

        # Hub products for Shop tab. `list_products_by_hub/1` already maps
        # each row through `prepare_product_for_display/1` before returning,
        # so a second `Enum.map(&prepare_product_for_display/1)` blew up with
        # `key :variants not found` — the display map has no `:variants`.
        hub_products = Shop.list_products_by_hub(hub.id)

        sol_usd_rate = BlocksterV2.Shop.Pricing.sol_usd_rate()

        # Follow state
        user_follows_hub =
          case socket.assigns[:current_user] do
            nil -> false
            user -> Blog.user_follows_hub?(user.id, hub.id)
          end

        follower_count = Blog.get_hub_follower_count(hub.id)

        # Split all_posts for the All tab sections
        {pinned_post, mosaic_posts} =
          case all_posts do
            [first | rest] -> {first, Enum.take(rest, 7)}
            [] -> {nil, []}
          end

        {:ok,
         socket
         |> assign(:hub, hub)
         |> assign(:all_posts, all_posts)
         |> assign(:pinned_post, pinned_post)
         |> assign(:mosaic_posts, mosaic_posts)
         |> assign(:videos_posts, videos_posts)
         |> assign(:hub_products, hub_products)
         |> assign(:sol_usd_rate, sol_usd_rate)
         |> assign(:user_follows_hub, user_follows_hub)
         |> assign(:follower_count, follower_count)
         |> assign(:page_title, "#{hub.name} Hub")
         |> assign(:active_tab, "all")
         |> assign(:show_mobile_menu, false)}
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
    {:noreply,
     socket
     |> assign(:active_tab, tab)
     |> assign(:show_mobile_menu, false)}
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
  def handle_event("toggle_follow", _params, socket) do
    case socket.assigns[:current_user] do
      nil ->
        {:noreply, push_navigate(socket, to: ~p"/login")}

      user ->
        hub = socket.assigns.hub

        case Blog.toggle_hub_follow(user.id, hub.id) do
          {:ok, :followed} ->
            UserEvents.track(user.id, "hub_subscribe", %{
              target_type: "hub",
              target_id: hub.id
            })

            {:noreply,
             socket
             |> assign(:user_follows_hub, true)
             |> assign(:follower_count, socket.assigns.follower_count + 1)}

          {:ok, :unfollowed} ->
            UserEvents.track(user.id, "hub_unsubscribe", %{
              target_type: "hub",
              target_id: hub.id
            })

            {:noreply,
             socket
             |> assign(:user_follows_hub, false)
             |> assign(:follower_count, max(socket.assigns.follower_count - 1, 0))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Something went wrong")}
        end
    end
  end

  # ── Helpers ──────────────────────────────────────────────────────────────────

  defp post_count(hub) do
    if Ecto.assoc_loaded?(hub.posts), do: length(hub.posts), else: 0
  end

  defp compact_number(n) when is_integer(n) and n >= 1_000_000,
    do: "#{Float.round(n / 1_000_000, 1)}M"

  defp compact_number(n) when is_integer(n) and n >= 1_000,
    do: "#{Float.round(n / 1_000, 1)}k"

  defp compact_number(n) when is_integer(n), do: "#{n}"
  defp compact_number(_), do: "0"

  defp read_time(post) do
    word_count =
      case post.content do
        %{"content" => content} when is_list(content) ->
          content
          |> Enum.map(&extract_text/1)
          |> Enum.join(" ")
          |> String.split(~r/\s+/, trim: true)
          |> length()

        _ ->
          0
      end

    max(div(word_count, 200), 1)
  end

  defp extract_text(%{"text" => text}), do: text
  defp extract_text(%{"content" => content}) when is_list(content),
    do: Enum.map(content, &extract_text/1) |> Enum.join(" ")
  defp extract_text(_), do: ""

  defp author_initials(post) do
    name = post.author_name || (post.author && post.author.username) || "?"
    name
    |> String.split(~r/[\s_-]+/)
    |> Enum.take(2)
    |> Enum.map(&String.first/1)
    |> Enum.join()
    |> String.upcase()
  end

  defp author_display_name(post) do
    post.author_name || (post.author && post.author.username) || "Unknown"
  end

  defp format_date(nil), do: ""
  defp format_date(dt) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, dt, :second)

    cond do
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(dt, "%b %d, %Y")
    end
  end

  defp tab_label("all"), do: "All"
  defp tab_label("news"), do: "News"
  defp tab_label("videos"), do: "Videos"
  defp tab_label("shop"), do: "Shop"
  defp tab_label("events"), do: "Events"

  defp tab_count("all", assigns) do
    length(assigns.all_posts) + length(assigns.videos_posts) + length(assigns.hub_products)
  end
  defp tab_count("news", assigns), do: length(assigns.all_posts)
  defp tab_count("videos", assigns), do: length(assigns.videos_posts)
  defp tab_count("shop", assigns), do: length(assigns.hub_products)
  defp tab_count("events", _assigns), do: 0
end
