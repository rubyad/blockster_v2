defmodule BlocksterV2.Repo.Migrations.FixProductJoinTablesIdDefault do
  use Ecto.Migration

  def change do
    # Add default UUID generation for product_category_assignments
    execute(
      "ALTER TABLE product_category_assignments ALTER COLUMN id SET DEFAULT gen_random_uuid()",
      "ALTER TABLE product_category_assignments ALTER COLUMN id DROP DEFAULT"
    )

    # Add default UUID generation for product_tag_assignments
    execute(
      "ALTER TABLE product_tag_assignments ALTER COLUMN id SET DEFAULT gen_random_uuid()",
      "ALTER TABLE product_tag_assignments ALTER COLUMN id DROP DEFAULT"
    )

    # Also add defaults for inserted_at and updated_at
    execute(
      "ALTER TABLE product_category_assignments ALTER COLUMN inserted_at SET DEFAULT now()",
      "ALTER TABLE product_category_assignments ALTER COLUMN inserted_at DROP DEFAULT"
    )

    execute(
      "ALTER TABLE product_category_assignments ALTER COLUMN updated_at SET DEFAULT now()",
      "ALTER TABLE product_category_assignments ALTER COLUMN updated_at DROP DEFAULT"
    )

    execute(
      "ALTER TABLE product_tag_assignments ALTER COLUMN inserted_at SET DEFAULT now()",
      "ALTER TABLE product_tag_assignments ALTER COLUMN inserted_at DROP DEFAULT"
    )

    execute(
      "ALTER TABLE product_tag_assignments ALTER COLUMN updated_at SET DEFAULT now()",
      "ALTER TABLE product_tag_assignments ALTER COLUMN updated_at DROP DEFAULT"
    )
  end
end
