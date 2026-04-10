defmodule BlocksterV2Web.PostLive.Redesign.VideoLayout do
  @moduledoc """
  Cycling layout #3 — the Watch grid.

  Renders 1 big featured video + 2 medium videos + 4 small videos. The parent
  LiveView only inserts this layout into the cycle when there are at least 7
  unconsumed video posts (`Blog.list_published_videos/1` returned >= 7). When
  fewer videos remain, this layout is skipped from that cycle and never re-runs
  in subsequent cycles.
  """

  use BlocksterV2Web, :live_component
  use BlocksterV2Web.DesignSystem

  import BlocksterV2Web.PostLive.Redesign.Shared
  import BlocksterV2Web.SharedComponents, only: [token_badge: 1, earned_badges: 1]

  alias BlocksterV2.ImageKit

  @impl true
  def render(assigns) do
    [big | rest] = assigns.posts ++ List.duplicate(nil, 7)
    {medium, rest} = Enum.split(rest, 2)
    {small, _} = Enum.split(rest, 4)

    assigns =
      assigns
      |> assign(:big, big)
      |> assign(:medium, Enum.reject(medium, &is_nil/1))
      |> assign(:small, Enum.reject(small, &is_nil/1))

    ~H"""
    <section class="py-10 border-t border-neutral-200/70">
      <.section_header eyebrow="Visual stories from the chain" title="Watch">
        <:see_all href={~p"/"}>All videos</:see_all>
      </.section_header>

      <div class="grid grid-cols-12 gap-4">
        <%= if @big do %>
          {big_video(assign(assigns, :post, @big))}
        <% end %>

        <div class="col-span-12 md:col-span-5 grid grid-rows-2 gap-4">
          <%= for post <- @medium do %>
            {medium_video(assign(assigns, :post, post))}
          <% end %>
        </div>

        <%= for post <- @small do %>
          {small_video(assign(assigns, :post, post))}
        <% end %>
      </div>
    </section>
    """
  end

  defp big_video(assigns) do
    ~H"""
    <.link
      navigate={~p"/#{@post.slug}"}
      class="ds-video-big group col-span-12 md:col-span-7 block rounded-2xl overflow-hidden relative bg-neutral-900"
    >
      <div class="aspect-[16/9] overflow-hidden">
        <%= if @post.featured_image do %>
          <img src={ImageKit.w500_h500(@post.featured_image)} alt="" class="w-full h-full object-cover" loading="lazy" />
        <% else %>
          <img src={post_image(@post)} alt="" class="w-full h-full object-cover" loading="lazy" />
        <% end %>
      </div>
      <div class="absolute inset-0 grid place-items-center pointer-events-none">
        <div class="w-20 h-20 rounded-full bg-white/95 backdrop-blur grid place-items-center shadow-2xl group-hover:scale-110 transition-transform">
          <svg class="w-8 h-8 text-[#0a0a0a] ml-1" viewBox="0 0 24 24" fill="currentColor">
            <path d="M8 5v14l11-7z" />
          </svg>
        </div>
      </div>
      <%= if duration = video_duration(@post) do %>
        <div class="absolute top-4 right-4 bg-black/85 backdrop-blur px-2.5 py-1 rounded text-white text-[11px] font-mono font-semibold tabular-nums">
          {duration}
        </div>
      <% end %>
      <div class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/95 via-black/60 to-transparent p-6 pt-12">
        <%= if hub_name(@post) do %>
          <div class="flex items-center gap-2 mb-3">
            <div class="w-5 h-5 rounded" style={"background-color: #{hub_color(@post)};"}></div>
            <span class="text-white text-[11px] uppercase tracking-[0.14em] font-bold">{hub_name(@post)}</span>
          </div>
        <% end %>
        <h3 class="font-bold tracking-[-0.022em] leading-[1.04] text-white text-[26px] md:text-[28px] mb-3 max-w-[480px] line-clamp-3">
          {@post.title}
        </h3>
        <div class="flex items-center justify-between flex-wrap gap-3">
          <div class="flex items-center gap-2 text-white/80 text-[12px]">
            <div class="w-7 h-7 rounded-full bg-white/20 backdrop-blur grid place-items-center text-[10px] font-bold text-white">
              {author_initials(@post)}
            </div>
            <span>{author_name(@post)}</span>
          </div>
          <%= if has_earned_reward?(assigns, @post) do %>
            <.earned_badges reward={user_reward(assigns, @post)} id={"video-big-earned-#{@post.id}"} />
          <% else %>
            <.token_badge post={@post} balance={bux_balance(assigns, @post)} id={"video-big-bux-#{@post.id}"} />
          <% end %>
        </div>
      </div>
    </.link>
    """
  end

  defp medium_video(assigns) do
    ~H"""
    <.link
      navigate={~p"/#{@post.slug}"}
      class="ds-video-medium group block rounded-2xl overflow-hidden relative bg-neutral-900"
    >
      <div class="aspect-[16/9] overflow-hidden">
        <%= if @post.featured_image do %>
          <img src={ImageKit.w500_h500(@post.featured_image)} alt="" class="w-full h-full object-cover" loading="lazy" />
        <% else %>
          <img src={post_image(@post)} alt="" class="w-full h-full object-cover" loading="lazy" />
        <% end %>
      </div>
      <div class="absolute inset-0 grid place-items-center pointer-events-none">
        <div class="w-12 h-12 rounded-full bg-white/95 backdrop-blur grid place-items-center shadow-xl group-hover:scale-110 transition-transform">
          <svg class="w-5 h-5 text-[#0a0a0a] ml-0.5" viewBox="0 0 24 24" fill="currentColor">
            <path d="M8 5v14l11-7z" />
          </svg>
        </div>
      </div>
      <%= if duration = video_duration(@post) do %>
        <div class="absolute top-3 right-3 bg-black/85 backdrop-blur px-2 py-0.5 rounded text-white text-[10px] font-mono font-semibold tabular-nums">
          {duration}
        </div>
      <% end %>
      <div class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/90 via-black/40 to-transparent p-4 pt-8">
        <%= if hub_name(@post) do %>
          <div class="flex items-center gap-1.5 mb-1.5">
            <div class="w-3.5 h-3.5 rounded" style={"background-color: #{hub_color(@post)};"}></div>
            <span class="text-white/90 text-[9px] uppercase tracking-[0.12em] font-bold">{hub_name(@post)}</span>
          </div>
        <% end %>
        <h3 class="font-bold text-white text-[14px] leading-[1.2] line-clamp-2 tracking-tight">
          {@post.title}
        </h3>
      </div>
    </.link>
    """
  end

  defp small_video(assigns) do
    ~H"""
    <.link
      navigate={~p"/#{@post.slug}"}
      class="ds-video-small group col-span-6 md:col-span-3 block rounded-2xl overflow-hidden relative bg-neutral-900"
    >
      <div class="aspect-[16/9] overflow-hidden">
        <%= if @post.featured_image do %>
          <img src={ImageKit.w500_h500(@post.featured_image)} alt="" class="w-full h-full object-cover" loading="lazy" />
        <% else %>
          <img src={post_image(@post)} alt="" class="w-full h-full object-cover" loading="lazy" />
        <% end %>
      </div>
      <div class="absolute inset-0 grid place-items-center pointer-events-none">
        <div class="w-10 h-10 rounded-full bg-white/95 backdrop-blur grid place-items-center shadow-lg group-hover:scale-110 transition-transform">
          <svg class="w-4 h-4 text-[#0a0a0a] ml-0.5" viewBox="0 0 24 24" fill="currentColor">
            <path d="M8 5v14l11-7z" />
          </svg>
        </div>
      </div>
      <%= if duration = video_duration(@post) do %>
        <div class="absolute top-2 right-2 bg-black/85 backdrop-blur px-1.5 py-0.5 rounded text-white text-[9px] font-mono font-semibold tabular-nums">
          {duration}
        </div>
      <% end %>
      <div class="absolute inset-x-0 bottom-0 bg-gradient-to-t from-black/95 to-transparent p-3 pt-6">
        <%= if hub_name(@post) do %>
          <div class="flex items-center gap-1 mb-1">
            <div class="w-2.5 h-2.5 rounded" style={"background-color: #{hub_color(@post)};"}></div>
            <span class="text-white/90 text-[8px] uppercase tracking-[0.12em] font-bold">{hub_name(@post)}</span>
          </div>
        <% end %>
        <h3 class="font-bold text-white text-[12px] leading-[1.2] line-clamp-2 tracking-tight">
          {@post.title}
        </h3>
      </div>
    </.link>
    """
  end
end
