defmodule BlocksterV2Web.PostLive.ShopOneComponent do
  use BlocksterV2Web, :live_component

  alias BlocksterV2.SiteSettings
  alias BlocksterV2.Shop

  @default_bg_image "https://ik.imagekit.io/blockster/hero.png"

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:show_edit_modal, false)
     |> assign(:best_offers_index, 0)
     |> assign(:show_product_picker, false)
     |> assign(:picking_slot, nil)
     |> assign(:editing_best_offers_title, false)}
  end

  @impl true
  def update(assigns, socket) do
    image_key = "shop_one_bg_image"

    # Load all settings with this prefix in a single query
    settings = SiteSettings.get_by_prefix(image_key)

    # Also get the best offers settings
    best_offers_setting = SiteSettings.get("shop_one_best_offers", "")
    best_offers_title = SiteSettings.get("shop_one_best_offers_title", "Best offers")

    # Extract settings with defaults
    bg_image_url = settings[image_key] || @default_bg_image
    bg_image_position = settings["#{image_key}_position"] || "50% 50%"
    bg_image_zoom = settings["#{image_key}_zoom"] || "100"

    # Text overlay settings
    overlay_text = settings["#{image_key}_overlay_text"] || "Shop Essentials"
    overlay_text_color = settings["#{image_key}_overlay_text_color"] || "#ffffff"
    overlay_text_size = settings["#{image_key}_overlay_text_size"] || "36"
    overlay_bg_color = settings["#{image_key}_overlay_bg_color"] || "#000000"
    overlay_bg_opacity = settings["#{image_key}_overlay_bg_opacity"] || "50"
    overlay_border_radius = settings["#{image_key}_overlay_border_radius"] || "12"
    overlay_position = settings["#{image_key}_overlay_position"] || "50% 50%"

    # Text box dimensions (for resizing)
    overlay_width = settings["#{image_key}_overlay_width"] || "300"
    overlay_height = settings["#{image_key}_overlay_height"] || "auto"

    # Button settings
    button_text = settings["#{image_key}_button_text"] || "Shop Now"
    button_url = settings["#{image_key}_button_url"] || "/shop"
    button_bg_color = settings["#{image_key}_button_bg_color"] || "#ffffff"
    button_text_color = settings["#{image_key}_button_text_color"] || "#000000"
    button_size = settings["#{image_key}_button_size"] || "medium"
    button_position = settings["#{image_key}_button_position"] || "50% 75%"

    # Visibility settings
    show_text = (settings["#{image_key}_show_text"] || "true") == "true"
    show_button = (settings["#{image_key}_show_button"] || "true") == "true"

    # Best Offers products - load from saved settings or use defaults
    best_offers_ids = parse_best_offers_ids(best_offers_setting)
    all_products = Shop.list_active_products(preload: [:images, :variants])
    best_offers_products = get_best_offers_products(best_offers_ids, all_products)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:image_key, image_key)
     |> assign(:all_products, all_products)
     |> assign(:best_offers_products, best_offers_products)
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
     |> assign(:show_button, show_button)
     |> assign(:best_offers_title, best_offers_title)}
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

  # Best Offers carousel handlers
  @impl true
  def handle_event("best_offers_prev", _params, socket) do
    current = socket.assigns.best_offers_index
    products = socket.assigns.best_offers_products
    # Move by 2 products, wrap around
    max_index = max(0, length(products) - 2)
    new_index = if current <= 0, do: max_index, else: max(0, current - 2)
    {:noreply, assign(socket, :best_offers_index, new_index)}
  end

  @impl true
  def handle_event("best_offers_next", _params, socket) do
    current = socket.assigns.best_offers_index
    products = socket.assigns.best_offers_products
    max_index = max(0, length(products) - 2)
    new_index = if current >= max_index, do: 0, else: min(max_index, current + 2)
    {:noreply, assign(socket, :best_offers_index, new_index)}
  end

  @impl true
  def handle_event("open_product_picker", %{"slot" => slot}, socket) do
    {:noreply,
     socket
     |> assign(:show_product_picker, true)
     |> assign(:picking_slot, String.to_integer(slot))}
  end

  @impl true
  def handle_event("close_product_picker", _params, socket) do
    {:noreply,
     socket
     |> assign(:show_product_picker, false)
     |> assign(:picking_slot, nil)}
  end

  @impl true
  def handle_event("select_product", %{"id" => product_id}, socket) do
    slot = socket.assigns.picking_slot
    # product_id is a UUID string, no need to convert
    products = socket.assigns.best_offers_products

    # Update the product at the given slot
    new_product = Enum.find(socket.assigns.all_products, fn p -> to_string(p.id) == product_id end)

    new_products =
      if new_product do
        # Ensure we have at least 4 slots
        products = ensure_min_slots(products, socket.assigns.all_products, 4)
        List.replace_at(products, slot, new_product)
      else
        products
      end

    # Save to settings
    ids = Enum.map(new_products, fn p -> p.id end) |> Enum.join(",")
    SiteSettings.set("shop_one_best_offers", ids)

    {:noreply,
     socket
     |> assign(:best_offers_products, new_products)
     |> assign(:show_product_picker, false)
     |> assign(:picking_slot, nil)}
  end

  @impl true
  def handle_event("edit_best_offers_title", _params, socket) do
    {:noreply, assign(socket, :editing_best_offers_title, true)}
  end

  @impl true
  def handle_event("save_best_offers_title", %{"title" => title}, socket) do
    SiteSettings.set("shop_one_best_offers_title", title)

    {:noreply,
     socket
     |> assign(:best_offers_title, title)
     |> assign(:editing_best_offers_title, false)}
  end

  @impl true
  def handle_event("cancel_edit_best_offers_title", _params, socket) do
    {:noreply, assign(socket, :editing_best_offers_title, false)}
  end

  defp parse_best_offers_ids(""), do: []
  defp parse_best_offers_ids(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
    # IDs are UUIDs (strings), no need to convert to integers
  end

  defp get_best_offers_products([], all_products) do
    # Default to first 4 products if none selected
    Enum.take(all_products, 4)
  end

  defp get_best_offers_products(ids, all_products) do
    # IDs are UUID strings, compare with to_string
    selected = Enum.filter(all_products, fn p -> to_string(p.id) in ids end)
    # Sort by the order in ids
    Enum.sort_by(selected, fn p -> Enum.find_index(ids, &(&1 == to_string(p.id))) || 999 end)
    |> then(fn products ->
      if length(products) < 4 do
        # Fill with other products to reach 4
        remaining = Enum.reject(all_products, fn p -> to_string(p.id) in ids end)
        products ++ Enum.take(remaining, 4 - length(products))
      else
        products
      end
    end)
  end

  defp ensure_min_slots(products, all_products, min) when length(products) < min do
    remaining = Enum.reject(all_products, fn p -> p in products end)
    products ++ Enum.take(remaining, min - length(products))
  end

  defp ensure_min_slots(products, _all_products, _min), do: products

  defp get_product_image(product) do
    case product.images do
      [first | _] -> first.src
      _ -> "https://via.placeholder.com/300x300?text=No+Image"
    end
  end

  defp get_product_images(product) do
    case product.images do
      images when is_list(images) and length(images) > 0 ->
        Enum.map(images, & &1.src)
      _ ->
        ["https://via.placeholder.com/300x300?text=No+Image"]
    end
  end

  defp get_product_price(product) do
    case product.variants do
      [first | _] when not is_nil(first.price) ->
        Decimal.to_float(first.price)
      _ ->
        0.0
    end
  end

  defp get_product_compare_price(product) do
    case product.variants do
      [first | _] when not is_nil(first.compare_at_price) ->
        Decimal.to_float(first.compare_at_price)
      _ ->
        get_product_price(product)
    end
  end
end
