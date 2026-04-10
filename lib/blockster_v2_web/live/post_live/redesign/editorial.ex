defmodule BlocksterV2Web.PostLive.Redesign.Editorial do
  @moduledoc """
  Cycling layout #4 — the From the editors grid.

  Renders 4 posts as large editorial cards in a 2x2 grid. Each card has the
  full image + hub badge + 24px article title + 2-line excerpt + author byline
  + lime BUX reward pill. Larger and more breathing-room than the regular
  `<.post_card />` used by the AI × Crypto layout.
  """

  use BlocksterV2Web, :live_component
  use BlocksterV2Web.DesignSystem

  import BlocksterV2Web.PostLive.Redesign.Shared
  import BlocksterV2Web.SharedComponents, only: [token_badge: 1, earned_badges: 1, video_play_icon: 1]

  alias BlocksterV2.ImageKit

  @impl true
  def render(assigns) do
    ~H"""
    <section class="py-10 border-t border-neutral-200/70">
      <.section_header eyebrow="Hand-picked by Blockster editors" title="From the editors">
        <:see_all href={~p"/"}>All editorial picks</:see_all>
      </.section_header>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
        <%= for post <- @posts do %>
          <.link
            navigate={~p"/#{post.slug}"}
            class="ds-editorial-card group block bg-white rounded-2xl border border-neutral-200/70 overflow-hidden transition-all duration-200 hover:-translate-y-0.5 hover:shadow-lg hover:border-neutral-300"
          >
            <div class="aspect-[16/9] bg-neutral-100 overflow-hidden relative">
              <%= if post.featured_image do %>
                <img src={ImageKit.w500_h500(post.featured_image)} alt="" class="w-full h-full object-cover group-hover:scale-[1.02] transition-transform duration-700" loading="lazy" />
              <% else %>
                <img src={post_image(post)} alt="" class="w-full h-full object-cover" loading="lazy" />
              <% end %>
              <%= if post.video_id do %>
                <.video_play_icon size={:medium} />
              <% end %>
            </div>
            <div class="p-6">
              <div class="flex items-center gap-2 mb-3">
                <%= if hub_name(post) do %>
                  <div class="w-4 h-4 rounded" style={"background-color: #{hub_color(post)};"}></div>
                  <span class="text-[10px] uppercase tracking-[0.14em] text-neutral-500">{hub_name(post)}</span>
                <% end %>
                <%= if hub_name(post) && category_name(post) do %>
                  <span class="text-neutral-300">·</span>
                <% end %>
                <%= if category_name(post) do %>
                  <span class="text-[10px] uppercase tracking-[0.14em] text-neutral-500">{category_name(post)}</span>
                <% end %>
              </div>
              <h3 class="font-bold tracking-[-0.022em] leading-[1.15] text-[#141414] text-[24px] mb-3 line-clamp-3">
                {post.title}
              </h3>
              <%= if post.excerpt do %>
                <p class="text-neutral-600 text-[14px] leading-snug mb-4 line-clamp-2">
                  {short_excerpt(post.excerpt, 220)}
                </p>
              <% end %>
              <div class="flex items-center justify-between">
                <div class="flex items-center gap-2">
                  <.author_avatar initials={author_initials(post)} size="sm" />
                  <div class="text-[11px] text-neutral-500">
                    {author_name(post)} · {read_minutes(post)} min
                  </div>
                </div>
                <%= if has_earned_reward?(assigns, post) do %>
                  <.earned_badges reward={user_reward(assigns, post)} id={"editorial-earned-#{post.id}"} />
                <% else %>
                  <.token_badge post={post} balance={bux_balance(assigns, post)} id={"editorial-bux-#{post.id}"} />
                <% end %>
              </div>
            </div>
          </.link>
        <% end %>
      </div>
    </section>
    """
  end
end
