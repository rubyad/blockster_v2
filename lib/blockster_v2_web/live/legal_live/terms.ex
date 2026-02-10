defmodule BlocksterV2Web.LegalLive.Terms do
  use BlocksterV2Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Terms of Service - Blockster")}
  end
end
