defmodule HighRollersWeb.AffiliatesLive do
  @moduledoc """
  LiveView for affiliate program.

  Shows:
  - Referral link generator (copy to clipboard) - only when connected
  - User's stats: Tier 1 total, Tier 2 total, Withdrawable balance
  - User's referrals table (their specific referrals)
  - Global Recent Affiliate Earnings table (all earnings, combined tiers)

  Real-time updates via PubSub when new referral sales occur.

  IMPORTANT: Affiliate withdrawals are user-initiated transactions on Arbitrum.
  The user calls withdrawFromAffiliate() directly on the NFT contract using their wallet.
  This is different from NFT revenue withdrawals which go through AdminTxQueue on Rogue Chain.
  """
  use HighRollersWeb, :live_view

  @earnings_per_page 30

  @impl true
  def mount(_params, session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(HighRollers.PubSub, "nft_events")
    end

    # Load global affiliate earnings (all users)
    all_earnings = HighRollers.Sales.get_affiliate_earnings(nil, @earnings_per_page)

    # Load user-specific data if wallet already connected (from session)
    # The WalletHook sets wallet_address from session before mount, but
    # the wallet_connected event only fires on initial connection, not navigation.
    wallet_address = session["wallet_address"]
    {connected_wallet, affiliate_stats, my_referrals, referral_link} = if wallet_address do
      address = String.downcase(wallet_address)
      if connected?(socket) do
        Phoenix.PubSub.subscribe(HighRollers.PubSub, "affiliate:#{address}")
      end
      stats = HighRollers.Sales.get_affiliate_stats(address)
      referrals = HighRollers.Sales.get_affiliate_earnings(address, 50)
      link = generate_referral_link(address)
      {address, stats, referrals, link}
    else
      {nil, nil, [], nil}
    end

    # Get ETH price for USD conversion
    eth_price = HighRollers.PriceCache.get_eth_price()

    {:ok,
     socket
     |> assign(:connected_wallet, connected_wallet)
     |> assign(:affiliate_stats, affiliate_stats)
     |> assign(:my_referrals, my_referrals)
     |> assign(:referral_link, referral_link)
     |> assign(:link_copied, false)
     |> assign(:withdrawing, false)
     |> assign(:withdraw_tx_hash, nil)
     |> assign(:withdraw_error, nil)
     |> assign(:all_earnings, all_earnings)
     |> assign(:earnings_offset, @earnings_per_page)
     |> assign(:loading_more, false)
     |> assign(:earnings_end, length(all_earnings) < @earnings_per_page)
     |> assign(:eth_price, eth_price)
     |> assign(:current_path, "/affiliates")
     |> HighRollersWeb.WalletHook.set_page_chain("arbitrum")}
  end

  @impl true
  def handle_event("wallet_connected", %{"address" => address}, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(HighRollers.PubSub, "affiliate:#{String.downcase(address)}")
    end

    stats = HighRollers.Sales.get_affiliate_stats(address)
    my_referrals = HighRollers.Sales.get_affiliate_earnings(address, 50)
    referral_link = generate_referral_link(address)

    {:noreply,
     socket
     |> assign(:connected_wallet, address)
     |> assign(:affiliate_stats, stats)
     |> assign(:my_referrals, my_referrals)
     |> assign(:referral_link, referral_link)}
  end

  @impl true
  def handle_event("request_wallet_connect", _params, socket) do
    # Push event to JavaScript to trigger wallet connection modal
    {:noreply, push_event(socket, "open_wallet_modal", %{})}
  end

  @impl true
  def handle_event("copy_link", _params, socket) do
    # Handled by copy_success event from hook
    {:noreply, socket}
  end

  @impl true
  def handle_event("copy_success", _params, socket) do
    if socket.assigns.link_copied do
      {:noreply, socket}
    else
      Process.send_after(self(), :reset_link_copied, 3000)
      {:noreply, assign(socket, :link_copied, true)}
    end
  end

  @impl true
  def handle_event("copy_error", _params, socket) do
    # Ignore copy errors (e.g., "No text to copy")
    {:noreply, socket}
  end

  @impl true
  def handle_event("withdraw_affiliate", _params, socket) do
    {:noreply,
     socket
     |> assign(:withdrawing, true)
     |> assign(:withdraw_error, nil)
     |> assign(:withdraw_tx_hash, nil)}
  end

  @impl true
  def handle_event("withdraw_started", %{"tx_hash" => tx_hash}, socket) do
    require Logger
    Logger.info("[AffiliatesLive] Withdrawal TX sent: #{tx_hash}")
    {:noreply, socket}
  end

  @impl true
  def handle_event("withdraw_success", %{"tx_hash" => tx_hash}, socket) do
    address = socket.assigns.connected_wallet
    HighRollers.Users.reset_affiliate_balance(address)
    stats = HighRollers.Sales.get_affiliate_stats(address)

    {:noreply,
     socket
     |> assign(:withdrawing, false)
     |> assign(:withdraw_tx_hash, tx_hash)
     |> assign(:affiliate_stats, stats)}
  end

  @impl true
  def handle_event("withdraw_error", %{"error" => error}, socket) do
    {:noreply,
     socket
     |> assign(:withdrawing, false)
     |> assign(:withdraw_error, error)}
  end

  @impl true
  def handle_event("balance_updated", _params, socket) do
    # Ignore balance updates - we don't need to display balance on this page
    {:noreply, socket}
  end

  # Handle affiliate balance fetched from NFT contract via AffiliateBalanceHook
  @impl true
  def handle_event("affiliate_balance_fetched", %{"balance" => balance}, socket) do
    # Update the withdrawable_balance in affiliate_stats
    stats = socket.assigns.affiliate_stats
    updated_stats = if stats do
      Map.put(stats, :withdrawable_balance, balance)
    else
      # Create default stats with all required fields
      %{
        tier1_count: 0,
        tier1_total: 0,
        tier2_count: 0,
        tier2_total: 0,
        total_earned: 0,
        withdrawable_balance: balance
      }
    end

    {:noreply, assign(socket, :affiliate_stats, updated_stats)}
  end

  @impl true
  def handle_event("affiliate_balance_error", %{"error" => error}, socket) do
    require Logger
    Logger.warning("[AffiliatesLive] Failed to fetch affiliate balance: #{error}")
    {:noreply, socket}
  end

  @impl true
  def handle_event("wallet_disconnected", _params, socket) do
    {:noreply,
     socket
     |> assign(:connected_wallet, nil)
     |> assign(:affiliate_stats, nil)
     |> assign(:my_referrals, [])
     |> assign(:referral_link, nil)}
  end

  @impl true
  def handle_event("load_more_earnings", _params, socket) do
    offset = socket.assigns.earnings_offset
    new_earnings = HighRollers.Sales.get_affiliate_earnings(nil, @earnings_per_page, offset)

    if Enum.empty?(new_earnings) do
      {:reply, %{end_reached: true}, assign(socket, :earnings_end, true)}
    else
      {:noreply,
       socket
       |> assign(:all_earnings, socket.assigns.all_earnings ++ new_earnings)
       |> assign(:earnings_offset, offset + length(new_earnings))
       |> assign(:earnings_end, length(new_earnings) < @earnings_per_page)}
    end
  end

  # Reset link copied feedback
  @impl true
  def handle_info(:reset_link_copied, socket) do
    {:noreply, assign(socket, :link_copied, false)}
  end

  # Real-time: new NFT minted (may have affiliate earnings)
  @impl true
  def handle_info({:nft_minted, _event}, socket) do
    # Reload global earnings
    all_earnings = HighRollers.Sales.get_affiliate_earnings(nil, socket.assigns.earnings_offset)

    # Reload user stats if connected
    socket = if socket.assigns.connected_wallet do
      address = socket.assigns.connected_wallet
      stats = HighRollers.Sales.get_affiliate_stats(address)
      my_referrals = HighRollers.Sales.get_affiliate_earnings(address, 50)
      socket
      |> assign(:affiliate_stats, stats)
      |> assign(:my_referrals, my_referrals)
      |> push_event("refresh_affiliate_balance", %{})  # Refresh balance from contract
    else
      socket
    end

    {:noreply, assign(socket, :all_earnings, all_earnings)}
  end

  # Real-time: affiliate earning for this specific user
  @impl true
  def handle_info({:affiliate_earning, _earning_data}, socket) do
    address = socket.assigns.connected_wallet
    stats = HighRollers.Sales.get_affiliate_stats(address)
    my_referrals = HighRollers.Sales.get_affiliate_earnings(address, 50)

    {:noreply,
     socket
     |> assign(:affiliate_stats, stats)
     |> assign(:my_referrals, my_referrals)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ===== Helper Functions =====

  defp generate_referral_link(address) do
    base_url = HighRollersWeb.Endpoint.url()
    "#{base_url}/?ref=#{address}"
  end

  def format_eth(nil), do: "0"
  def format_eth(wei) when is_integer(wei) do
    eth = wei / 1.0e18
    :erlang.float_to_binary(eth, decimals: 3)
  end
  def format_eth(wei_string) when is_binary(wei_string) do
    wei = String.to_integer(wei_string)
    format_eth(wei)
  end
  def format_eth(_), do: "0"

  def format_eth_usd(nil, _eth_price), do: "$0.00"
  def format_eth_usd(wei, eth_price) when is_integer(wei) and is_number(eth_price) and eth_price > 0 do
    eth = wei / 1.0e18
    usd = eth * eth_price
    "$#{:erlang.float_to_binary(usd, decimals: 2)}"
  end
  def format_eth_usd(wei_string, eth_price) when is_binary(wei_string) do
    wei = String.to_integer(wei_string)
    format_eth_usd(wei, eth_price)
  end
  def format_eth_usd(_, _), do: "$0.00"

  def truncate_address(nil), do: "..."
  def truncate_address(address) when is_binary(address) and byte_size(address) >= 10 do
    String.slice(address, 0, 6) <> "..." <> String.slice(address, -4, 4)
  end
  def truncate_address(_), do: "..."

  def tier_class(1), do: "bg-green-900 text-green-400"
  def tier_class(2), do: "bg-blue-900 text-blue-400"
  def tier_class(_), do: "bg-gray-900 text-gray-400"

  def format_date(nil), do: ""
  def format_date(timestamp) do
    {:ok, datetime} = DateTime.from_unix(timestamp)
    Calendar.strftime(datetime, "%H:%M %b %d, %Y")
  end

  # Always set chain for this page - overrides session value to ensure correct chain on navigation
  defp assign_default_chain(socket, chain) do
    assign(socket, :current_chain, chain)
  end
end
