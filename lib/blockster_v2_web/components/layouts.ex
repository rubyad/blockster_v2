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
  attr :post_category_slug, :string, default: nil, doc: "the current post's category slug for highlighting"
  attr :show_mobile_search, :boolean, default: false, doc: "whether to show the mobile search bar"
  attr :header_token, :string, default: "BUX", doc: "token to display in header (BUX or ROGUE)"
  attr :cart_item_count, :integer, default: 0, doc: "number of items in the user's cart"
  attr :unread_notification_count, :integer, default: 0, doc: "number of unread notifications"
  attr :notification_dropdown_open, :boolean, default: false, doc: "whether the notification dropdown is open"
  attr :recent_notifications, :list, default: [], doc: "recent notifications for dropdown"

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
      |> assign(:hide_mobile_token_name, balance >= 1000)

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
            <div id="header-tagline-container" class="relative mt-0.5" phx-hook="TaglineRotator">
              <p class="tagline-text uppercase font-extralight text-xs text-black tracking-[0.5em] pl-1.5 transition-all duration-500">
                Read & Earn BUX
              </p>
              <p class="tagline-text uppercase font-extralight text-xs text-black tracking-[0.5em] transition-all duration-500 absolute inset-0 opacity-0 whitespace-nowrap flex items-center justify-center">
                Powered by Rogue Chain
              </p>
            </div>
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
          <nav id="desktop-nav" phx-hook="DesktopNavHighlight" class="flex items-center gap-1">
            <.link navigate={~p"/"} data-nav-path="/" class="px-4 py-2 font-haas_medium_65 text-[14px] text-black uppercase rounded-full hover:bg-gray-100 transition-colors">News</.link>
            <.link navigate={~p"/hubs"} data-nav-path="/hubs" class="px-4 py-2 font-haas_medium_65 text-[14px] text-black uppercase rounded-full hover:bg-gray-100 transition-colors">Hubs</.link>
            <.link navigate={~p"/shop"} data-nav-path="/shop" class="px-4 py-2 font-haas_medium_65 text-[14px] text-black uppercase rounded-full hover:bg-gray-100 transition-colors">Shop</.link>
            <.link navigate={~p"/airdrop"} data-nav-path="/airdrop" class="px-4 py-2 font-haas_medium_65 text-[14px] text-black uppercase rounded-full hover:bg-gray-100 transition-colors">Airdrop</.link>
            <.link navigate={~p"/play"} data-nav-path="/play" class="px-4 py-2 font-haas_medium_65 text-[14px] text-black uppercase rounded-full hover:bg-gray-100 transition-colors cursor-pointer">Play</.link>
          </nav>

          <!-- Balance/User - Right (flex-1 for equal width with left side) -->
          <div class="flex items-center gap-2 flex-1 justify-end">
            <%= if @current_user do %>
              <!-- Cart Icon with Badge -->
              <.link navigate={~p"/cart"} class="relative flex items-center justify-center w-10 h-10 rounded-full bg-gray-100 hover:bg-gray-200 transition-colors cursor-pointer">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5 text-[#141414]">
                  <path fill-rule="evenodd" d="M7.5 6v.75H5.513c-.96 0-1.764.724-1.865 1.679l-1.263 12A1.875 1.875 0 0 0 4.25 22.5h15.5a1.875 1.875 0 0 0 1.865-2.071l-1.263-12a1.875 1.875 0 0 0-1.865-1.679H16.5V6a4.5 4.5 0 1 0-9 0ZM12 3a3 3 0 0 0-3 3v.75h6V6a3 3 0 0 0-3-3Zm-3 8.25a3 3 0 1 0 6 0v-.75a.75.75 0 0 1 1.5 0v.75a4.5 4.5 0 1 1-9 0v-.75a.75.75 0 0 1 1.5 0v.75Z" clip-rule="evenodd" />
                </svg>
                <%= if @cart_item_count > 0 do %>
                  <span class="absolute -top-1 -right-1 bg-[#8AE388] text-[#141414] text-xs font-haas_medium_65 rounded-full min-w-[18px] h-[18px] flex items-center justify-center px-1">
                    <%= @cart_item_count %>
                  </span>
                <% end %>
              </.link>
              <!-- Notification Bell Icon with Badge -->
              <div class="relative" id="notification-bell">
                <button phx-click="toggle_notification_dropdown"
                  class="relative flex items-center justify-center w-10 h-10 rounded-full bg-gray-100 hover:bg-gray-200 transition-colors cursor-pointer">
                  <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5 text-[#141414]">
                    <path fill-rule="evenodd" d="M5.25 9a6.75 6.75 0 0 1 13.5 0v.75c0 2.123.8 4.057 2.118 5.52a.75.75 0 0 1-.297 1.206c-1.544.57-3.16.99-4.831 1.243a3.75 3.75 0 1 1-7.48 0 24.585 24.585 0 0 1-4.831-1.244.75.75 0 0 1-.298-1.205A8.217 8.217 0 0 0 5.25 9.75V9Zm4.502 8.9a2.25 2.25 0 1 0 4.496 0 25.057 25.057 0 0 1-4.496 0Z" clip-rule="evenodd" />
                  </svg>
                  <%= if @unread_notification_count > 0 do %>
                    <span class="absolute -top-1 -right-1 bg-red-500 text-white text-[10px] font-haas_medium_65 rounded-full min-w-[18px] h-[18px] flex items-center justify-center px-1" id="notification-badge">
                      <%= if @unread_notification_count > 99, do: "99+", else: @unread_notification_count %>
                    </span>
                  <% end %>
                </button>
                <!-- Notification Dropdown -->
                <%= if @notification_dropdown_open do %>
                  <div id="notification-dropdown" class="absolute right-0 top-12 w-96 bg-white rounded-2xl shadow-2xl border border-gray-100 z-50 overflow-hidden" phx-click-away="close_notification_dropdown">
                    <!-- Header -->
                    <div class="flex items-center justify-between px-4 py-3 border-b border-gray-100">
                      <h3 class="font-haas_medium_65 text-[#141414] text-sm">Notifications</h3>
                      <div class="flex items-center gap-3">
                        <%= if @unread_notification_count > 0 do %>
                          <button phx-click="mark_all_notifications_read" class="text-xs text-gray-500 hover:text-[#141414] cursor-pointer">Mark all read</button>
                        <% end %>
                      </div>
                    </div>
                    <!-- Notification list -->
                    <div class="max-h-[420px] overflow-y-auto divide-y divide-gray-50">
                      <%= if @recent_notifications == [] do %>
                        <div class="py-12 text-center text-gray-400 text-sm font-haas_roman_55">
                          No notifications yet
                        </div>
                      <% else %>
                        <%= for notification <- @recent_notifications do %>
                          <div
                            phx-click="click_notification"
                            phx-value-id={notification.id}
                            phx-value-url={notification.action_url}
                            class={"flex items-start gap-3 px-4 py-3 hover:bg-gray-50 cursor-pointer transition-colors #{if is_nil(notification.read_at), do: "bg-blue-50/30", else: ""}"}
                          >
                            <%= if notification.image_url do %>
                              <img src={notification.image_url} class="w-10 h-10 rounded-lg object-cover flex-shrink-0" />
                            <% else %>
                              <div class="w-10 h-10 rounded-lg bg-[#CAFC00] flex items-center justify-center flex-shrink-0">
                                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5 text-black">
                                  <path fill-rule="evenodd" d="M5.25 9a6.75 6.75 0 0 1 13.5 0v.75c0 2.123.8 4.057 2.118 5.52a.75.75 0 0 1-.297 1.206c-1.544.57-3.16.99-4.831 1.243a3.75 3.75 0 1 1-7.48 0 24.585 24.585 0 0 1-4.831-1.244.75.75 0 0 1-.298-1.205A8.217 8.217 0 0 0 5.25 9.75V9Zm4.502 8.9a2.25 2.25 0 1 0 4.496 0 25.057 25.057 0 0 1-4.496 0Z" clip-rule="evenodd" />
                                </svg>
                              </div>
                            <% end %>
                            <div class="flex-1 min-w-0">
                              <p class={"text-sm truncate #{if is_nil(notification.read_at), do: "font-haas_medium_65 text-[#141414]", else: "font-haas_roman_55 text-gray-600"}"}><%= notification.title %></p>
                              <p class="text-xs text-gray-500 mt-0.5 line-clamp-2"><%= notification.body %></p>
                              <p class="text-[10px] text-gray-400 mt-1"><%= format_notification_time(notification.inserted_at) %></p>
                            </div>
                            <%= if is_nil(notification.read_at) do %>
                              <div class="w-2 h-2 rounded-full bg-blue-500 flex-shrink-0 mt-2"></div>
                            <% end %>
                          </div>
                        <% end %>
                      <% end %>
                    </div>
                    <!-- Footer -->
                    <div class="flex items-center justify-between px-4 py-2.5 border-t border-gray-100 bg-gray-50/50">
                      <.link navigate={~p"/notifications"} class="text-xs font-haas_medium_65 text-[#141414] hover:underline">
                        View all
                      </.link>
                      <.link navigate={~p"/notifications/settings"} class="text-xs text-gray-500 hover:text-[#141414] flex items-center gap-1">
                        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                          <path fill-rule="evenodd" d="M7.84 1.804A1 1 0 0 1 8.82 1h2.36a1 1 0 0 1 .98.804l.331 1.652a6.993 6.993 0 0 1 1.929 1.115l1.598-.54a1 1 0 0 1 1.186.447l1.18 2.044a1 1 0 0 1-.205 1.251l-1.267 1.113a7.047 7.047 0 0 1 0 2.228l1.267 1.113a1 1 0 0 1 .206 1.25l-1.18 2.045a1 1 0 0 1-1.187.447l-1.598-.54a6.993 6.993 0 0 1-1.929 1.115l-.33 1.652a1 1 0 0 1-.98.804H8.82a1 1 0 0 1-.98-.804l-.331-1.652a6.993 6.993 0 0 1-1.929-1.115l-1.598.54a1 1 0 0 1-1.186-.447l-1.18-2.044a1 1 0 0 1 .205-1.251l1.267-1.114a7.05 7.05 0 0 1 0-2.227L1.821 7.773a1 1 0 0 1-.206-1.25l1.18-2.045a1 1 0 0 1 1.187-.447l1.598.54A6.992 6.992 0 0 1 7.51 3.456l.33-1.652ZM10 13a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z" clip-rule="evenodd" />
                        </svg>
                        Settings
                      </.link>
                    </div>
                  </div>
                <% end %>
              </div>
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
                    <.link
                      navigate={~p"/member/#{@current_user.slug || @current_user.smart_wallet_address}"}
                      class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors font-semibold"
                    >
                      My Profile
                    </.link>
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
                          navigate={~p"/admin/orders"}
                          class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                        >
                          Orders
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
                        <.link
                          navigate={~p"/admin/content"}
                          class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                        >
                          Content Generator
                        </.link>
                        <div class="border-t border-gray-100 my-1"></div>
                        <.link
                          navigate={~p"/admin/notifications/campaigns"}
                          class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                        >
                          Notification Campaigns
                        </.link>
                        <.link
                          navigate={~p"/admin/notifications/analytics"}
                          class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                        >
                          Notification Analytics
                        </.link>
                        <.link
                          navigate={~p"/admin/ai-manager"}
                          class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                        >
                          AI Manager
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
            <div id="category-nav" phx-hook="CategoryNavHighlight" data-post-category={@post_category_slug} class="max-w-7xl mx-auto px-4 flex items-center justify-center gap-4 overflow-x-auto">
              <.link navigate={~p"/category/blockchain"} data-category-path="/category/blockchain" class="text-sm font-haas_roman_55 text-black hover:opacity-70 whitespace-nowrap transition-opacity leading-none pb-1 border-b-[3px] border-transparent">Blockchain</.link>
              <span class="text-gray-300">|</span>
              <.link navigate={~p"/category/investment"} data-category-path="/category/investment" class="text-sm font-haas_roman_55 text-black hover:opacity-70 whitespace-nowrap transition-opacity leading-none pb-1 border-b-[3px] border-transparent">Investment</.link>
              <span class="text-gray-300">|</span>
              <.link navigate={~p"/category/trading"} data-category-path="/category/trading" class="text-sm font-haas_roman_55 text-black hover:opacity-70 whitespace-nowrap transition-opacity leading-none pb-1 border-b-[3px] border-transparent">Trading</.link>
              <span class="text-gray-300">|</span>
              <.link navigate={~p"/category/people"} data-category-path="/category/people" class="text-sm font-haas_roman_55 text-black hover:opacity-70 whitespace-nowrap transition-opacity leading-none pb-1 border-b-[3px] border-transparent">People</.link>
              <span class="text-gray-300">|</span>
              <.link navigate={~p"/category/defi"} data-category-path="/category/defi" class="text-sm font-haas_roman_55 text-black hover:opacity-70 whitespace-nowrap transition-opacity leading-none pb-1 border-b-[3px] border-transparent">DeFi</.link>
              <span class="text-gray-300">|</span>
              <.link navigate={~p"/category/ai"} data-category-path="/category/ai" class="text-sm font-haas_roman_55 text-black hover:opacity-70 whitespace-nowrap transition-opacity leading-none pb-1 border-b-[3px] border-transparent">AI</.link>
              <span class="text-gray-300">|</span>
              <.link navigate={~p"/category/rwa"} data-category-path="/category/rwa" class="text-sm font-haas_roman_55 text-black hover:opacity-70 whitespace-nowrap transition-opacity leading-none pb-1 border-b-[3px] border-transparent">RWA</.link>
              <span class="text-gray-300">|</span>
              <.link navigate={~p"/category/events"} data-category-path="/category/events" class="text-sm font-haas_roman_55 text-black hover:opacity-70 whitespace-nowrap transition-opacity leading-none pb-1 border-b-[3px] border-transparent">Events</.link>
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
          <%= if @show_categories && (!@current_user || @cart_item_count == 0) do %>
            <!-- Search icon: shown on content pages when cart is empty -->
            <button phx-click="open_mobile_search" class="search-trigger w-8 h-8 flex items-center justify-center text-gray-500 rounded-full bg-[#F3F5FF] shadow-md cursor-pointer">
              <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 20 19" fill="none">
                <path d="M17 16.5L13.6556 13.1556M15.4444 8.72222C15.4444 12.1587 12.6587 14.9444 9.22222 14.9444C5.78578 14.9444 3 12.1587 3 8.72222C3 5.28578 5.78578 2.5 9.22222 2.5C12.6587 2.5 15.4444 5.28578 15.4444 8.72222Z"
                      stroke="#101C36" stroke-opacity="0.5" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
            </button>
          <% else %>
            <%= if @current_user do %>
              <!-- Cart icon: shown on non-content pages (always) or content pages when cart has items -->
              <.link navigate={~p"/cart"} class="relative w-8 h-8 flex items-center justify-center rounded-full bg-[#F3F5FF] shadow-md cursor-pointer">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-4 h-4 text-[#141414]">
                  <path fill-rule="evenodd" d="M7.5 6v.75H5.513c-.96 0-1.764.724-1.865 1.679l-1.263 12A1.875 1.875 0 0 0 4.25 22.5h15.5a1.875 1.875 0 0 0 1.865-2.071l-1.263-12a1.875 1.875 0 0 0-1.865-1.679H16.5V6a4.5 4.5 0 1 0-9 0ZM12 3a3 3 0 0 0-3 3v.75h6V6a3 3 0 0 0-3-3Zm-3 8.25a3 3 0 1 0 6 0v-.75a.75.75 0 0 1 1.5 0v.75a4.5 4.5 0 1 1-9 0v-.75a.75.75 0 0 1 1.5 0v.75Z" clip-rule="evenodd" />
                </svg>
                <%= if @cart_item_count > 0 do %>
                  <span class="absolute -top-1 -right-1 bg-[#8AE388] text-[#141414] text-[10px] font-haas_medium_65 rounded-full min-w-[16px] h-[16px] flex items-center justify-center px-0.5">
                    <%= @cart_item_count %>
                  </span>
                <% end %>
              </.link>
            <% else %>
              <!-- Search icon fallback for logged-out users on non-content pages -->
              <button phx-click="open_mobile_search" class="search-trigger w-8 h-8 flex items-center justify-center text-gray-500 rounded-full bg-[#F3F5FF] shadow-md cursor-pointer">
                <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 20 19" fill="none">
                  <path d="M17 16.5L13.6556 13.1556M15.4444 8.72222C15.4444 12.1587 12.6587 14.9444 9.22222 14.9444C5.78578 14.9444 3 12.1587 3 8.72222C3 5.28578 5.78578 2.5 9.22222 2.5C12.6587 2.5 15.4444 5.28578 15.4444 8.72222Z"
                        stroke="#101C36" stroke-opacity="0.5" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
                </svg>
              </button>
            <% end %>
          <% end %>
          <%= if @current_user do %>
            <!-- Mobile logged in user with dropdown -->
            <div class="relative" id="mobile-user-dropdown" phx-click-away={JS.hide(to: "#mobile-dropdown-menu")}>
              <button id="mobile-user-button" phx-click={JS.toggle(to: "#mobile-dropdown-menu")} class="flex items-center gap-2 rounded-[100px] bg-bg-light py-1.5 pl-2 pr-2 shadow-sm cursor-pointer">
                <img src={@token_logo} alt={@display_token} class="w-6 h-6 rounded-full" />
                <span class="text-sm font-haas_medium_65 text-[#000000]">{@formatted_bux_balance}<%= unless @hide_mobile_token_name do %> <span class="text-gray-500">{@display_token}</span><% end %></span>
                <span class="flex items-center transition-all ease-linear duration-500">
                  <svg xmlns="http://www.w3.org/2000/svg" width="20" height="20" viewBox="0 0 24 24" fill="none">
                    <path d="M8 10L12 14L16 10" stroke="#101D36" stroke-width="1.5" stroke-linecap="square" />
                  </svg>
                </span>
              </button>
              <!-- Mobile Dropdown menu -->
              <div id="mobile-dropdown-menu" class="absolute right-0 mt-2 w-48 bg-white rounded-lg shadow-lg border border-gray-200 hidden z-50">
                <div class="py-1">
                  <.link
                    navigate={~p"/member/#{@current_user.slug || @current_user.smart_wallet_address}"}
                    class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors font-semibold"
                  >
                    My Profile
                  </.link>
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
                        navigate={~p"/admin/orders"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Orders
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
                      <.link
                        navigate={~p"/admin/content"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Content Generator
                      </.link>
                      <div class="border-t border-gray-100 my-1"></div>
                      <.link
                        navigate={~p"/admin/notifications/campaigns"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Notification Campaigns
                      </.link>
                      <.link
                        navigate={~p"/admin/notifications/analytics"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Notification Analytics
                      </.link>
                      <.link
                        navigate={~p"/admin/ai-manager"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        AI Manager
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
              phx-mounted={JS.focus()}
              class="w-full h-10 px-4 pl-9 bg-[#F5F6FB] text-base font-haas_roman_55 rounded-full border border-[#E8EAEC]"
              id="mobile-search-input"
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
    <div class="h-14 lg:h-24"></div>
    """
  end

  defp format_notification_time(nil), do: ""
  defp format_notification_time(datetime) do
    now = DateTime.utc_now()
    diff = DateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
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
              <img src="https://ik.imagekit.io/blockster/Blockster-logo-white.png" alt="Blockster" class="h-8" />
            </div>
            <p class="text-sm font-haas_roman_55 text-[#E8EAEC] leading-relaxed max-w-sm">
              Web3's daily content hub—Earn BUX, redeem rewards, and stay plugged into crypto, blockchain, and the future of finance.
            </p>
            <!-- Social Links -->
            <div class="flex gap-4 mt-6">
              <a href="https://x.com/BlocksterCom" target="_blank" class="w-10 h-10 bg-white/10 rounded-full flex items-center justify-center hover:bg-white/20 transition-colors cursor-pointer">
                <span class="text-white font-bold">𝕏</span>
              </a>
            </div>
          </div>

          <!-- Blockster Links -->
          <div>
            <h3 class="font-haas_bold_75 text-white mb-4">Blockster</h3>
            <ul class="space-y-3">
              <li><.link navigate={~p"/"} class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors cursor-pointer">News</.link></li>
              <li><.link navigate={~p"/hubs"} class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors cursor-pointer">Hubs</.link></li>
              <li><.link navigate={~p"/shop"} class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors cursor-pointer">Shop</.link></li>
              <li><.link navigate={~p"/play"} class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors cursor-pointer">Play</.link></li>
            </ul>
          </div>

          <!-- Explore Links -->
          <div>
            <h3 class="font-haas_bold_75 text-white mb-4">Explore</h3>
            <ul class="space-y-3">
              <li><.link navigate={~p"/how-it-works"} class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors cursor-pointer">How it Works</.link></li>
              <li><.link navigate={~p"/shop"} class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors cursor-pointer">Shop</.link></li>
              <li><.link navigate={~p"/airdrop"} class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors cursor-pointer">Airdrop</.link></li>
              <li><.link navigate={~p"/play"} class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors cursor-pointer">BUX Booster</.link></li>
            </ul>
          </div>

          <!-- Rogue Chain Links -->
          <div>
            <h3 class="font-haas_bold_75 text-white mb-4">Rogue Chain</h3>
            <ul class="space-y-3">
              <li><a href="https://www.coingecko.com/en/coins/rogue" target="_blank" class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors cursor-pointer">ROGUE on CoinGecko</a></li>
              <li><a href="https://app.uniswap.org/explore/pools/arbitrum/0x9876d52d698ffad55fef13f4d631c0300cf2dc8ef90c8dd70405dc06fa10b2ec" target="_blank" class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors cursor-pointer">Buy ROGUE</a></li>
              <li><a href="https://roguetrader.io/bridge" target="_blank" class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors cursor-pointer">Bridge ROGUE</a></li>
              <li><a href="https://roguescan.io" target="_blank" class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors cursor-pointer">Block Explorer</a></li>
            </ul>
          </div>
        </div>

        <!-- Bottom Bar -->
        <div class="border-t border-white/10 pt-8">
          <div class="flex flex-col md:flex-row justify-between items-center gap-4">
            <p class="text-sm font-haas_roman_55 text-[#E8EAEC]">
              © 2026 Blockster Media & Technology, LLC. All rights reserved.
            </p>
            <div class="flex gap-6">
              <.link navigate={~p"/privacy"} class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors cursor-pointer">Privacy Policy</.link>
              <.link navigate={~p"/terms"} class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors cursor-pointer">Terms of Service</.link>
              <.link navigate={~p"/cookies"} class="text-sm font-haas_roman_55 text-[#E8EAEC] hover:text-white transition-colors cursor-pointer">Cookie Policy</.link>
            </div>
          </div>
        </div>
      </div>
    </footer>
    """
  end
end
