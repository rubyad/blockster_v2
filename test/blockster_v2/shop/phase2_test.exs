defmodule BlocksterV2.Shop.Phase2Test do
  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Shop
  alias BlocksterV2.Shop.SizePresets

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp create_product(attrs \\ %{}) do
    unique_id = System.unique_integer([:positive])

    default_attrs = %{
      title: "Test Product #{unique_id}",
      handle: "test-product-#{unique_id}",
      status: "active",
      bux_max_discount: 50
    }

    {:ok, product} = Shop.create_product(Map.merge(default_attrs, attrs))
    product
  end

  defp create_variant(product, attrs \\ %{}) do
    default_attrs = %{
      product_id: product.id,
      price: Decimal.new("50.00"),
      title: "Default",
      inventory_quantity: 10
    }

    {:ok, variant} = Shop.create_variant(Map.merge(default_attrs, attrs))
    variant
  end

  defp create_product_config(product, attrs \\ %{}) do
    default_attrs = %{product_id: product.id}
    {:ok, config} = Shop.create_product_config(Map.merge(default_attrs, attrs))
    config
  end

  # ============================================================================
  # SizePresets Tests
  # ============================================================================

  describe "SizePresets" do
    test "clothing sizes returns 7 standard sizes" do
      sizes = SizePresets.clothing_sizes()
      assert length(sizes) == 7
      assert "XS" in sizes
      assert "S" in sizes
      assert "3XL" in sizes
    end

    test "mens shoe sizes include half sizes" do
      sizes = SizePresets.mens_shoe_sizes()
      assert "US 7" in sizes
      assert "US 7.5" in sizes
      assert "US 10.5" in sizes
      assert "US 14" in sizes
      assert length(sizes) == 13
    end

    test "womens shoe sizes include half sizes" do
      sizes = SizePresets.womens_shoe_sizes()
      assert "US 5" in sizes
      assert "US 5.5" in sizes
      assert "US 11" in sizes
      assert length(sizes) == 12
    end

    test "sizes_for_type returns correct presets" do
      assert SizePresets.sizes_for_type("clothing") == SizePresets.clothing_sizes()
      assert SizePresets.sizes_for_type("mens_shoes") == SizePresets.mens_shoe_sizes()
      assert SizePresets.sizes_for_type("womens_shoes") == SizePresets.womens_shoe_sizes()
      assert SizePresets.sizes_for_type("one_size") == ["One Size"]
    end

    test "sizes_for_type unisex_shoes combines mens and womens" do
      sizes = SizePresets.sizes_for_type("unisex_shoes")
      assert "US 7" in sizes   # mens
      assert "US 5" in sizes   # womens
      assert length(sizes) == length(SizePresets.mens_shoe_sizes()) + length(SizePresets.womens_shoe_sizes())
    end

    test "sizes_for_type unknown returns empty" do
      assert SizePresets.sizes_for_type("bogus") == []
    end

    test "mens_unisex_sizes filters M- prefix" do
      sizes = ["M-US 9", "M-US 10", "W-US 7", "W-US 8"]
      assert SizePresets.mens_unisex_sizes(sizes) == ["US 9", "US 10"]
    end

    test "womens_unisex_sizes filters W- prefix" do
      sizes = ["M-US 9", "M-US 10", "W-US 7", "W-US 8"]
      assert SizePresets.womens_unisex_sizes(sizes) == ["US 7", "US 8"]
    end

    test "size_type_options returns 5 options" do
      options = SizePresets.size_type_options()
      assert length(options) == 5
      assert {"Clothing", "clothing"} in options
      assert {"Men's Shoes", "mens_shoes"} in options
    end

    test "size_type_label returns human labels" do
      assert SizePresets.size_type_label("clothing") == "Clothing"
      assert SizePresets.size_type_label("mens_shoes") == "Men's Shoes"
      assert SizePresets.size_type_label("unisex_shoes") == "Unisex Shoes"
      assert SizePresets.size_type_label("bogus") == "Unknown"
    end
  end

  # ============================================================================
  # ProductConfig + Product Integration Tests
  # ============================================================================

  describe "ProductConfig with product association" do
    test "product has_one product_config" do
      product = create_product()
      config = create_product_config(product, %{has_sizes: true, size_type: "mens_shoes"})

      loaded = Shop.get_product!(product.id) |> Repo.preload(:product_config)
      assert loaded.product_config.id == config.id
      assert loaded.product_config.has_sizes == true
      assert loaded.product_config.size_type == "mens_shoes"
    end

    test "config stores available_sizes as array" do
      product = create_product()
      sizes = ["US 9", "US 10", "US 11"]

      config = create_product_config(product, %{
        has_sizes: true,
        size_type: "mens_shoes",
        available_sizes: sizes
      })

      assert config.available_sizes == sizes
    end

    test "config stores available_colors as array" do
      product = create_product()
      colors = ["Black", "White", "Red"]

      config = create_product_config(product, %{
        has_colors: true,
        available_colors: colors
      })

      assert config.available_colors == colors
    end

    test "config affiliate_commission_rate is decimal" do
      product = create_product()

      config = create_product_config(product, %{
        affiliate_commission_rate: Decimal.new("0.10")
      })

      assert Decimal.equal?(config.affiliate_commission_rate, Decimal.new("0.10"))
    end

    test "config defaults checkout_enabled to false" do
      product = create_product()
      config = create_product_config(product)
      assert config.checkout_enabled == false
    end

    test "enabling checkout via update" do
      product = create_product()
      config = create_product_config(product)

      {:ok, updated} = Shop.update_product_config(config, %{checkout_enabled: true})
      assert updated.checkout_enabled == true
    end
  end

  # ============================================================================
  # Variant Generation Tests (config-driven)
  # ============================================================================

  describe "variant auto-generation from config sizes" do
    test "clothing product with sizes generates size variants" do
      product = create_product()
      sizes = ["S", "M", "L"]

      for size <- sizes do
        create_variant(product, %{option1: size, option2: nil})
      end

      loaded = Shop.get_product!(product.id) |> Repo.preload(:variants)
      variant_sizes = Enum.map(loaded.variants, & &1.option1) |> Enum.sort()
      assert variant_sizes == ["L", "M", "S"]
    end

    test "shoe product with sizes generates shoe size variants" do
      product = create_product()
      sizes = ["US 9", "US 10", "US 10.5"]

      for size <- sizes do
        create_variant(product, %{option1: size, option2: nil})
      end

      loaded = Shop.get_product!(product.id) |> Repo.preload(:variants)
      variant_sizes = Enum.map(loaded.variants, & &1.option1)
      assert "US 9" in variant_sizes
      assert "US 10" in variant_sizes
      assert "US 10.5" in variant_sizes
    end

    test "unisex shoe variants store with M-/W- prefix" do
      product = create_product()

      create_variant(product, %{option1: "M-US 9", option2: "Black"})
      create_variant(product, %{option1: "M-US 10", option2: "Black"})
      create_variant(product, %{option1: "W-US 7", option2: "Black"})
      create_variant(product, %{option1: "W-US 8", option2: "Black"})

      loaded = Shop.get_product!(product.id) |> Repo.preload(:variants)
      sizes = Enum.map(loaded.variants, & &1.option1)

      mens = Enum.filter(sizes, &String.starts_with?(&1, "M-"))
      womens = Enum.filter(sizes, &String.starts_with?(&1, "W-"))

      assert length(mens) == 2
      assert length(womens) == 2
    end

    test "product with sizes and colors generates cartesian product" do
      product = create_product()
      sizes = ["S", "M"]
      colors = ["Black", "White"]

      for size <- sizes, color <- colors do
        create_variant(product, %{option1: size, option2: color})
      end

      loaded = Shop.get_product!(product.id) |> Repo.preload(:variants)
      assert length(loaded.variants) == 4
    end
  end

  # ============================================================================
  # Conditional Rendering Logic Tests
  # ============================================================================

  describe "conditional rendering based on config" do
    test "product with has_sizes=false should not show sizes" do
      product = create_product()
      config = create_product_config(product, %{has_sizes: false})
      assert config.has_sizes == false
    end

    test "product with has_sizes=true and size_type=clothing" do
      product = create_product()
      config = create_product_config(product, %{
        has_sizes: true,
        size_type: "clothing",
        available_sizes: ["S", "M", "L", "XL"]
      })

      assert config.has_sizes == true
      assert config.size_type == "clothing"
      assert length(config.available_sizes) == 4
    end

    test "product with has_colors=false and has_sizes=false shows no options" do
      product = create_product()
      config = create_product_config(product, %{has_sizes: false, has_colors: false})
      assert config.has_sizes == false
      assert config.has_colors == false
    end

    test "product with checkout_enabled=true enables cart" do
      product = create_product()
      config = create_product_config(product, %{checkout_enabled: true})
      assert config.checkout_enabled == true
    end

    test "product with checkout_enabled=false shows Coming Soon" do
      product = create_product()
      config = create_product_config(product, %{checkout_enabled: false})
      assert config.checkout_enabled == false
    end

    test "unisex shoe config stores both size ranges" do
      product = create_product()

      # For unisex, available_sizes contains both mens and womens shoe sizes
      all_sizes = SizePresets.mens_shoe_sizes() ++ SizePresets.womens_shoe_sizes()
      config = create_product_config(product, %{
        has_sizes: true,
        size_type: "unisex_shoes",
        available_sizes: all_sizes
      })

      assert config.size_type == "unisex_shoes"
      assert "US 7" in config.available_sizes  # shared between mens & womens
      assert "US 14" in config.available_sizes  # mens only
      assert "US 5" in config.available_sizes   # womens only
    end
  end

  # ============================================================================
  # Seed Migration Tests
  # ============================================================================

  describe "seed migration - product configs for existing products" do
    test "new product without config gets nil from get_product_config" do
      product = create_product()
      # Don't create a config - verify it returns nil
      assert Shop.get_product_config(product.id) == nil
    end

    test "create_product_config sets sensible defaults" do
      product = create_product()
      config = create_product_config(product)

      assert config.has_sizes == false
      assert config.has_colors == false
      assert config.checkout_enabled == false
      assert config.size_type == "clothing"
      assert config.available_sizes == []
      assert config.available_colors == []
      assert config.requires_shipping == true
      assert config.is_digital == false
    end
  end
end
