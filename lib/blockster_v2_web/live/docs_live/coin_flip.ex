defmodule BlocksterV2Web.DocsLive.CoinFlip do
  use BlocksterV2Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Coin Flip - Blockster Docs")}
  end
end
