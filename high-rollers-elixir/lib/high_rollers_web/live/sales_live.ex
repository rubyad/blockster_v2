defmodule HighRollersWeb.SalesLive do
  @moduledoc """
  LiveView for the Live Sales tab.

  Shows:
  - Paginated sales table with all minted NFTs
  - Infinite scroll for loading more
  - Real-time prepending of new sales via PubSub

  Real-time updates:
  - New mints prepend to table via {:nft_minted, event}
  """
  use HighRollersWeb, :live_view

  @page_size 50

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(HighRollers.PubSub, "nft_events")
    end

    # Load initial sales
    sales = HighRollers.Sales.get_sales(@page_size, 0)

    # Get ETH price for USD conversion
    eth_price = HighRollers.PriceCache.get_eth_price()

    {:ok,
     socket
     |> assign(:sales, sales)
     |> assign(:sales_offset, @page_size)
     |> assign(:sales_end, length(sales) < @page_size)
     |> assign(:loading_more, false)
     |> assign(:eth_price, eth_price)
     |> assign(:current_path, "/sales")
     |> HighRollersWeb.WalletHook.set_page_chain("rogue")}
  end

  # ===== REAL-TIME UPDATES =====

  @impl true
  def handle_info({:nft_minted, event}, socket) do
    # Prepend new sale to top of list
    new_sale = %{
      token_id: event.token_id,
      buyer: event.recipient,
      hostess_index: event.hostess_index,
      hostess_name: HighRollers.Hostess.name(event.hostess_index),
      price: event.price,
      price_eth: format_eth(event.price),
      tx_hash: event.tx_hash,
      timestamp: System.system_time(:second)
    }

    {:noreply, assign(socket, :sales, [new_sale | socket.assigns.sales])}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ===== WALLET EVENTS =====

  @impl true
  def handle_event("wallet_connected", _params, socket) do
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

  # ===== EVENTS =====

  @impl true
  def handle_event("load_more_sales", _params, socket) do
    if socket.assigns.sales_end || socket.assigns.loading_more do
      {:noreply, socket}
    else
      socket = assign(socket, :loading_more, true)
      offset = socket.assigns.sales_offset

      new_sales = HighRollers.Sales.get_sales(@page_size, offset)

      {:noreply,
       socket
       |> assign(:sales, socket.assigns.sales ++ new_sales)
       |> assign(:sales_offset, offset + length(new_sales))
       |> assign(:sales_end, length(new_sales) < @page_size)
       |> assign(:loading_more, false)}
    end
  end

  # ===== HELPERS =====

  defp format_eth(nil), do: "0"
  defp format_eth(wei_string) when is_binary(wei_string) do
    wei = String.to_integer(wei_string)
    :erlang.float_to_binary(wei / 1.0e18, decimals: 6)
  end
  defp format_eth(_), do: "0"

  def format_date(nil), do: ""
  def format_date(timestamp) do
    {:ok, datetime} = DateTime.from_unix(timestamp)
    Calendar.strftime(datetime, "%H:%M %b %d, %Y")
  end

  def truncate_address(nil), do: ""
  def truncate_address(address) when is_binary(address) do
    String.slice(address, 0, 6) <> "..." <> String.slice(address, -4, 4)
  end

  def format_eth_short(nil), do: "0.00"
  def format_eth_short(wei_string) when is_binary(wei_string) do
    wei = String.to_integer(wei_string)
    :erlang.float_to_binary(wei / 1.0e18, decimals: 2)
  end
  def format_eth_short(_), do: "0.00"

  def format_eth_usd(nil, _eth_price), do: "$0.00"
  def format_eth_usd(wei_string, eth_price) when is_binary(wei_string) and is_number(eth_price) and eth_price > 0 do
    wei = String.to_integer(wei_string)
    eth = wei / 1.0e18
    usd = eth * eth_price
    "$#{:erlang.float_to_binary(usd, decimals: 2)}"
  end
  def format_eth_usd(_, _), do: "$0.00"

  # Always set chain for this page - overrides session value to ensure correct chain on navigation
  defp assign_default_chain(socket, chain) do
    assign(socket, :current_chain, chain)
  end
end
