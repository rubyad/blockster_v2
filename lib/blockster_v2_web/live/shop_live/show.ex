defmodule BlocksterV2Web.ShopLive.Show do
  use BlocksterV2Web, :live_view

  alias BlocksterV2.Shop
  alias BlocksterV2.Repo
  alias BlocksterV2.EngagementTracker

  # 1 BUX/token = $0.10
  @token_value_usd 0.10

  # Size ordering (S, M, L, XL)
  @size_order %{"S" => 1, "M" => 2, "L" => 3, "XL" => 4, "XXL" => 5}

  # Color name to hex code mapping
  @color_hex_map %{
    "White" => "#FFFFFF",
    "Black" => "#000000",
    "Grey" => "#808080",
    "Beige" => "#F5F5DC",
    "Light Blue" => "#ADD8E6",
    "Orange" => "#FFA500",
    "Pink" => "#FFC0CB",
    "Red" => "#FF0000",
    "Navy Blue" => "#000080",
    "Royal Blue" => "#4169E1",
    "Green" => "#008000",
    "Lime" => "#00FF00",
    "Yellow" => "#FFFF00",
    "Lavender" => "#E6E6FA"
  }

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
                  |> Repo.preload([{:images, images_query}, {:variants, variants_query}, :hub, :categories, :product_tags])
                  |> transform_product()

        # Fetch user balances if logged in
        user_id = case socket.assigns[:current_user] do
          nil -> nil
          user -> user.id
        end

        # Get actual BUX token balance (not aggregate) and hub token balance
        {user_bux_balance, user_hub_token_balance} = if user_id do
          token_balances = EngagementTracker.get_user_token_balances(user_id) || %{}
          bux = Map.get(token_balances, "BUX", 0) |> to_float()
          hub = if product.hub_token do
            Map.get(token_balances, product.hub_token, 0) |> to_float()
          else
            0.0
          end
          {bux, hub}
        else
          {0.0, 0.0}
        end

        # Combined total balance for redemption
        combined_balance = user_bux_balance + user_hub_token_balance

        # Calculate max tokens based on product discount settings
        # Use the higher of the two max discounts for the combined limit
        bux_discount = (product.bux_max_discount || 0) |> to_float()
        hub_discount = (product.hub_token_max_discount || 0) |> to_float()
        product_price = (product.price || 0) |> to_float()
        max_discount_percent = max(bux_discount, hub_discount)
        max_combined_tokens = if max_discount_percent > 0 do
          (product_price * max_discount_percent / 100) / @token_value_usd
        else
          0.0
        end

        # Default tokens to redeem is the lesser of combined balance and max allowed
        default_tokens = min(combined_balance, max_combined_tokens) |> to_float()

        # Allocate default tokens: prioritize hub tokens first, then BUX
        {default_hub_to_redeem, default_bux_to_redeem} = allocate_tokens(
          default_tokens,
          user_hub_token_balance,
          user_bux_balance
        )

        {:ok,
         socket
         |> assign(:page_title, product.name)
         |> assign(:product, product)
         |> assign(:quantity, 1)
         |> assign(:selected_size, nil)
         |> assign(:selected_color, nil)
         |> assign(:current_image_index, 0)
         |> assign(:user_bux_balance, user_bux_balance)
         |> assign(:user_hub_token_balance, user_hub_token_balance)
         |> assign(:max_combined_tokens, max_combined_tokens / 1)
         |> assign(:tokens_to_redeem, default_tokens)
         |> assign(:bux_to_redeem, default_bux_to_redeem)
         |> assign(:hub_to_redeem, default_hub_to_redeem)
         |> assign(:show_allocation_dropdown, false)
         |> assign(:show_discount_breakdown, false)
         |> assign(:color_hex_map, @color_hex_map)
         |> assign(:token_value_usd, @token_value_usd)}
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

    # Get all images
    images = Enum.map(db_product.images || [], fn img -> img.src end)

    # Get sizes from variants (option1), sorted in order S, M, L, XL
    sizes = (db_product.variants || [])
            |> Enum.map(fn v -> v.option1 end)
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()
            |> Enum.sort_by(fn size -> Map.get(@size_order, size, 99) end)

    # Get colors from variants (option2)
    colors = (db_product.variants || [])
            |> Enum.map(fn v -> v.option2 end)
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()

    # Get discount percentages from product
    bux_max_discount = db_product.bux_max_discount || 0
    hub_token_max_discount = db_product.hub_token_max_discount || 0

    # Calculate max tokens needed for each discount
    # Formula: (price * discount_percent / 100) / token_value
    # e.g., $220 * 50% = $110 discount = 11,000 BUX at $0.01 each
    max_bux_tokens = if bux_max_discount > 0 do
      round((price * bux_max_discount / 100) / @token_value_usd)
    else
      0
    end

    max_hub_tokens = if hub_token_max_discount > 0 do
      round((price * hub_token_max_discount / 100) / @token_value_usd)
    else
      0
    end

    # Get hub info if available
    hub = if Ecto.assoc_loaded?(db_product.hub) && db_product.hub, do: db_product.hub, else: nil

    # Get categories
    categories = if Ecto.assoc_loaded?(db_product.categories) do
      Enum.map(db_product.categories, fn cat -> %{name: cat.name, slug: cat.slug} end)
    else
      []
    end

    # Get product tags (many-to-many association)
    product_tags = if Ecto.assoc_loaded?(db_product.product_tags) do
      Enum.map(db_product.product_tags, fn tag -> %{name: tag.name, slug: tag.slug} end)
    else
      []
    end

    %{
      id: db_product.id,
      name: db_product.title,
      slug: db_product.handle,
      price: price,
      image: if(first_image, do: first_image.src, else: "https://via.placeholder.com/500x500?text=No+Image"),
      images: images,
      bux_max_discount: bux_max_discount,
      max_bux_tokens: max_bux_tokens,
      hub_token_max_discount: hub_token_max_discount,
      max_hub_tokens: max_hub_tokens,
      hub_name: if(hub, do: hub.name, else: nil),
      hub_slug: if(hub, do: hub.slug, else: nil),
      hub_token: if(hub, do: hub.token, else: nil),
      hub_logo_url: if(hub, do: hub.logo_url, else: nil),
      product_type: db_product.product_type,
      categories: categories,
      product_tags: product_tags,
      tags: db_product.tags || [],
      description: db_product.body_html || "Premium product from the Blockster shop.",
      features: [],
      sizes: if(Enum.empty?(sizes), do: ["S", "M", "L", "XL", "XXL"], else: sizes),
      colors: colors,
      artist: db_product.artist,
      collection_name: db_product.collection_name,
      max_inventory: db_product.max_inventory,
      sold_count: db_product.sold_count || 0
    }
  end

  defp to_float(value) when is_float(value), do: value
  defp to_float(value) when is_integer(value), do: value / 1
  defp to_float(nil), do: 0.0
  defp to_float(_), do: 0.0

  # Allocate tokens: prioritize hub tokens first, then BUX
  defp allocate_tokens(total, hub_balance, bux_balance) do
    hub_to_use = min(total, hub_balance)
    remaining = total - hub_to_use
    bux_to_use = min(remaining, bux_balance)
    {hub_to_use, bux_to_use}
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
  def handle_event("select_color", %{"color" => color}, socket) do
    {:noreply, assign(socket, :selected_color, color)}
  end

  @impl true
  def handle_event("update_tokens", %{"tokens" => tokens_str}, socket) do
    # Parse the input value as float to support fractional tokens
    tokens = case Float.parse(tokens_str) do
      {n, _} -> max(0.0, n)
      :error -> 0.0
    end

    # Combined balance and max tokens
    combined_balance = socket.assigns.user_bux_balance + socket.assigns.user_hub_token_balance
    max_tokens = socket.assigns.max_combined_tokens

    # Clamp to max allowed and combined balance
    clamped_tokens = min(tokens, min(max_tokens, combined_balance))

    # Reallocate tokens: prioritize hub tokens first, then BUX
    {hub_to_redeem, bux_to_redeem} = allocate_tokens(
      clamped_tokens,
      socket.assigns.user_hub_token_balance,
      socket.assigns.user_bux_balance
    )

    {:noreply,
     socket
     |> assign(:tokens_to_redeem, clamped_tokens)
     |> assign(:hub_to_redeem, hub_to_redeem)
     |> assign(:bux_to_redeem, bux_to_redeem)}
  end

  @impl true
  def handle_event("use_max_tokens", _, socket) do
    # Combined balance and max tokens
    combined_balance = socket.assigns.user_bux_balance + socket.assigns.user_hub_token_balance
    max_tokens = socket.assigns.max_combined_tokens
    clamped_tokens = min(combined_balance, max_tokens)

    # Reallocate tokens: prioritize hub tokens first, then BUX
    {hub_to_redeem, bux_to_redeem} = allocate_tokens(
      clamped_tokens,
      socket.assigns.user_hub_token_balance,
      socket.assigns.user_bux_balance
    )

    {:noreply,
     socket
     |> assign(:tokens_to_redeem, clamped_tokens)
     |> assign(:hub_to_redeem, hub_to_redeem)
     |> assign(:bux_to_redeem, bux_to_redeem)}
  end

  @impl true
  def handle_event("show_allocation_dropdown", _, socket) do
    {:noreply, assign(socket, :show_allocation_dropdown, true)}
  end

  @impl true
  def handle_event("hide_allocation_dropdown", _, socket) do
    {:noreply, assign(socket, :show_allocation_dropdown, false)}
  end

  @impl true
  def handle_event("toggle_discount_breakdown", _, socket) do
    {:noreply, assign(socket, :show_discount_breakdown, !socket.assigns.show_discount_breakdown)}
  end

  @impl true
  def handle_event("update_bux_allocation", %{"bux" => bux_str}, socket) do
    bux = case Float.parse(bux_str) do
      {n, _} -> max(0.0, n)
      :error -> 0.0
    end

    # Clamp to user's BUX balance
    clamped_bux = min(bux, socket.assigns.user_bux_balance)

    # Calculate new total
    new_total = clamped_bux + socket.assigns.hub_to_redeem

    # Clamp total to max allowed
    max_tokens = socket.assigns.max_combined_tokens
    if new_total > max_tokens do
      # Reduce BUX to fit within max
      adjusted_bux = max(0.0, max_tokens - socket.assigns.hub_to_redeem)
      {:noreply,
       socket
       |> assign(:bux_to_redeem, adjusted_bux)
       |> assign(:tokens_to_redeem, adjusted_bux + socket.assigns.hub_to_redeem)}
    else
      {:noreply,
       socket
       |> assign(:bux_to_redeem, clamped_bux)
       |> assign(:tokens_to_redeem, new_total)}
    end
  end

  @impl true
  def handle_event("update_hub_allocation", %{"hub" => hub_str}, socket) do
    hub = case Float.parse(hub_str) do
      {n, _} -> max(0.0, n)
      :error -> 0.0
    end

    # Clamp to user's hub token balance
    clamped_hub = min(hub, socket.assigns.user_hub_token_balance)

    # Calculate new total
    new_total = clamped_hub + socket.assigns.bux_to_redeem

    # Clamp total to max allowed
    max_tokens = socket.assigns.max_combined_tokens
    if new_total > max_tokens do
      # Reduce BUX to fit within max (keep hub amount, reduce BUX)
      adjusted_bux = max(0.0, max_tokens - clamped_hub)
      {:noreply,
       socket
       |> assign(:hub_to_redeem, clamped_hub)
       |> assign(:bux_to_redeem, adjusted_bux)
       |> assign(:tokens_to_redeem, clamped_hub + adjusted_bux)}
    else
      {:noreply,
       socket
       |> assign(:hub_to_redeem, clamped_hub)
       |> assign(:tokens_to_redeem, new_total)}
    end
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
