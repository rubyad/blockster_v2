defmodule BlocksterV2Web.ShopLive.Landing do
  use BlocksterV2Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Shop - Crypto Infused Streetwear")}
  end
end
