defmodule BlocksterV2Web.PostLive.ShopFourComponent do
  use BlocksterV2Web, :live_component

  alias BlocksterV2.SiteSettings
  alias BlocksterV2.Shop

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:show_product_picker, false)
     |> assign(:picking_slot, nil)
     |> assign(:selected_category, nil)
     |> assign(:editing_title, false)}
  end

  @impl true
  def update(assigns, socket) do
    settings_key = "shop_four_products"
    title_key = "shop_four_title"
    products_setting = SiteSettings.get(settings_key, "")
    section_title = SiteSettings.get(title_key, "Hot Deals")

    # Load all active products with categories
    all_products = Shop.list_active_products(preload: [:images, :variants, :categories])

    # Load categories
    categories = Shop.list_categories()

    # Get selected products or default to first 3
    product_ids = parse_product_ids(products_setting)
    selected_products = get_selected_products(product_ids, all_products, 3)

    # Filter by category if one is selected
    current_category = socket.assigns[:selected_category]
    filtered_products = filter_by_category(selected_products, current_category)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:settings_key, settings_key)
     |> assign(:title_key, title_key)
     |> assign(:section_title, section_title)
     |> assign(:all_products, all_products)
     |> assign(:products, selected_products)
     |> assign(:filtered_products, filtered_products)
     |> assign(:categories, categories)}
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
    products = socket.assigns.products

    new_product = Enum.find(socket.assigns.all_products, fn p -> to_string(p.id) == product_id end)

    new_products =
      if new_product do
        products = ensure_min_slots(products, socket.assigns.all_products, 3)
        List.replace_at(products, slot, new_product)
      else
        products
      end

    ids = Enum.map(new_products, fn p -> p.id end) |> Enum.join(",")
    SiteSettings.set(socket.assigns.settings_key, ids)

    filtered = filter_by_category(new_products, socket.assigns.selected_category)

    {:noreply,
     socket
     |> assign(:products, new_products)
     |> assign(:filtered_products, filtered)
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
  def handle_event("filter_category", %{"category" => category_id}, socket) do
    selected = if category_id == "", do: nil, else: category_id

    # When filtering, show from all products matching category
    filtered =
      if selected do
        socket.assigns.all_products
        |> Enum.filter(fn p ->
          Enum.any?(p.categories, fn c -> to_string(c.id) == selected end)
        end)
        |> Enum.take(3)
      else
        socket.assigns.products
      end

    {:noreply,
     socket
     |> assign(:selected_category, selected)
     |> assign(:filtered_products, filtered)}
  end

  defp filter_by_category(products, nil), do: products
  defp filter_by_category(products, category_id) do
    Enum.filter(products, fn p ->
      Enum.any?(p.categories, fn c -> to_string(c.id) == category_id end)
    end)
  end

  defp parse_product_ids(""), do: []
  defp parse_product_ids(str) do
    str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  defp get_selected_products([], all_products, count) do
    Enum.take(all_products, count)
  end

  defp get_selected_products(ids, all_products, count) do
    selected = Enum.filter(all_products, fn p -> to_string(p.id) in ids end)
    Enum.sort_by(selected, fn p -> Enum.find_index(ids, &(&1 == to_string(p.id))) || 999 end)
    |> then(fn products ->
      if length(products) < count do
        remaining = Enum.reject(all_products, fn p -> to_string(p.id) in ids end)
        products ++ Enum.take(remaining, count - length(products))
      else
        Enum.take(products, count)
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
      _ -> "https://via.placeholder.com/300x400?text=No+Image"
    end
  end

  defp get_product_images(product) do
    case product.images do
      images when is_list(images) and length(images) > 0 ->
        Enum.map(images, & &1.src)
      _ ->
        ["https://via.placeholder.com/300x400?text=No+Image"]
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
