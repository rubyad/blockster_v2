defmodule BlocksterV2Web.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use BlocksterV2Web, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
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
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Renders the site header with navigation.
  """
  attr :current_user, :any, default: nil, doc: "the current logged in user"
  attr :search_query, :string, default: "", doc: "the current search query"
  attr :search_results, :list, default: [], doc: "the search results"
  attr :show_search_results, :boolean, default: false, doc: "whether to show the search dropdown"
  attr :bux_balance, :any, default: 0, doc: "the user's on-chain BUX balance from Mnesia"
  attr :token_balances, :map, default: %{}, doc: "the user's individual token balances"
  attr :show_categories, :boolean, default: false, doc: "whether to show the categories row"
  attr :show_mobile_search, :boolean, default: false, doc: "whether to show the mobile search bar"
  attr :header_token, :string, default: "BUX", doc: "token to display in header (BUX or ROGUE)"

  def site_header(assigns) do
    # Get the selected token balance and logo (defaults to BUX)
    token = assigns.header_token || "BUX"
    balance = Map.get(assigns.token_balances || %{}, token, 0)
    formatted_balance = Number.Currency.number_to_currency(balance, unit: "", precision: 2)
    token_logo = if token == "ROGUE" do
      "https://ik.imagekit.io/blockster/rogue-white-in-indigo-logo.png"
    else
      "https://ik.imagekit.io/blockster/blockster-icon.png"
    end
    assigns = assigns
      |> assign(:formatted_bux_balance, formatted_balance)
      |> assign(:display_token, token)
      |> assign(:token_logo, token_logo)

    ~H"""
    <!-- Fixed Header Container with ThirdwebWallet for silent wallet initialization -->
    <div
      id="site-header"
      phx-hook="ThirdwebWallet"
      data-user-wallet={if @current_user, do: @current_user.wallet_address}
      data-smart-wallet={if @current_user, do: @current_user.smart_wallet_address}
      class="fixed top-0 left-0 right-0 w-full z-50 bg-white shadow-sm transition-all duration-300"
    >
      <!-- Desktop Header -->
      <header id="desktop-header" class="hidden lg:block pt-6 transition-all duration-300">
        <!-- Top Row: Logo centered (shrinks on scroll) -->
        <div id="header-logo-row" class="flex justify-center py-0.5 pb-4 mb-2 transition-all duration-300 overflow-hidden border-b border-gray-200" style="max-height: 68px; opacity: 1;">
          <div class="flex flex-col items-center">
            <.link navigate={~p"/"} class="block">
              <img id="header-logo" src="https://ik.imagekit.io/blockster/blockster-logo.png" alt="Blockster" class="h-7 transition-all duration-300" />
            </.link>
            <p id="header-tagline" class="uppercase font-extralight text-xs text-black tracking-[0.4em] mt-0.5 transition-all duration-300">
              Web3 Media Platform
            </p>
          </div>
        </div>

        <!-- Navigation Row: Search left, Menu centered, Balance right -->
        <div class="max-w-7xl mx-auto px-4 pb-2">
          <div class="flex items-center">
          <!-- Search Bar with Scroll Logo - Left (flex-1 for equal width with right side) -->
          <div class="flex items-center gap-3 flex-1">
            <div class="relative" id="search-container" phx-click-away={if @show_search_results, do: "close_search", else: nil}>
            <!-- Lightning Bolt Logo (hidden by default, shows on scroll, positioned right of search) -->
            <.link navigate={~p"/"} id="scroll-logo" class="absolute -right-12 top-1/2 -translate-y-1/2 cursor-pointer opacity-0 transition-opacity duration-300 z-20 pointer-events-none">
              <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="Blockster" class="h-8 w-8" />
            </.link>
            <div class="input-wrapper relative">
              <span class="absolute left-3 top-1/2 -translate-y-1/2 z-10">
                <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 14 14" fill="none">
                  <path d="M11.25 12.25L8.74167 9.74167M10.0833 6.41667C10.0833 8.994 7.994 11.0833 5.41667 11.0833C2.83934 11.0833 0.75 8.994 0.75 6.41667C0.75 3.83934 2.83934 1.75 5.41667 1.75C7.994 1.75 10.0833 3.83934 10.0833 6.41667Z"
                        stroke="#101C36" stroke-opacity="0.5" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
                </svg>
              </span>
              <input
                type="text"
                placeholder="Search"
                value={@search_query}
                phx-keyup="search_posts"
                phx-debounce="300"
                class="text-left text-grey-30 h-10 px-4 pl-9 bg-[#F5F6FB] text-sm font-haas_roman_55 w-[180px] rounded-full border border-[#E8EAEC]"
              />
              <!-- Search Results Dropdown -->
              <%= if @show_search_results && length(@search_results) > 0 do %>
                <div class="absolute top-full left-0 mt-2 w-[400px] bg-white rounded-2xl border border-[#E7E8F1] shadow-xl z-50 max-h-[500px] overflow-y-auto">
                  <div class="py-2">
                    <%= for post <- @search_results do %>
                      <.link
                        navigate={~p"/#{post.slug}"}
                        class="flex items-start gap-3 px-4 py-3 hover:bg-[#F5F6FB] transition-colors cursor-pointer"
                      >
                        <div class="img-wrapper rounded-lg overflow-hidden shrink-0" style="width: 60px; height: 60px;">
                          <img src={post.featured_image} class="object-cover w-full h-full" alt="" />
                        </div>
                        <div class="flex-1 min-w-0">
                          <h4 class="text-sm font-haas_medium_65 text-[#141414] line-clamp-2">
                            <%= post.title %>
                          </h4>
                          <%= if post.category do %>
                            <span class="inline-block mt-1 px-2 py-0.5 bg-[#F3F5FF] text-[#515B70] rounded-full text-xs font-haas_medium_65">
                              <%= post.category.name %>
                            </span>
                          <% end %>
                        </div>
                      </.link>
                    <% end %>
                  </div>
                </div>
              <% end %>
            </div>
          </div>
          </div>

          <!-- Navigation Links - Centered -->
          <nav class="flex items-center gap-1">
            <.link navigate={~p"/"} class="px-4 py-2 font-haas_medium_65 text-[14px] text-[#101D36] uppercase hover:opacity-70 transition-opacity">News</.link>
            <.link navigate={~p"/hubs"} class="px-4 py-2 font-haas_medium_65 text-[14px] text-[#101D36] uppercase hover:opacity-70 transition-opacity">Hubs</.link>
            <.link navigate={~p"/shop"} class="px-4 py-2 font-haas_medium_65 text-[14px] text-[#101D36] uppercase hover:opacity-70 transition-opacity">Shop</.link>
            <.link navigate={~p"/airdrop"} class="px-4 py-2 font-haas_medium_65 text-[14px] text-[#101D36] uppercase hover:opacity-70 transition-opacity">Airdrop</.link>
            <.link navigate={~p"/play"} class="px-4 py-2 font-haas_medium_65 text-[14px] text-[#101D36] uppercase hover:opacity-70 transition-opacity cursor-pointer">Play</.link>
          </nav>

          <!-- Balance/User - Right (flex-1 for equal width with left side) -->
          <div class="flex items-center gap-2 flex-1 justify-end">
            <%= if @current_user do %>
              <!-- Logged in user display with dropdown -->
              <div class="relative" id="desktop-user-dropdown" phx-click-away={JS.hide(to: "#desktop-dropdown-menu")}>
                <button id="desktop-user-button" phx-click={JS.toggle(to: "#desktop-dropdown-menu")} class="flex items-center gap-2 h-10 rounded-full bg-gray-100 pl-2 pr-3 hover:bg-gray-200 transition-colors cursor-pointer">
                  <img src={@token_logo} alt={@display_token} class="w-6 h-6 rounded-full" />
                  <span class="text-base font-haas_medium_65 text-[#000000]">{@formatted_bux_balance} <span class="text-sm text-gray-500">{@display_token}</span></span>
                  <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" class="ml-1">
                    <path d="M8 10L12 14L16 10" stroke="#101C36" stroke-width="1.5" stroke-linecap="square" />
                  </svg>
                </button>
                <!-- Dropdown menu -->
                <div id="desktop-dropdown-menu" class="absolute right-0 mt-2 w-48 bg-white rounded-lg shadow-lg border border-gray-200 hidden z-50">
                  <div class="py-1">
                    <a
                    href={"https://roguescan.io/address/#{@current_user.smart_wallet_address || @current_user.wallet_address}?tab=tokens"}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors cursor-pointer"
                  >
                    <div class="font-semibold">Wallet</div>
                    <div class="text-xs text-gray-500">{String.slice(@current_user.smart_wallet_address || @current_user.wallet_address || "", 0..5)}...{String.slice(@current_user.smart_wallet_address || @current_user.wallet_address || "", -4..-1//1)}</div>
                  </a>
                    <!-- Token Balances (BUX and ROGUE only - hub tokens removed) -->
                    <%= if assigns[:token_balances] && map_size(@token_balances) > 0 do %>
                      <div class="border-t border-gray-100 py-1">
                        <%
                          # Only show ROGUE and BUX (hub tokens removed)
                          rogue_balance = Map.get(@token_balances, "ROGUE", 0)
                          bux_balance = Map.get(@token_balances, "BUX", 0)
                          display_tokens = [{"ROGUE", rogue_balance}, {"BUX", bux_balance}]
                        %>
                        <%= for {token_name, balance} <- display_tokens do %>
                          <div class="flex items-center justify-between px-4 py-1.5 text-xs text-gray-600">
                            <div class="flex items-center gap-2">
                              <% logo_url = BlocksterV2.HubLogoCache.get_logo(token_name) %>
                              <%= if logo_url do %>
                                <img src={logo_url} alt={token_name} class="w-4 h-4 rounded-full object-cover" />
                              <% else %>
                                <div class="w-4 h-4 rounded-full bg-indigo-500 flex items-center justify-center">
                                  <span class="text-white text-[8px] font-bold">{String.first(token_name)}</span>
                                </div>
                              <% end %>
                              <span class="font-medium">{token_name}</span>
                            </div>
                            <span>{Number.Delimit.number_to_delimited(balance, precision: 2)}</span>
                          </div>
                        <% end %>
                      </div>
                    <% end %>
                    <div class="border-t border-gray-100"></div>
                    <.link
                      navigate={~p"/member/#{@current_user.slug || @current_user.smart_wallet_address}"}
                      class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                    >
                      View Profile
                    </.link>
                    <button
                      onclick="window.handleWalletDisconnect()"
                      class="w-full text-left px-4 py-2 text-sm text-red-600 hover:bg-red-50 transition-colors cursor-pointer"
                    >
                      Disconnect Wallet
                    </button>
                    <%= if @current_user.is_author || @current_user.is_admin do %>
                      <div class="border-t border-gray-100 my-1"></div>
                      <div class="px-4 py-1 text-xs text-gray-400 font-semibold uppercase">Admin</div>
                      <.link
                        navigate={~p"/new"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Create Article
                      </.link>
                      <%= if @current_user.is_admin do %>
                        <.link
                          navigate={~p"/admin"}
                          class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                        >
                          Dashboard
                        </.link>
                        <.link
                          navigate={~p"/admin/posts"}
                          class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                        >
                          Posts
                        </.link>
                        <.link
                          navigate={~p"/admin/events"}
                          class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                        >
                          Events
                        </.link>
                        <.link
                          navigate={~p"/admin/campaigns"}
                          class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                        >
                          Campaigns
                        </.link>
                        <.link
                          navigate={~p"/admin/categories"}
                          class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                        >
                          Categories
                        </.link>
                        <.link
                          navigate={~p"/hubs/admin"}
                          class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                        >
                          Hubs
                        </.link>
                        <.link
                          navigate={~p"/admin/products"}
                          class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                        >
                          Products
                        </.link>
                        <.link
                          navigate={~p"/admin/product-categories"}
                          class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                        >
                          Product Categories
                        </.link>
                        <.link
                          navigate={~p"/admin/product-tags"}
                          class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                        >
                          Product Tags
                        </.link>
                        <.link
                          navigate={~p"/admin/artists"}
                          class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                        >
                          Artists
                        </.link>
                        <.link
                          navigate={~p"/admin/waitlist"}
                          class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                        >
                          Waitlist
                        </.link>
                        <.link
                          navigate={~p"/admin/flagged-accounts"}
                          class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                        >
                          Flagged Accounts
                        </.link>
                        <.link
                          navigate={~p"/admin/stats"}
                          class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                        >
                          Bet Stats
                        </.link>
                      <% end %>
                    <% end %>
                  </div>
                </div>
              </div>
            <% else %>
              <!-- ThirdwebLogin nested LiveView -->
              <.live_component module={BlocksterV2Web.ThirdwebLoginLive} id="thirdweb-login-desktop" />
            <% end %>
          </div>
          </div>
        </div>

        <!-- Category Row -->
        <%= if @show_categories do %>
          <div class="border-t border-gray-200 py-2.5 bg-gray-50">
            <div class="max-w-7xl mx-auto px-4 flex items-center justify-center gap-4 overflow-x-auto">
              <.link navigate={~p"/category/blockchain"} class="text-sm font-haas_roman_55 text-black hover:opacity-70 whitespace-nowrap transition-opacity leading-none">Blockchain</.link>
              <span class="text-gray-300">|</span>
              <.link navigate={~p"/category/investment"} class="text-sm font-haas_roman_55 text-black hover:opacity-70 whitespace-nowrap transition-opacity leading-none">Investment</.link>
              <span class="text-gray-300">|</span>
              <.link navigate={~p"/category/crypto-trading"} class="text-sm font-haas_roman_55 text-black hover:opacity-70 whitespace-nowrap transition-opacity leading-none">Trading</.link>
              <span class="text-gray-300">|</span>
              <.link navigate={~p"/category/people"} class="text-sm font-haas_roman_55 text-black hover:opacity-70 whitespace-nowrap transition-opacity leading-none">People</.link>
              <span class="text-gray-300">|</span>
              <.link navigate={~p"/category/defi"} class="text-sm font-haas_roman_55 text-black hover:opacity-70 whitespace-nowrap transition-opacity leading-none">DeFi</.link>
              <span class="text-gray-300">|</span>
              <.link navigate={~p"/category/ai"} class="text-sm font-haas_roman_55 text-black hover:opacity-70 whitespace-nowrap transition-opacity leading-none">AI</.link>
              <span class="text-gray-300">|</span>
              <.link navigate={~p"/category/rwa"} class="text-sm font-haas_roman_55 text-black hover:opacity-70 whitespace-nowrap transition-opacity leading-none">RWA</.link>
              <span class="text-gray-300">|</span>
              <.link navigate={~p"/category/events"} class="text-sm font-haas_roman_55 text-black hover:opacity-70 whitespace-nowrap transition-opacity leading-none">Events</.link>
            </div>
          </div>
        <% end %>
      </header>

      <!-- Mobile Header -->
      <div class="mobile-header border border-[#E7E8F1] p-3 flex items-center justify-between bg-white lg:hidden" id="mobile-header-search">
      <!-- Default state: Logo and buttons (hidden when search is open) -->
      <div class={"no-search-wrapper flex justify-between items-center w-full #{if @show_mobile_search, do: "hidden", else: ""}"}>
        <div>
          <.link navigate={~p"/"}>
            <img src="/images/Logo.png" alt="Blockster" />
          </.link>
        </div>
        <div class="flex gap-2 items-center">
          <button phx-click="open_mobile_search" class="search-trigger w-8 h-8 flex items-center justify-center text-gray-500 rounded-full bg-[#F3F5FF] shadow-md cursor-pointer">
            <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 20 19" fill="none">
              <path d="M17 16.5L13.6556 13.1556M15.4444 8.72222C15.4444 12.1587 12.6587 14.9444 9.22222 14.9444C5.78578 14.9444 3 12.1587 3 8.72222C3 5.28578 5.78578 2.5 9.22222 2.5C12.6587 2.5 15.4444 5.28578 15.4444 8.72222Z"
                    stroke="#101C36" stroke-opacity="0.5" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
            </svg>
          </button>
          <%= if @current_user do %>
            <!-- Mobile logged in user with dropdown -->
            <div class="relative" id="mobile-user-dropdown" phx-click-away={JS.hide(to: "#mobile-dropdown-menu")}>
              <button id="mobile-user-button" phx-click={JS.toggle(to: "#mobile-dropdown-menu")} class="flex items-center gap-2 rounded-[100px] bg-bg-light py-1.5 pl-2 pr-2 shadow-sm cursor-pointer">
                <img src={@token_logo} alt={@display_token} class="w-6 h-6 rounded-full" />
                <span class="text-sm font-haas_medium_65 text-[#000000]">{@formatted_bux_balance} <span class="text-gray-500">{@display_token}</span></span>
                <span class="flex items-center transition-all ease-linear duration-500">
                  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none">
                    <path d="M8 10L12 14L16 10" stroke="#101D36" stroke-width="1.5" stroke-linecap="square" />
                  </svg>
                </span>
              </button>
              <!-- Mobile Dropdown menu -->
              <div id="mobile-dropdown-menu" class="absolute right-0 mt-2 w-48 bg-white rounded-lg shadow-lg border border-gray-200 hidden z-50">
                <div class="py-1">
                  <a
                    href={"https://roguescan.io/address/#{@current_user.smart_wallet_address || @current_user.wallet_address}?tab=tokens"}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="block px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors cursor-pointer"
                  >
                    <div class="font-semibold">Wallet</div>
                    <div class="text-xs text-gray-500">{String.slice(@current_user.smart_wallet_address || @current_user.wallet_address || "", 0..5)}...{String.slice(@current_user.smart_wallet_address || @current_user.wallet_address || "", -4..-1//1)}</div>
                  </a>
                  <!-- Token Balances (Mobile) -->
                  <%= if assigns[:token_balances] && map_size(@token_balances) > 0 do %>
                    <%
                      # Only show ROGUE and BUX (hub tokens removed)
                      rogue_balance = Map.get(@token_balances, "ROGUE", 0)
                      bux_balance = Map.get(@token_balances, "BUX", 0)
                      display_tokens = [{"ROGUE", rogue_balance}, {"BUX", bux_balance}]
                    %>
                    <div class="border-t border-gray-100 py-1">
                      <%= for {token_name, balance} <- display_tokens do %>
                        <div class="flex items-center justify-between px-4 py-1.5 text-xs text-gray-600">
                          <div class="flex items-center gap-2">
                            <% logo_url = BlocksterV2.HubLogoCache.get_logo(token_name) %>
                            <%= if logo_url do %>
                              <img src={logo_url} alt={token_name} class="w-4 h-4 rounded-full object-cover" />
                            <% else %>
                              <div class="w-4 h-4 rounded-full bg-indigo-500 flex items-center justify-center">
                                <span class="text-white text-[8px] font-bold">{String.first(token_name)}</span>
                              </div>
                            <% end %>
                            <span class="font-medium">{token_name}</span>
                          </div>
                          <span>{Number.Delimit.number_to_delimited(balance, precision: 2)}</span>
                        </div>
                      <% end %>
                    </div>
                  <% end %>
                  <div class="border-t border-gray-100"></div>
                  <.link
                    navigate={~p"/member/#{@current_user.slug || @current_user.smart_wallet_address}"}
                    class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                  >
                    View Profile
                  </.link>
                  <button
                    onclick="window.handleWalletDisconnect()"
                    class="w-full text-left px-4 py-2 text-sm text-red-600 hover:bg-red-50 transition-colors cursor-pointer"
                  >
                    Disconnect Wallet
                  </button>
                  <%= if @current_user.is_author || @current_user.is_admin do %>
                    <div class="border-t border-gray-100 my-1"></div>
                    <div class="px-4 py-1 text-xs text-gray-400 font-semibold uppercase">Admin</div>
                    <.link
                      navigate={~p"/new"}
                      class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                    >
                      Create Article
                    </.link>
                    <%= if @current_user.is_admin do %>
                      <.link
                        navigate={~p"/admin"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Dashboard
                      </.link>
                      <.link
                        navigate={~p"/admin/posts"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Posts
                      </.link>
                      <.link
                        navigate={~p"/admin/events"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Events
                      </.link>
                      <.link
                        navigate={~p"/admin/campaigns"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Campaigns
                      </.link>
                      <.link
                        navigate={~p"/admin/categories"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Categories
                      </.link>
                      <.link
                        navigate={~p"/hubs/admin"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Hubs
                      </.link>
                      <.link
                        navigate={~p"/admin/products"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Products
                      </.link>
                      <.link
                        navigate={~p"/admin/product-categories"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Product Categories
                      </.link>
                      <.link
                        navigate={~p"/admin/product-tags"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Product Tags
                      </.link>
                      <.link
                        navigate={~p"/admin/artists"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Artists
                      </.link>
                      <.link
                        navigate={~p"/admin/waitlist"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Waitlist
                      </.link>
                      <.link
                        navigate={~p"/admin/flagged-accounts"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Flagged Accounts
                      </.link>
                      <.link
                        navigate={~p"/admin/stats"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Bet Stats
                      </.link>
                    <% end %>
                  <% end %>
                </div>
              </div>
            </div>
          <% else %>
            <!-- Mobile ThirdwebLogin nested LiveView -->
            <.live_component module={BlocksterV2Web.ThirdwebLoginLive} id="thirdweb-login-mobile" />
          <% end %>
        </div>
      </div>
      <!-- Mobile Search Bar (shown when @show_mobile_search is true) -->
      <%= if @show_mobile_search do %>
      <div class="search-mobile w-full">
        <div class="flex items-center gap-2 w-full">
          <div class="relative flex-1">
            <span class="absolute left-3 top-1/2 -translate-y-1/2 z-10">
              <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 14 14" fill="none">
                <path d="M11.25 12.25L8.74167 9.74167M10.0833 6.41667C10.0833 8.994 7.994 11.0833 5.41667 11.0833C2.83934 11.0833 0.75 8.994 0.75 6.41667C0.75 3.83934 2.83934 1.75 5.41667 1.75C7.994 1.75 10.0833 3.83934 10.0833 6.41667Z"
                      stroke="#101C36" stroke-opacity="0.5" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
            </span>
            <input
              type="text"
              placeholder="Search articles..."
              value={@search_query}
              phx-keyup="search_posts"
              phx-debounce="300"
              class="w-full h-10 px-4 pl-9 bg-[#F5F6FB] text-sm font-haas_roman_55 rounded-full border border-[#E8EAEC]"
              id="mobile-search-input"
              autofocus
            />
            <!-- Mobile Search Results Dropdown -->
            <%= if @show_search_results && length(@search_results) > 0 do %>
              <div class="absolute top-full left-0 right-0 mt-2 bg-white rounded-2xl border border-[#E7E8F1] shadow-xl z-50 max-h-[400px] overflow-y-auto">
                <div class="py-2">
                  <%= for post <- @search_results do %>
                    <.link
                      navigate={~p"/#{post.slug}"}
                      class="flex items-start gap-3 px-4 py-3 hover:bg-[#F5F6FB] transition-colors cursor-pointer"
                    >
                      <div class="img-wrapper rounded-lg overflow-hidden shrink-0" style="width: 50px; height: 50px;">
                        <img src={post.featured_image} class="object-cover w-full h-full" alt="" />
                      </div>
                      <div class="flex-1 min-w-0">
                        <h4 class="text-sm font-haas_medium_65 text-[#141414] line-clamp-2">
                          <%= post.title %>
                        </h4>
                        <%= if post.category do %>
                          <span class="inline-block mt-1 px-2 py-0.5 bg-[#F3F5FF] text-[#515B70] rounded-full text-xs font-haas_medium_65">
                            <%= post.category.name %>
                          </span>
                        <% end %>
                      </div>
                    </.link>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
          <button phx-click="close_mobile_search" class="w-8 h-8 flex items-center justify-center text-gray-500 rounded-full bg-[#F3F5FF] cursor-pointer">
            <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <line x1="18" y1="6" x2="6" y2="18"></line>
              <line x1="6" y1="6" x2="18" y2="18"></line>
            </svg>
          </button>
        </div>
      </div>
      <% end %>
    </div>
    </div>
    <!-- Spacer to push content below fixed header -->
    <div class="h-20 lg:h-24"></div>
    """
  end

  @doc """
  Renders the site footer.
  """
  def site_footer(assigns) do
    ~H"""
    <footer class="bg-[#141414] text-white py-12 md:py-16">
      <div class="container mx-auto px-6">
        <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-5 gap-8 mb-12">
          <!-- Logo and Description -->
          <div class="lg:col-span-2">
            <div class="mb-6">
              <img src="/images/logo-footer.png" alt="Blockster" class="h-8" />
            </div>
            <p class="text-sm font-haas_roman_55 text-[#E8EAEC] leading-relaxed max-w-sm">
              Web3's Daily Content Hub—Earn $BUX, redeem rewards, and stay plugged into crypto, blockchain, and the future of finance.
            </p>
            <!-- Social Links -->
            <div class="flex gap-4 mt-6">
              <a href="#" class="w-10 h-10 bg-white/10 rounded-full flex items-center justify-center hover:bg-white/20 transition-colors">
                <span class="text-white font-bold">𝕏</span>
              </a>
              <a href="#" class="w-10 h-10 bg-white/10 rounded-full flex items-center justify-center hover:bg-white/20 transition-colors">
                <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="white">
                  <path d="M19 0h-14c-2.761 0-5 2.239-5 5v14c0 2.761 2.239 5 5 5h14c2.762 0 5-2.239 5-5v-14c0-2.761-2.238-5-5-5zm-11 19h-3v-11h3v11zm-1.5-12.268c-.966 0-1.75-.79-1.75-1.764s.784-1.764 1.75-1.764 1.75.79 1.75 1.764-.783 1.764-1.75 1.764zm13.5 12.268h-3v-5.604c0-3.368-4-3.113-4 0v5.604h-3v-11h3v1.765c1.396-2.586 7-2.777 7 2.476v6.759z"/>
                </svg>
              </a>
              <a href="#" class="w-10 h-10 bg-white/10 rounded-full flex items-center justify-center hover:bg-white/20 transition-colors">
                <span class="text-white text-sm font-bold">IG</span>
              </a>
            </div>
          </div>

          <!-- Resources Links -->
          <div>
            <h3 class="font-haas_bold_75 text-white mb-4">Resources</h3>
            <ul class="space-y-3">
              <li><a href="#" class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors">Blog</a></li>
              <li><a href="#" class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors">Help Center</a></li>
              <li><a href="#" class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors">Community</a></li>
              <li><a href="#" class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors">Guides</a></li>
            </ul>
          </div>

          <!-- Blockchain Links -->
          <div>
            <h3 class="font-haas_bold_75 text-white mb-4">Blockchain</h3>
            <ul class="space-y-3">
              <li><a href="#" class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors">Bitcoin</a></li>
              <li><a href="#" class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors">Ethereum</a></li>
              <li><a href="#" class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors">Solana</a></li>
              <li><a href="#" class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors">All Chains</a></li>
            </ul>
          </div>

          <!-- Newsletter -->
          <div>
            <h3 class="font-haas_bold_75 text-white mb-4">Newsletter</h3>
            <p class="text-sm font-haas_roman_55 text-[#E8EAEC] mb-4">
              Stay updated with the latest in crypto
            </p>
            <form class="flex gap-2">
              <input
                type="email"
                name="email"
                placeholder="Enter email"
                class="flex-1 px-4 py-2 bg-white/10 border border-white/20 rounded-[100px] text-sm text-white placeholder:text-white/50 focus:outline-none focus:border-white/40"
                required
              />
              <button
                type="submit"
                class="px-4 py-2 bg-white text-[#141414] font-haas_bold_75 rounded-[100px] text-sm hover:bg-[#E8EAEC] transition-colors"
              >
                →
              </button>
            </form>
          </div>
        </div>

        <!-- Bottom Bar -->
        <div class="border-t border-white/10 pt-8">
          <div class="flex flex-col md:flex-row justify-between items-center gap-4">
            <p class="text-sm font-haas_roman_55 text-[#E8EAEC]">
              © 2025 Blockster. All rights reserved.
            </p>
            <div class="flex gap-6">
              <a href="#" class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors">Privacy Policy</a>
              <a href="#" class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors">Terms of Service</a>
              <a href="#" class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors">Cookie Policy</a>
            </div>
          </div>
        </div>
      </div>
    </footer>
    """
  end
end
