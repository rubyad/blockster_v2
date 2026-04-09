defmodule BlocksterV2Web.DesignSystem.StatCardTest do
  use ExUnit.Case, async: true
  use Phoenix.Component
  import Phoenix.LiveViewTest
  import BlocksterV2Web.DesignSystem

  describe "stat_card/1" do
    test "renders the label, value, and unit" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.stat_card label="BUX Balance" value="12,450" unit="BUX" sub="≈ $124.50" />
        """)

      assert html =~ "ds-stat-card"
      assert html =~ "BUX Balance"
      assert html =~ "12,450"
      assert html =~ "BUX"
      assert html =~ "≈ $124.50"
    end

    test "renders the value in mono tabular-nums" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.stat_card label="X" value="42" />
        """)

      assert html =~ "font-mono"
      assert html =~ "tabular-nums"
    end

    test "renders the icon slot when provided" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.stat_card label="X" value="1">
          <:icon>
            <span class="my-test-icon">★</span>
          </:icon>
        </.stat_card>
        """)

      assert html =~ "my-test-icon"
      assert html =~ "★"
    end

    test "renders the footer slot inside a top-bordered footer row" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.stat_card label="X" value="1">
          <:footer>
            <span>Today</span>
            <span class="my-test-amount">+ 245 BUX</span>
          </:footer>
        </.stat_card>
        """)

      assert html =~ "border-t border-neutral-100"
      assert html =~ "my-test-amount"
      assert html =~ "+ 245 BUX"
    end

    test "applies the icon_bg color to the icon square" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.stat_card label="X" value="1" icon_bg="#7D00FF">
          <:icon>
            <span>★</span>
          </:icon>
        </.stat_card>
        """)

      assert html =~ "background-color: #7D00FF"
    end
  end
end
