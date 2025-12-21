defmodule BlocksterV2Web.PostLive.ShopOneComponent do
  use BlocksterV2Web, :live_component

  alias BlocksterV2.SiteSettings

  @default_bg_image "https://ik.imagekit.io/blockster/hero.png"

  @impl true
  def mount(socket) do
    {:ok, assign(socket, :show_edit_modal, false)}
  end

  @impl true
  def update(assigns, socket) do
    image_key = "shop_one_bg_image"
    bg_image_url = SiteSettings.get(image_key, @default_bg_image)
    bg_image_position = SiteSettings.get("#{image_key}_position", "50% 50%")
    bg_image_zoom = SiteSettings.get("#{image_key}_zoom", "100")

    # Text overlay settings
    overlay_text = SiteSettings.get("#{image_key}_overlay_text", "Shop Essentials")
    overlay_text_color = SiteSettings.get("#{image_key}_overlay_text_color", "#ffffff")
    overlay_text_size = SiteSettings.get("#{image_key}_overlay_text_size", "36")
    overlay_bg_color = SiteSettings.get("#{image_key}_overlay_bg_color", "#000000")
    overlay_bg_opacity = SiteSettings.get("#{image_key}_overlay_bg_opacity", "50")
    overlay_border_radius = SiteSettings.get("#{image_key}_overlay_border_radius", "12")
    overlay_position = SiteSettings.get("#{image_key}_overlay_position", "50% 50%")

    # Text box dimensions (for resizing)
    overlay_width = SiteSettings.get("#{image_key}_overlay_width", "300")
    overlay_height = SiteSettings.get("#{image_key}_overlay_height", "auto")

    # Button settings
    button_text = SiteSettings.get("#{image_key}_button_text", "Shop Now")
    button_url = SiteSettings.get("#{image_key}_button_url", "/shop")
    button_bg_color = SiteSettings.get("#{image_key}_button_bg_color", "#ffffff")
    button_text_color = SiteSettings.get("#{image_key}_button_text_color", "#000000")
    button_size = SiteSettings.get("#{image_key}_button_size", "medium")
    button_position = SiteSettings.get("#{image_key}_button_position", "50% 75%")

    # Visibility settings
    show_text = SiteSettings.get("#{image_key}_show_text", "true") == "true"
    show_button = SiteSettings.get("#{image_key}_show_button", "true") == "true"

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:image_key, image_key)
     |> assign(:bg_image_url, bg_image_url)
     |> assign(:bg_image_position, bg_image_position)
     |> assign(:bg_image_zoom, bg_image_zoom)
     |> assign(:overlay_text, overlay_text)
     |> assign(:overlay_text_color, overlay_text_color)
     |> assign(:overlay_text_size, overlay_text_size)
     |> assign(:overlay_bg_color, overlay_bg_color)
     |> assign(:overlay_bg_opacity, overlay_bg_opacity)
     |> assign(:overlay_border_radius, overlay_border_radius)
     |> assign(:overlay_position, overlay_position)
     |> assign(:overlay_width, overlay_width)
     |> assign(:overlay_height, overlay_height)
     |> assign(:button_text, button_text)
     |> assign(:button_url, button_url)
     |> assign(:button_bg_color, button_bg_color)
     |> assign(:button_text_color, button_text_color)
     |> assign(:button_size, button_size)
     |> assign(:button_position, button_position)
     |> assign(:show_text, show_text)
     |> assign(:show_button, show_button)}
  end

  @impl true
  def handle_event("update_banner", %{"banner_url" => banner_url}, socket) do
    image_key = socket.assigns.image_key

    case SiteSettings.set(image_key, banner_url) do
      {:ok, _} ->
        {:noreply, assign(socket, :bg_image_url, banner_url)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_position", %{"position" => position}, socket) do
    image_key = socket.assigns.image_key
    position_key = "#{image_key}_position"

    case SiteSettings.set(position_key, position) do
      {:ok, _} ->
        {:noreply, assign(socket, :bg_image_position, position)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_zoom", %{"zoom" => zoom}, socket) do
    image_key = socket.assigns.image_key
    zoom_key = "#{image_key}_zoom"

    case SiteSettings.set(zoom_key, zoom) do
      {:ok, _} ->
        {:noreply, assign(socket, :bg_image_zoom, zoom)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_overlay_position", %{"position" => position}, socket) do
    image_key = socket.assigns.image_key
    position_key = "#{image_key}_overlay_position"

    case SiteSettings.set(position_key, position) do
      {:ok, _} ->
        {:noreply, assign(socket, :overlay_position, position)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_overlay_size", %{"width" => width, "height" => height}, socket) do
    image_key = socket.assigns.image_key

    SiteSettings.set("#{image_key}_overlay_width", width)
    SiteSettings.set("#{image_key}_overlay_height", height)

    {:noreply,
     socket
     |> assign(:overlay_width, width)
     |> assign(:overlay_height, height)}
  end

  @impl true
  def handle_event("update_button_position", %{"position" => position}, socket) do
    image_key = socket.assigns.image_key
    position_key = "#{image_key}_button_position"

    case SiteSettings.set(position_key, position) do
      {:ok, _} ->
        {:noreply, assign(socket, :button_position, position)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("open_edit_modal", _params, socket) do
    {:noreply, assign(socket, :show_edit_modal, true)}
  end

  @impl true
  def handle_event("close_edit_modal", _params, socket) do
    {:noreply, assign(socket, :show_edit_modal, false)}
  end

  @impl true
  def handle_event("ignore", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save_overlay_settings", params, socket) do
    image_key = socket.assigns.image_key

    # Handle checkbox values (they come as "true" or nil)
    show_text = if params["show_text"], do: "true", else: "false"
    show_button = if params["show_button"], do: "true", else: "false"

    settings = [
      {"#{image_key}_overlay_text", params["overlay_text"]},
      {"#{image_key}_overlay_text_color", params["overlay_text_color"]},
      {"#{image_key}_overlay_text_size", params["overlay_text_size"]},
      {"#{image_key}_overlay_bg_color", params["overlay_bg_color"]},
      {"#{image_key}_overlay_bg_opacity", params["overlay_bg_opacity"]},
      {"#{image_key}_overlay_border_radius", params["overlay_border_radius"]},
      {"#{image_key}_button_text", params["button_text"]},
      {"#{image_key}_button_url", params["button_url"]},
      {"#{image_key}_button_bg_color", params["button_bg_color"]},
      {"#{image_key}_button_text_color", params["button_text_color"]},
      {"#{image_key}_button_size", params["button_size"]},
      {"#{image_key}_show_text", show_text},
      {"#{image_key}_show_button", show_button}
    ]

    Enum.each(settings, fn {key, value} ->
      if value, do: SiteSettings.set(key, value)
    end)

    {:noreply,
     socket
     |> assign(:overlay_text, params["overlay_text"] || socket.assigns.overlay_text)
     |> assign(:overlay_text_color, params["overlay_text_color"] || socket.assigns.overlay_text_color)
     |> assign(:overlay_text_size, params["overlay_text_size"] || socket.assigns.overlay_text_size)
     |> assign(:overlay_bg_color, params["overlay_bg_color"] || socket.assigns.overlay_bg_color)
     |> assign(:overlay_bg_opacity, params["overlay_bg_opacity"] || socket.assigns.overlay_bg_opacity)
     |> assign(:overlay_border_radius, params["overlay_border_radius"] || socket.assigns.overlay_border_radius)
     |> assign(:button_text, params["button_text"] || socket.assigns.button_text)
     |> assign(:button_url, params["button_url"] || socket.assigns.button_url)
     |> assign(:button_bg_color, params["button_bg_color"] || socket.assigns.button_bg_color)
     |> assign(:button_text_color, params["button_text_color"] || socket.assigns.button_text_color)
     |> assign(:button_size, params["button_size"] || socket.assigns.button_size)
     |> assign(:show_text, show_text == "true")
     |> assign(:show_button, show_button == "true")
     |> assign(:show_edit_modal, false)}
  end

  defp imagekit_url(url) do
    if String.contains?(url, "ik.imagekit.io") do
      "#{url}?tr=w-1920,q-90"
    else
      url
    end
  end

  defp parse_zoom(zoom) when is_binary(zoom) do
    case Float.parse(zoom) do
      {value, _} -> value
      :error -> 100.0
    end
  end

  defp parse_zoom(zoom) when is_number(zoom), do: zoom / 1
  defp parse_zoom(_), do: 100.0

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 0
    end
  end

  defp parse_int(value) when is_integer(value), do: value
  defp parse_int(_), do: 0

  defp hex_to_rgba(hex, opacity) do
    hex = String.replace(hex, "#", "")
    {r, _} = Integer.parse(String.slice(hex, 0, 2), 16)
    {g, _} = Integer.parse(String.slice(hex, 2, 2), 16)
    {b, _} = Integer.parse(String.slice(hex, 4, 2), 16)
    alpha = parse_int(opacity) / 100
    "rgba(#{r}, #{g}, #{b}, #{alpha})"
  end

  defp button_padding(size) do
    case size do
      "small" -> "px-4 py-2 text-sm"
      "large" -> "px-8 py-4 text-lg"
      _ -> "px-6 py-3 text-base"
    end
  end

  defp parse_position(position) do
    case String.split(position, " ") do
      [x, y] ->
        x_val = String.replace(x, "%", "") |> parse_int()
        y_val = String.replace(y, "%", "") |> parse_int()
        {x_val, y_val}
      _ ->
        {50, 50}
    end
  end
end
