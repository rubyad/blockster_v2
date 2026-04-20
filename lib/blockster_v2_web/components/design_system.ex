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
  Renders the lime announcement banner with a rotated message from
  `AnnouncementBanner.pick/1`. Falls back to static copy when no message
  map is provided.
  """
  attr :class, :string, default: nil
  attr :message, :any, default: nil, doc: "a map from AnnouncementBanner.pick/1"
  attr :rest, :global

  def why_earn_bux_banner(assigns) do
    # Fallback for callers that don't pass a message map yet
    assigns =
      if assigns.message do
        assigns
      else
        assign(assigns, :message, %{
          text: "Why Earn BUX? Redeem BUX to enter sponsored airdrops.",
          short: "BUX = airdrop entries.",
          link: nil, cta: "Coming Soon", badge: true
        })
      end

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
          <span class="hidden sm:inline"><%= @message.text %></span>
          <span class="sm:hidden"><%= @message.short %></span>
          <%= if @message[:badge] do %>
            <span class="inline-flex items-center gap-1 bg-black/10 px-2 py-0.5 rounded-md text-[11px] font-medium whitespace-nowrap">
              <svg class="w-3 h-3" fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z" />
              </svg>
              <%= @message.cta %>
            </span>
          <% else %>
            <%= if @message[:link] do %>
              <a href={@message.link} class="inline-flex items-center gap-1 bg-black/10 hover:bg-black/20 px-2 py-0.5 rounded-md text-[11px] font-medium whitespace-nowrap transition-colors cursor-pointer">
                <%= @message.cta %>
              </a>
            <% else %>
              <%= if @message[:cta] do %>
                <span class="inline-flex items-center gap-1 bg-black/10 px-2 py-0.5 rounded-md text-[11px] font-medium whitespace-nowrap">
                  <%= @message.cta %>
                </span>
              <% end %>
            <% end %>
          <% end %>
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
  attr :show_search_modal, :boolean, default: false
  attr :announcement_banner, :any, default: nil, doc: "message map from AnnouncementBanner.pick/1"
  attr :show_why_earn_bux, :boolean, default: true, doc: "deprecated — use announcement_banner"
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
      <div class="max-w-[1280px] mx-auto px-3 md:px-6 h-14 flex items-center justify-between gap-2 md:gap-4">
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

        <%!-- Center: nav --%>
        <div class="flex items-center gap-4 flex-1 justify-center">
          <nav class="hidden md:flex items-center gap-7 text-[13px] text-neutral-700">
            <.header_nav_link href={~p"/"} active={@active == "home"}>Home</.header_nav_link>
            <.header_nav_link href={~p"/hubs"} active={@active == "hubs"}>Hubs</.header_nav_link>
            <.header_nav_link href={~p"/shop"} active={@active == "shop"}>Shop</.header_nav_link>
            <.header_nav_link href={~p"/play"} active={@active == "play"}>Play</.header_nav_link>
            <.header_nav_link href={~p"/pool"} active={@active == "pool"}>Pool</.header_nav_link>
          </nav>
        </div>

        <%!-- Right --%>
        <div class="flex items-center gap-1.5 md:gap-2 shrink-0">
          <%!-- Search icon (opens modal) — hidden on mobile to prioritize BUX balance pill --%>
          <button
            type="button"
            phx-click="open_search_modal"
            aria-label="Search"
            class="relative w-9 h-9 hidden md:flex items-center justify-center rounded-full bg-neutral-100 hover:bg-neutral-200 transition-colors cursor-pointer"
          >
            <svg class="w-4 h-4 text-[#141414]" viewBox="0 0 24 24" fill="currentColor">
              <path fill-rule="evenodd" d="M10.5 3.75a6.75 6.75 0 1 0 0 13.5 6.75 6.75 0 0 0 0-13.5ZM2.25 10.5a8.25 8.25 0 1 1 14.59 5.28l4.69 4.69a.75.75 0 1 1-1.06 1.06l-4.69-4.69A8.25 8.25 0 0 1 2.25 10.5Z" clip-rule="evenodd" />
            </svg>
          </button>
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
              <button id="ds-user-button" phx-click={JS.toggle(to: "#ds-header-user-menu")} class="flex items-center gap-2 h-9 md:h-10 rounded-full bg-neutral-100 pl-1.5 pr-2 md:pl-2 md:pr-3 hover:bg-neutral-200 transition-colors cursor-pointer">
                <img src={@display_token_icon} alt={@display_token} class="w-6 h-6 rounded-full object-cover" />
                <span class="text-[13px] font-bold text-[#141414] font-mono tabular-nums">{@formatted_display_balance}</span>
                <span class="hidden md:inline text-[11px] text-neutral-500">{@display_token}</span>
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
              class={"inline-flex items-center gap-1.5 md:gap-2 px-3 py-2 md:px-4 rounded-full text-[11px] md:text-[12px] font-bold transition-colors cursor-pointer disabled:cursor-not-allowed whitespace-nowrap #{if @connecting, do: "bg-gray-200 text-gray-400", else: "bg-[#0a0a0a] text-white hover:bg-[#1a1a22]"}"}
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

      <.why_earn_bux_banner :if={@announcement_banner || @show_why_earn_bux} message={@announcement_banner} />
    </header>

    <%!-- Search modal --%>
    <%= if @show_search_modal do %>
      <div
        class="fixed inset-0 z-[60] flex items-start justify-center pt-20 px-4 bg-black/40 backdrop-blur-sm"
        phx-window-keydown="close_search_modal"
        phx-key="escape"
      >
        <div class="w-full max-w-2xl bg-white rounded-2xl shadow-2xl border border-neutral-200 overflow-hidden" phx-click-away="close_search_modal">
          <div class="flex items-center gap-3 px-5 py-4 border-b border-neutral-100">
            <svg class="w-4 h-4 text-neutral-400 shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
              <circle cx="11" cy="11" r="7"></circle>
              <path d="m21 21-4.3-4.3"></path>
            </svg>
            <input
              type="text"
              placeholder="Search articles..."
              value={@search_query}
              phx-keyup="search_posts"
              phx-debounce="300"
              phx-mounted={JS.focus()}
              class="flex-1 bg-transparent text-base outline-none border-0 focus:ring-0 text-[#141414]"
              id="ds-search-modal-input"
            />
            <button type="button" phx-click="close_search_modal" aria-label="Close"
              class="w-8 h-8 flex items-center justify-center text-neutral-500 rounded-full bg-neutral-100 hover:bg-neutral-200 cursor-pointer">
              <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <line x1="18" y1="6" x2="6" y2="18"></line>
                <line x1="6" y1="6" x2="18" y2="18"></line>
              </svg>
            </button>
          </div>
          <%= cond do %>
            <% @show_search_results and length(@search_results) > 0 -> %>
              <div class="max-h-[60vh] overflow-y-auto py-2">
                <%= for post <- @search_results do %>
                  <.link navigate={~p"/#{post.slug}"}
                    class="flex items-start gap-3 px-5 py-3 hover:bg-neutral-50 transition-colors cursor-pointer">
                    <div class="rounded-lg overflow-hidden shrink-0 w-14 h-14">
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
            <% String.length(@search_query) >= 2 -> %>
              <div class="px-5 py-10 text-center text-sm text-neutral-500">
                No results for "{@search_query}"
              </div>
            <% true -> %>
              <div class="px-5 py-10 text-center text-sm text-neutral-400">
                Type to search articles
              </div>
          <% end %>
        </div>
      </div>
    <% end %>
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
  # ── <.mobile_bottom_nav /> ─────────────────────────────────────────────────
  #
  # Bottom tab bar for mobile. Rendered in the redesign layout so every
  # redesigned page (home, hub, article, shop, etc.) gets consistent nav on
  # small screens. Hidden on md+ screens.

  @doc """
  Renders the fixed bottom navigation bar for mobile. The `DsMobileNavHighlight`
  JS hook (see assets/js/app.js) toggles `data-active` on each tab based on the
  current path — no server assign required.
  """

  def mobile_bottom_nav(assigns) do
    ~H"""
    <nav
      id="ds-mobile-bottom-nav"
      phx-hook="DsMobileNavHighlight"
      phx-update="ignore"
      class="fixed bottom-0 inset-x-0 z-40 md:hidden bg-white/95 backdrop-blur border-t border-neutral-200/80 pb-[env(safe-area-inset-bottom)]"
    >
      <ul class="flex items-stretch justify-between px-2">
        <.mobile_nav_tab href={~p"/"} nav_path="/" label="News">
          <svg viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5"><path fill-rule="evenodd" d="M4.125 3C3.089 3 2.25 3.84 2.25 4.875V18a3 3 0 0 0 3 3h15a3 3 0 0 1-3-3V4.875C17.25 3.839 16.41 3 15.375 3H4.125ZM12 9.75a.75.75 0 0 0 0 1.5h1.5a.75.75 0 0 0 0-1.5H12Zm-.75-2.25a.75.75 0 0 1 .75-.75h1.5a.75.75 0 0 1 0 1.5H12a.75.75 0 0 1-.75-.75ZM6 12.75a.75.75 0 0 0 0 1.5h7.5a.75.75 0 0 0 0-1.5H6Zm-.75 3.75a.75.75 0 0 1 .75-.75h7.5a.75.75 0 0 1 0 1.5H6a.75.75 0 0 1-.75-.75ZM6 6.75a.75.75 0 0 0-.75.75v3c0 .414.336.75.75.75h3a.75.75 0 0 0 .75-.75v-3A.75.75 0 0 0 9 6.75H6Z" clip-rule="evenodd"/><path d="M18.75 6.75h1.875c.621 0 1.125.504 1.125 1.125V18a1.5 1.5 0 0 1-3 0V6.75Z"/></svg>
        </.mobile_nav_tab>
        <.mobile_nav_tab href={~p"/hubs"} nav_path="/hubs" label="Hubs">
          <svg viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5"><path fill-rule="evenodd" d="M8.25 6.75a3.75 3.75 0 1 1 7.5 0 3.75 3.75 0 0 1-7.5 0ZM15.75 9.75a3 3 0 1 1 6 0 3 3 0 0 1-6 0ZM2.25 9.75a3 3 0 1 1 6 0 3 3 0 0 1-6 0ZM6.31 15.117A6.745 6.745 0 0 1 12 12a6.745 6.745 0 0 1 6.709 7.498.75.75 0 0 1-.372.568A12.696 12.696 0 0 1 12 21.75c-2.305 0-4.47-.612-6.337-1.684a.75.75 0 0 1-.372-.568 6.787 6.787 0 0 1 1.019-4.38Z" clip-rule="evenodd"/></svg>
        </.mobile_nav_tab>
        <.mobile_nav_tab href={~p"/shop"} nav_path="/shop" label="Shop">
          <svg viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5"><path fill-rule="evenodd" d="M7.5 6v.75H5.513c-.96 0-1.764.724-1.865 1.679l-1.263 12A1.875 1.875 0 0 0 4.25 22.5h15.5a1.875 1.875 0 0 0 1.865-2.071l-1.263-12a1.875 1.875 0 0 0-1.865-1.679H16.5V6a4.5 4.5 0 1 0-9 0ZM12 3a3 3 0 0 0-3 3v.75h6V6a3 3 0 0 0-3-3Zm-3 8.25a3 3 0 1 0 6 0v-.75a.75.75 0 0 1 1.5 0v.75a4.5 4.5 0 1 1-9 0v-.75a.75.75 0 0 1 1.5 0v.75Z" clip-rule="evenodd"/></svg>
        </.mobile_nav_tab>
        <.mobile_nav_tab href={~p"/pool"} nav_path="/pool" label="Pool">
          <svg viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5"><path d="M21 6.375c0 2.692-4.03 4.875-9 4.875S3 9.067 3 6.375 7.03 1.5 12 1.5s9 2.183 9 4.875Z"/><path d="M12 12.75c2.685 0 5.19-.586 7.078-1.609a8.283 8.283 0 0 0 1.897-1.384c.016.111.025.223.025.334 0 2.692-4.03 4.875-9 4.875s-9-2.183-9-4.875c0-.11.008-.223.025-.334a8.301 8.301 0 0 0 1.897 1.384C6.809 12.164 9.315 12.75 12 12.75Z"/><path d="M12 16.5c2.685 0 5.19-.586 7.078-1.609a8.282 8.282 0 0 0 1.897-1.384c.016.111.025.223.025.334 0 2.692-4.03 4.875-9 4.875s-9-2.183-9-4.875c0-.11.008-.223.025-.334a8.3 8.3 0 0 0 1.897 1.384C6.809 15.914 9.315 16.5 12 16.5Z"/></svg>
        </.mobile_nav_tab>
        <.mobile_nav_tab href={~p"/play"} nav_path="/play" label="Play">
          <svg viewBox="0 0 24 24" fill="currentColor" class="w-5 h-5"><path fill-rule="evenodd" d="M9.315 7.584C12.195 3.883 16.695 1.5 21.75 1.5a.75.75 0 0 1 .75.75c0 5.056-2.383 9.555-6.084 12.436A6.75 6.75 0 0 1 9.75 22.5a.75.75 0 0 1-.75-.75v-4.131A15.838 15.838 0 0 1 6.382 15H2.25a.75.75 0 0 1-.75-.75 6.75 6.75 0 0 1 7.815-6.666ZM15 6.75a2.25 2.25 0 1 0 0 4.5 2.25 2.25 0 0 0 0-4.5Z" clip-rule="evenodd"/></svg>
        </.mobile_nav_tab>
      </ul>
    </nav>
    """
  end

  attr :href, :string, required: true
  attr :nav_path, :string, required: true
  attr :label, :string, required: true
  slot :inner_block, required: true

  defp mobile_nav_tab(assigns) do
    ~H"""
    <li class="flex-1">
      <.link
        navigate={@href}
        data-nav-path={@nav_path}
        class="flex flex-col items-center justify-center gap-1 py-2.5 text-neutral-400 data-[active]:text-[#141414] transition-colors"
      >
        {render_slot(@inner_block)}
        <span class="text-[10px] font-bold tracking-[0.04em]">
          {@label}
        </span>
      </.link>
    </li>
    """
  end

  # ── <.footer /> ────────────────────────────────────────────────────────────
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
        <div class="grid grid-cols-12 gap-4 md:gap-8">
          <%!-- Brand block --%>
          <div class="col-span-12 md:col-span-5">
            <div class="flex items-center mb-5">
              <.logo size="22px" variant="dark" />
            </div>
            <h3 class="font-bold text-[28px] leading-[1.1] text-white max-w-[360px] tracking-tight mb-4">
              All in on Solana.
            </h3>
            <p class="text-white/55 text-[13px] leading-relaxed max-w-[360px]">
              The home feed of the Solana ecosystem. Builders, protocols, culture — daily.
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
              <li><.link navigate={~p"/"} class="text-white/70 hover:text-white transition-colors">Latest</.link></li>
              <li><.link navigate={~p"/hubs"} class="text-white/70 hover:text-white transition-colors">Hubs</.link></li>
              <li><.link navigate={~p"/how-it-works"} class="text-white/70 hover:text-white transition-colors">How it works</.link></li>
            </ul>
          </div>

          <%!-- Earn column --%>
          <div class="col-span-6 md:col-span-2">
            <div class="text-[10px] uppercase tracking-[0.14em] text-white/40 font-bold mb-4">Earn</div>
            <ul class="space-y-2.5 text-[13px]">
              <li><.link navigate={~p"/pool/bux"} class="text-white/70 hover:text-white transition-colors">BUX Token</.link></li>
              <li><.link navigate={~p"/pool"} class="text-white/70 hover:text-white transition-colors">Pool</.link></li>
              <li><.link navigate={~p"/play"} class="text-white/70 hover:text-white transition-colors">Play</.link></li>
              <li><.link navigate={~p"/shop"} class="text-white/70 hover:text-white transition-colors">Shop</.link></li>
              <li><.link navigate={~p"/airdrop"} class="text-white/70 hover:text-white transition-colors">Airdrop</.link></li>
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
            <a href="/media-kit" class="hover:text-[#CAFC00] transition-colors">Media kit</a>
            <a href="/privacy" class="hover:text-white transition-colors">Privacy</a>
            <a href="/terms" class="hover:text-white transition-colors">Terms</a>
            <a href="/cookies" class="hover:text-white transition-colors">Cookie Policy</a>
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
      <div class="grid grid-cols-12 gap-4 md:gap-8 items-end">
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

  defp format_reward(n) when is_integer(n) and n >= 0, do: "#{n}"
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
    <section class="ds-hero-feature pt-10 pb-4">
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
        <div class="grid grid-cols-12 gap-4 md:gap-8 items-center">
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
                    {format_reward(@bux_reward)}
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
  attr :article_count, :string, required: true
  attr :bux_paid, :string, required: true
  attr :hub_count, :any, required: true
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
    <section class="ds-welcome-hero pt-6 pb-4 md:pt-12 md:pb-6 md:mt-8">
      <div class="grid grid-cols-12 gap-6 md:gap-8 items-center bg-gradient-to-br from-[#0a0a0a] via-[#1a1a22] to-[#0a0a0a] rounded-3xl overflow-hidden p-6 md:p-12 ring-1 ring-white/10 relative">
        <div class="absolute top-0 right-0 w-[60%] h-full bg-gradient-to-l from-[#CAFC00]/[0.06] to-transparent pointer-events-none"></div>
        <div class="absolute bottom-0 left-0 w-[40%] h-[60%] bg-gradient-to-tr from-[#7D00FF]/15 to-transparent blur-3xl pointer-events-none"></div>
        <div class="col-span-12 md:col-span-7 relative">
          <div class="font-bold uppercase text-[10px] tracking-[0.16em] mb-4 text-[#CAFC00]">
            Welcome to Blockster
          </div>
          <h2 class="font-bold tracking-[-0.022em] leading-[1.04] text-white text-[32px] md:text-[58px] mb-5 max-w-[640px]">
            All in on Solana. <span class="text-white/45">The center of the ecosystem.</span>
          </h2>
          <p class="text-white/65 text-[15px] md:text-[16px] leading-[1.55] max-w-[520px] mb-6 md:mb-7">
            Blockster is a Solana publication. Solana is the most active chain in crypto — we cover the builders, the protocols, the drops, and everything moving on-chain. Read the stories. Follow the ecosystem. Earn BUX for every article you engage with.
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
              href="/hubs"
              class="inline-flex items-center gap-2 text-white/70 hover:text-white transition-colors text-[13px]"
            >
              Or browse without an account
            </a>
          </div>
          <div class="mt-6 md:mt-7 flex flex-wrap items-center gap-x-4 gap-y-2 md:gap-6 text-white/40 text-[11px] font-mono">
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
                  <% author = if @preview_author in [nil, "", "Anonymous", "Unknown"], do: nil, else: @preview_author %>
                  {author}{if author && @preview_read_minutes, do: " · ", else: ""}{if @preview_read_minutes, do: "#{@preview_read_minutes} min", else: ""}
                </span>
                <% reward = parse_reward(@preview_bux_reward) %>
                <%= if reward > 0 do %>
                  <div class="flex items-center gap-1 bg-[#CAFC00] text-black px-2 py-0.5 rounded-full font-bold">
                    <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="" class="w-2.5 h-2.5 rounded-full" />
                    {reward} BUX
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
            Curate your own feed by following the hubs you care about. Solana, Moonpay and more.
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
    assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))
    ~H"""
    <a href={@banner.link_url || "#"} target="_blank" rel="noopener" class={["not-prose block my-9 group", @class]} phx-click="track_ad_click" phx-value-id={@banner.id}>
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

  # Requests a crisp retina-ready render from ImageKit for ad hero images.
  # The raw stored URL can resolve to a 270-px source file — way too small for
  # 2-3× DPR displays. w-1200 asks ImageKit to deliver up to 1200px wide,
  # which is plenty for every inline/banner ad placement.
  defp ad_image_url(url), do: BlocksterV2.ImageKit.url(url, width: 1200, quality: 95)

  # Strips empty-string values to nil so `@p["key"] || "default"` falls through correctly.
  # Without this, the admin form submits "" for unfilled fields and "" is truthy in Elixir.
  defp sanitize_ad_params(params) do
    (params || %{})
    |> Enum.map(fn {k, ""} -> {k, nil}; kv -> kv end)
    |> Map.new()
  end

  # Maps the admin-selectable image_fit param to a Tailwind object-fit class.
  # Default "cover" matches the original portrait-template behaviour.
  defp portrait_image_fit_class("contain"), do: "object-contain"
  defp portrait_image_fit_class("scale-down"), do: "object-scale-down"
  defp portrait_image_fit_class(_), do: "object-cover"

  # Converts a USD price string/number on a luxury_watch banner into a live SOL
  # amount by reading the current SOL price from PriceTracker's Mnesia cache
  # (refreshed every minute). Returns "—" if SOL price isn't cached yet.
  defp luxury_watch_price_sol(price_usd) do
    with usd when is_number(usd) <- parse_number(price_usd),
         {:ok, %{usd_price: sol_usd}} when is_number(sol_usd) and sol_usd > 0 <-
           BlocksterV2.PriceTracker.get_price("SOL") do
      sol = usd / sol_usd

      cond do
        sol >= 1000 -> format_with_commas(trunc(sol))
        sol >= 100 -> :io_lib.format("~.1f", [sol]) |> IO.iodata_to_binary()
        true -> :io_lib.format("~.2f", [sol]) |> IO.iodata_to_binary()
      end
    else
      _ -> "—"
    end
  end

  # Formats a USD price with thousand-separators, no currency symbol.
  defp luxury_watch_format_usd(price_usd) do
    case parse_number(price_usd) do
      n when is_number(n) -> format_with_commas(trunc(n))
      _ -> "—"
    end
  end

  defp parse_number(n) when is_number(n), do: n

  defp parse_number(s) when is_binary(s) do
    case Float.parse(s) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_number(_), do: nil

  defp format_with_commas(n) when is_integer(n) do
    n
    |> Integer.to_string()
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  defp format_with_commas(_), do: "—"

  def ad_banner(%{banner: %{template: "dark_gradient"}} = assigns) do
    assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))
    ~H"""
    <div class={["my-10 -mx-2 not-prose", @class]}>
      <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold pl-2">Sponsored</div>
      <a href={@banner.link_url || "#"} target="_blank" rel="noopener" class="block group" phx-click="track_ad_click" phx-value-id={@banner.id}>
        <div class="relative rounded-2xl overflow-hidden p-6 shadow-[0_20px_40px_-15px_rgba(0,0,0,0.25)] ring-1 ring-white/[0.06]" style={"background: linear-gradient(135deg, #{@p["bg_color"] || "#0A0A0F"}, #{@p["bg_color_end"] || "#1c1c25"})"}>
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
    assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))
    ~H"""
    <div class={["not-prose my-12 flex justify-center", @class]}>
      <div class="text-center">
        <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold">Sponsored</div>
        <a href={@banner.link_url || "#"} target="_blank" rel="noopener" class="block group max-w-[440px] mx-auto" phx-click="track_ad_click" phx-value-id={@banner.id}>
          <div class="rounded-2xl overflow-hidden ring-1 ring-black/5 shadow-[0_30px_60px_-15px_rgba(0,0,0,0.18)] relative" style={"background: #{@p["bg_color"] || "#0a1838"}"}>
            <%= if @p["image_url"] do %>
              <div
                class="aspect-[4/3] relative overflow-hidden"
                style={"background: #{@p["image_bg_color"] || @p["bg_color"] || "#0a1838"};"}
              >
                <img
                  src={ad_image_url(@p["image_url"])}
                  alt=""
                  class={[
                    "w-full h-full",
                    portrait_image_fit_class(@p["image_fit"])
                  ]}
                />
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
    assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))
    ~H"""
    <div class={["mt-6", @class]}>
      <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold px-1">Sponsored</div>
      <a href={@banner.link_url || "#"} target="_blank" rel="noopener" class="block group" phx-click="track_ad_click" phx-value-id={@banner.id}>
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

  # Luxury watch template — editorial layout for high-end timepiece dealers.
  # Brand wordmark at the top, large centered watch image, model line with
  # reference number, tagline, CTA, and an optional 4-column spec row at the
  # bottom (CASE · DIAL · BAND · YEAR). Uses serif display typography and a
  # single accent color (intended for champagne-gold or warm metallics).
  def ad_banner(%{banner: %{template: "luxury_watch"}} = assigns) do
    assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))

    ~H"""
    <div class={["not-prose my-12 flex justify-center", @class]}>
      <div class="w-full max-w-[560px]">
        <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold text-center">Sponsored</div>
        <a
          href={@banner.link_url || "#"}
          target="_blank"
          rel="noopener"
          class="block group"
          phx-click="track_ad_click"
          phx-value-id={@banner.id}
        >
          <div
            class="rounded-2xl overflow-hidden ring-1 ring-black/5 shadow-[0_30px_60px_-15px_rgba(0,0,0,0.25)] relative"
            style={"background: linear-gradient(180deg, #{@p["bg_color"] || "#0a0a0a"}, #{@p["bg_color_end"] || "#1a1a1a"}); color: #{@p["text_color"] || "#E8E4DD"};"}
          >
            <%!-- Brand wordmark strip --%>
            <%= if @p["brand_name"] do %>
              <div class="pt-7 pb-4 flex items-center justify-center gap-3">
                <div class="h-px w-10 opacity-30" style={"background: #{@p["accent_color"] || "#D4AF37"}"}></div>
                <div class="text-[11px] font-semibold uppercase" style={"letter-spacing: 0.28em; color: #{@p["accent_color"] || "#D4AF37"};"}>
                  {@p["brand_name"]}
                </div>
                <div class="h-px w-10 opacity-30" style={"background: #{@p["accent_color"] || "#D4AF37"}"}></div>
              </div>
            <% end %>

            <%!-- Watch image — full width, image-driven height (no crop, no bars) --%>
            <%= if @p["image_url"] do %>
              <div
                class="relative"
                style={"background: #{@p["image_bg_color"] || @p["bg_color"] || "#0a0a0a"};"}
              >
                <img
                  src={ad_image_url(@p["image_url"])}
                  alt={@p["model_name"] || ""}
                  class="w-full h-auto block"
                />
                <%!-- Small "Ad" badge, bottom-right of image --%>
                <div class="absolute bottom-3 right-3 px-1.5 py-0.5 bg-white/85 rounded text-[9px] font-bold uppercase tracking-wider text-neutral-700">Ad</div>
              </div>
            <% end %>

            <%!-- Divider --%>
            <div class="flex justify-center pt-8">
              <div class="h-px w-16" style={"background: #{@p["accent_color"] || "#D4AF37"}; opacity: 0.5;"}></div>
            </div>

            <%!-- Model + reference --%>
            <div class="px-8 pt-5 text-center">
              <%= if @p["model_name"] do %>
                <h3
                  class="text-[22px] font-bold tracking-tight uppercase leading-[1.1]"
                  style={"font-family: 'Inter', 'Helvetica Neue', serif; letter-spacing: 0.12em; color: #{@p["text_color"] || "#E8E4DD"};"}
                >
                  {@p["model_name"]}
                </h3>
              <% end %>
              <%= if @p["reference"] do %>
                <div class="text-[11px] mt-2 italic opacity-75" style="font-family: Georgia, 'Times New Roman', serif;">
                  {@p["reference"]}
                </div>
              <% end %>
            </div>

            <%!-- Price in SOL (live, from PriceTracker) with USD below, OR
                 editorial tagline fallback when no price is set on the banner. --%>
            <%= cond do %>
              <% @p["price_usd"] -> %>
                <div class="px-8 pt-6 text-center">
                  <div class="inline-flex items-center justify-center gap-2 leading-none">
                    <img
                      src="https://ik.imagekit.io/blockster/solana-sol-logo.png"
                      alt="SOL"
                      width="28"
                      height="28"
                      class="rounded-full"
                      style="box-shadow: 0 0 0 1px rgba(153, 69, 255, 0.35);"
                    />
                    <span
                      class="text-[32px] font-semibold"
                      style={"font-family: 'JetBrains Mono', ui-monospace, monospace; font-variant-numeric: tabular-nums; color: #{@p["text_color"] || "#E8E4DD"}; letter-spacing: -0.01em;"}
                    >
                      {luxury_watch_price_sol(@p["price_usd"])}
                    </span>
                    <span
                      class="text-[18px] font-medium uppercase tracking-[0.2em] opacity-70"
                      style={"color: #{@p["text_color"] || "#E8E4DD"};"}
                    >
                      SOL
                    </span>
                  </div>
                  <div
                    class="text-[11px] mt-1.5 opacity-55"
                    style="font-family: 'JetBrains Mono', ui-monospace, monospace; font-variant-numeric: tabular-nums;"
                  >
                    ≈ ${luxury_watch_format_usd(@p["price_usd"])} USD
                  </div>
                </div>
              <% @p["tagline"] -> %>
                <div class="px-8 pt-6 text-center">
                  <p
                    class="text-[20px] leading-[1.3] font-light"
                    style={"font-family: Georgia, 'Times New Roman', serif; letter-spacing: -0.005em; color: #{@p["text_color"] || "#E8E4DD"};"}
                  >
                    "{@p["tagline"]}"
                  </p>
                </div>
              <% true -> %>
            <% end %>

            <%!-- Bottom breathing room --%>
            <div class="pb-8"></div>
          </div>
        </a>
      </div>
    </div>
    """
  end

  # Luxury watch compact full — formerly the more relaxed sibling of the
  # now-removed `luxury_watch_compact` template (the cropped 280px height
  # variant). This one keeps the entire watch visible — image-driven height,
  # image area auto-sizes to the photo so the entire watch is visible (no
  # crop). Use when you'd rather have a taller card than crop the bracelet.
  def ad_banner(%{banner: %{template: "luxury_watch_compact_full"}} = assigns) do
    assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))

    ~H"""
    <div class={["not-prose my-10 flex justify-center", @class]}>
      <div class="w-full max-w-[560px]">
        <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold text-center">Sponsored</div>
        <a
          href={@banner.link_url || "#"}
          target="_blank"
          rel="noopener"
          class="block group"
          phx-click="track_ad_click"
          phx-value-id={@banner.id}
        >
          <div
            class="rounded-2xl overflow-hidden ring-1 ring-black/5 shadow-[0_30px_60px_-15px_rgba(0,0,0,0.25)] relative"
            style={"background: linear-gradient(180deg, #{@p["bg_color"] || "#0a0a0a"}, #{@p["bg_color_end"] || "#1a1a1a"}); color: #{@p["text_color"] || "#E8E4DD"};"}
          >
            <%= if @p["brand_name"] do %>
              <div class="pt-5 pb-3 flex items-center justify-center gap-3">
                <div class="h-px w-8 opacity-30" style={"background: #{@p["accent_color"] || "#D4AF37"}"}></div>
                <div class="text-[10px] font-semibold uppercase" style={"letter-spacing: 0.28em; color: #{@p["accent_color"] || "#D4AF37"};"}>
                  {@p["brand_name"]}
                </div>
                <div class="h-px w-8 opacity-30" style={"background: #{@p["accent_color"] || "#D4AF37"}"}></div>
              </div>
            <% end %>

            <%!-- Image fills full width at its natural aspect — no crop --%>
            <%= if @p["image_url"] do %>
              <div
                class="relative"
                style={"background: #{@p["image_bg_color"] || @p["bg_color"] || "#0a0a0a"};"}
              >
                <img
                  src={ad_image_url(@p["image_url"])}
                  alt={@p["model_name"] || ""}
                  class="w-full h-auto block"
                />
                <div class="absolute bottom-2 right-2 px-1.5 py-0.5 bg-white/85 rounded text-[9px] font-bold uppercase tracking-wider text-neutral-700">Ad</div>
              </div>
            <% end %>

            <div class="flex justify-center pt-5">
              <div class="h-px w-12" style={"background: #{@p["accent_color"] || "#D4AF37"}; opacity: 0.5;"}></div>
            </div>

            <div class="px-6 pt-4 pb-6 text-center">
              <%= if @p["model_name"] do %>
                <h3
                  class="text-[18px] font-bold uppercase leading-[1.1]"
                  style={"font-family: 'Inter', 'Helvetica Neue', serif; letter-spacing: 0.12em; color: #{@p["text_color"] || "#E8E4DD"};"}
                >
                  {@p["model_name"]}
                </h3>
              <% end %>
              <%= if @p["reference"] do %>
                <div class="text-[10px] mt-1.5 italic opacity-75" style="font-family: Georgia, serif;">
                  {@p["reference"]}
                </div>
              <% end %>
              <%= if @p["price_usd"] do %>
                <div class="mt-3 inline-flex items-center justify-center gap-1.5 leading-none">
                  <img src="https://ik.imagekit.io/blockster/solana-sol-logo.png" alt="SOL" width="22" height="22" class="rounded-full" />
                  <span
                    class="text-[22px] font-semibold"
                    style={"font-family: 'JetBrains Mono', ui-monospace, monospace; font-variant-numeric: tabular-nums; color: #{@p["text_color"] || "#E8E4DD"};"}
                  >
                    {luxury_watch_price_sol(@p["price_usd"])}
                  </span>
                  <span class="text-[13px] font-medium uppercase tracking-[0.2em] opacity-70">SOL</span>
                </div>
                <div class="text-[10px] mt-1 opacity-55" style="font-family: 'JetBrains Mono', ui-monospace, monospace;">
                  ≈ ${luxury_watch_format_usd(@p["price_usd"])} USD
                </div>
              <% end %>
            </div>
          </div>
        </a>
      </div>
    </div>
    """
  end

  # Luxury watch skyscraper — 200px-wide tall sidebar variant. Brand at top,
  # square image, compact model/price, fits alongside `rt_sidebar_tile` /
  # `fs_skyscraper` in article sidebars.
  def ad_banner(%{banner: %{template: "luxury_watch_skyscraper"}} = assigns) do
    assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))

    ~H"""
    <a
      href={@banner.link_url || "#"}
      target="_blank"
      rel="noopener"
      class={["block group w-[200px]", @class]}
      phx-click="track_ad_click"
      phx-value-id={@banner.id}
    >
      <div
        class="rounded-xl overflow-hidden ring-1 ring-black/5 shadow-[0_12px_24px_-10px_rgba(0,0,0,0.25)] relative"
        style={"background: linear-gradient(180deg, #{@p["bg_color"] || "#0a0a0a"}, #{@p["bg_color_end"] || "#1a1a1a"}); color: #{@p["text_color"] || "#E8E4DD"};"}
      >
        <%= if @p["brand_name"] do %>
          <div class="pt-3 pb-2 flex items-center justify-center gap-2">
            <div class="h-px w-3 opacity-30" style={"background: #{@p["accent_color"] || "#D4AF37"}"}></div>
            <div class="text-[8px] font-semibold uppercase" style={"letter-spacing: 0.22em; color: #{@p["accent_color"] || "#D4AF37"};"}>
              {@p["brand_name"]}
            </div>
            <div class="h-px w-3 opacity-30" style={"background: #{@p["accent_color"] || "#D4AF37"}"}></div>
          </div>
        <% end %>

        <%= if @p["image_url"] do %>
          <div
            class="relative"
            style={"background: #{@p["image_bg_color"] || @p["bg_color"] || "#0a0a0a"};"}
          >
            <img
              src={ad_image_url(@p["image_url"])}
              alt={@p["model_name"] || ""}
              class="w-full h-auto block"
            />
            <div class="absolute bottom-1.5 right-1.5 px-1 py-px bg-white/85 rounded text-[7px] font-bold uppercase tracking-wider text-neutral-700">Ad</div>
          </div>
        <% end %>

        <div class="flex justify-center pt-3">
          <div class="h-px w-8" style={"background: #{@p["accent_color"] || "#D4AF37"}; opacity: 0.5;"}></div>
        </div>

        <div class="px-3 pt-2 pb-4 text-center">
          <%= if @p["model_name"] do %>
            <h3
              class="text-[11px] font-bold uppercase leading-[1.15]"
              style={"font-family: 'Inter', serif; letter-spacing: 0.1em; color: #{@p["text_color"] || "#E8E4DD"};"}
            >
              {@p["model_name"]}
            </h3>
          <% end %>
          <%= if @p["reference"] do %>
            <div class="text-[8.5px] mt-1 italic opacity-70 leading-snug" style="font-family: Georgia, serif;">
              {@p["reference"]}
            </div>
          <% end %>
          <%= if @p["price_usd"] do %>
            <div class="mt-2 inline-flex items-center justify-center gap-1 leading-none">
              <img src="https://ik.imagekit.io/blockster/solana-sol-logo.png" alt="SOL" width="14" height="14" class="rounded-full" />
              <span
                class="text-[14px] font-semibold"
                style={"font-family: 'JetBrains Mono', ui-monospace, monospace; font-variant-numeric: tabular-nums; color: #{@p["text_color"] || "#E8E4DD"};"}
              >
                {luxury_watch_price_sol(@p["price_usd"])}
              </span>
              <span class="text-[8px] font-medium uppercase tracking-[0.18em] opacity-70">SOL</span>
            </div>
            <div class="text-[8.5px] mt-0.5 opacity-55" style="font-family: 'JetBrains Mono', ui-monospace, monospace;">
              ≈ ${luxury_watch_format_usd(@p["price_usd"])}
            </div>
          <% end %>
        </div>
      </div>
    </a>
    """
  end

  # Luxury watch banner — full-width horizontal leaderboard. Image on the
  # left (square), brand + model + price on the right. Stacks vertically on
  # mobile (image on top, info below).
  def ad_banner(%{banner: %{template: "luxury_watch_banner"}} = assigns) do
    assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))

    ~H"""
    <div class={["not-prose my-6", @class]}>
      <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold text-center">Sponsored</div>
      <a
        href={@banner.link_url || "#"}
        target="_blank"
        rel="noopener"
        class="block group"
        phx-click="track_ad_click"
        phx-value-id={@banner.id}
      >
        <div
          class="rounded-2xl overflow-hidden ring-1 ring-black/5 shadow-[0_20px_40px_-12px_rgba(0,0,0,0.25)] relative"
          style={"background: linear-gradient(90deg, #{@p["bg_color"] || "#0a0a0a"}, #{@p["bg_color_end"] || "#1a1a1a"}); color: #{@p["text_color"] || "#E8E4DD"};"}
        >
          <div class="flex flex-col md:flex-row items-stretch">
            <%!-- Image: 180px tall on mobile, 160px square on desktop --%>
            <%= if @p["image_url"] do %>
              <div
                class="relative shrink-0 w-full md:w-[180px] h-[180px] md:h-[160px]"
                style={"background: #{@p["image_bg_color"] || @p["bg_color"] || "#0a0a0a"};"}
              >
                <img
                  src={ad_image_url(@p["image_url"])}
                  alt={@p["model_name"] || ""}
                  class="w-full h-full object-cover"
                  style="object-position: center 30%;"
                />
                <div class="absolute bottom-2 right-2 px-1.5 py-0.5 bg-white/85 rounded text-[9px] font-bold uppercase tracking-wider text-neutral-700">Ad</div>
              </div>
            <% end %>

            <%!-- Right side: brand, model, price, subtle divider --%>
            <div class="flex-1 px-6 py-5 flex flex-col justify-center md:items-start items-center text-center md:text-left gap-2">
              <%= if @p["brand_name"] do %>
                <div class="inline-flex items-center gap-2">
                  <div class="h-px w-6 opacity-30 md:hidden" style={"background: #{@p["accent_color"] || "#D4AF37"}"}></div>
                  <div
                    class="text-[10px] font-semibold uppercase"
                    style={"letter-spacing: 0.26em; color: #{@p["accent_color"] || "#D4AF37"};"}
                  >
                    {@p["brand_name"]}
                  </div>
                  <div class="h-px w-6 opacity-30 md:hidden" style={"background: #{@p["accent_color"] || "#D4AF37"}"}></div>
                </div>
              <% end %>
              <%= if @p["model_name"] do %>
                <h3
                  class="text-[18px] md:text-[20px] font-bold uppercase leading-[1.1]"
                  style={"font-family: 'Inter', serif; letter-spacing: 0.1em; color: #{@p["text_color"] || "#E8E4DD"};"}
                >
                  {@p["model_name"]}
                </h3>
              <% end %>
              <%= if @p["reference"] do %>
                <div class="text-[11px] italic opacity-70" style="font-family: Georgia, serif;">
                  {@p["reference"]}
                </div>
              <% end %>
              <%= if @p["price_usd"] do %>
                <div class="inline-flex items-baseline gap-1.5 mt-1 leading-none">
                  <img src="https://ik.imagekit.io/blockster/solana-sol-logo.png" alt="SOL" width="20" height="20" class="rounded-full translate-y-1" />
                  <span
                    class="text-[22px] font-semibold"
                    style={"font-family: 'JetBrains Mono', ui-monospace, monospace; font-variant-numeric: tabular-nums; color: #{@p["text_color"] || "#E8E4DD"};"}
                  >
                    {luxury_watch_price_sol(@p["price_usd"])}
                  </span>
                  <span class="text-[12px] font-medium uppercase tracking-[0.2em] opacity-70">SOL</span>
                  <span class="text-[10px] opacity-50 ml-2" style="font-family: 'JetBrains Mono', ui-monospace, monospace;">
                    ≈ ${luxury_watch_format_usd(@p["price_usd"])}
                  </span>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </a>
    </div>
    """
  end

  # Luxury watch split — split-card layout repurposed for watches. Dark
  # editorial info column on the left (brand · model · reference · price ·
  # CTA), light watch panel on the right that slots the white-padded
  # skyscraper image into the colored panel area. On mobile the watch
  # image stacks above the info.
  def ad_banner(%{banner: %{template: "luxury_watch_split"}} = assigns) do
    assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))

    ~H"""
    <div class={["mt-6", @class]}>
      <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold pl-1">Sponsored</div>
      <a
        href={@banner.link_url || "#"}
        target="_blank"
        rel="noopener"
        class="block group"
        phx-click="track_ad_click"
        phx-value-id={@banner.id}
      >
        <div
          class="relative rounded-2xl overflow-hidden ring-1 ring-black/5 shadow-[0_20px_40px_-12px_rgba(0,0,0,0.18)] hover:shadow-[0_28px_50px_-15px_rgba(0,0,0,0.22)] transition-shadow"
          style={"background: linear-gradient(135deg, #{@p["bg_color"] || "#0e0e0e"}, #{@p["bg_color_end"] || "#1a1a1a"}); color: #{@p["text_color"] || "#E8E4DD"};"}
        >
          <div class="grid grid-cols-1 md:grid-cols-[1fr_240px] items-stretch">
            <%!-- Left: editorial info column --%>
            <div class="p-7 flex flex-col justify-center">
              <%= if @p["brand_name"] do %>
                <div class="inline-flex items-center gap-2 mb-3">
                  <div class="h-px w-6 opacity-40" style={"background: #{@p["accent_color"] || "#C9A961"}"}></div>
                  <div
                    class="text-[10px] font-semibold uppercase"
                    style={"letter-spacing: 0.28em; color: #{@p["accent_color"] || "#C9A961"};"}
                  >
                    {@p["brand_name"]}
                  </div>
                </div>
              <% end %>
              <%= if @p["model_name"] do %>
                <h3
                  class="text-[24px] md:text-[26px] font-bold uppercase leading-[1.08] mb-2"
                  style={"font-family: 'Inter', 'Helvetica Neue', serif; letter-spacing: 0.08em; color: #{@p["text_color"] || "#E8E4DD"};"}
                >
                  {@p["model_name"]}
                </h3>
              <% end %>
              <%= if @p["reference"] do %>
                <div class="text-[12px] italic opacity-70 mb-4" style="font-family: Georgia, serif;">
                  {@p["reference"]}
                </div>
              <% end %>
              <%= if @p["price_usd"] do %>
                <div class="inline-flex items-baseline gap-1.5 mb-5 leading-none">
                  <img src="https://ik.imagekit.io/blockster/solana-sol-logo.png" alt="SOL" width="22" height="22" class="rounded-full translate-y-1" />
                  <span
                    class="text-[26px] font-semibold"
                    style={"font-family: 'JetBrains Mono', ui-monospace, monospace; font-variant-numeric: tabular-nums; color: #{@p["text_color"] || "#E8E4DD"};"}
                  >
                    {luxury_watch_price_sol(@p["price_usd"])}
                  </span>
                  <span class="text-[13px] font-medium uppercase tracking-[0.2em] opacity-70">SOL</span>
                  <span class="text-[11px] opacity-50 ml-2" style="font-family: 'JetBrains Mono', ui-monospace, monospace;">
                    ≈ ${luxury_watch_format_usd(@p["price_usd"])}
                  </span>
                </div>
              <% end %>
              <div
                class="inline-flex items-center self-start gap-2 px-5 py-2 rounded-full text-[11px] font-semibold uppercase tracking-[0.2em] transition-colors"
                style={"border: 1px solid #{@p["accent_color"] || "#C9A961"}; color: #{@p["accent_color"] || "#C9A961"};"}
              >
                {@p["cta_text"] || "Inspect the piece"}
                <span class="inline-block" style="letter-spacing: 0;">→</span>
              </div>
            </div>

            <%!-- Right: watch image panel. object-contain shows the whole
                 watch (no crop). The light bg matches the image's white
                 padding so any unused space blends seamlessly. --%>
            <%= if @p["image_url"] do %>
              <div
                class="relative grid place-items-center min-h-[200px] p-4"
                style={"background: #{@p["image_bg_color"] || "#f5f5f4"};"}
              >
                <img
                  src={ad_image_url(@p["image_url"])}
                  alt={@p["model_name"] || ""}
                  class="max-w-full max-h-full w-auto h-auto object-contain block"
                />
                <div class="absolute bottom-2 right-2 px-1.5 py-0.5 bg-white/85 rounded text-[9px] font-bold uppercase tracking-wider text-neutral-700">Ad</div>
              </div>
            <% end %>
          </div>
        </div>
      </a>
    </div>
    """
  end

  # Luxury car — bold landscape hero image with dark info panel below.
  # Brand strip at top, edge-to-edge car photo, then model · year/spec
  # row · live SOL price (with USD subtitle) · CTA. Designed for landscape
  # exotic-car listings (Ferrari, Lamborghini, etc.).
  def ad_banner(%{banner: %{template: "luxury_car"}} = assigns) do
    assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))

    ~H"""
    <div class={["not-prose my-12 flex justify-center", @class]}>
      <div class="w-full max-w-[560px]">
        <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold text-center">Sponsored</div>
        <a
          href={@banner.link_url || "#"}
          target="_blank"
          rel="noopener"
          class="block group"
          phx-click="track_ad_click"
          phx-value-id={@banner.id}
        >
          <div
            class="rounded-2xl overflow-hidden ring-1 ring-black/5 shadow-[0_30px_60px_-15px_rgba(0,0,0,0.30)] relative"
            style={"background: linear-gradient(180deg, #{@p["bg_color"] || "#0a0a0a"}, #{@p["bg_color_end"] || "#1a1a1a"}); color: #{@p["text_color"] || "#E8E4DD"};"}
          >
            <%!-- Brand strip at top — bold dealer name in accent color --%>
            <%= if @p["brand_name"] do %>
              <div class="px-6 pt-5 pb-4 flex items-center justify-between">
                <div class="inline-flex items-center gap-2.5">
                  <div class="h-px w-6" style={"background: #{@p["accent_color"] || "#FF2800"}"}></div>
                  <div
                    class="text-[11px] font-bold uppercase"
                    style={"letter-spacing: 0.24em; color: #{@p["accent_color"] || "#FF2800"};"}
                  >
                    {@p["brand_name"]}
                  </div>
                </div>
                <%= if @p["badge"] do %>
                  <div
                    class="text-[9px] font-semibold uppercase tracking-[0.18em] px-2 py-1 rounded"
                    style={"background: #{@p["accent_color"] || "#FF2800"}1a; color: #{@p["accent_color"] || "#FF2800"};"}
                  >
                    {@p["badge"]}
                  </div>
                <% end %>
              </div>
            <% end %>

            <%!-- Hero car photo, edge-to-edge --%>
            <%= if @p["image_url"] do %>
              <div class="relative" style={"background: #{@p["image_bg_color"] || "#0a0a0a"};"}>
                <img
                  src={ad_image_url(@p["image_url"])}
                  alt={@p["model_name"] || ""}
                  class="w-full h-auto block"
                />
                <div class="absolute bottom-3 right-3 px-1.5 py-0.5 bg-white/85 rounded text-[9px] font-bold uppercase tracking-wider text-neutral-700">Ad</div>
              </div>
            <% end %>

            <%!-- Info panel: model, spec row, price, CTA --%>
            <div class="px-6 py-6">
              <%= if @p["year"] || @p["model_name"] do %>
                <h3
                  class="text-[26px] md:text-[30px] font-bold uppercase leading-[1.05] mb-1"
                  style={"font-family: 'Inter', 'Helvetica Neue', sans-serif; letter-spacing: -0.005em; color: #{@p["text_color"] || "#E8E4DD"};"}
                >
                  <%= if @p["year"] do %>
                    <span style={"color: #{@p["accent_color"] || "#FF2800"};"}>{@p["year"]}</span>&nbsp;
                  <% end %>{@p["model_name"]}
                </h3>
              <% end %>
              <%= if @p["trim"] do %>
                <div class="text-[12px] italic opacity-70 mb-4" style="font-family: Georgia, serif;">
                  {@p["trim"]}
                </div>
              <% end %>

              <%!-- Spec row removed — kept the trim line above for color/variant info --%>
              <div class="mb-5 pb-5 border-b border-white/[0.08]"></div>

              <%!-- Price row + CTA --%>
              <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-4">
                <%= if @p["price_usd"] do %>
                  <div class="inline-flex items-baseline gap-1.5 leading-none">
                    <img src="https://ik.imagekit.io/blockster/solana-sol-logo.png" alt="SOL" width="22" height="22" class="rounded-full translate-y-1" />
                    <span
                      class="text-[28px] font-semibold"
                      style={"font-family: 'JetBrains Mono', ui-monospace, monospace; font-variant-numeric: tabular-nums; color: #{@p["text_color"] || "#E8E4DD"};"}
                    >
                      {luxury_watch_price_sol(@p["price_usd"])}
                    </span>
                    <span class="text-[14px] font-medium uppercase tracking-[0.2em] opacity-70">SOL</span>
                    <span class="text-[11px] opacity-50 ml-2" style="font-family: 'JetBrains Mono', ui-monospace, monospace;">
                      ≈ ${luxury_watch_format_usd(@p["price_usd"])}
                    </span>
                  </div>
                <% end %>
                <div
                  class="inline-flex self-start md:self-auto items-center gap-2 px-5 py-2.5 rounded-full text-[11px] font-bold uppercase tracking-[0.2em] transition-colors"
                  style={"border: 1px solid #{@p["accent_color"] || "#FF2800"}; color: #{@p["accent_color"] || "#FF2800"};"}
                >
                  {@p["cta_text"] || "View this car"}
                  <span class="inline-block" style="letter-spacing: 0;">→</span>
                </div>
              </div>
            </div>
          </div>
        </a>
      </div>
    </div>
    """
  end

  # Luxury car skyscraper — 200px-wide tall sidebar variant of luxury_car.
  # Sized to fit alongside watch skyscrapers in article sidebars.
  def ad_banner(%{banner: %{template: "luxury_car_skyscraper"}} = assigns) do
    assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))

    ~H"""
    <a
      href={@banner.link_url || "#"}
      target="_blank"
      rel="noopener"
      class={["block group w-[200px]", @class]}
      phx-click="track_ad_click"
      phx-value-id={@banner.id}
    >
      <div
        class="rounded-xl overflow-hidden ring-1 ring-black/5 shadow-[0_12px_24px_-10px_rgba(0,0,0,0.25)] relative"
        style={"background: linear-gradient(180deg, #{@p["bg_color"] || "#0a0a0a"}, #{@p["bg_color_end"] || "#1a1a1a"}); color: #{@p["text_color"] || "#E8E4DD"};"}
      >
        <%= if @p["brand_name"] do %>
          <div class="pt-3 pb-2 px-3 flex items-center gap-1.5">
            <div class="h-px w-2 opacity-50" style={"background: #{@p["accent_color"] || "#FF2800"}"}></div>
            <div class="text-[8px] font-bold uppercase truncate" style={"letter-spacing: 0.18em; color: #{@p["accent_color"] || "#FF2800"};"}>
              {@p["brand_name"]}
            </div>
          </div>
        <% end %>

        <%= if @p["image_url"] do %>
          <div class="relative" style={"background: #{@p["image_bg_color"] || "#0a0a0a"};"}>
            <img
              src={ad_image_url(@p["image_url"])}
              alt={@p["model_name"] || ""}
              class="w-full h-auto block"
            />
            <div class="absolute bottom-1.5 right-1.5 px-1 py-px bg-white/85 rounded text-[7px] font-bold uppercase tracking-wider text-neutral-700">Ad</div>
          </div>
        <% end %>

        <div class="px-3 pt-3 pb-4">
          <%= if @p["year"] || @p["model_name"] do %>
            <h3 class="text-[12px] font-bold uppercase leading-[1.1]" style={"font-family: 'Inter', sans-serif; letter-spacing: -0.005em; color: #{@p["text_color"] || "#E8E4DD"};"}>
              <%= if @p["year"] do %>
                <span style={"color: #{@p["accent_color"] || "#FF2800"};"}>{@p["year"]}</span>
              <% end %>
              {@p["model_name"]}
            </h3>
          <% end %>
          <%= if @p["trim"] do %>
            <div class="text-[9px] italic opacity-65 mt-0.5 leading-snug" style="font-family: Georgia, serif;">
              {@p["trim"]}
            </div>
          <% end %>
          <%= if @p["price_usd"] do %>
            <div class="mt-2 inline-flex items-baseline gap-1 leading-none">
              <img src="https://ik.imagekit.io/blockster/solana-sol-logo.png" alt="SOL" width="14" height="14" class="rounded-full translate-y-px" />
              <span
                class="text-[14px] font-semibold"
                style={"font-family: 'JetBrains Mono', ui-monospace, monospace; font-variant-numeric: tabular-nums; color: #{@p["text_color"] || "#E8E4DD"};"}
              >
                {luxury_watch_price_sol(@p["price_usd"])}
              </span>
              <span class="text-[8px] font-medium uppercase tracking-[0.18em] opacity-70">SOL</span>
            </div>
            <div class="text-[8.5px] mt-0.5 opacity-55" style="font-family: 'JetBrains Mono', ui-monospace, monospace;">
              ≈ ${luxury_watch_format_usd(@p["price_usd"])}
            </div>
          <% end %>
        </div>
      </div>
    </a>
    """
  end

  # Luxury car banner — full-width horizontal leaderboard. Image left,
  # year/model + price + CTA right. Stacks vertically on mobile.
  def ad_banner(%{banner: %{template: "luxury_car_banner"}} = assigns) do
    assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))

    ~H"""
    <div class={["not-prose my-6", @class]}>
      <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold text-center">Sponsored</div>
      <a
        href={@banner.link_url || "#"}
        target="_blank"
        rel="noopener"
        class="block group"
        phx-click="track_ad_click"
        phx-value-id={@banner.id}
      >
        <div
          class="rounded-2xl overflow-hidden ring-1 ring-black/5 shadow-[0_20px_40px_-12px_rgba(0,0,0,0.30)] relative"
          style={"background: linear-gradient(90deg, #{@p["bg_color"] || "#0a0a0a"}, #{@p["bg_color_end"] || "#1a1a1a"}); color: #{@p["text_color"] || "#E8E4DD"};"}
        >
          <div class="flex flex-col md:flex-row items-stretch">
            <%!-- Image left (wider for landscape car photos) --%>
            <%= if @p["image_url"] do %>
              <div
                class="relative shrink-0 w-full md:w-[300px] h-[200px] md:h-[180px]"
                style={"background: #{@p["image_bg_color"] || "#0a0a0a"};"}
              >
                <img
                  src={ad_image_url(@p["image_url"])}
                  alt={@p["model_name"] || ""}
                  class="w-full h-full object-cover"
                />
                <div class="absolute bottom-2 right-2 px-1.5 py-0.5 bg-white/85 rounded text-[9px] font-bold uppercase tracking-wider text-neutral-700">Ad</div>
              </div>
            <% end %>

            <%!-- Right: brand · year+model · trim · price · CTA --%>
            <div class="flex-1 px-6 py-5 flex flex-col justify-center md:items-start items-center text-center md:text-left gap-2">
              <%= if @p["brand_name"] do %>
                <div class="inline-flex items-center gap-2">
                  <div class="h-px w-5 opacity-40" style={"background: #{@p["accent_color"] || "#FF2800"}"}></div>
                  <div
                    class="text-[10px] font-bold uppercase"
                    style={"letter-spacing: 0.24em; color: #{@p["accent_color"] || "#FF2800"};"}
                  >
                    {@p["brand_name"]}
                  </div>
                </div>
              <% end %>
              <%= if @p["year"] || @p["model_name"] do %>
                <h3
                  class="text-[20px] md:text-[22px] font-bold uppercase leading-[1.05]"
                  style={"font-family: 'Inter', sans-serif; letter-spacing: -0.005em; color: #{@p["text_color"] || "#E8E4DD"};"}
                >
                  <%= if @p["year"] do %>
                    <span style={"color: #{@p["accent_color"] || "#FF2800"};"}>{@p["year"]}</span>&nbsp;
                  <% end %>{@p["model_name"]}
                </h3>
              <% end %>
              <%= if @p["trim"] do %>
                <div class="text-[11px] italic opacity-70" style="font-family: Georgia, serif;">
                  {@p["trim"]}
                </div>
              <% end %>
              <%= if @p["price_usd"] do %>
                <div class="inline-flex items-baseline gap-1.5 mt-1 leading-none">
                  <img src="https://ik.imagekit.io/blockster/solana-sol-logo.png" alt="SOL" width="20" height="20" class="rounded-full translate-y-1" />
                  <span
                    class="text-[24px] font-semibold"
                    style={"font-family: 'JetBrains Mono', ui-monospace, monospace; font-variant-numeric: tabular-nums; color: #{@p["text_color"] || "#E8E4DD"};"}
                  >
                    {luxury_watch_price_sol(@p["price_usd"])}
                  </span>
                  <span class="text-[12px] font-medium uppercase tracking-[0.2em] opacity-70">SOL</span>
                  <span class="text-[10px] opacity-50 ml-2" style="font-family: 'JetBrains Mono', ui-monospace, monospace;">
                    ≈ ${luxury_watch_format_usd(@p["price_usd"])}
                  </span>
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </a>
    </div>
    """
  end

  # Jet card compact — pre-paid private aviation hours block. The original
  # full-width `jet_card` template was removed in favor of this compact
  # Trimmed padding, smaller hero image (assumes a tightly cropped jet
  # photo), no benefit bullets row. Use when you want the jet ad without
  # taking over the article column.
  def ad_banner(%{banner: %{template: "jet_card_compact"}} = assigns) do
    assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))

    ~H"""
    <div class={["not-prose my-10 flex justify-center", @class]}>
      <div class="w-full max-w-[560px]">
        <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold text-center">Sponsored</div>
        <a
          href={@banner.link_url || "#"}
          target="_blank"
          rel="noopener"
          class="block group"
          phx-click="track_ad_click"
          phx-value-id={@banner.id}
        >
          <div
            class="rounded-2xl overflow-hidden ring-1 ring-black/5 shadow-[0_24px_48px_-14px_rgba(0,0,0,0.30)] relative"
            style={"background: linear-gradient(180deg, #{@p["bg_color"] || "#0a1838"}, #{@p["bg_color_end"] || "#142a6b"}); color: #{@p["text_color"] || "#E8E4DD"};"}
          >
            <%= if @p["brand_name"] do %>
              <div class="px-5 pt-4 pb-3 flex items-center justify-between">
                <div class="inline-flex items-center gap-2">
                  <div class="h-px w-5" style={"background: #{@p["accent_color"] || "#D4AF37"}"}></div>
                  <div
                    class="text-[10px] font-bold uppercase"
                    style={"letter-spacing: 0.22em; color: #{@p["accent_color"] || "#D4AF37"};"}
                  >
                    {@p["brand_name"]}
                  </div>
                </div>
                <%= if @p["badge"] do %>
                  <div
                    class="text-[8px] font-semibold uppercase tracking-[0.18em] px-2 py-0.5 rounded"
                    style={"background: #{@p["accent_color"] || "#D4AF37"}1a; color: #{@p["accent_color"] || "#D4AF37"};"}
                  >
                    {@p["badge"]}
                  </div>
                <% end %>
              </div>
            <% end %>

            <%= if @p["image_url"] do %>
              <div class="relative" style={"background: #{@p["image_bg_color"] || "#0a1838"};"}>
                <img
                  src={ad_image_url(@p["image_url"])}
                  alt={@p["headline"] || ""}
                  class="w-full h-auto block"
                />
                <div class="absolute bottom-2 right-2 px-1.5 py-0.5 bg-white/85 rounded text-[9px] font-bold uppercase tracking-wider text-neutral-700">Ad</div>
              </div>
            <% end %>

            <div class="px-5 py-5">
              <%= if @p["hours"] do %>
                <h3
                  class="text-[34px] font-bold leading-[0.95] mb-1"
                  style={"font-family: 'Inter', sans-serif; letter-spacing: -0.02em; color: #{@p["text_color"] || "#E8E4DD"};"}
                >
                  <span style={"color: #{@p["accent_color"] || "#D4AF37"};"}>{@p["hours"]}</span><span class="ml-2 text-[15px] font-medium uppercase tracking-[0.18em] opacity-70">Hours</span>
                </h3>
              <% end %>
              <%= if @p["headline"] do %>
                <div class="text-[14px] font-medium opacity-90">
                  {@p["headline"]}
                </div>
              <% end %>
              <%= if @p["aircraft_category"] do %>
                <div class="text-[11px] italic opacity-65 mb-4" style="font-family: Georgia, serif;">
                  {@p["aircraft_category"]}
                </div>
              <% end %>

              <div class="flex flex-col md:flex-row md:items-center md:justify-between gap-3 pt-3 border-t border-white/[0.08]">
                <%= if @p["price_usd"] do %>
                  <div class="inline-flex items-baseline gap-1.5 leading-none">
                    <img src="https://ik.imagekit.io/blockster/solana-sol-logo.png" alt="SOL" width="20" height="20" class="rounded-full translate-y-1" />
                    <span
                      class="text-[24px] font-semibold"
                      style={"font-family: 'JetBrains Mono', ui-monospace, monospace; font-variant-numeric: tabular-nums; color: #{@p["text_color"] || "#E8E4DD"};"}
                    >
                      {luxury_watch_price_sol(@p["price_usd"])}
                    </span>
                    <span class="text-[12px] font-medium uppercase tracking-[0.2em] opacity-70">SOL</span>
                    <span class="text-[10px] opacity-50 ml-2" style="font-family: 'JetBrains Mono', ui-monospace, monospace;">
                      ≈ ${luxury_watch_format_usd(@p["price_usd"])}
                    </span>
                  </div>
                <% end %>
                <div
                  class="inline-flex self-start md:self-auto items-center gap-2 px-4 py-2 rounded-full text-[10px] font-bold uppercase tracking-[0.2em] transition-colors"
                  style={"border: 1px solid #{@p["accent_color"] || "#D4AF37"}; color: #{@p["accent_color"] || "#D4AF37"};"}
                >
                  {@p["cta_text"] || "Buy Jet Card"}
                  <span class="inline-block" style="letter-spacing: 0;">→</span>
                </div>
              </div>
            </div>
          </div>
        </a>
      </div>
    </div>
    """
  end

  # Jet card skyscraper — 200px-wide tall sidebar variant.
  def ad_banner(%{banner: %{template: "jet_card_skyscraper"}} = assigns) do
    assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))

    ~H"""
    <a
      href={@banner.link_url || "#"}
      target="_blank"
      rel="noopener"
      class={["block group w-[200px]", @class]}
      phx-click="track_ad_click"
      phx-value-id={@banner.id}
    >
      <div
        class="rounded-xl overflow-hidden ring-1 ring-black/5 shadow-[0_12px_24px_-10px_rgba(0,0,0,0.25)] relative"
        style={"background: linear-gradient(180deg, #{@p["bg_color"] || "#0a1838"}, #{@p["bg_color_end"] || "#142a6b"}); color: #{@p["text_color"] || "#E8E4DD"};"}
      >
        <%= if @p["brand_name"] do %>
          <div class="pt-3 pb-2 px-3 flex items-center gap-1.5">
            <div class="h-px w-2 opacity-50" style={"background: #{@p["accent_color"] || "#D4AF37"}"}></div>
            <div class="text-[8px] font-bold uppercase truncate" style={"letter-spacing: 0.18em; color: #{@p["accent_color"] || "#D4AF37"};"}>
              {@p["brand_name"]}
            </div>
          </div>
        <% end %>

        <%= if @p["image_url"] do %>
          <div class="relative" style={"background: #{@p["image_bg_color"] || "#0a1838"};"}>
            <img
              src={ad_image_url(@p["image_url"])}
              alt={@p["headline"] || ""}
              class="w-full h-auto block"
            />
            <div class="absolute bottom-1.5 right-1.5 px-1 py-px bg-white/85 rounded text-[7px] font-bold uppercase tracking-wider text-neutral-700">Ad</div>
          </div>
        <% end %>

        <div class="px-3 pt-3 pb-4">
          <%= if @p["hours"] do %>
            <h3 class="text-[28px] font-bold leading-[0.95]" style={"font-family: 'Inter', sans-serif; letter-spacing: -0.02em; color: #{@p["text_color"] || "#E8E4DD"};"}>
              <span style={"color: #{@p["accent_color"] || "#D4AF37"};"}>{@p["hours"]}</span>
              <span class="text-[10px] font-medium uppercase tracking-[0.18em] opacity-70 ml-1">hrs</span>
            </h3>
          <% end %>
          <%= if @p["headline"] do %>
            <div class="text-[10px] font-medium leading-snug mt-0.5 opacity-90">
              {@p["headline"]}
            </div>
          <% end %>
          <%= if @p["aircraft_category"] do %>
            <div class="text-[8.5px] italic opacity-65 mt-1 leading-snug" style="font-family: Georgia, serif;">
              {@p["aircraft_category"]}
            </div>
          <% end %>
          <%= if @p["price_usd"] do %>
            <div class="mt-2.5 inline-flex items-baseline gap-1 leading-none">
              <img src="https://ik.imagekit.io/blockster/solana-sol-logo.png" alt="SOL" width="14" height="14" class="rounded-full translate-y-px" />
              <span
                class="text-[15px] font-semibold"
                style={"font-family: 'JetBrains Mono', ui-monospace, monospace; font-variant-numeric: tabular-nums; color: #{@p["text_color"] || "#E8E4DD"};"}
              >
                {luxury_watch_price_sol(@p["price_usd"])}
              </span>
              <span class="text-[8px] font-medium uppercase tracking-[0.18em] opacity-70">SOL</span>
            </div>
            <div class="text-[8.5px] mt-0.5 opacity-55" style="font-family: 'JetBrains Mono', ui-monospace, monospace;">
              ≈ ${luxury_watch_format_usd(@p["price_usd"])}
            </div>
          <% end %>
        </div>
      </div>
    </a>
    """
  end

  # Patriotic editorial portrait — centered brand wordmark · full-width
  # hero portrait with red/white/blue flag stripe across the top · bold
  # model name · italic reference line · central tagline · uppercase
  # subheading · rounded outline CTA. Designed for commemorative / political
  # ads (e.g. 250-year anniversary tribute).
  def ad_banner(%{banner: %{template: "patriotic_portrait"}} = assigns) do
    assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))

    ~H"""
    <div class={["not-prose my-12 flex justify-center", @class]}>
      <div class="w-full max-w-[560px]">
        <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold text-center">Sponsored</div>
        <a
          href={@banner.link_url || "#"}
          target="_blank"
          rel="noopener"
          class="block group"
          phx-click="track_ad_click"
          phx-value-id={@banner.id}
        >
          <div
            class="rounded-2xl overflow-hidden ring-1 ring-black/5 shadow-[0_30px_60px_-15px_rgba(0,0,0,0.25)] relative"
            style={"background: linear-gradient(180deg, #{@p["bg_color"] || "#0a0a0a"}, #{@p["bg_color_end"] || "#1a1a1a"}); color: #{@p["text_color"] || "#E8E4DD"};"}
          >
            <%!-- Brand wordmark strip --%>
            <%= if @p["brand_name"] do %>
              <div class="pt-7 pb-4 flex items-center justify-center gap-3">
                <div class="h-px w-10 opacity-40" style={"background: #{@p["accent_color"] || "#C9A961"}"}></div>
                <div class="text-[11px] font-semibold uppercase" style={"letter-spacing: 0.28em; color: #{@p["accent_color"] || "#C9A961"};"}>
                  {@p["brand_name"]}
                </div>
                <div class="h-px w-10 opacity-40" style={"background: #{@p["accent_color"] || "#C9A961"}"}></div>
              </div>
            <% end %>

            <%!-- Hero portrait with American flag stripe across the top --%>
            <%= if @p["image_url"] do %>
              <div
                class="relative"
                style={"background: #{@p["image_bg_color"] || "#FFFFFF"};"}
              >
                <img
                  src={ad_image_url(@p["image_url"])}
                  alt={@p["model_name"] || ""}
                  class="w-full h-auto block"
                />
                <div
                  class="absolute top-0 left-0 right-0 h-2 z-10"
                  style="background: linear-gradient(90deg, #BF0A30 33%, #FFFFFF 33% 66%, #002868 66%);"
                ></div>
                <div class="absolute bottom-3 right-3 px-1.5 py-0.5 bg-white/85 rounded text-[9px] font-bold uppercase tracking-wider text-neutral-700">Ad</div>
              </div>
            <% end %>

            <%!-- Gold divider --%>
            <div class="flex justify-center pt-8">
              <div class="h-px w-16" style={"background: #{@p["accent_color"] || "#C9A961"}; opacity: 0.5;"}></div>
            </div>

            <%!-- Model name (bold · uppercase) + italic reference --%>
            <div class="px-8 pt-5 text-center">
              <%= if @p["model_name"] do %>
                <h3
                  class="text-[22px] font-bold tracking-tight uppercase leading-[1.1]"
                  style={"font-family: 'Inter', 'Helvetica Neue', serif; letter-spacing: 0.12em; color: #{@p["text_color"] || "#E8E4DD"};"}
                >
                  {@p["model_name"]}
                </h3>
              <% end %>
              <%= if @p["reference"] do %>
                <div class="text-[11px] mt-2 italic opacity-75" style="font-family: Georgia, 'Times New Roman', serif;">
                  {@p["reference"]}
                </div>
              <% end %>
            </div>

            <%!-- Central tagline (big, colored) --%>
            <%= if @p["heading"] do %>
              <div class="px-8 pt-6 text-center">
                <div
                  class="text-[24px] md:text-[26px] font-bold leading-[1.15]"
                  style={"font-family: 'Inter', sans-serif; color: #{@p["accent_color"] || "#C9A961"}; letter-spacing: -0.01em;"}
                >
                  {@p["heading"]}
                </div>
              </div>
            <% end %>

            <%!-- Subheading (small uppercase) --%>
            <%= if @p["subheading"] do %>
              <div class="px-8 pt-3 text-center">
                <div class="text-[11px] opacity-55 font-semibold" style="letter-spacing: 0.18em; text-transform: uppercase;">
                  {@p["subheading"]}
                </div>
              </div>
            <% end %>

            <%!-- Outline CTA pill — uses first word of cta on mobile so wide
                 uppercase tracking doesn't blow the pill out of the card. --%>
            <% cta_full = @p["cta_text"] || "Learn more" %>
            <% cta_short = cta_full |> String.split(" ", trim: true) |> List.first() || cta_full %>
            <div class="pb-8 px-6 md:px-8 pt-6 text-center">
              <div
                class="hidden md:inline-flex items-center gap-2 px-5 py-3 rounded-full font-bold text-[11px] uppercase tracking-[0.2em] transition-colors"
                style={"border: 1px solid #{@p["accent_color"] || "#C9A961"}; color: #{@p["accent_color"] || "#C9A961"};"}
              >
                {cta_full}
                <span class="inline-block">→</span>
              </div>
              <div
                class="inline-flex md:hidden items-center gap-2 px-4 py-2.5 rounded-full font-bold text-[10px] uppercase tracking-[0.16em] transition-colors"
                style={"border: 1px solid #{@p["accent_color"] || "#C9A961"}; color: #{@p["accent_color"] || "#C9A961"};"}
              >
                {cta_short}
                <span class="inline-block">→</span>
              </div>
            </div>
          </div>
        </a>
      </div>
    </div>
    """
  end

  # Trump 2028 loop — square (1:1) animated ad. 10s loop:
  #   0–25%   headline ("America needs him, again.") on black
  #   25–62%  headline fades, hero image fades in + out
  #   60–92%  "TRUMP" / "2028" / subtitle on black (no glow)
  # CSS under `.t28-*` prefix in app.css.
  def ad_banner(%{banner: %{template: "trump_2028_loop"}} = assigns) do
    assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))

    headline_words =
      (assigns.p["headline"] || "")
      |> String.split(~r/\s+/, trim: true)
      |> Enum.take(6)

    assigns = assign(assigns, :headline_words, headline_words)

    ~H"""
    <div class={["not-prose my-12 flex justify-center", @class]}>
      <div class="w-full" style="max-width: 440px;">
        <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold text-center">Sponsored</div>
        <a
          href={@banner.link_url || "#"}
          target="_blank"
          rel="noopener"
          class="block group"
          phx-click="track_ad_click"
          phx-value-id={@banner.id}
        >
          <div class="t28-frame">
            <%= if @p["image_url"] do %>
              <div class="t28-img" style={"background-image: url('#{ad_image_url(@p["image_url"])}');"}></div>
            <% end %>
            <div class="t28-dim"></div>

            <%= if @p["brand_name"] do %>
              <div class="t28-brand">{@p["brand_name"]}</div>
            <% end %>
            <div class="t28-ad-badge">Ad</div>

            <%!-- Stage 1: headline --%>
            <div class="t28-headline-layer">
              <div class="t28-hl">
                <%= for word <- @headline_words do %><span>{word}</span> <% end %>
              </div>
            </div>

            <%!-- Stage 2: "TRUMP" / "2028" / subtitle --%>
            <div class="t28-reveal-layer">
              <%= if @p["top_text"] do %>
                <div class="t28-top">{@p["top_text"]}</div>
              <% end %>
              <%= if @p["number_text"] do %>
                <div class="t28-num" style={"color: #{@p["number_color"] || "#BF0A30"};"}>
                  {@p["number_text"]}
                </div>
              <% end %>
              <%= if @p["subtitle"] do %>
                <div class="t28-subtitle">{@p["subtitle"]}</div>
              <% end %>
            </div>

            <%!-- CTA --%>
            <div class="t28-cta">
              <div class="t28-cta-btn" style={"background: #{@p["accent_color"] || "#BF0A30"};"}>
                {@p["cta_text"] || "Learn more"}
                <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="none">
                  <path d="M3 10h12m0 0l-4-4m4 4l-4 4" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"/>
                </svg>
              </div>
            </div>
          </div>
        </a>
      </div>
    </div>
    """
  end

  # Patriotic loop — square (1:1) animated ad. 11s loop:
  #   0–30%  : headline writes word-by-word on black
  #   30–58% : hero image fades in (with grain)
  #   58–65% : image fades out
  #   65–92% : "THANK YOU" + "47" (or similar) shown on black, no glow
  #   92–100%: fades, restart
  # CSS lives in `assets/css/app.css` under the `.pl-*` prefix.
  def ad_banner(%{banner: %{template: "patriotic_loop"}} = assigns) do
    assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))

    # Split headline into word spans so the CSS nth-child word-by-word
    # animation can stagger them. Max 10 words (matches CSS nth-child rules).
    headline_words =
      (assigns.p["headline"] || "")
      |> String.split(~r/\s+/, trim: true)
      |> Enum.take(10)

    assigns = assign(assigns, :headline_words, headline_words)

    ~H"""
    <div class={["not-prose my-12 flex justify-center", @class]}>
      <div class="w-full" style="max-width: 440px;">
        <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold text-center">Sponsored</div>
        <a
          href={@banner.link_url || "#"}
          target="_blank"
          rel="noopener"
          class="block group"
          phx-click="track_ad_click"
          phx-value-id={@banner.id}
        >
          <div class="pl-frame">
            <%= if @p["image_url"] do %>
              <div class="pl-img" style={"background-image: url('#{ad_image_url(@p["image_url"])}');"}></div>
            <% end %>
            <div class="pl-dim"></div>
            <div class="pl-grain"></div>

            <%!-- Brand wordmark top-left + AD badge top-right --%>
            <%= if @p["brand_name"] do %>
              <div class="pl-brand">{@p["brand_name"]}</div>
            <% end %>
            <div class="pl-ad-badge">Ad</div>

            <%!-- Stage 1: headline words --%>
            <div class="pl-headline-layer">
              <div class="pl-headline">
                <%= for word <- @headline_words do %><span>{word}</span> <% end %>
              </div>
            </div>

            <%!-- Stage 2: THANK YOU + "47" on black --%>
            <div class="pl-thank-layer">
              <%= if @p["thank_top"] do %>
                <div class="pl-thank-top">{@p["thank_top"]}</div>
              <% end %>
              <%= if @p["number_text"] do %>
                <div class="pl-num" style={"color: #{@p["number_color"] || "#BF0A30"};"}>
                  {@p["number_text"]}
                </div>
              <% end %>
            </div>

            <%!-- CTA + meta at bottom --%>
            <div class="pl-cta">
              <div class="pl-cta-btn" style={"background: #{@p["accent_color"] || "#BF0A30"};"}>
                {@p["cta_text"] || "Learn more"}
                <svg class="w-3.5 h-3.5" viewBox="0 0 20 20" fill="none">
                  <path d="M3 10h12m0 0l-4-4m4 4l-4 4" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"/>
                </svg>
              </div>
              <%= if @p["cta_meta"] do %>
                <div class="pl-cta-meta">{@p["cta_meta"]}</div>
              <% end %>
            </div>
          </div>
        </a>
      </div>
    </div>
    """
  end

  # Streaming-service trial ad (FOX One, Hulu, Disney+, etc.). Dark card
  # with a bold brand wordmark, optional 16:9 hero image with gradient
  # overlay, large editorial headline, red/branded "free trial" badge, CTA
  # pill, and a device-availability footer strip. Stacks cleanly on mobile.
  def ad_banner(%{banner: %{template: "streaming_trial"}} = assigns) do
    assigns = assign(assigns, :p, sanitize_ad_params(assigns.banner.params))

    ~H"""
    <div class={["not-prose my-12 flex justify-center", @class]}>
      <div class="w-full max-w-[560px]">
        <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold text-center">Sponsored</div>
        <a
          href={@banner.link_url || "#"}
          target="_blank"
          rel="noopener"
          class="block group"
          phx-click="track_ad_click"
          phx-value-id={@banner.id}
        >
          <div
            class="relative rounded-2xl overflow-hidden shadow-[0_24px_48px_-14px_rgba(0,0,0,0.35)] ring-1 ring-white/[0.06]"
            style={"background: linear-gradient(180deg, #{@p["bg_color"] || "#0a0a0a"}, #{@p["bg_color_end"] || "#1a1a1a"}); color: #{@p["text_color"] || "#ffffff"};"}
          >
            <%!-- Brand strip --%>
            <div class="px-5 pt-4 pb-3 flex items-center justify-between border-b border-white/[0.08]">
              <div class="flex items-center gap-3">
                <%= if @p["brand_name"] do %>
                  <span
                    class="text-[22px] font-black tracking-tight leading-none"
                    style={"font-family: 'Inter', Impact, sans-serif; letter-spacing: -0.02em; color: #{@p["brand_color"] || "#003DA5"};"}
                  >
                    {@p["brand_name"]}
                  </span>
                <% end %>
                <%= if @p["brand_tagline"] do %>
                  <span class="text-[9px] uppercase tracking-[0.2em] font-bold opacity-60 pl-3 border-l border-white/20">
                    {@p["brand_tagline"]}
                  </span>
                <% end %>
              </div>
              <div class="text-[8px] font-bold uppercase tracking-wider bg-white/10 px-1.5 py-0.5 rounded">Ad</div>
            </div>

            <%!-- Optional hero image with gradient overlay --%>
            <%= if @p["image_url"] do %>
              <div class="relative aspect-[16/9] overflow-hidden">
                <img
                  src={ad_image_url(@p["image_url"])}
                  alt={@p["heading"] || ""}
                  class="w-full h-full object-cover"
                />
                <div
                  class="absolute inset-0 pointer-events-none"
                  style={"background: linear-gradient(180deg, rgba(0,0,0,0.0) 30%, #{@p["bg_color"] || "#0a0a0a"} 100%);"}
                ></div>
              </div>
            <% end %>

            <%!-- Body --%>
            <div class="px-5 py-6">
              <%= if @p["heading"] do %>
                <h3
                  class="text-[24px] md:text-[26px] font-bold leading-[1.12] mb-2"
                  style={"font-family: 'Inter', 'Helvetica Neue', sans-serif; letter-spacing: -0.02em; color: #{@p["text_color"] || "#ffffff"};"}
                >
                  {@p["heading"]}
                </h3>
              <% end %>
              <%= if @p["subheading"] do %>
                <p class="text-[13px] leading-snug opacity-70 mb-5 max-w-[480px]">
                  {@p["subheading"]}
                </p>
              <% end %>

              <%!-- Trial badge + price-after row --%>
              <div class="flex flex-wrap items-center gap-3 mb-5">
                <%= if @p["trial_label"] do %>
                  <div
                    class="px-3 py-1.5 rounded font-bold text-[11px] uppercase tracking-[0.14em]"
                    style={"background: #{@p["brand_color"] || "#003DA5"}; color: #{@p["brand_text_color"] || "#ffffff"};"}
                  >
                    {@p["trial_label"]}
                  </div>
                <% end %>
                <%= if @p["price_after"] do %>
                  <span class="text-[12px] opacity-60">
                    then {@p["price_after"]}
                  </span>
                <% end %>
              </div>

              <%!-- CTA --%>
              <div
                class="inline-flex items-center gap-2 px-5 py-3 rounded font-bold text-[13px] uppercase tracking-[0.14em] transition-colors"
                style={"background: #{@p["brand_color"] || "#003DA5"}; color: #{@p["brand_text_color"] || "#ffffff"};"}
              >
                {@p["cta_text"] || "Start Free Trial"}
                <svg class="w-4 h-4" viewBox="0 0 20 20" fill="none">
                  <path d="M3 10h12m0 0l-4-4m4 4l-4 4" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
                </svg>
              </div>
            </div>

            <%!-- Device availability footer --%>
            <%= if @p["watch_on"] do %>
              <div class="px-5 py-3 border-t border-white/[0.08] text-[9px] uppercase tracking-[0.22em] opacity-50 text-center font-semibold">
                {@p["watch_on"]}
              </div>
            <% end %>
          </div>
        </a>
      </div>
    </div>
    """
  end

  # FateSwap A2 · Combined — 440×480 animated ad. Buy→Sell flow driven by
  # the FsA2CombinedAd JS hook; all CSS scoped under .bw-fs-ad-root. See
  # docs/ad_banners_system.md for the system overview and the upstream spec
  # at fateswap/docs/ads/a2_combined_porting_spec.md for the source port.
  def ad_banner(%{banner: %{template: "fateswap_combined"}} = assigns) do
    ~H"""
    <div class={["not-prose my-12 flex justify-center", @class]}>
      <div class="w-full" style="max-width: 440px;">
        <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold text-center">Sponsored</div>
        <a
          href={@banner.link_url || "#"}
          target="_blank"
          rel="noopener"
          class="block group"
          phx-click="track_ad_click"
          phx-value-id={@banner.id}
        >
          <div class="bw-fs-ad-wrap bw-fs-ad-shape-a2">
            <div class="bw-fs-ad-root" id={"bw-fs-a2c-#{@banner.id}"} phx-hook="FsA2CombinedAd" phx-update="ignore">
              <div class="ad adA2 a2-combo">
                <div class="a-head">
                  <span class="fs-mark">
                    <svg class="fs-full" viewBox="0 0 220 28" aria-hidden="true">
                      <defs>
                        <linearGradient id={"a2c-grad-#{@banner.id}"} x1="30" y1="14" x2="220" y2="14" gradientUnits="userSpaceOnUse">
                          <stop offset="0%" stop-color="#22C55E"/>
                          <stop offset="50%" stop-color="#EAB308"/>
                          <stop offset="100%" stop-color="#EF4444"/>
                        </linearGradient>
                      </defs>
                      <rect x="0" y="5" width="18" height="4" rx="2" fill="#22C55E"/>
                      <rect x="0" y="12" width="13" height="4" rx="2" fill="#EAB308"/>
                      <rect x="0" y="19" width="8" height="4" rx="2" fill="#EF4444"/>
                      <text x="28" y="21" font-family="Satoshi,system-ui,sans-serif" font-weight="700" font-size="20" fill={"url(#a2c-grad-#{@banner.id})"}>FATESWAP</text>
                    </svg>
                    <span class="sep"></span>
                    <span class="dex">Solana DEX</span>
                  </span>
                  <span class="bal" data-bal><span class="lbl">Bal</span><span class="val">$50</span></span>
                </div>
                <div class="a-mode">
                  <button class="buy active" type="button">
                    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M7 17l10-10M9 7h8v8" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>
                    Buy
                  </button>
                  <button class="sell" type="button">
                    <svg viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M17 7L7 17M15 17H7v-8" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>
                    Sell
                  </button>
                </div>
                <div class="a-steps">
                  <span class="a-step" data-step="0"></span>
                  <span class="a-step" data-step="1"></span>
                  <span class="a-step" data-step="2"></span>
                  <span class="a-step" data-step="3"></span>
                  <span class="a-step" data-step="4"></span>
                </div>

                <div class="a-body">
                  <div class="a-panels">
                    <div class="a-panel buy-panel" data-panel="0">
                      <p class="panel-title"><span class="num">1</span>Pick a token to buy</p>
                      <div class="t-list">
                        <div class="tok2" data-t="0">
                          <img class="usdc" src="https://assets.coingecko.com/coins/images/6319/standard/usdc.png" alt="USDC"/>
                          <span class="nm">USDC <span class="tk">Stablecoin</span></span>
                          <span class="px"><b>$1.00</b>stable</span>
                        </div>
                        <div class="tok2" data-t="1">
                          <img class="usdc" src="https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/So11111111111111111111111111111111111111112/logo.png" alt="SOL"/>
                          <span class="nm">SOL <span class="tk">Solana</span></span>
                          <span class="px"><b>+2.1%</b>$134.22</span>
                        </div>
                        <div class="tok2" data-t="2">
                          <span class="av-letter usdt">T</span>
                          <span class="nm">USDT <span class="tk">Stablecoin</span></span>
                          <span class="px"><b>$1.00</b>stable</span>
                        </div>
                        <div class="tok2" data-t="3">
                          <span class="av-letter bonk">B</span>
                          <span class="nm">BONK <span class="tk">Memecoin</span></span>
                          <span class="px"><b>+14.2%</b>$0.000034</span>
                        </div>
                      </div>
                    </div>

                    <div class="a-panel buy-panel" data-panel="1">
                      <p class="panel-title"><span class="num">2</span>Set your discount</p>
                      <div class="p2-hdr">
                        <img class="usdc" src="https://assets.coingecko.com/coins/images/6319/standard/usdc.png" alt="USDC"/>
                        <span class="nm">USDC<small>Buying</small></span>
                        <span class="px"><b>$1.00</b>market</span>
                      </div>
                      <div class="p2-line">
                        Buy <b>USDC</b> at
                        <span style="display:block;margin-top:4px"><span class="em" data-pct-a2c-buy>50</span><span style="font-size:18px;font-weight:800;color:#E8E4DD;margin-left:4px">% off</span></span>
                        <span class="lbl">below market price</span>
                      </div>
                      <div class="slider2"><div class="fill"></div><div class="thumb"></div></div>
                      <div class="p2-tiers"><span>1%</span><span>10%</span><span>25%</span><span>50%</span><span>75%</span><span>90%</span></div>
                      <div class="p2-cmp">
                        <div class="b"><p class="lbl">You pay</p><span class="v">$50</span><span class="vsub">0.37 SOL</span></div>
                        <div class="b"><p class="lbl">You get (if filled)</p><span class="v win">$100</span><span class="vsub">of USDC</span></div>
                      </div>
                    </div>

                    <div class="a-panel buy-panel" data-panel="2">
                      <p class="panel-title"><span class="num">3</span>Place your fate order</p>
                      <div class="rev">
                        <div class="buy-line">
                          <img class="usdc usdc-sm" style="width:22px;height:22px" src="https://assets.coingecko.com/coins/images/6319/standard/usdc.png" alt="USDC"/>
                          <span class="nm">Buying USDC</span>
                          <span class="disc">50% off</span>
                        </div>
                        <div class="row"><span class="k">You pay</span><span class="v">$50.00</span></div>
                        <div class="row"><span class="k">You get if filled</span><span class="v win">$100.00 USDC</span></div>
                        <div class="row"><span class="k">Fill chance</span><span class="v">49.25%</span></div>
                        <div class="row"><span class="k">Settle</span><span class="v" style="color:#E8E4DD">~2 sec · On-chain</span></div>
                      </div>
                      <div class="cta2">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M5 13l4 4L19 7" stroke="#0A0A0F" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>
                        Buy USDC at 50% Discount
                      </div>
                    </div>

                    <div class="a-panel buy-panel" data-panel="3">
                      <p class="panel-title"><span class="num">4</span><span class="dot"></span>Revealing fate</p>
                      <div class="reveal">
                        <div class="cnum">
                          <span class="n" data-fate-a2c-buy>00.00</span>
                          <span class="vs">Fill if below <b>49.25</b></span>
                        </div>
                        <div style="flex:1"></div>
                        <div class="bar2">
                          <div class="fill"></div>
                          <div class="unfill"></div>
                          <div class="lbl"><span class="l">FILLED</span><span class="r">NOT FILLED</span></div>
                          <div class="need"></div>
                        </div>
                      </div>
                    </div>

                    <div class="a-panel p5b buy-panel" data-panel="4">
                      <span class="stamp">
                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M5 13l4 4L19 7" stroke="#86EFAC" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>
                        Order Filled
                      </span>
                      <div class="eq">
                        <span class="was">$100</span>
                        <span class="arrow">→</span>
                        <span class="now">$50</span>
                      </div>
                      <div class="receipt">
                        <div class="got">
                          <img class="usdc" src="https://assets.coingecko.com/coins/images/6319/standard/usdc.png" alt="USDC"/>
                          <span class="big">$100</span>
                          <span class="tk">USDC</span>
                        </div>
                        <p class="line">You bought <b>$100 of USDC</b> for <b>$50</b></p>
                        <div class="split">Doubled your money · on-chain</div>
                      </div>
                    </div>

                    <div class="a-panel sell-panel" data-panel="5">
                      <p class="panel-title"><span class="num">1</span>Set your premium</p>
                      <div class="p2-hdr">
                        <img class="usdc" src="https://assets.coingecko.com/coins/images/6319/standard/usdc.png" alt="USDC"/>
                        <span class="nm">USDC<small>Selling</small></span>
                        <span class="px"><b>$1.00</b>market</span>
                      </div>
                      <div class="p2-line">
                        Sell <b>USDC</b> at
                        <span style="display:block;margin-top:4px"><span class="em" data-pct-a2c-sell>100</span><span style="font-size:18px;font-weight:800;color:#E8E4DD;margin-left:4px">% premium</span></span>
                        <span class="lbl">above market price</span>
                      </div>
                      <div class="slider2"><div class="fill"></div><div class="thumb"></div></div>
                      <div class="p2-tiers"><span>1%</span><span>25%</span><span>50%</span><span>100%</span><span>250%</span><span>900%</span></div>
                      <div class="p2-cmp">
                        <div class="b"><p class="lbl">You stake</p><span class="v">$100</span><span class="vsub">of USDC</span></div>
                        <div class="b"><p class="lbl">You get (if filled)</p><span class="v win">$200</span><span class="vsub">paid in SOL</span></div>
                      </div>
                    </div>

                    <div class="a-panel sell-panel" data-panel="6">
                      <p class="panel-title"><span class="num">2</span>Place your fate order</p>
                      <div class="rev">
                        <div class="buy-line">
                          <img class="usdc usdc-sm" style="width:22px;height:22px" src="https://assets.coingecko.com/coins/images/6319/standard/usdc.png" alt="USDC"/>
                          <span class="nm">Selling USDC</span>
                          <span class="disc">100% premium</span>
                        </div>
                        <div class="row"><span class="k">You stake</span><span class="v">$100.00 USDC</span></div>
                        <div class="row"><span class="k">You get if filled</span><span class="v win">$200.00</span></div>
                        <div class="row"><span class="k">Fill chance</span><span class="v">49.25%</span></div>
                        <div class="row"><span class="k">Settle</span><span class="v" style="color:#E8E4DD">~2 sec · On-chain</span></div>
                      </div>
                      <div class="cta2">
                        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M5 13l4 4L19 7" stroke="#0A0A0F" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>
                        Sell USDC at 100% premium
                      </div>
                    </div>

                    <div class="a-panel sell-panel" data-panel="7">
                      <p class="panel-title"><span class="num">3</span><span class="dot"></span>Revealing fate</p>
                      <div class="reveal">
                        <div class="cnum">
                          <span class="n" data-fate-a2c-sell>00.00</span>
                          <span class="vs">Fill if below <b>49.25</b></span>
                        </div>
                        <div style="flex:1"></div>
                        <div class="bar2">
                          <div class="fill"></div>
                          <div class="unfill"></div>
                          <div class="lbl"><span class="l">FILLED</span><span class="r">NOT FILLED</span></div>
                          <div class="need"></div>
                        </div>
                      </div>
                    </div>

                    <div class="a-panel p5b sell-panel" data-panel="8">
                      <span class="stamp">
                        <svg width="12" height="12" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M5 13l4 4L19 7" stroke="#86EFAC" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"/></svg>
                        Order Filled
                      </span>
                      <div class="eq">
                        <span class="was">$100</span>
                        <span class="arrow">→</span>
                        <span class="now">$200</span>
                      </div>
                      <div class="receipt">
                        <div class="got">
                          <img class="usdc" src="https://raw.githubusercontent.com/solana-labs/token-list/main/assets/mainnet/So11111111111111111111111111111111111111112/logo.png" alt="SOL"/>
                          <span class="big">$200</span>
                          <span class="tk">paid out</span>
                        </div>
                        <p class="line">You sold <b>$100 of USDC</b> for <b>$200</b></p>
                        <div class="split">Doubled your money · on-chain</div>
                      </div>
                    </div>
                  </div>
                </div>

                <div class="hand" aria-hidden="true">
                  <svg viewBox="0 0 20 28" xmlns="http://www.w3.org/2000/svg">
                    <path d="M 6 2 C 6 1 7 0 8 0 C 9 0 10 1 10 2 L 10 11 L 11 11 L 11 6 C 11 5 12 4 13 4 C 14 4 15 5 15 6 L 15 11 L 16 11 L 16 8 C 16 7 17 6 18 6 C 19 6 20 7 20 8 L 20 19 C 20 24 16 28 11 28 L 9 28 C 5 28 2 25 1 21 L 0 17 C 0 15 2 14.5 3.5 15.5 L 6 17 Z"
                      fill="#FFFFFF" stroke="#111111" stroke-width="1.2" stroke-linejoin="round" stroke-linecap="round"/>
                  </svg>
                </div>

                <div class="a-foot">
                  <span class="foot-tag">Gamble for a better price than market</span>
                  <span class="foot-cta">Trade Now →</span>
                </div>
              </div>
            </div>
          </div>
        </a>
      </div>
    </div>
    """
  end

  # FateSwap C · Kinetic Hero — 440×640 hero ad with BONK token, "50% OFF"
  # typography, fate dial, and FILLED overlay. Driven by the FsKineticAd JS
  # hook; all CSS scoped under .bw-fs-ad-root.
  def ad_banner(%{banner: %{template: "fateswap_kinetic"}} = assigns) do
    ~H"""
    <div class={["not-prose my-12 flex justify-center", @class]}>
      <div class="w-full" style="max-width: 440px;">
        <div class="text-[9px] tracking-[0.16em] uppercase text-neutral-400 mb-2 font-bold text-center">Sponsored</div>
        <a
          href={@banner.link_url || "#"}
          target="_blank"
          rel="noopener"
          class="block group"
          phx-click="track_ad_click"
          phx-value-id={@banner.id}
        >
          <div class="bw-fs-ad-wrap bw-fs-ad-shape-c">
            <div class="bw-fs-ad-root" id={"bw-fs-c-#{@banner.id}"} phx-hook="FsKineticAd" phx-update="ignore">
              <div class="ad adC">
                <div class="c-glow"></div>
                <div class="c-wrap">
                  <div class="c-head">
                    <span class="fs-mark">
                      <svg class="fs-full" viewBox="0 0 220 28" aria-hidden="true">
                        <defs>
                          <linearGradient id={"c-grad-#{@banner.id}"} x1="30" y1="14" x2="220" y2="14" gradientUnits="userSpaceOnUse">
                            <stop offset="0%" stop-color="#22C55E"/>
                            <stop offset="50%" stop-color="#EAB308"/>
                            <stop offset="100%" stop-color="#EF4444"/>
                          </linearGradient>
                        </defs>
                        <rect x="0" y="5" width="18" height="4" rx="2" fill="#22C55E"/>
                        <rect x="0" y="12" width="13" height="4" rx="2" fill="#EAB308"/>
                        <rect x="0" y="19" width="8" height="4" rx="2" fill="#EF4444"/>
                        <text x="28" y="21" font-family="Satoshi,system-ui,sans-serif" font-weight="700" font-size="20" fill={"url(#c-grad-#{@banner.id})"}>FATESWAP</text>
                      </svg>
                      <span class="sep"></span>
                      <span class="dex">Solana DEX</span>
                    </span>
                  </div>

                  <div class="c-tok">
                    <span class="av">B</span>
                    <span class="nm">BONK</span>
                    <span class="chg">+14.2%</span>
                  </div>

                  <div class="c-hook">Memecoin trading on <b>steroids</b></div>

                  <div class="c-hero">
                    <span data-hero-c>50</span>
                    <span class="pct">% OFF</span>
                  </div>
                  <div class="c-hero-sub">Name your <b>discount</b>. Roll your <b>fate</b>.</div>

                  <div class="c-dial">
                    <div class="c-dial-lbl">
                      <span class="l">Fill &lt; 50.00</span>
                      <span class="r">Miss ≥ 50.00</span>
                    </div>
                    <div class="c-counter">
                      <span class="n" data-fate-c>00.00</span>
                      <span class="s">Your fate vs <b>50.00</b></span>
                    </div>
                    <div class="c-track">
                      <div class="fill"></div>
                      <div class="need"></div>
                    </div>
                  </div>

                  <div class="c-filled">
                    <div class="stamp">
                      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" aria-hidden="true"><path d="M5 13l4 4L19 7" stroke="#86EFAC" stroke-width="3.5" stroke-linecap="round" stroke-linejoin="round"/></svg>
                    </div>
                    <div class="txt">
                      <span class="k">Order Filled</span>
                      <span class="v"><b>+1.00 SOL</b> of BONK</span>
                      <span class="vs">≈ +$134 · paid $67</span>
                    </div>
                  </div>

                  <div class="c-foot">
                    <span class="tag"><span class="dot"></span>Provably fair</span>
                    <span class="cta">Place Fate Order →</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </a>
      </div>
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

        <div class="grid grid-cols-12 gap-4 md:gap-8 items-start">
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

  # Normalizes a BUX reward value (any of nil / int / float / "0.0" / Decimal)
  # into a non-negative integer for display in preview badges.
  defp parse_reward(nil), do: 0
  defp parse_reward(n) when is_integer(n) and n >= 0, do: n
  defp parse_reward(n) when is_integer(n), do: 0
  defp parse_reward(n) when is_float(n) and n >= 0, do: trunc(n)
  defp parse_reward(n) when is_float(n), do: 0
  defp parse_reward(%Decimal{} = d), do: d |> Decimal.to_float() |> parse_reward()

  defp parse_reward(s) when is_binary(s) do
    case Float.parse(s) do
      {n, _} -> parse_reward(n)
      :error -> 0
    end
  end

  defp parse_reward(_), do: 0
end
