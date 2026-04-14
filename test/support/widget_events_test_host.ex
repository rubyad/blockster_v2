defmodule BlocksterV2Web.WidgetEventsTestHost do
  @moduledoc """
  Minimal host LiveView that uses `BlocksterV2Web.WidgetEvents` so the
  macro's generated callbacks can be exercised via `live_isolated/3`.

  Pulls the list of active widget banners from `Ads.list_widget_banners/0`
  at mount time so tests can control inputs by inserting banners into the
  DB before starting the LiveView.
  """

  use Phoenix.LiveView

  use BlocksterV2Web.WidgetEvents

  @impl true
  def mount(_params, _session, socket) do
    banners = BlocksterV2.Ads.list_widget_banners()
    {:ok, mount_widgets(assign(socket, :banners, banners), banners)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="widget-events-test-host">
      <div :for={b <- @banners} data-banner-id={b.id}>{b.name}</div>
    </div>
    """
  end
end
