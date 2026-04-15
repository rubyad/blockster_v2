defmodule BlocksterV2Web.Widgets.WidgetShared do
  @moduledoc """
  Shared presentational primitives for the Phase 6 widget polish pass:

    * `skeleton_bar/1` — shimmering placeholder bar sized by caller
    * `skeleton_circle/1` — circular shimmer for avatars / logos
    * `tracker_error_placeholder/1` — subtle "data temporarily
      unavailable" placeholder used when a poller's `last_error` is
      non-nil AND it has no cached data to fall back on

  Every widget's empty-state branch consumes one of these instead of
  raw text copy. The shimmer CSS keyframes live in `assets/css/widgets.css`
  under `@keyframes bw-skeleton-shimmer`.
  """

  use Phoenix.Component

  attr :class, :string, default: nil
  attr :rest, :global

  def skeleton_bar(assigns) do
    ~H"""
    <span class={["bw-skeleton", @class]} {@rest}></span>
    """
  end

  attr :class, :string, default: nil
  attr :rest, :global

  def skeleton_circle(assigns) do
    ~H"""
    <span class={["bw-skeleton bw-skeleton-circle", @class]} {@rest}></span>
    """
  end

  @doc """
  Subtle "temporarily unavailable" placeholder. Renders the widget
  shell's empty-state region with an amber pulse dot + terse copy.
  Intentionally small and inline so it doesn't scream "broken card".
  """
  attr :brand, :atom, default: :rt, values: [:rt, :fs]
  attr :class, :string, default: nil

  def tracker_error_placeholder(assigns) do
    ~H"""
    <div class={["h-full w-full grid place-items-center px-3 py-6 text-center", @class]}>
      <div>
        <span class="inline-flex items-center gap-1.5 text-[9px] font-semibold uppercase tracking-[0.16em] text-[#EAB308]">
          <span class="bw-err-dot"></span>
          {error_headline(@brand)}
        </span>
        <div class="bw-display text-[10px] text-[#4B5563] mt-1 leading-snug">
          Retrying automatically — live data will appear shortly.
        </div>
      </div>
    </div>
    """
  end

  defp error_headline(:fs), do: "FateSwap feed paused"
  defp error_headline(_), do: "RogueTrader feed paused"
end
