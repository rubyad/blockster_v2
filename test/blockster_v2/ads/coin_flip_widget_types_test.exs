defmodule BlocksterV2.Ads.CoinFlipWidgetTypesTest do
  use ExUnit.Case, async: true

  alias BlocksterV2.Ads.Banner

  @cf_live_types ~w(cf_sidebar_tile cf_inline_landscape cf_portrait)
  @cf_demo_types ~w(cf_sidebar_demo cf_inline_landscape_demo cf_portrait_demo)

  test "all 6 coin flip widget types are in Banner.valid_widget_types()" do
    valid = Banner.valid_widget_types()

    for type <- @cf_live_types ++ @cf_demo_types do
      assert type in valid, "expected #{type} in valid_widget_types"
    end
  end

  test "coin flip widget types pass changeset validation" do
    for type <- @cf_live_types ++ @cf_demo_types do
      changeset =
        Banner.changeset(%Banner{}, %{
          name: "test-#{type}",
          placement: "sidebar_left",
          widget_type: type
        })

      assert changeset.valid?, "changeset should be valid for widget_type=#{type}, errors: #{inspect(changeset.errors)}"
    end
  end

  test "unknown cf_ widget type fails validation" do
    changeset =
      Banner.changeset(%Banner{}, %{
        name: "test-bad",
        placement: "sidebar_left",
        widget_type: "cf_nonexistent"
      })

    refute changeset.valid?
    assert Keyword.has_key?(changeset.errors, :widget_type)
  end
end
