defmodule BlocksterV2Web.DocsLive.Index do
  use BlocksterV2Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Documentation - Blockster")}
  end
end
