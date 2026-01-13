defmodule HighRollersWeb.MyNftsLive do
  @moduledoc """
  LiveView for user's NFT collection grid.

  Shows:
  - Grid of user's owned NFTs
  - Revenue sharing earnings per NFT (pending, total)
  - Time-based rewards for special NFTs (2340-2700)

  Real-time updates:
  - New mints via {:nft_minted, event}
  - NFT transfers via {:nft_transferred, event}
  - Earnings sync via {:earnings_synced, stats}
  - Reward claims via {:reward_claimed, event}

  Requires wallet connection - redirects to mint page if not connected.
  """
  use HighRollersWeb, :live_view
  require Logger

  @special_nft_start 2340
  @special_nft_end 2700

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(HighRollers.PubSub, "nft_events")
      Phoenix.PubSub.subscribe(HighRollers.PubSub, "reward_events")
      Phoenix.PubSub.subscribe(HighRollers.PubSub, "earnings_events")
      Phoenix.PubSub.subscribe(HighRollers.PubSub, "price_events")
    end

    # Get ROGUE price
    rogue_price = get_rogue_price()

    # Load NFTs if wallet already connected (from session)
    # The WalletHook sets wallet_address from session before mount, but
    # the wallet_connected event only fires on initial connection, not navigation.
    # So we need to load NFTs here if wallet is already in session.
    wallet_address = session["wallet_address"]
    {nfts, loading} = if wallet_address do
      {load_user_nfts(String.downcase(wallet_address)), false}
    else
      {[], true}
    end

    {:ok,
     socket
     |> assign(:nfts, nfts)
     |> assign(:rogue_price, rogue_price)
     |> assign(:loading, loading)
     |> assign(:current_path, "/my-nfts")
     |> HighRollersWeb.WalletHook.set_page_chain("rogue")}
  end

  # Load NFTs when wallet connects
  @impl true
  def handle_event("wallet_connected", %{"address" => address}, socket) do
    nfts = load_user_nfts(String.downcase(address))
    {:noreply, socket |> assign(:nfts, nfts) |> assign(:loading, false)}
  end

  # ===== REAL-TIME UPDATES =====

  @impl true
  def handle_info({:nft_minted, event}, socket) do
    # Check if this NFT was minted to the current user
    if socket.assigns.wallet_address &&
       String.downcase(event.recipient) == socket.assigns.wallet_address do
      # Reload NFTs to include the new one
      nfts = load_user_nfts(socket.assigns.wallet_address)
      {:noreply, assign(socket, :nfts, nfts)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:nft_transferred, event}, socket) do
    wallet_address = socket.assigns.wallet_address

    # Check if user received or sent an NFT
    if wallet_address &&
       (String.downcase(event.to) == wallet_address ||
        String.downcase(event.from) == wallet_address) do
      # Reload NFTs
      nfts = load_user_nfts(wallet_address)
      {:noreply, assign(socket, :nfts, nfts)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:earnings_synced, _stats}, socket) do
    # Reload NFTs to get updated earnings
    if socket.assigns.wallet_address do
      nfts = load_user_nfts(socket.assigns.wallet_address)
      {:noreply, assign(socket, :nfts, nfts)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:reward_received, event}, socket) do
    # When rewards are distributed, update NFT earnings optimistically
    if socket.assigns.wallet_address && length(socket.assigns.nfts) > 0 do
      updated_nfts = update_nfts_optimistically(socket.assigns.nfts, event.amount)
      {:noreply, assign(socket, :nfts, updated_nfts)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:reward_claimed, event}, socket) do
    # If this was our withdrawal, refresh data
    if socket.assigns.wallet_address &&
       String.downcase(event.user) == socket.assigns.wallet_address do
      nfts = load_user_nfts(socket.assigns.wallet_address)
      {:noreply, assign(socket, :nfts, nfts)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:price_update, %{rogue: rogue_price}}, socket) do
    {:noreply, assign(socket, :rogue_price, rogue_price)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ===== WALLET EVENTS =====

  @impl true
  def handle_event("wallet_disconnected", _params, socket) do
    # Redirect to home when wallet disconnects
    {:noreply, push_navigate(socket, to: "/")}
  end

  @impl true
  def handle_event("balance_updated", _params, socket) do
    {:noreply, socket}
  end

  # ===== EVENTS =====

  @impl true
  def handle_event("go_to_mint", _params, socket) do
    {:noreply, push_navigate(socket, to: "/")}
  end

  # ===== PRIVATE FUNCTIONS =====

  defp load_user_nfts(nil), do: []
  defp load_user_nfts(wallet_address) do
    nfts = HighRollers.NFTStore.get_by_owner(wallet_address)

    # Add time reward info for special NFTs
    nfts
    |> Enum.map(fn nft ->
      if special_nft?(nft.token_id) do
        time_info = HighRollers.TimeRewards.get_nft_time_info(nft.token_id)
        Map.put(nft, :time_reward, time_info)
      else
        nft
      end
    end)
    |> Enum.sort_by(& &1.token_id, :desc)  # Newest first
  end

  defp special_nft?(token_id), do: token_id >= @special_nft_start and token_id <= @special_nft_end

  # Multipliers for each hostess index (0-7)
  @multipliers [100, 90, 80, 70, 60, 50, 40, 30]

  defp update_nfts_optimistically(nfts, reward_amount_str) do
    reward_amount = String.to_integer(reward_amount_str)
    total_points = HighRollers.NFTStore.get_total_multiplier_points()

    updated_nfts = Enum.map(nfts, fn nft ->
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

    updated_nfts
  end

  defp add_wei(a, b) do
    Integer.to_string(String.to_integer(a || "0") + String.to_integer(b || "0"))
  end

  defp get_rogue_price do
    HighRollers.PriceCache.get_rogue_price()
  end

  # ===== VIEW HELPERS =====

  def format_rogue(nil), do: "0"
  def format_rogue(wei) when is_binary(wei), do: format_rogue(String.to_integer(wei))
  def format_rogue(wei) when is_integer(wei) do
    rogue = wei / 1.0e18
    format_number(rogue)
  end

  def format_usd(nil, _price), do: "$0.00"
  def format_usd(wei, rogue_price) when is_binary(wei), do: format_usd(String.to_integer(wei), rogue_price)
  def format_usd(wei, rogue_price) when is_integer(wei) and is_number(rogue_price) do
    rogue = wei / 1.0e18
    usd = rogue * rogue_price
    "$#{:erlang.float_to_binary(usd, decimals: 2)}"
  end
  def format_usd(_, _), do: "$0.00"

  defp format_number(value) when value >= 1_000_000, do: "#{Float.round(value / 1_000_000, 2)}M"
  defp format_number(value) when value >= 1_000, do: "#{Float.round(value / 1_000, 2)}K"
  defp format_number(value), do: "#{Float.round(value * 1.0, 2)}"

  def format_time_reward_amount(nil), do: "0"
  def format_time_reward_amount(0), do: "0"
  def format_time_reward_amount(amount) when is_number(amount) do
    # Format with comma delimiters and no decimal places (e.g., 618,802)
    amount
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

  def format_time_remaining(nil), do: "Ended"
  def format_time_remaining(seconds) when seconds <= 0, do: "Ended"
  def format_time_remaining(seconds) do
    days = div(seconds, 86400)
    hours = div(rem(seconds, 86400), 3600)
    minutes = div(rem(seconds, 3600), 60)
    secs = rem(seconds, 60)

    "#{days}d:#{pad(hours)}h:#{pad(minutes)}m:#{pad(secs)}s"
  end

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  @doc """
  Get CSS class for rarity badge - matches UI.getRarityClass() in Node.js app.
  Rarity string format: "0.5%", "1%", "3.5%", "7.5%", "12.5%", "25%"
  """
  def get_rarity_class(nil), do: "rarity-common"
  def get_rarity_class(rarity) when is_binary(rarity) do
    # Parse percent value from string like "0.5%" or "25%"
    percent = rarity
    |> String.replace("%", "")
    |> String.trim()
    |> Float.parse()
    |> case do
      {value, _} -> value
      :error -> 100.0
    end

    cond do
      percent <= 1 -> "rarity-legendary"    # 0.5% and 1%
      percent <= 7.5 -> "rarity-epic"       # 3.5% and 7.5%
      percent <= 12.5 -> "rarity-rare"      # 12.5%
      true -> "rarity-common"               # 25%
    end
  end

  def hostess_name(index), do: HighRollers.Hostess.name(index)
  def hostess_multiplier(index), do: HighRollers.Hostess.multiplier(index)
  def hostess_image(index), do: HighRollers.Hostess.image(index)

  # Always set chain for this page - overrides session value to ensure correct chain on navigation
  defp assign_default_chain(socket, chain) do
    assign(socket, :current_chain, chain)
  end
end
