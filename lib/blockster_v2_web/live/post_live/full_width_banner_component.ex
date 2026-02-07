defmodule BlocksterV2Web.PostLive.FullWidthBannerComponent do
  use BlocksterV2Web, :live_component

  @default_banner "https://ik.imagekit.io/blockster/hero.png"

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    # Set default banner URL if not provided
    base_url = Map.get(assigns, :banner_url) || @default_banner

    # Create separate URLs for desktop and mobile with different transformations
    desktop_url = imagekit_url(base_url, "w-1920,q-90")
    mobile_url = imagekit_url(base_url, "w-800,q-85")

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:desktop_banner_url, desktop_url)
     |> assign(:mobile_banner_url, mobile_url)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-full relative">
      <%!-- Desktop Banner --%>
      <div class="hidden md:block w-full h-[600px] overflow-hidden relative">
        <img
          src={@desktop_banner_url}
          alt="Banner"
          class="w-full h-full object-cover"
          style="object-position: 50% 50%;"
        />
        <%!-- Text Overlay - Desktop (one line, near bottom) --%>
        <%= if assigns[:overlay_text] do %>
          <div class="absolute inset-x-0 bottom-16 flex justify-center px-4">
            <div class="bg-black/50 rounded-xl px-8 py-4 text-center">
              <h2 class="text-white font-bold text-3xl whitespace-nowrap">
                <%= @overlay_text %>
              </h2>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Mobile Banner --%>
      <div class="md:hidden w-full h-[280px] overflow-hidden relative">
        <img
          src={@mobile_banner_url}
          alt="Banner"
          class="w-full h-full object-cover"
          style="object-position: 50% 50%;"
        />
        <%!-- Text Overlay - Mobile (wraps to 2 lines, near bottom) --%>
        <%= if assigns[:overlay_text] do %>
          <div class="absolute inset-x-0 bottom-8 flex justify-center px-4">
            <div class="bg-black/50 rounded-xl px-4 py-3 text-center max-w-[85%]">
              <h2 class="text-white font-bold text-base leading-tight">
                <%= @overlay_text %>
              </h2>
            </div>
          </div>
        <% end %>
      </div>

      <%!-- Button --%>
      <%= if assigns[:button_text] && assigns[:button_url] do %>
        <a
          href={@button_url}
          class="absolute left-1/2 -translate-x-1/2 bottom-8 md:bottom-16 bg-white text-black font-semibold rounded-full px-6 py-2 md:px-8 md:py-3 text-sm md:text-base hover:bg-gray-100 transition-colors cursor-pointer"
        >
          <%= @button_text %>
        </a>
      <% end %>
    </section>
    """
  end

  defp imagekit_url(url, transforms) do
    if url && String.contains?(url, "ik.imagekit.io") do
      "#{url}?tr=#{transforms}"
    else
      url
    end
  end
end
