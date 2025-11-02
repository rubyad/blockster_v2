defmodule BlocksterV2Web.HubLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Blog

  @impl true
  def mount(_params, _session, socket) do
    hubs = Blog.list_hubs()

    {:ok,
     socket
     |> assign(:hubs, hubs)
     |> assign(:page_title, "Business Hubs")}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end
end
