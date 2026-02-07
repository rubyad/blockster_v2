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
    banner_url = Map.get(assigns, :banner_url) || @default_banner
    banner_url = imagekit_url(banner_url)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:banner_url, banner_url)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="w-full relative overflow-hidden">
      <%!-- Desktop Banner --%>
      <div class="hidden md:block w-full h-[600px] overflow-hidden">
        <img
          src={@banner_url}
          alt="Banner"
          class="w-full h-full object-cover"
          style="object-position: 50% 50%;"
        />
      </div>

      <%!-- Mobile Banner --%>
      <div class="md:hidden w-full h-[280px] overflow-hidden">
        <img
          src={@banner_url}
          alt="Banner"
          class="w-full h-full object-cover"
          style="object-position: 50% 50%;"
        />
      </div>

      <%!-- Text Overlay - Responsive --%>
      <%= if assigns[:overlay_text] do %>
        <div class="absolute inset-0 flex items-center justify-center p-4">
          <div class="bg-black/50 rounded-xl p-4 md:p-6 max-w-[90%] md:max-w-md text-center">
            <h2 class="text-white font-bold text-xl md:text-4xl leading-tight">
              <%= @overlay_text %>
            </h2>
          </div>
        </div>
      <% end %>

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

  defp imagekit_url(url) do
    if url && String.contains?(url, "ik.imagekit.io") do
      "#{url}?tr=w-1920,q-90"
    else
      url
    end
  end
end
