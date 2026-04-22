defmodule BlocksterV2.Shop.Product do
  @moduledoc """
  Ecto schema for a shop product.

  ## BUX discount semantics (SHOP-04)

  `bux_max_discount` is a percentage in `[0, 100]`.

    * `0` (or `nil`) — BUX discount explicitly disabled for this product.
      The shop renderer treats this as "no discount allowed" under the
      hardened fallback (`SHOP_BUX_CAP_ENFORCED=true`, default in prod).
    * `1..100` — BUX discount enabled, capped at the given percentage.

  There is no separate `bux_enabled` field; the cap itself is the toggle.
  The changeset validates the range but accepts `0` as a valid "disabled"
  state. Enforcement of the 0-⇒-no-discount semantic lives in
  `BlocksterV2Web.ShopLive.Show` and `BlocksterV2.Shop.BuxDiscountConfig`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "products" do
    field :title, :string
    field :body_html, :string
    field :vendor, :string
    field :product_type, :string
    field :handle, :string
    field :status, :string, default: "draft"
    field :tags, {:array, :string}, default: []

    # Token discount settings (percentage 0-100). See moduledoc for semantics.
    field :bux_max_discount, :integer, default: 0
    field :hub_token_max_discount, :integer, default: 0

    # Artist and collection info
    field :artist, :string  # Legacy text field - kept for backwards compatibility
    field :collection_name, :string

    # Artist association (new)
    belongs_to :artist_record, BlocksterV2.Shop.Artist, foreign_key: :artist_id, type: :id

    # Inventory tracking (optional - for limited edition items)
    field :max_inventory, :integer
    field :sold_count, :integer, default: 0

    # Publishing
    field :published_at, :utc_datetime
    field :published_scope, :string, default: "web"
    field :template_suffix, :string

    # SEO
    field :seo_title, :string
    field :seo_description, :string

    # Associations
    belongs_to :hub, BlocksterV2.Blog.Hub, type: :id
    has_many :variants, BlocksterV2.Shop.ProductVariant, on_delete: :delete_all
    has_many :images, BlocksterV2.Shop.ProductImage, on_delete: :delete_all

    many_to_many :categories, BlocksterV2.Shop.ProductCategory,
      join_through: "product_category_assignments",
      join_keys: [product_id: :id, category_id: :id],
      on_replace: :delete

    many_to_many :product_tags, BlocksterV2.Shop.ProductTag,
      join_through: "product_tag_assignments",
      join_keys: [product_id: :id, tag_id: :id],
      on_replace: :delete

    has_one :product_config, BlocksterV2.Shop.ProductConfig

    timestamps()
  end

  @required_fields [:title, :handle]
  @optional_fields [
    :body_html,
    :vendor,
    :product_type,
    :status,
    :tags,
    :hub_id,
    :bux_max_discount,
    :hub_token_max_discount,
    :artist,
    :artist_id,
    :collection_name,
    :max_inventory,
    :sold_count,
    :published_at,
    :published_scope,
    :template_suffix,
    :seo_title,
    :seo_description
  ]

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:status, ["draft", "active", "archived"])
    |> validate_number(:bux_max_discount, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> validate_number(:hub_token_max_discount, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
    |> generate_handle()
    |> unique_constraint(:handle)
  end

  defp generate_handle(changeset) do
    case {get_field(changeset, :handle), get_field(changeset, :title)} do
      {nil, title} when is_binary(title) ->
        handle =
          title
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9\s-]/, "")
          |> String.replace(~r/\s+/, "-")
          |> String.trim("-")

        put_change(changeset, :handle, handle)

      _ ->
        changeset
    end
  end
end
