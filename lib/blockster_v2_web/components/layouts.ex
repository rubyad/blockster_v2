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

  def site_header(assigns) do

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
      <header class="pt-6 pb-4 hidden lg:flex items-center justify-between gap-4 px-6 lg:pl-11 lg:pr-7">
        <div class="left-header-inner flex items-center gap-9 w-full">
        <div>
          <.link navigate={~p"/"} class="bg-white py-6 px-5 rounded-[85px] block">
            <img src="/images/Logo.png" alt="Blockster" />
          </.link>
        </div>
        <div class="flex gap-2 bg-white p-2 rounded-[85px] justify-between w-full border border-[#E8EAEC]">
          <div class="flex gap-2 items-center">
            <!-- Search Bar -->
            <div class="right-section-left" id="search-container" phx-click-away={if @show_search_results, do: "close_search", else: nil}>
              <div class="input-wrapper relative max-w-[247px] w-[100%]">
                <span class="absolute left-2.5 top-1/2 -translate-y-1/2 z-10">
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
                  class="text-left text-grey-30 h-12 px-5 pl-[29px] bg-bg-input text-sm font-[400] font-haas_roman_55 w-full rounded-[85px]"
                />

                <!-- Search Results Dropdown -->
                <%= if @show_search_results && length(@search_results) > 0 do %>
                  <div class="absolute top-full left-0 mt-2 w-[400px] bg-white rounded-2xl border border-[#E7E8F1] shadow-xl z-50 max-h-[500px] overflow-y-auto">
                    <div class="py-2">
                      <%= for post <- @search_results do %>
                        <.link
                          navigate={~p"/#{post.slug}"}
                          class="flex items-start gap-3 px-4 py-3 hover:bg-[#F5F6FB] transition-colors cursor-pointer"
                          phx-click="close_search"
                        >
                          <div class="img-wrapper rounded-lg overflow-hidden flex-shrink-0" style="width: 60px; height: 60px;">
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
            <!-- Navigation Links -->
            <div class="inner-section-right">
              <ul class="flex gap-2 items-center">
                <li class="relative group">
                  <a href="#" class="px-4 pr-[9px] py-2 border-btn font-haas_medium_65 border-border-grey_12 border-[1px] rounded-[100px] block xl:text-[16px] text-[14px] text-[#101D36] border-solid flex items-center hover:bg-[#F5F6FB] transition-colors">
                    <span class="flex items-center">News</span>
                    <span class="flex items-center">
                      <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none">
                        <path d="M8 10L12 14L16 10" stroke="#101C36" stroke-width="1.5" stroke-linecap="square" />
                      </svg>
                    </span>
                  </a>

                  <!-- Dropdown Menu -->
                  <div class="absolute top-full left-0 mt-2 w-56 bg-white rounded-2xl border border-[#E7E8F1] shadow-xl opacity-0 invisible group-hover:opacity-100 group-hover:visible transition-all duration-200 z-50">
                    <div class="py-2">
                      <.link navigate={~p"/"} class="block px-4 py-2.5 text-sm font-haas_medium_65 text-[#141414] hover:bg-[#F5F6FB] transition-colors">
                        All News
                      </.link>
                      <div class="border-t border-[#E7E8F1] my-2"></div>
                      <.link navigate={~p"/category/blockchain"} class="block px-4 py-2.5 text-sm font-haas_roman_55 text-[#515B70] hover:bg-[#F5F6FB] hover:text-[#141414] transition-colors">
                        Blockchain
                      </.link>
                      <.link navigate={~p"/category/market-analysis"} class="block px-4 py-2.5 text-sm font-haas_roman_55 text-[#515B70] hover:bg-[#F5F6FB] hover:text-[#141414] transition-colors">
                        Market Analysis
                      </.link>
                      <.link navigate={~p"/category/investment"} class="block px-4 py-2.5 text-sm font-haas_roman_55 text-[#515B70] hover:bg-[#F5F6FB] hover:text-[#141414] transition-colors">
                        Investment
                      </.link>
                      <.link navigate={~p"/category/events"} class="block px-4 py-2.5 text-sm font-haas_roman_55 text-[#515B70] hover:bg-[#F5F6FB] hover:text-[#141414] transition-colors">
                        Events
                      </.link>
                      <.link navigate={~p"/category/crypto-trading"} class="block px-4 py-2.5 text-sm font-haas_roman_55 text-[#515B70] hover:bg-[#F5F6FB] hover:text-[#141414] transition-colors">
                        Crypto Trading
                      </.link>
                      <.link navigate={~p"/category/people"} class="block px-4 py-2.5 text-sm font-haas_roman_55 text-[#515B70] hover:bg-[#F5F6FB] hover:text-[#141414] transition-colors">
                        People
                      </.link>
                      <.link navigate={~p"/category/defi"} class="block px-4 py-2.5 text-sm font-haas_roman_55 text-[#515B70] hover:bg-[#F5F6FB] hover:text-[#141414] transition-colors">
                        DeFi
                      </.link>
                      <.link navigate={~p"/category/announcements"} class="block px-4 py-2.5 text-sm font-haas_roman_55 text-[#515B70] hover:bg-[#F5F6FB] hover:text-[#141414] transition-colors">
                        Announcements
                      </.link>
                      <.link navigate={~p"/category/gaming"} class="block px-4 py-2.5 text-sm font-haas_roman_55 text-[#515B70] hover:bg-[#F5F6FB] hover:text-[#141414] transition-colors">
                        Gaming
                      </.link>
                      <.link navigate={~p"/category/tech"} class="block px-4 py-2.5 text-sm font-haas_roman_55 text-[#515B70] hover:bg-[#F5F6FB] hover:text-[#141414] transition-colors">
                        Tech
                      </.link>
                    </div>
                  </div>
                </li>
                <li>
                  <.link navigate={~p"/hubs"} class="px-4 py-2 border-btn font-haas_medium_65 border-border-grey_12 border-[1px] rounded-[100px] block text-[#101D36] border-solid xl:text-[16px] text-[14px] hover:bg-[#F5F6FB] transition-colors">
                    Hubs
                  </.link>
                </li>
                <li>
                  <.link navigate={~p"/shop-landing"} class="px-4 py-2 border-btn font-haas_medium_65 border-border-grey_12 border-[1px] rounded-[100px] block text-[#101D36] border-solid xl:text-[16px] text-[14px] hover:bg-[#F5F6FB] transition-colors">
                    Shop
                  </.link>
                </li>
                <li>
                  <.link navigate={~p"/events"} class="px-4 py-2 border-btn font-haas_medium_65 border-border-grey_12 border-[1px] rounded-[100px] block text-[#101D36] border-solid xl:text-[16px] text-[14px] hover:bg-[#F5F6FB] transition-colors">
                    Events
                  </.link>
                </li>
                <li>
                  <a href="https://roguetrader.io" target="_blank" rel="noopener noreferrer" class="px-4 py-2 border-btn font-haas_medium_65 border-border-grey_12 border-[1px] rounded-[100px] block xl:text-[16px] text-[14px] text-[#101D36] border-solid hover:bg-[#F5F6FB] transition-colors">
                    Play
                  </a>
                </li>
              </ul>
            </div>
          </div>
          <!-- Right Section with User/Connect -->
          <div class="right-outer flex items-center gap-2 w-1/4 justify-end">
            <%= if @current_user do %>
              <!-- Logged in user display with dropdown -->
              <div class="relative" id="desktop-user-dropdown">
                <button id="desktop-user-button" onclick="var dropdown = document.getElementById('desktop-dropdown-menu'); dropdown.classList.toggle('hidden');" class="flex items-center gap-2 rounded-[100px] bg-bg-light py-2 pl-2 pr-4 hover:bg-gray-100 transition-colors">
                  <div class="img-rounded h-8 min-w-8 rounded-full bg-[#AFB5FF]">
                    <%= if @current_user.avatar_url do %>
                      <img src={@current_user.avatar_url} alt="User" class="h-full w-full min-w-auto object-cover rounded-full" />
                    <% else %>
                      <img src="/images/avatar.png" alt="User" class="h-full w-full min-w-auto object-cover rounded-full" />
                    <% end %>
                  </div>
                  <div class="flex flex-col justify-center gap-0.5">
                    <div class="flex items-center gap-0.5">
                      <span class="flex h-4 items-center justify-center rounded-[4px] bg-gradient-to-r from-[#8AE388] to-[#BAF55F] text-black w-[20px] text-xs font-work_sans font-bold">
                        {@current_user.level}
                      </span>
                      <h4 class="text-sm font-haas_medium_65 text-[#000000] truncate max-w-[120px]">
                        {@current_user.username || String.slice(@current_user.smart_wallet_address || @current_user.wallet_address, 0..5) <> "..." <> String.slice(@current_user.smart_wallet_address || @current_user.wallet_address, -4..-1//1)}
                      </h4>
                    </div>
                    <span class="relative h-1.5 w-full rounded-full bg-white border-[#0000001F] border-[0.5px] overflow-hidden flex">
                      <span class="h-1 bg-[#223436] rounded-full absolute top-0 left-0" style={"width: #{min(rem(@current_user.experience_points, 1000) / 10, 100)}%"}></span>
                    </span>
                  </div>
                  <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" class="ml-1">
                    <path d="M8 10L12 14L16 10" stroke="#101C36" stroke-width="1.5" stroke-linecap="square" />
                  </svg>
                </button>
                <!-- Dropdown menu -->
                <div id="desktop-dropdown-menu" class="absolute right-0 mt-2 w-48 bg-white rounded-lg shadow-lg border border-gray-200 hidden z-50">
                  <div class="py-1">
                    <div class="px-4 py-2 text-sm text-gray-700 border-b border-gray-100">
                      <div class="font-semibold">BUX Balance</div>
                      <div class="text-xs text-gray-500">{@current_user.bux_balance} BUX</div>
                    </div>
                    <.link
                      navigate={~p"/profile"}
                      class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                    >
                      View Profile
                    </.link>
                    <%= if @current_user.is_author || @current_user.is_admin do %>
                      <.link
                        navigate={~p"/new"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Create Article
                      </.link>
                    <% end %>
                    <%= if @current_user.is_admin do %>
                      <div class="border-t border-gray-100 my-1"></div>
                      <div class="px-4 py-1 text-xs text-gray-400 font-semibold uppercase">Admin</div>
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
                        navigate={~p"/hubs/admin"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Hubs
                      </.link>
                      <.link
                        navigate={~p"/admin/waitlist"}
                        class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                      >
                        Waitlist
                      </.link>
                    <% end %>
                    <button
                      onclick="window.handleWalletDisconnect()"
                      class="w-full text-left px-4 py-2 text-sm text-red-600 hover:bg-red-50 transition-colors"
                    >
                      Disconnect Wallet
                    </button>
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
      </header>

      <!-- Mobile Header -->
      <div class="mobile-header border border-[#E7E8F1] p-3 flex items-center justify-between bg-white lg:hidden">
      <div class="no-search-wrapper flex justify-between items-center w-full">
        <div>
          <.link navigate={~p"/"}>
            <img src="/images/Logo.png" alt="Blockster" />
          </.link>
        </div>
        <div class="flex gap-2 items-center">
          <button class="search-trigger w-8 h-8 flex items-center justify-center text-gray-500 rounded-full bg-[#F3F5FF] shadow-md">
            <svg xmlns="http://www.w3.org/2000/svg" width="13" height="13" viewBox="0 0 20 19" fill="none">
              <path d="M17 16.5L13.6556 13.1556M15.4444 8.72222C15.4444 12.1587 12.6587 14.9444 9.22222 14.9444C5.78578 14.9444 3 12.1587 3 8.72222C3 5.28578 5.78578 2.5 9.22222 2.5C12.6587 2.5 15.4444 5.28578 15.4444 8.72222Z"
                    stroke="#101C36" stroke-opacity="0.5" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
            </svg>
          </button>
          <%= if @current_user do %>
            <!-- Mobile logged in user with dropdown -->
            <div class="relative" id="mobile-user-dropdown">
              <button id="mobile-user-button" onclick="var dropdown = document.getElementById('mobile-dropdown-menu'); dropdown.classList.toggle('hidden');" class="flex items-center gap-2 rounded-[100px] bg-bg-light py-1 pl-1 pr-1 shadow-sm">
                <div class="img-rounded h-8 min-w-8 rounded-full bg-[#AFB5FF] relative">
                  <%= if @current_user.avatar_url do %>
                    <img src={@current_user.avatar_url} alt="User" class="h-full w-full min-w-auto object-cover rounded-full" />
                  <% else %>
                    <img src="/images/avatar.png" alt="User" class="h-full w-full min-w-auto object-cover rounded-full" />
                  <% end %>
                  <div class="absolute flex h-3 items-center justify-center rounded-[4px] bg-gradient-to-r from-[#8AE388] to-[#BAF55F] p-2 text-black w-3 text-xs font-work_sans font-bold -right-2 -top-1">
                    {@current_user.level}
                  </div>
                </div>
                <span class="flex items-center transition-all ease-linear duration-500">
                  <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none">
                    <path d="M8 10L12 14L16 10" stroke="#101D36" stroke-width="1.5" stroke-linecap="square" />
                  </svg>
                </span>
              </button>
              <!-- Mobile Dropdown menu -->
              <div id="mobile-dropdown-menu" class="absolute right-0 mt-2 w-48 bg-white rounded-lg shadow-lg border border-gray-200 hidden z-50">
                <div class="py-1">
                  <div class="px-4 py-2 text-sm text-gray-700 border-b border-gray-100">
                    <div class="font-semibold">{@current_user.username || String.slice(@current_user.smart_wallet_address || @current_user.wallet_address, 0..5) <> "..."}</div>
                    <div class="text-xs text-gray-500">{@current_user.bux_balance} BUX</div>
                  </div>
                  <.link
                    navigate={~p"/profile"}
                    class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                  >
                    View Profile
                  </.link>
                  <%= if @current_user.is_author || @current_user.is_admin do %>
                    <.link
                      navigate={~p"/new"}
                      class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                    >
                      Create Article
                    </.link>
                  <% end %>
                  <%= if @current_user.is_admin do %>
                    <div class="border-t border-gray-100 my-1"></div>
                    <div class="px-4 py-1 text-xs text-gray-400 font-semibold uppercase">Admin</div>
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
                      navigate={~p"/hubs/admin"}
                      class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                    >
                      Hubs
                    </.link>
                    <.link
                      navigate={~p"/admin/waitlist"}
                      class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors"
                    >
                      Waitlist
                    </.link>
                  <% end %>
                  <button
                    onclick="window.handleWalletDisconnect()"
                    class="w-full text-left px-4 py-2 text-sm text-red-600 hover:bg-red-50 transition-colors"
                  >
                    Disconnect Wallet
                  </button>
                </div>
              </div>
            </div>
          <% else %>
            <!-- Mobile ThirdwebLogin nested LiveView -->
            <.live_component module={BlocksterV2Web.ThirdwebLoginLive} id="thirdweb-login-mobile" />
          <% end %>
        </div>
      </div>
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
