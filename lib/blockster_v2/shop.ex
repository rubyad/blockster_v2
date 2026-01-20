defmodule BlocksterV2.Shop do
  @moduledoc """
  The Shop context for managing products, variants, images, categories, and tags.
  """

  import Ecto.Query, warn: false
  alias BlocksterV2.Repo

  alias BlocksterV2.Shop.{Product, ProductVariant, ProductImage, ProductCategory, ProductTag, Artist}

  # ============================================================================
  # Products
  # ============================================================================

  def list_products(opts \\ []) do
    Product
    |> apply_product_filters(opts)
    |> Repo.all()
  end

  def list_active_products(opts \\ []) do
    opts = Keyword.put(opts, :status, "active")
    list_products(opts)
  end

  def get_random_products(count \\ 3) do
    # Only get products that have at least one image using EXISTS subquery
    products =
      from(p in Product, as: :product,
        where: p.status == "active",
        where: exists(from(i in ProductImage, where: i.product_id == parent_as(:product).id, select: 1)),
        order_by: fragment("RANDOM()"),
        limit: ^count
      )
      |> Repo.all()
      |> Repo.preload([:images, :variants])

    # Return products with only first image and first variant for each
    Enum.map(products, fn product ->
      first_image = product.images |> Enum.sort_by(& &1.position) |> List.first()
      first_variant = product.variants |> Enum.sort_by(& &1.position) |> List.first()
      %{product | images: if(first_image, do: [first_image], else: []), variants: if(first_variant, do: [first_variant], else: [])}
    end)
  end

  @doc """
  Gets sidebar products for post pages: 2 T-shirts, 1 Hat, 1 Hoodie (randomly selected by category).
  Returns 4 products shuffled into random order.
  """
  def get_sidebar_products do
    tshirts = get_random_products_by_category_slug("t-shirt", 2)
    hats = get_random_products_by_category_slug("hat", 1)
    hoodies = get_random_products_by_category_slug("hoodie", 1)

    (tshirts ++ hats ++ hoodies)
    |> Enum.shuffle()
  end

  defp get_random_products_by_category_slug(category_slug, count) do
    # First get the category
    category = get_category_by_slug(category_slug)

    if category do
      # Get product IDs in category that have at least one image
      product_ids =
        from(p in Product, as: :product,
          join: c in assoc(p, :categories),
          where: p.status == "active",
          where: c.id == ^category.id,
          where: exists(from(i in ProductImage, where: i.product_id == parent_as(:product).id, select: 1)),
          select: p.id
        )
        |> Repo.all()

      # Shuffle and take random products
      selected_ids =
        product_ids
        |> Enum.shuffle()
        |> Enum.take(count)

      # Fetch the actual products with preloads
      products =
        from(p in Product, where: p.id in ^selected_ids)
        |> Repo.all()
        |> Repo.preload([:images, :variants])

      # Return products with first 2 images (for flip effect) and first variant
      Enum.map(products, fn product ->
        sorted_images = product.images |> Enum.sort_by(& &1.position)
        first_two_images = Enum.take(sorted_images, 2)
        first_variant = product.variants |> Enum.sort_by(& &1.position) |> List.first()
        %{product | images: first_two_images, variants: if(first_variant, do: [first_variant], else: [])}
      end)
    else
      []
    end
  end

  def get_product!(id), do: Repo.get!(Product, id)

  def get_product(id), do: Repo.get(Product, id)

  def get_product_by_handle(handle) do
    Repo.get_by(Product, handle: handle)
  end

  def get_product_with_associations(id) do
    images_query = from(i in ProductImage, order_by: i.position)
    variants_query = from(v in ProductVariant, order_by: v.position)

    Product
    |> Repo.get(id)
    |> Repo.preload([
      {:variants, variants_query},
      {:images, images_query},
      :categories,
      :product_tags,
      :hub
    ])
  end

  def create_product(attrs \\ %{}) do
    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert()
  end

  def update_product(%Product{} = product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  def delete_product(%Product{} = product) do
    Repo.delete(product)
  end

  def change_product(%Product{} = product, attrs \\ %{}) do
    Product.changeset(product, attrs)
  end

  defp apply_product_filters(query, opts) do
    Enum.reduce(opts, query, fn
      {:status, status}, query ->
        from p in query, where: p.status == ^status

      {:hub_id, hub_id}, query ->
        from p in query, where: p.hub_id == ^hub_id

      {:product_type, product_type}, query ->
        from p in query, where: p.product_type == ^product_type

      {:vendor, vendor}, query ->
        from p in query, where: p.vendor == ^vendor

      {:preload, preloads}, query ->
        # Convert preloads to use ordered queries for images and variants
        ordered_preloads = Enum.map(preloads, fn
          :images -> {:images, from(i in ProductImage, order_by: i.position)}
          :variants -> {:variants, from(v in ProductVariant, order_by: v.position)}
          other -> other
        end)
        from p in query, preload: ^ordered_preloads

      {:limit, limit}, query ->
        from p in query, limit: ^limit

      {:order_by, order}, query ->
        from p in query, order_by: ^order

      _, query ->
        query
    end)
  end

  # ============================================================================
  # Product Variants
  # ============================================================================

  def list_product_variants(product_id) do
    ProductVariant
    |> where([v], v.product_id == ^product_id)
    |> order_by([v], v.position)
    |> Repo.all()
  end

  def get_variant!(id), do: Repo.get!(ProductVariant, id)

  def get_variant(id), do: Repo.get(ProductVariant, id)

  def create_variant(attrs \\ %{}) do
    %ProductVariant{}
    |> ProductVariant.changeset(attrs)
    |> Repo.insert()
  end

  def update_variant(%ProductVariant{} = variant, attrs) do
    variant
    |> ProductVariant.changeset(attrs)
    |> Repo.update()
  end

  def delete_variant(%ProductVariant{} = variant) do
    Repo.delete(variant)
  end

  def change_variant(%ProductVariant{} = variant, attrs \\ %{}) do
    ProductVariant.changeset(variant, attrs)
  end

  # ============================================================================
  # Product Images
  # ============================================================================

  def list_product_images(product_id) do
    ProductImage
    |> where([i], i.product_id == ^product_id)
    |> order_by([i], i.position)
    |> Repo.all()
  end

  def get_image!(id), do: Repo.get!(ProductImage, id)

  def get_image(id), do: Repo.get(ProductImage, id)

  def create_image(attrs \\ %{}) do
    %ProductImage{}
    |> ProductImage.changeset(attrs)
    |> Repo.insert()
  end

  def update_image(%ProductImage{} = image, attrs) do
    image
    |> ProductImage.changeset(attrs)
    |> Repo.update()
  end

  def delete_image(%ProductImage{} = image) do
    Repo.delete(image)
  end

  def change_image(%ProductImage{} = image, attrs \\ %{}) do
    ProductImage.changeset(image, attrs)
  end

  # ============================================================================
  # Product Categories
  # ============================================================================

  def list_categories do
    ProductCategory
    |> order_by([c], c.position)
    |> Repo.all()
  end

  def list_root_categories do
    ProductCategory
    |> where([c], is_nil(c.parent_id))
    |> order_by([c], c.position)
    |> Repo.all()
  end

  def get_category!(id), do: Repo.get!(ProductCategory, id)

  def get_category(id), do: Repo.get(ProductCategory, id)

  def get_category_by_slug(slug) do
    Repo.get_by(ProductCategory, slug: slug)
  end

  def get_category_with_products(id) do
    ProductCategory
    |> Repo.get(id)
    |> Repo.preload(:products)
  end

  def create_category(attrs \\ %{}) do
    %ProductCategory{}
    |> ProductCategory.changeset(attrs)
    |> Repo.insert()
  end

  def update_category(%ProductCategory{} = category, attrs) do
    category
    |> ProductCategory.changeset(attrs)
    |> Repo.update()
  end

  def delete_category(%ProductCategory{} = category) do
    Repo.delete(category)
  end

  def change_category(%ProductCategory{} = category, attrs \\ %{}) do
    ProductCategory.changeset(category, attrs)
  end

  # ============================================================================
  # Product Tags
  # ============================================================================

  def list_tags do
    ProductTag
    |> order_by([t], t.name)
    |> Repo.all()
  end

  def get_tag!(id), do: Repo.get!(ProductTag, id)

  def get_tag(id), do: Repo.get(ProductTag, id)

  def get_tag_by_slug(slug) do
    Repo.get_by(ProductTag, slug: slug)
  end

  def get_tag_by_name(name) do
    Repo.get_by(ProductTag, name: name)
  end

  def get_or_create_tag(name) do
    case get_tag_by_name(name) do
      nil -> create_tag(%{name: name})
      tag -> {:ok, tag}
    end
  end

  def create_tag(attrs \\ %{}) do
    %ProductTag{}
    |> ProductTag.changeset(attrs)
    |> Repo.insert()
  end

  def update_tag(%ProductTag{} = tag, attrs) do
    tag
    |> ProductTag.changeset(attrs)
    |> Repo.update()
  end

  def delete_tag(%ProductTag{} = tag) do
    Repo.delete(tag)
  end

  def change_tag(%ProductTag{} = tag, attrs \\ %{}) do
    ProductTag.changeset(tag, attrs)
  end

  # ============================================================================
  # Product Associations
  # ============================================================================

  def add_product_to_category(%Product{} = product, %ProductCategory{} = category) do
    product = Repo.preload(product, :categories)
    categories = [category | product.categories] |> Enum.uniq_by(& &1.id)

    product
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:categories, categories)
    |> Repo.update()
  end

  def remove_product_from_category(%Product{} = product, %ProductCategory{} = category) do
    product = Repo.preload(product, :categories)
    categories = Enum.reject(product.categories, &(&1.id == category.id))

    product
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:categories, categories)
    |> Repo.update()
  end

  def add_tag_to_product(%Product{} = product, %ProductTag{} = tag) do
    product = Repo.preload(product, :product_tags)
    tags = [tag | product.product_tags] |> Enum.uniq_by(& &1.id)

    product
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:product_tags, tags)
    |> Repo.update()
  end

  def remove_tag_from_product(%Product{} = product, %ProductTag{} = tag) do
    product = Repo.preload(product, :product_tags)
    tags = Enum.reject(product.product_tags, &(&1.id == tag.id))

    product
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:product_tags, tags)
    |> Repo.update()
  end

  def set_product_categories(%Product{} = product, category_ids) when is_list(category_ids) do
    categories = ProductCategory |> where([c], c.id in ^category_ids) |> Repo.all()

    product
    |> Repo.preload(:categories)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:categories, categories)
    |> Repo.update()
  end

  def set_product_tags(%Product{} = product, tag_ids) when is_list(tag_ids) do
    tags = ProductTag |> where([t], t.id in ^tag_ids) |> Repo.all()

    product
    |> Repo.preload(:product_tags)
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:product_tags, tags)
    |> Repo.update()
  end

  # ============================================================================
  # Artists
  # ============================================================================

  def list_artists do
    Artist
    |> order_by([a], a.name)
    |> Repo.all()
  end

  def get_artist!(id), do: Repo.get!(Artist, id)

  def get_artist(id), do: Repo.get(Artist, id)

  def get_artist_by_slug(slug) do
    Repo.get_by(Artist, slug: slug)
  end

  def get_artist_with_products(id) do
    Artist
    |> Repo.get(id)
    |> Repo.preload(:products)
  end

  def create_artist(attrs \\ %{}) do
    %Artist{}
    |> Artist.changeset(attrs)
    |> Repo.insert()
  end

  def update_artist(%Artist{} = artist, attrs) do
    artist
    |> Artist.changeset(attrs)
    |> Repo.update()
  end

  def delete_artist(%Artist{} = artist) do
    Repo.delete(artist)
  end

  def change_artist(%Artist{} = artist, attrs \\ %{}) do
    Artist.changeset(artist, attrs)
  end

  @doc """
  Search artists by name for autocomplete.
  Returns up to 10 matching artists.
  """
  def search_artists(query) when is_binary(query) do
    search_term = "%#{query}%"

    Artist
    |> where([a], ilike(a.name, ^search_term))
    |> order_by([a], a.name)
    |> limit(10)
    |> Repo.all()
  end

  def search_artists(_), do: []
end
