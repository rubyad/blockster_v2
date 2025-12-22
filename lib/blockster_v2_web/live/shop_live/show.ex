defmodule BlocksterV2Web.ShopLive.Show do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Shop
  alias BlocksterV2.Repo

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Shop.get_product_by_handle(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Product not found")
         |> redirect(to: ~p"/shop")}

      db_product ->
        import Ecto.Query
        images_query = from(i in BlocksterV2.Shop.ProductImage, order_by: i.position)
        variants_query = from(v in BlocksterV2.Shop.ProductVariant, order_by: v.position)

        product = db_product
                  |> Repo.preload([{:images, images_query}, {:variants, variants_query}, :hub])
                  |> transform_product()

        {:ok,
         socket
         |> assign(:page_title, product.name)
         |> assign(:product, product)
         |> assign(:quantity, 1)
         |> assign(:selected_size, nil)
         |> assign(:current_image_index, 0)}
    end
  end

  defp transform_product(db_product) do
    first_variant = List.first(db_product.variants || [])
    first_image = List.first(db_product.images || [])

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

    discount_percent = if compare_price > 0 && compare_price > price do
      round((1 - price / compare_price) * 100)
    else
      db_product.bux_max_discount || 0
    end

    # Get all images
    images = Enum.map(db_product.images || [], fn img -> img.src end)

    # Get sizes from variants
    sizes = (db_product.variants || [])
            |> Enum.map(fn v -> v.option1 end)
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()

    %{
      id: db_product.id,
      name: db_product.title,
      slug: db_product.handle,
      price: price,
      original_price: compare_price,
      image: if(first_image, do: first_image.src, else: "https://via.placeholder.com/500x500?text=No+Image"),
      images: images,
      bux_discount: round(price * 25.28),
      discount_percent: max(discount_percent, db_product.bux_max_discount || 0),
      description: db_product.body_html || "Premium product from the Blockster shop.",
      features: [],
      sizes: if(Enum.empty?(sizes), do: ["S", "M", "L", "XL", "XXL"], else: sizes)
    }
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

  @impl true
  def handle_event("select_image", %{"index" => index}, socket) do
    {:noreply, assign(socket, :current_image_index, String.to_integer(index))}
  end

  @impl true
  def handle_event("next_image", _, socket) do
    images = socket.assigns.product.images
    current = socket.assigns.current_image_index
    next_index = rem(current + 1, max(length(images), 1))
    {:noreply, assign(socket, :current_image_index, next_index)}
  end

  @impl true
  def handle_event("prev_image", _, socket) do
    images = socket.assigns.product.images
    current = socket.assigns.current_image_index
    total = max(length(images), 1)
    prev_index = rem(current - 1 + total, total)
    {:noreply, assign(socket, :current_image_index, prev_index)}
  end
end
