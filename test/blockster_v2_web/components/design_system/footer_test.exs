defmodule BlocksterV2Web.DesignSystem.FooterTest do
  use ExUnit.Case, async: true
  use Phoenix.Component
  import Phoenix.LiveViewTest
  import BlocksterV2Web.DesignSystem

  describe "footer/1" do
    test "renders the dark footer with the mission line" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.footer />
        """)

      assert html =~ "ds-footer"
      assert html =~ "bg-[#0a0a0a]"
      assert html =~ "Where the chain meets the model."
    end

    test "renders the Miami Beach address per D2 / D22" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.footer />
        """)

      assert html =~ "1111 Lincoln Road, Suite 500"
      assert html =~ "Miami Beach, FL 33139"
    end

    test "renders the Media kit link in the bottom row" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.footer />
        """)

      assert html =~ "Media kit"
    end

    test "renders the dark wordmark with lime icon in the brand block" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.footer />
        """)

      assert html =~ "ds-logo--dark"
      assert html =~ "blockster-icon.png"
      assert html =~ ">BL</span>"
      assert html =~ ">CKSTER</span>"
    end

    test "renders the newsletter form with the locked subhead" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.footer />
        """)

      assert html =~ "The best of crypto × AI, every Friday. No spam, no shilling."
      assert html =~ ~s(name="email")
      assert html =~ "Subscribe"
    end

    test "renders Read and Earn link columns" do
      assigns = %{}

      html =
        rendered_to_string(~H"""
        <.footer />
        """)

      assert html =~ ">Read</div>"
      assert html =~ ">Earn</div>"
      assert html =~ ">Hubs</a>" or html =~ ">Hubs</.link>" or html =~ ">Hubs<"
      assert html =~ ">Pool<"
      assert html =~ ">Shop<"
    end
  end
end
