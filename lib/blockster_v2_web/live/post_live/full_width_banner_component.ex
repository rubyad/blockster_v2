defmodule BlocksterV2Web.PostLive.FullWidthBannerComponent do
  use BlocksterV2Web, :live_component

  alias BlocksterV2.SiteSettings

  @default_banner "https://ik.imagekit.io/blockster/hero.png"

  @impl true
  def mount(socket) do
    {:ok, assign(socket, show_edit_modal: false, editing_version: :desktop)}
  end

  @impl true
  def update(assigns, socket) do
    banner_key = Map.get(assigns, :banner_key, "shop_landing_banner")

    # Only load settings from database on initial mount (when :desktop is not yet assigned)
    # This prevents mobile from re-inheriting desktop values on every component update
    socket =
      if Map.has_key?(socket.assigns, :desktop) do
        # Already initialized - just update the assigns passed from parent
        assign(socket, assigns)
      else
        # Initial mount - load settings from database
        settings = SiteSettings.get_by_prefix(banner_key)

        # Load desktop settings (original keys)
        desktop = load_banner_settings(settings, banner_key, "")

        # Load mobile settings (with _mobile suffix), falls back to desktop values only on initial load
        mobile = load_banner_settings(settings, banner_key, "_mobile", desktop)

        socket
        |> assign(assigns)
        |> assign(:banner_key, banner_key)
        |> assign(:desktop, desktop)
        |> assign(:mobile, mobile)
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("set_editing_version", %{"version" => version}, socket) do
    editing_version = if version == "mobile", do: :mobile, else: :desktop
    {:noreply, assign(socket, :editing_version, editing_version)}
  end

  @impl true
  def handle_event("update_banner", %{"banner_url" => banner_url}, socket) do
    banner_key = socket.assigns.banner_key
    suffix = version_suffix(socket.assigns.editing_version)
    setting_key = "#{banner_key}#{suffix}"

    case SiteSettings.set(setting_key, banner_url) do
      {:ok, _} ->
        {:noreply, update_version_setting(socket, :banner_url, banner_url)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_position", %{"position" => position}, socket) do
    banner_key = socket.assigns.banner_key
    suffix = version_suffix(socket.assigns.editing_version)
    position_key = "#{banner_key}#{suffix}_position"

    case SiteSettings.set(position_key, position) do
      {:ok, _} ->
        {:noreply, update_version_setting(socket, :banner_position, position)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_zoom", %{"zoom" => zoom}, socket) do
    banner_key = socket.assigns.banner_key
    suffix = version_suffix(socket.assigns.editing_version)
    zoom_key = "#{banner_key}#{suffix}_zoom"

    case SiteSettings.set(zoom_key, zoom) do
      {:ok, _} ->
        {:noreply, update_version_setting(socket, :banner_zoom, zoom)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_overlay_position", %{"position" => position}, socket) do
    banner_key = socket.assigns.banner_key
    suffix = version_suffix(socket.assigns.editing_version)
    position_key = "#{banner_key}#{suffix}_overlay_position"

    case SiteSettings.set(position_key, position) do
      {:ok, _} ->
        {:noreply, update_version_setting(socket, :overlay_position, position)}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_overlay_size", %{"width" => width, "height" => height}, socket) do
    banner_key = socket.assigns.banner_key
    suffix = version_suffix(socket.assigns.editing_version)

    SiteSettings.set("#{banner_key}#{suffix}_overlay_width", width)
    SiteSettings.set("#{banner_key}#{suffix}_overlay_height", height)

    {:noreply, update_version_settings(socket, %{overlay_width: width, overlay_height: height})}
  end

  @impl true
  def handle_event("update_button_position", %{"position" => position}, socket) do
    banner_key = socket.assigns.banner_key
    suffix = version_suffix(socket.assigns.editing_version)
    position_key = "#{banner_key}#{suffix}_button_position"

    case SiteSettings.set(position_key, position) do
      {:ok, _} ->
        {:noreply, update_version_setting(socket, :button_position, position)}

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
    banner_key = socket.assigns.banner_key
    suffix = version_suffix(socket.assigns.editing_version)
    key_prefix = "#{banner_key}#{suffix}"

    # Get current version's settings for fallback values
    current = if socket.assigns.editing_version == :desktop,
      do: socket.assigns.desktop,
      else: socket.assigns.mobile

    # Handle checkbox values (they come as "true" or nil)
    show_text = if params["show_text"], do: "true", else: "false"
    show_button = if params["show_button"], do: "true", else: "false"

    settings = [
      {"#{key_prefix}_overlay_text", params["overlay_text"]},
      {"#{key_prefix}_overlay_text_color", params["overlay_text_color"]},
      {"#{key_prefix}_overlay_text_size", params["overlay_text_size"]},
      {"#{key_prefix}_overlay_bg_color", params["overlay_bg_color"]},
      {"#{key_prefix}_overlay_bg_opacity", params["overlay_bg_opacity"]},
      {"#{key_prefix}_overlay_border_radius", params["overlay_border_radius"]},
      {"#{key_prefix}_button_text", params["button_text"]},
      {"#{key_prefix}_button_url", params["button_url"]},
      {"#{key_prefix}_button_bg_color", params["button_bg_color"]},
      {"#{key_prefix}_button_text_color", params["button_text_color"]},
      {"#{key_prefix}_button_size", params["button_size"]},
      {"#{key_prefix}_height", params["banner_height"]},
      {"#{key_prefix}_show_text", show_text},
      {"#{key_prefix}_show_button", show_button}
    ]

    Enum.each(settings, fn {key, value} ->
      if value, do: SiteSettings.set(key, value)
    end)

    updates = %{
      overlay_text: params["overlay_text"] || current.overlay_text,
      overlay_text_color: params["overlay_text_color"] || current.overlay_text_color,
      overlay_text_size: params["overlay_text_size"] || current.overlay_text_size,
      overlay_bg_color: params["overlay_bg_color"] || current.overlay_bg_color,
      overlay_bg_opacity: params["overlay_bg_opacity"] || current.overlay_bg_opacity,
      overlay_border_radius: params["overlay_border_radius"] || current.overlay_border_radius,
      button_text: params["button_text"] || current.button_text,
      button_url: params["button_url"] || current.button_url,
      button_bg_color: params["button_bg_color"] || current.button_bg_color,
      button_text_color: params["button_text_color"] || current.button_text_color,
      button_size: params["button_size"] || current.button_size,
      banner_height: params["banner_height"] || current.banner_height,
      show_text: show_text == "true",
      show_button: show_button == "true"
    }

    {:noreply,
     socket
     |> update_version_settings(updates)
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

  # Load banner settings for a specific version (desktop or mobile)
  # suffix is "" for desktop, "_mobile" for mobile
  # defaults is an optional map to fall back to (used for mobile to fall back to desktop values)
  defp load_banner_settings(settings, banner_key, suffix, defaults \\ %{}) do
    key = "#{banner_key}#{suffix}"

    %{
      banner_url: settings[key] || defaults[:banner_url] || @default_banner,
      banner_position: settings["#{key}_position"] || defaults[:banner_position] || "50% 50%",
      banner_zoom: settings["#{key}_zoom"] || defaults[:banner_zoom] || "100",
      overlay_text: settings["#{key}_overlay_text"] || defaults[:overlay_text] || "Shop the collection on Blockster",
      overlay_text_color: settings["#{key}_overlay_text_color"] || defaults[:overlay_text_color] || "#ffffff",
      overlay_text_size: settings["#{key}_overlay_text_size"] || defaults[:overlay_text_size] || "48",
      overlay_bg_color: settings["#{key}_overlay_bg_color"] || defaults[:overlay_bg_color] || "#000000",
      overlay_bg_opacity: settings["#{key}_overlay_bg_opacity"] || defaults[:overlay_bg_opacity] || "50",
      overlay_border_radius: settings["#{key}_overlay_border_radius"] || defaults[:overlay_border_radius] || "12",
      overlay_position: settings["#{key}_overlay_position"] || defaults[:overlay_position] || "50% 50%",
      overlay_width: settings["#{key}_overlay_width"] || defaults[:overlay_width] || "400",
      overlay_height: settings["#{key}_overlay_height"] || defaults[:overlay_height] || "auto",
      button_text: settings["#{key}_button_text"] || defaults[:button_text] || "View All",
      button_url: settings["#{key}_button_url"] || defaults[:button_url] || "/shop",
      button_bg_color: settings["#{key}_button_bg_color"] || defaults[:button_bg_color] || "#ffffff",
      button_text_color: settings["#{key}_button_text_color"] || defaults[:button_text_color] || "#000000",
      button_size: settings["#{key}_button_size"] || defaults[:button_size] || "medium",
      button_position: settings["#{key}_button_position"] || defaults[:button_position] || "50% 70%",
      banner_height: settings["#{key}_height"] || defaults[:banner_height] || "600",
      show_text: (settings["#{key}_show_text"] || defaults[:show_text] || "true") == "true",
      show_button: (settings["#{key}_show_button"] || defaults[:show_button] || "true") == "true"
    }
  end

  defp version_suffix(:desktop), do: ""
  defp version_suffix(:mobile), do: "_mobile"

  # Update a setting in the current editing version's map
  defp update_version_setting(socket, key, value) do
    version = socket.assigns.editing_version
    version_map = if version == :desktop, do: socket.assigns.desktop, else: socket.assigns.mobile
    updated_map = Map.put(version_map, key, value)

    if version == :desktop do
      assign(socket, :desktop, updated_map)
    else
      assign(socket, :mobile, updated_map)
    end
  end

  # Update multiple settings in the current editing version's map
  defp update_version_settings(socket, updates) do
    version = socket.assigns.editing_version
    version_map = if version == :desktop, do: socket.assigns.desktop, else: socket.assigns.mobile
    updated_map = Map.merge(version_map, updates)

    if version == :desktop do
      assign(socket, :desktop, updated_map)
    else
      assign(socket, :mobile, updated_map)
    end
  end
end
