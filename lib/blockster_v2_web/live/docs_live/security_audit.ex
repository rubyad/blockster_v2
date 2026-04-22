defmodule BlocksterV2Web.DocsLive.SecurityAudit do
  use BlocksterV2Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Security Audit - Blockster Docs")}
  end
end
