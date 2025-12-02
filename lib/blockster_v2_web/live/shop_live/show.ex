defmodule BlocksterV2Web.ShopLive.Show do
  use BlocksterV2Web, :live_view

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case get_product_by_slug(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Product not found")
         |> redirect(to: ~p"/shop")}

      product ->
        {:ok,
         socket
         |> assign(:page_title, product.name)
         |> assign(:product, product)
         |> assign(:quantity, 1)
         |> assign(:selected_size, nil)}
    end
  end

  @impl true
  def handle_event("increment_quantity", _, socket) do
    {:noreply, assign(socket, :quantity, socket.assigns.quantity + 1)}
  end

  @impl true
  def handle_event("decrement_quantity", _, socket) do
    new_quantity = max(1, socket.assigns.quantity - 1)
    {:noreply, assign(socket, :quantity, new_quantity)}
  end

  @impl true
  def handle_event("select_size", %{"size" => size}, socket) do
    {:noreply, assign(socket, :selected_size, size)}
  end

  @impl true
  def handle_event("add_to_cart", _, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Coming soon! Product will be added to cart.")}
  end

  defp get_product_by_slug(slug) do
    products = [
      %{
        id: 1,
        name: "Cargo Comfort Pants",
        slug: "cargo-comfort-pants",
        price: 50.00,
        original_price: 65.00,
        image: "https://ik.imagekit.io/blockster/coming-soon-card-image1.png?tr=w-500",
        bux_discount: 1264,
        discount_percent: 25,
        description:
          "Premium cargo pants designed for the Web3 lifestyle. Comfortable, durable, and stylish.",
        features: [
          "100% organic cotton",
          "Multiple pockets for your essentials",
          "Adjustable waist",
          "Crypto-inspired design details"
        ],
        sizes: ["S", "M", "L", "XL", "XXL"]
      },
      %{
        id: 2,
        name: "Unofficial Cargo Pants",
        slug: "unofficial-cargo-pants",
        price: 50.00,
        original_price: 65.00,
        image: "https://ik.imagekit.io/blockster/coming-soon-card-image2.png?tr=w-500",
        bux_discount: 1264,
        discount_percent: 25,
        description:
          "Streetwear-inspired cargo pants perfect for everyday wear. Built for comfort and style.",
        features: [
          "Durable fabric",
          "Cargo pockets",
          "Relaxed fit",
          "Machine washable"
        ],
        sizes: ["S", "M", "L", "XL", "XXL"]
      },
      %{
        id: 3,
        name: "Blockster Sneakers",
        slug: "blockster-sneakers",
        price: 50.00,
        original_price: 65.00,
        image: "https://ik.imagekit.io/blockster/coming-soon-shoe.png?tr=w-500",
        bux_discount: 1264,
        discount_percent: 25,
        description:
          "Step into the future with these crypto-inspired sneakers. Comfort meets style.",
        features: [
          "Cushioned sole",
          "Breathable material",
          "Unique crypto-themed design",
          "Perfect for all-day wear"
        ],
        sizes: ["7", "8", "9", "10", "11", "12"]
      },
      %{
        id: 4,
        name: "Unofficial Standard Hoodie",
        slug: "unofficial-standard-hoodie",
        price: 50.00,
        original_price: 65.00,
        image: "https://ik.imagekit.io/blockster/hoode-comnmg-soon.png",
        bux_discount: 1264,
        discount_percent: 25,
        description:
          "Cozy hoodie perfect for those late-night coding sessions or casual outings.",
        features: [
          "Soft fleece interior",
          "Kangaroo pocket",
          "Adjustable hood",
          "Crypto logo detail"
        ],
        sizes: ["S", "M", "L", "XL", "XXL"]
      }
    ]

    Enum.find(products, &(&1.slug == slug))
  end
end
