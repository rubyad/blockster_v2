defmodule BlocksterV2Web.PostLive.Redesign.Mosaic do
  @moduledoc """
  Cycling layout #2 — the Trending mosaic.

  Renders up to 14 posts in a 12-col mixed-size mosaic grid. The pattern matches
  `homepage_mock.html` Trending section:

      Row 1: 1 big feature (col-span-7 row-span-2) + 2 medium horizontals (col-span-5 row-span-1)
      Row 2: 4 small cards (col-span-3 each)
      Row 3: 1 medium horizontal (col-span-5) + 1 big feature (col-span-7 row-span-2)
      Row 4: 1 medium horizontal (col-span-5) + 4 small cards (col-span-3)

  Filter chips (DeFi / L2s / AI × Crypto / Stables / RWA / All) are rendered in
  the section header but inert in v1 — wired up in a follow-up commit.
  """

  use BlocksterV2Web, :live_component
  use BlocksterV2Web.DesignSystem

  import BlocksterV2Web.PostLive.Redesign.Shared
  import BlocksterV2Web.SharedComponents, only: [token_badge: 1, earned_badges: 1, video_play_icon: 1]

  alias BlocksterV2.ImageKit

  @impl true
  def render(assigns) do
    {big1, rest} = take_split(assigns.posts, 1)
    {medium1, rest} = take_split(rest, 2)
    {small1, rest} = take_split(rest, 4)
    {medium2, rest} = take_split(rest, 1)
    {big2, rest} = take_split(rest, 1)
    {medium3, rest} = take_split(rest, 1)
    {small2, _rest} = take_split(rest, 4)

    assigns =
      assigns
      |> assign(:big1, List.first(big1))
      |> assign(:medium1, medium1)
      |> assign(:small1, small1)
      |> assign(:medium2, List.first(medium2))
      |> assign(:big2, List.first(big2))
      |> assign(:medium3, List.first(medium3))
      |> assign(:small2, small2)

    ~H"""
    <section class="py-10 border-t border-neutral-200/70">
      <.section_header eyebrow="Most read this week" title="Trending">
        <.chip variant="active">All</.chip>
        <.chip>DeFi</.chip>
        <.chip>L2s</.chip>
        <.chip>AI × Crypto</.chip>
        <.chip>Stables</.chip>
        <.chip>RWA</.chip>
      </.section_header>

      <div class="grid grid-cols-12 gap-4 auto-rows-[180px]">
        <%= if @big1 do %>
          {big_feature(assign(assigns, :post, @big1))}
        <% end %>

        <%= for post <- @medium1 do %>
          {medium_horizontal(assign(assigns, :post, post))}
        <% end %>

        <%= for post <- @small1 do %>
          {small_card(assign(assigns, :post, post))}
        <% end %>

        <%= if @medium2 do %>
          {medium_horizontal(assign(assigns, :post, @medium2))}
        <% end %>

        <%= if @big2 do %>
          {big_feature(assign(assigns, :post, @big2))}
        <% end %>

        <%= if @medium3 do %>
          {medium_horizontal(assign(assigns, :post, @medium3))}
        <% end %>

        <%= for post <- @small2 do %>
          {small_card(assign(assigns, :post, post))}
        <% end %>
      </div>
    </section>
    """
  end

  # ── Big dark feature card ───────────────────────────────────────────────────
  defp big_feature(assigns) do
    ~H"""
    <.link
      navigate={~p"/#{@post.slug}"}
      class="ds-mosaic-big group col-span-12 md:col-span-7 row-span-2 block rounded-2xl overflow-hidden relative bg-neutral-900 transition-transform duration-200 hover:-translate-y-0.5"
    >
      <div class="absolute inset-0">
        <%= if @post.featured_image do %>
          <img
            src={ImageKit.w500_h500(@post.featured_image)}
            alt=""
            class="w-full h-full object-cover group-hover:scale-[1.02] transition-transform duration-700"
            loading="lazy"
          />
        <% else %>
          <img
            src={post_image(@post)}
            alt=""
            class="w-full h-full object-cover group-hover:scale-[1.02] transition-transform duration-700"
            loading="lazy"
          />
        <% end %>
        <%= if @post.video_id do %>
          <.video_play_icon size={:medium} />
        <% end %>
      </div>
      <div class="absolute inset-0 bg-gradient-to-t from-black/85 via-black/40 to-transparent"></div>
      <div class="absolute inset-x-0 bottom-0 p-6">
        <div class="flex items-center gap-2 mb-3">
          <%= if hub_name(@post) do %>
            <div class="w-5 h-5 rounded" style={"background-color: #{hub_color(@post)};"}></div>
            <span class="text-white text-[11px] uppercase tracking-[0.14em] font-bold">{hub_name(@post)}</span>
          <% end %>
          <%= if hub_name(@post) && category_name(@post) do %>
            <span class="text-white/50">·</span>
          <% end %>
          <%= if category_name(@post) do %>
            <span class="text-white/80 text-[11px] uppercase tracking-[0.14em]">{category_name(@post)}</span>
          <% end %>
        </div>
        <h3 class="font-bold tracking-[-0.022em] leading-[1.04] text-white text-[28px] md:text-[32px] mb-3 max-w-[480px] line-clamp-3">
          {@post.title}
        </h3>
        <div class="flex items-center justify-between flex-wrap gap-3">
          <div class="flex items-center gap-2 text-white/80 text-[12px]">
            <div class="w-7 h-7 rounded-full bg-white/20 backdrop-blur grid place-items-center text-[10px] font-bold text-white">
              {author_initials(@post)}
            </div>
            <span>{author_name(@post)} · {read_minutes(@post)} min</span>
          </div>
          <div class="flex justify-center">
            <%= if has_earned_reward?(assigns, @post) do %>
              <.earned_badges reward={user_reward(assigns, @post)} id={"mosaic-big-earned-#{@post.id}"} />
            <% else %>
              <.token_badge post={@post} balance={bux_balance(assigns, @post)} id={"mosaic-big-bux-#{@post.id}"} />
            <% end %>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  # ── Medium horizontal split card ────────────────────────────────────────────
  defp medium_horizontal(assigns) do
    ~H"""
    <.link
      navigate={~p"/#{@post.slug}"}
      class="ds-mosaic-medium group col-span-12 md:col-span-5 row-span-1 block bg-white rounded-2xl border border-neutral-200/70 overflow-hidden transition-all duration-200 hover:-translate-y-0.5 hover:shadow-lg hover:border-neutral-300"
    >
      <div class="flex h-full">
        <div class="w-2/5 bg-neutral-100 overflow-hidden relative">
          <%= if @post.featured_image do %>
            <img
              src={ImageKit.w500_h500(@post.featured_image)}
              alt=""
              class="w-full h-full object-cover"
              loading="lazy"
            />
          <% else %>
            <img
              src={post_image(@post)}
              alt=""
              class="w-full h-full object-cover"
              loading="lazy"
            />
          <% end %>
          <%= if @post.video_id do %>
            <.video_play_icon size={:medium} />
          <% end %>
        </div>
        <div class="flex-1 p-4 flex flex-col">
          <div class="flex items-center gap-1.5 mb-2">
            <%= if hub_name(@post) do %>
              <div class="w-3.5 h-3.5 rounded" style={"background-color: #{hub_color(@post)};"}></div>
              <span class="text-[9px] uppercase tracking-[0.12em] text-neutral-500">{hub_name(@post)}</span>
            <% end %>
            <%= if hub_name(@post) && category_name(@post) do %>
              <span class="text-neutral-300">·</span>
            <% end %>
            <%= if category_name(@post) do %>
              <span class="text-[9px] uppercase tracking-[0.12em] text-neutral-500">{category_name(@post)}</span>
            <% end %>
          </div>
          <h3 class="font-bold text-[14px] text-[#141414] leading-[1.25] line-clamp-2 tracking-tight mb-auto">
            {@post.title}
          </h3>
          <div class="flex items-center justify-between text-[10px] mt-2">
            <span class="text-neutral-500">{read_minutes(@post)} min</span>
            <div class="flex justify-center">
              <%= if has_earned_reward?(assigns, @post) do %>
                <.earned_badges reward={user_reward(assigns, @post)} id={"mosaic-med-earned-#{@post.id}"} />
              <% else %>
                <.token_badge post={@post} balance={bux_balance(assigns, @post)} id={"mosaic-med-bux-#{@post.id}"} />
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  # ── Small image-on-top card ─────────────────────────────────────────────────
  defp small_card(assigns) do
    ~H"""
    <.link
      navigate={~p"/#{@post.slug}"}
      class="ds-mosaic-small group col-span-6 md:col-span-3 row-span-1 block bg-white rounded-2xl border border-neutral-200/70 overflow-hidden flex flex-col transition-all duration-200 hover:-translate-y-0.5 hover:shadow-lg hover:border-neutral-300"
    >
      <div class="aspect-[16/9] bg-neutral-100 overflow-hidden relative">
        <%= if @post.featured_image do %>
          <img
            src={ImageKit.w500_h500(@post.featured_image)}
            alt=""
            class="w-full h-full object-cover"
            loading="lazy"
          />
        <% else %>
          <img
            src={post_image(@post)}
            alt=""
            class="w-full h-full object-cover"
            loading="lazy"
          />
        <% end %>
      </div>
      <div class="p-3 flex flex-col flex-1">
        <div class="flex items-center gap-1.5 mb-1.5">
          <%= if hub_name(@post) do %>
            <div class="w-3 h-3 rounded" style={"background-color: #{hub_color(@post)};"}></div>
            <span class="text-[9px] uppercase tracking-[0.12em] text-neutral-500">{hub_name(@post)}</span>
          <% end %>
          <%= if hub_name(@post) && category_name(@post) do %>
            <span class="text-neutral-300">·</span>
          <% end %>
          <%= if category_name(@post) do %>
            <span class="text-[9px] uppercase tracking-[0.12em] text-neutral-500">{category_name(@post)}</span>
          <% end %>
        </div>
        <h3 class="font-bold text-[12px] text-[#141414] leading-[1.25] line-clamp-2 tracking-tight mb-auto">
          {@post.title}
        </h3>
        <div class="flex items-center justify-between text-[9px] mt-2">
          <span class="text-neutral-500">{read_minutes(@post)} min</span>
          <div class="flex justify-center">
            <%= if has_earned_reward?(assigns, @post) do %>
              <.earned_badges reward={user_reward(assigns, @post)} id={"mosaic-sm-earned-#{@post.id}"} />
            <% else %>
              <.token_badge post={@post} balance={bux_balance(assigns, @post)} id={"mosaic-sm-bux-#{@post.id}"} />
            <% end %>
          </div>
        </div>
      </div>
    </.link>
    """
  end

  defp take_split(list, n) do
    {Enum.take(list, n), Enum.drop(list, n)}
  end
end
