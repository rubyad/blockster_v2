defmodule BlocksterV2Web.UserAuth do
  @moduledoc """
  Handles mounting and authenticating the current_user in LiveViews.

  Solana wallet session is the only auth path. Legacy EVM user_token sessions
  are ignored — users must connect a Solana wallet to authenticate.

  See `docs/auth_session_contract.md` for the full session-key contract
  and the GLOBAL-01 flash-bug diagnosis notes.
  """

  import Phoenix.Component
  import Phoenix.LiveView

  alias BlocksterV2.Accounts
  alias BlocksterV2.EngagementTracker
  alias BlocksterV2.BuxMinter

  require Logger

  # Flip to true when diagnosing GLOBAL-01 auth-flash reports. Each
  # on_mount call logs the mount phase + session keys + connect_params
  # keys + resolved user id. Verbose; leave off in prod.
  @debug_auth System.get_env("BLOCKSTER_DEBUG_AUTH") == "1"

  def on_mount(:default, _params, session, socket) do
    log_auth_debug("on_mount:default", session, socket)
    socket = mount_current_user(socket, session)
    socket = sync_balances_on_nav(socket)
    {:cont, socket}
  end

  # GLOBAL-01 instrumentation. Gated by BLOCKSTER_DEBUG_AUTH=1 so
  # default-on prod traffic doesn't log PII. Surfaces the exact session
  # keys + connect_params visible to UserAuth, which is the data we'd
  # need to confirm the static-mount vs connected-mount asymmetry.
  defp log_auth_debug(_, _, _) when not @debug_auth, do: :ok

  defp log_auth_debug(phase, session, socket) do
    session_keys = session |> Map.keys() |> Enum.sort()
    wallet = session["wallet_address"]
    user_id = socket.assigns[:current_user] && socket.assigns.current_user.id

    connect_keys =
      if connected?(socket) do
        case get_connect_params(socket) do
          %{} = params -> params |> Map.keys() |> Enum.sort()
          _ -> []
        end
      else
        nil
      end

    Logger.debug(
      "[UserAuth #{phase}] connected?=#{connected?(socket)} session_keys=#{inspect(session_keys)} wallet=#{wallet_prefix(wallet)} connect_keys=#{inspect(connect_keys)} user_id=#{inspect(user_id)}"
    )
  end

  defp wallet_prefix(nil), do: "<nil>"
  defp wallet_prefix(addr) when is_binary(addr) and byte_size(addr) > 8,
    do: "#{String.slice(addr, 0, 4)}…#{String.slice(addr, -4, 4)}"

  defp wallet_prefix(addr), do: inspect(addr)

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
