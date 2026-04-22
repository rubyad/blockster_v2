defmodule BlocksterV2Web.DocsLive.Pools do
  use BlocksterV2Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Pools & LP - Blockster Docs")}
  end
end
