defmodule BlocksterV2Web.DesignSystem.LogoTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  import BlocksterV2Web.DesignSystem

  describe "logo/1" do
    test "renders the BLOCKSTER wordmark with the lime icon as the O" do
      html = render_component(&logo/1, %{size: "22px"})

      assert html =~ ~s(class="ds-logo)
      assert html =~ ">BL</span>"
      assert html =~ "blockster-icon.png"
      assert html =~ ~s(alt="o")
      assert html =~ ">CKSTER</span>"
    end

    test "applies the size as a CSS font-size" do
      html = render_component(&logo/1, %{size: "64px"})
      assert html =~ ~s(font-size: 64px)
    end

    test "uses the dark variant class when variant is dark" do
      html = render_component(&logo/1, %{variant: "dark"})
      assert html =~ "ds-logo--dark"
    end

    test "default variant is light (no dark class)" do
      html = render_component(&logo/1, %{})
      refute html =~ "ds-logo--dark"
    end

    test "passes through extra HTML attributes" do
      html = render_component(&logo/1, %{"data-testid": "logo-x"})
      assert html =~ ~s(data-testid="logo-x")
    end

    test "logo_icon_url/0 returns the canonical URL" do
      assert BlocksterV2Web.DesignSystem.logo_icon_url() ==
               "https://ik.imagekit.io/blockster/blockster-icon.png"
    end
  end
end
