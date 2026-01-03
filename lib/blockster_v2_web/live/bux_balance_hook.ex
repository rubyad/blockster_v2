defmodule BlocksterV2Web.BuxBalanceHook do
  @moduledoc """
  LiveView on_mount hook to manage BUX balance display in the header.

  - Fetches the initial on-chain BUX balance from Mnesia
  - Subscribes to PubSub updates when balance changes after minting
  - Updates the bux_balance assign when new balance is broadcast
  - Also updates token_balances for individual token balances in dropdowns
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]
  alias BlocksterV2.EngagementTracker

  @pubsub BlocksterV2.PubSub
  @topic_prefix "bux_balance:"

  def on_mount(:default, _params, _session, socket) do
    # Get user_id from current_user (set by UserAuth hook which runs before this)
    user_id = get_user_id(socket)

    # DEBUG: Dump full token balances record for user 65
    if user_id == 65, do: EngagementTracker.dump_user_bux_balances(65)

    # Fetch initial balance from Mnesia
    initial_balance = if user_id, do: EngagementTracker.get_user_bux_balance(user_id), else: 0

    # Fetch initial token balances (individual tokens like BUX, moonBUX, etc.)
    initial_token_balances = if user_id do
      EngagementTracker.get_user_token_balances(user_id) || %{}
    else
      %{}
    end

    # Subscribe to balance updates for this user (only if connected and logged in)
    if connected?(socket) && user_id do
      Phoenix.PubSub.subscribe(@pubsub, "#{@topic_prefix}#{user_id}")
    end

    socket =
      socket
      |> assign(:bux_balance, initial_balance)
      |> assign(:token_balances, initial_token_balances)
      |> attach_hook(:bux_balance_updates, :handle_info, fn
        {:bux_balance_updated, new_balance}, socket ->
          {:halt, assign(socket, :bux_balance, new_balance)}

        {:token_balances_updated, token_balances}, socket ->
          # Merge new token balances with existing (preserves ROGUE when only BUX is updated)
          existing_balances = Map.get(socket.assigns, :token_balances, %{})
          merged_balances = Map.merge(existing_balances, token_balances)
          # Update both :token_balances (for header) and :balances (for BuxBoosterLive)
          socket = assign(socket, :token_balances, merged_balances)
          socket = if Map.has_key?(socket.assigns, :balances) do
            existing_game_balances = Map.get(socket.assigns, :balances, %{})
            merged_game_balances = Map.merge(existing_game_balances, token_balances)
            assign(socket, :balances, merged_game_balances)
          else
            socket
          end
          {:halt, socket}

        _other, socket ->
          {:cont, socket}
      end)

    {:cont, socket}
  end

  defp get_user_id(socket) do
    case socket.assigns[:current_user] do
      nil -> nil
      user -> user.id
    end
  end

  @doc """
  Broadcasts a balance update to all LiveViews subscribed to this user's balance.
  Call this from EngagementTracker after updating the balance.
  """
  def broadcast_balance_update(user_id, new_balance) do
    Phoenix.PubSub.broadcast(@pubsub, "#{@topic_prefix}#{user_id}", {:bux_balance_updated, new_balance})
  end

  @doc """
  Broadcasts token balances update to all LiveViews subscribed to this user's balance.
  Call this from EngagementTracker after updating individual token balances.
  """
  def broadcast_token_balances_update(user_id, token_balances) do
    require Logger
    Logger.info("[BuxBalanceHook] Broadcasting token balances for user #{user_id}: #{inspect(token_balances)}")
    Phoenix.PubSub.broadcast(@pubsub, "#{@topic_prefix}#{user_id}", {:token_balances_updated, token_balances})
  end
end
