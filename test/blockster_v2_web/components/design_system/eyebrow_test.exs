defmodule BlocksterV2Web.DesignSystem.EyebrowTest do
  use ExUnit.Case, async: true
  use Phoenix.Component
  import Phoenix.LiveViewTest
  import BlocksterV2Web.DesignSystem

  describe "eyebrow/1" do
    test "renders the inner block with eyebrow class" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.eyebrow>Most read this week</.eyebrow>
        """)

      assert html =~ "ds-eyebrow"
      assert html =~ "Most read this week"
      assert html =~ "uppercase"
      assert html =~ "tracking-[0.16em]"
    end

    test "applies extra classes via the class attr" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.eyebrow class="text-amber-700">One thing left</.eyebrow>
        """)

      assert html =~ "text-amber-700"
      assert html =~ "One thing left"
    end
  end
end
