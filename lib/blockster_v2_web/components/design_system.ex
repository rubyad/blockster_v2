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
        "ds-logo inline-flex items-center whitespace-nowrap leading-none uppercase",
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
  # The new sticky site header. Hybrid of the mock visual (logo + Solana mainnet
  # pulse + center nav + lime banner) and the production functional features that
  # need to keep working (search trigger, notification bell + dropdown, cart icon
  # with count, user dropdown with admin links, mobile responsive layout).
  #
  # Two variants:
  #   logged_in  → BUX pill, cart, notifications, search, user dropdown
  #   anonymous  → Connect Wallet button only
  #
  # The center nav highlights the active route via `active` attr.

  @doc """
  Renders the redesigned site header. Pass `current_user: nil` for the anonymous
  variant, otherwise the logged-in variant is rendered.

      <.header current_user={@current_user} active="home" bux_balance={@bux_balance} />
  """
  attr :current_user, :any, default: nil
  attr :active, :string, default: nil, doc: "active nav slug: home|hubs|shop|play|pool|airdrop"
  attr :bux_balance, :any, default: 0
  attr :cart_item_count, :integer, default: 0
  attr :unread_notification_count, :integer, default: 0
  attr :show_why_earn_bux, :boolean, default: true

  def header(assigns) do
    assigns =
      assigns
      |> assign(:formatted_bux, format_bux(assigns.bux_balance))
      |> assign(:initials, user_initials(assigns.current_user))

    ~H"""
    <header
      id="ds-site-header"
      class="ds-header bg-white/[0.92] backdrop-blur-md border-b border-neutral-200/70 sticky top-0 z-30"
    >
      <div class="max-w-[1280px] mx-auto px-6 h-14 flex items-center justify-between gap-6">
        <%!-- Left: logo + Solana mainnet pulse --%>
        <div class="flex items-center gap-3 min-w-0">
          <.link navigate={~p"/"} class="flex items-center" aria-label="Blockster home">
            <.logo size="22px" />
          </.link>
          <div class="hidden md:flex items-center ml-2 gap-1.5 text-[11px] text-neutral-500 font-mono">
            <span class="w-1.5 h-1.5 rounded-full bg-[#22C55E]"></span>
            <span>Solana mainnet</span>
          </div>
        </div>

        <%!-- Center: nav --%>
        <nav class="hidden md:flex items-center gap-7 text-[13px] text-neutral-700">
          <.header_nav_link href={~p"/"} active={@active == "home"}>Home</.header_nav_link>
          <.header_nav_link href={~p"/hubs"} active={@active == "hubs"}>Hubs</.header_nav_link>
          <.header_nav_link href={~p"/shop"} active={@active == "shop"}>Shop</.header_nav_link>
          <.header_nav_link href={~p"/play"} active={@active == "play"}>Play</.header_nav_link>
          <.header_nav_link href={~p"/pool"} active={@active == "pool"}>Pool</.header_nav_link>
          <.header_nav_link href={~p"/airdrop"} active={@active == "airdrop"}>Airdrop</.header_nav_link>
        </nav>

        <%!-- Right --%>
        <div class="flex items-center gap-2">
          <%= if @current_user do %>
            <%!-- Search icon (opens overlay; preserves search_posts handler) --%>
            <button
              type="button"
              phx-click={JS.dispatch("ds:open-search")}
              class="hidden sm:flex w-9 h-9 items-center justify-center rounded-full bg-neutral-100 hover:bg-neutral-200 transition-colors"
              aria-label="Search"
            >
              <svg class="w-4 h-4 text-[#141414]" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
                <circle cx="11" cy="11" r="7"></circle>
                <path d="m21 21-4.3-4.3"></path>
              </svg>
            </button>

            <%!-- Notifications bell --%>
            <button
              type="button"
              phx-click="toggle_notification_dropdown"
              class="relative w-9 h-9 flex items-center justify-center rounded-full bg-neutral-100 hover:bg-neutral-200 transition-colors"
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

            <%!-- BUX pill --%>
            <div class="hidden sm:flex items-center gap-1.5 px-2.5 py-1.5 bg-neutral-100 border border-neutral-200/60 rounded-full">
              <img
                src="https://ik.imagekit.io/blockster/blockster-icon.png"
                alt="BUX"
                class="w-4 h-4 rounded-full object-cover"
              />
              <span class="text-[12px] font-bold text-neutral-800 font-mono tabular-nums">{@formatted_bux}</span>
              <span class="text-[10px] text-neutral-500">BUX</span>
            </div>

            <%!-- User avatar (dropdown trigger) --%>
            <button
              type="button"
              id="ds-header-user"
              phx-click={JS.toggle(to: "#ds-header-user-menu")}
              class="rounded-full"
              aria-label="Your account"
            >
              <.profile_avatar initials={@initials} size="sm" ring />
            </button>
          <% else %>
            <%!-- Anonymous: Connect Wallet --%>
            <button
              type="button"
              phx-click="show_wallet_selector"
              class="hidden sm:inline-flex items-center gap-2 bg-[#0a0a0a] text-white px-4 py-2 rounded-full text-[12px] font-bold hover:bg-[#1a1a22] transition-colors"
            >
              <svg class="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round">
                <rect x="2" y="6" width="20" height="14" rx="2"/>
                <path d="M22 10h-4a2 2 0 100 4h4"/>
              </svg>
              Connect Wallet
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

  defp format_bux(nil), do: "0"
  defp format_bux(n) when is_integer(n), do: Number.Delimit.number_to_delimited(n, precision: 0)

  defp format_bux(n) when is_float(n) or is_struct(n, Decimal),
    do: Number.Delimit.number_to_delimited(n, precision: 0)

  defp format_bux(_), do: "0"

  defp user_initials(nil), do: "??"

  defp user_initials(%{} = user) do
    cond do
      is_binary(Map.get(user, :display_name)) and Map.get(user, :display_name) != "" ->
        initials_from_string(user.display_name)

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
end
