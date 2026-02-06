defmodule BlocksterV2Web.ShopLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Shop
  alias BlocksterV2.ShopSlots

  # Category icons mapping (slug => ImageKit URL)
  @category_icons %{
    "t-shirt" => "https://ik.imagekit.io/blockster/tees.png",
    "tees" => "https://ik.imagekit.io/blockster/tees.png",
    "t-shirts" => "https://ik.imagekit.io/blockster/tees.png",
    "hoodie" => "https://ik.imagekit.io/blockster/hoodies.png",
    "hoodies" => "https://ik.imagekit.io/blockster/hoodies.png",
    "hat" => "https://ik.imagekit.io/blockster/hats.png",
    "hats" => "https://ik.imagekit.io/blockster/hats.png",
    "caps" => "https://ik.imagekit.io/blockster/hats.png",
    "sneakers" => "https://ik.imagekit.io/blockster/sneakers.png",
    "shoes" => "https://ik.imagekit.io/blockster/sneakers.png",
    "sunglasses" => "https://ik.imagekit.io/blockster/sunglasses.png",
    "eyewear" => "https://ik.imagekit.io/blockster/sunglasses.png",
    "gadgets" => "https://ik.imagekit.io/blockster/gadgets.png",
    "hardware" => "https://ik.imagekit.io/blockster/gadgets.png"
  }

  # Brand icons mapping (brand name => ImageKit URL)
  @brand_icons %{
    "Adidas" => "https://ik.imagekit.io/blockster/Adidas%20Black.png",
    "Converse" => "https://ik.imagekit.io/blockster/Converse%20Black.png",
    "Nike" => "https://ik.imagekit.io/blockster/Nike.png",
    "Oakley" => "https://ik.imagekit.io/blockster/Oakley%20Black.png",
    "Ledger" => "https://ik.imagekit.io/blockster/Ledger%20Black%20Icon.png",
    "Blockster" => "https://ik.imagekit.io/blockster/blockster-icon.png",
    "Cudis" => "https://ik.imagekit.io/blockster/Cudis%20Black.png",
    "Solana" => "https://ik.imagekit.io/blockster/Solana%20Black.png",
    "Trezor" => "https://ik.imagekit.io/blockster/Trezor%20Black.png"
  }

  def category_icon(slug), do: Map.get(@category_icons, slug)

  # Brand icon lookup - case-insensitive to handle database variations
  def brand_icon(brand) when is_binary(brand) do
    normalized = brand |> String.trim() |> String.downcase()
    Enum.find_value(@brand_icons, fn {key, url} ->
      if String.downcase(key) == normalized, do: url
    end)
  end
  def brand_icon(_), do: nil

  @impl true
  def mount(_params, _session, socket) do
    # Load all active products with associations
    all_products = Shop.list_active_products(preload: [:images, :variants, :hub, :artist_record, :categories, :product_tags])

    # Total slots = total active products
    total_slots = length(all_products)

    # Build products map for quick lookup by ID
    products_by_id = Map.new(all_products, fn p -> {to_string(p.id), p} end)

    # Get slot assignments and build display list
    display_slots = build_display_slots(total_slots, products_by_id)

    # Build slot assignments map for product picker (product_id => [slot_numbers])
    slot_assignments = build_slot_assignments(display_slots)

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
    # Normalize and deduplicate by lowercase to handle case variations (e.g., "Nike" vs "nike")
    brands_with_products =
      all_products
      |> Enum.map(& &1.vendor)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.uniq_by(&String.downcase/1)  # Dedupe by lowercase but keep original casing
      |> Enum.sort_by(&String.downcase/1)  # Sort case-insensitively

    {:ok,
     socket
     |> assign(:page_title, "Shop - Browse Products")
     |> assign(:all_products, all_products)
     |> assign(:products_by_id, products_by_id)
     |> assign(:total_slots, total_slots)
     |> assign(:display_slots, display_slots)
     |> assign(:slot_assignments, slot_assignments)
     |> assign(:filtered_products, nil)
     |> assign(:categories_with_products, categories_with_products)
     |> assign(:hubs_with_products, hubs_with_products)
     |> assign(:brands_with_products, brands_with_products)
     |> assign(:active_filter, nil)
     |> assign(:show_product_picker, false)
     |> assign(:picking_slot, nil)
     |> assign(:show_mobile_filters, false)}
  end

  # Build display slots list: [{slot_number, product_or_nil}, ...]
  defp build_display_slots(total_slots, products_by_id) do
    ShopSlots.build_display_list(total_slots)
    |> Enum.map(fn {slot_number, product_id} ->
      product = if product_id, do: Map.get(products_by_id, product_id), else: nil
      transformed = if product, do: transform_product(product), else: nil
      {slot_number, transformed}
    end)
  end

  # Build slot assignments map: %{product_id => [slot_numbers]}
  defp build_slot_assignments(display_slots) do
    display_slots
    |> Enum.filter(fn {_slot, product} -> product != nil end)
    |> Enum.reduce(%{}, fn {slot_number, product}, acc ->
      product_id = to_string(product.id)
      Map.update(acc, product_id, [slot_number], fn slots -> [slot_number | slots] end)
    end)
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

  # === URL PARAMS HANDLING ===

  @impl true
  def handle_params(params, _uri, socket) do
    socket = apply_url_filters(socket, params)
    {:noreply, socket}
  end

  defp apply_url_filters(socket, params) do
    cond do
      # Category filter from URL
      category_slug = params["category"] ->
        category = Enum.find(socket.assigns.categories_with_products, &(&1.slug == category_slug))
        if category do
          filtered = socket.assigns.all_products
          |> Enum.filter(fn p -> Enum.any?(p.categories || [], &(&1.slug == category_slug)) end)
          |> Enum.map(&transform_product/1)

          socket
          |> assign(:active_filter, {:category, category_slug, category.name})
          |> assign(:filtered_products, filtered)
        else
          socket
        end

      # Hub filter from URL
      hub_slug = params["hub"] ->
        hub = Enum.find(socket.assigns.hubs_with_products, &(&1.slug == hub_slug))
        if hub do
          filtered = socket.assigns.all_products
          |> Enum.filter(fn p -> p.hub && p.hub.slug == hub_slug end)
          |> Enum.map(&transform_product/1)

          socket
          |> assign(:active_filter, {:hub, hub_slug, hub.name})
          |> assign(:filtered_products, filtered)
        else
          socket
        end

      # Brand filter from URL
      brand = params["brand"] ->
        if brand in socket.assigns.brands_with_products do
          filtered = socket.assigns.all_products
          |> Enum.filter(fn p -> p.vendor == brand end)
          |> Enum.map(&transform_product/1)

          socket
          |> assign(:active_filter, {:brand, brand})
          |> assign(:filtered_products, filtered)
        else
          socket
        end

      # Artist filter from URL
      artist_slug = params["artist"] ->
        filtered = socket.assigns.all_products
        |> Enum.filter(fn p ->
          artist_record = if Ecto.assoc_loaded?(p.artist_record), do: p.artist_record, else: nil
          artist_record && artist_record.slug == artist_slug
        end)

        if Enum.any?(filtered) do
          artist_name = case List.first(filtered) do
            p when not is_nil(p) ->
              artist_record = if Ecto.assoc_loaded?(p.artist_record), do: p.artist_record, else: nil
              if artist_record, do: artist_record.name, else: p.artist
            _ -> artist_slug
          end

          socket
          |> assign(:active_filter, {:artist, artist_slug, artist_name})
          |> assign(:filtered_products, Enum.map(filtered, &transform_product/1))
        else
          socket
        end

      # Tag filter from URL
      tag_slug = params["tag"] ->
        filtered = socket.assigns.all_products
        |> Enum.filter(fn p ->
          product_tags = if Ecto.assoc_loaded?(p.product_tags), do: p.product_tags, else: []
          Enum.any?(product_tags, &(&1.slug == tag_slug))
        end)
        |> Enum.map(&transform_product/1)

        if Enum.any?(filtered) do
          socket
          |> assign(:active_filter, {:tag, tag_slug})
          |> assign(:filtered_products, filtered)
        else
          socket
        end

      # No filter - show all
      true ->
        socket
        |> assign(:active_filter, nil)
        |> assign(:filtered_products, nil)
    end
  end

  # === FILTER EVENT HANDLERS ===

  @impl true
  def handle_event("filter_by_category", %{"slug" => slug, "name" => name}, socket) do
    filtered = socket.assigns.all_products
    |> Enum.filter(fn p -> Enum.any?(p.categories || [], &(&1.slug == slug)) end)
    |> Enum.map(&transform_product/1)

    {:noreply,
     socket
     |> assign(:active_filter, {:category, slug, name})
     |> assign(:filtered_products, filtered)
     |> assign(:show_mobile_filters, false)}
  end

  @impl true
  def handle_event("filter_by_hub", %{"slug" => slug, "name" => name}, socket) do
    filtered = socket.assigns.all_products
    |> Enum.filter(fn p -> p.hub && p.hub.slug == slug end)
    |> Enum.map(&transform_product/1)

    {:noreply,
     socket
     |> assign(:active_filter, {:hub, slug, name})
     |> assign(:filtered_products, filtered)
     |> assign(:show_mobile_filters, false)}
  end

  @impl true
  def handle_event("filter_by_brand", %{"brand" => brand}, socket) do
    filtered = socket.assigns.all_products
    |> Enum.filter(fn p -> p.vendor == brand end)
    |> Enum.map(&transform_product/1)

    {:noreply,
     socket
     |> assign(:active_filter, {:brand, brand})
     |> assign(:filtered_products, filtered)
     |> assign(:show_mobile_filters, false)}
  end

  @impl true
  def handle_event("clear_all_filters", _params, socket) do
    {:noreply,
     socket
     |> assign(:active_filter, nil)
     |> assign(:filtered_products, nil)
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

    # Save to Mnesia - this ONLY affects this one slot
    ShopSlots.set_slot(slot, product_id)

    # Rebuild display slots
    display_slots = build_display_slots(
      socket.assigns.total_slots,
      socket.assigns.products_by_id
    )

    # Rebuild slot assignments for product picker
    slot_assignments = build_slot_assignments(display_slots)

    {:noreply,
     socket
     |> assign(:display_slots, display_slots)
     |> assign(:slot_assignments, slot_assignments)
     |> assign(:show_product_picker, false)
     |> assign(:picking_slot, nil)}
  end

  # === MOBILE FILTER EVENT HANDLERS ===

  @impl true
  def handle_event("toggle_mobile_filters", _params, socket) do
    {:noreply, assign(socket, :show_mobile_filters, !socket.assigns.show_mobile_filters)}
  end
end
