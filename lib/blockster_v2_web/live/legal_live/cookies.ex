defmodule BlocksterV2Web.LegalLive.Cookies do
  use BlocksterV2Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Cookie Policy - Blockster")}
  end
end
