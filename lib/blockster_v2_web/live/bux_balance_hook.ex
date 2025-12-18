defmodule BlocksterV2Web.BuxBalanceHook do
  @moduledoc """
  LiveView on_mount hook to manage BUX balance display in the header.

  - Fetches the initial on-chain BUX balance from Mnesia
  - Subscribes to PubSub updates when balance changes after minting
  - Updates the bux_balance assign when new balance is broadcast
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

    # Subscribe to balance updates for this user (only if connected and logged in)
    if connected?(socket) && user_id do
      Phoenix.PubSub.subscribe(@pubsub, "#{@topic_prefix}#{user_id}")
    end

    socket =
      socket
      |> assign(:bux_balance, initial_balance)
      |> attach_hook(:bux_balance_updates, :handle_info, fn
        {:bux_balance_updated, new_balance}, socket ->
          {:halt, assign(socket, :bux_balance, new_balance)}

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
end
