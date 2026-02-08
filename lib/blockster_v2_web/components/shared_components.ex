defmodule BlocksterV2Web.SharedComponents do
  @moduledoc """
  Shared UI components for the Blockster application.
  Contains reusable components like footer and icons.
  """
  use Phoenix.Component
  use BlocksterV2Web, :verified_routes

  alias BlocksterV2.ImageKit

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
  Renders a BUX token badge for posts/content.
  Always shows BUX icon with thin black border (hub tokens removed).

  ## Attributes
    - post: The post struct (kept for backward compatibility)
    - balance: The balance to display
    - id: Unique ID for the component (optional)
  """
  attr :post, :map, required: true
  attr :balance, :any, required: true
  attr :id, :string, default: nil

  def token_badge(assigns) do
    # Determine if pool is empty (balance is 0 or nil)
    is_empty = assigns.balance == 0 or assigns.balance == nil or assigns.balance == 0.0
    balance_formatted = Number.Delimit.number_to_delimited(assigns.balance, precision: 0)

    tooltip = if is_empty do
      "No BUX available in reward pool"
    else
      "#{balance_formatted} BUX available in reward pool"
    end

    assigns = assigns
      |> assign(:is_empty, is_empty)
      |> assign(:balance_formatted, balance_formatted)
      |> assign(:tooltip, tooltip)

    ~H"""
    <!-- BUX badge - solid lime green with lightning bolt from logo -->
    <!-- Gray out when pool is empty to indicate no BUX available -->
    <!-- Sized to match earned badges (h-4 icon, text-xs, px-2.5 py-1.5) -->
    <div class={"rounded-full inline-block cursor-default #{if @is_empty, do: "bg-gray-300", else: "bg-[#D4FF00]"}"} title={@tooltip}>
      <div class="flex items-center gap-1 rounded-full px-2.5 py-1.5">
        <img
          src={~p"/images/bolt.png"}
          alt="BUX"
          class={"h-4 w-4 #{if @is_empty, do: "opacity-40", else: ""}"}
        />
        <span class={"text-xs font-haas_medium_65 #{if @is_empty, do: "text-gray-400", else: "text-black"}"}>
          {@balance_formatted}
        </span>
      </div>
    </div>
    """
  end

  @doc """
  Renders earned badges showing BUX already earned from a post.
  Shows separate badges for each reward type: read (orange), share (black), watch (purple).

  ## Attributes
    - reward: Map with :read_bux, :x_share_bux, and :watch_bux amounts
    - id: Unique ID for the badge
  """
  attr :reward, :map, required: true
  attr :id, :string, default: nil

  def earned_badges(assigns) do
    read_bux = assigns.reward[:read_bux] || 0
    x_share_bux = assigns.reward[:x_share_bux] || 0
    watch_bux = assigns.reward[:watch_bux] || 0

    read_formatted = Number.Delimit.number_to_delimited(read_bux, precision: 0)
    share_formatted = Number.Delimit.number_to_delimited(x_share_bux, precision: 0)
    watch_formatted = Number.Delimit.number_to_delimited(watch_bux, precision: 0)

    assigns = assigns
      |> assign(:read_bux, read_bux)
      |> assign(:x_share_bux, x_share_bux)
      |> assign(:watch_bux, watch_bux)
      |> assign(:read_formatted, read_formatted)
      |> assign(:share_formatted, share_formatted)
      |> assign(:watch_formatted, watch_formatted)

    ~H"""
    <div class="flex flex-wrap gap-1">
      <!-- Read reward badge (amber with white text) - 20% bigger -->
      <%= if @read_bux > 0 do %>
        <div class="rounded-full inline-block bg-gradient-to-r from-amber-400 to-amber-500 cursor-default" title={"Earned #{@read_formatted} BUX for reading"}>
          <div class="flex items-center gap-1 rounded-full px-2.5 py-1.5">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-white" viewBox="0 0 20 20" fill="currentColor">
              <path d="M9 4.804A7.968 7.968 0 005.5 4c-1.255 0-2.443.29-3.5.804v10A7.969 7.969 0 015.5 14c1.669 0 3.218.51 4.5 1.385A7.962 7.962 0 0114.5 14c1.255 0 2.443.29 3.5.804v-10A7.968 7.968 0 0014.5 4c-1.255 0-2.443.29-3.5.804V12a1 1 0 11-2 0V4.804z" />
            </svg>
            <span class="text-xs font-haas_medium_65 text-white">
              {@read_formatted}
            </span>
          </div>
        </div>
      <% end %>

      <!-- Share reward badge (black filled with white text) - 20% bigger -->
      <%= if @x_share_bux > 0 do %>
        <div class="rounded-full inline-block bg-gray-900 cursor-default" title={"Earned #{@share_formatted} BUX for sharing on X"}>
          <div class="flex items-center gap-1 rounded-full px-2.5 py-1.5">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-white" viewBox="0 0 20 20" fill="currentColor">
              <path d="M15 8a3 3 0 10-2.977-2.63l-4.94 2.47a3 3 0 100 4.319l4.94 2.47a3 3 0 10.895-1.789l-4.94-2.47a3.027 3.027 0 000-.74l4.94-2.47C13.456 7.68 14.19 8 15 8z" />
            </svg>
            <span class="text-xs font-haas_medium_65 text-white">
              {@share_formatted}
            </span>
          </div>
        </div>
      <% end %>

      <!-- Watch reward badge (purple) - 20% bigger -->
      <%= if @watch_bux > 0 do %>
        <div class="rounded-full inline-block bg-gradient-to-r from-violet-400 to-violet-500 cursor-default" title={"Earned #{@watch_formatted} BUX for watching video"}>
          <div class="flex items-center gap-1.5 rounded-full px-2.5 py-1.5">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-white" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M10 18a8 8 0 100-16 8 8 0 000 16zM9.555 7.168A1 1 0 008 8v4a1 1 0 001.555.832l3-2a1 1 0 000-1.664l-3-2z" clip-rule="evenodd" />
            </svg>
            <span class="text-xs font-haas_medium_65 text-white">
              {@watch_formatted}
            </span>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a video play icon overlay for posts with videos.
  Positioned absolutely in the center of the parent container.

  ## Attributes
    - size: Icon size - :small (32px), :medium (48px), or :large (64px)
  """
  attr :size, :atom, default: :medium

  def video_play_icon(assigns) do
    size_classes = case assigns.size do
      :small -> "w-8 h-8"
      :medium -> "w-12 h-12"
      :large -> "w-16 h-16"
    end

    assigns = assign(assigns, :size_classes, size_classes)

    ~H"""
    <div class={"absolute inset-0 flex items-center justify-center pointer-events-none"}>
      <div class={"#{@size_classes} bg-black/60 rounded-full flex items-center justify-center"}>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="white" class="w-1/2 h-1/2 ml-0.5">
          <path d="M8 5v14l11-7z"/>
        </svg>
      </div>
    </div>
    """
  end

  @doc """
  Renders a post card for suggested/related posts.
  Matches the exact styling of homepage post cards.

  ## Attributes
    - post: The post struct (requires title, slug, featured_image, category, published_at)
    - balance: The BUX balance for the post
  """
  attr :post, :map, required: true
  attr :balance, :any, default: 0

  def post_card(assigns) do
    ~H"""
    <.link navigate={~p"/#{@post.slug}"} class="block cursor-pointer">
      <div class="rounded-lg border-[#1414141A] border bg-white hover:shadow-lg transition-all flex flex-col h-full">
        <!-- Featured Image -->
        <div class="img-wrapper w-full overflow-hidden rounded-t-lg aspect-square relative">
          <%= if @post.featured_image do %>
            <img
              src={ImageKit.w500_h500(@post.featured_image)}
              alt={@post.title}
              class="w-full h-full object-cover"
              loading="lazy"
            />
          <% else %>
            <div class="w-full h-full bg-gradient-to-br from-[#8AE388] to-[#BAF55F] flex items-center justify-center">
              <svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none">
                <path d="M15.8 2.21048C15.39 1.80048 14.68 2.08048 14.68 2.65048V6.14048C14.68 7.60048 15.92 8.81048 17.43 8.81048C18.38 8.82048 19.7 8.82048 20.83 8.82048C21.4 8.82048 21.7 8.15048 21.3 7.75048C19.86 6.30048 17.28 3.69048 15.8 2.21048Z" fill="#141414" />
                <path d="M20.5 10.19H17.61C15.24 10.19 13.31 8.26 13.31 5.89V3C13.31 2.45 12.86 2 12.31 2H8.07C4.99 2 2.5 4 2.5 7.57V16.43C2.5 20 4.99 22 8.07 22H15.93C19.01 22 21.5 20 21.5 16.43V11.19C21.5 10.64 21.05 10.19 20.5 10.19Z" fill="#141414" />
              </svg>
            </div>
          <% end %>
          <%= if @post.video_id do %>
            <.video_play_icon size={:medium} />
          <% end %>
        </div>

        <!-- Card Content -->
        <div class="px-3 py-3 pb-4 flex-1 flex flex-col text-center">
          <!-- Category Badge -->
          <%= if @post.category do %>
            <div class="flex justify-center">
              <span class="px-3 py-1 bg-white border border-[#E7E8F1] text-[#141414] rounded-full text-xs font-haas_medium_65">
                {@post.category.name}
              </span>
            </div>
          <% end %>

          <!-- Title -->
          <h4 class="font-haas_medium_65 text-[#141414] mt-2 text-md leading-tight flex-1">
            {@post.title}
          </h4>

          <!-- Date -->
          <p class="text-xs font-haas_roman_55 text-[#141414] mt-3">
            <%= if @post.published_at do %>
              {Calendar.strftime(@post.published_at, "%B %d, %Y")}
            <% else %>
              Draft
            <% end %>
          </p>

          <!-- BUX Token Badge -->
          <div class="flex justify-center mt-3">
            <.token_badge post={@post} balance={@balance} />
          </div>
        </div>
      </div>
    </.link>
    """
  end

end