defmodule HighRollersWeb.MintLive do
  @moduledoc """
  LiveView for NFT gallery and minting page (homepage / Mint tab).

  Shows:
  - Mint stats (total minted, remaining, price, max supply)
  - Revenue stats (total rewards, 24h, APY)
  - Mint button with VRF waiting state
  - Mint result display
  - Hostess gallery with rarity and multiplier info, APY badges

  Real-time updates:
  - New mints via {:nft_minted, event}
  - Revenue stats via {:reward_received, event}
  - Full stats refresh via {:earnings_synced, stats}
  """
  use HighRollersWeb, :live_view

  @max_supply 2700
  @special_nft_start 2340

  # Time reward rates per second in ROGUE for each hostess type (index 0-7)
  @time_reward_rates [
    2.125029,  # Penelope (100x)
    1.912007,  # Mia (90x)
    1.700492,  # Cleo (80x)
    1.487470,  # Sophia (70x)
    1.274962,  # Luna (60x)
    1.062454,  # Aurora (50x)
    0.849946,  # Scarlett (40x)
    0.637438   # Vivienne (30x)
  ]
  @seconds_in_180_days 180 * 24 * 60 * 60  # 15,552,000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(HighRollers.PubSub, "nft_events")
      Phoenix.PubSub.subscribe(HighRollers.PubSub, "reward_events")
      Phoenix.PubSub.subscribe(HighRollers.PubSub, "earnings_events")
      Phoenix.PubSub.subscribe(HighRollers.PubSub, "price_events")
    end

    # Load initial data
    total_minted = HighRollers.NFTStore.count()
    remaining = @max_supply - total_minted
    special_remaining = max(0, @max_supply - max(total_minted, @special_nft_start - 1))
    hostesses = HighRollers.Hostess.all_with_counts()
    global_stats = HighRollers.Rewards.get_global_stats() || %{}
    hostess_stats = HighRollers.Rewards.get_all_hostess_stats()

    # Get prices from cache
    rogue_price = get_rogue_price()
    eth_price = HighRollers.PriceCache.get_eth_price()

    # Calculate global time reward stats for all special NFTs
    global_time_stats = calculate_global_time_stats()

    {:ok,
     socket
     |> assign(:total_minted, total_minted)
     |> assign(:remaining, remaining)
     |> assign(:special_remaining, special_remaining)
     |> assign(:hostesses, hostesses)
     |> assign(:global_stats, global_stats)
     |> assign(:hostess_stats, hostess_stats)
     |> assign(:rogue_price, rogue_price)
     |> assign(:eth_price, eth_price)
     |> assign(:global_time_stats, global_time_stats)
     |> assign(:minting, false)
     |> assign(:mint_status, nil)
     |> assign(:mint_result, nil)
     |> assign(:sold_out, remaining <= 0)
     |> assign(:current_path, "/")
     |> HighRollersWeb.WalletHook.set_page_chain("arbitrum")}
  end

  # ===== REAL-TIME UPDATES =====

  @impl true
  def handle_info({:nft_minted, event}, socket) do
    # Update mint counts
    total_minted = socket.assigns.total_minted + 1
    remaining = @max_supply - total_minted
    special_remaining = max(0, @max_supply - max(total_minted, @special_nft_start - 1))
    hostesses = HighRollers.Hostess.all_with_counts()

    # If this is our mint (check wallet), show result and refresh balance
    socket = if socket.assigns.wallet_address &&
                String.downcase(event.recipient) == socket.assigns.wallet_address do
      socket
      |> assign(:mint_result, %{
        token_id: event.token_id,
        hostess_index: event.hostess_index,
        hostess_name: HighRollers.Hostess.name(event.hostess_index),
        hostess: HighRollers.Hostess.get(event.hostess_index),
        tx_hash: event.tx_hash
      })
      |> assign(:minting, false)
      |> assign(:mint_status, nil)
      |> push_event("refresh_balance", %{})  # Trigger JS to refresh wallet balance
    else
      socket
    end

    {:noreply,
     socket
     |> assign(:total_minted, total_minted)
     |> assign(:remaining, remaining)
     |> assign(:special_remaining, special_remaining)
     |> assign(:hostesses, hostesses)
     |> assign(:sold_out, remaining <= 0)}
  end

  @impl true
  def handle_info({:mint_requested, event}, socket) do
    # VRF request received - show waiting state if this is our mint
    if socket.assigns.wallet_address &&
       String.downcase(event.sender) == socket.assigns.wallet_address do
      {:noreply, assign(socket, :mint_status, "Waiting for VRF...")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:reward_received, event}, socket) do
    global_stats = socket.assigns.global_stats
    new_total = add_wei(global_stats[:total_rewards_received] || "0", event.amount)
    new_24h = add_wei(global_stats[:rewards_last_24h] || "0", event.amount)

    updated_stats = Map.merge(global_stats, %{
      total_rewards_received: new_total,
      rewards_last_24h: new_24h
    })

    {:noreply, assign(socket, :global_stats, updated_stats)}
  end

  @impl true
  def handle_info({:earnings_synced, stats}, socket) do
    hostess_stats = HighRollers.Rewards.get_all_hostess_stats()
    global_time_stats = calculate_global_time_stats()

    {:noreply,
     socket
     |> assign(:global_stats, stats)
     |> assign(:hostess_stats, hostess_stats)
     |> assign(:global_time_stats, global_time_stats)}
  end

  @impl true
  def handle_info({:price_update, %{rogue: rogue_price, eth: eth_price}}, socket) do
    {:noreply,
     socket
     |> assign(:rogue_price, rogue_price)
     |> assign(:eth_price, eth_price)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ===== WALLET EVENTS =====

  @impl true
  def handle_event("wallet_connected", _params, socket) do
    # Wallet state is managed by WalletHook via attach_hook
    {:noreply, socket}
  end

  @impl true
  def handle_event("wallet_disconnected", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("balance_updated", _params, socket) do
    {:noreply, socket}
  end

  # ===== MINT EVENTS =====

  @impl true
  def handle_event("mint", _params, socket) do
    # Mint transaction is initiated by JavaScript MintHook
    # This just sets the minting state
    {:noreply,
     socket
     |> assign(:minting, true)
     |> assign(:mint_status, "Initiating transaction...")
     |> assign(:mint_result, nil)}
  end

  @impl true
  def handle_event("mint_tx_sent", _params, socket) do
    {:noreply, assign(socket, :mint_status, "Waiting for confirmation...")}
  end

  @impl true
  def handle_event("mint_tx_confirmed", _params, socket) do
    {:noreply, assign(socket, :mint_status, "Waiting for VRF...")}
  end

  @impl true
  def handle_event("mint_requested", %{"request_id" => _request_id, "token_id" => _token_id, "tx_hash" => _tx_hash}, socket) do
    # Mint transaction confirmed, waiting for VRF
    {:noreply, assign(socket, :mint_status, "Waiting for VRF...")}
  end

  @impl true
  def handle_event("mint_complete", params, socket) do
    # Mint completed (from JS fallback polling or server event forwarding)
    hostess_index = params["hostess_index"] || 0
    hostess = HighRollers.Hostess.get(hostess_index)

    mint_result = %{
      token_id: params["token_id"],
      hostess_index: hostess_index,
      hostess_name: hostess.name,
      hostess: hostess,
      tx_hash: params["tx_hash"]
    }

    {:noreply,
     socket
     |> assign(:minting, false)
     |> assign(:mint_status, nil)
     |> assign(:mint_result, mint_result)
     |> push_event("refresh_balance", %{})}
  end

  @impl true
  def handle_event("mint_error", %{"error" => error}, socket) do
    {:noreply,
     socket
     |> assign(:minting, false)
     |> assign(:mint_status, "Error: #{error}")}
  end

  @impl true
  def handle_event("dismiss_mint_result", _params, socket) do
    {:noreply, assign(socket, :mint_result, nil)}
  end

  # ===== HELPERS =====

  defp add_wei(a, b) do
    Integer.to_string(String.to_integer(a || "0") + String.to_integer(b || "0"))
  end

  # Format helpers exposed for template
  def format_rogue(nil), do: "0"
  def format_rogue(wei_string) when is_binary(wei_string) do
    wei = String.to_integer(wei_string)
    rogue = wei / 1.0e18
    format_number(rogue)
  end
  def format_rogue(_), do: "0"

  def format_usd(nil, _price), do: "$0.00"
  def format_usd(wei_string, rogue_price) when is_binary(wei_string) and is_number(rogue_price) do
    wei = String.to_integer(wei_string)
    rogue = wei / 1.0e18
    usd = rogue * rogue_price
    "$#{:erlang.float_to_binary(usd, decimals: 2)}"
  end
  def format_usd(_, _), do: "$0.00"

  defp format_number(value) when value >= 1_000_000, do: "#{Float.round(value / 1_000_000, 2)}M"
  defp format_number(value) when value >= 1_000, do: "#{Float.round(value / 1_000, 2)}K"
  defp format_number(value), do: "#{Float.round(value * 1.0, 2)}"

  def format_apy(nil), do: "0"
  def format_apy(basis_points) when is_integer(basis_points), do: Float.round(basis_points / 100, 1)
  def format_apy(_), do: "0"

  def progress_percent(total_minted, max_supply) do
    Float.round(total_minted / max_supply * 100, 1)
  end

  def format_180_day_earnings(hostess_index) do
    rate = Enum.at(@time_reward_rates, hostess_index, 0)
    total = rate * @seconds_in_180_days
    format_number_with_commas(trunc(total))
  end

  def format_180_day_earnings_usd(hostess_index, rogue_price) do
    rate = Enum.at(@time_reward_rates, hostess_index, 0)
    total = rate * @seconds_in_180_days
    usd = total * (rogue_price || 0)
    "$#{format_number_with_commas(trunc(usd))}"
  end

  defp format_number_with_commas(number) when is_integer(number) do
    number
    |> Integer.to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp get_rogue_price do
    # Try to get from ETS cache or return default
    # This will be populated by a price service
    HighRollers.PriceCache.get_rogue_price()
  end

  @doc """
  Calculate global time reward stats for ALL special NFTs (for mint page display).
  Similar to calculate_special_nfts_stats in RevenuesLive but for all special NFTs globally.
  """
  def calculate_global_time_stats do
    special_nfts = HighRollers.NFTStore.get_special_nfts_by_owner(nil)

    # Filter to only those with time rewards started
    active_nfts = Enum.filter(special_nfts, fn nft ->
      nft.time_start_time && nft.time_start_time > 0
    end)

    if length(active_nfts) == 0 do
      %{
        count: 0,
        total_earned: 0.0,
        total_pending: 0.0,
        total_24h: 0.0,
        total_180d: 0.0,
        total_rate_per_second: 0.0,
        apy: 0.0,
        base_time: System.system_time(:second)
      }
    else
      now = System.system_time(:second)

      # Calculate totals for each special NFT
      {total_earned, total_pending, total_24h, total_180d, total_rate} =
        Enum.reduce(active_nfts, {0.0, 0.0, 0.0, 0.0, 0.0}, fn nft, {earned_acc, pending_acc, h24_acc, d180_acc, rate_acc} ->
          time_info = HighRollers.TimeRewards.get_nft_time_info(nft.token_id)

          {
            earned_acc + (time_info.total_earned || 0),
            pending_acc + (time_info.pending || 0),
            h24_acc + (time_info.last_24h || 0),
            d180_acc + (time_info.total_for_180_days || 0),
            rate_acc + (time_info.rate_per_second || 0)
          }
        end)

      # Calculate average APY based on 180d total earnings
      # APY = (total_for_180_days × 365/180) / nft_value × 100
      nft_value_rogue = HighRollers.PriceCache.get_nft_value_rogue()
      avg_apy = if length(active_nfts) > 0 and total_180d > 0 and nft_value_rogue > 0 do
        avg_180d_per_nft = total_180d / length(active_nfts)
        annualized = avg_180d_per_nft * 365 / 180
        Float.round(annualized / nft_value_rogue * 100, 1)
      else
        0.0
      end

      %{
        count: length(active_nfts),
        total_earned: total_earned,
        total_pending: total_pending,
        total_24h: total_24h,
        total_180d: total_180d,
        total_rate_per_second: total_rate,
        apy: avg_apy,
        base_time: now
      }
    end
  end

  @doc "Convert wei string to ROGUE float"
  def wei_to_rogue(nil), do: 0.0
  def wei_to_rogue("0"), do: 0.0
  def wei_to_rogue(wei) when is_binary(wei), do: String.to_integer(wei) / 1.0e18
  def wei_to_rogue(wei) when is_integer(wei), do: wei / 1.0e18

  @doc "Format number with commas, no decimals"
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

  @doc "Format USD from ROGUE amount"
  def format_usd_from_rogue(nil, _price), do: "$0.00"
  def format_usd_from_rogue(rogue, rogue_price) when is_number(rogue) and is_number(rogue_price) do
    usd = rogue * rogue_price
    "$#{:erlang.float_to_binary(usd, decimals: 2)}"
  end
  def format_usd_from_rogue(_, _), do: "$0.00"

  @doc "Format ETH amount to USD"
  def format_eth_to_usd(eth, eth_price) when is_number(eth) and is_number(eth_price) and eth_price > 0 do
    usd = eth * eth_price
    "$#{format_with_commas(trunc(usd))}"
  end
  def format_eth_to_usd(_, _), do: "$0"

  # Always set chain for this page - overrides session value to ensure correct chain on navigation
  defp assign_default_chain(socket, chain) do
    assign(socket, :current_chain, chain)
  end
end
