defmodule BlocksterV2Web.PostLive.Redesign.ThreeColumn do
  @moduledoc """
  Cycling layout #1 — 3 posts in a 3-col grid.
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
      <.section_header eyebrow="Where the chain meets the model" title="AI × Crypto">
        <:see_all href={~p"/category/ai"}>See all</:see_all>
      </.section_header>

      <div class="grid grid-cols-1 md:grid-cols-3 gap-4">
        <%= for {post, idx} <- Enum.with_index(@posts) do %>
          <.link navigate={~p"/#{post.slug}"} class="ds-post-card group block bg-white rounded-2xl border border-neutral-200/70 overflow-hidden transition-all duration-200 hover:-translate-y-0.5 hover:shadow-lg hover:border-neutral-300">
            <div class="aspect-[16/9] bg-neutral-100 overflow-hidden relative">
              <%= if post.featured_image do %>
                <img src={ImageKit.w500_h500(post.featured_image)} alt="" class="w-full h-full object-cover group-hover:scale-[1.02] transition-transform duration-500" loading="lazy" />
              <% else %>
                <div class="w-full h-full bg-gradient-to-br from-neutral-200 to-neutral-100"></div>
              <% end %>
              <%= if post.video_id do %>
                <.video_play_icon size={:medium} />
              <% end %>
            </div>
            <div class="p-4">
              <div class="flex items-center gap-1.5 mb-2">
                <%= if hub_name(post) do %>
                  <div class="w-4 h-4 rounded" style={"background-color: #{hub_color(post)};"}></div>
                  <span class="text-[9px] uppercase tracking-[0.12em] text-neutral-500">{hub_name(post)}</span>
                <% end %>
                <%= if hub_name(post) && category_name(post) do %>
                  <span class="text-neutral-300">·</span>
                <% end %>
                <%= if category_name(post) do %>
                  <span class="text-[9px] uppercase tracking-[0.12em] text-neutral-500">{category_name(post)}</span>
                <% end %>
              </div>
              <h3 class="font-bold text-[15px] text-[#141414] leading-[1.25] mb-3 line-clamp-3 tracking-tight">
                {post.title}
              </h3>
              <div class="flex items-center justify-between text-[10px]">
                <div class="flex items-center gap-1.5 text-neutral-500">
                  <span>{author_name(post)}</span>
                  <span class="text-neutral-300">·</span>
                  <span>{read_minutes(post)} min</span>
                </div>
                <div class="flex justify-center">
                  <%= if has_earned_reward?(assigns, post) do %>
                    <.earned_badges reward={user_reward(assigns, post)} id={"redesign-three-earned-#{post.id}-#{idx}"} />
                  <% else %>
                    <.token_badge post={post} balance={bux_balance(assigns, post)} id={"redesign-three-bux-#{post.id}-#{idx}"} />
                  <% end %>
                </div>
              </div>
            </div>
          </.link>
        <% end %>
      </div>
    </section>
    """
  end
end
