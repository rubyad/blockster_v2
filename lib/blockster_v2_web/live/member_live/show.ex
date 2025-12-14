defmodule BlocksterV2Web.MemberLive.Show do
  use BlocksterV2Web, :live_view

  import BlocksterV2Web.SharedComponents, only: [lightning_icon: 1]

  alias BlocksterV2.Accounts
  alias BlocksterV2.BuxMinter
  alias BlocksterV2.EngagementTracker
  alias BlocksterV2.Social
  alias BlocksterV2.Blog

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, active_tab: "activity", time_period: "24h")}
  end

  @impl true
  def handle_params(%{"slug" => slug_or_address}, _url, socket) do
    case Accounts.get_user_by_slug_or_address(slug_or_address) do
      nil ->
        {:noreply,
         socket
         |> put_flash(:error, "Member not found")
         |> push_navigate(to: ~p"/")}

      member ->
        all_activities = load_member_activities(member.id)
        time_period = socket.assigns[:time_period] || "24h"
        filtered_activities = filter_activities_by_period(all_activities, time_period)
        total_bux = calculate_total_bux(filtered_activities)
        overall_multiplier = EngagementTracker.get_user_multiplier(member.id)
        bux_balance = EngagementTracker.get_user_bux_balance(member.id)

        # Fetch on-chain BUX balance and update Mnesia (async to not block page load)
        maybe_refresh_bux_balance(member)

        {:noreply,
         socket
         |> assign(:page_title, member.username || "Member")
         |> assign(:member, member)
         |> assign(:all_activities, all_activities)
         |> assign(:activities, filtered_activities)
         |> assign(:total_bux, total_bux)
         |> assign(:time_period, time_period)
         |> assign(:overall_multiplier, overall_multiplier)
         |> assign(:bux_balance, bux_balance)}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("set_time_period", %{"period" => period}, socket) do
    filtered_activities = filter_activities_by_period(socket.assigns.all_activities, period)
    total_bux = calculate_total_bux(filtered_activities)

    {:noreply,
     socket
     |> assign(:time_period, period)
     |> assign(:activities, filtered_activities)
     |> assign(:total_bux, total_bux)}
  end

  # Load activities from both Mnesia tables (post reads and X shares)
  defp load_member_activities(user_id) do
    # Get post read rewards from Mnesia
    read_activities = EngagementTracker.get_all_user_post_rewards(user_id)

    # Get X share rewards from Mnesia
    share_activities = Social.list_user_share_rewards(user_id)

    # Combine and sort by timestamp (most recent first)
    # Read activities need post info enrichment, share activities have retweet_id
    (enrich_read_activities_with_post_info(read_activities) ++ share_activities)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  # Add post title/slug to read activities only
  defp enrich_read_activities_with_post_info(activities) do
    # Get all unique post IDs from read activities
    post_ids =
      activities
      |> Enum.map(& &1.post_id)
      |> Enum.uniq()

    # Fetch posts
    posts = Blog.get_posts_by_ids(post_ids)
    posts_map = Map.new(posts, fn post -> {post.id, post} end)

    # Enrich read activities with post info
    Enum.map(activities, fn activity ->
      post = Map.get(posts_map, activity.post_id)

      Map.merge(activity, %{
        post_title: post && post.title,
        post_slug: post && post.slug
      })
    end)
  end

  defp filter_activities_by_period(activities, period) do
    cutoff = get_cutoff_time(period)

    case cutoff do
      nil -> activities
      time -> Enum.filter(activities, fn a -> DateTime.compare(a.timestamp, time) != :lt end)
    end
  end

  defp get_cutoff_time("24h"), do: DateTime.add(DateTime.utc_now(), -24, :hour)
  defp get_cutoff_time("7d"), do: DateTime.add(DateTime.utc_now(), -7, :day)
  defp get_cutoff_time("30d"), do: DateTime.add(DateTime.utc_now(), -30, :day)
  defp get_cutoff_time("all"), do: nil

  defp calculate_total_bux(activities) do
    activities
    |> Enum.map(& &1.amount)
    |> Enum.filter(&is_number/1)
    |> Enum.sum()
  end

  # Fetch on-chain BUX balance and update Mnesia (async)
  defp maybe_refresh_bux_balance(%{id: user_id, smart_wallet_address: wallet})
       when is_binary(wallet) and wallet != "" do
    Task.start(fn ->
      case BuxMinter.get_balance(wallet) do
        {:ok, balance} ->
          EngagementTracker.update_user_bux_balance(user_id, wallet, balance)

        {:error, _reason} ->
          :ok
      end
    end)
  end

  defp maybe_refresh_bux_balance(_member), do: :ok
end
