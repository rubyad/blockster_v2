defmodule BlocksterV2Web.UserAuth do
  @moduledoc """
  Handles mounting and authenticating the current_user in LiveViews.

  Solana wallet session is the only auth path. Legacy EVM user_token sessions
  are ignored — users must connect a Solana wallet to authenticate.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias BlocksterV2.Accounts

  def on_mount(:default, _params, session, socket) do
    {:cont, mount_current_user(socket, session)}
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

  # Assign wallet_address and default wallet UI assigns for templates
  defp assign_wallet_address(socket, session) do
    wallet = session["wallet_address"] || get_wallet_from_connect_params(socket)

    socket
    |> assign(:wallet_address, wallet)
    |> assign_new(:detected_wallets, fn -> [] end)
    |> assign_new(:show_wallet_selector, fn -> false end)
    |> assign_new(:connecting, fn -> false end)
    |> assign_new(:auth_challenge, fn -> nil end)
  end
end
