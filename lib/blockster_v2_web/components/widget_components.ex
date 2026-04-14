defmodule BlocksterV2Web.WidgetComponents do
  @moduledoc """
  Dispatcher from an ad_banner row to either the existing image-based ad
  renderer (when `widget_type` is nil) or a real-time widget component
  (when `widget_type` matches one of the 14 shipped widgets).

  Phase 2b ships only the nil-fallback path plus an explicit raise for
  every known `widget_type` — individual widget components land in Phase
  3 and beyond. Raising beats a silent blank slot while the backend is
  flag-gated to `WIDGETS_ENABLED=false`.

  Plan: docs/solana/realtime_widgets_plan.md · §F "Widget components".
  """

  use Phoenix.Component

  alias BlocksterV2.Ads.Banner

  @known_widget_types Banner.valid_widget_types()

  attr :banner, :map, required: true
  attr :class, :string, default: nil
  attr :rest, :global

  def widget_or_ad(%{banner: %{widget_type: nil}} = assigns) do
    ~H"""
    <BlocksterV2Web.DesignSystem.ad_banner banner={@banner} class={@class} />
    """
  end

  def widget_or_ad(%{banner: %{widget_type: type}} = assigns)
      when type in @known_widget_types do
    raise ArgumentError,
          "widget component not yet implemented (Phase 3+): #{type}. " <>
            "Banner id=#{inspect(assigns.banner.id)} placement=#{inspect(assigns.banner.placement)}."
  end

  def widget_or_ad(%{banner: %{widget_type: type}}) do
    raise ArgumentError,
          "unknown widget_type: #{inspect(type)}. " <>
            "Expected nil or one of: #{Enum.join(@known_widget_types, ", ")}."
  end
end
