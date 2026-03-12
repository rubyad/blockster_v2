defmodule HighRollersWeb.SolanaWalletLive do
  @moduledoc """
  LiveView for the FateSwap / Solana wallet registration tab.

  Allows NFT holders to register their Solana wallet address to receive
  revenue sharing from FateSwap.io (Solana DEX gambling game).
  """
  use HighRollersWeb, :live_view
  require Logger

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:current_path, "/solana")
      |> assign(:solana_address, nil)
      |> assign(:solana_input, "")
      |> assign(:save_status, nil)
      |> assign(:validation_error, nil)
      |> assign(:editing, false)
      |> HighRollersWeb.WalletHook.set_page_chain("arbitrum")

    # Load saved Solana wallet if EVM wallet is connected
    socket =
      if socket.assigns[:wallet_connected] && socket.assigns[:wallet_address] do
        load_solana_wallet(socket, socket.assigns.wallet_address)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("wallet_connected", %{"address" => address}, socket) do
    socket = load_solana_wallet(socket, String.downcase(address))
    {:noreply, socket}
  end

  @impl true
  def handle_event("wallet_disconnected", _params, socket) do
    {:noreply,
     socket
     |> assign(:solana_address, nil)
     |> assign(:solana_input, "")
     |> assign(:save_status, nil)
     |> assign(:editing, false)}
  end

  @impl true
  def handle_event("balance_updated", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("validate_solana", %{"solana_address" => value}, socket) do
    {:noreply,
     socket
     |> assign(:solana_input, value)
     |> assign(:validation_error, nil)
     |> assign(:save_status, nil)}
  end

  @impl true
  def handle_event("save_solana", %{"solana_address" => address}, socket) do
    wallet_address = socket.assigns[:wallet_address]
    trimmed = String.trim(address)

    cond do
      is_nil(wallet_address) ->
        {:noreply, assign(socket, :validation_error, "Please connect your wallet first")}

      trimmed == "" ->
        {:noreply, assign(socket, :validation_error, "Please enter a Solana wallet address")}

      not valid_solana_address?(trimmed) ->
        {:noreply, assign(socket, :validation_error, "Invalid Solana address. Must be 32-44 base58 characters.")}

      true ->
        case HighRollers.Users.set_solana_wallet(wallet_address, trimmed) do
          {:ok, saved_address} ->
            {:noreply,
             socket
             |> assign(:solana_address, saved_address)
             |> assign(:solana_input, saved_address)
             |> assign(:save_status, :saved)
             |> assign(:validation_error, nil)
             |> assign(:editing, false)}

          _ ->
            {:noreply, assign(socket, :validation_error, "Failed to save. Please try again.")}
        end
    end
  end

  @impl true
  def handle_event("edit_solana", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, true)
     |> assign(:solana_input, socket.assigns.solana_address || "")
     |> assign(:save_status, nil)}
  end

  @impl true
  def handle_event("cancel_edit", _params, socket) do
    {:noreply,
     socket
     |> assign(:editing, false)
     |> assign(:solana_input, socket.assigns.solana_address || "")
     |> assign(:validation_error, nil)}
  end

  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  # ===== Private =====

  defp load_solana_wallet(socket, wallet_address) do
    solana = HighRollers.Users.get_solana_wallet(wallet_address)

    socket
    |> assign(:solana_address, solana)
    |> assign(:solana_input, solana || "")
  end

  @base58_chars ~c"123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

  defp valid_solana_address?(address) do
    len = String.length(address)
    len >= 32 and len <= 44 and
      String.to_charlist(address) |> Enum.all?(&(&1 in @base58_chars))
  end

  def truncate_sol(nil), do: ""
  def truncate_sol(address) when byte_size(address) < 12, do: address
  def truncate_sol(address) do
    "#{String.slice(address, 0, 6)}...#{String.slice(address, -6, 6)}"
  end
end
