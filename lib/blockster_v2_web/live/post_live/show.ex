defmodule BlocksterV2Web.PostLive.Show do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Blog
  alias BlocksterV2.TimeTracker
  alias BlocksterV2.EngagementTracker
  alias BlocksterV2.BuxMinter
  alias BlocksterV2.Social
  alias BlocksterV2.Social.XConnection
  alias BlocksterV2.Shop
  alias BlocksterV2.ImageKit
  alias BlocksterV2Web.PostLive.TipTapRenderer
  alias BlocksterV2Web.SharedComponents

  # =============================================================================
  # Pool Display Helpers (Guaranteed Earnings System)
  # =============================================================================

  @doc """
  Returns pool balance for display purposes.
  Always returns 0 or positive - never shows negative to users.
  """
  defp display_pool_balance(pool_balance) when pool_balance <= 0, do: 0
  defp display_pool_balance(pool_balance), do: pool_balance

  @doc """
  Determines if pool is available for NEW earning actions.
  Returns false if pool is zero or negative.
  """
  defp pool_available_for_new_actions?(pool_balance), do: pool_balance > 0

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"slug" => slug} = _params, _url, socket) do
    post = Blog.get_post_by_slug!(slug)

    # Unsubscribe from previous post if navigating between posts
    if socket.assigns[:post] do
      EngagementTracker.unsubscribe_from_post_bux(socket.assigns.post.id)
    end

    # Subscribe to BUX updates for this post
    EngagementTracker.subscribe_to_post_bux(post.id)

    # Increment view count
    # {:ok, updated_post} = Blog.increment_view_count(post)

    # Add bux_balance from Mnesia
    updated_post = Blog.with_bux_balances(post)

    # Check pool availability (pool system - finite BUX pools)
    # Note: pool_balance can be negative internally, but we display max(0, balance)
    pool_balance_internal = EngagementTracker.get_post_bux_balance(post.id)
    pool_balance = display_pool_balance(pool_balance_internal)
    pool_available = pool_available_for_new_actions?(pool_balance_internal)

    # Always use "BUX" for rewards (hub tokens removed)
    hub_logo = get_hub_logo(updated_post)

    # Get existing time spent for this user on this post
    user_id = get_user_id(socket)
    time_spent = safe_get_time(user_id, post.id)

    # Calculate word count for engagement tracking
    word_count = EngagementTracker.count_words(post.content)

    # Get existing engagement data if any
    engagement = safe_get_engagement(user_id, post.id)

    # Get user multiplier for BUX calculation
    user_multiplier = safe_get_user_multiplier(user_id)

    # Get existing rewards for this post
    rewards = safe_get_rewards(user_id, post.id)

    # Check if user already received read reward for this post
    {bux_earned, already_rewarded, read_tx_id} =
      case rewards do
        %{read_bux: read_bux, read_tx_id: tx_id} when is_number(read_bux) and read_bux > 0 ->
          {read_bux, true, tx_id}
        %{read_bux: read_bux} when is_number(read_bux) and read_bux > 0 ->
          {read_bux, true, nil}
        _ ->
          {nil, false, nil}
      end

    # Get base BUX reward for panel display
    base_bux_reward = updated_post.base_bux_reward || 1

    # Initial score/BUX always starts at 1 for fresh sessions (unless already rewarded)
    # Score builds up as user engages with the article
    {current_score, current_bux} =
      if already_rewarded do
        # Already rewarded - show final earned values
        {engagement && engagement.engagement_score || 10, bux_earned}
      else
        # Fresh session - always start at 1
        {1, EngagementTracker.calculate_bux_earned(1, base_bux_reward, user_multiplier)}
      end

    # Load X connection and share campaign for logged-in users
    {x_connection, share_campaign, share_reward, x_share_reward} =
      case socket.assigns[:current_user] do
        nil ->
          {nil, nil, nil, nil}

        current_user ->
          x_conn = Social.get_x_connection_for_user(current_user.id)
          campaign = Social.get_campaign_for_post(post.id)
          # Only consider successful (verified/rewarded) shares - failed shares can be retried
          reward =
            if campaign do
              Social.get_successful_share_reward(current_user.id, campaign.post_id)
            end

          # Calculate personalized X share reward: x_multiplier * base_bux_reward
          x_multiplier = EngagementTracker.get_user_x_multiplier(current_user.id)
          calculated_reward = round(x_multiplier * base_bux_reward)

          {x_conn, campaign, reward, calculated_reward}
      end

    # Load suggested posts (highest BUX balance, excluding posts user has read)
    suggested_user_id = if socket.assigns[:current_user], do: socket.assigns.current_user.id, else: nil
    suggested_posts = Blog.get_suggested_posts(post.id, suggested_user_id, 4)

    # Load sidebar products (2 tees, 1 hat, 1 hoodie - shuffled) only on connected mount
    # Split into 2 for left sidebar and 2 for right sidebar
    {left_sidebar_products, right_sidebar_products} =
      if connected?(socket) do
        all_products = Shop.get_sidebar_products()
        {Enum.take(all_products, 2), Enum.drop(all_products, 2)}
      else
        {socket.assigns[:left_sidebar_products] || [], socket.assigns[:right_sidebar_products] || []}
      end

    # Anonymous user tracking assigns
    is_anonymous = socket.assigns[:current_user] == nil

    {:noreply,
     socket
     |> assign(:page_title, post.title)
     |> assign(:show_categories, true)
     |> assign(:post, updated_post)
     |> assign(:time_spent, time_spent)
     |> assign(:word_count, word_count)
     |> assign(:engagement, engagement)
     |> assign(:user_multiplier, user_multiplier)
     |> assign(:base_bux_reward, base_bux_reward)
     |> assign(:rewards, rewards)
     |> assign(:bux_earned, bux_earned)
     |> assign(:already_rewarded, already_rewarded)
     |> assign(:article_completed, already_rewarded)
     |> assign(:current_score, current_score)
     |> assign(:current_bux, current_bux)
     |> assign(:read_tx_id, read_tx_id)
     |> assign(:x_connection, x_connection)
     |> assign(:share_campaign, share_campaign)
     |> assign(:share_reward, share_reward)
     |> assign(:x_share_reward, x_share_reward)
     |> assign(:show_share_modal, false)
     |> assign(:share_status, nil)
     |> assign(:needs_x_reconnect, false)
     |> assign(:hub_token, "BUX")  # Always BUX (hub tokens removed)
     |> assign(:hub_logo, hub_logo)
     |> assign(:suggested_posts, suggested_posts)
     |> assign(:pool_available, pool_available)
     |> assign(:pool_balance, pool_balance)
     |> assign(:left_sidebar_products, left_sidebar_products)
     |> assign(:right_sidebar_products, right_sidebar_products)
     |> assign(:video_modal_open, false)
     |> assign(:is_anonymous, is_anonymous)
     |> assign(:show_signup_prompt, false)
     |> assign(:show_video_signup_prompt, false)
     |> assign(:anonymous_earned, 0)
     |> assign(:anonymous_video_earned, 0)
     |> assign(:engagement_score, nil)
     |> load_video_engagement()}
  end

  @impl true
  def handle_event("time_update", %{"seconds" => seconds}, socket) do
    user_id = get_user_id(socket)
    post_id = socket.assigns.post.id

    # Update the TimeTracker GenServer (fire and forget)
    # Client manages its own display incrementally - no need to push back
    # The initial time is loaded on page mount, JS adds to it locally
    TimeTracker.update_time(user_id, post_id, seconds)

    {:noreply, socket}
  end

  defp get_user_id(socket) do
    case socket.assigns[:current_user] do
      nil -> "anonymous"
      user -> user.id
    end
  end

  defp safe_get_time(user_id, post_id) do
    TimeTracker.get_time(user_id, post_id)
  catch
    :exit, _ -> 0
  end

  defp safe_get_engagement(user_id, post_id) do
    EngagementTracker.get_engagement_map(user_id, post_id)
  catch
    :exit, _ -> nil
  end

  defp safe_get_user_multiplier("anonymous"), do: 1
  defp safe_get_user_multiplier(user_id) do
    EngagementTracker.get_user_multiplier(user_id)
  catch
    :exit, _ -> 1
  end

  defp safe_get_rewards("anonymous", _post_id), do: nil
  defp safe_get_rewards(user_id, post_id) do
    EngagementTracker.get_rewards_map(user_id, post_id)
  catch
    :exit, _ -> nil
  end

  # Always return "BUX" (hub tokens removed)
  defp get_hub_token(_), do: "BUX"

  # Get the hub's logo URL (if any) for displaying alongside the token
  defp get_hub_logo(%{hub: %{logo_url: logo_url}}) when is_binary(logo_url) and logo_url != "", do: logo_url
  defp get_hub_logo(_), do: nil

  # Calculate engagement score from metrics (for anonymous users)
  # Same logic as EngagementTracker.calculate_engagement_score/9 but works with map params
  defp calculate_engagement_score(metrics) when is_map(metrics) do
    # JS sends snake_case keys (time_spent, not timeSpent)
    time_spent = Map.get(metrics, "time_spent", 0)
    min_read_time = Map.get(metrics, "min_read_time", 1)
    scroll_depth = Map.get(metrics, "scroll_depth", 0)
    reached_end = Map.get(metrics, "reached_end", false)

    # Base score starts at 1
    base_score = 1.0

    # Time ratio score (0-6 points)
    time_ratio = if min_read_time > 0, do: time_spent / min_read_time, else: 0
    time_score = cond do
      time_ratio >= 1.0 -> 6.0
      time_ratio >= 0.9 -> 5.0
      time_ratio >= 0.8 -> 4.0
      time_ratio >= 0.7 -> 3.0
      time_ratio >= 0.5 -> 2.0
      time_ratio >= 0.3 -> 1.0
      true -> 0.0
    end

    # Scroll depth score (0-3 points)
    depth_score = cond do
      reached_end || scroll_depth >= 100 -> 3.0
      scroll_depth >= 66 -> 2.0
      scroll_depth >= 33 -> 1.0
      true -> 0.0
    end

    # Calculate final score (min 1, max 10)
    final_score = base_score + time_score + depth_score
    min(max(final_score, 1.0), 10.0)
  end

  defp calculate_engagement_score(_), do: 1.0

  # Load existing video engagement for this user/post
  defp load_video_engagement(socket) do
    post = socket.assigns.post

    # Only load if post has a video
    if post.video_id do
      user_id = get_user_id(socket)
      video_duration = post.video_duration || 0
      video_duration_formatted = format_video_time(video_duration)

      if user_id != "anonymous" do
        case EngagementTracker.get_video_engagement(user_id, post.id) do
          {:ok, engagement} ->
            fully_watched = video_duration > 0 && engagement.high_water_mark >= video_duration

            socket
            |> assign(:video_high_water_mark, engagement.high_water_mark)
            |> assign(:video_total_bux_earned, engagement.total_bux_earned)
            |> assign(:video_completion_percentage, engagement.completion_percentage)
            |> assign(:video_fully_watched, fully_watched)
            |> assign(:video_tx_ids, engagement.video_tx_ids || [])
            |> assign(:video_duration_formatted, video_duration_formatted)

          {:error, :not_found} ->
            # No previous engagement - user starts fresh
            socket
            |> assign(:video_high_water_mark, 0.0)
            |> assign(:video_total_bux_earned, 0.0)
            |> assign(:video_completion_percentage, 0)
            |> assign(:video_fully_watched, false)
            |> assign(:video_tx_ids, [])
            |> assign(:video_duration_formatted, video_duration_formatted)
        end
      else
        # Anonymous user - no tracking
        socket
        |> assign(:video_high_water_mark, 0.0)
        |> assign(:video_total_bux_earned, 0.0)
        |> assign(:video_completion_percentage, 0)
        |> assign(:video_fully_watched, false)
        |> assign(:video_tx_ids, [])
        |> assign(:video_duration_formatted, video_duration_formatted)
      end
    else
      # No video on this post
      socket
      |> assign(:video_high_water_mark, 0.0)
      |> assign(:video_total_bux_earned, 0.0)
      |> assign(:video_completion_percentage, 0)
      |> assign(:video_fully_watched, false)
      |> assign(:video_tx_ids, [])
      |> assign(:video_duration_formatted, "0:00")
    end
  end

  # Format video duration in seconds to "M:SS" or "H:MM:SS" format
  defp format_video_time(seconds) when is_number(seconds) do
    seconds = trunc(seconds)
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)

    if hours > 0 do
      "#{hours}:#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
    else
      "#{minutes}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
    end
  end
  defp format_video_time(_), do: "0:00"

  @impl true
  def handle_event("article-visited", %{"min_read_time" => min_read_time} = _params, socket) do
    user_id = get_user_id(socket)
    post_id = socket.assigns.post.id

    # Only track for logged-in users
    if user_id != "anonymous" do
      EngagementTracker.record_visit(user_id, post_id, min_read_time)
      # Refresh engagement data
      engagement = safe_get_engagement(user_id, post_id)
      {:noreply, assign(socket, :engagement, engagement)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("engagement-update", params, socket) do
    user_id = get_user_id(socket)
    post_id = socket.assigns.post.id

    # Only track for logged-in users who haven't already been rewarded
    if user_id != "anonymous" and not socket.assigns.already_rewarded do
      case EngagementTracker.update_engagement(user_id, post_id, params) do
        {:ok, score} ->
          # Only update socket if score actually changed
          if score != socket.assigns.current_score do
            # Calculate current BUX value
            base_bux_reward = socket.assigns.post.base_bux_reward || 1
            user_multiplier = socket.assigns.user_multiplier || 1
            current_bux = EngagementTracker.calculate_bux_earned(score, base_bux_reward, user_multiplier)

            # Refresh engagement data
            engagement = safe_get_engagement(user_id, post_id)

            {:noreply,
             socket
             |> assign(:engagement, engagement)
             |> assign(:current_score, score)
             |> assign(:current_bux, current_bux)}
          else
            {:noreply, socket}
          end

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("article-read", params, socket) do
    user_id = get_user_id(socket)
    post_id = socket.assigns.post.id

    # Only track for logged-in users
    if user_id != "anonymous" do
      # First record the engagement data
      case EngagementTracker.record_read(user_id, post_id, params) do
        {:ok, score} ->
          # Calculate desired BUX earned
          base_bux_reward = socket.assigns.post.base_bux_reward || 1
          user_multiplier = socket.assigns.user_multiplier || 1
          desired_bux = EngagementTracker.calculate_bux_earned(score, base_bux_reward, user_multiplier)

          # GUARANTEED EARNINGS: No pool check at completion
          # Pool was checked when page loaded. If user started reading when pool was positive,
          # they are guaranteed the full reward. Pool can go negative to honor this commitment.

          cond do
            desired_bux <= 0 ->
              # No reward earned (score too low or already claimed)
              {:noreply,
               socket
               |> assign(:bux_earned, 0)
               |> assign(:current_bux, 0)
               |> assign(:article_completed, true)}

            true ->
              # GUARANTEED EARNINGS: Always pay full calculated amount
              actual_amount = desired_bux

              # Try to record reward and mint to user
              case EngagementTracker.record_read_reward(user_id, post_id, actual_amount) do
                {:ok, recorded_bux} ->
                  # New reward recorded - mint tokens
                  engagement = safe_get_engagement(user_id, post_id)
                  rewards = safe_get_rewards(user_id, post_id)

                  # Mint BUX tokens to user's smart wallet (async)
                  # Pool deduction happens AFTER successful mint
                  if socket.assigns[:current_user] do
                    wallet = socket.assigns.current_user.smart_wallet_address
                    if wallet && wallet != "" and recorded_bux > 0 do
                      lv_pid = self()
                      post_id_capture = post_id
                      Task.start(fn ->
                        case BuxMinter.mint_bux(wallet, recorded_bux, user_id, post_id_capture, :read) do
                          {:ok, %{"transactionHash" => tx_hash}} ->
                            # GUARANTEED EARNINGS: Deduct from pool (can go negative)
                            EngagementTracker.deduct_from_pool_guaranteed(post_id_capture, recorded_bux)
                            send(lv_pid, {:mint_completed, tx_hash})
                          _ ->
                            :ok
                        end
                      end)
                    end
                  end

                  # Get current pool balance for display (will be >= 0)
                  pool_balance_internal = EngagementTracker.get_post_bux_balance(post_id)

                  socket = socket
                    |> assign(:engagement, engagement)
                    |> assign(:rewards, rewards)
                    |> assign(:bux_earned, recorded_bux)
                    |> assign(:already_rewarded, false)
                    |> assign(:article_completed, true)
                    |> assign(:current_score, score)
                    |> assign(:current_bux, recorded_bux)
                    |> assign(:read_tx_id, nil)
                    |> assign(:pool_balance, display_pool_balance(pool_balance_internal))
                    |> assign(:pool_available, pool_available_for_new_actions?(pool_balance_internal))

                  {:noreply, socket}

                {:already_rewarded, existing_bux} ->
                  # User already received reward for this article
                  engagement = safe_get_engagement(user_id, post_id)
                  rewards = safe_get_rewards(user_id, post_id)
                  tx_id = rewards && Map.get(rewards, :read_tx_id)
                  {:noreply,
                   socket
                   |> assign(:engagement, engagement)
                   |> assign(:rewards, rewards)
                   |> assign(:bux_earned, existing_bux)
                   |> assign(:already_rewarded, true)
                   |> assign(:article_completed, true)
                   |> assign(:read_tx_id, tx_id)}

                {:error, _} ->
                  {:noreply, socket}
              end
          end

        {:error, _} ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Anonymous user engagement update - calculate but don't reward
  @impl true
  def handle_event("anonymous-engagement-update", params, socket) do
    if socket.assigns.is_anonymous && not socket.assigns.show_signup_prompt do
      # Calculate engagement score from metrics
      engagement_score = calculate_engagement_score(params)

      # Calculate BUX earned for anonymous users: 5 BUX per engagement point
      bux_earned = engagement_score * 5.0

      {:noreply,
       socket
       |> assign(:engagement_score, engagement_score)
       |> assign(:anonymous_earned, bux_earned)}
    else
      {:noreply, socket}
    end
  end

  # Show signup prompt when anonymous user completes article
  @impl true
  def handle_event("show-anonymous-claim", params, socket) do
    if socket.assigns.is_anonymous do
      # Calculate final engagement score and earned amount
      engagement_score = calculate_engagement_score(params["metrics"])
      bux_earned = engagement_score * 5.0

      {:noreply,
       socket
       |> assign(:show_signup_prompt, true)
       |> assign(:anonymous_earned, bux_earned)
       |> assign(:engagement_score, engagement_score)}
    else
      {:noreply, socket}
    end
  end

  # Show signup prompt when anonymous user watches video
  @impl true
  def handle_event("show-anonymous-video-claim", params, socket) do
    if socket.assigns.is_anonymous do
      # BUX earned already calculated by JS: (seconds / 60) * 15.0
      bux_earned = params["buxEarned"] || 0

      {:noreply,
       socket
       |> assign(:show_video_signup_prompt, true)
       |> assign(:anonymous_video_earned, bux_earned)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:mint_completed, tx_hash}, socket) do
    {:noreply, assign(socket, :read_tx_id, tx_hash)}
  end

  @impl true
  def handle_info({:bux_update, post_id, new_balance}, socket) do
    # Only update if this is for the current post
    # Note: new_balance from broadcast is already the display value (>= 0)
    # but we fetch internal to be consistent with pool_available logic
    if socket.assigns.post.id == post_id do
      internal_balance = EngagementTracker.get_post_bux_balance(post_id)
      display_balance = display_pool_balance(internal_balance)
      updated_post = Map.put(socket.assigns.post, :bux_balance, display_balance)
      {:noreply,
       socket
       |> assign(:post, updated_post)
       |> assign(:pool_balance, display_balance)
       |> assign(:pool_available, pool_available_for_new_actions?(internal_balance))}
    else
      {:noreply, socket}
    end
  end

  # ============================================
  # VIDEO WATCH REWARD EVENT HANDLERS
  # ============================================

  @impl true
  def handle_event("open_video_modal", _params, socket) do
    {:noreply, assign(socket, :video_modal_open, true)}
  end

  @impl true
  def handle_event("close_video_modal", _params, socket) do
    {:noreply, assign(socket, :video_modal_open, false)}
  end

  @impl true
  def handle_event("video-modal-opened", %{"post_id" => _post_id}, socket) do
    # Record video view start for logged-in users
    user_id = get_user_id(socket)

    if user_id != "anonymous" do
      post = socket.assigns.post
      video_duration = post.video_duration || 0
      EngagementTracker.record_video_view(user_id, post.id, video_duration)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("video-playing", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("video-paused", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("video-watch-update", params, socket) do
    # Periodic sync from JS (every 5 seconds)
    # We don't need to do anything server-side here since we handle everything in video-watch-complete
    # This is here for potential future analytics or state persistence
    _ = params
    {:noreply, socket}
  end

  @impl true
  def handle_event("video-watch-complete", params, socket) do
    %{
      "session_earnable_time" => session_earnable_time,
      "session_bux_earned" => client_session_bux,
      "session_max_position" => session_max_position,
      "previous_high_water_mark" => previous_hwm,
      "new_high_water_mark" => new_hwm,
      "video_duration" => video_duration,
      "completion_percentage" => completion,
      "pause_count" => pause_count,
      "tab_away_count" => tab_away_count
    } = params

    user_id = get_user_id(socket)
    post = socket.assigns.post

    cond do
      # Not logged in
      user_id == "anonymous" ->
        {:noreply,
         socket
         |> assign(:video_modal_open, false)
         |> put_flash(:info, "Log in to earn BUX for watching videos")}

      # No new territory watched (session_earnable_time <= 0)
      session_earnable_time <= 0 ->
        # Still update high water mark even if no BUX earned
        if new_hwm > previous_hwm do
          EngagementTracker.update_video_high_water_mark(user_id, post.id, new_hwm)
        end
        {:noreply, assign(socket, :video_modal_open, false)}

      # Video fully watched already
      socket.assigns.video_fully_watched ->
        {:noreply,
         socket
         |> assign(:video_modal_open, false)
         |> put_flash(:info, "You've watched the full video and earned all available BUX")}

      # Validate and mint for NEW territory
      true ->
        socket = mint_video_session_reward(socket, user_id, post, %{
          session_earnable_time: session_earnable_time,
          client_session_bux: client_session_bux,
          session_max_position: session_max_position,
          previous_high_water_mark: previous_hwm,
          new_high_water_mark: new_hwm,
          video_duration: video_duration,
          completion_percentage: completion,
          pause_count: pause_count,
          tab_away_count: tab_away_count
        })

        {:noreply, assign(socket, :video_modal_open, false)}
    end
  end

  # Server-side BUX calculation and minting for a VIDEO SESSION
  # Only mints BUX for NEW territory watched (beyond previous high water mark)
  defp mint_video_session_reward(socket, user_id, post, metrics) do
    bux_per_minute = Decimal.to_float(post.video_bux_per_minute || Decimal.new("1.0"))
    max_total_reward = post.video_max_reward && Decimal.to_float(post.video_max_reward)
    previous_total_earned = socket.assigns.video_total_bux_earned

    # Server-side validation: Calculate BUX for NEW territory only
    # session_earnable_time = seconds spent BEYOND previous high water mark
    server_calculated_bux = calculate_session_video_bux(
      metrics.session_earnable_time,
      bux_per_minute,
      max_total_reward,
      previous_total_earned
    )

    # Apply anti-gaming penalties
    final_session_bux = apply_video_penalties(server_calculated_bux, metrics)

    # GUARANTEED EARNINGS: No pool check at completion
    # Pool was checked when video modal opened. If user started watching when pool was positive,
    # they are guaranteed the full reward. Pool can go negative to honor this commitment.

    cond do
      final_session_bux <= 0 ->
        # Update high water mark even if no BUX earned (they watched new territory)
        EngagementTracker.update_video_engagement_session(user_id, post.id, %{
          new_high_water_mark: metrics.new_high_water_mark,
          session_bux: 0,
          session_earnable_time: metrics.session_earnable_time,
          pause_count: metrics.pause_count,
          tab_away_count: metrics.tab_away_count
        })
        put_flash(socket, :info, "Keep watching new content to earn BUX!")

      true ->
        # GUARANTEED EARNINGS: Always pay full calculated amount (no min with pool)
        actual_bux = final_session_bux

        # Mint the BUX for this session (async)
        current_user = socket.assigns[:current_user]
        wallet_address = current_user && current_user.smart_wallet_address
        new_total_earned = previous_total_earned + actual_bux
        video_duration = post.video_duration || 0
        fully_watched = video_duration > 0 && metrics.new_high_water_mark >= video_duration

        if wallet_address && wallet_address != "" and actual_bux > 0 do
          lv_pid = self()
          Task.start(fn ->
            case BuxMinter.mint_bux(wallet_address, actual_bux, user_id, post.id, :video_watch) do
              {:ok, %{"transactionHash" => tx_hash}} ->
                # Update video engagement with new high water mark and BUX earned
                EngagementTracker.update_video_engagement_session(user_id, post.id, %{
                  new_high_water_mark: metrics.new_high_water_mark,
                  session_bux: actual_bux,
                  session_earnable_time: metrics.session_earnable_time,
                  pause_count: metrics.pause_count,
                  tab_away_count: metrics.tab_away_count,
                  tx_hash: tx_hash
                })

                # GUARANTEED EARNINGS: Deduct from pool (can go negative)
                EngagementTracker.deduct_from_pool_guaranteed(post.id, trunc(actual_bux))

                # Send completion message back to LiveView
                send(lv_pid, {:video_mint_completed, tx_hash, actual_bux})

              {:error, reason} ->
                require Logger
                Logger.error("Failed to mint video reward: #{inspect(reason)}")
            end
          end)
        else
          # No wallet - just update engagement tracking
          EngagementTracker.update_video_engagement_session(user_id, post.id, %{
            new_high_water_mark: metrics.new_high_water_mark,
            session_bux: 0,
            session_earnable_time: metrics.session_earnable_time,
            pause_count: metrics.pause_count,
            tab_away_count: metrics.tab_away_count
          })
        end

        socket
        |> assign(:video_high_water_mark, metrics.new_high_water_mark)
        |> assign(:video_total_bux_earned, new_total_earned)
        |> assign(:video_completion_percentage, metrics.completion_percentage)
        |> assign(:video_fully_watched, fully_watched)
        |> put_flash(:success, "You earned +#{actual_bux} BUX for watching!")
    end
  end

  # Calculate BUX for SESSION (new territory only)
  defp calculate_session_video_bux(session_earnable_time, bux_per_minute, max_total_reward, previous_total_earned) do
    session_minutes = session_earnable_time / 60
    session_bux = session_minutes * bux_per_minute

    # Apply max total reward cap if set
    if max_total_reward do
      remaining_earnable = max_total_reward - previous_total_earned
      max(0, min(session_bux, remaining_earnable)) |> Float.round(1)
    else
      max(0, session_bux) |> Float.round(1)
    end
  end

  # Apply penalties for suspicious behavior in this session
  defp apply_video_penalties(bux, metrics) do
    penalty_multiplier = 1.0

    # Penalty for excessive pausing (potential gaming)
    penalty_multiplier = if metrics.pause_count > 10 do
      penalty_multiplier * 0.8  # 20% reduction
    else
      penalty_multiplier
    end

    # Penalty for excessive tab switching (potential gaming)
    penalty_multiplier = if metrics.tab_away_count > 5 do
      penalty_multiplier * 0.9  # 10% reduction
    else
      penalty_multiplier
    end

    Float.round(bux * penalty_multiplier, 1)
  end

  @impl true
  def handle_info({:video_mint_completed, tx_hash, bux_amount}, socket) do
    # Update pool balance after successful mint (display value, always >= 0)
    post_id = socket.assigns.post.id
    pool_balance_internal = EngagementTracker.get_post_bux_balance(post_id)

    # Append new tx to the list
    now = System.system_time(:second)
    new_tx = %{tx_hash: tx_hash, bux_amount: bux_amount, timestamp: now}
    updated_tx_ids = (socket.assigns[:video_tx_ids] || []) ++ [new_tx]

    {:noreply,
     socket
     |> assign(:video_tx_ids, updated_tx_ids)
     |> assign(:pool_balance, display_pool_balance(pool_balance_internal))
     |> assign(:pool_available, pool_available_for_new_actions?(pool_balance_internal))
     |> put_flash(:success, "Earned #{bux_amount} BUX! TX: #{String.slice(tx_hash, 0, 10)}...")}
  end

  @impl true
  def handle_event("publish", _params, socket) do
    {:ok, post} = Blog.publish_post(socket.assigns.post)

    {:noreply,
     socket
     |> put_flash(:info, "Post published successfully")
     |> assign(:post, post)}
  end

  @impl true
  def handle_event("unpublish", _params, socket) do
    {:ok, post} = Blog.unpublish_post(socket.assigns.post)

    {:noreply,
     socket
     |> put_flash(:info, "Post unpublished successfully")
     |> assign(:post, post)}
  end

  @impl true
  def handle_event("delete", _params, socket) do
    {:ok, _} = Blog.delete_post(socket.assigns.post)

    {:noreply, push_navigate(socket, to: ~p"/")}
  end

  @impl true
  def handle_event("open_share_modal", _params, socket) do
    x_connection = socket.assigns.x_connection

    # Check if X connection needs refresh when opening modal
    socket =
      if x_connection && XConnection.token_needs_refresh?(x_connection) do
        # Try to refresh the token
        case Social.maybe_refresh_token(x_connection) do
          {:ok, refreshed_connection} ->
            # Token refreshed successfully
            assign(socket, :x_connection, refreshed_connection)

          {:error, _reason} ->
            # Refresh failed - mark as needing reconnect and clear connection
            Social.disconnect_x_account(socket.assigns.current_user.id)

            socket
            |> assign(:x_connection, nil)
            |> assign(:needs_x_reconnect, true)
        end
      else
        socket
      end

    {:noreply, assign(socket, :show_share_modal, true)}
  end

  @impl true
  def handle_event("close_share_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_share_modal, false)
     |> assign(:share_status, nil)}
  end

  @impl true
  def handle_event("share_to_x", _params, socket) do
    user = socket.assigns.current_user
    x_connection = socket.assigns.x_connection
    share_campaign = socket.assigns.share_campaign

    cond do
      is_nil(user) ->
        {:noreply,
         socket
         |> assign(:share_status, {:error, "Please log in to share"})}

      is_nil(x_connection) ->
        {:noreply,
         socket
         |> assign(:share_status, {:error, "Please connect your X account first"})}

      is_nil(share_campaign) || !share_campaign.is_active ->
        # No active campaign, just open regular X share intent
        post = socket.assigns.post
        share_url = BlocksterV2Web.Endpoint.url() <> "/posts/#{post.slug}"
        share_text = URI.encode_www_form("#{post.title}")

        {:noreply,
         socket
         |> push_event("open_external_url", %{
           url: "https://twitter.com/intent/tweet?url=#{URI.encode_www_form(share_url)}&text=#{share_text}"
         })}

      socket.assigns.share_reward != nil ->
        # User already shared
        {:noreply,
         socket
         |> assign(:share_status, {:info, "You've already shared this article!"})}

      true ->
        # Active campaign - initiate tracked retweet
        initiate_tracked_share(socket, user, x_connection, share_campaign)
    end
  end

  defp initiate_tracked_share(socket, user, x_connection, share_campaign) do
    post = socket.assigns.post

    # Create pending reward (campaign_id is post_id in Mnesia, x_connection_id is user_id)
    case Social.create_pending_reward(user.id, post.id, user.id) do
      {:ok, _reward} ->
        # Refresh token if needed before making API call
        case Social.maybe_refresh_token(x_connection) do
          {:ok, refreshed_connection} ->
            # Get access token from the Mnesia map (already decrypted)
            access_token = refreshed_connection.access_token

            if access_token do
              # Retweet and like the campaign's specified tweet
              campaign_tweet_id = share_campaign.tweet_id
              x_user_id = refreshed_connection.x_user_id

              # Retweet and like the campaign tweet via API
              case Social.XApiClient.retweet_and_like(access_token, x_user_id, campaign_tweet_id) do
                {:ok, result} ->
                  # Check if at least the retweet succeeded
                  if result[:retweeted] do
                    # Verify and record the tweet (campaign_id is post.id)
                    case Social.verify_share_reward(user.id, post.id, campaign_tweet_id) do
                      {:ok, _verified_reward} ->
                        # GUARANTEED EARNINGS: Award full BUX amount
                        # Pool was checked when share modal opened. User is guaranteed full reward.
                        actual_bux = socket.assigns.x_share_reward

                        Social.increment_campaign_shares(share_campaign)

                        # Mint BUX tokens to user's wallet (synchronous to capture tx_hash)
                        wallet = user.smart_wallet_address
                        tx_hash =
                          if wallet && wallet != "" and actual_bux > 0 do
                            case BuxMinter.mint_bux(wallet, actual_bux, user.id, post.id, :x_share) do
                              {:ok, response} ->
                                # GUARANTEED EARNINGS: Deduct from pool (can go negative)
                                EngagementTracker.deduct_from_pool_guaranteed(post.id, actual_bux)
                                response["transactionHash"]
                              {:error, _} -> nil
                            end
                          else
                            nil
                          end

                        {:ok, final_reward} = Social.mark_rewarded(user.id, post.id, actual_bux, tx_hash: tx_hash, post_id: post.id)

                        # Update pool balance in assigns (display value, always >= 0)
                        new_pool_balance_internal = EngagementTracker.get_post_bux_balance(post.id)

                        # Build success message
                        success_msg = if result[:liked] do
                          "Retweeted & Liked! You earned #{actual_bux} BUX!"
                        else
                          "Retweeted! You earned #{actual_bux} BUX!"
                        end

                        {:noreply,
                         socket
                         |> assign(:share_reward, final_reward)
                         |> assign(:share_status, {:success, success_msg})
                         |> assign(:show_share_modal, false)
                         |> assign(:pool_balance, display_pool_balance(new_pool_balance_internal))
                         |> assign(:pool_available, pool_available_for_new_actions?(new_pool_balance_internal))}

                    {:error, _} ->
                      {:noreply,
                       socket
                       |> assign(:share_status, {:error, "Failed to verify share"})}
                  end
                  else
                    # Retweet failed even though API returned :ok
                    retweet_error = result[:retweet_error] || "Unknown error"
                    Social.delete_share_reward(user.id, post.id)

                    {:noreply,
                     socket
                     |> assign(:share_reward, nil)
                     |> assign(:share_status, {:error, "Failed to retweet: #{retweet_error}"})}
                  end

                {:error, :unauthorized} ->
                  # Token is invalid/expired - disconnect and prompt reconnection
                  Social.delete_share_reward(user.id, post.id)
                  Social.disconnect_x_account(user.id)

                  {:noreply,
                   socket
                   |> assign(:x_connection, nil)
                   |> assign(:share_reward, nil)
                   |> assign(:needs_x_reconnect, true)
                   |> assign(:share_status, {:error, "X session expired. Please reconnect your account."})}

                {:error, reason} ->
                  # Other errors - user can retry
                  Social.delete_share_reward(user.id, post.id)

                  {:noreply,
                   socket
                   |> assign(:share_reward, nil)
                   |> assign(:share_status, {:error, "Failed to post tweet: #{reason}"})}
              end
            else
              # Delete reward so user can retry after reconnecting
              Social.delete_share_reward(user.id, post.id)
              Social.disconnect_x_account(user.id)

              {:noreply,
               socket
               |> assign(:x_connection, nil)
               |> assign(:share_reward, nil)
               |> assign(:needs_x_reconnect, true)
               |> assign(:share_status, {:error, "Failed to authenticate with X. Please reconnect your account."})}
            end

          {:error, _reason} ->
            # Token refresh failed - delete the pending reward so user can retry after reconnecting
            Social.delete_share_reward(user.id, post.id)
            Social.disconnect_x_account(user.id)

            {:noreply,
             socket
             |> assign(:x_connection, nil)
             |> assign(:share_reward, nil)
             |> assign(:needs_x_reconnect, true)
             |> assign(:share_status, {:error, "X session expired. Please reconnect your account."})}
        end

      {:error, _changeset} ->
        {:noreply,
         socket
         |> assign(:share_status, {:error, "Failed to initiate share"})}
    end
  end

  # Handle TipTap format
  defp render_content(%{"type" => "doc"} = content) do
    TipTapRenderer.render_content(content)
  end

  # Fallback for empty or invalid content
  defp render_content(_), do: ""

  # Legacy Quill format handler (deprecated - kept for reference only)
  # All content should now be in TipTap format
  defp _render_legacy_quill_content(%{"ops" => ops}) when is_list(ops) do
    IO.puts("=== LEGACY QUILL FORMAT DETECTED ===")
    IO.inspect(ops, label: "OPS", limit: :infinity)

    html_parts =
      ops
      |> Enum.with_index()
      |> Enum.map(fn {op, index} ->
        next_op = Enum.at(ops, index + 1)
        result = render_single_op(op, next_op)
        IO.inspect({op, result}, label: "OP -> RESULT")
        result
      end)
      |> List.flatten()
      |> tap(fn parts -> IO.inspect(parts, label: "BEFORE REJECT", limit: :infinity) end)
      |> Enum.reject(fn x -> x == "" || x == nil end)
      |> tap(fn parts -> IO.inspect(parts, label: "AFTER REJECT", limit: :infinity) end)
      |> wrap_inline_paragraphs()
      |> Enum.join("\n")
      |> wrap_list_items() # Groups list items with formatted content

    Phoenix.HTML.raw(html_parts)
  end

  # Wrap consecutive inline text/formatted elements in paragraph tags
  defp wrap_inline_paragraphs(parts) do
    {result, current_para} = Enum.reduce(parts, {[], []}, fn part, {acc, para} ->
      cond do
        # If it's a block-level element (starts with known block tags), flush current paragraph
        String.starts_with?(part, ["<h1", "<h2", "<h3", "<h4", "<h5", "<h6", "<blockquote", "<ul", "<ol", "<div", "<img", "<p "]) ->
          if length(para) > 0 do
            # Wrap accumulated inline content in a paragraph
            wrapped = ~s(<p class="mt-4 mb-8 text-[#343434] leading-[1.6]">#{Enum.join(para, "")}</p>)
            {acc ++ [wrapped, part], []}
          else
            {acc ++ [part], []}
          end

        # Otherwise, accumulate inline content
        true ->
          {acc, para ++ [part]}
      end
    end)

    # Handle remaining accumulated inline content
    if length(current_para) > 0 do
      wrapped = ~s(<p class="mt-4 mb-8 text-[#343434] leading-[1.6]">#{Enum.join(current_para, "")}</p>)
      result ++ [wrapped]
    else
      result
    end
  end

  # Wrap consecutive list items in ul/ol tags and blockquote paragraphs in blockquote tags
  defp wrap_list_items(html) do
    html
    |> String.replace(
      ~r/<li class="[^"]*list-item-ordered">.*?<\/li>/s,
      fn match ->
        # Check if already wrapped
        if String.contains?(match, "<ol") do
          match
        else
          match
        end
      end
    )
    # Wrap bullet list items
    |> String.replace(
      ~r/(<li class="[^"]*list-item-bullet">.*?<\/li>)+/s,
      fn matches ->
        ~s(<ul class="list-disc pl-6 mb-4">#{matches}</ul>)
      end
    )
    # Wrap ordered list items
    |> String.replace(
      ~r/(<li class="[^"]*list-item-ordered">.*?<\/li>)+/s,
      fn matches ->
        ~s(<ol class="list-decimal pl-6 mb-4">#{matches}</ol>)
      end
    )
    # Wrap consecutive blockquote paragraphs in a single blockquote
    |> wrap_blockquotes()
  end

  # Wrap consecutive blockquote-line paragraphs
  defp wrap_blockquotes(html) do
    IO.puts("=== WRAP_BLOCKQUOTES CALLED ===")
    IO.inspect(String.contains?(html, "blockquote-line"), label: "Contains blockquote-line?")

    # Split HTML into lines and process sequentially
    lines = String.split(html, "\n")
    IO.inspect(length(lines), label: "Number of lines")

    {result, current_group} = Enum.reduce(lines, {[], []}, fn line, {acc, group} ->
      cond do
        # If line contains blockquote-line opening tag
        String.contains?(line, ~s(<p class="blockquote-line">)) ->
          {acc, [line | group]}

        # If we have accumulated blockquote lines and this isn't one, wrap them
        length(group) > 0 and not String.contains?(line, "blockquote-line") ->
          # Process the group - mark last paragraph as attribution
          reversed_group = Enum.reverse(group)
          cleaned_lines = reversed_group
          |> Enum.with_index()
          |> Enum.map(fn {l, idx} ->
            # Last item gets attribution class
            if idx == length(reversed_group) - 1 do
              String.replace(l, ~s(<p class="blockquote-line">), ~s(<p class="blockquote-attribution">))
            else
              String.replace(l, ~s(<p class="blockquote-line">), "<p>")
            end
          end)
          wrapped = ~s(<blockquote class="mt-4 mb-8">#{Enum.join(cleaned_lines, "\n")}</blockquote>)
          {acc ++ [wrapped, line], []}

        # Otherwise just accumulate
        true ->
          {acc ++ [line], group}
      end
    end)

    # Handle remaining group at end
    final_result = if length(current_group) > 0 do
      # Process the group - mark last paragraph as attribution
      reversed_group = Enum.reverse(current_group)
      cleaned_lines = reversed_group
      |> Enum.with_index()
      |> Enum.map(fn {l, idx} ->
        # Last item gets attribution class
        if idx == length(reversed_group) - 1 do
          String.replace(l, ~s(<p class="blockquote-line">), ~s(<p class="blockquote-attribution">))
        else
          String.replace(l, ~s(<p class="blockquote-line">), "<p>")
        end
      end)
      wrapped = ~s(<blockquote class="mt-4 mb-8">#{Enum.join(cleaned_lines, "\n")}</blockquote>)
      result ++ [wrapped]
    else
      result
    end

    Enum.join(final_result, "\n")
  end


  # Handle text that will be followed by a header newline
  defp render_single_op(
         %{"insert" => text},
         %{"insert" => "\n", "attributes" => %{"header" => level}}
       )
       when is_binary(text) do
    # Split the text by newlines
    lines = String.split(text, "\n")

    # All lines except the last are regular paragraphs
    paragraph_lines = Enum.drop(lines, -1)

    # The last line is the header text
    header_text = List.last(lines) |> String.trim()

    # Render paragraphs first (only non-empty ones)
    paragraphs =
      paragraph_lines
      |> Enum.map(fn para ->
        trimmed = String.trim(para)

        if trimmed != "" do
          ~s(<p class="mb-4 text-[#343434] leading-[1.6]">#{trimmed}</p>)
        else
          # Skip empty lines, margins provide spacing
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Render header with proper HTML tag and size
    size_class =
      case level do
        1 -> "text-4xl font-bold"
        2 -> "text-3xl font-bold"
        _ -> "text-2xl font-bold"
      end

    # Add mt-4 mb-8 spacing for h1 and h2 tags
    spacing_class =
      case level do
        1 -> "mt-4 mb-8"
        2 -> "mt-4 mb-8"
        _ -> "mb-4"
      end

    header_tag = "h#{level}"

    header_html =
      ~s(<#{header_tag} class="#{spacing_class} text-[#343434] leading-[1.2] #{size_class}">#{header_text}</#{header_tag}>)

    # Return paragraphs followed by header
    paragraphs ++ [header_html]
  end

  # Handle header newlines - just skip them, margins handle spacing
  defp render_single_op(%{"insert" => text, "attributes" => %{"header" => _}}, _next_op) when is_binary(text) do
    # Check if the text is ONLY newlines (no actual text content)
    if String.trim(text) == "" do
      # Skip newline-only header operations, margins provide spacing
      nil
    else
      # Has actual text content, should be handled by the header+text handler above
      nil
    end
  end

  # Handle blockquote text - mark it as blockquote paragraph, wrapping happens later
  defp render_single_op(
         %{"insert" => text},
         %{"insert" => "\n", "attributes" => %{"blockquote" => true}}
       )
       when is_binary(text) do
    IO.inspect(text, label: "BLOCKQUOTE TEXT")

    # Check if text contains a double newline (paragraph separator)
    # If so, only render paragraphs AFTER the first double newline as blockquote
    # This handles Quill's behavior of including preceding text in blockquote
    result = if String.contains?(text, "\n\n") do
      # Split by double newline to separate paragraphs
      paragraphs = String.split(text, "\n\n")
      IO.inspect(paragraphs, label: "SPLIT PARAGRAPHS")

      # First paragraph(s) before the last one should be rendered as normal text
      # Only the last paragraph(s) should be blockquoted
      {non_blockquote_parts, blockquote_parts} = Enum.split(paragraphs, -1)

      # Render non-blockquote parts as regular paragraphs (skip empty ones)
      regular_html = non_blockquote_parts
      |> Enum.map(fn para ->
        trimmed = String.trim(para)
        if trimmed != "" do
          ~s(<p>#{trimmed}</p>)
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

      # Render blockquote parts with blockquote-line class (skip empty lines)
      blockquote_html = blockquote_parts
      |> Enum.flat_map(fn para -> String.split(para, "\n") end)
      |> Enum.map(fn line ->
        trimmed = String.trim(line)
        if trimmed != "" do
          ~s(<p class="blockquote-line">#{trimmed}</p>)
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

      # Combine regular and blockquote HTML
      [regular_html, blockquote_html]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
    else
      # No double newline - render all as blockquote (skip empty lines)
      lines = String.split(text, "\n")

      lines
      |> Enum.map(fn line ->
        trimmed = String.trim(line)
        if trimmed != "" do
          ~s(<p class="blockquote-line">#{trimmed}</p>)
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")
    end

    IO.inspect(result, label: "BLOCKQUOTE RESULT")
    result
  end

  # Detect if a line is an attribution (e.g., "John Doe, CEO at Company")
  defp is_attribution?(text) do
    # Pattern: Name, Title at Company or Name, Title
    # Look for patterns like ", CEO at", ", CTO at", etc.
    String.match?(text, ~r/^[^,]+,\s+[A-Z][^,]+ at .+$/) or
    # Also match simpler pattern: just "Name, Position"
    String.match?(text, ~r/^[^,]+,\s+[A-Z][^,]+$/)
  end

  # Skip blockquote newlines (they're processed above)
  defp render_single_op(%{"insert" => "\n", "attributes" => %{"blockquote" => true}}, _next_op) do
    nil
  end

  # Handle list item text (ordered or bullet)
  defp render_single_op(
         %{"insert" => text},
         %{"insert" => "\n", "attributes" => %{"list" => list_type}}
       )
       when is_binary(text) do
    trimmed = String.trim(text)

    if trimmed != "" do
      ~s(<li class="mb-2 text-[#343434] leading-[1.6] list-item-#{list_type}">#{trimmed}</li>)
    else
      ""
    end
  end

  # Skip list newlines (they're processed above)
  defp render_single_op(%{"insert" => "\n", "attributes" => %{"list" => _}}, _next_op) do
    nil
  end

  # Handle text with inline formatting attributes (bold, italic, underline, strike, link)
  # This MUST come before the plain text handler to match more specific patterns first
  defp render_single_op(%{"insert" => text, "attributes" => attrs}, _next_op)
       when is_binary(text) and is_map(attrs) do
    # Don't process if this is a block-level attribute (header, blockquote, list)
    # Those are handled by their specific handlers above
    if Map.has_key?(attrs, "header") or Map.has_key?(attrs, "blockquote") or
         Map.has_key?(attrs, "list") do
      nil
    else
      # Just apply inline formatting without wrapping in <p> tags
      # The wrapping happens later when we join ops together
      content = text

      content =
        if attrs["bold"] do
          ~s(<strong>#{content}</strong>)
        else
          content
        end

      content =
        if attrs["italic"] do
          ~s(<em>#{content}</em>)
        else
          content
        end

      content =
        if attrs["underline"] do
          ~s(<u>#{content}</u>)
        else
          content
        end

      content =
        if attrs["strike"] do
          ~s(<s>#{content}</s>)
        else
          content
        end

      content =
        if attrs["link"] do
          url = attrs["link"]
          ~s(<a href="#{url}" target="_blank" rel="noopener noreferrer" class="text-blue-600 hover:underline">#{content}</a>)
        else
          content
        end

      content
    end
  end

  # Handle regular text without any formatting
  defp render_single_op(%{"insert" => text}, _next_op) when is_binary(text) do
    # Split by double newlines (paragraph breaks) to preserve paragraph structure
    # Single newlines within paragraphs are ignored
    text
    |> String.split("\n\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(fn para ->
      # Reject empty strings and separator-only strings like "--"
      para == "" || String.match?(para, ~r/^[-\s]+$/)
    end)
    |> Enum.map(fn para ->
      ~s(<p class="mt-4 mb-8 text-[#343434] leading-[1.6]">#{para}</p>)
    end)
  end

  # Handle images
  defp render_single_op(%{"insert" => %{"image" => url}}, _next_op) do
    ~s(<img src="#{url}" class="max-w-full h-auto rounded-lg my-4" />)
  end

  # Handle spacer embeds
  defp render_single_op(%{"insert" => %{"spacer" => _}}, _next_op) do
    ~s(<div class="text-left text-[#343434] my-4 text-2xl">--</div>)
  end

  # Handle tweet embeds with embedded HTML
  defp render_single_op(%{"insert" => %{"tweet" => %{"html" => html}}}, _next_op) do
    ~s{<div class="my-6">#{html}<script async src="https://platform.twitter.com/widgets.js" charset="utf-8"></script></div>}
  end

  # Handle tweet embeds using Twitter's oEmbed API (legacy format with URL)
  defp render_single_op(%{"insert" => %{"tweet" => %{"url" => url}}}, _next_op) do
    # Fetch tweet HTML from Twitter's oEmbed API
    case fetch_tweet_embed(url) do
      {:ok, html} ->
        # Wrap in container for styling
        ~s(<div class="my-6">#{html}</div>)

      {:error, _reason} ->
        # Fallback to simple link if oEmbed fails
        ~s(<p class="my-4"><a href="#{url}" target="_blank" rel="noopener noreferrer" class="text-blue-600 hover:underline">View Tweet on Twitter</a></p>)
    end
  end

  # Handle tweet embeds with just a URL string (backward compatibility)
  defp render_single_op(%{"insert" => %{"tweet" => url}}, _next_op) when is_binary(url) do
    # Fetch tweet HTML from Twitter's oEmbed API
    case fetch_tweet_embed(url) do
      {:ok, html} ->
        # Wrap in container for styling
        ~s(<div class="my-6">#{html}</div>)

      {:error, _reason} ->
        # Fallback to simple link if oEmbed fails
        ~s(<p class="my-4"><a href="#{url}" target="_blank" rel="noopener noreferrer" class="text-blue-600 hover:underline">View Tweet on Twitter</a></p>)
    end
  end

  # Handle plain newlines (blank lines) - just skip them, margins handle spacing
  defp render_single_op(%{"insert" => "\n"}, _next_op) do
    nil
  end

  # Catch-all for unknown ops
  defp render_single_op(_op, _next_op), do: nil

  # Fetch tweet embed HTML from Twitter's oEmbed API
  defp fetch_tweet_embed(url) do
    # Twitter's oEmbed endpoint
    oembed_url =
      "https://publish.twitter.com/oembed?url=#{URI.encode_www_form(url)}&theme=light&dnt=true"

    case Req.get(oembed_url) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        # Extract HTML from oEmbed response
        case Map.get(body, "html") do
          html when is_binary(html) ->
            {:ok, html}

          _ ->
            {:error, :invalid_response}
        end

      {:ok, %{status: status}} ->
        {:error, {:http_error, status}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      {:error, error}
  end

  # Helper functions for engagement display

  defp format_time(seconds) when is_integer(seconds) do
    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3600 ->
        mins = div(seconds, 60)
        secs = rem(seconds, 60)
        "#{mins}m #{secs}s"
      true ->
        hours = div(seconds, 3600)
        mins = div(rem(seconds, 3600), 60)
        "#{hours}h #{mins}m"
    end
  end
  defp format_time(_), do: "0s"

  defp engagement_score_color(score) when is_integer(score) do
    cond do
      score >= 8 -> "bg-green-100 text-green-800 border-2 border-green-300"
      score >= 6 -> "bg-blue-100 text-blue-800 border-2 border-blue-300"
      score >= 4 -> "bg-yellow-100 text-yellow-800 border-2 border-yellow-300"
      true -> "bg-red-100 text-red-800 border-2 border-red-300"
    end
  end
  defp engagement_score_color(_), do: "bg-gray-100 text-gray-800 border-2 border-gray-300"

  defp engagement_score_label(score) when is_integer(score) do
    cond do
      score >= 9 -> "Excellent Reader"
      score >= 7 -> "Good Reader"
      score >= 5 -> "Moderate Engagement"
      score >= 3 -> "Light Skimmer"
      true -> "Quick Glance"
    end
  end
  defp engagement_score_label(_), do: "Not Rated"
end
