defmodule BlocksterV2Web.SharedComponents do
  @moduledoc """
  Shared UI components for the Blockster application.
  Contains reusable components like footer and icons.
  """
  use Phoenix.Component
  use BlocksterV2Web, :verified_routes

  @doc """
  Renders the BUX token icon.
  Uses the ImageKit-hosted blockster icon image.
  """
  attr :size, :string, default: "20"
  attr :id, :string, default: nil

  def lightning_icon(assigns) do
    ~H"""
    <img
      src="https://ik.imagekit.io/blockster/blockster-icon.png"
      alt="BUX"
      class="rounded-full object-cover"
      style={"width: #{@size}px; height: #{@size}px;"}
    />
    """
  end

  @doc """
  Renders a token badge for posts/content.
  Shows hub logo with thin black border if post has active hub with token,
  otherwise shows default blocksterBUX icon with thin black border.

  ## Attributes
    - post: The post struct (must have hub preloaded)
    - balance: The balance to display
    - id: Unique ID for the component (optional)
  """
  attr :post, :map, required: true
  attr :balance, :any, required: true
  attr :id, :string, default: nil

  def token_badge(assigns) do
    hub = assigns.post.hub
    has_hub_token = hub && hub.is_active && hub.token && hub.token != "" && hub.logo_url && hub.logo_url != ""
    assigns = assign(assigns, :has_hub_token, has_hub_token)
    assigns = assign(assigns, :hub, hub)
    assigns = assign(assigns, :unique_id, assigns[:id] || "token_#{:erlang.unique_integer([:positive])}")

    ~H"""
    <%= if @has_hub_token do %>
      <!-- Hub token badge with thin black border -->
      <div class="p-[0.5px] rounded-[100px] inline-block bg-[#141414]">
        <div class="flex items-center gap-1.5 bg-white rounded-[100px] px-2 py-1 min-w-[73px]">
          <img src={@hub.logo_url} alt={@hub.name} class="h-5 w-5 rounded-full object-cover" />
          <span class="text-xs font-haas_medium_65">{Number.Delimit.number_to_delimited(@balance, precision: 2)}</span>
        </div>
      </div>
    <% else %>
      <!-- Default BUX badge with thin black border -->
      <div class="p-[0.5px] rounded-[100px] inline-block bg-[#141414]">
        <div class="flex items-center gap-1.5 bg-white rounded-[100px] px-2 py-1 min-w-[73px]">
          <img src="https://ik.imagekit.io/blockster/blockster-icon.png" alt="BUX" class="h-5 w-5 rounded-full object-cover" />
          <span class="text-xs font-haas_medium_65">{Number.Delimit.number_to_delimited(@balance, precision: 2)}</span>
        </div>
      </div>
    <% end %>
    """
  end

end