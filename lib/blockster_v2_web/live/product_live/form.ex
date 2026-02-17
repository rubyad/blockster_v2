defmodule BlocksterV2Web.ProductLive.Form do
  use BlocksterV2Web, :live_view

  import Ecto.Query

  alias BlocksterV2.Shop
  alias BlocksterV2.Shop.{Product, ProductImage, ProductVariant, ProductConfig}
  alias BlocksterV2.Shop.SizePresets
  alias BlocksterV2.Blog
  alias BlocksterV2.Repo

  # Available sizes for checkbox selection (legacy — now driven by SizePresets via product_config)
  @available_sizes ["S", "M", "L", "XL"]

  # Available colors with their hex codes for checkbox selection
  @available_colors [
    {"White", "#FFFFFF"},
    {"Black", "#000000"},
    {"Grey", "#808080"},
    {"Beige", "#F5F5DC"},
    {"Light Blue", "#ADD8E6"},
    {"Orange", "#FFA500"},
    {"Pink", "#FFC0CB"},
    {"Red", "#FF0000"},
    {"Navy Blue", "#000080"},
    {"Royal Blue", "#4169E1"},
    {"Green", "#008000"},
    {"Lime", "#00FF00"},
    {"Yellow", "#FFFF00"},
    {"Lavender", "#E6E6FA"}
  ]

  @impl true
  def mount(params, _session, socket) do
    if socket.assigns.current_user && socket.assigns.current_user.is_admin do
      product =
        case params do
          %{"id" => id} ->
            Shop.get_product!(id)
            |> Repo.preload(ordered_preloads())

          _ ->
            %Product{status: "draft", images: [], categories: [], product_tags: [], variants: []}
        end

      changeset = Shop.change_product(product)
      form = to_form(changeset)
      hubs = Blog.list_hubs()
      categories = Shop.list_categories()
      tags = Shop.list_tags()

      # Get artist info if product has an artist_id
      selected_artist = if product.artist_id do
        Shop.get_artist(product.artist_id)
      else
        nil
      end

      # Extract selected sizes and colors from existing variants
      {selected_sizes, selected_colors, variant_price} = extract_variant_options(product.variants || [])

      # Load product config (or defaults for new products)
      product_config = if product.id, do: Shop.get_product_config(product.id), else: nil
      config_assigns = product_config_assigns(product_config)

      {:ok,
       socket
       |> assign(:product, product)
       |> assign(:form, form)
       |> assign(:hubs, hubs)
       |> assign(:categories, categories)
       |> assign(:tags, tags)
       |> assign(:images, product.images || [])
       |> assign(:variants, transform_variants(product.variants || []))
       |> assign(:selected_category_ids, get_selected_category_ids(product))
       |> assign(:selected_tag_ids, get_selected_tag_ids(product))
       |> assign(:selected_sizes, selected_sizes)
       |> assign(:selected_colors, selected_colors)
       |> assign(:variant_price, variant_price)
       |> assign(:available_sizes, @available_sizes)
       |> assign(:available_colors, @available_colors)
       |> assign(:selected_artist, selected_artist)
       |> assign(:artist_search, "")
       |> assign(:artist_suggestions, [])
       |> assign(:show_artist_dropdown, false)
       |> assign(:page_title, page_title(socket.assigns.live_action))
       |> assign(config_assigns)}
    else
      {:ok,
       socket
       |> put_flash(:error, "You must be an admin to access this page.")
       |> redirect(to: ~p"/")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Product")
    |> assign(:product, %Product{status: "draft", images: [], categories: [], product_tags: [], variants: []})
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    product = Shop.get_product!(id) |> Repo.preload(ordered_preloads())
    {selected_sizes, selected_colors, variant_price} = extract_variant_options(product.variants || [])

    # Get artist info if product has an artist_id
    selected_artist = if product.artist_id do
      Shop.get_artist(product.artist_id)
    else
      nil
    end

    # Load product config
    product_config = Shop.get_product_config(product.id)
    config_assigns = product_config_assigns(product_config)

    socket
    |> assign(:page_title, "Edit Product")
    |> assign(:product, product)
    |> assign(:images, product.images || [])
    |> assign(:variants, transform_variants(product.variants || []))
    |> assign(:selected_category_ids, get_selected_category_ids(product))
    |> assign(:selected_tag_ids, get_selected_tag_ids(product))
    |> assign(:selected_sizes, selected_sizes)
    |> assign(:selected_colors, selected_colors)
    |> assign(:variant_price, variant_price)
    |> assign(:selected_artist, selected_artist)
    |> assign(:artist_search, "")
    |> assign(:artist_suggestions, [])
    |> assign(:show_artist_dropdown, false)
    |> assign(config_assigns)
  end

  @impl true
  def handle_event("validate", %{"product" => product_params}, socket) do
    changeset =
      socket.assigns.product
      |> Shop.change_product(product_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  @impl true
  def handle_event("save", %{"product" => product_params}, socket) do
    # Extract category and tag IDs
    category_ids = socket.assigns.selected_category_ids
    tag_ids = socket.assigns.selected_tag_ids

    save_product(socket, socket.assigns.live_action, product_params, category_ids, tag_ids)
  end

  @impl true
  def handle_event("toggle_category", %{"category-id" => category_id}, socket) do
    category_id = category_id
    selected_category_ids = socket.assigns.selected_category_ids

    new_selected_category_ids =
      if category_id in selected_category_ids do
        List.delete(selected_category_ids, category_id)
      else
        [category_id | selected_category_ids]
      end

    {:noreply, assign(socket, :selected_category_ids, new_selected_category_ids)}
  end

  @impl true
  def handle_event("toggle_tag", %{"tag-id" => tag_id}, socket) do
    tag_id = tag_id
    selected_tag_ids = socket.assigns.selected_tag_ids

    new_selected_tag_ids =
      if tag_id in selected_tag_ids do
        List.delete(selected_tag_ids, tag_id)
      else
        [tag_id | selected_tag_ids]
      end

    {:noreply, assign(socket, :selected_tag_ids, new_selected_tag_ids)}
  end

  @impl true
  def handle_event("toggle_size", %{"size" => size}, socket) do
    selected_sizes = socket.assigns.selected_sizes

    new_selected_sizes =
      if size in selected_sizes do
        List.delete(selected_sizes, size)
      else
        selected_sizes ++ [size]
      end

    # Regenerate variants based on new selections
    new_variants = generate_variants_from_selections(
      new_selected_sizes,
      socket.assigns.selected_colors,
      socket.assigns.variant_price
    )

    {:noreply,
     socket
     |> assign(:selected_sizes, new_selected_sizes)
     |> assign(:variants, new_variants)}
  end

  @impl true
  def handle_event("toggle_color", %{"color" => color}, socket) do
    selected_colors = socket.assigns.selected_colors

    new_selected_colors =
      if color in selected_colors do
        List.delete(selected_colors, color)
      else
        selected_colors ++ [color]
      end

    # Regenerate variants based on new selections
    new_variants = generate_variants_from_selections(
      socket.assigns.selected_sizes,
      new_selected_colors,
      socket.assigns.variant_price
    )

    {:noreply,
     socket
     |> assign(:selected_colors, new_selected_colors)
     |> assign(:variants, new_variants)}
  end

  @impl true
  def handle_event("update_variant_price", %{"value" => price}, socket) do
    # Update all variants with the new price
    new_variants = generate_variants_from_selections(
      socket.assigns.selected_sizes,
      socket.assigns.selected_colors,
      price
    )

    {:noreply,
     socket
     |> assign(:variant_price, price)
     |> assign(:variants, new_variants)}
  end

  @impl true
  def handle_event("image_uploaded", %{"url" => url}, socket) do
    images = socket.assigns.images

    # Create a new image record
    new_image = %{
      id: "temp_#{System.unique_integer([:positive])}",
      src: url,
      alt: "",
      position: length(images) + 1
    }

    {:noreply, assign(socket, :images, images ++ [new_image])}
  end

  @impl true
  def handle_event("remove_image", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    images = socket.assigns.images
    new_images = List.delete_at(images, index)
    {:noreply, assign(socket, :images, new_images)}
  end

  @impl true
  def handle_event("move_image_up", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    images = socket.assigns.images

    new_images =
      if index > 0 do
        images
        |> List.pop_at(index)
        |> then(fn {item, rest} -> List.insert_at(rest, index - 1, item) end)
      else
        images
      end

    {:noreply, assign(socket, :images, new_images)}
  end

  @impl true
  def handle_event("move_image_down", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    images = socket.assigns.images

    new_images =
      if index < length(images) - 1 do
        images
        |> List.pop_at(index)
        |> then(fn {item, rest} -> List.insert_at(rest, index + 1, item) end)
      else
        images
      end

    {:noreply, assign(socket, :images, new_images)}
  end

  @impl true
  def handle_event("add_variant", _, socket) do
    variants = socket.assigns.variants
    new_variant = %{
      id: "new_#{System.unique_integer([:positive])}",
      option1: "",
      option2: "",
      price: "",
      compare_at_price: "",
      inventory_quantity: "0",
      sku: ""
    }
    {:noreply, assign(socket, :variants, variants ++ [new_variant])}
  end

  @impl true
  def handle_event("remove_variant", %{"index" => index_str}, socket) do
    index = String.to_integer(index_str)
    variants = socket.assigns.variants
    new_variants = List.delete_at(variants, index)
    {:noreply, assign(socket, :variants, new_variants)}
  end

  @impl true
  def handle_event("update_variant", %{"index" => index_str, "field" => field, "value" => value}, socket) do
    index = String.to_integer(index_str)
    variants = socket.assigns.variants
    variant = Enum.at(variants, index)
    updated_variant = Map.put(variant, String.to_existing_atom(field), value)
    new_variants = List.replace_at(variants, index, updated_variant)
    {:noreply, assign(socket, :variants, new_variants)}
  end

  @impl true
  def handle_event("search_artist", %{"value" => query}, socket) do
    if String.length(query) >= 1 do
      suggestions = Shop.search_artists(query)
      {:noreply,
       socket
       |> assign(:artist_search, query)
       |> assign(:artist_suggestions, suggestions)
       |> assign(:show_artist_dropdown, length(suggestions) > 0)}
    else
      {:noreply,
       socket
       |> assign(:artist_search, query)
       |> assign(:artist_suggestions, [])
       |> assign(:show_artist_dropdown, false)}
    end
  end

  @impl true
  def handle_event("select_artist", %{"artist-id" => artist_id_str}, socket) do
    artist_id = String.to_integer(artist_id_str)
    artist = Shop.get_artist!(artist_id)
    {:noreply,
     socket
     |> assign(:selected_artist, artist)
     |> assign(:artist_search, "")
     |> assign(:artist_suggestions, [])
     |> assign(:show_artist_dropdown, false)}
  end

  @impl true
  def handle_event("clear_artist", _, socket) do
    {:noreply,
     socket
     |> assign(:selected_artist, nil)
     |> assign(:artist_search, "")
     |> assign(:artist_suggestions, [])
     |> assign(:show_artist_dropdown, false)}
  end

  @impl true
  def handle_event("close_artist_dropdown", _, socket) do
    {:noreply, assign(socket, :show_artist_dropdown, false)}
  end

  # Product Config event handlers

  @impl true
  def handle_event("toggle_config_has_sizes", _, socket) do
    new_val = !socket.assigns.config_has_sizes

    # When enabling sizes, set default size_type and load presets
    socket = if new_val do
      size_type = socket.assigns.config_size_type || "clothing"
      preset_sizes = SizePresets.sizes_for_type(size_type)

      socket
      |> assign(:config_has_sizes, true)
      |> assign(:config_size_type, size_type)
      |> assign(:config_preset_sizes, preset_sizes)
      |> assign(:config_available_sizes, preset_sizes)
    else
      socket
      |> assign(:config_has_sizes, false)
      |> assign(:config_available_sizes, [])
    end

    # Regenerate variants based on new config
    {:noreply, regenerate_variants_from_config(socket)}
  end

  @impl true
  def handle_event("toggle_config_has_colors", _, socket) do
    new_val = !socket.assigns.config_has_colors

    socket = if new_val do
      assign(socket, :config_has_colors, true)
    else
      socket
      |> assign(:config_has_colors, false)
      |> assign(:selected_colors, [])
    end

    {:noreply, regenerate_variants_from_config(socket)}
  end

  @impl true
  def handle_event("toggle_config_checkout", _, socket) do
    {:noreply, assign(socket, :config_checkout_enabled, !socket.assigns.config_checkout_enabled)}
  end

  @impl true
  def handle_event("change_size_type", %{"config_size_type" => size_type}, socket) do
    preset_sizes = SizePresets.sizes_for_type(size_type)

    socket =
      socket
      |> assign(:config_size_type, size_type)
      |> assign(:config_preset_sizes, preset_sizes)
      |> assign(:config_available_sizes, preset_sizes)
      |> assign(:selected_sizes, [])

    {:noreply, regenerate_variants_from_config(socket)}
  end

  @impl true
  def handle_event("toggle_config_size", %{"size" => size}, socket) do
    available = socket.assigns.config_available_sizes

    new_available = if size in available do
      List.delete(available, size)
    else
      # Insert in preset order
      preset = socket.assigns.config_preset_sizes
      (available ++ [size]) |> Enum.sort_by(fn s -> Enum.find_index(preset, &(&1 == s)) || 999 end)
    end

    # Also update selected_sizes to remove any that are no longer available
    new_selected = Enum.filter(socket.assigns.selected_sizes, &(&1 in new_available))

    socket =
      socket
      |> assign(:config_available_sizes, new_available)
      |> assign(:selected_sizes, new_selected)

    {:noreply, regenerate_variants_from_config(socket)}
  end

  @impl true
  def handle_event("update_config_commission", %{"value" => value}, socket) do
    {:noreply, assign(socket, :config_affiliate_commission_rate, value)}
  end

  defp save_product(socket, :edit, product_params, category_ids, tag_ids) do
    # Add artist_id to params if an artist is selected
    product_params = if socket.assigns.selected_artist do
      Map.put(product_params, "artist_id", socket.assigns.selected_artist.id)
    else
      Map.put(product_params, "artist_id", nil)
    end

    case Shop.update_product(socket.assigns.product, product_params) do
      {:ok, product} ->
        # Update categories
        Shop.set_product_categories(product, category_ids)

        # Update tags
        Shop.set_product_tags(product, tag_ids)

        # Save images
        save_images(product.id, socket.assigns.images)

        # Save variants
        save_variants(product.id, socket.assigns.variants)

        # Save product config
        save_product_config(product.id, socket)

        {:noreply,
         socket
         |> put_flash(:info, "Product updated successfully")
         |> push_navigate(to: ~p"/admin/products")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_product(socket, :new, product_params, category_ids, tag_ids) do
    # Add artist_id to params if an artist is selected
    product_params = if socket.assigns.selected_artist do
      Map.put(product_params, "artist_id", socket.assigns.selected_artist.id)
    else
      product_params
    end

    case Shop.create_product(product_params) do
      {:ok, product} ->
        # Update categories
        Shop.set_product_categories(product, category_ids)

        # Update tags
        Shop.set_product_tags(product, tag_ids)

        # Save images
        save_images(product.id, socket.assigns.images)

        # Save variants
        save_variants(product.id, socket.assigns.variants)

        # Save product config
        save_product_config(product.id, socket)

        {:noreply,
         socket
         |> put_flash(:info, "Product created successfully")
         |> push_navigate(to: ~p"/admin/products")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp save_images(product_id, images) do
    # Delete existing images for the product
    existing_images = Shop.list_product_images(product_id)
    Enum.each(existing_images, &Shop.delete_image/1)

    # Create new images
    Enum.with_index(images, 1)
    |> Enum.each(fn {image, position} ->
      Shop.create_image(%{
        product_id: product_id,
        src: get_image_src(image),
        alt: get_image_alt(image),
        position: position
      })
    end)
  end

  defp get_image_src(%{src: src}), do: src
  defp get_image_src(image) when is_map(image), do: Map.get(image, :src) || Map.get(image, "src")

  defp get_image_alt(%{alt: alt}), do: alt || ""
  defp get_image_alt(image) when is_map(image), do: Map.get(image, :alt) || Map.get(image, "alt") || ""

  defp page_title(:new), do: "New Product"
  defp page_title(:edit), do: "Edit Product"

  defp ordered_preloads do
    [
      {:images, from(i in ProductImage, order_by: i.position)},
      {:variants, from(v in ProductVariant, order_by: v.position)},
      :hub,
      :categories,
      :product_tags
    ]
  end

  defp get_selected_category_ids(%Product{categories: categories}) when is_list(categories) do
    Enum.map(categories, & &1.id)
  end

  defp get_selected_category_ids(_), do: []

  defp get_selected_tag_ids(%Product{product_tags: tags}) when is_list(tags) do
    Enum.map(tags, & &1.id)
  end

  defp get_selected_tag_ids(_), do: []

  defp transform_variants(variants) when is_list(variants) do
    Enum.map(variants, fn v ->
      %{
        id: v.id,
        option1: v.option1 || "",
        option2: v.option2 || "",
        price: if(v.price, do: Decimal.to_string(v.price), else: ""),
        compare_at_price: if(v.compare_at_price, do: Decimal.to_string(v.compare_at_price), else: ""),
        inventory_quantity: to_string(v.inventory_quantity || 0),
        sku: v.sku || ""
      }
    end)
  end

  defp transform_variants(_), do: []

  # Extract unique sizes, colors, and common price from existing variants
  defp extract_variant_options(variants) when is_list(variants) and length(variants) > 0 do
    sizes = variants
            |> Enum.map(& &1.option1)
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()

    colors = variants
             |> Enum.map(& &1.option2)
             |> Enum.reject(&is_nil/1)
             |> Enum.uniq()

    # Get the price from the first variant
    price = case List.first(variants) do
      nil -> ""
      v -> if v.price, do: Decimal.to_string(v.price), else: ""
    end

    {sizes, colors, price}
  end

  defp extract_variant_options(_), do: {[], [], ""}

  # Generate variants from selected sizes and colors
  defp generate_variants_from_selections(sizes, colors, price) do
    cond do
      # Both sizes and colors selected - create cartesian product
      Enum.any?(sizes) && Enum.any?(colors) ->
        for size <- sizes, color <- colors do
          %{
            id: "new_#{System.unique_integer([:positive])}",
            option1: size,
            option2: color,
            price: price,
            compare_at_price: "",
            inventory_quantity: "0",
            sku: ""
          }
        end

      # Only sizes selected
      Enum.any?(sizes) ->
        for size <- sizes do
          %{
            id: "new_#{System.unique_integer([:positive])}",
            option1: size,
            option2: "",
            price: price,
            compare_at_price: "",
            inventory_quantity: "0",
            sku: ""
          }
        end

      # Only colors selected
      Enum.any?(colors) ->
        for color <- colors do
          %{
            id: "new_#{System.unique_integer([:positive])}",
            option1: "",
            option2: color,
            price: price,
            compare_at_price: "",
            inventory_quantity: "0",
            sku: ""
          }
        end

      # Nothing selected - no variants
      true ->
        []
    end
  end

  defp save_variants(product_id, variants) do
    # Delete existing variants for the product
    existing_variants = Shop.list_product_variants(product_id)
    Enum.each(existing_variants, &Shop.delete_variant/1)

    # Create new variants
    Enum.with_index(variants, 1)
    |> Enum.each(fn {variant, position} ->
      price = parse_decimal(variant.price)
      compare_at_price = parse_decimal(variant.compare_at_price)
      inventory = parse_integer(variant.inventory_quantity)

      if price do
        Shop.create_variant(%{
          product_id: product_id,
          option1: variant.option1,
          option2: variant.option2,
          price: price,
          compare_at_price: compare_at_price,
          inventory_quantity: inventory,
          sku: variant.sku,
          position: position
        })
      end
    end)
  end

  defp parse_decimal(""), do: nil
  defp parse_decimal(nil), do: nil
  defp parse_decimal(value) when is_binary(value) do
    case Decimal.parse(value) do
      {decimal, _} -> decimal
      :error -> nil
    end
  end
  defp parse_decimal(value), do: value

  defp parse_integer(""), do: 0
  defp parse_integer(nil), do: 0
  defp parse_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> 0
    end
  end
  defp parse_integer(value) when is_integer(value), do: value

  # Product Config helpers

  defp product_config_assigns(nil) do
    %{
      config_has_sizes: false,
      config_has_colors: false,
      config_size_type: "clothing",
      config_preset_sizes: SizePresets.clothing_sizes(),
      config_available_sizes: [],
      config_checkout_enabled: false,
      config_affiliate_commission_rate: ""
    }
  end

  defp product_config_assigns(%ProductConfig{} = config) do
    preset_sizes = SizePresets.sizes_for_type(config.size_type || "clothing")

    %{
      config_has_sizes: config.has_sizes || false,
      config_has_colors: config.has_colors || false,
      config_size_type: config.size_type || "clothing",
      config_preset_sizes: preset_sizes,
      config_available_sizes: config.available_sizes || [],
      config_checkout_enabled: config.checkout_enabled || false,
      config_affiliate_commission_rate: if(config.affiliate_commission_rate, do: Decimal.to_string(config.affiliate_commission_rate), else: "")
    }
  end

  defp save_product_config(product_id, socket) do
    commission = parse_decimal(socket.assigns.config_affiliate_commission_rate)

    attrs = %{
      product_id: product_id,
      has_sizes: socket.assigns.config_has_sizes,
      has_colors: socket.assigns.config_has_colors,
      size_type: socket.assigns.config_size_type,
      available_sizes: socket.assigns.config_available_sizes,
      available_colors: Enum.map(socket.assigns.selected_colors, & &1),
      checkout_enabled: socket.assigns.config_checkout_enabled,
      affiliate_commission_rate: commission
    }

    case Shop.get_product_config(product_id) do
      nil -> Shop.create_product_config(attrs)
      existing -> Shop.update_product_config(existing, attrs)
    end
  end

  defp regenerate_variants_from_config(socket) do
    sizes = if socket.assigns.config_has_sizes do
      config_sizes = socket.assigns.config_available_sizes

      case socket.assigns.config_size_type do
        "unisex_shoes" ->
          # For unisex, prefix sizes with M- or W-
          mens = SizePresets.mens_shoe_sizes()
          womens = SizePresets.womens_shoe_sizes()

          mens_selected = Enum.filter(config_sizes, &(&1 in mens)) |> Enum.map(&("M-" <> &1))
          womens_selected = Enum.filter(config_sizes, &(&1 in womens)) |> Enum.map(&("W-" <> &1))
          mens_selected ++ womens_selected

        _ ->
          config_sizes
      end
    else
      []
    end

    colors = if socket.assigns.config_has_colors do
      socket.assigns.selected_colors
    else
      []
    end

    new_variants = generate_variants_from_selections(sizes, colors, socket.assigns.variant_price)

    socket
    |> assign(:selected_sizes, sizes)
    |> assign(:variants, new_variants)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-4xl mx-auto px-4 pt-24 pb-8">
      <div class="mb-8">
        <.link navigate={~p"/admin/products"} class="text-blue-600 hover:text-blue-800">
          &larr; Back to Products
        </.link>
        <h1 class="text-3xl font-bold text-gray-900 mt-4"><%= @page_title %></h1>
      </div>

      <.form for={@form} phx-change="validate" phx-submit="save" class="space-y-8">
        <%!-- Basic Information --%>
        <div class="bg-white shadow-md rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Basic Information</h2>

          <div class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Title *</label>
              <.input field={@form[:title]} type="text" placeholder="Product title" class="w-full" />
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Handle (URL slug)</label>
              <.input field={@form[:handle]} type="text" placeholder="product-url-slug" class="w-full" />
              <p class="text-sm text-gray-500 mt-1">Leave blank to auto-generate from title</p>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Description</label>
              <div id="product-description-editor" phx-hook="ProductDescriptionEditor" phx-update="ignore" class="border border-gray-300 rounded-lg overflow-hidden">
                <div class="product-editor-toolbar"></div>
                <div class="product-editor-container"></div>
                <textarea
                  name={@form[:body_html].name}
                  id={@form[:body_html].id}
                  data-product-description
                  class="hidden"
                ><%= Phoenix.HTML.Form.input_value(@form, :body_html) %></textarea>
              </div>
              <p class="text-sm text-gray-500 mt-1">Use the toolbar to format text with bold, italic, lists, and more.</p>
            </div>

            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Vendor</label>
                <.input field={@form[:vendor]} type="text" placeholder="e.g., Blockster" class="w-full" />
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Product Type</label>
                <.input field={@form[:product_type]} type="text" placeholder="e.g., T-Shirt, Hoodie" class="w-full" />
              </div>
            </div>

            <div class="grid grid-cols-2 gap-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Artist</label>
                <%= if @selected_artist do %>
                  <%!-- Selected artist display --%>
                  <div class="flex items-center gap-2 px-3 py-2 bg-blue-50 border border-blue-200 rounded-lg">
                    <%= if @selected_artist.image do %>
                      <img src={@selected_artist.image} alt={@selected_artist.name} class="w-8 h-8 rounded-full object-cover" />
                    <% else %>
                      <div class="w-8 h-8 rounded-full bg-blue-200 flex items-center justify-center">
                        <span class="text-blue-700 font-medium text-sm"><%= String.first(@selected_artist.name) %></span>
                      </div>
                    <% end %>
                    <span class="font-medium text-gray-900 flex-1"><%= @selected_artist.name %></span>
                    <button
                      type="button"
                      phx-click="clear_artist"
                      class="text-gray-400 hover:text-red-500 cursor-pointer"
                      title="Remove artist"
                    >
                      <svg class="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2">
                        <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                      </svg>
                    </button>
                  </div>
                <% else %>
                  <%!-- Artist search autocomplete --%>
                  <div class="relative" phx-click-away="close_artist_dropdown">
                    <input
                      type="text"
                      value={@artist_search}
                      phx-keyup="search_artist"
                      phx-debounce="200"
                      placeholder="Search artists..."
                      class="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                    />
                    <%= if @show_artist_dropdown && length(@artist_suggestions) > 0 do %>
                      <div class="absolute z-50 w-full mt-1 bg-white border border-gray-300 rounded-lg shadow-lg max-h-60 overflow-y-auto">
                        <%= for artist <- @artist_suggestions do %>
                          <button
                            type="button"
                            phx-click="select_artist"
                            phx-value-artist-id={artist.id}
                            class="w-full flex items-center gap-3 px-3 py-2 hover:bg-gray-50 cursor-pointer text-left"
                          >
                            <%= if artist.image do %>
                              <img src={artist.image} alt={artist.name} class="w-8 h-8 rounded-full object-cover" />
                            <% else %>
                              <div class="w-8 h-8 rounded-full bg-gray-200 flex items-center justify-center">
                                <span class="text-gray-600 font-medium text-sm"><%= String.first(artist.name) %></span>
                              </div>
                            <% end %>
                            <span class="font-medium text-gray-900"><%= artist.name %></span>
                          </button>
                        <% end %>
                      </div>
                    <% end %>
                  </div>
                  <p class="text-sm text-gray-500 mt-1">
                    <.link navigate={~p"/admin/artists"} class="text-blue-600 hover:underline cursor-pointer">Create new artist</.link>
                  </p>
                <% end %>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Collection Name</label>
                <.input field={@form[:collection_name]} type="text" placeholder="e.g., Summer 2024" class="w-full" />
              </div>
            </div>

            <div class="grid grid-cols-2 gap-4 mt-4">
              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Max Inventory (Limited Edition)</label>
                <.input field={@form[:max_inventory]} type="number" min="1" placeholder="Leave empty for unlimited" class="w-full" />
                <p class="text-sm text-gray-500 mt-1">Optional. Set for limited edition items to show sold count.</p>
              </div>

              <div>
                <label class="block text-sm font-medium text-gray-700 mb-1">Sold Count</label>
                <.input field={@form[:sold_count]} type="number" min="0" placeholder="0" class="w-full" />
                <p class="text-sm text-gray-500 mt-1">Number of units sold (auto-increments on purchase).</p>
              </div>
            </div>
          </div>
        </div>

        <%!-- Status & Hub --%>
        <div class="bg-white shadow-md rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Status & Hub</h2>

          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Status</label>
              <.input field={@form[:status]} type="select" options={[{"Draft", "draft"}, {"Active", "active"}, {"Archived", "archived"}]} class="w-full" />
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Hub</label>
              <.input
                field={@form[:hub_id]}
                type="select"
                options={[{"No Hub", nil}] ++ Enum.map(@hubs, &{&1.name, &1.id})}
                class="w-full"
              />
            </div>
          </div>
        </div>

        <%!-- Token Discounts --%>
        <div class="bg-white shadow-md rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Token Discounts</h2>

          <div class="grid grid-cols-2 gap-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">BUX Max Discount (%)</label>
              <.input field={@form[:bux_max_discount]} type="number" min="0" max="100" placeholder="0" class="w-full" />
              <p class="text-sm text-gray-500 mt-1">Maximum discount when redeeming BUX tokens</p>
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">Hub Token Max Discount (%)</label>
              <.input field={@form[:hub_token_max_discount]} type="number" min="0" max="100" placeholder="0" class="w-full" />
              <p class="text-sm text-gray-500 mt-1">Maximum discount when redeeming hub tokens (moonBUX, etc.)</p>
            </div>
          </div>
        </div>

        <%!-- Product Configuration --%>
        <div class="bg-white shadow-md rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Product Configuration</h2>
          <p class="text-sm text-gray-500 mb-4">Configure checkout, sizes, and colors for this product.</p>

          <%!-- Enable Checkout Toggle --%>
          <div class="flex items-center justify-between py-3 border-b border-gray-100">
            <div>
              <span class="text-sm font-medium text-gray-700">Enable Checkout</span>
              <p class="text-xs text-gray-500">When enabled, "Add to Cart" button will be active on the product page</p>
            </div>
            <button
              type="button"
              phx-click="toggle_config_checkout"
              class={"relative inline-flex h-6 w-11 items-center rounded-full transition-colors cursor-pointer #{if @config_checkout_enabled, do: "bg-green-500", else: "bg-gray-300"}"}
            >
              <span class={"inline-block h-4 w-4 transform rounded-full bg-white transition-transform #{if @config_checkout_enabled, do: "translate-x-6", else: "translate-x-1"}"} />
            </button>
          </div>

          <%!-- Has Sizes Toggle --%>
          <div class="flex items-center justify-between py-3 border-b border-gray-100">
            <div>
              <span class="text-sm font-medium text-gray-700">Has Sizes</span>
              <p class="text-xs text-gray-500">Enable size selection for this product</p>
            </div>
            <button
              type="button"
              phx-click="toggle_config_has_sizes"
              class={"relative inline-flex h-6 w-11 items-center rounded-full transition-colors cursor-pointer #{if @config_has_sizes, do: "bg-green-500", else: "bg-gray-300"}"}
            >
              <span class={"inline-block h-4 w-4 transform rounded-full bg-white transition-transform #{if @config_has_sizes, do: "translate-x-6", else: "translate-x-1"}"} />
            </button>
          </div>

          <%!-- Size Type + Size Checkboxes (revealed when Has Sizes is on) --%>
          <%= if @config_has_sizes do %>
            <div class="py-3 border-b border-gray-100 pl-4">
              <label class="block text-sm font-medium text-gray-700 mb-2">Size Type</label>
              <form phx-change="change_size_type" class="inline">
                <select
                  name="config_size_type"
                  class="w-64 px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-blue-500 focus:border-blue-500 cursor-pointer"
                >
                  <%= for {label, value} <- BlocksterV2.Shop.SizePresets.size_type_options() do %>
                    <option value={value} selected={value == @config_size_type}><%= label %></option>
                  <% end %>
                </select>
              </form>

              <%!-- Size Checkboxes --%>
              <div class="mt-3">
                <label class="block text-sm font-medium text-gray-700 mb-2">Available Sizes</label>
                <div class="flex flex-wrap gap-2">
                  <%= for size <- @config_preset_sizes do %>
                    <button
                      type="button"
                      phx-click="toggle_config_size"
                      phx-value-size={size}
                      class={"px-3 py-1.5 rounded-lg text-sm font-medium transition-colors cursor-pointer border-2 #{if size in @config_available_sizes, do: "border-blue-600 bg-blue-50 text-blue-700", else: "border-gray-300 bg-white text-gray-700 hover:border-gray-400"}"}
                    >
                      <%= size %>
                    </button>
                  <% end %>
                </div>
                <p class="text-xs text-gray-500 mt-2">
                  <%= length(@config_available_sizes) %> of <%= length(@config_preset_sizes) %> sizes enabled
                </p>
              </div>
            </div>
          <% end %>

          <%!-- Has Colors Toggle --%>
          <div class="flex items-center justify-between py-3 border-b border-gray-100">
            <div>
              <span class="text-sm font-medium text-gray-700">Has Colors</span>
              <p class="text-xs text-gray-500">Enable color selection for this product</p>
            </div>
            <button
              type="button"
              phx-click="toggle_config_has_colors"
              class={"relative inline-flex h-6 w-11 items-center rounded-full transition-colors cursor-pointer #{if @config_has_colors, do: "bg-green-500", else: "bg-gray-300"}"}
            >
              <span class={"inline-block h-4 w-4 transform rounded-full bg-white transition-transform #{if @config_has_colors, do: "translate-x-6", else: "translate-x-1"}"} />
            </button>
          </div>

          <%!-- Affiliate Commission Override --%>
          <div class="py-3">
            <label class="block text-sm font-medium text-gray-700 mb-1">Affiliate Commission Rate Override</label>
            <div class="flex items-center gap-2">
              <input
                type="number"
                step="0.01"
                min="0"
                max="1"
                name="config_commission"
                value={@config_affiliate_commission_rate}
                phx-keyup="update_config_commission"
                phx-debounce="300"
                placeholder="0.05"
                class="w-32 px-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-blue-500 focus:border-blue-500"
              />
              <span class="text-sm text-gray-500">e.g. 0.05 = 5% (leave blank for default)</span>
            </div>
          </div>
        </div>

        <%!-- Variants (Sizes, Colors, Price) --%>
        <div class="bg-white shadow-md rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Variants</h2>
          <p class="text-sm text-gray-500 mb-4">Select sizes and colors to auto-generate variants with a single price.</p>

          <%!-- Price Input --%>
          <div class="mb-6">
            <label class="block text-sm font-medium text-gray-700 mb-2">Price (applies to all variants) *</label>
            <div class="relative w-48">
              <span class="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500">$</span>
              <input
                type="number"
                step="0.01"
                min="0"
                name="variant_price"
                value={@variant_price}
                phx-keyup="update_variant_price"
                phx-debounce="100"
                placeholder="0.00"
                class="w-full pl-7 pr-3 py-2 border border-gray-300 rounded-lg text-sm focus:ring-blue-500 focus:border-blue-500"
              />
            </div>
          </div>

          <%!-- Sizes Selection (only show if Has Sizes is disabled in config — legacy mode) --%>
          <%= unless @config_has_sizes do %>
            <div class="mb-6">
              <label class="block text-sm font-medium text-gray-700 mb-2">Sizes</label>
              <div class="flex flex-wrap gap-2">
                <%= for size <- @available_sizes do %>
                  <button
                    type="button"
                    phx-click="toggle_size"
                    phx-value-size={size}
                    class={"px-4 py-2 rounded-lg text-sm font-medium transition-colors cursor-pointer border-2 #{if size in @selected_sizes, do: "border-blue-600 bg-blue-50 text-blue-700", else: "border-gray-300 bg-white text-gray-700 hover:border-gray-400"}"}
                  >
                    <%= size %>
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>

          <%!-- Colors Selection (show when config has_colors is on, or legacy mode) --%>
          <%= if @config_has_colors || !@config_has_sizes do %>
            <div class="mb-6">
              <label class="block text-sm font-medium text-gray-700 mb-2">Colors</label>
              <div class="flex flex-wrap gap-3">
                <%= for {color_name, hex_code} <- @available_colors do %>
                  <button
                    type="button"
                    phx-click="toggle_color"
                    phx-value-color={color_name}
                    class={"flex flex-col items-center gap-1 p-2 rounded-lg transition-all cursor-pointer #{if color_name in @selected_colors, do: "ring-2 ring-blue-600 ring-offset-2", else: "hover:bg-gray-50"}"}
                    title={color_name}
                  >
                    <div
                      class={"w-8 h-8 rounded-full border #{if hex_code == "#FFFFFF", do: "border-gray-300", else: "border-transparent"}"}
                      style={"background-color: #{hex_code};"}
                    />
                    <span class="text-xs text-gray-600"><%= color_name %></span>
                  </button>
                <% end %>
              </div>
            </div>
          <% end %>

          <%!-- Generated Variants Preview --%>
          <%= if length(@variants) > 0 do %>
            <div class="border-t pt-4">
              <div class="flex justify-between items-center mb-3">
                <h3 class="text-sm font-medium text-gray-700">Generated Variants (<%= length(@variants) %>)</h3>
              </div>
              <div class="flex flex-wrap gap-2">
                <%= for variant <- @variants do %>
                  <span class="px-3 py-1 bg-gray-100 text-gray-700 rounded-full text-sm">
                    <%= if variant.option1 && variant.option2 do %>
                      <%= variant.option1 %> / <%= variant.option2 %>
                    <% else %>
                      <%= variant.option1 || variant.option2 %>
                    <% end %>
                  </span>
                <% end %>
              </div>
            </div>
          <% else %>
            <p class="text-gray-500 text-center py-4 border-t">Select at least one size or color to generate variants.</p>
          <% end %>
        </div>

        <%!-- Categories --%>
        <div class="bg-white shadow-md rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Categories</h2>

          <%= if Enum.empty?(@categories) do %>
            <p class="text-gray-500">No categories available. Create categories first.</p>
          <% else %>
            <div class="flex flex-wrap gap-2">
              <%= for category <- @categories do %>
                <button
                  type="button"
                  phx-click="toggle_category"
                  phx-value-category-id={category.id}
                  class={"px-3 py-1 rounded-full text-sm font-medium transition-colors cursor-pointer #{if category.id in @selected_category_ids, do: "bg-blue-600 text-white", else: "bg-gray-200 text-gray-700 hover:bg-gray-300"}"}
                >
                  <%= category.name %>
                </button>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Tags --%>
        <div class="bg-white shadow-md rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Tags</h2>

          <%= if Enum.empty?(@tags) do %>
            <p class="text-gray-500">No tags available. Create tags first.</p>
          <% else %>
            <%!-- Selected tags as pills with X to remove --%>
            <%= if length(@selected_tag_ids) > 0 do %>
              <div class="flex flex-wrap gap-2 mb-4">
                <%= for tag_id <- @selected_tag_ids do %>
                  <% tag = Enum.find(@tags, fn t -> t.id == tag_id end) %>
                  <%= if tag do %>
                    <span class="inline-flex items-center gap-1 px-3 py-1 bg-green-600 text-white rounded-full text-sm font-medium">
                      <%= tag.name %>
                      <button
                        type="button"
                        phx-click="toggle_tag"
                        phx-value-tag-id={tag.id}
                        class="hover:bg-green-700 rounded-full p-0.5 cursor-pointer"
                        title="Remove tag"
                      >
                        <svg class="w-3.5 h-3.5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="3">
                          <path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" />
                        </svg>
                      </button>
                    </span>
                  <% end %>
                <% end %>
              </div>
            <% end %>

            <%!-- Available tags to add --%>
            <p class="text-sm text-gray-600 mb-2">Click to add tags:</p>
            <div class="flex flex-wrap gap-2">
              <%= for tag <- @tags do %>
                <%= unless tag.id in @selected_tag_ids do %>
                  <button
                    type="button"
                    phx-click="toggle_tag"
                    phx-value-tag-id={tag.id}
                    class="px-3 py-1 rounded-full text-sm font-medium transition-colors bg-gray-200 text-gray-700 hover:bg-gray-300 cursor-pointer"
                  >
                    <%= tag.name %>
                  </button>
                <% end %>
              <% end %>
            </div>
          <% end %>
        </div>

        <%!-- Images --%>
        <div class="bg-white shadow-md rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">Product Images</h2>

          <div class="space-y-4">
            <%!-- Existing images --%>
            <%= if length(@images) > 0 do %>
              <p class="text-sm text-gray-500 mb-2">Drag or use arrows to reorder. First image is the main product image.</p>
              <div class="grid grid-cols-2 md:grid-cols-4 gap-4">
                <%= for {image, index} <- Enum.with_index(@images) do %>
                  <div class="relative group">
                    <%= if index == 0 do %>
                      <span class="absolute top-2 left-2 bg-blue-500 text-white text-xs px-2 py-1 rounded z-10">Main</span>
                    <% end %>
                    <img
                      src={get_image_src(image)}
                      alt={get_image_alt(image)}
                      class="w-full h-32 object-cover rounded-lg border"
                    />
                    <%!-- Action buttons --%>
                    <div class="absolute top-2 right-2 flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                      <%= if index > 0 do %>
                        <button
                          type="button"
                          phx-click="move_image_up"
                          phx-value-index={index}
                          class="bg-gray-700 text-white rounded-full p-1 cursor-pointer"
                          title="Move left"
                        >
                          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19l-7-7 7-7" />
                          </svg>
                        </button>
                      <% end %>
                      <%= if index < length(@images) - 1 do %>
                        <button
                          type="button"
                          phx-click="move_image_down"
                          phx-value-index={index}
                          class="bg-gray-700 text-white rounded-full p-1 cursor-pointer"
                          title="Move right"
                        >
                          <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 5l7 7-7 7" />
                          </svg>
                        </button>
                      <% end %>
                      <button
                        type="button"
                        phx-click="remove_image"
                        phx-value-index={index}
                        class="bg-red-500 text-white rounded-full p-1 cursor-pointer"
                        title="Remove image"
                      >
                        <svg class="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
                        </svg>
                      </button>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>

            <%!-- Upload new image --%>
            <div class="border-2 border-dashed border-gray-300 rounded-lg p-6 text-center hover:border-blue-400 transition-colors">
              <input
                type="file"
                id="product-image-upload"
                accept="image/*"
                multiple
                class="hidden"
                phx-hook="ProductImageUpload"
              />
              <label for="product-image-upload" class="cursor-pointer">
                <svg class="mx-auto h-12 w-12 text-gray-400" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 16l4.586-4.586a2 2 0 012.828 0L16 16m-2-2l1.586-1.586a2 2 0 012.828 0L20 14m-6-6h.01M6 20h12a2 2 0 002-2V6a2 2 0 00-2-2H6a2 2 0 00-2 2v12a2 2 0 002 2z" />
                </svg>
                <p class="mt-2 text-sm text-gray-600">Click to upload images</p>
                <p class="text-xs text-gray-500">PNG, JPG</p>
              </label>
            </div>
          </div>
        </div>

        <%!-- SEO --%>
        <div class="bg-white shadow-md rounded-lg p-6">
          <h2 class="text-xl font-semibold mb-4">SEO</h2>

          <div class="space-y-4">
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">SEO Title</label>
              <.input field={@form[:seo_title]} type="text" placeholder="SEO title" class="w-full" />
            </div>

            <div>
              <label class="block text-sm font-medium text-gray-700 mb-1">SEO Description</label>
              <.input field={@form[:seo_description]} type="textarea" rows="3" placeholder="SEO description" class="w-full" />
            </div>
          </div>
        </div>

        <%!-- Submit --%>
        <div class="flex justify-end gap-4">
          <.link navigate={~p"/admin/products"} class="px-6 py-2 border border-gray-300 rounded-lg hover:bg-gray-50">
            Cancel
          </.link>
          <button type="submit" class="px-6 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 font-medium cursor-pointer">
            <%= if @live_action == :new, do: "Create Product", else: "Update Product" %>
          </button>
        </div>
      </.form>
    </div>
    """
  end
end
