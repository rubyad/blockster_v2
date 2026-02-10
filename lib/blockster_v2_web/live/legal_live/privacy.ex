defmodule BlocksterV2Web.LegalLive.Privacy do
  use BlocksterV2Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Privacy Policy - Blockster")}
  end
end
