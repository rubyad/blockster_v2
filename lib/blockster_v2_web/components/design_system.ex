defmodule BlocksterV2Web.DesignSystem do
  @moduledoc """
  Foundation components for the existing-pages redesign release.

  Visual language is captured in `docs/solana/design_system.md`. The mock files
  in `docs/solana/*_mock.html` are the visual reference. This module is the
  source of truth for reusable Phoenix components extracted from those mocks.

  Wave 0 components live directly in this module. As later waves extract more
  components, this file grows. If it gets too large we'll split into per-component
  files later — for now keeping everything together makes the design language
  easy to read and update in one place.

  Used as:

      use BlocksterV2Web.DesignSystem

  ...which imports every public component function so consumers can write
  `<.header />`, `<.footer />`, `<.logo />`, etc. without namespacing.
  """

  defmacro __using__(_) do
    quote do
      # `BlocksterV2Web.CoreComponents` defines a generic `header/1` that
      # ships with Phoenix's scaffolding (used for admin tables). It collides
      # with our site `header/1`. Re-importing CoreComponents with `:except`
      # drops the collision so consumers can write `<.header />` and get the
      # design-system header. CoreComponents is automatically imported by
      # `use BlocksterV2Web, :live_view` / `:html` before this macro runs.
      import BlocksterV2Web.CoreComponents, except: [header: 1]
      import BlocksterV2Web.DesignSystem
    end
  end

  use Phoenix.Component
  use BlocksterV2Web, :verified_routes

  alias Phoenix.LiveView.JS

  @logo_icon_url "https://ik.imagekit.io/blockster/blockster-icon.png"

  @doc """
  Returns the canonical URL for the lime Blockster icon (the "O" in the
  wordmark, also reused for BUX accent dots).
  """
  def logo_icon_url, do: @logo_icon_url

  # ── <.logo /> ───────────────────────────────────────────────────────────────
  #
  # The locked-in wordmark: BLOCKSTER in Inter 800 uppercase, +0.06em tracking,
  # with the lime brand icon swapped in for the O at 0.78em.
  #
  # Sizes match the spec in design_system.md (12px footer fineprint up to 96px
  # poster). Variants:
  #   light  → black wordmark, lime icon (default — for use on light surfaces)
  #   dark   → off-white wordmark for use on dark surfaces (#E8E4DD)

  @doc """
  Renders the Blockster wordmark — Inter 800 uppercase with the lime icon in
  place of the O. Scales perfectly at any font-size; the icon is sized in
  ems so it always sits in proportion to the cap height.

      <.logo size="22px" />
      <.logo size="64px" variant="dark" />
  """
  attr :size, :string, default: "22px", doc: "CSS font-size value (e.g. 22px, 1.5rem)"
  attr :variant, :string, default: "light", values: ~w(light dark)
  attr :class, :string, default: nil
  attr :rest, :global

  def logo(assigns) do
    ~H"""
    <span
      class={[
        "ds-logo inline-flex items-center whitespace-nowrap leading-none uppercase font-extrabold tracking-[0.06em]",
        @variant == "dark" && "ds-logo--dark",
        @class
      ]}
      style={"font-size: #{@size};"}
      {@rest}
    >
      <span class="ds-logo__b">BL</span><img
        src="https://ik.imagekit.io/blockster/blockster-icon.png"
        alt="o"
        class="ds-logo__o"
        style="display:inline-block;width:0.78em;height:0.78em;object-fit:contain;margin:0 0.04em;vertical-align:middle;flex-shrink:0;"
        loading="eager"
      /><span class="ds-logo__c">CKSTER</span>
    </span>
    """
  end

  # ── <.eyebrow /> ────────────────────────────────────────────────────────────
  #
  # Tiny uppercase tracked label that sits above section titles or inside cards.
  # Inter 700, 10px, 0.16em tracking, faint gray. The editorial weight comes
  # from these — every section gets one.

  @doc """
  Renders a small uppercase eyebrow label.

      <.eyebrow>Most read this week</.eyebrow>
      <.eyebrow class="text-[#a16207]">One thing left</.eyebrow>
  """
  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def eyebrow(assigns) do
    ~H"""
    <div
      class={[
        "ds-eyebrow font-bold uppercase text-[10px] tracking-[0.16em] text-neutral-400",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  # ── <.chip /> ───────────────────────────────────────────────────────────────
  #
  # Filter / category pill. Two variants: default (white with gray border) and
  # active (black with white text). Used in the homepage trending filter row,
  # the hubs index category bar, etc.

  @doc """
  Renders a filter chip.

      <.chip>DeFi</.chip>
      <.chip variant="active">All</.chip>
      <.chip variant="default" phx-click="filter" phx-value-key="defi">DeFi</.chip>
  """
  attr :variant, :string, default: "default", values: ~w(default active)
  attr :class, :string, default: nil
  attr :rest, :global, include: ~w(phx-click phx-value-key phx-target href type)
  slot :inner_block, required: true

  def chip(assigns) do
    ~H"""
    <button
      type="button"
      class={[
        "ds-chip inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-medium",
        "whitespace-nowrap transition-colors cursor-pointer",
        @variant == "default" &&
          "bg-white border border-neutral-200 text-neutral-500 hover:border-neutral-900 hover:text-neutral-900",
        @variant == "active" && "bg-neutral-900 text-white border border-neutral-900",
        @class
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  # ── <.author_avatar /> ──────────────────────────────────────────────────────
  #
  # Round avatar with two-letter initials in the dark gradient style. Used in
  # bylines and small author blocks. The initials avatar is the small variant;
  # `.profile_avatar` is the larger profile-page variant.

  @doc """
  Renders an author initials avatar (dark gradient circle, white initials).

      <.author_avatar initials="MV" />
      <.author_avatar initials="JC" size="lg" />
  """
  attr :initials, :string, required: true
  attr :size, :string, default: "md", values: ~w(xs sm md lg xl)
  attr :class, :string, default: nil
  attr :rest, :global

  def author_avatar(assigns) do
    ~H"""
    <div
      class={[
        "ds-author-avatar shrink-0 rounded-full grid place-items-center text-white font-bold tracking-wide",
        avatar_size_class(@size),
        @class
      ]}
      {@rest}
    >
      {String.upcase(@initials)}
    </div>
    """
  end

  defp avatar_size_class("xs"), do: "w-6 h-6 text-[9px]"
  defp avatar_size_class("sm"), do: "w-7 h-7 text-[10px]"
  defp avatar_size_class("md"), do: "w-9 h-9 text-[11px]"
  defp avatar_size_class("lg"), do: "w-12 h-12 text-[14px]"
  defp avatar_size_class("xl"), do: "w-16 h-16 text-[18px]"

  # ── <.profile_avatar /> ─────────────────────────────────────────────────────
  #
  # Larger, slightly different gradient — used on the profile page hero and
  # the user dropdown trigger. The lime ring is optional (used in the header
  # so the avatar reads as the active user).

  @doc """
  Renders a profile-style avatar (slightly heavier gradient, optional lime ring).

      <.profile_avatar initials="MV" size="md" ring />
      <.profile_avatar initials="MV" size="2xl" />
  """
  attr :initials, :string, required: true
  attr :size, :string, default: "md", values: ~w(sm md lg xl 2xl)
  attr :ring, :boolean, default: false
  attr :class, :string, default: nil
  attr :rest, :global

  def profile_avatar(assigns) do
    ~H"""
    <div
      class={[
        "ds-profile-avatar shrink-0 rounded-full overflow-hidden grid place-items-center text-white font-extrabold",
        profile_size_class(@size),
        @ring && "ring-2 ring-[#CAFC00]",
        @class
      ]}
      {@rest}
    >
      {String.upcase(@initials)}
    </div>
    """
  end

  defp profile_size_class("sm"), do: "w-8 h-8 text-[11px]"
  defp profile_size_class("md"), do: "w-10 h-10 text-[13px]"
  defp profile_size_class("lg"), do: "w-14 h-14 text-[16px]"
  defp profile_size_class("xl"), do: "w-20 h-20 text-[22px]"
  defp profile_size_class("2xl"), do: "w-28 h-28 text-[30px]"

  # ── <.why_earn_bux_banner /> ────────────────────────────────────────────────
  #
  # The lime band that sits under every header. Per D3 the copy is locked.

  @doc """
  Renders the lime "Why Earn BUX?" announcement banner.
  """
  attr :class, :string, default: nil
  attr :rest, :global

  def why_earn_bux_banner(assigns) do
    ~H"""
    <div
      class={[
        "ds-why-earn-bux bg-[#CAFC00] border-t border-black/10",
        @class
      ]}
      {@rest}
    >
      <div class="max-w-[1280px] mx-auto px-6">
        <div class="flex items-center justify-center gap-3 py-1.5 text-[13px] text-black">
          <span>
            <strong class="font-bold">Why Earn BUX?</strong>
            Redeem BUX to enter sponsored airdrops.
          </span>
        </div>
      </div>
    </div>
    """
  end

  # ── <.header /> ─────────────────────────────────────────────────────────────
  #
  # The redesigned site header with ALL production features:
  #   - Logo (PNG from ImageKit), Solana mainnet pulse, center nav
  #   - Search input with live results dropdown (search_posts handler)
  #   - Notification bell with full dropdown panel (toggle/close/click/mark-all)
  #   - Cart icon with count badge
  #   - BUX balance pill (2 decimal places)
  #   - User dropdown (My Profile, BUX detail, Disconnect, Admin links)
  #   - Connect Wallet button (anonymous)
  #   - Lime "Why Earn BUX?" banner

  @doc """
  Renders the redesigned site header with all production features.
  """
  attr :current_user, :any, default: nil
  attr :active, :string, default: nil, doc: "active nav slug: home|hubs|shop|play|pool|airdrop"
  attr :bux_balance, :any, default: 0
  attr :token_balances, :map, default: %{}
  attr :cart_item_count, :integer, default: 0
  attr :unread_notification_count, :integer, default: 0
  attr :notification_dropdown_open, :boolean, default: false
  attr :recent_notifications, :list, default: []
  attr :search_query, :string, default: ""
  attr :search_results, :list, default: []
  attr :show_search_results, :boolean, default: false
  attr :show_why_earn_bux, :boolean, default: true
  attr :connecting, :boolean, default: false
  attr :display_token, :string, default: "BUX", values: ~w(BUX SOL), doc: "which token balance to show in the header pill"

  def header(assigns) do
    display_token = assigns.display_token
    display_balance =
      case display_token do
        "SOL" -> Map.get(assigns.token_balances || %{}, "SOL", 0)
        _ -> assigns.bux_balance
      end

    assigns =
      assigns
      |> assign(:formatted_bux, format_bux(assigns.bux_balance))
      |> assign(:formatted_display_balance, format_display_balance(display_token, display_balance))
      |> assign(:display_token_icon, display_token_icon(display_token))
      |> assign(:initials, user_initials(assigns.current_user))
      |> assign(:user_slug, user_slug(assigns.current_user))

    ~H"""
    <header
      id="ds-site-header"
      phx-hook="SolanaWallet"
      class="ds-header bg-white/[0.92] backdrop-blur-md border-b border-neutral-200/70 sticky top-0 z-30"
    >
      <div class="max-w-[1280px] mx-auto px-6 h-14 flex items-center justify-between gap-4">
        <%!-- Left: logo + Solana mainnet pulse --%>
        <div class="flex items-center gap-3 min-w-0 shrink-0">
          <.link navigate={~p"/"} class="flex items-center" aria-label="Blockster home">
            <.logo size="22px" />
          </.link>
          <div class="hidden md:flex items-center ml-2 gap-1.5 text-[11px] text-neutral-500 font-mono">
            <span class="w-1.5 h-1.5 rounded-full bg-[#22C55E]"></span>
            <span>Solana mainnet</span>
          </div>
        </div>

        <%!-- Center: search + nav --%>
        <div class="flex items-center gap-4 flex-1 justify-center">
          <%!-- Search input --%>
          <div class="relative hidden md:block" id="ds-search-container" phx-click-away={if @show_search_results, do: "close_search", else: nil}>
            <div class="relative">
              <span class="absolute left-3 top-1/2 -translate-y-1/2">
                <svg class="w-3.5 h-3.5 text-neutral-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                  <circle cx="11" cy="11" r="7"></circle>
                  <path d="m21 21-4.3-4.3"></path>
                </svg>
              </span>
              <input
                type="text"
                placeholder="Search"
                value={@search_query}
                phx-keyup="search_posts"
                phx-debounce="300"
                class="h-9 pl-9 pr-3 bg-neutral-100 text-sm w-[180px] rounded-full border border-neutral-200/60 focus:outline-none focus:border-neutral-400 text-[#141414]"
              />
            </div>
            <%!-- Search results dropdown --%>
            <%= if @show_search_results && length(@search_results) > 0 do %>
              <div class="absolute top-full left-0 mt-2 w-[400px] bg-white rounded-2xl border border-neutral-200 shadow-xl z-50 max-h-[500px] overflow-y-auto">
                <div class="py-2">
                  <%= for post <- @search_results do %>
                    <.link
                      navigate={~p"/#{post.slug}"}
                      class="flex items-start gap-3 px-4 py-3 hover:bg-neutral-50 transition-colors cursor-pointer"
                    >
                      <div class="rounded-lg overflow-hidden shrink-0 w-[60px] h-[60px]">
                        <img src={post.featured_image} class="object-cover w-full h-full" alt="" />
                      </div>
                      <div class="flex-1 min-w-0">
                        <h4 class="text-sm font-bold text-[#141414] line-clamp-2">{post.title}</h4>
                        <%= if post.category do %>
                          <span class="inline-block mt-1 px-2 py-0.5 bg-neutral-100 text-neutral-600 rounded-full text-xs">
                            {post.category.name}
                          </span>
                        <% end %>
                      </div>
                    </.link>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>

          <nav class="hidden md:flex items-center gap-7 text-[13px] text-neutral-700">
            <.header_nav_link href={~p"/"} active={@active == "home"}>Home</.header_nav_link>
            <.header_nav_link href={~p"/hubs"} active={@active == "hubs"}>Hubs</.header_nav_link>
            <.header_nav_link href={~p"/shop"} active={@active == "shop"}>Shop</.header_nav_link>
            <.header_nav_link href={~p"/play"} active={@active == "play"}>Play</.header_nav_link>
            <.header_nav_link href={~p"/pool"} active={@active == "pool"}>Pool</.header_nav_link>
            <.header_nav_link href={~p"/airdrop"} active={@active == "airdrop"}>Airdrop</.header_nav_link>
          </nav>
        </div>

        <%!-- Right --%>
        <div class="flex items-center gap-2 shrink-0">
          <%= if @current_user do %>
            <%!-- Notifications bell with dropdown --%>
            <div class="relative" id="ds-notification-bell">
              <button
                type="button"
                phx-click="toggle_notification_dropdown"
                class="relative w-9 h-9 flex items-center justify-center rounded-full bg-neutral-100 hover:bg-neutral-200 transition-colors cursor-pointer"
                aria-label="Notifications"
              >
                <svg class="w-4 h-4 text-[#141414]" viewBox="0 0 24 24" fill="currentColor">
                  <path fill-rule="evenodd" d="M5.25 9a6.75 6.75 0 0 1 13.5 0v.75c0 2.123.8 4.057 2.118 5.52a.75.75 0 0 1-.297 1.206c-1.544.57-3.16.99-4.831 1.243a3.75 3.75 0 1 1-7.48 0 24.585 24.585 0 0 1-4.831-1.244.75.75 0 0 1-.298-1.205A8.217 8.217 0 0 0 5.25 9.75V9Zm4.502 8.9a2.25 2.25 0 1 0 4.496 0 25.057 25.057 0 0 1-4.496 0Z" clip-rule="evenodd" />
                </svg>
                <%= if @unread_notification_count > 0 do %>
                  <span class="absolute -top-1 -right-1 bg-red-500 text-white text-[10px] font-bold rounded-full min-w-[18px] h-[18px] flex items-center justify-center px-1">
                    {if @unread_notification_count > 99, do: "99+", else: @unread_notification_count}
                  </span>
                <% end %>
              </button>

              <%!-- Notification dropdown panel --%>
              <%= if @notification_dropdown_open do %>
                <div id="ds-notification-dropdown" class="absolute right-0 top-12 w-96 bg-white rounded-2xl shadow-2xl border border-gray-100 z-50 overflow-hidden" phx-click-away="close_notification_dropdown">
                  <div class="flex items-center justify-between px-4 py-3 border-b border-gray-100">
                    <h3 class="font-bold text-[#141414] text-sm">Notifications</h3>
                    <%= if @unread_notification_count > 0 do %>
                      <button phx-click="mark_all_notifications_read" class="text-xs text-gray-500 hover:text-[#141414] cursor-pointer">Mark all read</button>
                    <% end %>
                  </div>
                  <div class="max-h-[420px] overflow-y-auto divide-y divide-gray-50">
                    <%= if @recent_notifications == [] do %>
                      <div class="py-12 text-center text-gray-400 text-sm">No notifications yet</div>
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
                              <svg class="w-5 h-5 text-black" viewBox="0 0 24 24" fill="currentColor">
                                <path fill-rule="evenodd" d="M5.25 9a6.75 6.75 0 0 1 13.5 0v.75c0 2.123.8 4.057 2.118 5.52a.75.75 0 0 1-.297 1.206c-1.544.57-3.16.99-4.831 1.243a3.75 3.75 0 1 1-7.48 0 24.585 24.585 0 0 1-4.831-1.244.75.75 0 0 1-.298-1.205A8.217 8.217 0 0 0 5.25 9.75V9Zm4.502 8.9a2.25 2.25 0 1 0 4.496 0 25.057 25.057 0 0 1-4.496 0Z" clip-rule="evenodd" />
                              </svg>
                            </div>
                          <% end %>
                          <div class="flex-1 min-w-0">
                            <p class={"text-sm truncate #{if is_nil(notification.read_at), do: "font-bold text-[#141414]", else: "text-gray-600"}"}>
                              {notification.title}
                            </p>
                            <p class="text-xs text-gray-500 mt-0.5 line-clamp-2">{notification.body}</p>
                            <p class="text-[10px] text-gray-400 mt-1">{format_notification_time(notification.inserted_at)}</p>
                          </div>
                          <%= if is_nil(notification.read_at) do %>
                            <div class="w-2 h-2 rounded-full bg-blue-500 flex-shrink-0 mt-2"></div>
                          <% end %>
                        </div>
                      <% end %>
                    <% end %>
                  </div>
                  <div class="flex items-center justify-between px-4 py-2.5 border-t border-gray-100 bg-gray-50/50">
                    <.link navigate={~p"/notifications"} class="text-xs font-bold text-[#141414] hover:underline">View all</.link>
                    <.link navigate={~p"/notifications/settings"} class="text-xs text-gray-500 hover:text-[#141414] flex items-center gap-1">
                      <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="currentColor">
                        <path fill-rule="evenodd" d="M7.84 1.804A1 1 0 0 1 8.82 1h2.36a1 1 0 0 1 .98.804l.331 1.652a6.993 6.993 0 0 1 1.929 1.115l1.598-.54a1 1 0 0 1 1.186.447l1.18 2.044a1 1 0 0 1-.205 1.251l-1.267 1.113a7.047 7.047 0 0 1 0 2.228l1.267 1.113a1 1 0 0 1 .206 1.25l-1.18 2.045a1 1 0 0 1-1.187.447l-1.598-.54a6.993 6.993 0 0 1-1.929 1.115l-.33 1.652a1 1 0 0 1-.98.804H8.82a1 1 0 0 1-.98-.804l-.331-1.652a6.993 6.993 0 0 1-1.929-1.115l-1.598.54a1 1 0 0 1-1.186-.447l-1.18-2.044a1 1 0 0 1 .205-1.251l1.267-1.114a7.05 7.05 0 0 1 0-2.227L1.821 7.773a1 1 0 0 1-.206-1.25l1.18-2.045a1 1 0 0 1 1.187-.447l1.598.54A6.992 6.992 0 0 1 7.51 3.456l.33-1.652ZM10 13a3 3 0 1 0 0-6 3 3 0 0 0 0 6Z" clip-rule="evenodd" />
                      </svg>
                      Settings
                    </.link>
                  </div>
                </div>
              <% end %>
            </div>

            <%!-- Cart icon --%>
            <.link
              navigate={~p"/cart"}
              class="relative w-9 h-9 flex items-center justify-center rounded-full bg-neutral-100 hover:bg-neutral-200 transition-colors"
              aria-label="Cart"
            >
              <svg class="w-4 h-4 text-[#141414]" viewBox="0 0 24 24" fill="currentColor">
                <path fill-rule="evenodd" d="M7.5 6v.75H5.513c-.96 0-1.764.724-1.865 1.679l-1.263 12A1.875 1.875 0 0 0 4.25 22.5h15.5a1.875 1.875 0 0 0 1.865-2.071l-1.263-12a1.875 1.875 0 0 0-1.865-1.679H16.5V6a4.5 4.5 0 1 0-9 0ZM12 3a3 3 0 0 0-3 3v.75h6V6a3 3 0 0 0-3-3Z" clip-rule="evenodd" />
              </svg>
              <%= if @cart_item_count > 0 do %>
                <span class="absolute -top-1 -right-1 bg-[#CAFC00] text-[#141414] text-[10px] font-bold rounded-full min-w-[18px] h-[18px] flex items-center justify-center px-1">
                  {@cart_item_count}
                </span>
              <% end %>
            </.link>

            <%!-- User dropdown (token pill + avatar) --%>
            <div class="relative" id="ds-user-dropdown" phx-click-away={JS.hide(to: "#ds-header-user-menu")}>
              <button id="ds-user-button" phx-click={JS.toggle(to: "#ds-header-user-menu")} class="flex items-center gap-2 h-10 rounded-full bg-neutral-100 pl-2 pr-3 hover:bg-neutral-200 transition-colors cursor-pointer">
                <img src={@display_token_icon} alt={@display_token} class="w-6 h-6 rounded-full object-cover" />
                <span class="text-[13px] font-bold text-[#141414] font-mono tabular-nums">{@formatted_display_balance}</span>
                <span class="text-[11px] text-neutral-500">{@display_token}</span>
                <svg class="w-4 h-4 ml-0.5 text-neutral-400" viewBox="0 0 24 24" fill="none">
                  <path d="M8 10L12 14L16 10" stroke="currentColor" stroke-width="1.5" stroke-linecap="square" />
                </svg>
              </button>
              <%!-- User dropdown menu --%>
              <div id="ds-header-user-menu" class="absolute right-0 mt-2 w-48 bg-white rounded-lg shadow-lg border border-gray-200 hidden z-50">
                <div class="py-1">
                  <.link
                    navigate={~p"/member/#{@user_slug}"}
                    class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors font-semibold"
                  >
                    My Profile
                  </.link>
                  <%!-- Token balance detail --%>
                  <div class="border-t border-gray-100 py-1">
                    <% bux_detail = Map.get(@token_balances, "BUX", 0) %>
                    <div class="flex items-center justify-between px-4 py-1.5 text-xs text-gray-600">
                      <div class="flex items-center gap-2">
                        <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="BUX" class="w-4 h-4 rounded-full object-cover" />
                        <span class="font-medium">BUX</span>
                      </div>
                      <span class="font-mono tabular-nums">{Number.Delimit.number_to_delimited(bux_detail, precision: 2)}</span>
                    </div>
                  </div>
                  <div class="border-t border-gray-100"></div>
                  <button
                    phx-click="disconnect_wallet"
                    class="w-full text-left px-4 py-2 text-sm text-red-600 hover:bg-red-50 transition-colors cursor-pointer"
                  >
                    Disconnect Wallet
                  </button>
                  <%!-- Admin section --%>
                  <%= if @current_user.is_author || @current_user.is_admin do %>
                    <div class="border-t border-gray-100 my-1"></div>
                    <div class="px-4 py-1 text-xs text-gray-400 font-semibold uppercase">Admin</div>
                    <.link navigate={~p"/new"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Create Article</.link>
                    <%= if @current_user.is_admin do %>
                      <.link navigate={~p"/admin"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Dashboard</.link>
                      <.link navigate={~p"/admin/posts"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Posts</.link>
                      <.link navigate={~p"/admin/events"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Events</.link>
                      <.link navigate={~p"/admin/campaigns"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Campaigns</.link>
                      <.link navigate={~p"/admin/categories"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Categories</.link>
                      <.link navigate={~p"/hubs/admin"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Hubs</.link>
                      <.link navigate={~p"/admin/products"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Products</.link>
                      <.link navigate={~p"/admin/orders"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Orders</.link>
                      <.link navigate={~p"/admin/product-categories"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Product Categories</.link>
                      <.link navigate={~p"/admin/product-tags"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Product Tags</.link>
                      <.link navigate={~p"/admin/artists"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Artists</.link>
                      <.link navigate={~p"/admin/waitlist"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Waitlist</.link>
                      <.link navigate={~p"/admin/flagged-accounts"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Flagged Accounts</.link>
                      <.link navigate={~p"/admin/stats"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Bet Stats</.link>
                      <.link navigate={~p"/admin/content"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Content Generator</.link>
                      <div class="border-t border-gray-100 my-1"></div>
                      <.link navigate={~p"/admin/notifications/campaigns"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Notification Campaigns</.link>
                      <.link navigate={~p"/admin/notifications/analytics"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Notification Analytics</.link>
                      <.link navigate={~p"/admin/ai-manager"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">AI Manager</.link>
                      <.link navigate={~p"/admin/banners"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Ad Banners</.link>
                      <.link navigate={~p"/admin/promo"} class="block w-full text-left px-4 py-2 text-sm text-gray-700 hover:bg-gray-50 transition-colors">Promo Dashboard</.link>
                    <% end %>
                  <% end %>
                </div>
              </div>
            </div>
          <% else %>
            <%!-- Anonymous: Connect Wallet --%>
            <button
              type="button"
              phx-click="show_wallet_selector"
              disabled={@connecting}
              class={"hidden sm:inline-flex items-center gap-2 px-4 py-2 rounded-full text-[12px] font-bold transition-colors cursor-pointer disabled:cursor-not-allowed #{if @connecting, do: "bg-gray-200 text-gray-400", else: "bg-[#0a0a0a] text-white hover:bg-[#1a1a22]"}"}
            >
              <%= if @connecting do %>
                <svg class="w-4 h-4 animate-spin" fill="none" viewBox="0 0 24 24">
                  <circle class="opacity-20" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="3"></circle>
                  <path class="opacity-80" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"></path>
                </svg>
                Connecting...
              <% else %>
                <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
                  <rect x="2" y="6" width="20" height="14" rx="2" />
                  <path d="M22 10h-4a2 2 0 100 4h4" />
                </svg>
                Connect Wallet
              <% end %>
            </button>
          <% end %>
        </div>
      </div>

      <.why_earn_bux_banner :if={@show_why_earn_bux} />
    </header>
    """
  end

  attr :href, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  defp header_nav_link(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "ds-header__nav-link transition-colors",
        @active && "text-neutral-900 font-bold border-b-2 border-[#CAFC00] -mb-[15px] pb-[15px]",
        !@active && "hover:text-neutral-900"
      ]}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end

  defp format_bux(nil), do: "0.00"

  defp format_bux(n) when is_number(n) or is_struct(n, Decimal),
    do: Number.Delimit.number_to_delimited(n, precision: 2)

  defp format_bux(_), do: "0.00"

  defp format_display_balance("SOL", n) when is_number(n) or is_struct(n, Decimal),
    do: Number.Delimit.number_to_delimited(n, precision: 4)

  defp format_display_balance("SOL", _), do: "0.0000"
  defp format_display_balance(_, n), do: format_bux(n)

  defp display_token_icon("SOL"), do: "https://ik.imagekit.io/blockster/solana-sol-logo.png"
  defp display_token_icon(_), do: "https://ik.imagekit.io/blockster/blockster-icon.png"

  defp format_notification_time(nil), do: ""

  defp format_notification_time(dt) do
    now = NaiveDateTime.utc_now()
    diff = NaiveDateTime.diff(now, dt, :second)

    cond do
      diff < 60 -> "just now"
      diff < 3600 -> "#{div(diff, 60)}m ago"
      diff < 86_400 -> "#{div(diff, 3600)}h ago"
      diff < 604_800 -> "#{div(diff, 86_400)}d ago"
      true -> Calendar.strftime(dt, "%b %d")
    end
  end

  defp user_slug(nil), do: ""
  defp user_slug(%{slug: slug}) when is_binary(slug) and slug != "", do: slug
  defp user_slug(%{wallet_address: addr}) when is_binary(addr), do: addr
  defp user_slug(_), do: ""

  defp user_initials(nil), do: "??"

  defp user_initials(%{} = user) do
    cond do
      is_binary(Map.get(user, :username)) and Map.get(user, :username) != "" ->
        initials_from_string(user.username)

      is_binary(Map.get(user, :wallet_address)) and Map.get(user, :wallet_address) != "" ->
        user.wallet_address |> String.slice(0, 2) |> String.upcase()

      true ->
        "??"
    end
  end

  defp initials_from_string(string) do
    string
    |> String.split(~r/\s+/, trim: true)
    |> Enum.take(2)
    |> Enum.map_join("", &String.first/1)
    |> String.upcase()
    |> case do
      "" -> "??"
      i -> i
    end
  end

  # ── <.footer /> ─────────────────────────────────────────────────────────────
  #
  # The dark footer shared across every page. Mission line, address row,
  # link columns, newsletter form, bottom utility row with media kit link.
  # Locked content per design_system.md and D2.

  @doc """
  Renders the redesigned dark site footer.
  """
  attr :class, :string, default: nil
  attr :rest, :global

  def footer(assigns) do
    ~H"""
    <footer
      class={[
        "ds-footer mt-20 bg-[#0a0a0a] text-white relative overflow-hidden",
        @class
      ]}
      {@rest}
    >
      <div class="absolute top-0 right-0 w-[40%] h-full bg-gradient-to-l from-[#CAFC00]/[0.04] to-transparent pointer-events-none"></div>
      <div class="absolute top-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-white/10 to-transparent"></div>

      <div class="max-w-[1280px] mx-auto px-6 py-16 relative">
        <div class="grid grid-cols-12 gap-8">
          <%!-- Brand block --%>
          <div class="col-span-12 md:col-span-5">
            <div class="flex items-center mb-5">
              <.logo size="22px" variant="dark" />
            </div>
            <h3 class="font-bold text-[28px] leading-[1.1] text-white max-w-[360px] tracking-tight mb-4">
              Where the chain meets the model.
            </h3>
            <p class="text-white/55 text-[13px] leading-relaxed max-w-[360px]">
              Blockster is a decentralized publishing platform where readers earn BUX for engaging with the best writing in crypto and AI — and where every dollar of attention is settled on chain.
            </p>
            <div class="mt-5 flex items-start gap-2 text-[11px] text-white/40 leading-relaxed max-w-[360px]">
              <svg class="w-3 h-3 mt-0.5 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z" />
                <circle cx="12" cy="10" r="3" />
              </svg>
              <span>1111 Lincoln Road, Suite 500 · Miami Beach, FL 33139 · USA</span>
            </div>
          </div>

          <%!-- Read column --%>
          <div class="col-span-6 md:col-span-2">
            <div class="text-[10px] uppercase tracking-[0.14em] text-white/40 font-bold mb-4">Read</div>
            <ul class="space-y-2.5 text-[13px]">
              <li><.link navigate={~p"/hubs"} class="text-white/70 hover:text-white transition-colors">Hubs</.link></li>
              <li><a href="#" class="text-white/70 hover:text-white transition-colors">Categories</a></li>
              <li><a href="#" class="text-white/70 hover:text-white transition-colors">Authors</a></li>
              <li><.link navigate={~p"/"} class="text-white/70 hover:text-white transition-colors">Latest</.link></li>
              <li><a href="#" class="text-white/70 hover:text-white transition-colors">Trending</a></li>
            </ul>
          </div>

          <%!-- Earn column --%>
          <div class="col-span-6 md:col-span-2">
            <div class="text-[10px] uppercase tracking-[0.14em] text-white/40 font-bold mb-4">Earn</div>
            <ul class="space-y-2.5 text-[13px]">
              <li><a href="#" class="text-white/70 hover:text-white transition-colors">BUX Token</a></li>
              <li><.link navigate={~p"/pool"} class="text-white/70 hover:text-white transition-colors">Pool</.link></li>
              <li><.link navigate={~p"/play"} class="text-white/70 hover:text-white transition-colors">Play</.link></li>
              <li><.link navigate={~p"/airdrop"} class="text-white/70 hover:text-white transition-colors">Airdrops</.link></li>
              <li><.link navigate={~p"/shop"} class="text-white/70 hover:text-white transition-colors">Shop</.link></li>
            </ul>
          </div>

          <%!-- Newsletter --%>
          <div class="col-span-12 md:col-span-3">
            <div class="text-[10px] uppercase tracking-[0.14em] text-white/40 font-bold mb-4">Stay in the loop</div>
            <p class="text-[13px] text-white/60 leading-relaxed mb-3">
              The best of crypto × AI, every Friday. No spam, no shilling.
            </p>
            <form class="flex items-center gap-2" phx-submit="newsletter_subscribe">
              <input
                type="email"
                name="email"
                placeholder="you@somewhere.com"
                class="flex-1 min-w-0 bg-white/[0.06] border border-white/10 rounded-md px-3 py-2 text-[12px] text-white placeholder-white/30 focus:outline-none focus:border-[#CAFC00]/50"
              />
              <button
                type="submit"
                class="shrink-0 bg-[#CAFC00] text-black px-3.5 py-2 rounded-md text-[12px] font-bold hover:bg-white transition-colors"
              >
                Subscribe
              </button>
            </form>
            <div class="mt-4 flex items-center gap-1.5 text-[10px] text-white/40 font-mono">
              <span class="w-1.5 h-1.5 rounded-full bg-[#22C55E] animate-pulse"></span>
              <span>SOLANA · MAINNET LIVE</span>
            </div>
          </div>
        </div>

        <div class="mt-14 pt-6 border-t border-white/[0.08] flex items-center justify-between flex-wrap gap-4">
          <div class="text-[11px] text-white/40">© 2026 Blockster Inc. · All rights reserved.</div>
          <div class="flex items-center gap-5 text-[11px] text-white/40">
            <a href="#" class="hover:text-[#CAFC00] transition-colors">Media kit</a>
            <a href="#" class="hover:text-white transition-colors">Privacy</a>
            <a href="#" class="hover:text-white transition-colors">Terms</a>
            <a href="#" class="hover:text-white transition-colors">Cookie Policy</a>
            <a href="#" class="hover:text-white transition-colors">Status</a>
          </div>
        </div>
      </div>
    </footer>
    """
  end

  # ── <.page_hero /> ──────────────────────────────────────────────────────────
  #
  # Variant A — editorial title hero. Big article-title heading on the left,
  # 3-stat band on the right. Used by 80% of index pages (hubs, profile, pool,
  # play, airdrop, shop, category, member, etc.).
  #
  # The `:stats` slot accepts up to 3 stat blocks rendered as a 3-col grid on
  # the right side. The optional `:cta` slot puts a CTA cluster below the title.

  @doc """
  Renders the editorial title page hero (Variant A).

      <.page_hero
        eyebrow="The library"
        title="Browse hubs"
        description="Every brand on Blockster, sorted by activity."
      >
        <:stat label="Active hubs" value="142" />
        <:stat label="Posts today" value="48" sub="+12 vs yesterday" />
        <:stat label="BUX in pool" value="2.4M" />
      </.page_hero>
  """
  attr :variant, :string, default: "A", values: ~w(A)
  attr :eyebrow, :string, default: nil
  attr :title, :string, required: true
  attr :description, :string, default: nil
  attr :title_size, :string, default: "xl", values: ~w(md xl)
  attr :class, :string, default: nil

  slot :stat do
    attr :label, :string, required: true
    attr :value, :string, required: true
    attr :sub, :string
  end

  slot :cta

  def page_hero(assigns) do
    ~H"""
    <section class={["ds-page-hero pt-12 pb-10", @class]}>
      <div class="grid grid-cols-12 gap-8 items-end">
        <div class={[
          "col-span-12",
          length(@stat) > 0 && "md:col-span-7",
          length(@stat) == 0 && "md:col-span-12"
        ]}>
          <%= if @eyebrow do %>
            <.eyebrow class="mb-3">{@eyebrow}</.eyebrow>
          <% end %>
          <h1 class={[
            "ds-page-hero__title font-bold tracking-[-0.022em] leading-[0.96] mb-3 text-[#141414]",
            @title_size == "xl" && "text-[44px] md:text-[80px]",
            @title_size == "md" && "text-[36px] md:text-[52px]"
          ]}>
            {@title}
          </h1>
          <%= if @description do %>
            <p class="text-[16px] leading-[1.5] text-neutral-600 max-w-[560px]">
              {@description}
            </p>
          <% end %>
          <%= if @cta != [] do %>
            <div class="mt-6 flex items-center gap-3 flex-wrap">
              {render_slot(@cta)}
            </div>
          <% end %>
        </div>

        <%= if length(@stat) > 0 do %>
          <div class="col-span-12 md:col-span-5">
            <div class={["grid gap-3", stat_grid_class(length(@stat))]}>
              <%= for stat <- @stat do %>
                <div class="bg-white rounded-xl border border-neutral-200/70 p-4 shadow-[0_1px_3px_rgba(0,0,0,0.04)]">
                  <div class="text-[10px] uppercase tracking-[0.14em] text-neutral-400 font-bold mb-2">
                    {stat.label}
                  </div>
                  <div class="font-mono font-bold text-[26px] text-[#141414] leading-none tracking-tight tabular-nums">
                    {stat.value}
                  </div>
                  <%= if Map.get(stat, :sub) do %>
                    <div class="mt-2 text-[10px] text-neutral-500">{stat.sub}</div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>
        <% end %>
      </div>
    </section>
    """
  end

  defp stat_grid_class(1), do: "grid-cols-1"
  defp stat_grid_class(2), do: "grid-cols-2"
  defp stat_grid_class(_), do: "grid-cols-3"

  # ── <.stat_card /> ──────────────────────────────────────────────────────────
  #
  # The white "big number" stat card. Eyebrow + colored icon square + big mono
  # number + sub-text + optional bordered footer with action hint. Used heavily
  # on the profile page and the pool detail page.

  @doc """
  Renders a white stat card.

      <.stat_card label="BUX Balance" value="12,450" unit="BUX" sub="≈ $124.50">
        <:icon>
          <img src={...} class="w-5 h-5" />
        </:icon>
        <:footer>
          <span class="text-neutral-500">Today</span>
          <span class="font-mono font-bold text-[#22C55E]">+ 245 BUX</span>
        </:footer>
      </.stat_card>
  """
  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :unit, :string, default: nil
  attr :sub, :string, default: nil
  attr :icon_bg, :string, default: "#CAFC00", doc: "background color for the icon square"
  attr :class, :string, default: nil

  slot :icon
  slot :footer

  def stat_card(assigns) do
    ~H"""
    <div class={[
      "ds-stat-card bg-white rounded-2xl border border-neutral-200/70 p-6 shadow-[0_1px_3px_rgba(0,0,0,0.04)]",
      @class
    ]}>
      <div class="flex items-start justify-between mb-4">
        <.eyebrow>{@label}</.eyebrow>
        <%= if @icon != [] do %>
          <div
            class="w-9 h-9 rounded-xl grid place-items-center"
            style={"background-color: #{@icon_bg};"}
          >
            {render_slot(@icon)}
          </div>
        <% end %>
      </div>
      <div class="flex items-baseline gap-2 mb-1">
        <span class="font-mono font-bold text-[44px] text-[#141414] leading-none tracking-tight tabular-nums">
          {@value}
        </span>
        <%= if @unit do %>
          <span class="text-[12px] text-neutral-500">{@unit}</span>
        <% end %>
      </div>
      <%= if @sub do %>
        <div class="text-[11px] text-neutral-500">{@sub}</div>
      <% end %>
      <%= if @footer != [] do %>
        <div class="mt-4 pt-4 border-t border-neutral-100 flex items-center justify-between text-[10px]">
          {render_slot(@footer)}
        </div>
      <% end %>
    </div>
    """
  end

  # ── <.post_card /> ──────────────────────────────────────────────────────────
  #
  # The standard suggested-reading / article post card. White, hover lift,
  # 16:9 image on top, hub badge + title + author/time + lime BUX reward pill.
  # The most-reused content card across the whole site.

  @doc """
  Renders a standard article post card.

      <.post_card
        href={~p"/the-quiet-revolution"}
        image="https://picsum.photos/seed/post-1/640/360"
        hub_name="Moonpay"
        hub_color="#7D00FF"
        title="The quiet revolution of on-chain liquidity pools"
        author="Marcus Verren"
        read_minutes={8}
        bux_reward={45}
      />
  """
  attr :href, :string, required: true
  attr :image, :string, required: true
  attr :hub_name, :string, default: nil
  attr :hub_color, :string, default: "#7D00FF"
  attr :title, :string, required: true
  attr :author, :string, default: nil
  attr :read_minutes, :integer, default: nil
  attr :bux_reward, :any, default: nil, doc: "integer to show as +N, or string"
  attr :class, :string, default: nil

  def post_card(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "ds-post-card group block bg-white rounded-2xl border border-neutral-200/70 overflow-hidden",
        "transition-all duration-200 hover:-translate-y-0.5 hover:shadow-lg hover:border-neutral-300",
        @class
      ]}
    >
      <div class="aspect-[16/9] bg-neutral-100 overflow-hidden">
        <img
          src={@image}
          alt=""
          class="w-full h-full object-cover group-hover:scale-[1.02] transition-transform duration-500"
          loading="lazy"
        />
      </div>
      <div class="p-4">
        <%= if @hub_name do %>
          <div class="flex items-center gap-1.5 mb-2">
            <div class="w-4 h-4 rounded" style={"background-color: #{@hub_color};"}></div>
            <span class="text-[9px] uppercase tracking-[0.12em] text-neutral-500">
              {@hub_name}
            </span>
          </div>
        <% end %>
        <h3 class="font-bold text-[15px] text-[#141414] leading-[1.25] mb-3 line-clamp-3 tracking-tight">
          {@title}
        </h3>
        <div class="flex items-center justify-between text-[10px]">
          <div class="flex items-center gap-1.5 text-neutral-500">
            <%= if @author do %>
              <span>{@author}</span>
            <% end %>
            <%= if @author && @read_minutes do %>
              <span class="text-neutral-300">·</span>
            <% end %>
            <%= if @read_minutes do %>
              <span>{@read_minutes} min</span>
            <% end %>
          </div>
          <%= if @bux_reward do %>
            <div class="flex items-center gap-1 bg-[#CAFC00] text-black px-1.5 py-0.5 rounded-full font-bold tabular-nums">
              <img
                src="https://ik.imagekit.io/blockster/blockster-icon.png"
                alt=""
                class="w-2.5 h-2.5 rounded-full"
              />
              {format_reward(@bux_reward)}
            </div>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end

  defp format_reward(n) when is_integer(n) and n >= 0, do: "+#{n}"
  defp format_reward(s) when is_binary(s), do: s
  defp format_reward(_), do: ""

  # ── <.section_header /> ─────────────────────────────────────────────────────
  #
  # The eyebrow + section title + "See all →" link pattern repeated across
  # every named section on the homepage. Used by AI × Crypto, Trending,
  # Hub showcase, Token sales, Watch, From the editors, Hubs you follow,
  # Recommended for you. Tightly coupled to the editorial weight of the design.

  @doc """
  Renders a section header (eyebrow + section title + optional see-all link).

      <.section_header eyebrow="Most read this week" title="Trending">
        <:see_all href="/trending">See all</:see_all>
      </.section_header>
  """
  attr :eyebrow, :string, default: nil
  attr :title, :string, required: true
  attr :title_size, :string, default: "lg", values: ~w(md lg)
  attr :class, :string, default: nil

  slot :see_all do
    attr :href, :string
  end

  slot :inner_block, doc: "optional content rendered to the right of the title (e.g. filter chips)"

  def section_header(assigns) do
    ~H"""
    <div class={["ds-section-header flex items-baseline justify-between mb-6 flex-wrap gap-3", @class]}>
      <div>
        <%= if @eyebrow do %>
          <.eyebrow class="mb-1">{@eyebrow}</.eyebrow>
        <% end %>
        <h2 class={[
          "font-bold tracking-[-0.018em] text-[#141414]",
          @title_size == "lg" && "text-[28px] md:text-[34px]",
          @title_size == "md" && "text-[22px] md:text-[26px]"
        ]}>
          {@title}
        </h2>
      </div>
      <div class="flex items-center gap-2 flex-wrap">
        {render_slot(@inner_block)}
        <%= for see_all <- @see_all do %>
          <.link
            navigate={Map.get(see_all, :href, "#")}
            class="text-[13px] text-neutral-600 hover:text-neutral-900 transition-colors group"
          >
            {render_slot(see_all)}
            <span class="inline-block group-hover:translate-x-0.5 transition-transform">→</span>
          </.link>
        <% end %>
      </div>
    </div>
    """
  end

  # ── <.hero_feature_card /> ──────────────────────────────────────────────────
  #
  # Variant B page hero — magazine cover featured article. Used at the top of
  # the homepage. 7-col image left + 5-col title/byline/CTA right.

  @doc """
  Renders the magazine-cover featured article hero.

      <.hero_feature_card
        href="/the-quiet-revolution"
        image="https://example.com/img.jpg"
        eyebrow="Today's Story"
        eyebrow_meta="Updated 12 minutes ago"
        hub_name="Moonpay"
        hub_color="#7D00FF"
        category="DeFi"
        title="The quiet revolution of on-chain liquidity pools"
        excerpt="How dual-vault bankrolls are rewriting the rules of provably-fair gaming on Solana."
        author="Marcus Verren"
        author_initials="MV"
        read_minutes={8}
        time_ago="2h ago"
        bux_reward={45}
      />
  """
  attr :href, :string, required: true
  attr :image, :string, required: true
  attr :eyebrow, :string, default: "Today's Story"
  attr :eyebrow_meta, :string, default: nil
  attr :hub_name, :string, default: nil
  attr :hub_color, :string, default: "#7D00FF"
  attr :category, :string, default: nil
  attr :title, :string, required: true
  attr :excerpt, :string, default: nil
  attr :author, :string, default: nil
  attr :author_initials, :string, default: nil
  attr :read_minutes, :integer, default: nil
  attr :time_ago, :string, default: nil
  attr :bux_reward, :any, default: nil

  def hero_feature_card(assigns) do
    ~H"""
    <section class="ds-hero-feature pt-10 pb-14">
      <div class="flex items-center gap-3 mb-5">
        <span class="ds-eyebrow font-bold uppercase text-[10px] tracking-[0.16em] text-neutral-400">
          {@eyebrow}
        </span>
        <%= if @eyebrow_meta do %>
          <span class="w-8 h-px bg-neutral-300"></span>
          <span class="text-[10px] tracking-[0.16em] uppercase text-neutral-400">
            {@eyebrow_meta}
          </span>
        <% end %>
      </div>
      <.link navigate={@href} class="block group">
        <div class="grid grid-cols-12 gap-8 items-center">
          <%!-- Image --%>
          <div class="col-span-12 md:col-span-7">
            <div class="aspect-[16/11] rounded-2xl overflow-hidden ring-1 ring-black/5 bg-neutral-100">
              <img
                src={@image}
                alt=""
                class="w-full h-full object-cover group-hover:scale-[1.02] transition-transform duration-700"
              />
            </div>
          </div>
          <%!-- Text --%>
          <div class="col-span-12 md:col-span-5">
            <%= if @hub_name do %>
              <div class="flex items-center gap-2 mb-4">
                <div class="w-5 h-5 rounded" style={"background-color: #{@hub_color};"}></div>
                <span class="text-[12px] font-bold text-[#141414]">{@hub_name}</span>
                <%= if @category do %>
                  <span class="text-neutral-300">·</span>
                  <span class="text-[10px] uppercase tracking-[0.14em] text-neutral-500">
                    {@category}
                  </span>
                <% end %>
              </div>
            <% end %>
            <h1 class="font-bold tracking-[-0.022em] leading-[1.04] text-[#141414] text-[44px] md:text-[52px] mb-5 group-hover:opacity-80 transition-opacity">
              {@title}
            </h1>
            <%= if @excerpt do %>
              <p class="text-[16px] leading-[1.55] text-neutral-600 mb-6 max-w-[480px]">
                {@excerpt}
              </p>
            <% end %>
            <%= if @author do %>
              <div class="flex items-center gap-3 mb-6">
                <%= if @author_initials do %>
                  <.author_avatar initials={@author_initials} size="md" />
                <% end %>
                <div>
                  <div class="text-[13px] font-bold text-[#141414]">{@author}</div>
                  <%= if @read_minutes do %>
                    <div class="text-[11px] text-neutral-500 mt-[1px]">
                      {@read_minutes} min read{if @time_ago, do: " · #{@time_ago}", else: ""}
                    </div>
                  <% end %>
                </div>
                <%= if @bux_reward do %>
                  <div class="ml-auto flex items-center gap-1 bg-[#CAFC00] text-black px-2.5 py-1 rounded-full text-[11px] font-bold">
                    <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="" class="w-3 h-3 rounded-full" />
                    Earn {@bux_reward} BUX
                  </div>
                <% end %>
              </div>
            <% end %>
            <div class="inline-flex items-center gap-2 bg-[#0a0a0a] text-white px-5 py-3 rounded-full text-[13px] font-bold group-hover:bg-[#1a1a22] transition-colors">
              Read article
              <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="none">
                <path d="M3 10h12m0 0l-4-4m4 4l-4 4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
              </svg>
            </div>
          </div>
        </div>
      </.link>
    </section>
    """
  end

  # ── <.hub_card /> ───────────────────────────────────────────────────────────
  #
  # Full-bleed brand-color hub card with logo + name + description + post/reader
  # counts + Follow button. Used in the homepage hub showcase + future hubs index.

  @doc """
  Renders a hub showcase card with the hub's brand-color gradient background.

      <.hub_card
        href="/hub/moonpay"
        name="Moonpay"
        ticker="M"
        primary="#7D00FF"
        secondary="#4A00B8"
        description="The simplest way to buy and sell crypto."
        post_count="142"
        reader_count="8.2k"
      />
  """
  attr :href, :string, required: true
  attr :name, :string, required: true
  attr :ticker, :string, default: nil, doc: "1-3 char ticker shown in the logo square"
  attr :logo_url, :string, default: nil, doc: "optional logo URL to render instead of the ticker"
  attr :primary, :string, required: true
  attr :secondary, :string, required: true
  attr :description, :string, default: nil
  attr :post_count, :string, default: nil
  attr :reader_count, :string, default: nil
  attr :category, :string, default: nil, doc: "optional category badge text (top-right)"
  attr :class, :string, default: nil

  def hub_card(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "ds-hub-card group block rounded-2xl p-5 text-white relative overflow-hidden",
        "transition-all duration-200 hover:-translate-y-0.5 hover:shadow-xl",
        @class
      ]}
      style={"background: linear-gradient(135deg, #{@primary} 0%, #{@secondary} 100%); min-height: 240px;"}
    >
      <%!-- Top-right radial highlight --%>
      <div
        class="absolute inset-0 pointer-events-none"
        style="background: radial-gradient(circle at 80% 20%, rgba(255,255,255,0.18), transparent 60%);"
      ></div>
      <div class="relative z-10 h-full flex flex-col" style="min-height: 200px;">
        <div class="flex items-center justify-between mb-8">
          <div class="w-9 h-9 rounded-md bg-white/15 backdrop-blur grid place-items-center ring-1 ring-white/20">
            <%= cond do %>
              <% @logo_url -> %>
                <img src={@logo_url} alt={@name} class="w-5 h-5 rounded" />
              <% @ticker -> %>
                <span class="text-white font-bold text-[14px]">{@ticker}</span>
              <% true -> %>
                <span class="text-white font-bold text-[14px]">{String.first(@name)}</span>
            <% end %>
          </div>
          <%= if @category do %>
            <div class="text-[9px] uppercase tracking-[0.12em] bg-white/[0.12] backdrop-blur px-2 py-0.5 rounded-full font-bold">
              {@category}
            </div>
          <% end %>
        </div>
        <h3 class="font-bold text-[20px] tracking-tight mb-1">{@name}</h3>
        <%= if @description do %>
          <p class="text-white/75 text-[11px] line-clamp-2 mb-4 mt-auto">{@description}</p>
        <% end %>
        <div class="flex items-center justify-between mt-auto">
          <div class="flex items-center gap-3">
            <%= if @post_count do %>
              <div>
                <span class="text-[14px] font-bold tabular-nums">{@post_count}</span>
                <span class="text-[10px] text-white/65">posts</span>
              </div>
            <% end %>
            <%= if @reader_count do %>
              <div>
                <span class="text-[14px] font-bold tabular-nums">{@reader_count}</span>
                <span class="text-[10px] text-white/65">readers</span>
              </div>
            <% end %>
          </div>
          <span class="bg-black/25 backdrop-blur text-white text-[10px] font-bold px-2.5 py-1 rounded-full ring-1 ring-white/20 group-hover:bg-black/40 transition-colors">
            Visit hub
          </span>
        </div>
      </div>
    </.link>
    """
  end

  # ── <.hub_card_more /> ──────────────────────────────────────────────────────
  #
  # The dashed "+ N more hubs · Browse all" tile that goes at the end of the
  # hub showcase grid. Same dimensions as a regular hub card.

  @doc """
  Renders the "browse all hubs" tile that fills the last slot of the hub showcase grid.
  """
  attr :href, :string, default: "/hubs"
  attr :more_count, :integer, required: true

  def hub_card_more(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class="ds-hub-card-more group block rounded-2xl p-5 bg-white border-2 border-dashed border-neutral-300 hover:border-[#141414] grid place-items-center text-center"
      style="min-height: 240px;"
    >
      <div>
        <div class="w-12 h-12 rounded-full bg-neutral-100 grid place-items-center mx-auto mb-4 group-hover:bg-[#CAFC00] transition-colors">
          <svg class="w-5 h-5 text-neutral-600 group-hover:text-black transition-colors" viewBox="0 0 20 20" fill="none">
            <path d="M3 10h12m0 0l-4-4m4 4l-4 4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" />
          </svg>
        </div>
        <h3 class="font-bold text-[16px] text-[#141414]">+{@more_count} more hubs</h3>
        <p class="text-[11px] text-neutral-500 mt-0.5">Browse all categories</p>
      </div>
    </.link>
    """
  end

  # ── <.hub_feature_card /> ─────────────────────────────────────────────────────
  #
  # Large featured hub card for the hubs index "Featured this week" section.
  # Two internal layouts:
  #   :horizontal  — wide card (5-col or 4-col), stats in a row, follow + visit buttons
  #   :vertical    — narrow card (3-col), stats stacked vertically, full-width follow button

  @doc """
  Renders a large featured hub card with brand-color gradient, badge, follow
  button, and stats. Used in the hubs index "Featured this week" section.

      <.hub_feature_card
        href="/hub/moonpay"
        name="Moonpay"
        ticker="M"
        primary="#7D00FF"
        secondary="#4A00B8"
        description="The simplest way to buy and sell crypto."
        badge="Sponsor"
        post_count="142"
        follower_count="8.2k"
        bux_paid="340k"
        layout={:horizontal}
      />
  """
  attr :href, :string, required: true
  attr :name, :string, required: true
  attr :ticker, :string, default: nil, doc: "1-3 char ticker shown in the logo square"
  attr :logo_url, :string, default: nil, doc: "optional logo URL to render instead of the ticker"
  attr :primary, :string, required: true
  attr :secondary, :string, required: true
  attr :description, :string, default: nil
  attr :badge, :string, default: nil, doc: "badge text — Sponsor, Trending, etc."
  attr :post_count, :string, default: nil
  attr :follower_count, :string, default: nil
  attr :bux_paid, :string, default: nil
  attr :layout, :atom, default: :horizontal, values: [:horizontal, :vertical]
  attr :class, :string, default: nil

  def hub_feature_card(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "ds-hub-feature-card group block rounded-3xl p-8 text-white relative overflow-hidden",
        "transition-all duration-300 hover:-translate-y-1 hover:shadow-[0_30px_60px_-20px_rgba(0,0,0,0.40)]",
        @class
      ]}
      style={"background: linear-gradient(135deg, #{@primary} 0%, #{@secondary} 100%); min-height: 320px;"}
    >
      <%!-- Dot pattern overlay --%>
      <div
        class="absolute inset-0 opacity-15 pointer-events-none"
        style="background-image: radial-gradient(circle at 30% 30%, white 1.5px, transparent 1.5px); background-size: 28px 28px;"
      >
      </div>
      <%!-- Blur glow --%>
      <div class="absolute -top-32 -right-32 w-80 h-80 bg-white/10 rounded-full blur-3xl pointer-events-none">
      </div>
      <div class="relative h-full flex flex-col">
        <%!-- Header: logo + badge --%>
        <div class="flex items-start justify-between mb-12">
          <div class="w-14 h-14 rounded-xl bg-white/15 backdrop-blur grid place-items-center ring-1 ring-white/25 shadow-lg">
            <%= cond do %>
              <% @logo_url -> %>
                <img src={@logo_url} alt={@name} class="w-8 h-8 rounded" />
              <% @ticker -> %>
                <span class="text-white font-bold text-[18px]">{@ticker}</span>
              <% true -> %>
                <span class="text-white font-bold text-[18px]">{String.first(@name)}</span>
            <% end %>
          </div>
          <%= if @badge do %>
            <div class="flex items-center gap-1.5 text-[10px] uppercase tracking-[0.14em] bg-white/15 backdrop-blur px-2.5 py-1 rounded-full font-bold ring-1 ring-white/15">
              <span class="w-1.5 h-1.5 rounded-full bg-[#CAFC00] pulse-dot"></span>
              {@badge}
            </div>
          <% end %>
        </div>
        <%!-- Title + description --%>
        <h3 class="font-bold text-[36px] tracking-tight mb-2 leading-none">{@name}</h3>
        <%= if @description do %>
          <p class="text-white/75 text-[14px] leading-[1.5] mb-6 max-w-[320px]">{@description}</p>
        <% end %>
        <%!-- Stats + actions --%>
        <div class="mt-auto">
          <%= if @layout == :horizontal do %>
            <%!-- Horizontal stats row --%>
            <div class="flex items-center gap-5 mb-5 text-white/85">
              <%= if @post_count do %>
                <div>
                  <span class="font-mono font-bold text-[18px]">{@post_count}</span>
                  <span class="text-[10px] text-white/60 ml-0.5">posts</span>
                </div>
              <% end %>
              <%= if @follower_count do %>
                <div>
                  <span class="font-mono font-bold text-[18px]">{@follower_count}</span>
                  <span class="text-[10px] text-white/60 ml-0.5">followers</span>
                </div>
              <% end %>
              <%= if @bux_paid do %>
                <div>
                  <span class="font-mono font-bold text-[18px]">{@bux_paid}</span>
                  <span class="text-[10px] text-white/60 ml-0.5">BUX</span>
                </div>
              <% end %>
            </div>
            <div class="flex items-center gap-2">
              <span class="bg-black/30 backdrop-blur text-white text-[12px] font-bold px-4 py-2 rounded-full ring-1 ring-white/25 group-hover:bg-black/50 transition-colors">
                + Follow Hub
              </span>
              <span class="text-white/80 group-hover:text-white text-[12px] px-3 py-2 transition-colors">
                Visit →
              </span>
            </div>
          <% else %>
            <%!-- Vertical stats (narrow card) --%>
            <div class="flex flex-col gap-1 mb-5 text-white">
              <%= if @post_count do %>
                <div class="flex items-center justify-between">
                  <span class="text-[10px] uppercase tracking-[0.12em] text-white/65">Posts</span>
                  <span class="font-mono font-bold text-[14px]">{@post_count}</span>
                </div>
              <% end %>
              <%= if @follower_count do %>
                <div class="flex items-center justify-between">
                  <span class="text-[10px] uppercase tracking-[0.12em] text-white/65">Followers</span>
                  <span class="font-mono font-bold text-[14px]">{@follower_count}</span>
                </div>
              <% end %>
              <%= if @bux_paid do %>
                <div class="flex items-center justify-between">
                  <span class="text-[10px] uppercase tracking-[0.12em] text-white/65">BUX paid</span>
                  <span class="font-mono font-bold text-[14px]">{@bux_paid}</span>
                </div>
              <% end %>
            </div>
            <span class="block w-full text-center bg-black/25 backdrop-blur text-white text-[12px] font-bold px-4 py-2.5 rounded-full ring-1 ring-white/25 group-hover:bg-black/40 transition-colors">
              + Follow Hub
            </span>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end

  # ── <.coming_soon_card /> ───────────────────────────────────────────────────
  #
  # Stub placeholder card for sections whose backend ships in a later release.
  # Per the redesign release plan stub policy: "prefer visible Coming soon
  # placeholders over hidden sections; honest about what's missing; card-shaped,
  # inert button, clear copy."
  #
  # Variants drive the visual treatment:
  #   token_sale  → matches the token sale card outer frame (gradient stripe + brand block)
  #   recommended → simpler horizontal card matching the recommendation card layout

  @doc """
  Renders a "Coming soon" placeholder card. The shape matches the future real
  component so the swap is a 1-line template change when the backend lights up.

      <.coming_soon_card variant="token_sale" title="First sale launches soon" />
      <.coming_soon_card variant="recommended" />
  """
  attr :variant, :string, required: true, values: ~w(token_sale recommended)
  attr :title, :string, default: nil
  attr :body, :string, default: nil

  def coming_soon_card(assigns) do
    assigns =
      assigns
      |> assign_new(:default_title, fn ->
        case assigns.variant do
          "token_sale" -> "First sale launches soon"
          "recommended" -> "Personalized recommendations are on the way"
        end
      end)
      |> assign_new(:default_body, fn ->
        case assigns.variant do
          "token_sale" -> "We're launching token sales for BUX-tier holders soon. Check back here when allocations open."
          "recommended" -> "We're building a recommendation system that surfaces posts based on what you've already read. Until then, your followed hubs and the trending feed below have you covered."
        end
      end)

    ~H"""
    <div class={[
      "ds-coming-soon-card block bg-white rounded-2xl border border-dashed border-neutral-300",
      @variant == "token_sale" && "overflow-hidden shadow-[0_1px_3px_rgba(0,0,0,0.04)]",
      @variant == "recommended" && "p-5"
    ]}>
      <%= if @variant == "token_sale" do %>
        <div class="h-1 bg-neutral-200"></div>
        <div class="p-5">
          <div class="flex items-start justify-between mb-4">
            <div class="flex items-center gap-3">
              <div class="w-12 h-12 rounded-xl grid place-items-center bg-neutral-100">
                <svg class="w-5 h-5 text-neutral-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
                  <circle cx="12" cy="12" r="10" />
                  <path d="M12 6v6l4 2" />
                </svg>
              </div>
              <div>
                <h3 class="font-bold text-[15px] text-[#141414] tracking-tight leading-tight">
                  {@title || @default_title}
                </h3>
                <div class="text-[10px] font-mono text-neutral-400">Coming soon</div>
              </div>
            </div>
            <span class="inline-flex items-center gap-1 bg-neutral-100 text-neutral-500 border border-neutral-200 px-2 py-0.5 rounded-full text-[9px] font-bold uppercase tracking-wider">
              Soon
            </span>
          </div>
          <p class="text-[11px] text-neutral-500 leading-relaxed">
            {@body || @default_body}
          </p>
          <div class="mt-4 pt-3 border-t border-neutral-100 flex items-center justify-between">
            <div class="text-[10px] text-neutral-400">Notify me when it launches</div>
            <span class="inline-flex items-center gap-1 bg-neutral-100 border border-neutral-200 text-neutral-400 px-3 py-1.5 rounded-full text-[10px] font-bold cursor-not-allowed">
              Notify me
            </span>
          </div>
        </div>
      <% end %>
      <%= if @variant == "recommended" do %>
        <div class="flex items-start gap-4">
          <div class="w-12 h-12 rounded-xl bg-neutral-100 grid place-items-center shrink-0">
            <svg class="w-5 h-5 text-neutral-400" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
              <path d="M12 2l3 7h7l-5.5 4 2 7-6.5-4.5L5.5 20l2-7L2 9h7z" />
            </svg>
          </div>
          <div class="flex-1 min-w-0">
            <h3 class="font-bold text-[14px] text-[#141414] mb-1">
              {@title || @default_title}
            </h3>
            <p class="text-[12px] text-neutral-500 leading-relaxed">
              {@body || @default_body}
            </p>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # ── <.welcome_hero /> ───────────────────────────────────────────────────────
  #
  # The dark gradient anonymous-only CTA section. Welcome eyebrow in lime,
  # huge dual-tone title, Connect Wallet button, stats row, tilted preview card.
  # Only ever rendered on the homepage when @current_user == nil.

  @doc """
  Renders the dark anonymous Welcome / Connect Wallet hero.
  """
  attr :article_count, :string, default: "12,450"
  attr :bux_paid, :string, default: "4.2M"
  attr :hub_count, :string, default: "66"
  attr :preview_image, :string, default: nil
  attr :preview_title, :string, default: nil
  attr :preview_hub_name, :string, default: nil
  attr :preview_hub_color, :string, default: "#7D00FF"
  attr :preview_category, :string, default: nil
  attr :preview_author, :string, default: nil
  attr :preview_read_minutes, :integer, default: nil
  attr :preview_bux_reward, :any, default: nil

  def welcome_hero(assigns) do
    ~H"""
    <section class="ds-welcome-hero pt-12 pb-6 mt-8">
      <div class="grid grid-cols-12 gap-8 items-center bg-gradient-to-br from-[#0a0a0a] via-[#1a1a22] to-[#0a0a0a] rounded-3xl overflow-hidden p-12 ring-1 ring-white/10 relative">
        <div class="absolute top-0 right-0 w-[60%] h-full bg-gradient-to-l from-[#CAFC00]/[0.06] to-transparent pointer-events-none"></div>
        <div class="absolute bottom-0 left-0 w-[40%] h-[60%] bg-gradient-to-tr from-[#7D00FF]/15 to-transparent blur-3xl pointer-events-none"></div>
        <div class="col-span-12 md:col-span-7 relative">
          <div class="font-bold uppercase text-[10px] tracking-[0.16em] mb-4 text-[#CAFC00]">
            Welcome to Blockster
          </div>
          <h2 class="font-bold tracking-[-0.022em] leading-[1.04] text-white text-[44px] md:text-[58px] mb-5 max-w-[640px]">
            The chain meets the model. <span class="text-white/45">Read it daily.</span>
          </h2>
          <p class="text-white/65 text-[16px] leading-[1.55] max-w-[520px] mb-7">
            Blockster is a publication about the intersection of crypto and AI. We pay readers BUX for engaging with the best writing in the space — and every dollar of attention is settled on chain.
          </p>
          <div class="flex items-center gap-3 flex-wrap">
            <button
              type="button"
              phx-click="show_wallet_selector"
              class="inline-flex items-center gap-2 bg-[#CAFC00] text-black px-5 py-3 rounded-full text-[14px] font-bold hover:bg-white transition-colors"
            >
              <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
                <rect x="2" y="6" width="20" height="14" rx="2" />
                <path d="M22 10h-4a2 2 0 100 4h4" />
              </svg>
              Connect Wallet to start earning
            </button>
            <a
              href="#"
              class="inline-flex items-center gap-2 text-white/70 hover:text-white transition-colors text-[13px]"
            >
              Or browse without an account
            </a>
          </div>
          <div class="mt-7 flex items-center gap-6 text-white/40 text-[11px] font-mono">
            <div><span class="text-white font-bold tabular-nums">{@article_count}</span> articles</div>
            <div><span class="text-white font-bold tabular-nums">{@bux_paid}</span> BUX paid out</div>
            <div><span class="text-white font-bold tabular-nums">{@hub_count}</span> hubs</div>
          </div>
        </div>
        <%= if @preview_title do %>
          <div class="col-span-12 md:col-span-5 relative">
            <div class="bg-white rounded-2xl p-5 shadow-2xl relative ring-1 ring-white/20 rotate-1 hover:rotate-0 transition-transform">
              <%= if @preview_image do %>
                <div class="aspect-[16/9] rounded-xl bg-neutral-100 overflow-hidden mb-4">
                  <img src={@preview_image} alt="" class="w-full h-full object-cover" />
                </div>
              <% end %>
              <%= if @preview_hub_name do %>
                <div class="flex items-center gap-1.5 mb-2">
                  <div class="w-4 h-4 rounded" style={"background-color: #{@preview_hub_color};"}></div>
                  <span class="text-[9px] uppercase tracking-[0.12em] text-neutral-500">
                    {@preview_hub_name}{if @preview_category, do: " · #{@preview_category}", else: ""}
                  </span>
                </div>
              <% end %>
              <h3 class="font-bold text-[16px] text-[#141414] leading-[1.2] mb-3 tracking-tight">
                {@preview_title}
              </h3>
              <div class="flex items-center justify-between text-[10px]">
                <span class="text-neutral-500">
                  {@preview_author}{if @preview_read_minutes, do: " · #{@preview_read_minutes} min", else: ""}
                </span>
                <%= if @preview_bux_reward do %>
                  <div class="flex items-center gap-1 bg-[#CAFC00] text-black px-2 py-0.5 rounded-full font-bold">
                    <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="" class="w-2.5 h-2.5 rounded-full" />
                    Earn {@preview_bux_reward} BUX
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </section>
    """
  end

  # ── <.what_you_unlock_grid /> ───────────────────────────────────────────────
  #
  # Anonymous-only 3-feature card grid: "Earn BUX as you read" / "Follow 66 hubs"
  # / "Spend BUX on rewards". Static copy. Renders below the welcome hero.

  @doc """
  Renders the 3-feature anonymous CTA grid below the welcome hero.
  """
  attr :hub_count, :integer, default: 66

  def what_you_unlock_grid(assigns) do
    ~H"""
    <section class="ds-what-you-unlock py-12 border-t border-neutral-200/70 mt-8">
      <div class="text-center mb-8">
        <.eyebrow class="mb-2">What you unlock</.eyebrow>
        <h2 class="font-bold tracking-[-0.018em] text-[#141414] text-[28px] md:text-[36px] max-w-[640px] mx-auto">
          Reading is free. Earning is unlocked when you connect a wallet.
        </h2>
      </div>
      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <div class="bg-white rounded-2xl p-6 border border-neutral-200/70">
          <div class="w-10 h-10 rounded-xl bg-[#CAFC00] grid place-items-center mb-4">
            <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="" class="w-6 h-6 rounded-full" />
          </div>
          <h3 class="font-bold text-[16px] text-[#141414] mb-2">Earn BUX as you read</h3>
          <p class="text-[13px] text-neutral-600 leading-relaxed">
            Every article you finish pays out BUX based on how engaged you were. Real tokens, settled on chain.
          </p>
        </div>
        <div class="bg-white rounded-2xl p-6 border border-neutral-200/70">
          <div class="w-10 h-10 rounded-xl bg-[#7D00FF] grid place-items-center mb-4">
            <svg class="w-5 h-5 text-white" viewBox="0 0 24 24" fill="currentColor">
              <circle cx="12" cy="12" r="10" stroke="white" stroke-width="2" fill="none" />
              <circle cx="12" cy="12" r="5" fill="white" />
            </svg>
          </div>
          <h3 class="font-bold text-[16px] text-[#141414] mb-2">Follow {@hub_count} hubs</h3>
          <p class="text-[13px] text-neutral-600 leading-relaxed">
            Curate your own feed by following the hubs you care about. Solana, Bitcoin, Ethereum, Moonpay and more.
          </p>
        </div>
        <div class="bg-white rounded-2xl p-6 border border-neutral-200/70">
          <div class="w-10 h-10 rounded-xl bg-[#0a0a0a] grid place-items-center mb-4">
            <svg class="w-5 h-5 text-[#CAFC00]" viewBox="0 0 24 24" fill="currentColor">
              <path d="M13 2L3 14h7l-1 8 10-12h-7l1-8z" />
            </svg>
          </div>
          <h3 class="font-bold text-[16px] text-[#141414] mb-2">Spend BUX on rewards</h3>
          <p class="text-[13px] text-neutral-600 leading-relaxed">
            Redeem for sponsored airdrops, exclusive merch, and access to events from partners across the ecosystem.
          </p>
        </div>
      </div>
    </section>
    """
  end

  # ──────────────────────────────────────────────────────────────────────
  # Ad Banner Templates — styled ads generated from admin params
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  Renders a template-based ad banner. Dispatches to the correct template
  based on `banner.template`. Falls back to a simple image banner for
  legacy `image` template or unknown types.
  """
  attr :banner, :map, required: true
  attr :class, :string, default: nil

  def ad_banner(%{banner: %{template: "follow_bar"}} = assigns) do
    assigns = assign(assigns, :p, assigns.banner.params || %{})
    ~H"""
    <a href={@banner.link_url || "#"} class={["not-prose block my-9 group", @class]} phx-click="track_ad_click" phx-value-id={@banner.id}>
      <div class="flex items-center justify-between gap-3 bg-[#0a0a0a] hover:bg-[#1a1a1a] transition-colors rounded-2xl pl-2 pr-3 py-2.5 ring-1 ring-black/10">
        <div class="flex items-center gap-3 min-w-0">
          <div class="w-11 h-11 bg-white grid place-items-center shrink-0 rounded-md">
            <%= if @p["icon_url"] do %>
              <img src={@p["icon_url"]} alt="" class="w-6 h-6 rounded object-cover" />
            <% else %>
              <div class="w-6 h-6 rounded grid place-items-center" style={"background: #{@p["brand_color"] || "#7D00FF"}"}>
                <div class="w-3 h-3 rounded-full bg-white"></div>
              </div>
            <% end %>
          </div>
          <span class="text-white font-bold text-[15px] truncate">{@p["heading"] || "Follow in Hubs"}</span>
        </div>
        <div class="w-9 h-9 rounded-full bg-white grid place-items-center shrink-0 group-hover:scale-105 transition-transform">
          <svg class="w-4 h-4" style={"color: #{@p["brand_color"] || "#7D00FF"}"} viewBox="0 0 20 20" fill="currentColor">
            <path d="M10 4v12M4 10h12" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"/>
          </svg>
        </div>
      </div>
    </a>
    """
  end

  def ad_banner(%{banner: %{template: "dark_gradient"}} = assigns) do
    assigns = assign(assigns, :p, assigns.banner.params || %{})
    ~H"""
    <div class={["my-10 -mx-2 not-prose", @class]}>
      <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold pl-2">Sponsored</div>
      <a href={@banner.link_url || "#"} class="block group" phx-click="track_ad_click" phx-value-id={@banner.id}>
        <div class="relative rounded-2xl overflow-hidden bg-gradient-to-br from-[#0A0A0F] via-[#14141A] to-[#1c1c25] p-6 shadow-[0_20px_40px_-15px_rgba(0,0,0,0.25)] ring-1 ring-white/[0.06]">
          <div class="absolute top-0 right-0 w-64 h-64 bg-gradient-to-br to-transparent blur-3xl pointer-events-none" style={"background: #{@p["brand_color"] || "#7D00FF"}30"}></div>
          <div class="absolute bottom-0 left-0 w-48 h-48 bg-gradient-to-tr from-[#CAFC00]/15 to-transparent blur-3xl pointer-events-none"></div>
          <div class="relative flex items-center justify-between gap-6">
            <div class="flex-1">
              <div class="flex items-center gap-2 mb-3">
                <%= if @p["icon_url"] do %>
                  <img src={@p["icon_url"]} alt="" class="w-7 h-7 rounded-md object-cover" />
                <% else %>
                  <div class="w-7 h-7 rounded-md grid place-items-center" style={"background: #{@p["brand_color"] || "#7D00FF"}"}>
                    <div class="w-3.5 h-3.5 rounded-full bg-white"></div>
                  </div>
                <% end %>
                <span class="text-[11px] uppercase tracking-[0.14em] text-white/60">{@p["brand_name"] || "Sponsor"}</span>
              </div>
              <h3 class="text-white font-bold text-[22px] leading-[1.15] mb-2 max-w-[380px]">{@p["heading"]}</h3>
              <p class="text-white/60 text-[13px] leading-snug max-w-[420px]">{@p["description"]}</p>
            </div>
            <div class="flex-shrink-0 hidden md:block">
              <div class="inline-flex items-center gap-2 bg-[#CAFC00] text-black px-4 py-2.5 rounded-full font-bold text-[13px] group-hover:bg-white transition-colors">
                {@p["cta_text"] || "Learn more"}
                <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="none"><path d="M3 10h12m0 0l-4-4m4 4l-4 4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
              </div>
            </div>
          </div>
        </div>
      </a>
    </div>
    """
  end

  def ad_banner(%{banner: %{template: "portrait"}} = assigns) do
    assigns = assign(assigns, :p, assigns.banner.params || %{})
    ~H"""
    <div class={["not-prose my-12 flex justify-center", @class]}>
      <div class="text-center">
        <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold">Sponsored</div>
        <a href={@banner.link_url || "#"} class="block group max-w-[440px] mx-auto" phx-click="track_ad_click" phx-value-id={@banner.id}>
          <div class="rounded-2xl overflow-hidden ring-1 ring-black/5 shadow-[0_30px_60px_-15px_rgba(0,0,0,0.18)] relative" style={"background: #{@p["bg_color"] || "#0a1838"}"}>
            <%= if @p["image_url"] do %>
              <div class="aspect-[4/3] bg-neutral-200 relative overflow-hidden">
                <img src={@p["image_url"]} alt="" class="w-full h-full object-cover" />
                <div class="absolute top-3 right-3 w-6 h-6 border-t-2 border-r-2" style={"border-color: #{@p["accent_color"] || "#FF6B35"}"}></div>
                <div class="absolute top-3 right-3 w-2 h-2" style={"background: #{@p["accent_color"] || "#FF6B35"}"}></div>
                <div class="absolute top-3 left-3 px-1.5 py-0.5 bg-white/95 rounded text-[9px] font-bold uppercase tracking-wider text-neutral-700">Ad</div>
              </div>
            <% end %>
            <div class="px-7 pt-7 pb-6 relative" style={"background: linear-gradient(to bottom, #{@p["bg_color"] || "#0a1838"}, #{@p["bg_color_end"] || "#142a6b"})"}>
              <div class="absolute bottom-4 left-4 w-7 h-7 border-l-2 border-b-2" style={"border-color: #{@p["accent_color"] || "#FF6B35"}"}></div>
              <h3 class="text-white font-bold text-[28px] leading-[1.08] mb-5 max-w-[300px]" style="letter-spacing: -0.02em;">
                {@p["heading"]}
              </h3>
              <div class="text-white font-bold text-[15px] mb-5">{@p["subtitle"]}</div>
              <div class="inline-flex items-center px-4 py-2 border border-white/80 text-white text-[12px] font-bold rounded group-hover:bg-white transition-colors" style={"group-hover:color: #{@p["bg_color"] || "#0a1838"}"}>
                {@p["cta_text"] || "Find out more"}
              </div>
              <%= if @p["brand_name"] do %>
                <div class="mt-5 pt-4 border-t border-white/15 text-right">
                  <span class="text-white text-[20px] tracking-tight" style="font-family: 'Inter', serif; font-weight: 600;">{@p["brand_name"]}</span>
                </div>
              <% end %>
            </div>
          </div>
        </a>
      </div>
    </div>
    """
  end

  def ad_banner(%{banner: %{template: "split_card"}} = assigns) do
    assigns = assign(assigns, :p, assigns.banner.params || %{})
    ~H"""
    <div class={["mt-6", @class]}>
      <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold px-1">Sponsored</div>
      <a href={@banner.link_url || "#"} class="block group" phx-click="track_ad_click" phx-value-id={@banner.id}>
        <div class="relative rounded-2xl overflow-hidden bg-white border border-neutral-200/70 shadow-[0_1px_3px_rgba(0,0,0,0.04)] hover:shadow-[0_18px_30px_-12px_rgba(0,0,0,0.10)] transition-shadow">
          <div class="grid grid-cols-1 md:grid-cols-[1fr_220px] items-stretch">
            <div class="p-7">
              <div class="flex items-center gap-2 mb-4">
                <%= if @p["icon_url"] do %>
                  <img src={@p["icon_url"]} alt="" class="w-6 h-6 rounded-md object-cover" />
                <% else %>
                  <div class="w-6 h-6 rounded-md grid place-items-center" style={"background: #{@p["brand_color"] || "#7D00FF"}"}>
                    <div class="w-3 h-3 rounded-full bg-white"></div>
                  </div>
                <% end %>
                <span class="text-[10px] uppercase tracking-[0.14em] text-neutral-500">{@p["brand_name"] || "Sponsor"}</span>
                <%= if @p["badge"] do %>
                  <span class="text-neutral-300">&middot;</span>
                  <span class="text-[10px] uppercase tracking-[0.14em] text-neutral-500">{@p["badge"]}</span>
                <% end %>
              </div>
              <h3 class="font-bold text-[26px] text-[#141414] mb-2 leading-[1.1]" style="letter-spacing: -0.02em;">{@p["heading"]}</h3>
              <p class="text-neutral-600 text-[14px] leading-snug mb-5 max-w-[520px]">{@p["description"]}</p>
              <div class="inline-flex items-center gap-2 bg-[#0A0A0F] text-white px-4 py-2.5 rounded-full font-bold text-[13px] group-hover:bg-[#1a1a22] transition-colors">
                {@p["cta_text"] || "Learn more"}
                <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="none"><path d="M3 10h12m0 0l-4-4m4 4l-4 4" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>
              </div>
            </div>
            <div class="hidden md:grid relative place-items-center" style={"background: linear-gradient(135deg, #{@p["panel_color"] || "#7D00FF"}, #{@p["panel_color_end"] || "#4A00B8"})"}>
              <div class="absolute inset-0 opacity-20" style="background-image: radial-gradient(circle at 30% 30%, white 1px, transparent 1px); background-size: 16px 16px;"></div>
              <div class="relative text-white text-center">
                <div class="text-[11px] uppercase tracking-[0.14em] opacity-70 mb-1">{@p["stat_label_top"] || ""}</div>
                <div class="font-mono text-4xl font-bold">{@p["stat_value"] || ""}</div>
                <div class="text-[11px] uppercase tracking-[0.14em] opacity-70 mt-1">{@p["stat_label_bottom"] || ""}</div>
              </div>
            </div>
          </div>
        </div>
      </a>
    </div>
    """
  end

  # Fallback: legacy image banner
  def ad_banner(assigns) do
    ~H"""
    <%= if @banner.image_url do %>
      <a href={@banner.link_url || "#"} target="_blank" rel="noopener" class={["block rounded-lg overflow-hidden hover:shadow-lg transition-shadow cursor-pointer", @class]} phx-click="track_ad_click" phx-value-id={@banner.id}>
        <img src={@banner.image_url} alt={@banner.name} class="w-full" loading="lazy" />
      </a>
    <% end %>
    """
  end

  # ──────────────────────────────────────────────────────────────────────
  # Discover Card — article page sidebar · Event / Token Sale / Airdrop
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  A discovery sidebar card for the article page. Three variants share the
  same outer frame (white, rounded-2xl, border) with a colored-dot eyebrow.

  - `variant="event"` — stub: "Coming soon" placeholder (D12)
  - `variant="sale"`  — stub: "Coming soon" placeholder (D12)
  - `variant="airdrop"` — real data from `@round` assign
  """
  attr :variant, :string, required: true, values: ~w(event sale airdrop)
  attr :round, :map, default: nil, doc: "Airdrop round (only used when variant=airdrop)"
  attr :class, :string, default: nil

  def discover_card(%{variant: "event"} = assigns) do
    ~H"""
    <div class={["block bg-white border border-neutral-200/70 rounded-2xl overflow-hidden", @class]}>
      <div class="flex items-center gap-1.5 px-3 py-2 border-b border-neutral-100 text-[9px] font-bold tracking-[0.16em] uppercase text-neutral-400">
        <span class="w-1.5 h-1.5 rounded-full bg-[#7D00FF] shrink-0"></span>
        <svg class="w-[11px] h-[11px] text-neutral-400 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
        Event
      </div>
      <div class="p-3">
        <div class="bg-neutral-50 border border-neutral-200/70 rounded-lg p-4 mb-3 text-center">
          <div class="w-8 h-8 rounded-lg bg-[#7D00FF]/10 grid place-items-center mx-auto mb-2">
            <svg class="w-4 h-4 text-[#7D00FF]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>
          </div>
          <div class="text-[11px] font-bold text-neutral-700 mb-1">Coming soon</div>
          <div class="text-[9px] text-neutral-400 leading-snug">Events launch soon</div>
        </div>
        <span class="flex items-center justify-center gap-1 w-full bg-neutral-100 text-neutral-400 text-[10px] font-bold py-[7px] rounded-full cursor-default">
          Stay tuned
        </span>
      </div>
    </div>
    """
  end

  def discover_card(%{variant: "sale"} = assigns) do
    ~H"""
    <div class={["block bg-white border border-neutral-200/70 rounded-2xl overflow-hidden", @class]}>
      <div class="h-[3px] w-full bg-gradient-to-r from-[#FF6B35] to-[#C73E1D]"></div>
      <div class="flex items-center gap-1.5 px-3 py-2 border-b border-neutral-100 text-[9px] font-bold tracking-[0.16em] uppercase text-neutral-400">
        <span class="w-1.5 h-1.5 rounded-full bg-[#FF6B35] shrink-0"></span>
        <svg class="w-[11px] h-[11px] text-neutral-400 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/></svg>
        Token sale
      </div>
      <div class="p-3">
        <div class="bg-neutral-50 border border-neutral-200/70 rounded-lg p-4 mb-3 text-center">
          <div class="w-8 h-8 rounded-lg bg-[#FF6B35]/10 grid place-items-center mx-auto mb-2">
            <svg class="w-4 h-4 text-[#FF6B35]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="22 12 18 12 15 21 9 3 6 12 2 12"/></svg>
          </div>
          <div class="text-[11px] font-bold text-neutral-700 mb-1">Coming soon</div>
          <div class="text-[9px] text-neutral-400 leading-snug">First sale launches soon</div>
        </div>
        <span class="flex items-center justify-center gap-1 w-full bg-neutral-100 text-neutral-400 text-[10px] font-bold py-[7px] rounded-full cursor-default">
          Stay tuned
        </span>
      </div>
    </div>
    """
  end

  def discover_card(%{variant: "airdrop"} = assigns) do
    ~H"""
    <.link navigate="/airdrop" class={["block bg-white border border-neutral-200/70 rounded-2xl overflow-hidden hover:shadow-md hover:border-neutral-300/70 transition-all", @class]}>
      <div class="flex items-center gap-1.5 px-3 py-2 border-b border-neutral-100 text-[9px] font-bold tracking-[0.16em] uppercase text-neutral-400">
        <span class="w-1.5 h-1.5 rounded-full bg-[#CAFC00] shrink-0"></span>
        <svg class="w-[11px] h-[11px] text-neutral-400 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="20 12 20 22 4 22 4 12"/><rect x="2" y="7" width="20" height="5"/><line x1="12" y1="22" x2="12" y2="7"/><path d="M12 7H7.5a2.5 2.5 0 0 1 0-5C11 2 12 7 12 7z"/><path d="M12 7h4.5a2.5 2.5 0 0 0 0-5C13 2 12 7 12 7z"/></svg>
        Airdrop
        <%= if @round do %>
          <span class="ml-auto font-mono font-medium text-[8px] tracking-[0.04em] normal-case text-neutral-400">round {@round.round_id}</span>
        <% end %>
      </div>
      <div class="p-3">
        <%= if @round do %>
          <div class="flex items-baseline gap-1 mb-1">
            <span class="font-mono font-bold text-[18px] text-[#141414] leading-none tracking-tight">
              Round {@round.round_id}
            </span>
          </div>
          <div class="bg-neutral-50 border border-neutral-200/70 rounded-lg p-2 mb-3 space-y-1">
            <div class="flex items-center justify-between text-[9px]">
              <span class="text-neutral-500">Status</span>
              <span class="font-mono font-bold text-[#141414]">
                {String.capitalize(@round.status || "open")}
              </span>
            </div>
            <%= if @round.total_entries && @round.total_entries > 0 do %>
              <div class="flex items-center justify-between text-[9px]">
                <span class="text-neutral-500">Entries</span>
                <span class="font-mono font-bold text-[#141414]">
                  {Number.Delimit.number_to_delimited(@round.total_entries, precision: 0)}
                </span>
              </div>
            <% end %>
          </div>
          <span class="flex items-center justify-center gap-1 w-full bg-[#0a0a0a] hover:bg-[#1a1a22] text-white text-[10px] font-bold py-[7px] rounded-full transition-colors">
            Redeem BUX to enter
            <svg class="w-2.5 h-2.5" viewBox="0 0 20 20" fill="none"><path d="M3 10h12m0 0l-4-4m4 4l-4 4" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
          </span>
        <% else %>
          <div class="bg-neutral-50 border border-neutral-200/70 rounded-lg p-4 mb-3 text-center">
            <div class="text-[11px] font-bold text-neutral-700 mb-1">No active round</div>
            <div class="text-[9px] text-neutral-400 leading-snug">Check back soon</div>
          </div>
          <span class="flex items-center justify-center gap-1 w-full bg-[#0a0a0a] hover:bg-[#1a1a22] text-white text-[10px] font-bold py-[7px] rounded-full transition-colors">
            View airdrop
            <svg class="w-2.5 h-2.5" viewBox="0 0 20 20" fill="none"><path d="M3 10h12m0 0l-4-4m4 4l-4 4" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
          </span>
        <% end %>
      </div>
    </.link>
    """
  end

  # ──────────────────────────────────────────────────────────────────────
  # Suggest Card — article page suggested reading
  # ──────────────────────────────────────────────────────────────────────

  @doc """
  A suggested-reading card for the article page. Similar to `post_card` but
  with a compact layout: 16:10 image, hub badge, title (3-line clamp),
  author + read time, BUX badge. Hover lift effect.
  """
  attr :href, :string, required: true
  attr :image, :string, default: nil
  attr :hub_name, :string, default: nil
  attr :hub_color, :string, default: nil
  attr :title, :string, required: true
  attr :author, :string, default: nil
  attr :read_minutes, :integer, default: nil
  attr :bux_reward, :any, default: nil
  attr :class, :string, default: nil

  def suggest_card(assigns) do
    ~H"""
    <.link
      navigate={@href}
      class={[
        "block bg-white rounded-2xl border border-neutral-200/70 overflow-hidden",
        "hover:-translate-y-0.5 hover:shadow-[0_18px_30px_-12px_rgba(0,0,0,0.12)] hover:border-neutral-300/80",
        "transition-all duration-200 cursor-pointer",
        @class
      ]}
    >
      <%= if @image do %>
        <div class="aspect-[16/10] bg-neutral-100 overflow-hidden">
          <img src={@image} alt="" class="w-full h-full object-cover" loading="lazy" />
        </div>
      <% end %>
      <div class="p-4">
        <%= if @hub_name do %>
          <div class="flex items-center gap-1.5 mb-2">
            <div class="w-4 h-4 rounded grid place-items-center shrink-0" style={"background: #{@hub_color || "#0a0a0a"}"}>
              <div class="w-1.5 h-1.5 rounded-full bg-white"></div>
            </div>
            <span class="text-[9px] uppercase tracking-[0.12em] text-neutral-500">{@hub_name}</span>
          </div>
        <% end %>
        <h3 class="font-bold text-[15px] text-[#141414] leading-[1.25] mb-3 tracking-tight line-clamp-3">
          {@title}
        </h3>
        <div class="flex items-center justify-between text-[10px]">
          <div class="flex items-center gap-1.5 text-neutral-500">
            <%= if @author do %>
              <span>{@author}</span>
            <% end %>
            <%= if @author && @read_minutes do %>
              <span class="text-neutral-300">&middot;</span>
            <% end %>
            <%= if @read_minutes do %>
              <span>{@read_minutes} min</span>
            <% end %>
          </div>
          <%= if @bux_reward do %>
            <div class="flex items-center gap-1 bg-[#CAFC00] text-black px-1.5 py-0.5 rounded-full font-bold tabular-nums">
              <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="" class="w-2.5 h-2.5 rounded-full" />
              {format_reward(@bux_reward)}
            </div>
          <% end %>
        </div>
      </div>
    </.link>
    """
  end

  # ── <.hub_banner /> ──────────────────────────────────────────────────────────
  #
  # Variant C hero: full-bleed brand-color gradient with dot pattern overlay,
  # identity block, stats row, CTAs, and frosted-glass live activity widget.
  # Used on the hub show page (/hub/:slug).

  attr :hub, :map, required: true, doc: "Hub struct with color_primary/secondary, name, description, logo_url, token"
  attr :post_count, :integer, default: 0
  attr :follower_count, :integer, default: 0
  attr :user_follows_hub, :boolean, default: false
  attr :current_user, :any, default: nil
  attr :class, :string, default: nil
  attr :rest, :global

  def hub_banner(assigns) do
    ~H"""
    <section
      class={"ds-hub-banner relative overflow-hidden text-white #{@class}"}
      style={"background: linear-gradient(135deg, #{@hub.color_primary || "#6B7280"} 0%, #{@hub.color_secondary || "#374151"} 100%)"}
      {@rest}
    >
      <%!-- Dot pattern overlay --%>
      <div class="absolute inset-0 pointer-events-none" style="background-image: radial-gradient(circle at 30% 30%, rgba(255, 255, 255, 0.08) 1.5px, transparent 1.5px); background-size: 32px 32px;"></div>
      <%!-- Top-right blur glow --%>
      <div class="absolute top-0 right-0 w-1/2 h-full pointer-events-none" style="background: radial-gradient(ellipse at top right, rgba(255,255,255,0.12), transparent 60%);"></div>

      <div class="max-w-[1280px] mx-auto px-6 py-12 relative">
        <%!-- Breadcrumb --%>
        <div class="mb-8 flex items-center gap-2 text-[11px] text-white/60">
          <.link navigate={~p"/hubs"} class="hover:text-white transition-colors">Hubs</.link>
          <span>/</span>
          <span class="text-white/85">{@hub.name}</span>
        </div>

        <div class="grid grid-cols-12 gap-8 items-start">
          <div class="col-span-12 md:col-span-8">
            <%!-- Identity block --%>
            <div class="flex items-center gap-5 mb-6">
              <div class="w-20 h-20 rounded-2xl bg-white/15 backdrop-blur grid place-items-center ring-1 ring-white/25 shadow-2xl">
                <%= if @hub.logo_url do %>
                  <img src={@hub.logo_url} alt={@hub.name} class="w-12 h-12 object-contain rounded-lg" />
                <% else %>
                  <span class="text-[24px] font-bold text-white">
                    {String.first(@hub.token || @hub.name)}
                  </span>
                <% end %>
              </div>
              <div>
                <div class="flex items-center gap-2 mb-1">
                  <span class="text-[10px] uppercase tracking-[0.16em] text-white/65 font-bold">{@hub.name} Hub</span>
                </div>
                <h1 class="font-bold text-[56px] md:text-[68px] tracking-[-0.025em] leading-[0.95]">{@hub.name}</h1>
              </div>
            </div>

            <%!-- Description --%>
            <%= if @hub.description do %>
              <p class="text-white/85 text-[18px] leading-[1.5] max-w-[640px] mb-8">
                {@hub.description}
              </p>
            <% end %>

            <%!-- Stats row --%>
            <div class="flex items-center flex-wrap gap-x-8 gap-y-3 mb-7">
              <div>
                <div class="font-mono font-bold text-[28px] text-white leading-none">{compact_number(@post_count)}</div>
                <div class="text-[10px] uppercase tracking-[0.14em] text-white/55 mt-1.5">Posts</div>
              </div>
              <div class="w-px h-10 bg-white/15"></div>
              <div>
                <div class="font-mono font-bold text-[28px] text-white leading-none">{compact_number(@follower_count)}</div>
                <div class="text-[10px] uppercase tracking-[0.14em] text-white/55 mt-1.5">Followers</div>
              </div>
            </div>

            <%!-- CTAs + social icons --%>
            <div class="flex items-center flex-wrap gap-3">
              <%= if @user_follows_hub do %>
                <button phx-click="toggle_follow" class="inline-flex items-center gap-2 bg-white text-black px-5 py-3 rounded-full text-[14px] font-bold hover:bg-white/90 transition-colors cursor-pointer">
                  <svg class="w-4 h-4" viewBox="0 0 24 24" fill="currentColor"><path fill-rule="evenodd" d="M2.25 12c0-5.385 4.365-9.75 9.75-9.75s9.75 4.365 9.75 9.75-4.365 9.75-9.75 9.75S2.25 17.385 2.25 12Zm13.36-1.814a.75.75 0 1 0-1.22-.872l-3.236 4.53L9.53 12.22a.75.75 0 0 0-1.06 1.06l2.25 2.25a.75.75 0 0 0 1.14-.094l3.75-5.25Z" clip-rule="evenodd" /></svg>
                  Following
                </button>
              <% else %>
                <button phx-click="toggle_follow" class="inline-flex items-center gap-2 bg-[#CAFC00] text-black px-5 py-3 rounded-full text-[14px] font-bold hover:bg-white transition-colors cursor-pointer">
                  <svg class="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 5v14M5 12h14"/></svg>
                  Follow Hub
                </button>
              <% end %>

              <%!-- Social icons --%>
              <div class="flex items-center gap-1 ml-2">
                <%= if @hub.website_url do %>
                  <a href={@hub.website_url} target="_blank" class="w-9 h-9 rounded-full bg-white/10 hover:bg-white/20 backdrop-blur grid place-items-center transition-colors">
                    <svg class="w-4 h-4 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="2" y1="12" x2="22" y2="12"/><path d="M12 2a15.3 15.3 0 014 10 15.3 15.3 0 01-4 10 15.3 15.3 0 01-4-10 15.3 15.3 0 014-10z"/></svg>
                  </a>
                <% end %>
                <%= if @hub.twitter_url do %>
                  <a href={@hub.twitter_url} target="_blank" class="w-9 h-9 rounded-full bg-white/10 hover:bg-white/20 backdrop-blur grid place-items-center transition-colors">
                    <svg class="w-4 h-4 text-white" viewBox="0 0 24 24" fill="currentColor"><path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z"/></svg>
                  </a>
                <% end %>
                <%= if @hub.telegram_url do %>
                  <a href={@hub.telegram_url} target="_blank" class="w-9 h-9 rounded-full bg-white/10 hover:bg-white/20 backdrop-blur grid place-items-center transition-colors">
                    <svg class="w-4 h-4 text-white" viewBox="0 0 24 24" fill="currentColor"><path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.464.141a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z"/></svg>
                  </a>
                <% end %>
                <%= if @hub.discord_url do %>
                  <a href={@hub.discord_url} target="_blank" class="w-9 h-9 rounded-full bg-white/10 hover:bg-white/20 backdrop-blur grid place-items-center transition-colors">
                    <svg class="w-4 h-4 text-white" viewBox="0 0 24 24" fill="currentColor"><path d="M20.317 4.37a19.791 19.791 0 0 0-4.885-1.515.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.25.077.077 0 0 0-.079-.037A19.736 19.736 0 0 0 3.677 4.37a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 0 0 .031.057 19.9 19.9 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028 14.09 14.09 0 0 0 1.226-1.994.076.076 0 0 0-.041-.106 13.107 13.107 0 0 1-1.872-.892.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.892.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.028 19.839 19.839 0 0 0 6.002-3.03.077.077 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 0 0-.031-.03zM8.02 15.33c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.956-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.956 2.418-2.157 2.418zm7.975 0c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.955-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.946 2.418-2.157 2.418z"/></svg>
                  </a>
                <% end %>
                <%= if @hub.instagram_url do %>
                  <a href={@hub.instagram_url} target="_blank" class="w-9 h-9 rounded-full bg-white/10 hover:bg-white/20 backdrop-blur grid place-items-center transition-colors">
                    <svg class="w-4 h-4 text-white" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="2" y="2" width="20" height="20" rx="5" ry="5"/><path d="M16 11.37A4 4 0 1 1 12.63 8 4 4 0 0 1 16 11.37z"/><line x1="17.5" y1="6.5" x2="17.51" y2="6.5"/></svg>
                  </a>
                <% end %>
                <%= if @hub.linkedin_url do %>
                  <a href={@hub.linkedin_url} target="_blank" class="w-9 h-9 rounded-full bg-white/10 hover:bg-white/20 backdrop-blur grid place-items-center transition-colors">
                    <svg class="w-4 h-4 text-white" viewBox="0 0 24 24" fill="currentColor"><path d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433c-1.144 0-2.063-.926-2.063-2.065 0-1.138.92-2.063 2.063-2.063 1.14 0 2.064.925 2.064 2.063 0 1.139-.925 2.065-2.064 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z"/></svg>
                  </a>
                <% end %>
                <%= if @hub.tiktok_url do %>
                  <a href={@hub.tiktok_url} target="_blank" class="w-9 h-9 rounded-full bg-white/10 hover:bg-white/20 backdrop-blur grid place-items-center transition-colors">
                    <svg class="w-4 h-4 text-white" viewBox="0 0 24 24" fill="currentColor"><path d="M12.525.02c1.31-.02 2.61-.01 3.91-.02.08 1.53.63 3.09 1.75 4.17 1.12 1.11 2.7 1.62 4.24 1.79v4.03c-1.44-.05-2.89-.35-4.2-.97-.57-.26-1.1-.59-1.62-.93-.01 2.92.01 5.84-.02 8.75-.08 1.4-.54 2.79-1.35 3.94-1.31 1.92-3.58 3.17-5.91 3.21-1.43.08-2.86-.31-4.08-1.03-2.02-1.19-3.44-3.37-3.65-5.71-.02-.5-.03-1-.01-1.49.18-1.9 1.12-3.72 2.58-4.96 1.66-1.44 3.98-2.13 6.15-1.72.02 1.48-.04 2.96-.04 4.44-.99-.32-2.15-.23-3.02.37-.63.41-1.11 1.04-1.36 1.75-.21.51-.15 1.07-.14 1.61.24 1.64 1.82 3.02 3.5 2.87 1.12-.01 2.19-.66 2.77-1.61.19-.33.4-.67.41-1.06.1-1.79.06-3.57.07-5.36.01-4.03-.01-8.05.02-12.07z"/></svg>
                  </a>
                <% end %>
                <%= if @hub.reddit_url do %>
                  <a href={@hub.reddit_url} target="_blank" class="w-9 h-9 rounded-full bg-white/10 hover:bg-white/20 backdrop-blur grid place-items-center transition-colors">
                    <svg class="w-4 h-4 text-white" viewBox="0 0 24 24" fill="currentColor"><path d="M12 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0zm5.01 4.744c.688 0 1.25.561 1.25 1.249a1.25 1.25 0 0 1-2.498.056l-2.597-.547-.8 3.747c1.824.07 3.48.632 4.674 1.488.308-.309.73-.491 1.207-.491.968 0 1.754.786 1.754 1.754 0 .716-.435 1.333-1.01 1.614a3.111 3.111 0 0 1 .042.52c0 2.694-3.13 4.87-7.004 4.87-3.874 0-7.004-2.176-7.004-4.87 0-.183.015-.366.043-.534A1.748 1.748 0 0 1 4.028 12c0-.968.786-1.754 1.754-1.754.463 0 .898.196 1.207.49 1.207-.883 2.878-1.43 4.744-1.487l.885-4.182a.342.342 0 0 1 .14-.197.35.35 0 0 1 .238-.042l2.906.617a1.214 1.214 0 0 1 1.108-.701zM9.25 12C8.561 12 8 12.562 8 13.25c0 .687.561 1.248 1.25 1.248.687 0 1.248-.561 1.248-1.249 0-.688-.561-1.249-1.249-1.249zm5.5 0c-.687 0-1.248.561-1.248 1.25 0 .687.561 1.248 1.249 1.248.688 0 1.249-.561 1.249-1.249 0-.687-.562-1.249-1.25-1.249zm-5.466 3.99a.327.327 0 0 0-.231.094.33.33 0 0 0 0 .463c.842.842 2.484.913 2.961.913.477 0 2.105-.056 2.961-.913a.361.361 0 0 0 .029-.463.33.33 0 0 0-.464 0c-.547.533-1.684.73-2.512.73-.828 0-1.979-.196-2.512-.73a.326.326 0 0 0-.232-.095z"/></svg>
                  </a>
                <% end %>
                <%= if @hub.youtube_url do %>
                  <a href={@hub.youtube_url} target="_blank" class="w-9 h-9 rounded-full bg-white/10 hover:bg-white/20 backdrop-blur grid place-items-center transition-colors">
                    <svg class="w-4 h-4 text-white" viewBox="0 0 24 24" fill="currentColor"><path d="M23.498 6.186a3.016 3.016 0 0 0-2.122-2.136C19.505 3.545 12 3.545 12 3.545s-7.505 0-9.377.505A3.017 3.017 0 0 0 .502 6.186C0 8.07 0 12 0 12s0 3.93.502 5.814a3.016 3.016 0 0 0 2.122 2.136c1.871.505 9.376.505 9.376.505s7.505 0 9.377-.505a3.015 3.015 0 0 0 2.122-2.136C24 15.93 24 12 24 12s0-3.93-.502-5.814zM9.545 15.568V8.432L15.818 12l-6.273 3.568z"/></svg>
                  </a>
                <% end %>
              </div>
            </div>
          </div>

          <%!-- Right column: live activity widget (placeholder) --%>
          <div class="col-span-12 md:col-span-4 mt-2">
            <div class="bg-white/[0.07] backdrop-blur rounded-2xl p-5 ring-1 ring-white/15 shadow-2xl">
              <div class="flex items-center justify-between mb-4">
                <div class="flex items-center gap-1.5">
                  <span class="w-1.5 h-1.5 rounded-full bg-[#CAFC00] animate-pulse"></span>
                  <span class="text-[9px] font-bold uppercase tracking-[0.14em] text-white/85">Latest Activity</span>
                </div>
                <span class="text-[9px] font-mono text-white/45">live</span>
              </div>
              <div class="space-y-3.5">
                <div class="flex items-center gap-3">
                  <div class="w-7 h-7 rounded-full bg-white/15 grid place-items-center text-[10px] font-bold text-white">+</div>
                  <div class="flex-1 min-w-0">
                    <div class="text-[11px] text-white/85 truncate">New content published</div>
                    <div class="text-[9px] text-white/45 font-mono">recently</div>
                  </div>
                </div>
                <div class="flex items-center gap-3">
                  <div class="w-7 h-7 rounded-full bg-white/15 grid place-items-center text-[10px] font-bold text-white">+{min(@follower_count, 8)}</div>
                  <div class="flex-1 min-w-0">
                    <div class="text-[11px] text-white/85 truncate">New followers this week</div>
                    <div class="text-[9px] text-white/45 font-mono">just now</div>
                  </div>
                </div>
                <div class="flex items-center gap-3">
                  <div class="w-7 h-7 rounded-full bg-[#CAFC00] grid place-items-center text-[10px] font-bold text-black">$</div>
                  <div class="flex-1 min-w-0">
                    <div class="text-[11px] text-white/85 truncate">BUX paid out to readers</div>
                    <div class="text-[9px] text-white/45 font-mono">across readers</div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </section>
    """
  end

  defp compact_number(n) when n >= 1_000_000, do: "#{Float.round(n / 1_000_000, 1)}M"
  defp compact_number(n) when n >= 1_000, do: "#{Float.round(n / 1_000, 1)}k"
  defp compact_number(n), do: "#{n}"
end
