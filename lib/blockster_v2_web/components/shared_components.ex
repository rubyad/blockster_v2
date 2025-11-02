defmodule BlocksterV2Web.SharedComponents do
  @moduledoc """
  Shared UI components for the Blockster application.
  Contains reusable components like footer and icons.
  """
  use Phoenix.Component
  use BlocksterV2Web, :verified_routes

  @doc """
  Renders a lightning bolt icon with gradient (BUX token icon).
  Ensures unique IDs to avoid duplicate ID warnings.
  """
  attr :size, :string, default: "20"
  attr :id, :string, required: true

  def lightning_icon(assigns) do
    ~H"""
    <svg xmlns="http://www.w3.org/2000/svg" width={@size} height={@size} viewBox="0 0 24 24" fill="none">
      <g clip-path={"url(#clip_#{@id})"}>
        <circle cx="12" cy="12" r="12" fill={"url(#paint_#{@id})"} />
        <path d="M16.0709 10.7413L9.28536 19.0418L11.071 13.2675H8.0354L14.4638 5.50839L12.8567 10.7413H16.0709Z" fill="#141414" />
      </g>
      <defs>
        <linearGradient id={"paint_#{@id}"} x1="24" y1="24" x2="0" y2="0" gradientUnits="userSpaceOnUse">
          <stop stop-color="#8AE388" />
          <stop offset="1" stop-color="#BAF55F" />
        </linearGradient>
        <clipPath id={"clip_#{@id}"}>
          <rect width="24" height="24" rx="12" fill="white" />
        </clipPath>
      </defs>
    </svg>
    """
  end

end