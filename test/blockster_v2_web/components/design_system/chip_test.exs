defmodule BlocksterV2Web.DesignSystem.ChipTest do
  use ExUnit.Case, async: true
  use Phoenix.Component
  import Phoenix.LiveViewTest
  import BlocksterV2Web.DesignSystem

  describe "chip/1" do
    test "renders default variant with white background and gray border" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.chip>DeFi</.chip>
        """)

      assert html =~ "ds-chip"
      assert html =~ "DeFi"
      assert html =~ "bg-white"
      assert html =~ "border-neutral-200"
      assert html =~ "text-neutral-500"
    end

    test "renders active variant with black background and white text" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.chip variant="active">All</.chip>
        """)

      assert html =~ "All"
      assert html =~ "bg-neutral-900"
      assert html =~ "text-white"
      refute html =~ "bg-white border border-neutral-200"
    end

    test "passes phx-click and phx-value-* attrs through" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.chip phx-click="filter" phx-value-key="defi">DeFi</.chip>
        """)

      assert html =~ ~s(phx-click="filter")
      assert html =~ ~s(phx-value-key="defi")
    end
  end
end
