defmodule BlocksterV2Web.ShopLive.Index do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Shop
  alias BlocksterV2.Blog

  @impl true
  def mount(_params, _session, socket) do
    # Load filter options from database
    hubs = Blog.list_hubs()
    artists = Shop.list_artists()
    categories = Shop.list_categories()

    # Load active products from database with preloads
    db_products = Shop.list_active_products(preload: [:images, :variants, :hub, :artist_record, :categories])

    # Transform database products to display format, falling back to sample products if empty
    products = case db_products do
      [] -> get_sample_products()
      _ -> Enum.map(db_products, &transform_product/1)
    end

    {:ok,
     socket
     |> assign(:page_title, "Shop - Browse Products")
     |> assign(:all_products, products)
     |> assign(:products, products)
     |> assign(:hubs, hubs)
     |> assign(:artists, artists)
     |> assign(:categories, categories)
     |> assign(:show_hub_dropdown, false)
     |> assign(:show_artist_dropdown, false)
     |> assign(:show_category_dropdown, false)
     |> assign(:hub_search, "")
     |> assign(:artist_search, "")
     |> assign(:category_search, "")
     |> assign(:selected_hub, nil)
     |> assign(:selected_artist, nil)
     |> assign(:selected_category, nil)}
  end

  # Token value: 1 token = $0.10 discount
  @token_value_usd 0.10

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

  @impl true
  def handle_event("toggle_dropdown", %{"filter" => filter}, socket) do
    case filter do
      "hub" ->
        {:noreply,
         assign(socket,
           show_hub_dropdown: !socket.assigns.show_hub_dropdown,
           show_artist_dropdown: false,
           show_category_dropdown: false
         )}

      "artist" ->
        {:noreply,
         assign(socket,
           show_artist_dropdown: !socket.assigns.show_artist_dropdown,
           show_hub_dropdown: false,
           show_category_dropdown: false
         )}

      "category" ->
        {:noreply,
         assign(socket,
           show_category_dropdown: !socket.assigns.show_category_dropdown,
           show_hub_dropdown: false,
           show_artist_dropdown: false
         )}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("update_search", %{"filter" => filter, "value" => value}, socket) do
    case filter do
      "hub" ->
        {:noreply, assign(socket, :hub_search, value)}

      "artist" ->
        {:noreply, assign(socket, :artist_search, value)}

      "category" ->
        {:noreply, assign(socket, :category_search, value)}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_option", %{"filter" => filter, "slug" => slug, "name" => name}, socket) do
    socket = case filter do
      "hub" ->
        assign(socket,
          selected_hub: %{slug: slug, name: name},
          show_hub_dropdown: false
        )

      "artist" ->
        assign(socket,
          selected_artist: %{slug: slug, name: name},
          show_artist_dropdown: false
        )

      "category" ->
        assign(socket,
          selected_category: %{slug: slug, name: name},
          show_category_dropdown: false
        )

      _ ->
        socket
    end

    {:noreply, filter_products(socket)}
  end

  @impl true
  def handle_event("clear_filter", %{"filter" => filter}, socket) do
    socket = case filter do
      "hub" ->
        assign(socket, :selected_hub, nil)

      "artist" ->
        assign(socket, :selected_artist, nil)

      "category" ->
        assign(socket, :selected_category, nil)

      _ ->
        socket
    end

    {:noreply, filter_products(socket)}
  end

  @impl true
  def handle_event("clear_all_filters", _, socket) do
    {:noreply,
     socket
     |> assign(:selected_hub, nil)
     |> assign(:selected_artist, nil)
     |> assign(:selected_category, nil)
     |> filter_products()}
  end

  @impl true
  def handle_event("close_dropdown", %{"filter" => filter}, socket) do
    case filter do
      "hub" ->
        {:noreply, assign(socket, :show_hub_dropdown, false)}

      "artist" ->
        {:noreply, assign(socket, :show_artist_dropdown, false)}

      "category" ->
        {:noreply, assign(socket, :show_category_dropdown, false)}

      _ ->
        {:noreply, socket}
    end
  end

  defp filter_products(socket) do
    products = socket.assigns.all_products

    products = if socket.assigns.selected_hub do
      Enum.filter(products, fn p -> p.hub_slug == socket.assigns.selected_hub.slug end)
    else
      products
    end

    products = if socket.assigns.selected_artist do
      Enum.filter(products, fn p -> p.artist_slug == socket.assigns.selected_artist.slug end)
    else
      products
    end

    products = if socket.assigns.selected_category do
      Enum.filter(products, fn p -> socket.assigns.selected_category.slug in p.category_slugs end)
    else
      products
    end

    assign(socket, :products, products)
  end

  defp has_active_filters?(socket) do
    socket.assigns.selected_hub != nil ||
    socket.assigns.selected_artist != nil ||
    socket.assigns.selected_category != nil
  end

  defp get_sample_products do
    [
      %{
        id: 1,
        name: "Cargo Comfort Pants",
        slug: "cargo-comfort-pants",
        price: 50.00,
        original_price: 65.00,
        max_discounted_price: 25.00,
        bux_max_discount: 25,
        hub_token_max_discount: 25,
        total_max_discount: 50,
        image: "https://ik.imagekit.io/blockster/coming-soon-card-image1.png?tr=w-500",
        images: ["https://ik.imagekit.io/blockster/coming-soon-card-image1.png?tr=w-500", "https://ik.imagekit.io/blockster/coming-soon-card-image2.png?tr=w-500"],
        hub_logo: "https://ik.imagekit.io/blockster/moon-logo.png",
        hub_name: "MoonPay",
        hub_slug: nil,
        artist_slug: nil,
        artist_name: nil,
        category_slugs: []
      },
      %{
        id: 2,
        name: "Unofficial Cargo Pants",
        slug: "unofficial-cargo-pants",
        price: 50.00,
        original_price: 65.00,
        max_discounted_price: 25.00,
        bux_max_discount: 25,
        hub_token_max_discount: 25,
        total_max_discount: 50,
        image: "https://ik.imagekit.io/blockster/coming-soon-card-image2.png?tr=w-500",
        images: ["https://ik.imagekit.io/blockster/coming-soon-card-image2.png?tr=w-500", "https://ik.imagekit.io/blockster/coming-soon-card-image1.png?tr=w-500"],
        hub_logo: nil,
        hub_name: nil,
        hub_slug: nil,
        artist_slug: nil,
        artist_name: nil,
        category_slugs: []
      },
      %{
        id: 3,
        name: "Blockster Sneakers",
        slug: "blockster-sneakers",
        price: 50.00,
        original_price: 65.00,
        max_discounted_price: 25.00,
        bux_max_discount: 25,
        hub_token_max_discount: 25,
        total_max_discount: 50,
        image: "https://ik.imagekit.io/blockster/coming-soon-shoe.png?tr=w-500",
        images: ["https://ik.imagekit.io/blockster/coming-soon-shoe.png?tr=w-500", "https://ik.imagekit.io/blockster/hoode-comnmg-soon.png"],
        hub_logo: "https://ik.imagekit.io/blockster/neo-logo.png",
        hub_name: "Neo",
        hub_slug: nil,
        artist_slug: nil,
        artist_name: nil,
        category_slugs: []
      },
      %{
        id: 4,
        name: "Unofficial Standard Hoodie",
        slug: "unofficial-standard-hoodie",
        price: 50.00,
        original_price: 65.00,
        max_discounted_price: 0.00,
        bux_max_discount: 50,
        hub_token_max_discount: 50,
        total_max_discount: 100,
        image: "https://ik.imagekit.io/blockster/hoode-comnmg-soon.png",
        images: ["https://ik.imagekit.io/blockster/hoode-comnmg-soon.png", "https://ik.imagekit.io/blockster/coming-soon-shoe.png?tr=w-500"],
        hub_logo: "https://ik.imagekit.io/blockster/rogue-logo.png",
        hub_name: "Rogue",
        hub_slug: nil,
        artist_slug: nil,
        artist_name: nil,
        category_slugs: []
      },
      %{
        id: 5,
        name: "Crypto Street Jacket",
        slug: "crypto-street-jacket",
        price: 75.00,
        original_price: 95.00,
        max_discounted_price: 56.25,
        bux_max_discount: 15,
        hub_token_max_discount: 10,
        total_max_discount: 25,
        image: "https://ik.imagekit.io/blockster/coming-soon-card-image1.png?tr=w-500",
        images: ["https://ik.imagekit.io/blockster/coming-soon-card-image1.png?tr=w-500", "https://ik.imagekit.io/blockster/coming-soon-card-image2.png?tr=w-500"],
        hub_logo: nil,
        hub_name: nil,
        hub_slug: nil,
        artist_slug: nil,
        artist_name: nil,
        category_slugs: []
      },
      %{
        id: 6,
        name: "Blockster Classic Tee",
        slug: "blockster-classic-tee",
        price: 35.00,
        original_price: 45.00,
        max_discounted_price: 17.50,
        bux_max_discount: 25,
        hub_token_max_discount: 25,
        total_max_discount: 50,
        image: "https://ik.imagekit.io/blockster/coming-soon-card-image2.png?tr=w-500",
        images: ["https://ik.imagekit.io/blockster/coming-soon-card-image2.png?tr=w-500", "https://ik.imagekit.io/blockster/coming-soon-card-image1.png?tr=w-500"],
        hub_logo: "https://ik.imagekit.io/blockster/moon-logo.png",
        hub_name: "MoonPay",
        hub_slug: nil,
        artist_slug: nil,
        artist_name: nil,
        category_slugs: []
      },
      %{
        id: 7,
        name: "Web3 Cap",
        slug: "web3-cap",
        price: 25.00,
        original_price: 35.00,
        max_discounted_price: 12.50,
        bux_max_discount: 25,
        hub_token_max_discount: 25,
        total_max_discount: 50,
        image: "https://ik.imagekit.io/blockster/coming-soon-shoe.png?tr=w-500",
        images: ["https://ik.imagekit.io/blockster/coming-soon-shoe.png?tr=w-500", "https://ik.imagekit.io/blockster/hoode-comnmg-soon.png"],
        hub_logo: nil,
        hub_name: nil,
        hub_slug: nil,
        artist_slug: nil,
        artist_name: nil,
        category_slugs: []
      },
      %{
        id: 8,
        name: "NFT Collector Backpack",
        slug: "nft-collector-backpack",
        price: 85.00,
        original_price: 110.00,
        max_discounted_price: 42.50,
        bux_max_discount: 25,
        hub_token_max_discount: 25,
        total_max_discount: 50,
        image: "https://ik.imagekit.io/blockster/hoode-comnmg-soon.png",
        images: ["https://ik.imagekit.io/blockster/hoode-comnmg-soon.png", "https://ik.imagekit.io/blockster/coming-soon-card-image1.png?tr=w-500"],
        hub_logo: "https://ik.imagekit.io/blockster/neo-logo.png",
        hub_name: "Neo",
        hub_slug: nil,
        artist_slug: nil,
        artist_name: nil,
        category_slugs: []
      },
      %{
        id: 9,
        name: "Decentralized Joggers",
        slug: "decentralized-joggers",
        price: 60.00,
        original_price: 80.00,
        max_discounted_price: 30.00,
        bux_max_discount: 25,
        hub_token_max_discount: 25,
        total_max_discount: 50,
        image: "https://ik.imagekit.io/blockster/coming-soon-card-image1.png?tr=w-500",
        images: ["https://ik.imagekit.io/blockster/coming-soon-card-image1.png?tr=w-500", "https://ik.imagekit.io/blockster/coming-soon-card-image2.png?tr=w-500"],
        hub_logo: nil,
        hub_name: nil,
        hub_slug: nil,
        artist_slug: nil,
        artist_name: nil,
        category_slugs: []
      },
      %{
        id: 10,
        name: "Blockchain Bomber",
        slug: "blockchain-bomber",
        price: 90.00,
        original_price: 120.00,
        max_discounted_price: 45.00,
        bux_max_discount: 25,
        hub_token_max_discount: 25,
        total_max_discount: 50,
        image: "https://ik.imagekit.io/blockster/coming-soon-card-image2.png?tr=w-500",
        images: ["https://ik.imagekit.io/blockster/coming-soon-card-image2.png?tr=w-500", "https://ik.imagekit.io/blockster/hoode-comnmg-soon.png"],
        hub_logo: "https://ik.imagekit.io/blockster/rogue-logo.png",
        hub_name: "Rogue",
        hub_slug: nil,
        artist_slug: nil,
        artist_name: nil,
        category_slugs: []
      },
      %{
        id: 11,
        name: "Smart Contract Socks",
        slug: "smart-contract-socks",
        price: 15.00,
        original_price: 20.00,
        max_discounted_price: 7.50,
        bux_max_discount: 25,
        hub_token_max_discount: 25,
        total_max_discount: 50,
        image: "https://ik.imagekit.io/blockster/coming-soon-shoe.png?tr=w-500",
        images: ["https://ik.imagekit.io/blockster/coming-soon-shoe.png?tr=w-500", "https://ik.imagekit.io/blockster/coming-soon-card-image1.png?tr=w-500"],
        hub_logo: nil,
        hub_name: nil,
        hub_slug: nil,
        artist_slug: nil,
        artist_name: nil,
        category_slugs: []
      },
      %{
        id: 12,
        name: "DeFi Denim Jacket",
        slug: "defi-denim-jacket",
        price: 95.00,
        original_price: 125.00,
        max_discounted_price: 47.50,
        bux_max_discount: 25,
        hub_token_max_discount: 25,
        total_max_discount: 50,
        image: "https://ik.imagekit.io/blockster/hoode-comnmg-soon.png",
        images: ["https://ik.imagekit.io/blockster/hoode-comnmg-soon.png", "https://ik.imagekit.io/blockster/coming-soon-card-image2.png?tr=w-500"],
        hub_logo: "https://ik.imagekit.io/blockster/moon-logo.png",
        hub_name: "MoonPay",
        hub_slug: nil,
        artist_slug: nil,
        artist_name: nil,
        category_slugs: []
      }
    ]
  end
end
