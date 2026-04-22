defmodule BlocksterV2.Shop.ProductTest do
  @moduledoc """
  Changeset tests for `BlocksterV2.Shop.Product` — specifically the
  SHOP-04 BUX discount cap semantics.

  Per the moduledoc: `bux_max_discount` is a percentage in `[0, 100]`,
  where `0` means "BUX discount explicitly disabled for this product".
  There is no `bux_enabled` field on the schema — the cap itself is the
  toggle.

  The checklist item "changeset rejects `bux_enabled: true` +
  `bux_max_discount: 0`" is not directly enforceable at the schema layer
  because `bux_enabled` does not exist. These tests instead pin down:

    * the schema-level validation accepts `0` as a valid "disabled" value
    * the schema-level validation rejects out-of-range (<0 or >100)
    * the render-layer fallback in `BlocksterV2.Shop.BuxDiscountConfig`
      is what turns `0` into "no discount allowed" — covered in
      `show_test.exs`.
  """

  use BlocksterV2.DataCase, async: true

  alias BlocksterV2.Shop.Product

  defp base_attrs(overrides \\ %{}) do
    Map.merge(
      %{
        "title" => "Sample product",
        "handle" => "sample-product-#{System.unique_integer([:positive])}",
        "status" => "active",
        "vendor" => "Sample"
      },
      overrides
    )
  end

  describe "changeset/2 — bux_max_discount range" do
    test "accepts 0 (BUX discount disabled, valid state)" do
      changeset = Product.changeset(%Product{}, base_attrs(%{"bux_max_discount" => 0}))
      assert changeset.valid?
    end

    test "accepts nil (defaults to 0 at schema level)" do
      changeset = Product.changeset(%Product{}, base_attrs())
      assert changeset.valid?
    end

    test "accepts 1 through 100 (valid cap)" do
      for pct <- [1, 25, 50, 75, 100] do
        changeset = Product.changeset(%Product{}, base_attrs(%{"bux_max_discount" => pct}))
        assert changeset.valid?, "expected #{pct} to be valid"
      end
    end

    test "rejects negative values" do
      changeset = Product.changeset(%Product{}, base_attrs(%{"bux_max_discount" => -1}))
      refute changeset.valid?

      assert %{bux_max_discount: [_msg]} = errors_on(changeset)
    end

    test "rejects values greater than 100" do
      changeset = Product.changeset(%Product{}, base_attrs(%{"bux_max_discount" => 101}))
      refute changeset.valid?

      assert %{bux_max_discount: [_msg]} = errors_on(changeset)
    end
  end
end
