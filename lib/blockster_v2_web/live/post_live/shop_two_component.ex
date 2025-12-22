defmodule BlocksterV2Web.PostLive.ShopTwoComponent do
  use BlocksterV2Web, :live_component

  alias BlocksterV2.SiteSettings
  alias BlocksterV2.Shop

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:show_product_picker, false)
     |> assign(:picking_slot, nil)
     |> assign(:editing_title, false)}
  end

  @impl true
  def update(assigns, socket) do
    # Use unique settings key based on component id
    settings_key = "shop_two_products_#{assigns.id}"
    title_key = "shop_two_title_#{assigns.id}"
    products_setting = SiteSettings.get(settings_key, "")
    section_title = SiteSettings.get(title_key, "Crypto-Infused Streetwear")

    # Load all active products
    all_products = Shop.list_active_products(preload: [:images, :variants])

    # Get selected products or default to first 4
    product_ids = parse_product_ids(products_setting)
    selected_products = get_selected_products(product_ids, all_products)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:settings_key, settings_key)
     |> assign(:title_key, title_key)
     |> assign(:section_title, section_title)
     |> assign(:all_products, all_products)
     |> assign(:products, selected_products)}
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
  def handle_event("edit_title", _params, socket) do
    {:noreply, assign(socket, :editing_title, true)}
  end

  @impl true
  def handle_event("save_title", %{"title" => title}, socket) do
    SiteSettings.set(socket.assigns.title_key, title)

    {:noreply,
     socket
     |> assign(:section_title, title)
     |> assign(:editing_title, false)}
  end

  @impl true
  def handle_event("cancel_edit_title", _params, socket) do
    {:noreply, assign(socket, :editing_title, false)}
  end

  @impl true
  def handle_event("select_product", %{"id" => product_id}, socket) do
    slot = socket.assigns.picking_slot
    products = socket.assigns.products

    # Find the new product
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
    SiteSettings.set(socket.assigns.settings_key, ids)

    {:noreply,
     socket
     |> assign(:products, new_products)
     |> assign(:show_product_picker, false)
     |> assign(:picking_slot, nil)}
  end

  defp parse_product_ids(""), do: []
  defp parse_product_ids(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp get_selected_products([], all_products) do
    Enum.take(all_products, 4)
  end

  defp get_selected_products(ids, all_products) do
    selected = Enum.filter(all_products, fn p -> to_string(p.id) in ids end)
    # Sort by the order in ids
    Enum.sort_by(selected, fn p -> Enum.find_index(ids, &(&1 == to_string(p.id))) || 999 end)
    |> then(fn products ->
      if length(products) < 4 do
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
