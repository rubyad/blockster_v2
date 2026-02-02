defmodule BlocksterV2Web.ShopLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Shop
  alias BlocksterV2.SiteSettings

  @impl true
  def mount(_params, _session, socket) do
    # Load curated product placements from SiteSettings
    placements_setting = SiteSettings.get("shop_page_product_placements", "")
    curated_product_ids = parse_product_ids(placements_setting)

    # Load all active products with associations
    all_products = Shop.list_active_products(preload: [:images, :variants, :hub, :artist_record, :categories])

    # === DYNAMIC FILTER EXTRACTION ===

    # Categories (Products section) - from product categories
    categories_with_products =
      all_products
      |> Enum.flat_map(fn p -> p.categories || [] end)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.name)

    # Hubs (Communities section) - from product hubs
    hubs_with_products =
      all_products
      |> Enum.map(& &1.hub)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq_by(& &1.id)
      |> Enum.sort_by(& &1.name)

    # Vendors (Brands section) - from product vendors
    brands_with_products =
      all_products
      |> Enum.map(& &1.vendor)
      |> Enum.reject(&is_nil/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq()
      |> Enum.sort()

    # Build display order (curated first, then remaining)
    display_products = build_display_order(curated_product_ids, all_products)

    {:ok,
     socket
     |> assign(:page_title, "Shop - Browse Products")
     |> assign(:all_products, all_products)
     |> assign(:curated_product_ids, curated_product_ids)
     |> assign(:products, Enum.map(display_products, &transform_product/1))
     |> assign(:categories_with_products, categories_with_products)
     |> assign(:hubs_with_products, hubs_with_products)
     |> assign(:brands_with_products, brands_with_products)
     |> assign(:active_filter, nil)
     |> assign(:filtered_mode, false)
     |> assign(:show_product_picker, false)
     |> assign(:picking_slot, nil)
     |> assign(:show_mobile_filters, false)}
  end

  # Parse comma-separated product IDs from SiteSettings
  defp parse_product_ids(""), do: []
  defp parse_product_ids(nil), do: []
  defp parse_product_ids(setting) do
    setting
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Build display order: curated products first, then remaining
  defp build_display_order(curated_ids, all_products) do
    # Get curated products in order
    curated =
      curated_ids
      |> Enum.map(fn id -> Enum.find(all_products, &(to_string(&1.id) == id)) end)
      |> Enum.reject(&is_nil/1)

    # Get remaining products not in curated list
    curated_id_set = MapSet.new(curated_ids)
    remaining = Enum.reject(all_products, fn p ->
      to_string(p.id) in curated_id_set
    end)

    curated ++ remaining
  end

  defp transform_product(product) do
    first_variant = List.first(product.variants || [])
    first_image = List.first(product.images || [])

    price = if first_variant && first_variant.price do
      Decimal.to_float(first_variant.price)
    else
      0.0
    end

    compare_price = if first_variant && first_variant.compare_at_price do
      Decimal.to_float(first_variant.compare_at_price)
    else
      price
    end

    # Get the token discount percentages (0-100)
    bux_max_discount = product.bux_max_discount || 0
    hub_token_max_discount = product.hub_token_max_discount || 0

    # Max discount is the higher of the two (not additive)
    total_max_discount = max(bux_max_discount, hub_token_max_discount)

    # Calculate max discounted price (after max token redemption)
    max_discounted_price = price * (1 - total_max_discount / 100)

    # Get all image URLs
    images = Enum.map(product.images || [], fn img -> img.src end)

    # Get hub info if available
    hub = product.hub
    hub_logo = if hub && hub.logo_url, do: hub.logo_url, else: nil
    hub_name = if hub && hub.name, do: hub.name, else: nil

    # Get artist info
    artist_record = if Ecto.assoc_loaded?(product.artist_record) && product.artist_record do
      product.artist_record
    else
      nil
    end

    # Get categories
    category_slugs = if Ecto.assoc_loaded?(product.categories) do
      Enum.map(product.categories, & &1.slug)
    else
      []
    end

    %{
      id: product.id,
      name: product.title,
      slug: product.handle,
      price: price,
      original_price: compare_price,
      max_discounted_price: max_discounted_price,
      bux_max_discount: bux_max_discount,
      hub_token_max_discount: hub_token_max_discount,
      total_max_discount: total_max_discount,
      image: if(first_image, do: first_image.src, else: "https://via.placeholder.com/300x300?text=No+Image"),
      images: images,
      hub_logo: hub_logo,
      hub_name: hub_name,
      hub_slug: if(hub, do: hub.slug, else: nil),
      artist_slug: if(artist_record, do: artist_record.slug, else: nil),
      artist_name: if(artist_record, do: artist_record.name, else: product.artist),
      category_slugs: category_slugs
    }
  end

  # === FILTER EVENT HANDLERS ===

  @impl true
  def handle_event("filter_by_category", %{"slug" => slug, "name" => name}, socket) do
    filtered = filter_by_category(socket.assigns.all_products, slug)

    {:noreply,
     socket
     |> assign(:active_filter, {:category, slug, name})
     |> assign(:filtered_mode, true)
     |> assign(:products, Enum.map(filtered, &transform_product/1))
     |> assign(:show_mobile_filters, false)}
  end

  @impl true
  def handle_event("filter_by_hub", %{"slug" => slug, "name" => name}, socket) do
    filtered = filter_by_hub(socket.assigns.all_products, slug)

    {:noreply,
     socket
     |> assign(:active_filter, {:hub, slug, name})
     |> assign(:filtered_mode, true)
     |> assign(:products, Enum.map(filtered, &transform_product/1))
     |> assign(:show_mobile_filters, false)}
  end

  @impl true
  def handle_event("filter_by_brand", %{"brand" => brand}, socket) do
    filtered = filter_by_vendor(socket.assigns.all_products, brand)

    {:noreply,
     socket
     |> assign(:active_filter, {:brand, brand})
     |> assign(:filtered_mode, true)
     |> assign(:products, Enum.map(filtered, &transform_product/1))
     |> assign(:show_mobile_filters, false)}
  end

  @impl true
  def handle_event("clear_all_filters", _params, socket) do
    display_products = build_display_order(
      socket.assigns.curated_product_ids,
      socket.assigns.all_products
    )

    {:noreply,
     socket
     |> assign(:active_filter, nil)
     |> assign(:filtered_mode, false)
     |> assign(:products, Enum.map(display_products, &transform_product/1))
     |> assign(:show_mobile_filters, false)}
  end

  # === ADMIN PRODUCT PLACEMENT EVENT HANDLERS ===

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
  def handle_event("ignore", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_product_for_slot", %{"id" => product_id}, socket) do
    slot = socket.assigns.picking_slot
    curated_ids = socket.assigns.curated_product_ids

    # Update or insert product ID at slot position
    new_curated_ids = update_curated_ids(curated_ids, slot, product_id)

    # Save to SiteSettings
    SiteSettings.set("shop_page_product_placements", Enum.join(new_curated_ids, ","))

    # Rebuild display order
    display_products = build_display_order(new_curated_ids, socket.assigns.all_products)

    {:noreply,
     socket
     |> assign(:curated_product_ids, new_curated_ids)
     |> assign(:products, Enum.map(display_products, &transform_product/1))
     |> assign(:show_product_picker, false)
     |> assign(:picking_slot, nil)}
  end

  # === MOBILE FILTER EVENT HANDLERS ===

  @impl true
  def handle_event("toggle_mobile_filters", _params, socket) do
    {:noreply, assign(socket, :show_mobile_filters, !socket.assigns.show_mobile_filters)}
  end

  # === FILTER HELPER FUNCTIONS ===

  defp filter_by_category(products, category_slug) do
    Enum.filter(products, fn p ->
      Enum.any?(p.categories || [], fn cat -> cat.slug == category_slug end)
    end)
  end

  defp filter_by_hub(products, hub_slug) do
    Enum.filter(products, fn p ->
      p.hub && p.hub.slug == hub_slug
    end)
  end

  defp filter_by_vendor(products, vendor) do
    Enum.filter(products, fn p ->
      p.vendor == vendor
    end)
  end

  defp update_curated_ids(existing_ids, slot, new_id) do
    # Ensure list is long enough
    padded = existing_ids ++ List.duplicate("", max(0, slot + 1 - length(existing_ids)))

    # Replace at slot, filtering out empty strings
    padded
    |> List.replace_at(slot, new_id)
    |> Enum.filter(&(&1 != ""))
    |> Enum.uniq()
  end
end
