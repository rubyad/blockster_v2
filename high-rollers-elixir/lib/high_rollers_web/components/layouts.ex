defmodule HighRollersWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use HighRollersWeb, :html

  # Embed all files in layouts/* within this module.
  embed_templates "layouts/*"

  # NOTE: The app/1 function is now generated automatically by embed_templates
  # from app.html.heex. The template uses @inner_content (not @inner_block)
  # because it's used via the router's layout: option.

  @doc """
  Tab navigation component.
  """
  attr :current_path, :string, required: true
  attr :wallet_connected, :boolean, default: false

  def tab_nav(assigns) do
    ~H"""
    <nav class="bg-gray-800 border-b border-gray-700 sticky top-0 z-40">
      <div class="container mx-auto flex overflow-x-auto">
        <.tab_button path="/" label="Mint" current={@current_path} />
        <.tab_button path="/sales" label="Live Sales" current={@current_path} />
        <.tab_button path="/affiliates" label="Affiliates" current={@current_path} />
        <%= if @wallet_connected do %>
          <.tab_button path="/my-nfts" label="My NFTs" current={@current_path} />
        <% end %>
        <.tab_button path="/revenues" label="My Earnings" current={@current_path} />
      </div>
    </nav>
    """
  end

  attr :path, :string, required: true
  attr :label, :string, required: true
  attr :current, :string, required: true

  defp tab_button(assigns) do
    # Normalize paths for comparison (/ and /mint are same tab)
    current = if assigns.current in ["/", "/mint"], do: "/", else: assigns.current
    path = if assigns.path in ["/", "/mint"], do: "/", else: assigns.path
    active = current == path

    assigns = assign(assigns, :active, active)

    ~H"""
    <.link
      navigate={@path}
      class={[
        "px-6 py-4 cursor-pointer whitespace-nowrap transition-colors",
        @active && "text-purple-400 border-b-2 border-purple-400",
        !@active && "text-gray-400 hover:text-white"
      ]}
    >
      <%= @label %>
    </.link>
    """
  end

  @doc """
  Wallet connection modal.
  """
  def wallet_modal(assigns) do
    ~H"""
    <div
      id="wallet-modal"
      class="fixed inset-0 bg-black/80 z-50 hidden items-center justify-center p-4"
      phx-click={hide_modal("wallet-modal")}
    >
      <div class="bg-gray-800 rounded-xl p-6 max-w-md w-full" phx-click-away={hide_modal("wallet-modal")}>
        <h2 class="text-xl font-bold mb-4">Connect Wallet</h2>
        <p class="text-gray-400 mb-6">Select your preferred wallet to continue</p>

        <div class="space-y-3" id="wallet-options">
          <!-- MetaMask -->
          <button
            class="wallet-option w-full flex items-center gap-4 p-4 bg-gray-700 hover:bg-gray-600 rounded-lg cursor-pointer transition-colors"
            data-wallet="metamask"
          >
            <img src="/images/wallets/metamask.svg" alt="MetaMask" class="w-10 h-10" />
            <div class="text-left">
              <p class="font-bold">MetaMask</p>
              <p class="text-sm text-gray-400">Connect using browser extension</p>
            </div>
          </button>
          <!-- Coinbase Wallet -->
          <button
            class="wallet-option w-full flex items-center gap-4 p-4 bg-gray-700 hover:bg-gray-600 rounded-lg cursor-pointer transition-colors"
            data-wallet="coinbase"
          >
            <img src="/images/wallets/coinbase.svg" alt="Coinbase Wallet" class="w-10 h-10" />
            <div class="text-left">
              <p class="font-bold">Coinbase Wallet</p>
              <p class="text-sm text-gray-400">Connect using Coinbase Wallet</p>
            </div>
          </button>
          <!-- Rabby -->
          <button
            class="wallet-option w-full flex items-center gap-4 p-4 bg-gray-700 hover:bg-gray-600 rounded-lg cursor-pointer transition-colors"
            data-wallet="rabby"
          >
            <img src="/images/wallets/rabby.svg" alt="Rabby" class="w-10 h-10" />
            <div class="text-left">
              <p class="font-bold">Rabby</p>
              <p class="text-sm text-gray-400">The game changing wallet for DeFi</p>
            </div>
          </button>
          <!-- Trust Wallet -->
          <button
            class="wallet-option w-full flex items-center gap-4 p-4 bg-gray-700 hover:bg-gray-600 rounded-lg cursor-pointer transition-colors"
            data-wallet="trust"
          >
            <img src="/images/wallets/trust.svg" alt="Trust Wallet" class="w-10 h-10" />
            <div class="text-left">
              <p class="font-bold">Trust Wallet</p>
              <p class="text-sm text-gray-400">Connect using Trust Wallet</p>
            </div>
          </button>
        </div>

        <button
          id="close-wallet-modal"
          class="mt-4 w-full py-2 text-gray-400 hover:text-white cursor-pointer transition-colors"
          phx-click={hide_modal("wallet-modal")}
        >
          Cancel
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="fixed top-4 right-4 z-50 space-y-2">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="Connection Lost"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect...
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect...
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  # ===== PUBLIC HELPERS (used by app.html.heex template) =====

  @doc "Truncate wallet address for display"
  def truncate_address(nil), do: ""
  def truncate_address(address) when byte_size(address) < 10, do: address

  def truncate_address(address) do
    String.slice(address, 0, 6) <> "..." <> String.slice(address, -4, 4)
  end

  @doc "Show modal JS command"
  def show_modal(id) do
    JS.remove_class("hidden", to: "##{id}")
    |> JS.add_class("flex", to: "##{id}")
  end

  @doc "Hide modal JS command"
  def hide_modal(id) do
    JS.add_class("hidden", to: "##{id}")
    |> JS.remove_class("flex", to: "##{id}")
  end

  @doc "Get wallet logo URL"
  def wallet_logo_url(nil), do: ""
  def wallet_logo_url("metamask"), do: "/images/wallets/metamask.svg"
  def wallet_logo_url("coinbase"), do: "/images/wallets/coinbase.svg"
  def wallet_logo_url("rabby"), do: "/images/wallets/rabby.svg"
  def wallet_logo_url("trust"), do: "/images/wallets/trust.svg"
  def wallet_logo_url("brave"), do: "/images/wallets/brave.svg"
  def wallet_logo_url(_), do: "/images/wallets/generic.svg"

  @doc "Get chain logo URL"
  def chain_logo_url("rogue"), do: "https://ik.imagekit.io/blockster/rogue-white-in-indigo-logo.png"
  def chain_logo_url(_), do: "https://ik.imagekit.io/blockster/arbitrum-logo.png"

  @doc "Get chain currency symbol"
  def chain_currency("rogue"), do: "ROGUE"
  def chain_currency(_), do: "ETH"

  @doc """
  Format balance for display (handles nil, string, and number)
  ETH: 6 decimal places
  ROGUE: 2 decimal places with comma delimiters
  """
  def format_balance(balance, chain \\ "arbitrum")

  def format_balance(nil, "rogue"), do: "0.00"
  def format_balance(nil, _chain), do: "0.000000"

  def format_balance(balance, chain) when is_binary(balance) do
    case Float.parse(balance) do
      {num, _} -> format_number(num, chain)
      :error -> balance
    end
  end

  def format_balance(balance, chain) when is_number(balance) do
    format_number(balance * 1.0, chain)
  end

  defp format_number(num, "rogue") do
    # ROGUE: 2 decimals with comma delimiters
    formatted = :erlang.float_to_binary(num, decimals: 2)
    add_commas(formatted)
  end

  defp format_number(num, _chain) do
    # ETH: 6 decimals, no comma delimiters
    :erlang.float_to_binary(num, decimals: 6)
  end

  defp add_commas(number_string) do
    [integer_part | decimal_parts] = String.split(number_string, ".")
    integer_with_commas =
      integer_part
      |> String.reverse()
      |> String.to_charlist()
      |> Enum.chunk_every(3)
      |> Enum.join(",")
      |> String.reverse()

    case decimal_parts do
      [] -> integer_with_commas
      [decimal] -> "#{integer_with_commas}.#{decimal}"
    end
  end
end
