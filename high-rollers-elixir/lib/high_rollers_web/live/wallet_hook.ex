defmodule HighRollersWeb.WalletHook do
  @moduledoc """
  LiveView on_mount hook for wallet state management.

  Reads wallet state from Phoenix session (set by WalletController API).
  Subscribes to PubSub for real-time balance updates across all tabs.

  Assigns set:
  - wallet_address: connected wallet address (nil if disconnected)
  - wallet_connected: boolean
  - wallet_balance: current balance string
  - wallet_type: wallet provider (metamask, coinbase, etc.)
  - current_chain: "arbitrum" or "rogue"
  - current_path: current route path for tab highlighting

  This eliminates wallet state flash on navigation by reading from session
  before first render (session is set by /api/wallet/connect endpoint).
  """
  import Phoenix.LiveView
  import Phoenix.Component

  @pubsub HighRollers.PubSub
  @topic_prefix "wallet:"

  def on_mount(:default, _params, session, socket) do
    # Debug: Log session contents
    require Logger
    Logger.debug("[WalletHook] Session keys: #{inspect(Map.keys(session))}")
    Logger.debug("[WalletHook] Session: #{inspect(session)}")

    # Read wallet state from session (set by /api/wallet/connect)
    wallet_address = session["wallet_address"]
    wallet_connected = wallet_address != nil
    Logger.debug("[WalletHook] wallet_address from session: #{inspect(wallet_address)}")

    # Determine current path for tab highlighting
    # NOTE: This returns "/" as default - each LiveView will override with its actual path
    current_path = get_current_path(socket)

    # Set initial assigns from session
    # NOTE: current_chain is set to nil here - each LiveView will set it based on its page
    # This ensures the correct chain is shown immediately without flash
    # Store session_chain so LiveViews can detect chain mismatch and clear stale balance
    socket =
      socket
      |> assign(:wallet_address, wallet_address)
      |> assign(:wallet_connected, wallet_connected)
      |> assign(:wallet_balance, session["wallet_balance"])
      |> assign(:wallet_type, session["wallet_type"])
      |> assign(:current_chain, nil)
      |> assign(:session_chain, session["wallet_chain"])
      |> assign(:current_path, current_path)

    # Subscribe to balance updates and attach hooks (only if connected)
    socket =
      if connected?(socket) && wallet_address do
        # Subscribe to PubSub for this wallet
        Phoenix.PubSub.subscribe(@pubsub, "#{@topic_prefix}#{wallet_address}")

        # Attach hooks to handle PubSub messages and JS events
        socket
        |> attach_hook(:wallet_updates, :handle_info, &handle_wallet_info/2)
        |> attach_hook(:wallet_events, :handle_event, &handle_wallet_event/3)
      else
        # Still attach event hook for wallet_connected event (user might connect)
        attach_hook(socket, :wallet_events, :handle_event, &handle_wallet_event/3)
      end

    {:cont, socket}
  end

  # ===== PubSub Message Handlers =====

  defp handle_wallet_info({:balance_updated, balance}, socket) do
    {:halt, assign(socket, :wallet_balance, balance)}
  end

  defp handle_wallet_info({:wallet_disconnected}, socket) do
    socket =
      socket
      |> assign(:wallet_address, nil)
      |> assign(:wallet_connected, false)
      |> assign(:wallet_balance, nil)
      |> assign(:wallet_type, nil)

    {:halt, socket}
  end

  defp handle_wallet_info(_other, socket) do
    {:cont, socket}
  end

  # ===== JavaScript Event Handlers =====

  # Handle wallet connection from JavaScript (for immediate UI update)
  defp handle_wallet_event("wallet_connected", %{"address" => address} = params, socket) do
    # Re-subscribe to new wallet's PubSub topic
    if socket.assigns[:wallet_address] do
      Phoenix.PubSub.unsubscribe(@pubsub, "#{@topic_prefix}#{socket.assigns.wallet_address}")
    end

    normalized_address = String.downcase(address)
    Phoenix.PubSub.subscribe(@pubsub, "#{@topic_prefix}#{normalized_address}")

    socket =
      socket
      |> assign(:wallet_address, normalized_address)
      |> assign(:wallet_connected, true)
      |> maybe_assign(:wallet_balance, params["balance"])
      |> maybe_assign(:wallet_type, params["type"])
      |> maybe_assign(:current_chain, params["chain"])

    {:cont, socket}
  end

  # Handle wallet disconnection from JavaScript
  defp handle_wallet_event("wallet_disconnected", _params, socket) do
    if socket.assigns[:wallet_address] do
      Phoenix.PubSub.unsubscribe(@pubsub, "#{@topic_prefix}#{socket.assigns.wallet_address}")
    end

    # Default chain based on page: Mint uses Arbitrum, all others use Rogue
    current_path = socket.assigns[:current_path] || "/"
    default_chain = if current_path == "/", do: "arbitrum", else: "rogue"

    socket =
      socket
      |> assign(:wallet_address, nil)
      |> assign(:wallet_connected, false)
      |> assign(:wallet_balance, nil)
      |> assign(:wallet_type, nil)
      |> assign(:current_chain, default_chain)

    {:cont, socket}
  end

  # Handle balance updates from JavaScript
  defp handle_wallet_event("balance_updated", %{"balance" => balance} = params, socket) do
    require Logger
    Logger.info("[WalletHook] balance_updated event: balance=#{balance}, chain=#{params["chain"]}")

    socket =
      socket
      |> assign(:wallet_balance, balance)
      |> maybe_assign(:current_chain, params["chain"])

    {:cont, socket}
  end

  # Handle chain changes from JavaScript
  # Use {:halt, ...} because this event is fully handled here - don't pass to LiveView
  defp handle_wallet_event("wallet_chain_changed", %{"chain" => chain}, socket) do
    {:halt, assign(socket, :current_chain, parse_chain(chain))}
  end

  # Pass through all other events
  defp handle_wallet_event(_event, _params, socket) do
    {:cont, socket}
  end

  # ===== Helper Functions =====

  defp get_current_path(_socket) do
    # NOTE: Each LiveView now sets its own current_path in mount, so this
    # function just returns a default value that will be overridden.
    # The LiveView's mount happens AFTER on_mount, so the LiveView's value wins.
    "/"
  end

  defp maybe_assign(socket, _key, nil), do: socket
  defp maybe_assign(socket, key, value), do: assign(socket, key, value)

  defp parse_chain("arbitrum"), do: "arbitrum"
  defp parse_chain("rogue"), do: "rogue"
  defp parse_chain(42161), do: "arbitrum"
  defp parse_chain(560013), do: "rogue"
  defp parse_chain(_), do: "arbitrum"

  # ===== Public Helpers (called from LiveViews) =====

  @doc """
  Set the current chain for this page and clear stale balance if chain changed.

  Call this in LiveView mount to set the expected chain for the page.
  If the session chain doesn't match the expected chain, clears the balance
  until JavaScript fetches the correct balance for the new chain.

  ## Example

      def mount(_params, _session, socket) do
        socket = WalletHook.set_page_chain(socket, "rogue")
        {:ok, socket}
      end
  """
  def set_page_chain(socket, expected_chain) do
    session_chain = socket.assigns[:session_chain]

    # If session chain doesn't match expected chain, clear the stale balance
    # JavaScript will fetch and push the correct balance for the new chain
    wallet_balance =
      if session_chain != expected_chain && socket.assigns[:wallet_connected] do
        nil
      else
        socket.assigns[:wallet_balance]
      end

    socket
    |> assign(:current_chain, expected_chain)
    |> assign(:wallet_balance, wallet_balance)
  end

  # ===== Broadcast Functions (called from business logic) =====

  @doc """
  Broadcast balance update to all LiveViews for this wallet.
  Call this after mint, withdraw, or any balance-changing operation.
  """
  def broadcast_balance_update(wallet_address, balance) when is_binary(wallet_address) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "#{@topic_prefix}#{String.downcase(wallet_address)}",
      {:balance_updated, balance}
    )
  end

  @doc """
  Broadcast disconnect to all LiveViews for this wallet.
  """
  def broadcast_disconnect(wallet_address) when is_binary(wallet_address) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      "#{@topic_prefix}#{String.downcase(wallet_address)}",
      {:wallet_disconnected}
    )
  end
end
