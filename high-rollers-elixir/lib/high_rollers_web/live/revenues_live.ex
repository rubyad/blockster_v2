defmodule HighRollersWeb.RevenuesLive do
  @moduledoc """
  LiveView for My Earnings / Revenue sharing statistics.

  Shows:
  - User's NFT earnings (when wallet connected)
  - Special NFTs time rewards (when user has special NFTs 2340-2700)
  - Per-NFT earnings table
  - Recent reward events (payout history)
  - Withdrawal functionality

  Real-time updates via PubSub - no polling needed.

  HTML structure matches exactly: high-rollers-nfts/public/index.html lines 390-527
  """
  use HighRollersWeb, :live_view
  require Logger

  @special_nft_start 2340
  @special_nft_end 2700

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(HighRollers.PubSub, "reward_events")
      Phoenix.PubSub.subscribe(HighRollers.PubSub, "earnings_events")
      Phoenix.PubSub.subscribe(HighRollers.PubSub, "price_events")
    end

    # Get ROGUE price and NFT value for APY calculations
    rogue_price = get_rogue_price()
    nft_value_rogue = get_nft_value_rogue()

    # Load recent reward events (payout history)
    reward_events = HighRollers.Rewards.get_events(50)

    socket =
      socket
      |> assign(:rogue_price, rogue_price)
      |> assign(:nft_value_rogue, nft_value_rogue)
      |> assign(:reward_events, reward_events)
      |> assign(:reward_events_loading, false)
      |> assign(:user_earnings, nil)
      |> assign(:special_nfts_stats, nil)
      |> assign(:withdrawing, false)
      |> assign(:withdraw_error, nil)
      |> assign(:withdraw_tx_hashes, nil)
      |> assign(:current_path, "/revenues")
      |> HighRollersWeb.WalletHook.set_page_chain("rogue")

    # If wallet already connected, load user earnings
    socket =
      if socket.assigns[:wallet_connected] && socket.assigns[:wallet_address] do
        load_user_data(socket, socket.assigns.wallet_address)
      else
        socket
      end

    {:ok, socket}
  end

  # ===== WALLET EVENTS =====
  # WalletHook sets :wallet_connected and :wallet_address via attach_hook
  # This handle_event is for page-specific logic

  @impl true
  def handle_event("request_wallet_connect", _params, socket) do
    # Push event to JavaScript to trigger wallet connection
    {:noreply, push_event(socket, "open_wallet_modal", %{})}
  end

  @impl true
  def handle_event("wallet_connected", %{"address" => address}, socket) do
    socket = load_user_data(socket, String.downcase(address))
    {:noreply, socket}
  end

  @impl true
  def handle_event("wallet_disconnected", _params, socket) do
    {:noreply,
     socket
     |> assign(:user_earnings, nil)
     |> assign(:special_nfts_stats, nil)}
  end

  @impl true
  def handle_event("balance_updated", _params, socket) do
    # Ignore balance updates - not needed on this page
    {:noreply, socket}
  end

  # ===== WITHDRAWAL =====

  @impl true
  def handle_event("withdraw", _params, socket) do
    wallet_address = socket.assigns[:wallet_address]

    if is_nil(wallet_address) do
      {:noreply, assign(socket, :withdraw_error, "Wallet not connected")}
    else
      # Start withdrawal in background
      socket = socket
      |> assign(:withdrawing, true)
      |> assign(:withdraw_error, nil)
      |> assign(:withdraw_tx_hashes, nil)

      # Send to self so we can track completion
      parent = self()
      Task.start(fn ->
        result = perform_withdrawal(wallet_address)
        send(parent, {:withdrawal_complete, result})
      end)

      {:noreply, socket}
    end
  end

  # ===== REAL-TIME UPDATES =====

  @impl true
  def handle_info({:withdrawal_complete, {:ok, tx_hashes}}, socket) do
    # Refresh user earnings after withdrawal
    socket =
      if socket.assigns[:wallet_address] do
        load_user_data(socket, socket.assigns.wallet_address)
      else
        socket
      end

    {:noreply,
     socket
     |> assign(:withdrawing, false)
     |> assign(:withdraw_tx_hashes, tx_hashes)
     |> push_event("refresh_balance", %{})}  # Trigger JS to refresh wallet balance
  end

  @impl true
  def handle_info({:withdrawal_complete, {:error, reason}}, socket) do
    {:noreply,
     socket
     |> assign(:withdrawing, false)
     |> assign(:withdraw_error, to_string(reason))}
  end

  @impl true
  def handle_info({:reward_received, event}, socket) do
    # Prepend new reward event to list
    reward_events = [event_to_display_map(event) | socket.assigns.reward_events]
    |> Enum.take(50)

    # Update user earnings optimistically if connected
    socket =
      if socket.assigns.user_earnings && socket.assigns[:wallet_address] do
        update_user_earnings_optimistically(socket, event.amount)
      else
        socket
      end

    {:noreply, assign(socket, :reward_events, reward_events)}
  end

  @impl true
  def handle_info({:earnings_synced, _stats}, socket) do
    # Full refresh from sync
    socket =
      if socket.assigns[:wallet_address] do
        load_user_data(socket, socket.assigns.wallet_address)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:price_update, %{rogue: rogue_price}}, socket) do
    # Recalculate NFT value when price changes
    nft_value_rogue = get_nft_value_rogue()
    {:noreply,
     socket
     |> assign(:rogue_price, rogue_price)
     |> assign(:nft_value_rogue, nft_value_rogue)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ===== PRIVATE FUNCTIONS =====

  defp load_user_data(socket, wallet_address) do
    user_earnings = load_user_earnings(wallet_address)
    special_nfts_stats = calculate_special_nfts_stats(user_earnings.nfts)

    socket
    |> assign(:user_earnings, user_earnings)
    |> assign(:special_nfts_stats, special_nfts_stats)
  end

  defp load_user_earnings(address) do
    nfts = HighRollers.NFTStore.get_by_owner(address)

    # Enrich NFTs with earnings and time rewards
    nft_earnings =
      Enum.map(nfts, fn nft ->
        # Add time reward info for special NFTs
        time_reward =
          if special_nft?(nft.token_id) do
            HighRollers.TimeRewards.get_nft_time_info(nft.token_id)
          else
            nil
          end

        Map.put(nft, :time_reward, time_reward)
      end)
      |> Enum.sort_by(& &1.token_id, :desc)

    # Aggregate totals for revenue sharing
    total_pending = sum_wei(nft_earnings, :pending_amount)
    total_earned = sum_wei(nft_earnings, :total_earned)
    total_24h = sum_wei(nft_earnings, :last_24h_earned)

    # Check for time rewards pending (special NFTs)
    has_time_rewards_pending =
      Enum.any?(nft_earnings, fn nft ->
        nft.time_reward && (nft.time_reward[:pending] || 0) > 0
      end)

    %{
      address: address,
      nfts: nft_earnings,
      nft_count: length(nft_earnings),
      total_pending: total_pending,
      total_earned: total_earned,
      total_24h: total_24h,
      can_withdraw: String.to_integer(total_pending) > 0 || has_time_rewards_pending
    }
  end

  defp calculate_special_nfts_stats(nfts) do
    special_nfts = Enum.filter(nfts, fn nft ->
      special_nft?(nft.token_id) && nft.time_reward && nft.time_reward.has_started
    end)

    if length(special_nfts) == 0 do
      nil
    else
      now = System.system_time(:second)

      # Sum up time reward stats
      total_time_earned = Enum.reduce(special_nfts, 0.0, fn nft, acc ->
        acc + (nft.time_reward.total_earned || 0)
      end)

      total_time_pending = Enum.reduce(special_nfts, 0.0, fn nft, acc ->
        acc + (nft.time_reward.pending || 0)
      end)

      total_time_24h = Enum.reduce(special_nfts, 0.0, fn nft, acc ->
        acc + (nft.time_reward.last_24h || 0)
      end)

      total_180d = Enum.reduce(special_nfts, 0.0, fn nft, acc ->
        acc + (nft.time_reward.total_for_180_days || 0)
      end)

      # Sum of all rates for live counting in JS
      total_rate_per_second = Enum.reduce(special_nfts, 0.0, fn nft, acc ->
        acc + (nft.time_reward.rate_per_second || 0)
      end)

      # Calculate average APY based on 180d total earnings
      # APY = (total_for_180_days × 365/180) / nft_value × 100
      # NFT value calculated from live ETH/ROGUE prices (0.32 ETH mint price)
      nft_value_rogue = get_nft_value_rogue()
      avg_apy = if length(special_nfts) > 0 and total_180d > 0 and nft_value_rogue > 0 do
        avg_180d_per_nft = total_180d / length(special_nfts)
        annualized = avg_180d_per_nft * 365 / 180
        Float.round(annualized / nft_value_rogue * 100, 1)
      else
        0
      end

      %{
        count: length(special_nfts),
        total_earned: total_time_earned,
        total_pending: total_time_pending,
        total_24h: total_time_24h,
        total_180d: total_180d,
        apy: avg_apy,
        # For JS live counting
        total_rate_per_second: total_rate_per_second,
        base_time: now
      }
    end
  end

  defp special_nft?(token_id), do: token_id >= @special_nft_start and token_id <= @special_nft_end

  defp perform_withdrawal(address) do
    user_nfts = HighRollers.NFTStore.get_by_owner(address)
    tx_hashes = []

    # 1. Revenue sharing withdrawal
    token_ids_with_pending =
      user_nfts
      |> Enum.filter(fn nft ->
        String.to_integer(nft.pending_amount || "0") > 0
      end)
      |> Enum.map(& &1.token_id)

    tx_hashes =
      if length(token_ids_with_pending) > 0 do
        case HighRollers.AdminTxQueue.withdraw_to(token_ids_with_pending, address) do
          {:ok, receipt} ->
            # Clear pending amounts in Mnesia after successful withdrawal
            for token_id <- token_ids_with_pending do
              HighRollers.NFTStore.update_earnings(token_id, %{pending_amount: "0"})
            end
            [receipt.tx_hash]
          {:error, _} -> []
        end
      else
        []
      end

    # 2. Time-based rewards withdrawal (special NFTs 2340-2700)
    special_token_ids_with_pending =
      user_nfts
      |> Enum.filter(fn nft -> special_nft?(nft.token_id) end)
      |> Enum.filter(fn nft ->
        time_info = HighRollers.TimeRewards.get_nft_time_info(nft.token_id)
        (time_info[:pending] || 0) > 0
      end)
      |> Enum.map(& &1.token_id)

    {tx_hashes, time_error} =
      if length(special_token_ids_with_pending) > 0 do
        case HighRollers.AdminTxQueue.claim_time_rewards(special_token_ids_with_pending, address) do
          {:ok, receipt} ->
            # Record time claims in Mnesia - sets last_claim to now, clears pending
            for token_id <- special_token_ids_with_pending do
              HighRollers.TimeRewards.record_claim(token_id)
            end
            {tx_hashes ++ [receipt.tx_hash], nil}
          {:error, reason} -> {tx_hashes, reason}
        end
      else
        {tx_hashes, nil}
      end

    cond do
      length(tx_hashes) > 0 -> {:ok, tx_hashes}
      time_error != nil -> {:error, "Time rewards claim failed: #{inspect(time_error)}"}
      true -> {:error, "No pending rewards to withdraw"}
    end
  end

  @multipliers [100, 90, 80, 70, 60, 50, 40, 30]  # Hostess index 0-7

  defp update_user_earnings_optimistically(socket, reward_amount_str) do
    reward_amount = String.to_integer(reward_amount_str)
    user_earnings = socket.assigns.user_earnings
    total_points = HighRollers.NFTStore.get_total_multiplier_points()

    # Update each NFT's earnings proportionally - calculate new values
    updated_nfts =
      Enum.map(user_earnings.nfts, fn nft ->
        multiplier = Enum.at(@multipliers, nft.hostess_index, 30)
        nft_share = div(reward_amount * multiplier, total_points)

        new_pending = add_wei(nft.pending_amount, Integer.to_string(nft_share))
        new_total = add_wei(nft.total_earned, Integer.to_string(nft_share))
        new_24h = add_wei(nft.last_24h_earned, Integer.to_string(nft_share))

        nft
        |> Map.put(:pending_amount, new_pending)
        |> Map.put(:total_earned, new_total)
        |> Map.put(:last_24h_earned, new_24h)
      end)

    # Update Mnesia asynchronously so EarningsSyncer reload gets correct values
    # This prevents the race condition where earnings_synced reverts the optimistic update
    Task.start(fn ->
      Enum.each(updated_nfts, fn nft ->
        HighRollers.NFTStore.update_earnings(nft.token_id, %{
          pending_amount: nft.pending_amount,
          total_earned: nft.total_earned,
          last_24h_earned: nft.last_24h_earned
        })
      end)
    end)

    # Recalculate aggregates
    total_pending = sum_wei(updated_nfts, :pending_amount)
    total_earned = sum_wei(updated_nfts, :total_earned)
    total_24h = sum_wei(updated_nfts, :last_24h_earned)

    updated_user_earnings = %{
      user_earnings |
      nfts: updated_nfts,
      total_pending: total_pending,
      total_earned: total_earned,
      total_24h: total_24h,
      can_withdraw: String.to_integer(total_pending) > 0
    }

    assign(socket, :user_earnings, updated_user_earnings)
  end

  defp add_wei(a, b) do
    Integer.to_string(String.to_integer(a || "0") + String.to_integer(b || "0"))
  end

  defp sum_wei(list, key) do
    Enum.reduce(list, 0, fn item, acc ->
      acc + String.to_integer(Map.get(item, key) || "0")
    end)
    |> Integer.to_string()
  end

  defp event_to_display_map(event) when is_map(event), do: event
  defp event_to_display_map(_), do: %{}

  # Prices are fetched from PriceCache (Mnesia) - no blocking API calls
  defp get_rogue_price, do: HighRollers.PriceCache.get_rogue_price()
  defp get_eth_price, do: HighRollers.PriceCache.get_eth_price()

  @doc "Calculate NFT value in ROGUE based on 0.32 ETH mint price and current prices"
  def get_nft_value_rogue, do: HighRollers.PriceCache.get_nft_value_rogue()

  # ===== VIEW HELPERS =====

  def format_rogue(nil), do: "0"
  def format_rogue("0"), do: "0"
  def format_rogue(wei) when is_binary(wei), do: format_rogue(String.to_integer(wei))
  def format_rogue(wei) when is_integer(wei) do
    rogue = wei / 1.0e18
    format_number(rogue)
  end

  def format_usd(nil, _price), do: "$0.00"
  def format_usd("0", _price), do: "$0.00"
  def format_usd(wei, rogue_price) when is_binary(wei), do: format_usd(String.to_integer(wei), rogue_price)
  def format_usd(wei, rogue_price) when is_integer(wei) and is_number(rogue_price) do
    rogue = wei / 1.0e18
    usd = rogue * rogue_price
    "$#{:erlang.float_to_binary(usd, decimals: 2)}"
  end
  def format_usd(_, _), do: "$0.00"

  def format_usd_from_rogue(nil, _price), do: "$0.00"
  def format_usd_from_rogue(rogue, rogue_price) when is_number(rogue) and is_number(rogue_price) do
    usd = rogue * rogue_price
    "$#{:erlang.float_to_binary(usd, decimals: 2)}"
  end
  def format_usd_from_rogue(_, _), do: "$0.00"

  def format_number(value) when value >= 1_000_000, do: "#{Float.round(value / 1_000_000, 2)}M"
  def format_number(value) when value >= 1_000, do: "#{Float.round(value / 1_000, 2)}K"
  def format_number(value) when value < 0.01 and value > 0, do: "#{:erlang.float_to_binary(value, decimals: 4)}"
  def format_number(value), do: "#{Float.round(value * 1.0, 2)}"

  @doc "Format number with comma delimiters and no decimal places (e.g., 618,802)"
  def format_with_commas(value) when is_number(value) do
    value
    |> trunc()
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.map(&Enum.reverse/1)
    |> Enum.reverse()
    |> Enum.map(&Enum.join/1)
    |> Enum.join(",")
  end
  def format_with_commas(_), do: "0"

  @doc "Get combined total earned (revenue + time rewards) for an NFT in ROGUE"
  def nft_combined_total_earned(nft) do
    revenue = wei_to_rogue(nft.total_earned)
    time = if nft.time_reward, do: nft.time_reward.total_earned || 0, else: 0
    revenue + time
  end

  @doc "Get combined pending (revenue + time rewards) for an NFT in ROGUE"
  def nft_combined_pending(nft) do
    revenue = wei_to_rogue(nft.pending_amount)
    time = if nft.time_reward, do: nft.time_reward.pending || 0, else: 0
    revenue + time
  end

  @doc "Get combined 24h (revenue + time rewards) for an NFT in ROGUE"
  def nft_combined_24h(nft) do
    revenue = wei_to_rogue(nft.last_24h_earned)
    time = if nft.time_reward, do: nft.time_reward.last_24h || 0, else: 0
    revenue + time
  end

  @doc "Get time reward rate per second for an NFT (0 if not special)"
  def nft_time_rate(nft) do
    if nft.time_reward, do: nft.time_reward.rate_per_second || 0, else: 0
  end

  @doc "Check if NFT is a special NFT with time rewards"
  def nft_is_special?(nft) do
    nft.time_reward != nil && nft.time_reward.has_started
  end

  def wei_to_rogue(nil), do: 0.0
  def wei_to_rogue("0"), do: 0.0
  def wei_to_rogue(wei) when is_binary(wei), do: String.to_integer(wei) / 1.0e18
  def wei_to_rogue(wei) when is_integer(wei), do: wei / 1.0e18

  def format_time_ago(nil), do: "Just now"
  def format_time_ago(timestamp) when is_integer(timestamp) do
    now = System.system_time(:second)
    diff = now - timestamp

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      true -> "#{div(diff, 86400)}d ago"
    end
  end

  def truncate_address(nil), do: ""
  def truncate_address(address) when byte_size(address) < 10, do: address
  def truncate_address(address) do
    "#{String.slice(address, 0, 6)}...#{String.slice(address, -4, 4)}"
  end

  def hostess_name(index), do: HighRollers.Hostess.name(index)
  def hostess_multiplier(index), do: HighRollers.Hostess.multiplier(index)

  @doc """
  Calculate APY for an NFT based on its earnings.

  For non-special NFTs: Revenue APY only (24h earnings × 365 / NFT value)
  For special NFTs: Combined APY (revenue + time rewards)

  Time APY = (total_for_180_days × 365/180) / nft_value × 100
  Revenue APY = (24h_earnings × 365) / nft_value × 100
  """
  def nft_apy(nft, nft_value_rogue) when nft_value_rogue > 0 do
    # Revenue APY (based on 24h earnings)
    revenue_24h = wei_to_rogue(nft.last_24h_earned)
    revenue_annual = revenue_24h * 365
    revenue_apy = revenue_annual / nft_value_rogue * 100

    # Time APY (for special NFTs only)
    time_apy = if nft.time_reward && nft.time_reward.total_for_180_days > 0 do
      total_180d = nft.time_reward.total_for_180_days
      annualized = total_180d * 365 / 180
      annualized / nft_value_rogue * 100
    else
      0
    end

    Float.round(revenue_apy + time_apy, 1)
  end
  def nft_apy(_nft, _nft_value_rogue), do: 0.0

  # Always set chain for this page - overrides session value to ensure correct chain on navigation
  defp assign_default_chain(socket, chain) do
    assign(socket, :current_chain, chain)
  end
end
