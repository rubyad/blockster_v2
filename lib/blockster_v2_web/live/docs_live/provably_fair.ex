defmodule BlocksterV2Web.DocsLive.ProvablyFair do
  use BlocksterV2Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Provably Fair - Blockster Docs")}
  end
end
