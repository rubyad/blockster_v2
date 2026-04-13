defmodule BlocksterV2Web.UserAuth do
  @moduledoc """
  Handles mounting and authenticating the current_user in LiveViews.

  Solana wallet session is the only auth path. Legacy EVM user_token sessions
  are ignored — users must connect a Solana wallet to authenticate.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias BlocksterV2.Accounts
  alias BlocksterV2.EngagementTracker
  alias BlocksterV2.BuxMinter

  def on_mount(:default, _params, session, socket) do
    socket = mount_current_user(socket, session)
    socket = sync_balances_on_nav(socket)
    {:cont, socket}
  end

  defp mount_current_user(socket, session) do
    socket =
      Phoenix.Component.assign_new(socket, :current_user, fn ->
        # Solana wallet session only — ignore legacy EVM user_token
        restore_from_wallet(socket, session)
      end)
      |> assign_wallet_address(session)

    # Attach wallet_authenticated handler via lifecycle hook (only on first mount)
    if !socket.assigns[:__wallet_auth_hooked__] &&
       function_exported?(socket.view, :__wallet_auth_attach_hook__, 1) do
      socket.view.__wallet_auth_attach_hook__(socket)
      |> Phoenix.Component.assign(:__wallet_auth_hooked__, true)
    else
      socket
    end
  end

  # Restore user from wallet_address in session cookie
  defp restore_from_wallet(socket, session) do
    wallet = session["wallet_address"] || get_wallet_from_connect_params(socket)

    case wallet do
      nil -> nil
      address -> Accounts.get_user_by_wallet_address(address)
    end
  end

  # On connected mount, check connect_params for wallet from localStorage
  defp get_wallet_from_connect_params(socket) do
    if connected?(socket) do
      case get_connect_params(socket) do
        %{"wallet_address" => addr} when is_binary(addr) and addr != "" -> addr
        _ -> nil
      end
    else
      nil
    end
  end

  # Sync balances on every LiveView navigation for logged-in users
  defp sync_balances_on_nav(socket) do
    user = socket.assigns[:current_user]

    if user && connected?(socket) && user.wallet_address do
      BuxMinter.sync_user_balances_async(user.id, user.wallet_address)
      token_balances = EngagementTracker.get_user_token_balances(user.id)
      assign(socket, :token_balances, token_balances)
    else
      socket
    end
  end

  # Assign wallet_address and default wallet UI assigns for templates
  defp assign_wallet_address(socket, session) do
    wallet = session["wallet_address"] || get_wallet_from_connect_params(socket)

    socket
    |> assign(:wallet_address, wallet)
    |> assign_new(:detected_wallets, fn -> [] end)
    |> assign_new(:show_wallet_selector, fn -> false end)
    |> assign_new(:connecting, fn -> false end)
    |> assign_new(:connecting_wallet_name, fn -> nil end)
    |> assign_new(:auth_challenge, fn -> nil end)
  end
end
