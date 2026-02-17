defmodule BlocksterV2.Repo.Migrations.SeedProductConfigs do
  use Ecto.Migration

  def up do
    # Create a product_config record for every existing product that doesn't have one yet.
    # Defaults: checkout_enabled=false, no sizes, no colors.
    execute """
    INSERT INTO product_configs (id, product_id, has_sizes, has_colors, has_custom_option, size_type,
      available_sizes, available_colors, requires_shipping, is_digital, checkout_enabled,
      inserted_at, updated_at)
    SELECT
      gen_random_uuid(),
      p.id,
      false,
      false,
      false,
      'clothing',
      '{}',
      '{}',
      true,
      false,
      false,
      NOW(),
      NOW()
    FROM products p
    WHERE NOT EXISTS (
      SELECT 1 FROM product_configs pc WHERE pc.product_id = p.id
    )
    """
  end

  def down do
    # Only delete configs that match the seeded defaults (no sizes, no colors, checkout disabled)
    execute """
    DELETE FROM product_configs
    WHERE has_sizes = false
      AND has_colors = false
      AND checkout_enabled = false
    """
  end
end
