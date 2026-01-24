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
    {:ok, assign(socket, active_tab: "activity", time_period: "24h", show_multiplier_dropdown: false)}
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
        multiplier_details = EngagementTracker.get_user_multiplier_details(member.id)
        token_balances = EngagementTracker.get_user_token_balances(member.id)

        # Fetch on-chain BUX balance and update Mnesia (async to not block page load)
        maybe_refresh_bux_balance(member)

        # Check if user is viewing their own profile and just signed up
        is_own_profile = socket.assigns[:current_user] && socket.assigns.current_user.id == member.id
        is_new_user = is_own_profile && is_new_user?(member)

        # Process pending anonymous claims if connected and viewing own profile
        socket = if connected?(socket) && is_own_profile do
          process_pending_claims(socket, member)
        else
          socket
          |> assign(:claimed_rewards, [])
          |> assign(:total_claimed, 0)
        end

        {:noreply,
         socket
         |> assign(:page_title, member.username || "Member")
         |> assign(:member, member)
         |> assign(:all_activities, all_activities)
         |> assign(:activities, filtered_activities)
         |> assign(:total_bux, total_bux)
         |> assign(:time_period, time_period)
         |> assign(:overall_multiplier, multiplier_details.overall_multiplier)
         |> assign(:multiplier_details, multiplier_details)
         |> assign(:token_balances, token_balances)
         |> assign(:is_new_user, is_new_user)}
    end
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, :active_tab, tab)}
  end

  @impl true
  def handle_event("toggle_multiplier_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_multiplier_dropdown, !socket.assigns.show_multiplier_dropdown)}
  end

  @impl true
  def handle_event("close_multiplier_dropdown", _params, socket) do
    {:noreply, assign(socket, :show_multiplier_dropdown, false)}
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

    # Enrich read activities with post info (always BUX - hub tokens removed)
    Enum.map(activities, fn activity ->
      post = Map.get(posts_map, activity.post_id)

      Map.merge(activity, %{
        post_title: post && post.title,
        post_slug: post && post.slug,
        token: "BUX"
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

  # Fetch all on-chain token balances via BalanceAggregator and update Mnesia (async)
  defp maybe_refresh_bux_balance(%{id: user_id, smart_wallet_address: wallet})
       when is_binary(wallet) and wallet != "" do
    BuxMinter.sync_user_balances_async(user_id, wallet)
  end

  defp maybe_refresh_bux_balance(_member), do: :ok

  # Check if user is new (account created within last 30 minutes for claim processing)
  defp is_new_user?(user) do
    account_age_seconds = NaiveDateTime.diff(NaiveDateTime.utc_now(), user.inserted_at, :second)
    account_age_seconds < 1800  # 30 minutes
  end

  # Process pending anonymous claims from localStorage
  defp process_pending_claims(socket, member) do
    pending_claims_raw = get_connect_params(socket)["pending_claims"]

    # Convert map to list if needed (JavaScript sends array as map with numeric keys)
    pending_claims = case pending_claims_raw do
      claims when is_map(claims) -> Map.values(claims)
      claims when is_list(claims) -> claims
      _ -> []
    end

    require Logger
    Logger.info("Processing claims for user #{member.id}: #{length(pending_claims)} claims, is_new_user: #{is_new_user?(member)}")

    if length(pending_claims) > 0 && is_new_user?(member) do
      # Process each claim
      results = Enum.map(pending_claims, fn claim ->
        process_single_claim(member, claim)
      end)

      # Filter successful claims
      successful_claims = Enum.filter(results, fn {status, _} -> status == :ok end)

      if length(successful_claims) > 0 do
        total_claimed = successful_claims
          |> Enum.map(fn {:ok, amount} -> amount end)
          |> Enum.sum()

        socket
        |> assign(:claimed_rewards, successful_claims)
        |> assign(:total_claimed, total_claimed)
        |> put_flash(:info, "Successfully claimed #{Float.round(total_claimed, 2)} BUX from #{length(successful_claims)} post(s)!")
      else
        socket
        |> assign(:claimed_rewards, [])
        |> assign(:total_claimed, 0)
      end
    else
      socket
      |> assign(:claimed_rewards, [])
      |> assign(:total_claimed, 0)
    end
  end

  # Process a single anonymous claim
  defp process_single_claim(user, claim) do
    post_id = case claim["postId"] do
      id when is_integer(id) -> id
      id when is_binary(id) -> String.to_integer(id)
    end

    claim_type = claim["type"]

    earned_amount = case claim["earnedAmount"] do
      amount when is_float(amount) -> amount
      amount when is_integer(amount) -> amount * 1.0
      amount when is_binary(amount) -> String.to_float(amount)
    end

    wallet_address = user.smart_wallet_address

    # Check if user already received reward for this post
    if already_rewarded?(user.id, post_id, claim_type) do
      {:error, "Already rewarded for this post"}
    else
      if wallet_address && wallet_address != "" do
        case claim_type do
          "read" ->
            # Mint BUX for reading
            case BuxMinter.mint_bux(wallet_address, earned_amount, user.id, post_id, :read, "BUX") do
              {:ok, %{"transactionHash" => _tx_hash}} ->
                # Record in Mnesia
                EngagementTracker.record_read_reward(user.id, post_id, earned_amount)
                # Deduct from pool
                EngagementTracker.deduct_from_pool_guaranteed(post_id, earned_amount)
                {:ok, earned_amount}

              {:error, reason} ->
                {:error, reason}
            end

          "video" ->
            # Mint BUX for video watching
            case BuxMinter.mint_bux(wallet_address, earned_amount, user.id, post_id, :video, "BUX") do
              {:ok, %{"transactionHash" => tx_hash}} ->
                # Get metrics from claim
                earnable_time = get_in(claim, ["metrics", "earnableTime"]) || 0

                # First ensure video engagement record exists
                EngagementTracker.record_video_view(user.id, post_id)

                # Then update with the session data
                EngagementTracker.update_video_engagement_session(user.id, post_id, %{
                  session_bux: earned_amount,
                  session_earnable_time: earnable_time,
                  tx_hash: tx_hash,
                  new_high_water_mark: earnable_time  # Use earnable time as HWM since we watched that much
                })

                {:ok, earned_amount}

              {:error, reason} ->
                {:error, reason}
            end

          _ ->
            {:error, "Unknown claim type"}
        end
      else
        {:error, "No wallet address"}
      end
    end
  end

  # Check if user already received a reward for this post
  defp already_rewarded?(user_id, post_id, claim_type) do
    case claim_type do
      "read" ->
        # Check user_post_rewards table
        case :mnesia.dirty_read({:user_post_rewards, {user_id, post_id}}) do
          [_record] -> true
          [] -> false
        end

      "video" ->
        # Check user_post_rewards table for video rewards
        case :mnesia.dirty_read({:user_post_rewards, {user_id, post_id}}) do
          [record] ->
            # Check if video_bux field has value (index 5)
            elem(record, 5) > 0

          [] ->
            false
        end

      _ ->
        false
    end
  end
end
