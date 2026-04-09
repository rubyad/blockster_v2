defmodule BlocksterV2Web.DesignSystem.WhyEarnBuxBannerTest do
  use ExUnit.Case, async: true
  use Phoenix.Component
  import Phoenix.LiveViewTest
  import BlocksterV2Web.DesignSystem

  describe "why_earn_bux_banner/1" do
    test "renders the locked-in copy verbatim per D3" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.why_earn_bux_banner />
        """)

      assert html =~ "ds-why-earn-bux"
      assert html =~ "Why Earn BUX?"
      assert html =~ "Redeem BUX to enter sponsored airdrops."
      assert html =~ "bg-[#CAFC00]"
    end
  end
end
